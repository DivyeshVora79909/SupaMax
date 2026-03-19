CREATE TABLE IF NOT EXISTS opportunity (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    title text NOT NULL,
    proposal_path text,
    contract_path text,
    opportunity_status text,
    forecast_category text,
    lead_source text,
    status_order integer DEFAULT 0,
    probability smallint CHECK (
        probability >= 0
        AND probability <= 100
    ),
    amount decimal(15, 2),
    currency text DEFAULT 'USD',
    close_date date,
    description text,
    other jsonb,
    account_id uuid NOT NULL REFERENCES account (id) ON DELETE CASCADE,
    owner_id uuid NOT NULL REFERENCES dag_node (id) ON DELETE RESTRICT,
    created_by_node uuid REFERENCES dag_node (id) ON DELETE SET NULL,
    updated_by_node uuid REFERENCES dag_node (id) ON DELETE SET NULL,
    created_at timestamptz,
    updated_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_opportunity_account ON opportunity (account_id);

CREATE INDEX IF NOT EXISTS idx_opportunity_owner ON opportunity (owner_id);

CREATE INDEX IF NOT EXISTS idx_opp_status ON opportunity (opportunity_status);

CREATE INDEX IF NOT EXISTS idx_opp_close_date ON opportunity (close_date);

CREATE INDEX IF NOT EXISTS idx_opp_amount ON opportunity (amount DESC);

CREATE TRIGGER trg_opportunity_audit
    BEFORE INSERT OR UPDATE ON opportunity
    FOR EACH ROW EXECUTE FUNCTION audit_meta_fields();

CREATE TRIGGER trg_opportunity_ownership
    BEFORE UPDATE OF owner_id ON opportunity
    FOR EACH ROW EXECUTE FUNCTION enforce_ownership_root_res();

ALTER TABLE opportunity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_opportunity_select_via_dominance" ON opportunity FOR
SELECT TO authenticated USING (
        has_perm ('OPP_SELECT')
        AND _i_dominate (owner_id)
    );

CREATE POLICY "rls_opportunity_select_via_parent" ON opportunity FOR
SELECT TO authenticated USING (
        has_perm ('OPP_SELECT')
        AND _is_nonuser_parent (owner_id)
    );

CREATE POLICY "rls_opportunity_insert" ON opportunity FOR
INSERT
    TO authenticated
WITH
    CHECK (
        has_perm ('OPP_INSERT')
        AND (
            _i_dominate (owner_id)
            OR _is_nonuser_parent (owner_id)
        )
    );

CREATE POLICY "rls_opportunity_update" ON opportunity FOR
UPDATE TO authenticated USING (
    has_perm ('OPP_UPDATE')
    AND (
        _i_dominate (owner_id)
        OR _is_nonuser_parent (owner_id)
    )
);

CREATE POLICY "rls_opportunity_delete" ON opportunity FOR DELETE TO authenticated USING (
    has_perm ('OPP_DELETE')
    AND _i_dominate (owner_id)
);

GRANT
SELECT,
INSERT
,
UPDATE,
DELETE ON public.opportunity TO authenticated;