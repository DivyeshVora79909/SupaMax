CREATE TABLE IF NOT EXISTS account(
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    pdf_path text,
    excel_path text,
    status_label text,
    status_order integer DEFAULT 0,
    owner_id uuid NOT NULL REFERENCES dag_node(id) ON DELETE RESTRICT,
    created_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    updated_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_account_owner ON account(owner_id);

CREATE OR REPLACE FUNCTION _trigger_audit_account()
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
        IF NEW.owner_id IS DISTINCT FROM OLD.owner_id THEN
            PERFORM
                assert_dominance(assert_authenticated(), NEW.owner_id);
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_account_audit
    BEFORE INSERT OR UPDATE ON account
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_audit_account();

CREATE TRIGGER trg_account_pdf_gc
    AFTER DELETE OR UPDATE OF pdf_path ON account
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_link_storage('pdf_path');

CREATE TRIGGER trg_account_excel_gc
    AFTER DELETE OR UPDATE OF excel_path ON account
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_link_storage('excel_path');

ALTER TABLE account ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_account_select" ON account
    FOR SELECT
        USING (predicate_has_perm(get_graph_context(), 'ACCOUNT_SELECT')
            AND (owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                SELECT
                    1
                FROM
                    closure_dominance cd
                WHERE
                    cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = account.owner_id)));

CREATE POLICY "rls_account_insert" ON account
    FOR INSERT
        WITH CHECK (predicate_has_perm(get_graph_context(), 'ACCOUNT_INSERT')
        AND (owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
            SELECT
                1
            FROM
                closure_dominance cd
            WHERE
                cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = account.owner_id)));

CREATE POLICY "rls_account_update" ON account
    FOR UPDATE
        USING (predicate_has_perm(get_graph_context(), 'ACCOUNT_UPDATE')
            AND (owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                SELECT
                    1
                FROM
                    closure_dominance cd
                WHERE
                    cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = account.owner_id)));

CREATE POLICY "rls_account_delete" ON account
    FOR DELETE
        USING (predicate_has_perm(get_graph_context(), 'ACCOUNT_DELETE')
            AND (owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                SELECT
                    1
                FROM
                    closure_dominance cd
                WHERE
                    cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = account.owner_id)));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.account TO authenticated;

