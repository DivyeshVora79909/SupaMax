-- 1. Closure Table: Structural Access (Public Read)
-- Required for Graph UI traversal
CREATE POLICY "rls_closure_read" ON closure_dominance
    FOR SELECT
        USING (TRUE);

-- 2. Nodes: Granular Visibility
-- Logic: Has Permission AND (Dominates Node OR Node is Sibling)
CREATE POLICY "rls_node_read" ON dag_node
    FOR SELECT
        USING ((WITH ctx AS (
            SELECT
                *
            FROM
                get_graph_context())
                    SELECT
                        predicate_has_perm(ctx, 'GRAPH_READ') AND (
                        -- Dominance (I own it)
                        predicate_dominates(ctx.node_id, id) OR
                        -- Membership (It is my sibling: Child of my parent Groups/Roles)
                        EXISTS (
                            SELECT
                                1
                            FROM
                                dag_edge e
                            WHERE
                                e.child_id = id AND e.parent_id = ANY (ctx.membership_ids)))));

-- 3. Edges: Structural Consistency
-- Logic: Can see edge if can see Parent AND Child
CREATE POLICY "rls_edge_read" ON dag_edge
    FOR SELECT
        USING ((WITH ctx AS (
            SELECT
                *
            FROM
                get_graph_context())
                    SELECT
                        predicate_has_perm(ctx, 'GRAPH_READ') AND (
                        -- Dominance (I own the relationship)
                        predicate_dominates(ctx.node_id, parent_id) OR
                        -- Membership (Edge belongs to my parent Group/Role)
                        parent_id = ANY (ctx.membership_ids))));

