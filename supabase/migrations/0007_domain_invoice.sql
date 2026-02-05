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
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_invoice_audit
    BEFORE INSERT OR UPDATE ON invoice
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_audit_invoice();

-- 3. Security (RLS)
ALTER TABLE invoice ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_invoice_read" ON invoice
    FOR SELECT
        USING ((WITH ctx AS (
            SELECT
                *
            FROM
                get_graph_context())
                    SELECT
                        predicate_has_perm(ctx, 'INVOICE_READ') -- Permission Check
                        AND (predicate_dominates(ctx.node_id, invoice.owner_id) -- Dominance Check
                        OR invoice.owner_id = ANY (ctx.parent_ids) -- Membership Check (Siblings)
)));

CREATE POLICY "rls_invoice_write" ON invoice
    FOR ALL
        USING ((WITH ctx AS (
            SELECT
                *
            FROM
                get_graph_context())
                    SELECT
                        predicate_has_perm(ctx, 'INVOICE_WRITE') AND (predicate_dominates(ctx.node_id, invoice.owner_id) OR invoice.owner_id = ANY (ctx.parent_ids))));

