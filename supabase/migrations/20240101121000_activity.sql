CREATE TABLE IF NOT EXISTS opportunity_activity (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    activity_type text NOT NULL,
    title text NOT NULL,
    description text,
    start_time timestamptz,
    end_time timestamptz,
    opportunity_id uuid NOT NULL REFERENCES opportunity (id) ON DELETE CASCADE,
    owner_id uuid NOT NULL REFERENCES dag_node (id) ON DELETE RESTRICT,
    created_by_node uuid REFERENCES dag_node (id) ON DELETE SET NULL,
    updated_by_node uuid REFERENCES dag_node (id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_opportunity_activity_time_order CHECK (
        end_time IS NULL
        OR start_time IS NULL
        OR end_time >= start_time
    )
);

CREATE INDEX IF NOT EXISTS idx_opportunity_activity_parent ON opportunity_activity (
    opportunity_id,
    created_at DESC
);

CREATE INDEX IF NOT EXISTS idx_opportunity_activity_owner ON opportunity_activity (owner_id);

CREATE TRIGGER trg_opportunity_activity_audit
    BEFORE INSERT OR UPDATE ON opportunity_activity
    FOR EACH ROW EXECUTE FUNCTION audit_meta_fields();

CREATE TRIGGER trg_opportunity_activity_ownership
    BEFORE UPDATE OF owner_id ON opportunity_activity
    FOR EACH ROW EXECUTE FUNCTION enforce_ownership_root_res();

ALTER TABLE opportunity_activity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_opportunity_activity_select_via_dominance" ON opportunity_activity FOR
SELECT TO authenticated USING (
        has_perm ('OPP_SELECT')
        AND _i_dominate (owner_id)
    );

CREATE POLICY "rls_opportunity_activity_select_via_parent" ON opportunity_activity FOR
SELECT TO authenticated USING (
        has_perm ('OPP_SELECT')
        AND _is_nonuser_parent (owner_id)
    );

CREATE POLICY "rls_opportunity_activity_insert" ON opportunity_activity FOR
INSERT
    TO authenticated
WITH
    CHECK (
        has_perm ('OPP_ACTIVITY_INSERT')
        AND (
            _i_dominate (owner_id)
            OR _is_nonuser_parent (owner_id)
        )
    );

CREATE POLICY "rls_opportunity_activity_update" ON opportunity_activity FOR
UPDATE TO authenticated USING (
    has_perm ('OPP_ACTIVITY_UPDATE')
    AND (
        _i_dominate (owner_id)
        OR _is_nonuser_parent (owner_id)
    )
);

CREATE POLICY "rls_opportunity_activity_delete" ON opportunity_activity FOR DELETE TO authenticated USING (
    has_perm ('OPP_ACTIVITY_DELETE')
    AND _i_dominate (owner_id)
);

GRANT
SELECT,
INSERT
,
UPDATE,
DELETE ON public.opportunity_activity TO authenticated;