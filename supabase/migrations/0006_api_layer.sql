-- Helper: Advisory Lock to serialize writes per node
CREATE OR REPLACE FUNCTION _lock_node(p_node uuid)
    RETURNS void
    LANGUAGE sql
    SET search_path = public
    AS $$
    SELECT
        pg_advisory_xact_lock(hashtext(p_node::text));
$$;

-- 1. Create Group
CREATE OR REPLACE FUNCTION rpc_create_group(p_parent_id uuid, p_label text)
    RETURNS uuid
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
DECLARE
    ctx graph_context;
    v_new uuid;
BEGIN
    ctx := assert_authenticated();
    PERFORM
        _lock_node(p_parent_id);
    -- Lock Parent
    PERFORM
        assert_dominance(ctx, p_parent_id);
    PERFORM
        assert_permission(ctx, 'NODE_CREATE');
    INSERT INTO dag_node(type, label)
        VALUES ('group', p_label)
    RETURNING
        id INTO v_new;
    PERFORM
        _algo_init_node(v_new);
    INSERT INTO dag_edge(parent_id, child_id)
        VALUES (p_parent_id, v_new);
    PERFORM
        _algo_attach_subtree(p_parent_id, v_new);
    RETURN v_new;
END;
$$;

-- 2. Create Role
CREATE OR REPLACE FUNCTION rpc_create_role(p_parent_id uuid, p_label text, p_bits bit(256))
    RETURNS uuid
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
DECLARE
    ctx graph_context;
    v_new uuid;
BEGIN
    ctx := assert_authenticated();
    PERFORM
        _lock_node(p_parent_id);
    -- Lock Parent
    PERFORM
        assert_dominance(ctx, p_parent_id);
    PERFORM
        assert_permission(ctx, 'NODE_CREATE');
    PERFORM
        assert_permission(ctx, 'ROLE_MANAGE');
    -- Extra check for creating permissions
    PERFORM
        assert_no_escalation(ctx, p_bits);
    INSERT INTO dag_node(type, label, permission_bits)
        VALUES ('role', p_label, p_bits)
    RETURNING
        id INTO v_new;
    PERFORM
        _algo_init_node(v_new);
    INSERT INTO dag_edge(parent_id, child_id)
        VALUES (p_parent_id, v_new);
    PERFORM
        _algo_attach_subtree(p_parent_id, v_new);
    RETURN v_new;
END;
$$;

-- 3. Link Nodes
CREATE OR REPLACE FUNCTION rpc_link_node(p_parent uuid, p_child uuid)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
DECLARE
    ctx graph_context;
BEGIN
    ctx := assert_authenticated();
    -- Lock both to prevent cycle race conditions
    PERFORM
        _lock_node(p_parent);
    PERFORM
        _lock_node(p_child);
    PERFORM
        assert_dominance(ctx, p_parent);
    PERFORM
        assert_permission(ctx, 'EDGE_LINK');
    IF _algo_detect_cycle(p_parent, p_child) THEN
        RAISE EXCEPTION 'ERR_CYCLE_DETECTED';
    END IF;
    INSERT INTO dag_edge(parent_id, child_id)
        VALUES (p_parent, p_child);
    PERFORM
        _algo_attach_subtree(p_parent, p_child);
END;
$$;

-- 4. Unlink Nodes (Prevent Orphans)
CREATE OR REPLACE FUNCTION rpc_unlink_node(p_parent uuid, p_child uuid)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
DECLARE
    ctx graph_context;
BEGIN
    ctx := assert_authenticated();
    PERFORM
        _lock_node(p_parent);
    PERFORM
        _lock_node(p_child);
    PERFORM
        assert_dominance(ctx, p_parent);
    PERFORM
        assert_permission(ctx, 'EDGE_UNLINK');
    -- Orphan Check
    IF (
        SELECT
            count(*)
        FROM
            dag_edge
        WHERE
            child_id = p_child) <= 1 THEN
        RAISE EXCEPTION 'ERR_WOULD_ORPHAN: Node must have at least one parent';
    END IF;
    PERFORM
        _algo_detach_subtree(p_parent, p_child);
    DELETE FROM dag_edge
    WHERE parent_id = p_parent
        AND child_id = p_child;
END;
$$;

-- 5. Delete Node (Leaf Only)
CREATE OR REPLACE FUNCTION rpc_delete_node(p_target_id uuid)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
DECLARE
    ctx graph_context;
BEGIN
    ctx := assert_authenticated();
    PERFORM
        _lock_node(p_target_id);
    PERFORM
        assert_dominance(ctx, p_target_id);
    PERFORM
        assert_permission(ctx, 'NODE_DELETE');
    -- Leaf Check: Does it have children?
    IF EXISTS (
        SELECT
            1
        FROM
            dag_edge
        WHERE
            parent_id = p_target_id) THEN
    RAISE EXCEPTION 'ERR_NOT_LEAF: Cannot delete node with children';
END IF;
    -- NOTE: 'ON DELETE RESTRICT' in resources will automatically prevent deletion
    -- if this node owns invoices, etc. No need for manual check here.
    DELETE FROM dag_node
    WHERE id = p_target_id;
    -- Edges cascade automatically
    -- Closure cascades automatically
END;
$$;

-- 6. Invite User (with optional expiry)
CREATE OR REPLACE FUNCTION rpc_invite_user(p_parent_id uuid, p_label text, p_expires_in interval DEFAULT NULL)
    RETURNS text
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
DECLARE
    ctx graph_context;
    v_raw_token text := gen_random_uuid()::text;
    v_new uuid;
    v_expires timestamptz;
BEGIN
    ctx := assert_authenticated();
    PERFORM
        _lock_node(p_parent_id);
    PERFORM
        assert_dominance(ctx, p_parent_id);
    PERFORM
        assert_permission(ctx, 'NODE_CREATE');
    v_expires := now() + COALESCE(p_expires_in, interval '24 hours');
    INSERT INTO dag_node(type, label, invite_hash, invite_expires)
        VALUES ('user', p_label, crypt(v_raw_token, gen_salt('bf')), v_expires)
    RETURNING
        id INTO v_new;
    PERFORM
        _algo_init_node(v_new);
    INSERT INTO dag_edge(parent_id, child_id)
        VALUES (p_parent_id, v_new);
    PERFORM
        _algo_attach_subtree(p_parent_id, v_new);
    RETURN v_raw_token;
END;
$$;

-- 7. Claim Invite
CREATE OR REPLACE FUNCTION rpc_claim_invite(p_token text)
    RETURNS boolean
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
DECLARE
    v_node_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'ERR_NOT_AUTHENTICATED';
    END IF;
    IF EXISTS (
        SELECT
            1
        FROM
            dag_node
        WHERE
            auth_user_id = auth.uid()) THEN
    RAISE EXCEPTION 'ERR_ALREADY_CLAIMED';
END IF;
    SELECT
        id INTO v_node_id
    FROM
        dag_node
    WHERE
        type = 'user'
        AND invite_expires > now()
        AND invite_hash = crypt(p_token, invite_hash);
    IF v_node_id IS NULL THEN
        RAISE EXCEPTION 'ERR_INVALID_TOKEN';
    END IF;
    UPDATE
        dag_node
    SET
        auth_user_id = auth.uid(),
        invite_hash = NULL,
        invite_expires = NULL,
        updated_at = now()
    WHERE
        id = v_node_id;
    RETURN TRUE;
END;
$$;

