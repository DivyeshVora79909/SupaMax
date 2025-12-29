-- 1. HIERARCHY MAINTENANCE
CREATE OR REPLACE FUNCTION public.rebuild_role_closure() RETURNS TRIGGER AS $$
DECLARE v_org uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN v_org := OLD.org_id; ELSE v_org := COALESCE(NEW.org_id, OLD.org_id); END IF;
  DELETE FROM public.role_closure WHERE org_id = v_org;
  WITH RECURSIVE hierarchy AS (
    SELECT org_id, parent_role_id, child_role_id, 1 AS depth FROM public.role_hierarchy WHERE org_id = v_org
    UNION ALL
    SELECT e.org_id, h.parent_role_id, e.child_role_id, h.depth + 1
    FROM hierarchy h JOIN public.role_hierarchy e ON h.child_role_id = e.parent_role_id WHERE e.org_id = v_org
  )
  INSERT INTO public.role_closure (org_id, parent_role_id, child_role_id, depth)
  SELECT DISTINCT org_id, parent_role_id, child_role_id, depth FROM hierarchy ON CONFLICT DO NOTHING;
  INSERT INTO public.role_closure (org_id, parent_role_id, child_role_id, depth)
  SELECT org_id, id, id, 0 FROM public.roles WHERE org_id = v_org ON CONFLICT DO NOTHING;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_hierarchy_change AFTER INSERT OR UPDATE OR DELETE ON public.role_hierarchy
FOR EACH ROW EXECUTE FUNCTION public.rebuild_role_closure();

CREATE OR REPLACE FUNCTION check_hierarchy_cycle() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.parent_role_id = NEW.child_role_id THEN RAISE EXCEPTION 'Role cannot be its own parent.'; END IF;
    IF EXISTS (SELECT 1 FROM public.role_closure WHERE parent_role_id = NEW.child_role_id AND child_role_id = NEW.parent_role_id) THEN
        RAISE EXCEPTION 'Cyclic dependency detected.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_acyclic_hierarchy BEFORE INSERT OR UPDATE ON public.role_hierarchy
FOR EACH ROW EXECUTE FUNCTION check_hierarchy_cycle();

-- =========================================================
-- 2. AUTOMATIC METADATA (Ownership Assignment)
-- =========================================================
CREATE OR REPLACE FUNCTION set_rls_metadata() RETURNS TRIGGER AS $$
DECLARE user_meta RECORD;
BEGIN
    SELECT org_id, role_id INTO user_meta FROM public.profiles WHERE id = auth.uid();
    
    -- Safety check: if running via backend without session, this might be null
    IF user_meta.org_id IS NOT NULL THEN
        NEW.owner_user_id := auth.uid();
        NEW.owner_tenant_id := user_meta.org_id;
        NEW.owner_role_id := user_meta.role_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach to CRM Tables
CREATE TRIGGER set_companies_meta BEFORE INSERT ON public.crm_companies FOR EACH ROW EXECUTE FUNCTION set_rls_metadata();
CREATE TRIGGER set_contacts_meta BEFORE INSERT ON public.crm_contacts FOR EACH ROW EXECUTE FUNCTION set_rls_metadata();
CREATE TRIGGER set_deals_meta BEFORE INSERT ON public.crm_deals FOR EACH ROW EXECUTE FUNCTION set_rls_metadata();
CREATE TRIGGER set_activities_meta BEFORE INSERT ON public.crm_activities FOR EACH ROW EXECUTE FUNCTION set_rls_metadata();
CREATE TRIGGER set_notes_meta BEFORE INSERT ON public.crm_notes FOR EACH ROW EXECUTE FUNCTION set_rls_metadata();

-- Trigger for Trigger 3 is handled in migration 06