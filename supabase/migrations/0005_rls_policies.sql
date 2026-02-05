-- 1. Closure Table: Structural Access (Public Read)
CREATE POLICY "rls_closure_read" ON closure_dominance
    FOR SELECT
        USING (TRUE);

-- 2. Nodes: Line of Sight
CREATE POLICY "rls_node_read" ON dag_node
    FOR SELECT
        USING ((WITH ctx AS (
            SELECT
                *
            FROM
                get_graph_context())
                    SELECT
                        -- Case A: Looking Up (I can see my ancestors)
(id = ANY (
                            SELECT
                                ancestor_ids
                            FROM
                                ctx)) OR
                                -- Case B: Looking Down (I can see my descendants)
                                EXISTS (
                                    SELECT
                                        1
                                    FROM
                                        closure_dominance
                                    WHERE
                                        ancestor_id =(
                                            SELECT
                                                node_id
                                            FROM
                                                ctx) AND descendant_id = id)));

-- 3. Edges: Structural Consistency
CREATE POLICY "rls_edge_read" ON dag_edge
    FOR SELECT
        USING ((WITH ctx AS (
            SELECT
                *
            FROM
                get_graph_context())
                    SELECT
                        -- Case A: Looking Sideways (Edges of my direct parents/siblings)
(parent_id = ANY (
                            SELECT
                                parent_ids
                            FROM
                                ctx)) OR
                                -- Case B: Looking Down (Edges within my subtree)
                                EXISTS (
                                    SELECT
                                        1
                                    FROM
                                        closure_dominance
                                    WHERE
                                        ancestor_id =(
                                            SELECT
                                                node_id
                                            FROM
                                                ctx) AND descendant_id = parent_id)));

