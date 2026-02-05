-- 1. Table Definition
CREATE TABLE IF NOT EXISTS invoice(
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    amount numeric NOT NULL,
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

-- 3. Security (Granular RLS)
ALTER TABLE invoice ENABLE ROW LEVEL SECURITY;

-- Policy: SELECT
CREATE POLICY "rls_invoice_select" ON invoice
    FOR SELECT
        USING ((WITH ctx AS (
            SELECT
                *
            FROM
                get_graph_context())
                    SELECT
                        predicate_has_perm(ctx, 'INV_SELECT') AND (predicate_dominates(ctx.node_id, owner_id) OR owner_id = ANY (ctx.membership_ids))));

-- Policy: INSERT
CREATE POLICY "rls_invoice_insert" ON invoice
    FOR INSERT
        WITH CHECK ((WITH ctx AS (
            SELECT
                *
            FROM
                get_graph_context())
                    SELECT
                        predicate_has_perm(ctx, 'INV_INSERT') AND (predicate_dominates(ctx.node_id, owner_id) OR owner_id = ANY (ctx.membership_ids))));

-- Policy: UPDATE
CREATE POLICY "rls_invoice_update" ON invoice
    FOR UPDATE
        USING ((WITH ctx AS (
            SELECT
                *
            FROM
                get_graph_context())
                    SELECT
                        predicate_has_perm(ctx, 'INV_UPDATE') AND (predicate_dominates(ctx.node_id, owner_id) OR owner_id = ANY (ctx.membership_ids))));

-- Policy: DELETE
CREATE POLICY "rls_invoice_delete" ON invoice
    FOR DELETE
        USING ((WITH ctx AS (
            SELECT
                *
            FROM
                get_graph_context())
                    SELECT
                        predicate_has_perm(ctx, 'INV_DELETE') AND (predicate_dominates(ctx.node_id, owner_id) OR owner_id = ANY (ctx.membership_ids))));

