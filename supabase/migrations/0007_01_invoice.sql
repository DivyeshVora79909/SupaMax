-- 1. Table Definition
CREATE TABLE IF NOT EXISTS invoice(
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    amount numeric NOT NULL,
    pdf_path text,
    excel_path text,
    owner_id uuid NOT NULL REFERENCES dag_node(id) ON DELETE RESTRICT,
    created_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    updated_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- 2. Audit Logic
CREATE OR REPLACE FUNCTION _trigger_audit_invoice()
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
        -- Anti-Hiding Check: If changing owner, I must dominate the NEW owner
        IF NEW.owner_id IS DISTINCT FROM OLD.owner_id THEN
            PERFORM
                assert_dominance(assert_authenticated(), NEW.owner_id);
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_invoice_audit
    BEFORE INSERT OR UPDATE ON invoice
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_audit_invoice();

-- 3. Security
ALTER TABLE invoice ENABLE ROW LEVEL SECURITY;

-- Policy: SELECT
CREATE POLICY "rls_invoice_select" ON invoice
    FOR SELECT
        USING (predicate_has_perm(get_graph_context(), 'INV_SELECT')
            AND (owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                SELECT
                    1
                FROM
                    closure_dominance cd
                WHERE
                    cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = invoice.owner_id)));

-- Policy: INSERT
CREATE POLICY "rls_invoice_insert" ON invoice
    FOR INSERT
        WITH CHECK (predicate_has_perm(get_graph_context(), 'INV_INSERT')
        AND (owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
            SELECT
                1
            FROM
                closure_dominance cd
            WHERE
                cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = invoice.owner_id)));

-- Policy: UPDATE
CREATE POLICY "rls_invoice_update" ON invoice
    FOR UPDATE
        USING (predicate_has_perm(get_graph_context(), 'INV_UPDATE')
            AND (owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                SELECT
                    1
                FROM
                    closure_dominance cd
                WHERE
                    cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = invoice.owner_id)));

-- Policy: DELETE
CREATE POLICY "rls_invoice_delete" ON invoice
    FOR DELETE
        USING (predicate_has_perm(get_graph_context(), 'INV_DELETE')
            AND (owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                SELECT
                    1
                FROM
                    closure_dominance cd
                WHERE
                    cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = invoice.owner_id)));

-- 4. Bucket
INSERT INTO storage.buckets(id, name, public)
    VALUES ('invoices', 'invoices', FALSE)
ON CONFLICT (id)
    DO NOTHING;

-- 5. Storage Security
CREATE POLICY "rls_invoice_storage_access" ON storage.objects
    FOR ALL TO authenticated
        USING (bucket_id = 'invoices'
            AND EXISTS (
                SELECT
                    1
                FROM
                    invoice i
                WHERE
                    i.id::text = split_part(name, '/', 1)))
                WITH CHECK (bucket_id = 'invoices'
                AND EXISTS (
                    SELECT
                        1
                    FROM
                        invoice i
                    WHERE
                        i.id::text = split_part(name, '/', 1)));

