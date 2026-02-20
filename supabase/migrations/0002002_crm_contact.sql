CREATE TABLE IF NOT EXISTS contact(
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    email text,
    avatar_path text,
    document_path text,
    status_label text,
    status_order integer DEFAULT 0,
    account_id uuid NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    created_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    updated_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_contact_account ON contact(account_id);

CREATE INDEX IF NOT EXISTS idx_contact_email ON contact(email);

CREATE OR REPLACE FUNCTION _trigger_audit_contact()
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

CREATE TRIGGER trg_contact_audit
    BEFORE INSERT OR UPDATE ON contact
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_audit_contact();

CREATE TRIGGER trg_contact_avatar_gc
    AFTER DELETE OR UPDATE OF avatar_path ON contact
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_link_storage('avatar_path');

CREATE TRIGGER trg_contact_document_gc
    AFTER DELETE OR UPDATE OF document_path ON contact
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_link_storage('document_path');

ALTER TABLE contact ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_contact_select" ON contact
    FOR SELECT
        USING (predicate_has_perm(get_graph_context(), 'CONTACT_SELECT')
            AND EXISTS (
                SELECT
                    1
                FROM
                    account a
                WHERE
                    a.id = contact.account_id AND (a.owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                        SELECT
                            1
                        FROM
                            closure_dominance cd
                        WHERE
                            cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = a.owner_id))));

CREATE POLICY "rls_contact_insert" ON contact
    FOR INSERT
        WITH CHECK (predicate_has_perm(get_graph_context(), 'CONTACT_INSERT')
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

CREATE POLICY "rls_contact_update" ON contact
    FOR UPDATE
        USING (predicate_has_perm(get_graph_context(), 'CONTACT_UPDATE')
            AND EXISTS (
                SELECT
                    1
                FROM
                    account a
                WHERE
                    a.id = contact.account_id AND (a.owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                        SELECT
                            1
                        FROM
                            closure_dominance cd
                        WHERE
                            cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = a.owner_id))));

CREATE POLICY "rls_contact_delete" ON contact
    FOR DELETE
        USING (predicate_has_perm(get_graph_context(), 'CONTACT_DELETE')
            AND EXISTS (
                SELECT
                    1
                FROM
                    account a
                WHERE
                    a.id = contact.account_id AND (a.owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                        SELECT
                            1
                        FROM
                            closure_dominance cd
                        WHERE
                            cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = a.owner_id))));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.contact TO authenticated;

