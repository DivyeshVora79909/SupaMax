CREATE TABLE IF NOT EXISTS crm_label (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    column_name text NOT NULL,
    label text NOT NULL,
    sort_order integer DEFAULT 0,
    color text,
    icon text,
    owner_id uuid NOT NULL REFERENCES dag_node (id) ON DELETE CASCADE,
    created_by_node uuid REFERENCES dag_node (id) ON DELETE SET NULL,
    updated_by_node uuid REFERENCES dag_node (id) ON DELETE SET NULL,
    created_at timestamptz,
    updated_at timestamptz,
    CONSTRAINT unq_crm_label UNIQUE (owner_id, column_name, label),
    CONSTRAINT chk_crm_label_column CHECK (
        column_name IN (
            'lead_source',
            'industry',
            'priority',
            'account_status',
            'account_type',
            'rating',
            'contact_status',
            'activity_status',
            'contact_type',
            'department',
            'opportunity_status',
            'forecast_category',
            'activity_type',
            'project_status',
            'health_status',
            'project_type'
        )
    )
);

CREATE INDEX IF NOT EXISTS idx_crm_label_lookup ON crm_label (owner_id, column_name);

CREATE TRIGGER trg_crm_label_audit
    BEFORE INSERT OR UPDATE ON crm_label
    FOR EACH ROW EXECUTE FUNCTION audit_meta_fields();

CREATE TRIGGER trg_crm_label_ownership
    BEFORE UPDATE OF owner_id ON crm_label
    FOR EACH ROW EXECUTE FUNCTION enforce_ownership_root_res();

ALTER TABLE crm_label ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_crm_label_select_via_dominance" ON crm_label FOR
SELECT TO authenticated USING (_i_dominate (owner_id));

CREATE POLICY "rls_crm_label_select_via_parent" ON crm_label FOR
SELECT TO authenticated USING (_is_nonuser_parent (owner_id));

CREATE POLICY "rls_crm_label_insert" ON crm_label FOR
INSERT
    TO authenticated
WITH
    CHECK (
        has_perm ('CRM_LABEL_INSERT')
        AND (
            _i_dominate (owner_id)
            OR _is_nonuser_parent (owner_id)
        )
    );

CREATE POLICY "rls_crm_label_update" ON crm_label FOR
UPDATE TO authenticated USING (
    has_perm ('CRM_LABEL_UPDATE')
    AND (
        _i_dominate (owner_id)
        OR _is_nonuser_parent (owner_id)
    )
);

CREATE POLICY "rls_crm_label_delete" ON crm_label FOR DELETE TO authenticated USING (
    has_perm ('CRM_LABEL_DELETE')
    AND _i_dominate (owner_id)
);

GRANT
SELECT,
INSERT
,
UPDATE,
DELETE ON public.crm_label TO authenticated;