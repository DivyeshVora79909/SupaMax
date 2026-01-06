-- 0. SECURITY HELPERS
CREATE OR REPLACE FUNCTION public.get_my_role_id() 
RETURNS UUID LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$ BEGIN
    RETURN (SELECT role_id FROM public.profiles WHERE id = auth.uid());
END;
 $$;

CREATE OR REPLACE FUNCTION public.check_root_or_subordinate(target_role UUID) 
RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$ DECLARE
    v_my_role UUID;
    v_is_root BOOLEAN;
    v_is_subordinate BOOLEAN;
BEGIN
    IF auth.role() = 'service_role' THEN RETURN TRUE; END IF;

    SELECT role_id, r.is_root INTO v_my_role, v_is_root
    FROM public.profiles p 
    JOIN public.roles r ON p.role_id = r.id 
    WHERE p.id = auth.uid();

    IF v_is_root THEN RETURN TRUE; END IF;

    SELECT EXISTS(
        SELECT 1 FROM public.role_closure 
        WHERE ancestor_id = v_my_role AND descendant_id = target_role
    ) INTO v_is_subordinate;

    RETURN v_is_subordinate;
END;
 $$;

-- 1. PROVISION TENANT
CREATE OR REPLACE FUNCTION public.provision_tenant(
    p_name TEXT,
    p_slug TEXT,
    p_admin_email TEXT,
    p_role_name TEXT
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$ 
DECLARE
    v_tenant_id UUID;
    v_role_id UUID;
    v_invite_id UUID;
BEGIN
    IF auth.role() != 'service_role' AND current_user != 'postgres' THEN
        RAISE EXCEPTION 'Access Denied: Only Service Role can provision tenants.';
    END IF;

    -- 1. Create Tenant (Explicitly Generate UUID to avoid NULL issues)
    v_tenant_id := gen_random_uuid();
    INSERT INTO public.tenants (id, name, slug) 
    VALUES (v_tenant_id, p_name, p_slug);

    -- 2. Create Root Role (Explicitly Generate UUID)
    v_role_id := gen_random_uuid();
    INSERT INTO public.roles (id, tenant_id, name, is_root) 
    VALUES (v_role_id, v_tenant_id, p_role_name, TRUE);

    -- 3. Assign ALL Permissions (Wildcard approach)
    INSERT INTO public.role_permissions (role_id, permission_code)
    SELECT v_role_id, code FROM public.permissions;

    -- 4. Create Invitation (Explicitly Generate UUID)
    v_invite_id := gen_random_uuid();
    INSERT INTO public.invitations (id, email, role_id, tenant_id, invited_by)
    VALUES (v_invite_id, p_admin_email, v_role_id, v_tenant_id, auth.uid());

    -- 5. Return Data
    RETURN json_build_object(
        'tenant_id', v_tenant_id,
        'role_id', v_role_id,
        'invite_id', v_invite_id,
        'message', 'Tenant provisioned successfully. Invitation created.'
    );
END;
 $$;

-- 2. SECURE INVITE HELPER
CREATE OR REPLACE FUNCTION public.invite_user_secure(p_email TEXT, p_role_id UUID)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$ 
DECLARE
    v_tenant_id UUID;
    v_role_name TEXT;
    v_my_role_id UUID;
    v_id UUID;
BEGIN
    SELECT tenant_id, name INTO v_tenant_id, v_role_name 
    FROM public.roles WHERE id = p_role_id;
    
    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'Invalid Role: Role ID % does not exist.', p_role_id;
    END IF;

    SELECT tenant_id INTO v_my_role_id FROM public.profiles WHERE id = auth.uid();
    
    IF v_my_role_id IS NULL OR v_my_role_id != v_tenant_id THEN
        RAISE EXCEPTION 'Security Violation: Cannot invite users to other tenants.';
    END IF;

    INSERT INTO public.invitations (email, role_id, tenant_id, invited_by)
    VALUES (p_email, p_role_id, v_tenant_id, auth.uid())
    RETURNING id INTO v_id;
    
    RETURN json_build_object('id', v_id, 'success', true);
END;
 $$;

-- 3. TENANT FACTORY
CREATE OR REPLACE FUNCTION public.create_tenant(p_name TEXT, p_slug TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$ 
DECLARE
    v_tenant_id UUID;
    v_admin_role_id UUID;
BEGIN
    IF auth.role() != 'service_role' AND current_user != 'postgres' THEN 
        RAISE EXCEPTION 'Access Denied: Service Role required.'; 
    END IF;

    INSERT INTO public.tenants (name, slug) VALUES (p_name, p_slug) RETURNING id INTO v_tenant_id;
    INSERT INTO public.roles (tenant_id, name, is_root) VALUES (v_tenant_id, 'Tenant Owner', TRUE) RETURNING id INTO v_admin_role_id;
    
    INSERT INTO public.role_permissions (role_id, permission_code)
    SELECT v_admin_role_id, code FROM public.permissions;
    
    RETURN v_tenant_id;
END;
 $$;

-- 4. ACCESS CONTROL HELPERS
CREATE OR REPLACE FUNCTION public.has_permission(p_code text) RETURNS boolean 
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$ 
BEGIN
    -- Immediate check against DB for revocation support
    RETURN EXISTS (
        SELECT 1 FROM public.role_permissions rp
        JOIN public.profiles p ON p.role_id = rp.role_id
        WHERE p.id = auth.uid() AND rp.permission_code = p_code
    );
END;
 $$;

CREATE OR REPLACE FUNCTION public.is_in_my_tenant(p_tenant_id uuid) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$   
DECLARE v_tid uuid;
BEGIN
    IF auth.role() = 'service_role' THEN RETURN TRUE; END IF;
    -- Check DB for accuracy
    SELECT tenant_id INTO v_tid FROM public.profiles WHERE id = auth.uid();
    RETURN p_tenant_id = v_tid;
END;
 $$;

-- 4.2 Resource Access Helper
CREATE OR REPLACE FUNCTION public.check_resource_access(
    p_tenant_id uuid,
    p_visibility visibility_mode, 
    p_owner_id uuid,
    p_owner_role_id uuid,
    p_resource_prefix text,
    p_op text
) RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$ 
DECLARE
    subordinates uuid[];
    my_tid uuid;
    my_role_id uuid;
    req_perm text;
BEGIN
    IF auth.role() = 'service_role' THEN RETURN TRUE; END IF;

    -- Always check DB for immediate consistency
    SELECT tenant_id, role_id INTO my_tid, my_role_id FROM public.profiles WHERE id = auth.uid();
    
    -- 1. Tenant Isolation (Strict)
    IF p_tenant_id IS NULL OR my_tid IS NULL OR p_tenant_id != my_tid THEN RETURN FALSE; END IF;

    IF p_op = 'insert' THEN 
        RETURN public.has_permission(p_resource_prefix || ':c');
    END IF;
    
    IF p_op = 'select' THEN
        IF p_visibility IN ('PRIVATE', 'CONTROLLED') THEN 
            IF p_owner_id = auth.uid() THEN RETURN TRUE; END IF;
            -- Check if I am an ancestor of the owner's role
            RETURN EXISTS (
                SELECT 1 FROM public.role_closure 
                WHERE ancestor_id = my_role_id AND descendant_id = p_owner_role_id
                AND ancestor_id != descendant_id -- Sibling isolation: cannot see same-role private data
            );
        ELSE 
            RETURN public.has_permission(p_resource_prefix || ':r');
        END IF;
    END IF;

    IF p_op = 'update' THEN
        IF p_visibility IN ('PRIVATE', 'CONTROLLED') THEN 
            IF p_owner_id = auth.uid() THEN RETURN TRUE; END IF;
            RETURN EXISTS (
                SELECT 1 FROM public.role_closure 
                WHERE ancestor_id = my_role_id AND descendant_id = p_owner_role_id
                AND ancestor_id != descendant_id
            );
        ELSE 
            IF p_owner_id = auth.uid() THEN RETURN TRUE; END IF;
            RETURN public.has_permission(p_resource_prefix || ':u');
        END IF;
    END IF;

    IF p_op = 'delete' THEN
        IF p_owner_id = auth.uid() THEN RETURN TRUE; END IF;
        IF p_visibility IN ('PRIVATE', 'CONTROLLED') THEN
             RETURN EXISTS (
                SELECT 1 FROM public.role_closure 
                WHERE ancestor_id = my_role_id AND descendant_id = p_owner_role_id
                AND ancestor_id != descendant_id
            );
        END IF;
        RETURN public.has_permission(p_resource_prefix || ':d');
    END IF;

    RETURN FALSE;
END;
 $$;

-- G. Protect Profile Role
CREATE OR REPLACE FUNCTION public.prevent_profile_role_update() RETURNS TRIGGER AS $$ 
BEGIN
    IF auth.role() = 'service_role' THEN RETURN NEW; END IF;
    
    -- Only allow Owner (Root) to change roles
    IF NOT EXISTS (
        SELECT 1 FROM public.roles r 
        JOIN public.profiles p ON p.role_id = r.id 
        WHERE p.id = auth.uid() AND r.is_root = TRUE
    ) THEN
        IF NEW.role_id != OLD.role_id THEN
            RAISE EXCEPTION 'Access Denied: You cannot change your own role or others roles unless you are an Owner.';
        END IF;
    END IF;
    
    RETURN NEW;
END;
 $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS protect_profile_role_trigger ON public.profiles;
CREATE TRIGGER protect_profile_role_trigger BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.prevent_profile_role_update();

-- 5. TRIGGERS

-- A. Auto-Populate Tenant ID for Roles (Fixes Frontend Role Creation)
CREATE OR REPLACE FUNCTION public.populate_role_tenant() 
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$ 
BEGIN
    NEW.tenant_id := (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid;

    IF NEW.tenant_id IS NULL THEN
        SELECT tenant_id INTO NEW.tenant_id FROM public.profiles WHERE id = auth.uid();
    END IF;
    
    RETURN NEW;
END;
 $$;

DROP TRIGGER IF EXISTS set_role_tenant ON public.roles;
CREATE TRIGGER set_role_tenant 
BEFORE INSERT ON public.roles 
FOR EACH ROW 
EXECUTE FUNCTION public.populate_role_tenant();

-- B. Auto-Populate Resources (Deals, etc)
CREATE OR REPLACE FUNCTION public.populate_resource_fields() RETURNS TRIGGER AS $$ BEGIN
    IF auth.role() = 'service_role' THEN
        RETURN NEW;
    END IF;

    NEW.tenant_id := (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid;
    NEW.owner_id := auth.uid();
    NEW.owner_role_id := (auth.jwt() -> 'app_metadata' ->> 'role_id')::uuid;
    RETURN NEW;
END;
 $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS set_deals_metadata ON public.deals;
CREATE TRIGGER populate_deals_fields BEFORE INSERT ON public.deals FOR EACH ROW EXECUTE FUNCTION public.populate_resource_fields();

-- C. Prevent Permission Escalation
CREATE OR REPLACE FUNCTION public.prevent_permission_escalation() RETURNS TRIGGER AS $$ DECLARE my_perms text[];
BEGIN
    IF auth.role() = 'service_role' THEN RETURN NEW; END IF;
    my_perms := ARRAY(SELECT jsonb_array_elements_text(COALESCE(auth.jwt() -> 'app_metadata' -> 'permissions', '[]'::jsonb)));
    IF NOT (NEW.permission_code = ANY(my_perms)) THEN RAISE EXCEPTION 'Access Denied: You cannot grant a permission you do not possess.'; END IF;
    RETURN NEW;
END;
 $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS check_permission_escalation ON public.role_permissions;
CREATE TRIGGER check_permission_escalation BEFORE INSERT ON public.role_permissions FOR EACH ROW EXECUTE FUNCTION public.prevent_permission_escalation();

-- D. FIX: Prevent Role Escalation (Invite) - Checks DB if Root
CREATE OR REPLACE FUNCTION public.prevent_role_escalation_invite() RETURNS TRIGGER AS $$ DECLARE v_is_root BOOLEAN;
BEGIN
    IF auth.role() = 'service_role' THEN RETURN NEW; END IF;

    SELECT is_root INTO v_is_root 
    FROM public.roles r 
    JOIN public.profiles p ON p.role_id = r.id 
    WHERE p.id = auth.uid();
    
    IF v_is_root THEN RETURN NEW; END IF;

    IF NOT public.check_root_or_subordinate(NEW.role_id) THEN 
        RAISE EXCEPTION 'Access Denied: You can only assign roles that are below you.'; 
    END IF;
    
    RETURN NEW;
END;
 $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS check_role_escalation_invite ON public.invitations;
CREATE TRIGGER check_role_escalation_invite BEFORE INSERT ON public.invitations FOR EACH ROW EXECUTE FUNCTION public.prevent_role_escalation_invite();

-- D2. Auto-Populate Invitations
CREATE OR REPLACE FUNCTION public.populate_invitation_fields() RETURNS TRIGGER AS $$ 
BEGIN
    IF auth.role() = 'service_role' THEN RETURN NEW; END IF;
    NEW.tenant_id := (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid;
    NEW.invited_by := auth.uid();
    RETURN NEW;
END;
 $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS set_invitation_metadata ON public.invitations;
CREATE TRIGGER set_invitation_metadata BEFORE INSERT ON public.invitations FOR EACH ROW EXECUTE FUNCTION public.populate_invitation_fields();

-- E. Protect Root Role
CREATE OR REPLACE FUNCTION public.protect_root_role() RETURNS TRIGGER AS $$ BEGIN
    IF auth.role() = 'service_role' THEN RETURN OLD; END IF;
    IF OLD.is_root THEN RAISE EXCEPTION 'Constraint Violation: Root Role cannot be modified or deleted.'; END IF;
    RETURN OLD;
END;
 $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS protect_root_role_trigger ON public.roles;
CREATE TRIGGER protect_root_role_trigger BEFORE DELETE OR UPDATE ON public.roles FOR EACH ROW EXECUTE FUNCTION public.protect_root_role();

-- F. Auto-Populate Tenant ID for Roles (FIXED)
CREATE OR REPLACE FUNCTION public.populate_role_tenant() 
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path = public 
AS $$ 
BEGIN
    IF NEW.tenant_id IS NOT NULL THEN 
        RETURN NEW; 
    END IF;

    NEW.tenant_id := (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid;

    IF NEW.tenant_id IS NULL THEN
        SELECT tenant_id INTO NEW.tenant_id FROM public.profiles WHERE id = auth.uid();
    END IF;
    RETURN NEW;
END;
 $$;

DROP TRIGGER IF EXISTS set_role_tenant ON public.roles;
CREATE TRIGGER set_role_tenant BEFORE INSERT ON public.roles FOR EACH ROW EXECUTE FUNCTION public.populate_role_tenant();