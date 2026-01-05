-- ). PROVISION TENANT (Atomic Transaction)
-- Usage: rpc('provision_tenant', { 
--   p_name: 'Acme Corp', 
--   p_slug: 'acme', 
--   p_admin_email: 'ceo@acme.com', 
--   p_role_name: 'Admin', 
--   p_permissions: ['dl:c', 'dl:r', 'dl:u', 'dl:d', 'rl:c', 'rl:u'] 
-- })
CREATE OR REPLACE FUNCTION public.provision_tenant(
    p_name TEXT,
    p_slug TEXT,
    p_admin_email TEXT,
    p_role_name TEXT,
    p_permissions TEXT[]
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
    -- 1. Security Check
    IF auth.role() != 'service_role' AND session_user != 'postgres' THEN
        RAISE EXCEPTION 'Access Denied: Only Service Role or Superuser can provision tenants.';
    END IF;

    -- 2. Create Tenant
    INSERT INTO public.tenants (name, slug) 
    VALUES (p_name, p_slug) 
    RETURNING id INTO v_tenant_id;

    -- 3. Create Root Role (Softcoded Name)
    INSERT INTO public.roles (tenant_id, name, is_root) 
    VALUES (v_tenant_id, p_role_name, TRUE) 
    RETURNING id INTO v_role_id;

    -- 4. Assign Permissions (Softcoded List)
    INSERT INTO public.role_permissions (role_id, permission_code)
    SELECT v_role_id, p
    FROM unnest(p_permissions) AS p;

    -- 5. Create Invitation
    INSERT INTO public.invitations (email, role_id, tenant_id, invited_by)
    VALUES (p_admin_email, v_role_id, v_tenant_id, auth.uid())
    RETURNING id INTO v_invite_id;

    -- 6. Return Data
    RETURN json_build_object(
        'tenant_id', v_tenant_id,
        'role_id', v_role_id,
        'invite_id', v_invite_id
    );
END;
$$;

-- 1. TENANT FACTORY (Service Role Only)
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
    SELECT v_admin_role_id, code FROM public.permissions 
    WHERE code LIKE 'dl:%' OR code LIKE 'tn:%' OR code LIKE 'rl:%' OR code LIKE 'iv:%';
    
    RETURN v_tenant_id;
END;
$$;

-- 2. INVITE HELPER
CREATE OR REPLACE FUNCTION public.invite_user(p_email TEXT, p_role_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER AS $$ 
DECLARE
    v_tenant_id UUID;
    v_id UUID;
BEGIN
    SELECT tenant_id INTO v_tenant_id FROM public.roles WHERE id = p_role_id;
    INSERT INTO public.invitations (email, role_id, tenant_id, invited_by)
    VALUES (p_email, p_role_id, v_tenant_id, auth.uid()) RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

-- 3. HELPERS
CREATE OR REPLACE FUNCTION public.has_permission(p_code text) RETURNS boolean 
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$ 
BEGIN
    RETURN (auth.jwt() -> 'app_metadata' -> 'permissions') ? p_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_in_my_tenant(p_tenant_id uuid) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$   
DECLARE v_tid uuid;
BEGIN

    IF auth.role() = 'service_role' THEN 
        RETURN TRUE; 
    END IF;

    v_tid := (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid;
    IF v_tid IS NULL THEN SELECT tenant_id INTO v_tid FROM public.profiles WHERE id = auth.uid(); END IF;
    RETURN p_tenant_id = v_tid;
END;
$$;

-- 4. MASTER ACCESS CONTROL
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
    permissions text[];
    my_tid uuid;
    req_perm text;
BEGIN
    IF auth.role() = 'service_role' THEN RETURN TRUE; END IF;

    subordinates := ARRAY(SELECT jsonb_array_elements_text(COALESCE(auth.jwt() -> 'app_metadata' -> 'subordinate_role_ids', '[]'::jsonb)))::uuid[];
    permissions := ARRAY(SELECT jsonb_array_elements_text(COALESCE(auth.jwt() -> 'app_metadata' -> 'permissions', '[]'::jsonb)))::text[];
    my_tid := (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid;

    -- 1. Tenant Isolation (Strict)
    IF p_tenant_id IS NULL OR my_tid IS NULL OR p_tenant_id != my_tid THEN RETURN FALSE; END IF;

    IF p_op = 'insert' THEN 
        req_perm := p_resource_prefix || ':c';
        RETURN req_perm = ANY(permissions); 
    END IF;
    
    IF p_op = 'select' THEN
        IF p_visibility IN ('PRIVATE', 'CONTROLLED') THEN RETURN (p_owner_id = auth.uid() OR p_owner_role_id = ANY(subordinates));
        ELSE req_perm := p_resource_prefix || ':r'; RETURN req_perm = ANY(permissions); END IF;
    END IF;

    IF p_op = 'update' THEN
        IF p_visibility IN ('PRIVATE', 'CONTROLLED') THEN RETURN p_owner_id = auth.uid();
        ELSE 
            IF p_owner_id = auth.uid() THEN RETURN TRUE; END IF;
            req_perm := p_resource_prefix || ':u';
            RETURN req_perm = ANY(permissions); 
        END IF;
    END IF;

    IF p_op = 'delete' THEN
        IF p_owner_id = auth.uid() THEN RETURN TRUE; END IF;
        IF p_visibility IN ('PRIVATE', 'CONTROLLED') AND p_owner_role_id = ANY(subordinates) THEN RETURN TRUE; END IF;
        req_perm := p_resource_prefix || ':d';
        RETURN req_perm = ANY(permissions);
    END IF;

    RETURN FALSE;
END;
$$;

-- 5. TRIGGERS

-- A. Auto-Metadata (Consolidated)
CREATE OR REPLACE FUNCTION public.populate_resource_fields() RETURNS TRIGGER AS $$
BEGIN
    NEW.tenant_id := (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid;
    NEW.owner_id := auth.uid();
    NEW.owner_role_id := (auth.jwt() -> 'app_metadata' ->> 'role_id')::uuid;
    RAISE NOTICE 'populate_resource_fields: tenant_id=%, owner_id=%, owner_role_id=%', NEW.tenant_id, NEW.owner_id, NEW.owner_role_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS set_deals_metadata ON public.deals;
DROP TRIGGER IF EXISTS populate_deals_fields ON public.deals;
CREATE TRIGGER populate_deals_fields BEFORE INSERT ON public.deals FOR EACH ROW EXECUTE FUNCTION public.populate_resource_fields();

-- B. Prevent Permission Escalation
CREATE OR REPLACE FUNCTION public.prevent_permission_escalation() RETURNS TRIGGER AS $$
DECLARE my_perms text[];
BEGIN
    IF auth.role() = 'service_role' THEN 
        RETURN NEW; 
    END IF;

    my_perms := ARRAY(SELECT jsonb_array_elements_text(COALESCE(auth.jwt() -> 'app_metadata' -> 'permissions', '[]'::jsonb)));
    IF NOT (NEW.permission_code = ANY(my_perms)) THEN RAISE EXCEPTION 'Access Denied: You cannot grant a permission you do not possess.'; END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS check_permission_escalation ON public.role_permissions;
CREATE TRIGGER check_permission_escalation BEFORE INSERT ON public.role_permissions FOR EACH ROW EXECUTE FUNCTION public.prevent_permission_escalation();

-- C. Prevent Role Escalation (Invite)
CREATE OR REPLACE FUNCTION public.prevent_role_escalation_invite() RETURNS TRIGGER AS $$
DECLARE subordinates uuid[];
BEGIN
    IF auth.role() = 'service_role' THEN 
        RETURN NEW; 
    END IF;

    subordinates := ARRAY(SELECT jsonb_array_elements_text(COALESCE(auth.jwt() -> 'app_metadata' -> 'subordinate_role_ids', '[]'::jsonb)))::uuid[];
    IF NOT (NEW.role_id = ANY(subordinates)) THEN RAISE EXCEPTION 'Access Denied: You can only assign roles that are below you.'; END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS check_role_escalation_invite ON public.invitations;
CREATE TRIGGER check_role_escalation_invite BEFORE INSERT ON public.invitations FOR EACH ROW EXECUTE FUNCTION public.prevent_role_escalation_invite();

-- D. Protect Root Role
CREATE OR REPLACE FUNCTION public.protect_root_role() RETURNS TRIGGER AS $$
BEGIN
    IF auth.role() = 'service_role' THEN 
        RETURN OLD; 
    END IF;

    IF OLD.is_root THEN RAISE EXCEPTION 'Constraint Violation: Root Role cannot be modified or deleted.'; END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS protect_root_role_trigger ON public.roles;
CREATE TRIGGER protect_root_role_trigger BEFORE DELETE OR UPDATE ON public.roles FOR EACH ROW EXECUTE FUNCTION public.protect_root_role();

-- E. Single Root User Enforcement
CREATE OR REPLACE FUNCTION public.enforce_single_root_user() RETURNS TRIGGER AS $$
DECLARE v_is_root BOOLEAN;
BEGIN
    SELECT is_root INTO v_is_root FROM public.roles WHERE id = NEW.role_id;
    
    IF v_is_root THEN
        IF EXISTS (SELECT 1 FROM public.profiles WHERE role_id = NEW.role_id AND id != NEW.id) THEN
            RAISE EXCEPTION 'Constraint Violation: Root Role is already assigned to another user.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS enforce_single_root_user_trigger ON public.profiles;
CREATE TRIGGER enforce_single_root_user_trigger BEFORE INSERT OR UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.enforce_single_root_user();