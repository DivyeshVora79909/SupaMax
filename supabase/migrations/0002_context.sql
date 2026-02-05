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
    IMMUTABLE
    AS $$
    SELECT
        bit_index
    FROM
        permission_manifest
    WHERE
        slug = p_slug;
$$;

-- 3. Helper: Calculate Effective Permissions (Depth-1 Only)
-- Change: No recursion. Only sum bits from direct parents that are roles.
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
        dag_edge e
        JOIN dag_node p ON e.parent_id = p.id
    WHERE
        e.child_id = p_node
        AND p.type = 'role';
        -- Strict Depth-1 Inheritance
$$;

-- 4. The Context Engine: Optimized for Membership RLS
CREATE TYPE graph_context AS (
    node_id uuid, -- Who am I?
    perms bit(256), -- What can I do?
    membership_ids uuid[] -- Direct parents (Groups/Roles) for Siblings/Resource access
);

CREATE OR REPLACE FUNCTION get_graph_context()
    RETURNS graph_context
    LANGUAGE plpgsql
    STABLE
    SECURITY DEFINER
    AS $$
DECLARE
    v_node_id uuid;
    v_perms bit(256);
    v_membership uuid[];
BEGIN
    v_node_id := current_node_id();
    IF v_node_id IS NULL THEN
        RETURN (NULL,
            B'0'::bit(256),
            ARRAY[]::uuid[]);
    END IF;
    -- 1. Calculate Permissions (Depth-1)
    v_perms := _calc_effective_permissions(v_node_id);
    -- 2. Fetch Membership (Direct parents that are Groups or Roles)
    -- This drives the "Membership" RLS check (Siblings & Resources)
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

