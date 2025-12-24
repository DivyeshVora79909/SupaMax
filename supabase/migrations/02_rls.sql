-- Enable RLS
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_hierarchy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_closure ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
-- CRM Tables
ALTER TABLE public.crm_companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_deals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_activities ENABLE ROW LEVEL SECURITY;

-- Helper Function (UNCHANGED)
CREATE OR REPLACE FUNCTION public.jwt_has_permission(perm text) RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1
    FROM jsonb_array_elements_text(COALESCE(auth.jwt() -> 'app_metadata' -> 'permissions', '[]'::jsonb)) p
    WHERE p = perm
  );
$$ LANGUAGE SQL STABLE;

-- CORE SYSTEM POLICIES (UNCHANGED from previous)
CREATE POLICY "View own Organization" ON public.organizations FOR SELECT TO authenticated USING ( id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid );
CREATE POLICY "View Org Profiles" ON public.profiles FOR SELECT TO authenticated USING ( org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid );
CREATE POLICY "Update Own Profile" ON public.profiles FOR UPDATE TO authenticated USING ( id = auth.uid() );
CREATE POLICY "Read Org Roles" ON public.roles FOR SELECT TO authenticated USING ( org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid );
CREATE POLICY "Write Org Roles" ON public.roles FOR INSERT TO authenticated WITH CHECK ( org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid AND is_system = FALSE );
CREATE POLICY "Modify Org Roles" ON public.roles FOR UPDATE TO authenticated USING ( org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid AND is_system = FALSE );
CREATE POLICY "Delete Org Roles" ON public.roles FOR DELETE TO authenticated USING ( org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid AND is_system = FALSE );
CREATE POLICY "Read Global Permissions" ON public.permissions FOR SELECT TO authenticated USING ( true );
CREATE POLICY "Read Role Permissions" ON public.role_permissions FOR SELECT TO authenticated USING ( role_id IN (SELECT id FROM public.roles WHERE org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid) );
CREATE POLICY "Modify Role Permissions" ON public.role_permissions FOR ALL TO authenticated USING ( role_id IN (SELECT id FROM public.roles WHERE org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid AND is_system = FALSE) );
CREATE POLICY "Read Org Hierarchy" ON public.role_hierarchy FOR SELECT TO authenticated USING ( org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid );
CREATE POLICY "Read Org Closure" ON public.role_closure FOR SELECT TO authenticated USING ( org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid );

-- =========================================================
-- CRM POLICIES (NEW)
-- Applies the "Owner + Hierarchy + Permissions" Logic
-- =========================================================

-- 1. COMPANIES
CREATE POLICY "CRM: Companies Access" ON public.crm_companies
FOR ALL TO authenticated
USING (
  owner_tenant_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
  AND (
    owner_user_id = auth.uid() -- I own it
    OR owner_role_id = ANY (ARRAY(SELECT jsonb_array_elements_text(auth.jwt() -> 'app_metadata' -> 'accessible_roles'))::uuid[]) -- My child owns it
    OR (public.jwt_has_permission('crm_companies.read') AND (enforcement_mode = 'PUBLIC' OR enforcement_mode = 'CONTROLLED')) -- Shared
  )
);

-- 2. CONTACTS
CREATE POLICY "CRM: Contacts Access" ON public.crm_contacts
FOR ALL TO authenticated
USING (
  owner_tenant_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
  AND (
    owner_user_id = auth.uid()
    OR owner_role_id = ANY (ARRAY(SELECT jsonb_array_elements_text(auth.jwt() -> 'app_metadata' -> 'accessible_roles'))::uuid[])
    OR (public.jwt_has_permission('crm_contacts.read') AND (enforcement_mode = 'PUBLIC' OR enforcement_mode = 'CONTROLLED'))
  )
);

-- 3. DEALS
CREATE POLICY "CRM: Deals Access" ON public.crm_deals
FOR ALL TO authenticated
USING (
  owner_tenant_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
  AND (
    owner_user_id = auth.uid()
    OR owner_role_id = ANY (ARRAY(SELECT jsonb_array_elements_text(auth.jwt() -> 'app_metadata' -> 'accessible_roles'))::uuid[])
    OR (public.jwt_has_permission('crm_deals.read') AND (enforcement_mode = 'PUBLIC' OR enforcement_mode = 'CONTROLLED'))
  )
);

-- 4. ACTIVITIES
CREATE POLICY "CRM: Activities Access" ON public.crm_activities
FOR ALL TO authenticated
USING (
  owner_tenant_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
  AND (
    owner_user_id = auth.uid()
    OR owner_role_id = ANY (ARRAY(SELECT jsonb_array_elements_text(auth.jwt() -> 'app_metadata' -> 'accessible_roles'))::uuid[])
    OR (public.jwt_has_permission('crm_activities.read') AND (enforcement_mode = 'PUBLIC' OR enforcement_mode = 'CONTROLLED'))
  )
);