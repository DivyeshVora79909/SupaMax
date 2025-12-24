-- 1. HIERARCHY MAINTENANCE
CREATE OR REPLACE FUNCTION public.rebuild_role_closure()
RETURNS TRIGGER AS $$
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

-- Prevent Cycles
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

-- 2. AUTOMATIC METADATA
CREATE OR REPLACE FUNCTION set_rls_metadata() RETURNS TRIGGER AS $$
DECLARE user_meta RECORD;
BEGIN
    SELECT org_id, role_id INTO user_meta FROM public.profiles WHERE id = auth.uid();
    NEW.owner_user_id := auth.uid();
    NEW.owner_tenant_id := user_meta.org_id;
    NEW.owner_role_id := user_meta.role_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_projects_meta BEFORE INSERT ON public.projects FOR EACH ROW EXECUTE FUNCTION set_rls_metadata();
CREATE TRIGGER set_tasks_meta BEFORE INSERT ON public.tasks FOR EACH ROW EXECUTE FUNCTION set_rls_metadata();

-- 3. AUTH SIGNUP HANDLER
CREATE OR REPLACE FUNCTION handle_new_user_signup()
RETURNS TRIGGER AS $$
DECLARE
    v_org_id UUID;
    v_role_owner_id UUID;
    v_role_member_id UUID;
BEGIN
    -- Create Organization
    INSERT INTO public.organizations (name, plan)
    VALUES (COALESCE(new.raw_user_meta_data->>'company_name', 'My Organization'), 'free')
    RETURNING id INTO v_org_id;

    -- Create System Roles
    INSERT INTO public.roles (org_id, name, description, is_system) VALUES (v_org_id, 'Owner', 'Full access', TRUE) RETURNING id INTO v_role_owner_id;
    INSERT INTO public.roles (org_id, name, description, is_system) VALUES (v_org_id, 'Member', 'Standard access', TRUE) RETURNING id INTO v_role_member_id;

    -- Assign Permissions
    INSERT INTO public.role_permissions (role_id, permission_id) SELECT v_role_owner_id, id FROM public.permissions;
    INSERT INTO public.role_permissions (role_id, permission_id) SELECT v_role_member_id, id FROM public.permissions WHERE code LIKE '%.read';

    -- Create Profile
    INSERT INTO public.profiles (id, full_name, org_id, role_id)
    VALUES (new.id, new.raw_user_meta_data->>'full_name', v_org_id, v_role_owner_id);

    -- Update Org Owner (Circular Link)
    UPDATE public.organizations SET owner_profile_id = new.id WHERE id = v_org_id;

    -- Init Closure
    INSERT INTO public.role_closure (org_id, parent_role_id, child_role_id, depth)
    VALUES (v_org_id, v_role_owner_id, v_role_owner_id, 0);

    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user_signup();