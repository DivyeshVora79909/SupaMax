-- Enable RLS on ALL tables
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_hierarchy ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_closure ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;

-- Helper Function
CREATE OR REPLACE FUNCTION public.jwt_has_permission(perm text) RETURNS boolean AS $$
  SELECT EXISTS (
    SELECT 1
    FROM jsonb_array_elements_text(COALESCE(auth.jwt() -> 'app_metadata' -> 'permissions', '[]'::jsonb)) p
    WHERE p = perm
  );
$$ LANGUAGE SQL STABLE;

-- 1. ORGANIZATIONS
CREATE POLICY "View own Organization" ON public.organizations
FOR SELECT TO authenticated
USING ( id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid );

-- 2. PROFILES
CREATE POLICY "View Org Profiles" ON public.profiles
FOR SELECT TO authenticated
USING ( org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid );

CREATE POLICY "Update Own Profile" ON public.profiles
FOR UPDATE TO authenticated
USING ( id = auth.uid() );

-- 3. ROLES (Read All, Write/Delete only if NOT system)
CREATE POLICY "Read Org Roles" ON public.roles
FOR SELECT TO authenticated
USING ( org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid );

CREATE POLICY "Write Org Roles" ON public.roles
FOR INSERT TO authenticated
WITH CHECK ( 
    org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid 
    AND is_system = FALSE 
);

CREATE POLICY "Modify Org Roles" ON public.roles
FOR UPDATE TO authenticated
USING ( 
    org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid 
    AND is_system = FALSE 
);

CREATE POLICY "Delete Org Roles" ON public.roles
FOR DELETE TO authenticated
USING ( 
    org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid 
    AND is_system = FALSE 
);

-- 4. PERMISSIONS & HIERARCHY
CREATE POLICY "Read Global Permissions" ON public.permissions
FOR SELECT TO authenticated
USING ( true );

CREATE POLICY "Read Role Permissions" ON public.role_permissions
FOR SELECT TO authenticated
USING (
  role_id IN (SELECT id FROM public.roles WHERE org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid)
);

CREATE POLICY "Modify Role Permissions" ON public.role_permissions
FOR ALL TO authenticated
USING (
  role_id IN (SELECT id FROM public.roles WHERE org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid AND is_system = FALSE)
);

CREATE POLICY "Read Org Hierarchy" ON public.role_hierarchy
FOR SELECT TO authenticated
USING ( org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid );

CREATE POLICY "Read Org Closure" ON public.role_closure
FOR SELECT TO authenticated
USING ( org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid );

-- 5. PROJECTS & TASKS
CREATE POLICY "RBAC: Projects Access" ON public.projects
FOR ALL TO authenticated
USING (
  owner_tenant_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
  AND (
    owner_user_id = auth.uid()
    OR owner_role_id = ANY (ARRAY(SELECT jsonb_array_elements_text(auth.jwt() -> 'app_metadata' -> 'accessible_roles'))::uuid[])
    OR (public.jwt_has_permission('projects.read') AND (enforcement_mode = 'PUBLIC' OR enforcement_mode = 'CONTROLLED'))
  )
);

CREATE POLICY "RBAC: Tasks Access" ON public.tasks
FOR ALL TO authenticated
USING (
  owner_tenant_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid
  AND (
    owner_user_id = auth.uid()
    OR assigned_to = auth.uid() 
    OR owner_role_id = ANY (ARRAY(SELECT jsonb_array_elements_text(auth.jwt() -> 'app_metadata' -> 'accessible_roles'))::uuid[])
    OR (public.jwt_has_permission('tasks.read') AND (enforcement_mode = 'PUBLIC' OR enforcement_mode = 'CONTROLLED'))
  )
);