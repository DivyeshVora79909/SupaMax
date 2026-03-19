CREATE OR REPLACE FUNCTION get_perm_id(p_slug text)
RETURNS int
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
    SELECT bit_index FROM permission_manifest WHERE slug = p_slug;
$$;

CREATE OR REPLACE FUNCTION _auth_context(
    OUT node_id uuid,
    OUT perms   bit(256)
)
RETURNS record
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        n.id,
        COALESCE(bit_or(r.permission_bits), B'0'::bit(256))
    FROM  dag_node n
    LEFT  JOIN dag_edge e ON e.child_id  = n.id
    LEFT  JOIN dag_node r ON r.id        = e.parent_id
                          AND r.type     = 'role'
    WHERE n.auth_user_id = auth.uid()
    GROUP BY n.id;
$$;

CREATE OR REPLACE FUNCTION has_perm(p_slug text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT get_bit((_auth_context()).perms, get_perm_id(p_slug)) = 1;
$$;

CREATE OR REPLACE FUNCTION _i_dominate(p_target uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM  closure_dominance
        WHERE ancestor_id   = (_auth_context()).node_id
          AND descendant_id = p_target
    );
$$;

CREATE OR REPLACE FUNCTION _i_strictly_dominate(p_target uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM  closure_dominance
        WHERE ancestor_id   = (_auth_context()).node_id
          AND descendant_id = p_target
          AND depth         > 0
    );
$$;

CREATE OR REPLACE FUNCTION _is_nonuser_parent(p_target uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM  dag_edge e
        JOIN  dag_node p ON p.id = e.parent_id
        WHERE e.child_id = (_auth_context()).node_id
          AND p.id       = p_target
          AND p.type     IN ('group', 'role')
    );
$$;