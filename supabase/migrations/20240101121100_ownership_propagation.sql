CREATE OR REPLACE FUNCTION _cascade_owner_from_account()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF OLD.owner_id IS DISTINCT FROM NEW.owner_id THEN
        UPDATE contact
        SET owner_id = NEW.owner_id
        WHERE account_id = NEW.id AND owner_id IS DISTINCT FROM NEW.owner_id;

        UPDATE opportunity
        SET owner_id = NEW.owner_id
        WHERE account_id = NEW.id AND owner_id IS DISTINCT FROM NEW.owner_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_account_cascade_owner ON account;

CREATE TRIGGER trg_account_cascade_owner
    AFTER UPDATE OF owner_id ON account
    FOR EACH ROW EXECUTE FUNCTION _cascade_owner_from_account();

CREATE OR REPLACE FUNCTION _cascade_owner_from_opportunity()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF OLD.owner_id IS DISTINCT FROM NEW.owner_id THEN
        UPDATE project
        SET owner_id = NEW.owner_id
        WHERE opportunity_id = NEW.id AND owner_id IS DISTINCT FROM NEW.owner_id;

        UPDATE opportunity_activity
        SET owner_id = NEW.owner_id
        WHERE opportunity_id = NEW.id AND owner_id IS DISTINCT FROM NEW.owner_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_opportunity_cascade_owner ON opportunity;

CREATE TRIGGER trg_opportunity_cascade_owner
    AFTER UPDATE OF owner_id ON opportunity
    FOR EACH ROW EXECUTE FUNCTION _cascade_owner_from_opportunity();

CREATE OR REPLACE FUNCTION _inherit_owner_from_account()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.account_id IS NOT NULL THEN
        SELECT owner_id INTO NEW.owner_id
        FROM account WHERE id = NEW.account_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION _inherit_owner_from_opportunity()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
    IF NEW.opportunity_id IS NOT NULL THEN
        SELECT owner_id INTO NEW.owner_id
        FROM opportunity WHERE id = NEW.opportunity_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_contact_inherit_owner ON contact;

CREATE TRIGGER trg_contact_inherit_owner
    BEFORE INSERT OR UPDATE OF account_id ON contact
    FOR EACH ROW EXECUTE FUNCTION _inherit_owner_from_account();

DROP TRIGGER IF EXISTS trg_opportunity_inherit_owner ON opportunity;

CREATE TRIGGER trg_opportunity_inherit_owner
    BEFORE INSERT OR UPDATE OF account_id ON opportunity
    FOR EACH ROW EXECUTE FUNCTION _inherit_owner_from_account();

DROP TRIGGER IF EXISTS trg_project_inherit_owner ON project;

CREATE TRIGGER trg_project_inherit_owner
    BEFORE INSERT OR UPDATE OF opportunity_id ON project
    FOR EACH ROW EXECUTE FUNCTION _inherit_owner_from_opportunity();

DROP TRIGGER IF EXISTS trg_opportunity_activity_inherit_owner ON opportunity_activity;

CREATE TRIGGER trg_opportunity_activity_inherit_owner
    BEFORE INSERT OR UPDATE OF opportunity_id ON opportunity_activity
    FOR EACH ROW EXECUTE FUNCTION _inherit_owner_from_opportunity();

-- ========================= STORAGE SYNC =========================

CREATE OR REPLACE FUNCTION _sync_account_storage_owner()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF OLD.owner_id IS DISTINCT FROM NEW.owner_id THEN
        UPDATE storage.objects
        SET metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{owner_id}', to_jsonb(NEW.owner_id::text))
        WHERE bucket_id = 'resources'
          AND name IN (NEW.pdf_path, NEW.excel_path);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_account_storage_sync ON account;

CREATE TRIGGER trg_account_storage_sync
    AFTER UPDATE OF owner_id ON account
    FOR EACH ROW EXECUTE FUNCTION _sync_account_storage_owner();

CREATE OR REPLACE FUNCTION _sync_contact_storage_owner()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF OLD.owner_id IS DISTINCT FROM NEW.owner_id THEN
        UPDATE storage.objects
        SET metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{owner_id}', to_jsonb(NEW.owner_id::text))
        WHERE bucket_id = 'resources'
          AND name IN (NEW.avatar_path, NEW.document_path);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_contact_storage_sync ON contact;

CREATE TRIGGER trg_contact_storage_sync
    AFTER UPDATE OF owner_id ON contact
    FOR EACH ROW EXECUTE FUNCTION _sync_contact_storage_owner();

CREATE OR REPLACE FUNCTION _sync_opportunity_storage_owner()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF OLD.owner_id IS DISTINCT FROM NEW.owner_id THEN
        UPDATE storage.objects
        SET metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{owner_id}', to_jsonb(NEW.owner_id::text))
        WHERE bucket_id = 'resources'
          AND name IN (NEW.proposal_path, NEW.contract_path);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_opportunity_storage_sync ON opportunity;

CREATE TRIGGER trg_opportunity_storage_sync
    AFTER UPDATE OF owner_id ON opportunity
    FOR EACH ROW EXECUTE FUNCTION _sync_opportunity_storage_owner();

CREATE OR REPLACE FUNCTION _sync_project_storage_owner()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    IF OLD.owner_id IS DISTINCT FROM NEW.owner_id THEN
        UPDATE storage.objects
        SET metadata = jsonb_set(COALESCE(metadata, '{}'::jsonb), '{owner_id}', to_jsonb(NEW.owner_id::text))
        WHERE bucket_id = 'resources'
          AND name IN (NEW.brief_path, NEW.spec_path);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_project_storage_sync ON project;

CREATE TRIGGER trg_project_storage_sync
    AFTER UPDATE OF owner_id ON project
    FOR EACH ROW EXECUTE FUNCTION _sync_project_storage_owner();