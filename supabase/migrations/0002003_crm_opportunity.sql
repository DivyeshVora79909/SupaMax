CREATE TABLE IF NOT EXISTS opportunity(
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL,
    proposal_path text,
    contract_path text,
    status_label text,
    status_order integer DEFAULT 0,
    probability smallint CHECK (probability >= 0 AND probability <= 100),
    account_id uuid NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    created_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    updated_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_opportunity_account ON opportunity(account_id);

CREATE OR REPLACE FUNCTION _trigger_audit_opportunity()
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
        IF NEW.account_id IS DISTINCT FROM OLD.account_id THEN
            PERFORM
                assert_dominance(assert_authenticated(), NEW.account_id);
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_opportunity_audit
    BEFORE INSERT OR UPDATE ON opportunity
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_audit_opportunity();

CREATE TRIGGER trg_opportunity_proposal_gc
    AFTER DELETE OR UPDATE OF proposal_path ON opportunity
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_link_storage('proposal_path');

CREATE TRIGGER trg_opportunity_contract_gc
    AFTER DELETE OR UPDATE OF contract_path ON opportunity
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_link_storage('contract_path');

ALTER TABLE opportunity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_opportunity_select" ON opportunity
    FOR SELECT
        USING (predicate_has_perm(get_graph_context(), 'OPP_SELECT')
            AND EXISTS (
                SELECT
                    1
                FROM
                    account a
                WHERE
                    a.id = opportunity.account_id AND (a.owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                        SELECT
                            1
                        FROM
                            closure_dominance cd
                        WHERE
                            cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = a.owner_id))));

CREATE POLICY "rls_opportunity_insert" ON opportunity
    FOR INSERT
        WITH CHECK (predicate_has_perm(get_graph_context(), 'OPP_INSERT')
        AND EXISTS (
            SELECT
                1
            FROM
                account a
            WHERE
                a.id = account_id AND (a.owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                    SELECT
                        1
                    FROM
                        closure_dominance cd
                    WHERE
                        cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = a.owner_id))));

CREATE POLICY "rls_opportunity_update" ON opportunity
    FOR UPDATE
        USING (predicate_has_perm(get_graph_context(), 'OPP_UPDATE')
            AND EXISTS (
                SELECT
                    1
                FROM
                    account a
                WHERE
                    a.id = opportunity.account_id AND (a.owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                        SELECT
                            1
                        FROM
                            closure_dominance cd
                        WHERE
                            cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = a.owner_id))));

CREATE POLICY "rls_opportunity_delete" ON opportunity
    FOR DELETE
        USING (predicate_has_perm(get_graph_context(), 'OPP_DELETE')
            AND EXISTS (
                SELECT
                    1
                FROM
                    account a
                WHERE
                    a.id = opportunity.account_id AND (a.owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                        SELECT
                            1
                        FROM
                            closure_dominance cd
                        WHERE
                            cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = a.owner_id))));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.opportunity TO authenticated;

