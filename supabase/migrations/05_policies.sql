-- 1. TENANTS
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Tenants: Read Own" ON public.tenants FOR SELECT TO authenticated
USING (id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid);

-- 2. PROFILES
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Profiles: Read Tenant" ON public.profiles FOR SELECT TO authenticated
USING (id = auth.uid() OR public.is_in_my_tenant(tenant_id));
CREATE POLICY "Profiles: Update Self" ON public.profiles FOR UPDATE TO authenticated
USING (id = auth.uid());

-- 3. ROLES & PERMISSIONS
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_hierarchy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_closure ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Roles: Read Tenant" ON public.roles FOR SELECT TO authenticated USING (public.is_in_my_tenant(tenant_id));
CREATE POLICY "Roles: Manage" ON public.roles FOR ALL TO authenticated USING (public.is_in_my_tenant(tenant_id) AND public.has_permission('rl:u'));

CREATE POLICY "Perms: Read Tenant" ON public.role_permissions FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM public.roles r WHERE r.id = role_id AND public.is_in_my_tenant(r.tenant_id)));
CREATE POLICY "Perms: Manage" ON public.role_permissions FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM public.roles r WHERE r.id = role_id AND public.is_in_my_tenant(r.tenant_id)) AND public.has_permission('rl:u'));

-- EXCLUSIVE ROOT ACCESS FOR HIERARCHY
CREATE POLICY "Hierarchy: Read Tenant" ON public.role_hierarchy FOR SELECT TO authenticated 
USING (
    EXISTS (SELECT 1 FROM public.roles r WHERE r.id = parent_id AND public.is_in_my_tenant(r.tenant_id))
    AND 
    (auth.jwt() -> 'app_metadata' ->> 'role_id')::uuid IN (SELECT id FROM public.roles WHERE is_root = TRUE)
);

CREATE POLICY "Hierarchy: Manage" ON public.role_hierarchy FOR ALL TO authenticated 
USING (
    EXISTS (SELECT 1 FROM public.roles r WHERE r.id = parent_id AND public.is_in_my_tenant(r.tenant_id))
    AND 
    (auth.jwt() -> 'app_metadata' ->> 'role_id')::uuid IN (SELECT id FROM public.roles WHERE is_root = TRUE)
);

CREATE POLICY "Closure: Read" ON public.role_closure FOR SELECT TO authenticated 
USING ( (auth.jwt() -> 'app_metadata' ->> 'role_id')::uuid IN (SELECT id FROM public.roles WHERE is_root = TRUE) );

CREATE POLICY "Definitions: Read" ON public.permissions FOR SELECT TO authenticated USING (true);

-- 4. INVITATIONS
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Invites: View" ON public.invitations FOR SELECT TO authenticated USING (public.has_permission('iv:r') AND tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid);
CREATE POLICY "Invites: Create" ON public.invitations FOR INSERT TO authenticated WITH CHECK (public.has_permission('iv:c') AND tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid);
CREATE POLICY "Invites: Delete" ON public.invitations FOR DELETE TO authenticated USING (public.has_permission('iv:d') AND tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')::uuid);

-- 5. DEALS
ALTER TABLE public.deals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Deals: Select" ON public.deals FOR SELECT TO authenticated USING (public.check_resource_access(tenant_id, visibility, owner_id, owner_role_id, 'dl', 'select'));
CREATE POLICY "Deals: Insert" ON public.deals FOR INSERT TO authenticated WITH CHECK (public.check_resource_access(tenant_id, visibility, owner_id, owner_role_id, 'dl', 'insert'));
CREATE POLICY "Deals: Update" ON public.deals FOR UPDATE TO authenticated USING (public.check_resource_access(tenant_id, visibility, owner_id, owner_role_id, 'dl', 'update'));
CREATE POLICY "Deals: Delete" ON public.deals FOR DELETE TO authenticated USING (public.check_resource_access(tenant_id, visibility, owner_id, owner_role_id, 'dl', 'delete'));

-- 6. STORAGE
CREATE POLICY "Storage: Download" ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'deals' AND EXISTS (SELECT 1 FROM public.deals WHERE file_path = name));

CREATE POLICY "Storage: Upload" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'deals');

CREATE POLICY "Storage: Manage" ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'deals' AND EXISTS (SELECT 1 FROM public.deals WHERE file_path = name));

CREATE POLICY "Storage: Delete" ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'deals' AND EXISTS (SELECT 1 FROM public.deals WHERE file_path = name));