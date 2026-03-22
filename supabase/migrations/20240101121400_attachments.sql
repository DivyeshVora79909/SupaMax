INSERT INTO
    storage.buckets (id, name, public)
VALUES (
        'resources',
        'resources',
        FALSE
    ) ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public._sync_account_storage_owner()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
BEGIN
    UPDATE storage.objects
    SET    owner_id = NEW.owner_id::text
    WHERE  bucket_id = 'resources'
      AND  name IN (NEW.pdf_path, NEW.excel_path)
      AND  name IS NOT NULL
      AND  (owner_id IS DISTINCT FROM NEW.owner_id::text);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._sync_contact_storage_owner()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
BEGIN
    UPDATE storage.objects
    SET    owner_id = NEW.owner_id::text
    WHERE  bucket_id = 'resources'
      AND  name IN (NEW.avatar_path, NEW.document_path)
      AND  name IS NOT NULL
      AND  (owner_id IS DISTINCT FROM NEW.owner_id::text);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._sync_opportunity_storage_owner()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
BEGIN
    UPDATE storage.objects
    SET    owner_id = NEW.owner_id::text
    WHERE  bucket_id = 'resources'
      AND  name IN (NEW.proposal_path, NEW.contract_path)
      AND  name IS NOT NULL
      AND  (owner_id IS DISTINCT FROM NEW.owner_id::text);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._sync_project_storage_owner()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
BEGIN
    UPDATE storage.objects
    SET    owner_id = NEW.owner_id::text
    WHERE  bucket_id = 'resources'
      AND  name IN (NEW.brief_path, NEW.spec_path)
      AND  name IS NOT NULL
      AND  (owner_id IS DISTINCT FROM NEW.owner_id::text);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_account_storage_sync
    AFTER INSERT OR UPDATE OF owner_id, pdf_path, excel_path ON account
    FOR EACH ROW EXECUTE FUNCTION public._sync_account_storage_owner();

CREATE TRIGGER trg_contact_storage_sync
    AFTER INSERT OR UPDATE OF owner_id, avatar_path, document_path ON contact
    FOR EACH ROW EXECUTE FUNCTION public._sync_contact_storage_owner();

CREATE TRIGGER trg_opportunity_storage_sync
    AFTER INSERT OR UPDATE OF owner_id, proposal_path, contract_path ON opportunity
    FOR EACH ROW EXECUTE FUNCTION public._sync_opportunity_storage_owner();

CREATE TRIGGER trg_project_storage_sync
    AFTER INSERT OR UPDATE OF owner_id, brief_path, spec_path ON project
    FOR EACH ROW EXECUTE FUNCTION public._sync_project_storage_owner();

CREATE POLICY "rls_resources_select" ON storage.objects FOR SELECT TO authenticated USING (
    bucket_id = 'resources'
    AND owner_id IS NOT NULL
    AND (
        _i_dominate(NULLIF(owner_id, '')::uuid) 
    )
);

CREATE POLICY "rls_resources_select_via_parent" ON storage.objects FOR SELECT TO authenticated USING (
    bucket_id = 'resources'
    AND owner_id IS NOT NULL
    AND _is_nonuser_parent(NULLIF(owner_id, '')::uuid)
);

CREATE POLICY "rls_resources_insert" ON storage.objects FOR
INSERT
    TO authenticated
WITH
    CHECK (bucket_id = 'resources');

CREATE POLICY "rls_resources_update" ON storage.objects FOR UPDATE TO authenticated USING (
    bucket_id = 'resources'
    AND owner_id IS NOT NULL
    AND (
        _i_dominate(NULLIF(owner_id, '')::uuid) 
    )
);

CREATE POLICY "rls_resources_delete" ON storage.objects FOR DELETE TO authenticated USING (
    bucket_id = 'resources'
    AND owner_id IS NOT NULL
    AND (
        _i_dominate(NULLIF(owner_id, '')::uuid) 
    )
);