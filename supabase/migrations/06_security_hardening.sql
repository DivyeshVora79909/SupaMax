-- =========================================================
-- 1. SETUP BYPASS FOR SIGNUP & DEFAULT SEEDING
-- =========================================================

CREATE OR REPLACE FUNCTION public.before_auth_user_created()
RETURNS TRIGGER AS $$
DECLARE
    v_org_id UUID;
    v_role_owner_id UUID;
    v_role_member_id UUID;
    v_pipeline_id UUID;
    v_perms text[];
BEGIN
    -- If org_id is already set in app_metadata, this user is being invited/created in an existing org.
    -- We don't want to create a new org for them.
    IF (new.raw_app_meta_data->>'org_id') IS NOT NULL THEN
        RAISE LOG 'User % already has org_id %, skipping org creation', new.id, new.raw_app_meta_data->>'org_id';
        RETURN new;
    END IF;

    RAISE LOG 'BEFORE Signup trigger fired for user: %', new.id;
    
    v_org_id := gen_random_uuid();
    v_role_owner_id := gen_random_uuid();
    v_role_member_id := gen_random_uuid();
    v_pipeline_id := gen_random_uuid();

    -- 1. Create Organization
    INSERT INTO public.organizations (id, name, plan)
    VALUES (v_org_id, COALESCE(new.raw_user_meta_data->>'company_name', 'My Organization'), 'free');
    
    -- 2. SUBSCRIBE TO MODULES
    INSERT INTO public.org_subscriptions (org_id, module_code) VALUES 
    (v_org_id, 'core'),
    (v_org_id, 'crm');

    -- 3. Create Default Activity Types
    INSERT INTO public.crm_activity_types (org_id, name, icon, color, is_system) VALUES
    (v_org_id, 'Call', 'phone', '#3b82f6', TRUE),
    (v_org_id, 'Email', 'mail', '#eab308', TRUE),
    (v_org_id, 'Meeting', 'users', '#a855f7', TRUE),
    (v_org_id, 'Task', 'check-square', '#22c55e', TRUE),
    (v_org_id, 'Lunch', 'coffee', '#f97316', TRUE);

    -- 4. Create Default Sales Pipeline
    INSERT INTO public.crm_pipelines (id, org_id, name, is_default) 
    VALUES (v_pipeline_id, v_org_id, 'Sales Pipeline', TRUE);

    -- 5. Create Default Stages
    INSERT INTO public.crm_pipeline_stages (pipeline_id, name, display_order, win_probability, type) VALUES
    (v_pipeline_id, 'Lead', 1, 10, 'open'),
    (v_pipeline_id, 'Qualified', 2, 40, 'open'),
    (v_pipeline_id, 'Proposal', 3, 70, 'open'),
    (v_pipeline_id, 'Negotiation', 4, 90, 'open'),
    (v_pipeline_id, 'Won', 5, 100, 'won'),
    (v_pipeline_id, 'Lost', 6, 0, 'lost');

    -- 6. Create System Roles
    INSERT INTO public.roles (id, org_id, name, description, is_system) VALUES (v_role_owner_id, v_org_id, 'Owner', 'Full access', TRUE);
    INSERT INTO public.roles (id, org_id, name, description, is_system) VALUES (v_role_member_id, v_org_id, 'Member', 'Standard access', TRUE);

    -- 7. Assign Permissions
    INSERT INTO public.role_permissions (role_id, permission_id) 
    SELECT v_role_owner_id, id FROM public.permissions;
    
    SELECT array_agg(code) INTO v_perms FROM public.permissions;

    INSERT INTO public.role_permissions (role_id, permission_id) SELECT v_role_member_id, id FROM public.permissions WHERE code LIKE '%.read';

    -- 8. Set raw_app_meta_data
    new.raw_app_meta_data := jsonb_set(
        COALESCE(new.raw_app_meta_data, '{}'::jsonb),
        '{org_id}',
        to_jsonb(v_org_id)
    );
    new.raw_app_meta_data := jsonb_set(
        new.raw_app_meta_data,
        '{role_id}',
        to_jsonb(v_role_owner_id)
    );
    new.raw_app_meta_data := jsonb_set(
        new.raw_app_meta_data,
        '{permissions}',
        to_jsonb(v_perms)
    );

    RAISE LOG 'BEFORE Signup trigger completed for user: %', new.id;
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.after_auth_user_created()
RETURNS TRIGGER AS $$
DECLARE
    v_role_name TEXT;
    v_org_id UUID;
    v_role_id UUID;
BEGIN
    v_org_id := (new.raw_app_meta_data->>'org_id')::uuid;
    v_role_id := (new.raw_app_meta_data->>'role_id')::uuid;

    IF v_org_id IS NULL OR v_role_id IS NULL THEN
        RETURN new;
    END IF;

    RAISE LOG 'AFTER Signup trigger fired for user: %', new.id;

    -- Create Profile
    INSERT INTO public.profiles (id, full_name, org_id, role_id)
    VALUES (
        new.id, 
        new.raw_user_meta_data->>'full_name', 
        v_org_id, 
        v_role_id
    ) ON CONFLICT (id) DO NOTHING;

    -- Check if this is the Owner role
    SELECT name INTO v_role_name FROM public.roles WHERE id = v_role_id;

    IF v_role_name = 'Owner' THEN
        -- Update Org Owner
        UPDATE public.organizations SET owner_profile_id = new.id WHERE id = v_org_id AND owner_profile_id IS NULL;

        -- Init Closure
        INSERT INTO public.role_closure (org_id, parent_role_id, child_role_id, depth)
        VALUES (v_org_id, v_role_id, v_role_id, 0)
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Re-attach the triggers
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS before_auth_user_created_trigger ON auth.users;
DROP TRIGGER IF EXISTS after_auth_user_created_trigger ON auth.users;

CREATE TRIGGER before_auth_user_created_trigger
  BEFORE INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.before_auth_user_created();

CREATE TRIGGER after_auth_user_created_trigger
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.after_auth_user_created();


-- =========================================================
-- 2. HELPER: GET USER PERMISSIONS
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_current_user_permission_ids()
RETURNS uuid[] 
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE
    v_role_id uuid;
    v_perms uuid[];
BEGIN
    SELECT role_id INTO v_role_id FROM public.profiles WHERE id = auth.uid();
    SELECT array_agg(permission_id) INTO v_perms FROM public.role_permissions WHERE role_id = v_role_id;
    RETURN COALESCE(v_perms, '{}'::uuid[]);
END;
$$;

-- =========================================================
-- 3. TRIGGER: SUBSET RULE FOR ROLE ASSIGNMENT
-- =========================================================

CREATE OR REPLACE FUNCTION public.enforce_role_assignment_subset()
RETURNS TRIGGER AS $$
DECLARE
    doer_perms uuid[];
    target_role_perms uuid[];
BEGIN
    IF current_setting('app.is_system_action', true) = 'true' OR auth.uid() IS NULL THEN RETURN NEW; END IF;
    IF (TG_OP = 'UPDATE' AND OLD.role_id = NEW.role_id) THEN RETURN NEW; END IF;

    doer_perms := public.get_current_user_permission_ids();

    SELECT array_agg(permission_id) INTO target_role_perms
    FROM public.role_permissions WHERE role_id = NEW.role_id;
    target_role_perms := COALESCE(target_role_perms, '{}'::uuid[]);

    IF NOT (target_role_perms <@ doer_perms) THEN
        RAISE EXCEPTION 'Security Violation: You cannot assign a role that has permissions you do not possess.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_role_assignment_power
BEFORE INSERT OR UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.enforce_role_assignment_subset();

-- =========================================================
-- 4. TRIGGER: SUBSET RULE FOR EDITING PERMISSIONS
-- =========================================================

CREATE OR REPLACE FUNCTION public.enforce_permission_grant_subset()
RETURNS TRIGGER AS $$
DECLARE
    doer_perms uuid[];
BEGIN
    IF current_setting('app.is_system_action', true) = 'true' OR auth.uid() IS NULL THEN RETURN NEW; END IF;
    doer_perms := public.get_current_user_permission_ids();
    IF NOT (ARRAY[NEW.permission_id] <@ doer_perms) THEN
         RAISE EXCEPTION 'Security Violation: You cannot grant a permission you do not possess.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_permission_grant_power
BEFORE INSERT ON public.role_permissions
FOR EACH ROW EXECUTE FUNCTION public.enforce_permission_grant_subset();

-- =========================================================
-- 5. SECURE HIERARCHY
-- =========================================================

CREATE OR REPLACE FUNCTION public.is_org_owner(org_id uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (SELECT 1 FROM public.organizations WHERE id = org_id AND owner_profile_id = auth.uid());
$$;

CREATE POLICY "Owner Manage Hierarchy" ON public.role_hierarchy FOR ALL TO authenticated
USING ( public.is_org_owner(org_id) ) WITH CHECK ( public.is_org_owner(org_id) );

CREATE OR REPLACE FUNCTION check_hierarchy_owner_safety() RETURNS TRIGGER AS $$
DECLARE v_owner_role_id UUID;
BEGIN
    SELECT id INTO v_owner_role_id FROM public.roles WHERE org_id = NEW.org_id AND name = 'Owner';
    IF NEW.child_role_id = v_owner_role_id THEN
        RAISE EXCEPTION 'Hierarchy Violation: The Owner role cannot be a child of another role.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER protect_owner_role_node
BEFORE INSERT OR UPDATE ON public.role_hierarchy
FOR EACH ROW EXECUTE FUNCTION check_hierarchy_owner_safety();