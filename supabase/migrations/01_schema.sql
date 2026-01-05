-- 1. EXTENSIONS & CONFIG
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
ALTER ROLE authenticator SET log_statement = 'all';

-- 2. ENUMS
CREATE TYPE visibility_mode AS ENUM ('PRIVATE', 'PUBLIC', 'CONTROLLED');

-- 3. CORE TABLES
CREATE TABLE public.tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT UNIQUE,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    is_root BOOLEAN DEFAULT FALSE,
    UNIQUE(tenant_id, name)
);

CREATE UNIQUE INDEX idx_single_root_per_tenant ON public.roles (tenant_id) WHERE is_root = TRUE;

CREATE TABLE public.permissions (
    code TEXT PRIMARY KEY,
    description TEXT
);

CREATE TABLE public.role_permissions (
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    permission_code TEXT NOT NULL REFERENCES public.permissions(code) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_code)
);

-- 4. HIERARCHY TABLES
CREATE TABLE public.role_hierarchy (
    parent_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    PRIMARY KEY (parent_id, child_id),
    CHECK (parent_id != child_id)
);

CREATE TABLE public.role_closure (
    ancestor_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    descendant_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    depth INT NOT NULL,
    PRIMARY KEY (ancestor_id, descendant_id)
);

-- 5. USER TABLES
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    full_name TEXT,
    email TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL UNIQUE,
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES public.tenants(id) ON DELETE CASCADE,
    invited_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 6. RESOURCE TABLES (Example: Deals)
CREATE TABLE public.deals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    file_path TEXT UNIQUE,
    
    -- Security Mixin
    tenant_id UUID REFERENCES public.tenants(id),
    owner_id UUID NOT NULL REFERENCES auth.users(id),
    visibility visibility_mode NOT NULL DEFAULT 'PRIVATE',
    owner_role_id UUID NOT NULL REFERENCES public.roles(id),
    
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 7. INDEXES (Performance)
CREATE INDEX idx_roles_tenant ON public.roles(tenant_id);
CREATE INDEX idx_profiles_tenant ON public.profiles(tenant_id);
CREATE INDEX idx_closure_anc ON public.role_closure(ancestor_id);
CREATE INDEX idx_closure_desc ON public.role_closure(descendant_id);
CREATE INDEX idx_deals_lookup ON public.deals(tenant_id, owner_id);
CREATE INDEX idx_deals_files ON public.deals(file_path);