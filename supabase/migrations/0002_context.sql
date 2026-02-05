-- 1. Helper: Get Current Node ID from Auth
CREATE OR REPLACE FUNCTION current_node_id()
    RETURNS uuid
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
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
    STABLE
    AS $$
    SELECT
        bit_index
    FROM
        permission_manifest
    WHERE
        slug = p_slug;
$$;

-- 3. Helper: Calculate Cumulative Permissions (Recursive Math)
CREATE OR REPLACE FUNCTION _calc_effective_permissions(p_node uuid)
    RETURNS bit (
        256)
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    AS $$
    SELECT
        COALESCE(bit_or(p.permission_bits), B'0'::bit(256))
    FROM
        closure_dominance cd
        JOIN dag_node p ON p.id = cd.ancestor_id
    WHERE
        cd.descendant_id = p_node
        AND p.type = 'role';
$$;

-- 4. The Context Engine
-- Defines the mathematical set of properties for the current actor
CREATE TYPE graph_context AS (
    node_id uuid, -- Who am I?
    perms bit(256), -- What can I do?
    parent_ids uuid[], -- My immediate environment (Siblings/Membership)
    ancestor_ids uuid[] -- My Line of Sight (Upwards)
);

CREATE OR REPLACE FUNCTION get_graph_context()
    RETURNS graph_context
    LANGUAGE plpgsql
    STABLE -- MEMOIZED: Runs once per query
    SECURITY DEFINER
    AS $$
DECLARE
    v_node_id uuid;
    v_perms bit(256);
    v_parents uuid[];
    v_ancestors uuid[];
BEGIN
    v_node_id := current_node_id();
    IF v_node_id IS NULL THEN
        RETURN (NULL,
            B'0'::bit(256),
            ARRAY[]::uuid[],
            ARRAY[]::uuid[]);
    END IF;
    -- Parallel-capable calculations
    v_perms := _calc_effective_permissions(v_node_id);
    -- Fetch Direct Parents (Fast Join)
    SELECT
        COALESCE(array_agg(parent_id), ARRAY[]::uuid[]) INTO v_parents
    FROM
        dag_edge
    WHERE
        child_id = v_node_id;
    -- Fetch Ancestors (Fast Index Scan)
    SELECT
        COALESCE(array_agg(ancestor_id), ARRAY[]::uuid[]) INTO v_ancestors
    FROM
        closure_dominance
    WHERE
        descendant_id = v_node_id;
    RETURN (v_node_id,
        v_perms,
        v_parents,
        v_ancestors);
END;
$$;

