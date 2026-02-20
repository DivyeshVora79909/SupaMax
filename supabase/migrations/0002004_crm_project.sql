CREATE TABLE IF NOT EXISTS project(
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL,
    description text,
    brief_path text,
    spec_path text,
    status_label text,
    status_order integer DEFAULT 0,
    probability smallint CHECK (probability >= 0 AND probability <= 100),
    opportunity_id uuid NOT NULL REFERENCES opportunity(id) ON DELETE CASCADE,
    created_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    updated_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_project_opportunity ON project(opportunity_id);

CREATE OR REPLACE FUNCTION _trigger_audit_project()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_by_node := current_node_id();
        NEW.updated_by_node := current_node_id();
    ELSIF TG_OP = 'UPDATE' THEN
        NEW.updated_by_node := current_node_id();
        NEW.updated_at := now();
        IF NEW.opportunity_id IS DISTINCT FROM OLD.opportunity_id THEN
            PERFORM
                assert_dominance(assert_authenticated(), NEW.opportunity_id);
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_project_audit
    BEFORE INSERT OR UPDATE ON project
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_audit_project();

CREATE TRIGGER trg_project_brief_gc
    AFTER DELETE OR UPDATE OF brief_path ON project
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_link_storage('brief_path');

CREATE TRIGGER trg_project_spec_gc
    AFTER DELETE OR UPDATE OF spec_path ON project
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_link_storage('spec_path');

ALTER TABLE project ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_project_select" ON project
    FOR SELECT
        USING (predicate_has_perm(get_graph_context(), 'PROJ_SELECT')
            AND EXISTS (
                SELECT
                    1
                FROM
                    opportunity o
                    JOIN account a ON o.account_id = a.id
                WHERE
                    o.id = project.opportunity_id AND (a.owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                        SELECT
                            1
                        FROM
                            closure_dominance cd
                        WHERE
                            cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = a.owner_id))));

CREATE POLICY "rls_project_insert" ON project
    FOR INSERT
        WITH CHECK (predicate_has_perm(get_graph_context(), 'PROJ_INSERT')
        AND EXISTS (
            SELECT
                1
            FROM
                opportunity o
                JOIN account a ON o.account_id = a.id
            WHERE
                o.id = opportunity_id AND (a.owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                    SELECT
                        1
                    FROM
                        closure_dominance cd
                    WHERE
                        cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = a.owner_id))));

CREATE POLICY "rls_project_update" ON project
    FOR UPDATE
        USING (predicate_has_perm(get_graph_context(), 'PROJ_UPDATE')
            AND EXISTS (
                SELECT
                    1
                FROM
                    opportunity o
                    JOIN account a ON o.account_id = a.id
                WHERE
                    o.id = project.opportunity_id AND (a.owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                        SELECT
                            1
                        FROM
                            closure_dominance cd
                        WHERE
                            cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = a.owner_id))));

CREATE POLICY "rls_project_delete" ON project
    FOR DELETE
        USING (predicate_has_perm(get_graph_context(), 'PROJ_DELETE')
            AND EXISTS (
                SELECT
                    1
                FROM
                    opportunity o
                    JOIN account a ON o.account_id = a.id
                WHERE
                    o.id = project.opportunity_id AND (a.owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                        SELECT
                            1
                        FROM
                            closure_dominance cd
                        WHERE
                            cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = a.owner_id))));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.project TO authenticated;

