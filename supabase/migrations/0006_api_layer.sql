-- 1. Create Group
CREATE OR REPLACE FUNCTION rpc_create_group(p_parent_id uuid, p_label text)
    RETURNS uuid
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
DECLARE
    ctx graph_context;
    v_new uuid;
BEGIN
    ctx := assert_authenticated();
    PERFORM
        assert_dominance(ctx, p_parent_id);
    PERFORM
        assert_permission(ctx, 'GRAPH_EDIT');
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
    AS $$
DECLARE
    ctx graph_context;
    v_new uuid;
BEGIN
    ctx := assert_authenticated();
    PERFORM
        assert_dominance(ctx, p_parent_id);
    PERFORM
        assert_permission(ctx, 'GRAPH_EDIT');
    PERFORM
        assert_no_escalation(ctx, p_bits);
    -- Specific assertion reuse
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
    AS $$
DECLARE
    ctx graph_context;
BEGIN
    ctx := assert_authenticated();
    PERFORM
        assert_dominance(ctx, p_parent);
    PERFORM
        assert_permission(ctx, 'GRAPH_EDIT');
    IF _algo_detect_cycle(p_parent, p_child) THEN
        RAISE EXCEPTION 'ERR_CYCLE_DETECTED';
    END IF;
    INSERT INTO dag_edge(parent_id, child_id)
        VALUES (p_parent, p_child);
    PERFORM
        _algo_attach_subtree(p_parent, p_child);
END;
$$;

-- 4. Unlink Nodes
CREATE OR REPLACE FUNCTION rpc_unlink_node(p_parent uuid, p_child uuid)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
DECLARE
    ctx graph_context;
BEGIN
    ctx := assert_authenticated();
    PERFORM
        assert_dominance(ctx, p_parent);
    PERFORM
        assert_permission(ctx, 'GRAPH_EDIT');
    -- Orphan Check (Inline logic is fine for small checks)
    IF (
        SELECT
            count(*)
        FROM
            dag_edge
        WHERE
            child_id = p_child) <= 1 THEN
        RAISE EXCEPTION 'ERR_WOULD_ORPHAN';
    END IF;
    PERFORM
        _algo_detach_subtree(p_parent, p_child);
    DELETE FROM dag_edge
    WHERE parent_id = p_parent
        AND child_id = p_child;
END;
$$;

-- 5. Invite User (Helper)
CREATE OR REPLACE FUNCTION rpc_invite_user(p_parent_id uuid, p_label text)
    RETURNS text
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
DECLARE
    ctx graph_context;
    v_raw_token text := gen_random_uuid()::text;
    v_new uuid;
BEGIN
    ctx := assert_authenticated();
    PERFORM
        assert_dominance(ctx, p_parent_id);
    PERFORM
        assert_permission(ctx, 'GRAPH_EDIT');
    INSERT INTO dag_node(type, label, invite_hash, invite_expires)
        VALUES ('user', p_label, crypt(v_raw_token, gen_salt('bf')), now() + interval '24 hours')
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

-- 6. Claim Invite (Public Endpoint)
CREATE OR REPLACE FUNCTION rpc_claim_invite(p_token text)
    RETURNS boolean
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
DECLARE
    v_node_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'ERR_NOT_AUTHENTICATED';
    END IF;
    -- Check if user already has a node
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

