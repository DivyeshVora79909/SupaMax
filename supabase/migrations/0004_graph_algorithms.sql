-- 1. Internal: Cycle Detection
CREATE OR REPLACE FUNCTION _algo_detect_cycle(p_parent uuid, p_child uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    AS $$
    SELECT
        EXISTS(
            SELECT
                1
            FROM
                closure_dominance
            WHERE
                ancestor_id = p_child
                AND descendant_id = p_parent);
$$;

-- 2. Internal: Attach Subtree (Closure Maintenance)
CREATE OR REPLACE FUNCTION _algo_attach_subtree(p_parent uuid, p_child uuid)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
BEGIN
    -- A x B Cartesian Product for new paths
    INSERT INTO closure_dominance(ancestor_id, descendant_id, depth)
    SELECT
        a.ancestor_id,
        d.descendant_id,
        a.depth + d.depth + 1
    FROM
        closure_dominance a
        CROSS JOIN closure_dominance d
    WHERE
        a.descendant_id = p_parent
        AND d.ancestor_id = p_child
    ON CONFLICT
        DO NOTHING;
END;
$$;

-- 3. Internal: Detach Subtree (Closure Maintenance)
-- Sophisticated logic to handle multi-path reachability
CREATE OR REPLACE FUNCTION _algo_detach_subtree(p_parent uuid, p_child uuid)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $$
DECLARE
    rec_ancestor record;
    v_descendants uuid[];
    v_reachable uuid[];
BEGIN
    FOR rec_ancestor IN
    SELECT
        ancestor_id
    FROM
        closure_dominance
    WHERE
        descendant_id = p_parent LOOP
            -- Get all nodes in the subtree being potentially cut off
            SELECT
                array_agg(descendant_id) INTO v_descendants
            FROM
                closure_dominance
            WHERE
                ancestor_id = p_child;
            IF v_descendants IS NULL THEN
                CONTINUE;
            END IF;
            -- Graph Traversal: Is there ANY other path from Ancestor -> Descendants?
            WITH RECURSIVE reach(
                n
) AS (
                SELECT
                    child_id
                FROM
                    dag_edge
                WHERE
                    parent_id = rec_ancestor.ancestor_id
                    AND NOT (parent_id = p_parent
                        AND child_id = p_child) -- Ignore edge being deleted
                UNION
                SELECT
                    e.child_id
                FROM
                    dag_edge e
                    JOIN reach r ON e.parent_id = r.n
                WHERE
                    NOT (e.parent_id = p_parent
                        AND e.child_id = p_child))
            SELECT
                array_agg(n) INTO v_reachable
            FROM
                reach
            WHERE
                n = ANY (v_descendants);
            -- Prune Closure
            IF v_reachable IS NULL THEN
                DELETE FROM closure_dominance
                WHERE ancestor_id = rec_ancestor.ancestor_id
                    AND descendant_id = ANY (v_descendants)
                    AND ancestor_id <> descendant_id;
            ELSE
                DELETE FROM closure_dominance
                WHERE ancestor_id = rec_ancestor.ancestor_id
                    AND descendant_id = ANY (v_descendants)
                    AND NOT (descendant_id = ANY (v_reachable))
                    AND ancestor_id <> descendant_id;
            END IF;
        END LOOP;
END;
$$;

-- 4. Internal: Init Single Node Closure
CREATE OR REPLACE FUNCTION _algo_init_node(p_node uuid)
    RETURNS void
    LANGUAGE sql
    AS $$
    INSERT INTO closure_dominance(ancestor_id, descendant_id, depth)
        VALUES(p_node, p_node, 0)
    ON CONFLICT
        DO NOTHING;
$$;

