ALTER TABLE dag_node ENABLE ROW LEVEL SECURITY;

ALTER TABLE dag_edge ENABLE ROW LEVEL SECURITY;

ALTER TABLE closure_dominance ENABLE ROW LEVEL SECURITY;

-- 1. Closure
CREATE POLICY "rls_closure_read" ON closure_dominance
    FOR SELECT TO authenticated
        USING (TRUE);

-- 2. Nodes
CREATE OR REPLACE VIEW view_graph_nodes AS
WITH ctx AS (
    SELECT
        *
    FROM
        get_graph_context())
SELECT
    n.id,
    n.type,
    n.label,
    n.auth_user_id,
    CASE WHEN predicate_has_perm(ROW (ctx.node_id, ctx.perms, ctx.membership_ids)::graph_context, 'NODE_CREATE') THEN
        n.invite_hash
    ELSE
        NULL
    END AS invite_hash,
    n.invite_expires,
    n.permission_bits,
    n.created_at,
    n.updated_at
FROM
    dag_node n
    JOIN ctx ON TRUE
    LEFT JOIN closure_dominance cd ON cd.ancestor_id = ctx.node_id
        AND cd.descendant_id = n.id
WHERE
    predicate_has_perm(ROW (ctx.node_id, ctx.perms, ctx.membership_ids)::graph_context, 'GRAPH_READ')
    AND (cd.ancestor_id IS NOT NULL
        OR EXISTS (
            SELECT
                1
            FROM
                dag_edge e
            WHERE
                e.child_id = n.id
                AND e.parent_id = ANY (ctx.membership_ids)));

-- 3. Edges
CREATE OR REPLACE VIEW view_graph_edges AS
WITH ctx AS (
    SELECT
        *
    FROM
        get_graph_context())
SELECT
    e.parent_id,
    e.child_id,
    e.created_at
FROM
    dag_edge e
    JOIN ctx ON TRUE
    LEFT JOIN closure_dominance cd ON cd.ancestor_id = ctx.node_id
        AND cd.descendant_id = e.parent_id
WHERE
    predicate_has_perm(ROW (ctx.node_id, ctx.perms, ctx.membership_ids)::graph_context, 'GRAPH_READ')
    AND (cd.ancestor_id IS NOT NULL
        OR e.parent_id = ANY (ctx.membership_ids));

-- 4. Permissions
GRANT SELECT ON view_graph_nodes TO authenticated;

GRANT SELECT ON view_graph_edges TO authenticated;

