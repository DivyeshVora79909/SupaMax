ALTER TABLE dag_node ENABLE ROW LEVEL SECURITY;

ALTER TABLE dag_edge ENABLE ROW LEVEL SECURITY;

ALTER TABLE closure_dominance ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.dag_node TO authenticated;

GRANT SELECT ON public.dag_edge TO authenticated;

GRANT SELECT ON public.closure_dominance TO authenticated;

CREATE POLICY "rls_closure_read" ON closure_dominance
    FOR SELECT TO authenticated
        USING (TRUE);

-- 1. Node Policy (Consolidated Upward + Downward)
CREATE POLICY "rls_dag_node_select" ON dag_node
    FOR SELECT TO authenticated
        USING ((
            SELECT
                predicate_has_perm(get_graph_context(), 'GRAPH_READ'))
                AND (id = ANY ((
                    SELECT
                        membership_ids
                    FROM
                        get_graph_context())) OR EXISTS (
                            SELECT
                                1
                            FROM
                                closure_dominance cd
                            WHERE
                                cd.ancestor_id =(
                                    SELECT
                                        current_node_id()) AND cd.descendant_id = dag_node.id)));

-- 2. Edge Policy (Consolidated Upward + Downward)
CREATE POLICY "rls_dag_edge_select" ON dag_edge
    FOR SELECT TO authenticated
        USING ((
            SELECT
                predicate_has_perm(get_graph_context(), 'GRAPH_READ'))
                AND (parent_id = ANY ((
                    SELECT
                        membership_ids
                    FROM
                        get_graph_context())) OR EXISTS (
                            SELECT
                                1
                            FROM
                                closure_dominance cd
                            WHERE
                                cd.ancestor_id =(
                                    SELECT
                                        current_node_id()) AND cd.descendant_id = dag_edge.parent_id)));

