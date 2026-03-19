CREATE OR REPLACE FUNCTION _lock_node(p_node uuid)
RETURNS void
LANGUAGE sql
SET search_path = public
AS $$
    SELECT pg_advisory_xact_lock(
        ('x' || substr(replace(p_node::text, '-', ''), 1, 16))::bit(64)::bigint
    );
$$;

CREATE OR REPLACE FUNCTION _algo_init_node(p_node uuid)
RETURNS void
LANGUAGE sql
SET search_path = public
AS $$
    INSERT INTO closure_dominance(ancestor_id, descendant_id, depth)
        VALUES (p_node, p_node, 0)
    ON CONFLICT DO NOTHING;
$$;

CREATE OR REPLACE FUNCTION _algo_detect_cycle(p_parent uuid, p_child uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM  closure_dominance
        WHERE ancestor_id   = p_child
          AND descendant_id = p_parent
    );
$$;

CREATE OR REPLACE FUNCTION _algo_attach_subtree(p_parent uuid, p_child uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO closure_dominance(ancestor_id, descendant_id, depth)
    SELECT
        a.ancestor_id,
        d.descendant_id,
        a.depth + d.depth + 1
    FROM  closure_dominance a
    CROSS JOIN closure_dominance d
    WHERE a.descendant_id = p_parent
      AND d.ancestor_id   = p_child
    ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION _algo_detach_subtree(p_parent uuid, p_child uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    rec_ancestor  record;
    v_descendants uuid[];
    v_reachable   uuid[];
BEGIN
    SELECT array_agg(descendant_id)
    INTO   v_descendants
    FROM   closure_dominance
    WHERE  ancestor_id = p_child;

    IF v_descendants IS NULL THEN RETURN; END IF;

    FOR rec_ancestor IN
        SELECT ancestor_id
        FROM   closure_dominance
        WHERE  descendant_id = p_parent
    LOOP
        WITH RECURSIVE reach(n) AS (
            SELECT child_id
            FROM   dag_edge
            WHERE  parent_id = rec_ancestor.ancestor_id
               AND NOT (parent_id = p_parent AND child_id = p_child)
            UNION
            SELECT e.child_id
            FROM   dag_edge e
            JOIN   reach    r ON e.parent_id = r.n
            WHERE  NOT (e.parent_id = p_parent AND e.child_id = p_child)
        )
        SELECT array_agg(n)
        INTO   v_reachable
        FROM   reach
        WHERE  n = ANY(v_descendants);

        IF v_reachable IS NULL THEN
            DELETE FROM closure_dominance
            WHERE  ancestor_id   = rec_ancestor.ancestor_id
              AND  descendant_id = ANY(v_descendants)
              AND  ancestor_id  <> descendant_id;
        ELSE
            DELETE FROM closure_dominance
            WHERE  ancestor_id   = rec_ancestor.ancestor_id
              AND  descendant_id = ANY(v_descendants)
              AND  descendant_id <> ALL(v_reachable)
              AND  ancestor_id  <> descendant_id;
        END IF;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION _calc_effective_permissions(p_node uuid)
RETURNS bit(256)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(bit_or(r.permission_bits), B'0'::bit(256))
    FROM  dag_edge e
    JOIN  dag_node r ON r.id   = e.parent_id
                    AND r.type = 'role'
    WHERE e.child_id = p_node;
$$;

CREATE OR REPLACE FUNCTION _algo_check_escalation(p_parent uuid, p_bits bit(256))
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF (p_bits & ~_calc_effective_permissions(p_parent)) <> B'0'::bit(256) THEN
        RAISE EXCEPTION 'ERR_ESCALATION: You cannot assign permissions the parent node does not possess.';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION insert_node(
    p_parent_id uuid,
    p_type      text,
    p_label     text,
    p_bits      bit(256) DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_new_id      uuid;
    v_invite_hash text := NULL;
    v_raw_token   text := NULL;
BEGIN
    PERFORM _lock_node(p_parent_id);

    IF NOT has_perm('NODE_CREATE') THEN
        RAISE EXCEPTION 'ERR_PERM_DENIED: Missing NODE_CREATE';
    END IF;
    IF NOT _i_dominate(p_parent_id) THEN
        RAISE EXCEPTION 'ERR_ACCESS_DENIED: Cannot attach to a node you do not dominate';
    END IF;

    IF p_type = 'role' THEN
        IF NOT has_perm('ROLE_MANAGE') THEN
            RAISE EXCEPTION 'ERR_PERM_DENIED: Missing ROLE_MANAGE';
        END IF;
        PERFORM _algo_check_escalation(p_parent_id, p_bits);

    ELSIF p_type = 'user' THEN
        v_raw_token   := gen_random_uuid()::text;
        v_invite_hash := crypt(v_raw_token, gen_salt('bf'));
    END IF;

    INSERT INTO dag_node(type, label, permission_bits, invite_hash, invite_expires)
        VALUES (
            p_type,
            p_label,
            p_bits,
            v_invite_hash,
            CASE WHEN p_type = 'user' THEN now() + interval '24 hours' ELSE NULL END
        )
    RETURNING id INTO v_new_id;

    PERFORM _algo_init_node(v_new_id);
    INSERT INTO dag_edge(parent_id, child_id) VALUES (p_parent_id, v_new_id);
    PERFORM _algo_attach_subtree(p_parent_id, v_new_id);

    RETURN jsonb_build_object('id', v_new_id, 'invite_token', v_raw_token);
END;
$$;

CREATE OR REPLACE FUNCTION update_node(
    p_node_id uuid,
    p_label   text,
    p_bits    bit(256) DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_type text;
BEGIN
    PERFORM _lock_node(p_node_id);

    IF NOT _i_strictly_dominate(p_node_id) THEN
        RAISE EXCEPTION 'ERR_ACCESS_DENIED: You can only update nodes strictly below you';
    END IF;

    SELECT type INTO v_type FROM dag_node WHERE id = p_node_id;

    IF p_bits IS NOT NULL AND v_type = 'role' THEN
        IF NOT has_perm('ROLE_MANAGE') THEN
            RAISE EXCEPTION 'ERR_PERM_DENIED: Missing ROLE_MANAGE';
        END IF;
        PERFORM _algo_check_escalation(parent_id, p_bits)
            FROM dag_edge WHERE child_id = p_node_id;
    END IF;

    UPDATE dag_node
    SET
        label           = COALESCE(p_label, label),
        permission_bits = CASE
                            WHEN v_type = 'role' THEN COALESCE(p_bits, permission_bits)
                            ELSE permission_bits
                          END,
        updated_at      = now()
    WHERE id = p_node_id;
END;
$$;

CREATE OR REPLACE FUNCTION insert_edge(p_parent_id uuid, p_child_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_child_type text;
    v_child_bits bit(256);
BEGIN
    PERFORM _lock_node(p_parent_id);
    PERFORM _lock_node(p_child_id);

    IF NOT has_perm('EDGE_LINK') THEN
        RAISE EXCEPTION 'ERR_PERM_DENIED: Missing EDGE_LINK';
    END IF;
    IF NOT _i_dominate(p_parent_id) OR NOT _i_dominate(p_child_id) THEN
        RAISE EXCEPTION 'ERR_ACCESS_DENIED: Must dominate both nodes';
    END IF;
    IF _algo_detect_cycle(p_parent_id, p_child_id) THEN
        RAISE EXCEPTION 'ERR_CYCLE_DETECTED';
    END IF;

    SELECT type, permission_bits
    INTO   v_child_type, v_child_bits
    FROM   dag_node WHERE id = p_child_id;

    IF v_child_type = 'role' THEN
        PERFORM _algo_check_escalation(p_parent_id, v_child_bits);
    END IF;

    INSERT INTO dag_edge(parent_id, child_id) VALUES (p_parent_id, p_child_id);
    PERFORM _algo_attach_subtree(p_parent_id, p_child_id);
END;
$$;

CREATE OR REPLACE FUNCTION delete_edge(p_parent_id uuid, p_child_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM _lock_node(p_parent_id);
    PERFORM _lock_node(p_child_id);

    IF NOT has_perm('EDGE_UNLINK') THEN
        RAISE EXCEPTION 'ERR_PERM_DENIED: Missing EDGE_UNLINK';
    END IF;
    IF NOT _i_dominate(p_parent_id) OR NOT _i_dominate(p_child_id) THEN
        RAISE EXCEPTION 'ERR_ACCESS_DENIED: Must dominate both nodes';
    END IF;

    PERFORM _algo_detach_subtree(p_parent_id, p_child_id);
    DELETE FROM dag_edge WHERE parent_id = p_parent_id AND child_id = p_child_id;

    IF NOT EXISTS (SELECT 1 FROM dag_edge WHERE child_id = p_child_id) THEN
        DELETE FROM dag_node WHERE id = p_child_id;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION delete_node(p_target_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM _lock_node(p_target_id);

    IF NOT has_perm('NODE_DELETE') THEN
        RAISE EXCEPTION 'ERR_PERM_DENIED: Missing NODE_DELETE';
    END IF;
    IF NOT _i_strictly_dominate(p_target_id) THEN
        RAISE EXCEPTION 'ERR_ACCESS_DENIED: Must dominate node to delete it';
    END IF;
    IF EXISTS (SELECT 1 FROM dag_edge WHERE parent_id = p_target_id) THEN
        RAISE EXCEPTION 'ERR_NOT_LEAF: Cannot delete a node that has children. Unlink children first.';
    END IF;

    DELETE FROM dag_node WHERE id = p_target_id;
END;
$$;

CREATE OR REPLACE FUNCTION claim_invite(p_token text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_node_id uuid;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'ERR_NOT_AUTHENTICATED';
    END IF;
    IF EXISTS (SELECT 1 FROM dag_node WHERE auth_user_id = auth.uid()) THEN
        RAISE EXCEPTION 'ERR_ALREADY_CLAIMED';
    END IF;

    SELECT id INTO v_node_id
    FROM   dag_node
    WHERE  type           = 'user'
      AND  invite_expires > now()
      AND  invite_hash    = crypt(p_token, invite_hash);

    IF v_node_id IS NULL THEN
        RAISE EXCEPTION 'ERR_INVALID_TOKEN';
    END IF;

    UPDATE dag_node
    SET
        auth_user_id   = auth.uid(),
        invite_hash    = NULL,
        invite_expires = NULL,
        updated_at     = now()
    WHERE id = v_node_id;

    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION leave_node()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_node_id uuid;
BEGIN
    v_node_id := (_auth_context()).node_id;
    IF v_node_id IS NULL THEN RETURN; END IF;

    UPDATE dag_node
    SET
        auth_user_id   = NULL,
        invite_hash    = crypt(gen_random_uuid()::text, gen_salt('bf')),
        invite_expires = NULL,
        updated_at     = now()
    WHERE id = v_node_id;
END;
$$;

CREATE OR REPLACE FUNCTION delete_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    v_uid uuid;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'ERR_NOT_AUTHENTICATED';
    END IF;
    PERFORM leave_node();
    DELETE FROM auth.users WHERE id = v_uid;
END;
$$;