-- 1. Helper: Get Current Node ID from Auth
CREATE OR REPLACE FUNCTION current_node_id()
    RETURNS uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public
    AS $$
    SELECT
        id
    FROM
        dag_node
    WHERE
        auth_user_id = auth.uid()
    LIMIT 1;
$$;

-- 2. Helper: Map Permission Slug to Integer
CREATE OR REPLACE FUNCTION get_perm_id(p_slug text)
    RETURNS int
    LANGUAGE sql
    IMMUTABLE
    SET search_path = public
    AS $$
    SELECT
        bit_index
    FROM
        permission_manifest
    WHERE
        slug = p_slug;
$$;

-- 3. Helper: Calculate Effective Permissions (Depth-1 Only)
CREATE OR REPLACE FUNCTION _calc_effective_permissions(p_node uuid)
    RETURNS bit (
        256)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public
    AS $$
    SELECT
        COALESCE(bit_or(p.permission_bits), B'0'::bit(256))
    FROM
        dag_edge e
        JOIN dag_node p ON e.parent_id = p.id
    WHERE
        e.child_id = p_node
        AND p.type = 'role';
$$;

-- 4. The Context Engine
CREATE TYPE graph_context AS (
    node_id uuid,
    perms bit(256),
    membership_ids uuid[]
);

CREATE OR REPLACE FUNCTION get_graph_context()
    RETURNS graph_context
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
    SET search_path = public
    AS $$
DECLARE
    v_node_id uuid;
    v_perms bit(256);
    v_membership uuid[];
BEGIN
    v_node_id := current_node_id();
    IF v_node_id IS NULL THEN
        RETURN (NULL::uuid,
            B'0'::bit(256),
            ARRAY[]::uuid[]);
    END IF;
    v_perms := _calc_effective_permissions(v_node_id);
    SELECT
        COALESCE(array_agg(parent_id), ARRAY[]::uuid[]) INTO v_membership
    FROM
        dag_edge e
        JOIN dag_node p ON e.parent_id = p.id
    WHERE
        e.child_id = v_node_id
        AND p.type IN ('group', 'role');
    RETURN (v_node_id,
        v_perms,
        v_membership);
END;
$$;

-- 5. Helper: Storage Garbage Collector
CREATE OR REPLACE FUNCTION _trigger_link_storage()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
DECLARE
    v_col text := TG_ARGV[0];
    v_old_path text;
    v_new_path text;
BEGIN
    EXECUTE format('SELECT ($1).%I', v_col)
    USING OLD INTO v_old_path;
    IF TG_OP = 'UPDATE' THEN
        EXECUTE format('SELECT ($1).%I', v_col)
        USING NEW INTO v_new_path;
    END IF;
        IF v_old_path IS NOT NULL AND (TG_OP = 'DELETE' OR v_old_path IS DISTINCT FROM v_new_path) THEN
            DELETE FROM storage.objects
            WHERE bucket_id = 'resources'
                AND name = v_old_path;
        END IF;
        RETURN NULL;
END;
$$;

