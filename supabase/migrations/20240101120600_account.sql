CREATE TABLE IF NOT EXISTS account (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    name text NOT NULL,
    pdf_path text,
    excel_path text,
    account_status text,
    lead_source text,
    account_type text,
    rating text,
    status_order integer DEFAULT 0,
    annual_revenue decimal(15, 2),
    head_count integer,
    industry text,
    website text,
    billing_address jsonb,
    shipping_address jsonb,
    description text,
    other jsonb,
    owner_id uuid NOT NULL REFERENCES dag_node (id) ON DELETE RESTRICT,
    created_by_node uuid REFERENCES dag_node (id) ON DELETE SET NULL,
    updated_by_node uuid REFERENCES dag_node (id) ON DELETE SET NULL,
    created_at timestamptz,
    updated_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_account_owner ON account (owner_id);

CREATE INDEX IF NOT EXISTS idx_account_status ON account (account_status);

CREATE INDEX IF NOT EXISTS idx_account_type ON account (account_type);

CREATE INDEX IF NOT EXISTS idx_account_name_search ON account (name text_pattern_ops);

CREATE INDEX IF NOT EXISTS idx_account_industry ON account (industry);

CREATE INDEX IF NOT EXISTS idx_account_pagination ON account (created_at DESC, id);

CREATE TRIGGER trg_account_audit
    BEFORE INSERT OR UPDATE ON account
    FOR EACH ROW EXECUTE FUNCTION audit_meta_fields();

CREATE TRIGGER trg_account_ownership
    BEFORE UPDATE OF owner_id ON account
    FOR EACH ROW EXECUTE FUNCTION enforce_ownership_root_res();

ALTER TABLE account ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_account_select_via_dominance" ON account FOR
SELECT TO authenticated USING (
        has_perm ('ACCOUNT_SELECT')
        AND _i_dominate (owner_id)
    );

CREATE POLICY "rls_account_select_via_parent" ON account FOR
SELECT TO authenticated USING (
        has_perm ('ACCOUNT_SELECT')
        AND _is_nonuser_parent (owner_id)
    );

CREATE POLICY "rls_account_insert" ON account FOR
INSERT
    TO authenticated
WITH
    CHECK (
        has_perm ('ACCOUNT_INSERT')
        AND (
            _i_dominate (owner_id)
            OR _is_nonuser_parent (owner_id)
        )
    );

CREATE POLICY "rls_account_update" ON account FOR
UPDATE TO authenticated USING (
    has_perm ('ACCOUNT_UPDATE')
    AND (
        _i_dominate (owner_id)
        OR _is_nonuser_parent (owner_id)
    )
);

CREATE POLICY "rls_account_delete" ON account FOR DELETE TO authenticated USING (
    has_perm ('ACCOUNT_DELETE')
    AND _i_dominate (owner_id)
);

GRANT
SELECT,
INSERT
,
UPDATE,
DELETE ON public.account TO authenticated;