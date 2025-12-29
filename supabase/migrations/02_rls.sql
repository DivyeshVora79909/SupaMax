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
ALTER TABLE public.crm_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_deal_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_activity_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_pipelines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crm_pipeline_stages ENABLE ROW LEVEL SECURITY;


-- Helper Function
CREATE OR REPLACE FUNCTION public.jwt_has_permission(perm text) RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1
    FROM jsonb_array_elements_text(COALESCE(auth.jwt() -> 'app_metadata' -> 'permissions', '[]'::jsonb)) p
    WHERE p = perm
  );
$$ LANGUAGE SQL STABLE;

-- CORE SYSTEM POLICIES (Unchanged)
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
-- CRM POLICIES (Updated for Consistency)
-- =========================================================

-- 1. CONFIGURATION (Pipelines, Types) -> Controlled by 'orgs.write'
CREATE POLICY "View Config" ON public.crm_activity_types FOR SELECT TO authenticated USING ( org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid );
CREATE POLICY "View Pipelines" ON public.crm_pipelines FOR SELECT TO authenticated USING ( org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid );
CREATE POLICY "View Stages" ON public.crm_pipeline_stages FOR SELECT TO authenticated USING ( pipeline_id IN (SELECT id FROM public.crm_pipelines WHERE org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid) );

CREATE POLICY "Manage Config" ON public.crm_activity_types FOR ALL TO authenticated USING ( org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid AND public.jwt_has_permission('orgs.write') );
CREATE POLICY "Manage Pipelines" ON public.crm_pipelines FOR ALL TO authenticated USING ( org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid AND public.jwt_has_permission('orgs.write') );
CREATE POLICY "Manage Stages" ON public.crm_pipeline_stages FOR ALL TO authenticated USING ( pipeline_id IN (SELECT id FROM public.crm_pipelines WHERE org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid) AND public.jwt_has_permission('orgs.write') );

-- 2. PRODUCTS -> Controlled by 'crm_products.*'
CREATE POLICY "View Products" ON public.crm_products FOR SELECT TO authenticated USING ( 
    org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid AND public.jwt_has_permission('crm_products.read')
);
CREATE POLICY "Manage Products" ON public.crm_products FOR ALL TO authenticated USING ( 
    org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid AND public.jwt_has_permission('crm_products.write') 
);

-- 3. DEAL LINE ITEMS -> Inherited from Deal (Easiness: If you see the deal, you see the items)
CREATE POLICY "Access Deal Items" ON public.crm_deal_items FOR ALL TO authenticated USING (
    deal_id IN (SELECT id FROM public.crm_deals WHERE owner_tenant_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
);

-- 4. COMPANIES -> Controlled by 'crm_companies.*'
CREATE POLICY "CRM: Companies Access" ON public.crm_companies FOR ALL TO authenticated USING (
  owner_tenant_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid AND (
    owner_user_id = auth.uid() 
    OR owner_role_id = ANY (ARRAY(SELECT jsonb_array_elements_text(auth.jwt() -> 'app_metadata' -> 'accessible_roles'))::uuid[]) 
    OR (public.jwt_has_permission('crm_companies.read') AND (enforcement_mode = 'PUBLIC' OR enforcement_mode = 'CONTROLLED'))
  )
);

-- 5. CONTACTS -> Controlled by 'crm_contacts.*'
CREATE POLICY "CRM: Contacts Access" ON public.crm_contacts FOR ALL TO authenticated USING (
  owner_tenant_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid AND (
    owner_user_id = auth.uid()
    OR owner_role_id = ANY (ARRAY(SELECT jsonb_array_elements_text(auth.jwt() -> 'app_metadata' -> 'accessible_roles'))::uuid[])
    OR (public.jwt_has_permission('crm_contacts.read') AND (enforcement_mode = 'PUBLIC' OR enforcement_mode = 'CONTROLLED'))
  )
);

-- 6. DEALS -> Controlled by 'crm_deals.*'
CREATE POLICY "CRM: Deals Access" ON public.crm_deals FOR ALL TO authenticated USING (
  owner_tenant_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid AND (
    owner_user_id = auth.uid()
    OR owner_role_id = ANY (ARRAY(SELECT jsonb_array_elements_text(auth.jwt() -> 'app_metadata' -> 'accessible_roles'))::uuid[])
    OR (public.jwt_has_permission('crm_deals.read') AND (enforcement_mode = 'PUBLIC' OR enforcement_mode = 'CONTROLLED'))
  )
);

-- 7. ACTIVITIES -> Controlled by 'crm_activities.*'
CREATE POLICY "CRM: Activities Access" ON public.crm_activities FOR ALL TO authenticated USING (
  owner_tenant_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid AND (
    owner_user_id = auth.uid()
    OR owner_role_id = ANY (ARRAY(SELECT jsonb_array_elements_text(auth.jwt() -> 'app_metadata' -> 'accessible_roles'))::uuid[])
    OR (public.jwt_has_permission('crm_activities.read') AND (enforcement_mode = 'PUBLIC' OR enforcement_mode = 'CONTROLLED'))
  )
);

-- 8. NOTES -> Controlled by 'crm_notes.*'
CREATE POLICY "CRM: Notes Access" ON public.crm_notes FOR ALL TO authenticated USING (
  owner_tenant_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid AND (
    owner_user_id = auth.uid()
    OR owner_role_id = ANY (ARRAY(SELECT jsonb_array_elements_text(auth.jwt() -> 'app_metadata' -> 'accessible_roles'))::uuid[])
    OR (public.jwt_has_permission('crm_notes.read') AND (enforcement_mode = 'PUBLIC' OR enforcement_mode = 'CONTROLLED'))
  )
);