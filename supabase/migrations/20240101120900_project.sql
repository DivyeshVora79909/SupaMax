CREATE TABLE IF NOT EXISTS project (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    title text NOT NULL,
    description text,
    brief_path text,
    spec_path text,
    project_status text,
    status_order integer DEFAULT 0,
    health_status text,
    project_type text,
    priority text,
    probability smallint CHECK (
        probability >= 0
        AND probability <= 100
    ),
    budget decimal(15, 2),
    actual_cost decimal(15, 2),
    completion_percent integer CHECK (
        completion_percent BETWEEN 0 AND 100
    ),
    project_manager text,
    start_date date,
    target_end_date date,
    actual_end_date date,
    other jsonb,
    opportunity_id uuid NOT NULL REFERENCES opportunity (id) ON DELETE CASCADE,
    owner_id uuid NOT NULL REFERENCES dag_node (id) ON DELETE RESTRICT,
    created_by_node uuid REFERENCES dag_node (id) ON DELETE SET NULL,
    updated_by_node uuid REFERENCES dag_node (id) ON DELETE SET NULL,
    created_at timestamptz,
    updated_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_project_opportunity ON project (opportunity_id);

CREATE INDEX IF NOT EXISTS idx_project_owner ON project (owner_id);

CREATE INDEX IF NOT EXISTS idx_project_status ON project (project_status);

CREATE INDEX IF NOT EXISTS idx_project_dates ON project (start_date, target_end_date);

CREATE TRIGGER trg_project_audit
    BEFORE INSERT OR UPDATE ON project
    FOR EACH ROW EXECUTE FUNCTION audit_meta_fields();

CREATE TRIGGER trg_project_ownership
    BEFORE UPDATE OF owner_id ON project
    FOR EACH ROW EXECUTE FUNCTION enforce_ownership_root_res();

ALTER TABLE project ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_project_select_via_dominance" ON project FOR
SELECT TO authenticated USING (
        has_perm ('PROJ_SELECT')
        AND _i_dominate (owner_id)
    );

CREATE POLICY "rls_project_select_via_parent" ON project FOR
SELECT TO authenticated USING (
        has_perm ('PROJ_SELECT')
        AND _is_nonuser_parent (owner_id)
    );

CREATE POLICY "rls_project_insert" ON project FOR
INSERT
    TO authenticated
WITH
    CHECK (
        has_perm ('PROJ_INSERT')
        AND (
            _i_dominate (owner_id)
            OR _is_nonuser_parent (owner_id)
        )
    );

CREATE POLICY "rls_project_update" ON project FOR
UPDATE TO authenticated USING (
    has_perm ('PROJ_UPDATE')
    AND (
        _i_dominate (owner_id)
        OR _is_nonuser_parent (owner_id)
    )
);

CREATE POLICY "rls_project_delete" ON project FOR DELETE TO authenticated USING (
    has_perm ('PROJ_DELETE')
    AND _i_dominate (owner_id)
);

GRANT
SELECT,
INSERT
,
UPDATE,
DELETE ON public.project TO authenticated;