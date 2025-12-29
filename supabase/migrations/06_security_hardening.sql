-- =========================================================
-- 1. SETUP BYPASS FOR SIGNUP
-- We modify the signup handler to flag itself as a "System Action"
-- so triggers don't block the initial Owner creation.
-- =========================================================

CREATE OR REPLACE FUNCTION handle_new_user_signup()
RETURNS TRIGGER AS $$
DECLARE
    v_org_id UUID;
    v_role_owner_id UUID;
    v_role_member_id UUID;
BEGIN
    -- [SECURITY] Set a session variable to bypass subset triggers during signup
    PERFORM set_config('app.is_system_action', 'true', true);

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

    -- Update Org Owner
    UPDATE public.organizations SET owner_profile_id = new.id WHERE id = v_org_id;

    -- Init Closure
    INSERT INTO public.role_closure (org_id, parent_role_id, child_role_id, depth)
    VALUES (v_org_id, v_role_owner_id, v_role_owner_id, 0);

    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =========================================================
-- 2. HELPER: GET USER PERMISSIONS
-- Returns an array of permission IDs that the current user holds
-- =========================================================

CREATE OR REPLACE FUNCTION public.get_current_user_permission_ids()
RETURNS uuid[] 
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE
    v_role_id uuid;
    v_perms uuid[];
BEGIN
    -- Get current user's role
    SELECT role_id INTO v_role_id FROM public.profiles WHERE id = auth.uid();
    
    -- Get permission IDs for that role
    SELECT array_agg(permission_id) INTO v_perms
    FROM public.role_permissions
    WHERE role_id = v_role_id;

    RETURN COALESCE(v_perms, '{}'::uuid[]);
END;
$$;

-- =========================================================
-- 3. TRIGGER: SUBSET RULE FOR ROLE ASSIGNMENT (PROFILES)
-- Prevents a user from assigning a role more powerful than their own.
-- =========================================================

CREATE OR REPLACE FUNCTION public.enforce_role_assignment_subset()
RETURNS TRIGGER AS $$
DECLARE
    doer_perms uuid[];
    target_role_perms uuid[];
BEGIN
    -- 1. Skip if System Action (Signup) or Service Role
    IF current_setting('app.is_system_action', true) = 'true' OR auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    -- 2. Only check if role_id is changing
    IF (TG_OP = 'UPDATE' AND OLD.role_id = NEW.role_id) THEN
        RETURN NEW;
    END IF;

    -- 3. Get Doer's Permissions
    doer_perms := public.get_current_user_permission_ids();

    -- 4. Get Permissions of the Role being assigned
    SELECT array_agg(permission_id) INTO target_role_perms
    FROM public.role_permissions
    WHERE role_id = NEW.role_id;

    target_role_perms := COALESCE(target_role_perms, '{}'::uuid[]);

    -- 5. Check: Doer must have ALL permissions that the target role has
    -- "target_role_perms <@ doer_perms" means "is target a subset of doer?"
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
-- Prevents a user from adding a permission to a role if they don't have it.
-- =========================================================

CREATE OR REPLACE FUNCTION public.enforce_permission_grant_subset()
RETURNS TRIGGER AS $$
DECLARE
    doer_perms uuid[];
BEGIN
    -- 1. Skip if System Action
    IF current_setting('app.is_system_action', true) = 'true' OR auth.uid() IS NULL THEN
        RETURN NEW;
    END IF;

    -- 2. Get Doer's Permissions
    doer_perms := public.get_current_user_permission_ids();

    -- 3. Check: Can only grant what you have
    -- NEW.permission_id must exist in doer_perms
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
-- 5. SECURE HIERARCHY (OWNER ONLY)
-- Only the Organization Owner can edit the hierarchy structure.
-- =========================================================

-- Helper to check if current user is Org Owner
CREATE OR REPLACE FUNCTION public.is_org_owner(org_id uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.organizations 
        WHERE id = org_id 
        AND owner_profile_id = auth.uid()
    );
$$;

-- Add Write Policies to Hierarchy
CREATE POLICY "Owner Manage Hierarchy" ON public.role_hierarchy
FOR ALL TO authenticated
USING (
    public.is_org_owner(org_id)
)
WITH CHECK (
    public.is_org_owner(org_id)
);

-- Validation: Owner Role cannot be a Child
-- This prevents locking the owner out or creating loops involving the root.
CREATE OR REPLACE FUNCTION check_hierarchy_owner_safety() RETURNS TRIGGER AS $$
DECLARE
    v_owner_role_id UUID;
BEGIN
    -- Find the 'Owner' role ID for this org
    SELECT id INTO v_owner_role_id FROM public.roles 
    WHERE org_id = NEW.org_id AND name = 'Owner';

    IF NEW.child_role_id = v_owner_role_id THEN
        RAISE EXCEPTION 'Hierarchy Violation: The Owner role cannot be a child of another role.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER protect_owner_role_node
BEFORE INSERT OR UPDATE ON public.role_hierarchy
FOR EACH ROW EXECUTE FUNCTION check_hierarchy_owner_safety();