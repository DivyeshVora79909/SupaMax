-- 1. Enums & Core (UNCHANGED)
CREATE TYPE public.enforcement_mode AS ENUM ('PUBLIC', 'CONTROLLED', 'PRIVATE', 'OWNER_ONLY');
CREATE TYPE public.deal_stage AS ENUM ('lead', 'qualified', 'proposal', 'negotiation', 'won', 'lost');

-- 2. Organizations (UNCHANGED)
CREATE TABLE public.organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    plan TEXT CHECK (plan IN ('free', 'pro', 'enterprise')) DEFAULT 'free',
    owner_profile_id UUID, 
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Roles (UNCHANGED)
CREATE TABLE public.roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    is_system BOOLEAN DEFAULT FALSE,
    UNIQUE(org_id, name)
);

-- 4. Permissions (UNCHANGED)
CREATE TABLE public.permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL,
    description TEXT,
    UNIQUE(code)
);

-- 5. Role <-> Permissions (UNCHANGED)
CREATE TABLE public.role_permissions (
    role_id UUID REFERENCES public.roles(id) ON DELETE CASCADE,
    permission_id UUID REFERENCES public.permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- 6. Hierarchy (UNCHANGED)
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

-- 7. Profiles (UNCHANGED)
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE RESTRICT,
    full_name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.organizations ADD CONSTRAINT fk_org_owner FOREIGN KEY (owner_profile_id) REFERENCES public.profiles(id) ON DELETE RESTRICT; 

-- =========================================================
-- 8. CRM DOMAIN ENTITIES (NEW)
-- All tables include the "owner_..." columns for RBAC automation
-- =========================================================

-- CRM: Companies (B2B Accounts)
CREATE TABLE public.crm_companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    industry TEXT,
    website TEXT,
    
    -- AUTOMATION FIELDS
    owner_tenant_id UUID NOT NULL REFERENCES public.organizations(id),
    owner_user_id   UUID NOT NULL REFERENCES auth.users(id),
    owner_role_id   UUID NOT NULL REFERENCES public.roles(id),
    enforcement_mode public.enforcement_mode DEFAULT 'CONTROLLED',
    
    created_at TIMESTAMPTZ DEFAULT now()
);

-- CRM: Contacts (People)
CREATE TABLE public.crm_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES public.crm_companies(id) ON DELETE SET NULL,
    first_name TEXT NOT NULL,
    last_name TEXT,
    email TEXT,
    phone TEXT,
    
    -- AUTOMATION FIELDS
    owner_tenant_id UUID NOT NULL REFERENCES public.organizations(id),
    owner_user_id   UUID NOT NULL REFERENCES auth.users(id),
    owner_role_id   UUID NOT NULL REFERENCES public.roles(id),
    enforcement_mode public.enforcement_mode DEFAULT 'CONTROLLED',
    
    created_at TIMESTAMPTZ DEFAULT now()
);

-- CRM: Deals (Opportunities)
CREATE TABLE public.crm_deals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_id UUID REFERENCES public.crm_contacts(id) ON DELETE SET NULL,
    company_id UUID REFERENCES public.crm_companies(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    amount DECIMAL(12,2) DEFAULT 0,
    stage public.deal_stage DEFAULT 'lead',
    expected_close_date DATE,
    
    -- AUTOMATION FIELDS
    owner_tenant_id UUID NOT NULL REFERENCES public.organizations(id),
    owner_user_id   UUID NOT NULL REFERENCES auth.users(id),
    owner_role_id   UUID NOT NULL REFERENCES public.roles(id),
    enforcement_mode public.enforcement_mode DEFAULT 'PRIVATE', -- Stricter default
    
    created_at TIMESTAMPTZ DEFAULT now()
);

-- CRM: Activities (Calls, Notes, Meetings)
CREATE TABLE public.crm_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deal_id UUID REFERENCES public.crm_deals(id) ON DELETE CASCADE,
    type TEXT CHECK (type IN ('call', 'email', 'meeting', 'note')),
    summary TEXT,
    
    -- AUTOMATION FIELDS
    owner_tenant_id UUID NOT NULL REFERENCES public.organizations(id),
    owner_user_id   UUID NOT NULL REFERENCES auth.users(id),
    owner_role_id   UUID NOT NULL REFERENCES public.roles(id),
    enforcement_mode public.enforcement_mode DEFAULT 'CONTROLLED',
    
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for performance
CREATE INDEX idx_crm_companies_rls ON public.crm_companies(owner_tenant_id, owner_user_id, owner_role_id);
CREATE INDEX idx_crm_contacts_rls ON public.crm_contacts(owner_tenant_id, owner_user_id, owner_role_id);
CREATE INDEX idx_crm_deals_rls ON public.crm_deals(owner_tenant_id, owner_user_id, owner_role_id);