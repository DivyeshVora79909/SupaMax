CREATE TABLE IF NOT EXISTS contact (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid (),
    email text,
    avatar_path text,
    document_path text,
    contact_status text,
    status_order integer DEFAULT 0,
    first_name text NOT NULL,
    last_name text NOT NULL,
    phone text,
    mobile text,
    department text,
    activity_status text,
    contact_type text,
    social_links jsonb,
    profile jsonb,
    other jsonb,
    account_id uuid NOT NULL REFERENCES account (id) ON DELETE CASCADE,
    owner_id uuid NOT NULL REFERENCES dag_node (id) ON DELETE RESTRICT,
    created_by_node uuid REFERENCES dag_node (id) ON DELETE SET NULL,
    updated_by_node uuid REFERENCES dag_node (id) ON DELETE SET NULL,
    created_at timestamptz,
    updated_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_contact_account ON contact (account_id);

CREATE INDEX IF NOT EXISTS idx_contact_owner ON contact (owner_id);

CREATE INDEX IF NOT EXISTS idx_contact_email ON contact (email);

CREATE INDEX IF NOT EXISTS idx_contact_name ON contact (last_name, first_name);

CREATE INDEX IF NOT EXISTS idx_contact_status ON contact (contact_status);

CREATE TRIGGER trg_contact_audit
    BEFORE INSERT OR UPDATE ON contact
    FOR EACH ROW EXECUTE FUNCTION audit_meta_fields();

CREATE TRIGGER trg_contact_ownership
    BEFORE UPDATE OF owner_id ON contact
    FOR EACH ROW EXECUTE FUNCTION enforce_ownership_root_res();

ALTER TABLE contact ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_contact_select_via_dominance" ON contact FOR
SELECT TO authenticated USING (
        has_perm ('CONTACT_SELECT')
        AND _i_dominate (owner_id)
    );

CREATE POLICY "rls_contact_select_via_parent" ON contact FOR
SELECT TO authenticated USING (
        has_perm ('CONTACT_SELECT')
        AND _is_nonuser_parent (owner_id)
    );

CREATE POLICY "rls_contact_insert" ON contact FOR
INSERT
    TO authenticated
WITH
    CHECK (
        has_perm ('CONTACT_INSERT')
        AND (
            _i_dominate (owner_id)
            OR _is_nonuser_parent (owner_id)
        )
    );

CREATE POLICY "rls_contact_update" ON contact FOR
UPDATE TO authenticated USING (
    has_perm ('CONTACT_UPDATE')
    AND (
        _i_dominate (owner_id)
        OR _is_nonuser_parent (owner_id)
    )
);

CREATE POLICY "rls_contact_delete" ON contact FOR DELETE TO authenticated USING (
    has_perm ('CONTACT_DELETE')
    AND _i_dominate (owner_id)
);

GRANT
SELECT,
INSERT
,
UPDATE,
DELETE ON public.contact TO authenticated;