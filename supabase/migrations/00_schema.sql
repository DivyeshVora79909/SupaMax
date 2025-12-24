-- 1. Enums
CREATE TYPE public.enforcement_mode AS ENUM ('PUBLIC', 'CONTROLLED', 'PRIVATE', 'OWNER_ONLY');

-- 2. Organizations
CREATE TABLE public.organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    plan TEXT CHECK (plan IN ('free', 'pro', 'enterprise')) DEFAULT 'free',
    owner_profile_id UUID, -- Structural link to the one true owner (Nullable initially)
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Roles
CREATE TABLE public.roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    is_system BOOLEAN DEFAULT FALSE,
    UNIQUE(org_id, name)
);

-- 4. Permissions
CREATE TABLE public.permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL,
    description TEXT,
    UNIQUE(code)
);

-- 5. Role <-> Permissions
CREATE TABLE public.role_permissions (
    role_id UUID REFERENCES public.roles(id) ON DELETE CASCADE,
    permission_id UUID REFERENCES public.permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- 6. Hierarchy
CREATE TABLE public.role_hierarchy (
    org_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    parent_role_id UUID REFERENCES public.roles(id) ON DELETE CASCADE,
    child_role_id UUID REFERENCES public.roles(id) ON DELETE CASCADE,
    PRIMARY KEY (parent_role_id, child_role_id)
);

CREATE TABLE public.role_closure (
    org_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    parent_role_id UUID REFERENCES public.roles(id) ON DELETE CASCADE,
    child_role_id UUID REFERENCES public.roles(id) ON DELETE CASCADE,
    depth INT DEFAULT 0,
    PRIMARY KEY (org_id, parent_role_id, child_role_id)
);
CREATE INDEX idx_role_closure_child ON public.role_closure(child_role_id);

-- 7. Profiles
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- RELATIONAL POWER: ON DELETE RESTRICT
    -- Prevents deleting Organization if members exist
    org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    
    -- RELATIONAL POWER: ON DELETE RESTRICT
    -- Prevents deleting Role if assigned to a member
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE RESTRICT,
    
    full_name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 8. Add Circular Constraint for Organization Owner
ALTER TABLE public.organizations
ADD CONSTRAINT fk_org_owner
FOREIGN KEY (owner_profile_id) REFERENCES public.profiles(id)
ON DELETE RESTRICT; 

-- 9. Domain Entities
CREATE TABLE public.projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    
    owner_tenant_id UUID NOT NULL REFERENCES public.organizations(id),
    owner_user_id   UUID NOT NULL REFERENCES auth.users(id),
    owner_role_id   UUID NOT NULL REFERENCES public.roles(id),
    enforcement_mode public.enforcement_mode DEFAULT 'PRIVATE',
    
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    status TEXT DEFAULT 'todo',
    
    owner_tenant_id UUID NOT NULL REFERENCES public.organizations(id),
    owner_user_id   UUID NOT NULL REFERENCES auth.users(id),
    owner_role_id   UUID NOT NULL REFERENCES public.roles(id),
    enforcement_mode public.enforcement_mode DEFAULT 'CONTROLLED',
    
    assigned_to UUID REFERENCES public.profiles(id) ON DELETE SET NULL, 
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_projects_rls ON public.projects(owner_tenant_id, owner_user_id, owner_role_id);
CREATE INDEX idx_tasks_rls ON public.tasks(owner_tenant_id, owner_user_id, owner_role_id);