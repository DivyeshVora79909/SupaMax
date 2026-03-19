CREATE POLICY "rls_closure_read" ON closure_dominance FOR
SELECT TO authenticated USING (TRUE);

CREATE POLICY "rls_node_select_via_dominance" ON dag_node FOR
SELECT TO authenticated USING (
        has_perm ('GRAPH_READ')
        AND _i_dominate (id)
    );

CREATE POLICY "rls_node_select_via_parent" ON dag_node FOR
SELECT TO authenticated USING (
        has_perm ('GRAPH_READ')
        AND _is_nonuser_parent (id)
    );

CREATE POLICY "rls_edge_select_parent_dominates" ON dag_edge FOR
SELECT TO authenticated USING (
        has_perm ('GRAPH_READ')
        AND _i_dominate (parent_id)
    );

CREATE POLICY "rls_edge_select_child_dominates" ON dag_edge FOR
SELECT TO authenticated USING (
        has_perm ('GRAPH_READ')
        AND _i_dominate (child_id)
    );

CREATE POLICY "rls_edge_select_parent_is_nonuser_parent" ON dag_edge FOR
SELECT TO authenticated USING (
        has_perm ('GRAPH_READ')
        AND _is_nonuser_parent (parent_id)
    );

CREATE POLICY "rls_edge_select_child_is_nonuser_parent" ON dag_edge FOR
SELECT TO authenticated USING (
        has_perm ('GRAPH_READ')
        AND _is_nonuser_parent (child_id)
    );