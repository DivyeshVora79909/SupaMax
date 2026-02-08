-- 1. Table Definition
CREATE TABLE IF NOT EXISTS customer(
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name text NOT NULL,
    email text,
    status text DEFAULT 'prospect', -- prospect, active, churned
    owner_id uuid NOT NULL REFERENCES dag_node(id) ON DELETE RESTRICT,
    created_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    updated_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- 2. Indexes
CREATE INDEX idx_customer_owner ON customer(owner_id);

CREATE INDEX idx_customer_email ON customer(email);

-- 3. Audit Logic
CREATE OR REPLACE FUNCTION _trigger_audit_customer()
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

CREATE TRIGGER trg_customer_audit
    BEFORE INSERT OR UPDATE ON customer
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_audit_customer();

-- 4. Security
ALTER TABLE customer ENABLE ROW LEVEL SECURITY;

-- SELECT Policy
CREATE POLICY "rls_customer_select" ON customer
    FOR SELECT
        USING (predicate_has_perm(get_graph_context(), 'CUST_SELECT')
            AND (owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                SELECT
                    1
                FROM
                    closure_dominance cd
                WHERE
                    cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = customer.owner_id)));

-- INSERT Policy
CREATE POLICY "rls_customer_insert" ON customer
    FOR INSERT
        WITH CHECK (predicate_has_perm(get_graph_context(), 'CUST_INSERT')
        AND (owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
            SELECT
                1
            FROM
                closure_dominance cd
            WHERE
                cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = customer.owner_id)));

-- UPDATE Policy
CREATE POLICY "rls_customer_update" ON customer
    FOR UPDATE
        USING (predicate_has_perm(get_graph_context(), 'CUST_UPDATE')
            AND (owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                SELECT
                    1
                FROM
                    closure_dominance cd
                WHERE
                    cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = customer.owner_id)));

-- DELETE Policy
CREATE POLICY "rls_customer_delete" ON customer
    FOR DELETE
        USING (predicate_has_perm(get_graph_context(), 'CUST_DELETE')
            AND (owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                SELECT
                    1
                FROM
                    closure_dominance cd
                WHERE
                    cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = customer.owner_id)));

