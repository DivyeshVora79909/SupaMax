-- 1. Enums & Core
-- Removed hardcoded deal_stage and activity types.
-- Keep enforcement_mode for RBAC logic.
CREATE TYPE public.enforcement_mode AS ENUM ('PUBLIC', 'CONTROLLED', 'PRIVATE', 'OWNER_ONLY');

-- 2. Organizations
CREATE TABLE public.organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    plan TEXT CHECK (plan IN ('free', 'pro', 'enterprise')) DEFAULT 'free',
    owner_profile_id UUID, 
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
    org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    full_name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.organizations ADD CONSTRAINT fk_org_owner FOREIGN KEY (owner_profile_id) REFERENCES public.profiles(id) ON DELETE SET NULL; 

-- =========================================================
-- 8. CRM CONFIGURATION (Customizable)
-- =========================================================

-- Config: Activity Types (e.g., Call, Email, Lunch, Demo)
CREATE TABLE public.crm_activity_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    icon TEXT DEFAULT 'circle', -- Frontend icon name
    color TEXT DEFAULT '#cccccc', -- Frontend hex color
    is_system BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE(org_id, name)
);

-- Config: Pipelines (e.g., Sales Pipeline, Partnership Pipeline)
CREATE TABLE public.crm_pipelines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Config: Pipeline Stages (e.g., Lead -> Won)
CREATE TABLE public.crm_pipeline_stages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pipeline_id UUID NOT NULL REFERENCES public.crm_pipelines(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    win_probability INT DEFAULT 0, -- 0-100%
    display_order INT NOT NULL DEFAULT 0,
    type TEXT CHECK (type IN ('open', 'won', 'lost')) DEFAULT 'open',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- =========================================================
-- 9. CRM DOMAIN ENTITIES
-- =========================================================

-- CRM: Products / Services Catalog
CREATE TABLE public.crm_products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    sku TEXT,
    description TEXT,
    unit_price DECIMAL(12,2) DEFAULT 0,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- CRM: Companies (Accounts)
CREATE TABLE public.crm_companies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    industry TEXT,
    website TEXT,
    address TEXT,
    city TEXT,
    state TEXT,
    
    -- AUTOMATION FIELDS
    owner_tenant_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    owner_user_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    owner_role_id   UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    enforcement_mode public.enforcement_mode DEFAULT 'CONTROLLED',
    
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- CRM: Contacts (People)
CREATE TABLE public.crm_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES public.crm_companies(id) ON DELETE SET NULL,
    first_name TEXT NOT NULL,
    last_name TEXT,
    email TEXT,
    phone TEXT,
    job_title TEXT,
    
    -- AUTOMATION FIELDS
    owner_tenant_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    owner_user_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    owner_role_id   UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    enforcement_mode public.enforcement_mode DEFAULT 'CONTROLLED',
    
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- CRM: Deals (Opportunities)
CREATE TABLE public.crm_deals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID REFERENCES public.crm_companies(id) ON DELETE SET NULL,
    contact_id UUID REFERENCES public.crm_contacts(id) ON DELETE SET NULL,
    
    -- Normalized Pipeline references
    pipeline_id UUID REFERENCES public.crm_pipelines(id) ON DELETE RESTRICT,
    stage_id UUID REFERENCES public.crm_pipeline_stages(id) ON DELETE RESTRICT,
    
    title TEXT NOT NULL,
    amount DECIMAL(12,2) DEFAULT 0,
    expected_close_date DATE,
    probability INT,
    
    -- AUTOMATION FIELDS
    owner_tenant_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    owner_user_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    owner_role_id   UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    enforcement_mode public.enforcement_mode DEFAULT 'PRIVATE',
    
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- CRM: Deal Line Items (Products attached to a Deal)
CREATE TABLE public.crm_deal_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deal_id UUID NOT NULL REFERENCES public.crm_deals(id) ON DELETE CASCADE,
    product_id UUID REFERENCES public.crm_products(id) ON DELETE SET NULL,
    description TEXT,
    quantity INT DEFAULT 1,
    unit_price DECIMAL(12,2) NOT NULL,
    total_price DECIMAL(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- CRM: Activities (Interactions)
CREATE TABLE public.crm_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Normalized Type reference
    activity_type_id UUID REFERENCES public.crm_activity_types(id) ON DELETE RESTRICT,
    
    -- Polymorphic-style associations
    deal_id UUID REFERENCES public.crm_deals(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES public.crm_contacts(id) ON DELETE CASCADE,
    company_id UUID REFERENCES public.crm_companies(id) ON DELETE CASCADE,
    
    subject TEXT NOT NULL,
    description TEXT,
    
    -- Scheduling
    due_date TIMESTAMPTZ,
    duration_minutes INT DEFAULT 30,
    is_completed BOOLEAN DEFAULT FALSE,
    completed_at TIMESTAMPTZ,
    
    -- AUTOMATION FIELDS
    owner_tenant_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    owner_user_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    owner_role_id   UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    enforcement_mode public.enforcement_mode DEFAULT 'CONTROLLED',
    
    created_at TIMESTAMPTZ DEFAULT now()
);

-- CRM: Notes (Simple text logs)
CREATE TABLE public.crm_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deal_id UUID REFERENCES public.crm_deals(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES public.crm_contacts(id) ON DELETE CASCADE,
    company_id UUID REFERENCES public.crm_companies(id) ON DELETE CASCADE,
    
    content TEXT NOT NULL,
    
    -- AUTOMATION FIELDS
    owner_tenant_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    owner_user_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    owner_role_id   UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    enforcement_mode public.enforcement_mode DEFAULT 'CONTROLLED',
    
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for RLS Performance
CREATE INDEX idx_crm_companies_rbac ON public.crm_companies(owner_tenant_id, owner_user_id, owner_role_id);
CREATE INDEX idx_crm_contacts_rbac ON public.crm_contacts(owner_tenant_id, owner_user_id, owner_role_id);
CREATE INDEX idx_crm_deals_rbac ON public.crm_deals(owner_tenant_id, owner_user_id, owner_role_id);
CREATE INDEX idx_crm_activities_rbac ON public.crm_activities(owner_tenant_id, owner_user_id, owner_role_id);
CREATE INDEX idx_crm_notes_rbac ON public.crm_notes(owner_tenant_id, owner_user_id, owner_role_id);

-- =========================================================
-- 10. MODULES & SUBSCRIPTIONS (NEW)
-- =========================================================

-- Defines what permissions exist in a module (e.g., 'crm' module includes 'crm_companies.read', etc.)
CREATE TABLE public.app_modules (
    code TEXT PRIMARY KEY, -- e.g. 'crm', 'hrm', 'billing'
    name TEXT NOT NULL,
    description TEXT,
    included_permissions TEXT[] DEFAULT '{}' -- Array of permission codes
);

-- Links an Org to a Module
CREATE TABLE public.org_subscriptions (
    org_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    module_code TEXT REFERENCES public.app_modules(code) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (org_id, module_code)
);

-- RLS for Modules (View only for authenticated, Manage for SuperAdmins/DBA only)
ALTER TABLE public.app_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Read Modules" ON public.app_modules FOR SELECT TO authenticated USING (true);
CREATE POLICY "Read Subs" ON public.org_subscriptions FOR SELECT TO authenticated USING (org_id = (auth.jwt() -> 'app_metadata' ->> 'org_id')::uuid);