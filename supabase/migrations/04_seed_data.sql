INSERT INTO public.permissions (code, description) VALUES
-- System
('orgs.read', 'Can view org'),
('orgs.write', 'Can edit org settings (Pipelines, Activity Types)'),
('roles.read', 'Can view roles'),
('roles.write', 'Can edit roles'),
('roles.delete', 'Can delete roles'),
('profiles.read', 'Can view profiles'),
('profiles.write', 'Can edit profiles'),
('profiles.delete', 'Can kick members'),

-- CRM: Companies
('crm_companies.read', 'View companies'),
('crm_companies.write', 'Create/Edit companies'),
('crm_companies.delete', 'Delete companies'),

-- CRM: Contacts
('crm_contacts.read', 'View contacts'),
('crm_contacts.write', 'Create/Edit contacts'),
('crm_contacts.delete', 'Delete contacts'),

-- CRM: Deals
('crm_deals.read', 'View deals'),
('crm_deals.write', 'Create/Edit deals'),
('crm_deals.delete', 'Delete deals'),

-- CRM: Products (NEW - Consistent)
('crm_products.read', 'View product catalog'),
('crm_products.write', 'Create/Edit products'),
('crm_products.delete', 'Delete products'),

-- CRM: Activities
('crm_activities.read', 'View activities'),
('crm_activities.write', 'Log activities'),
('crm_activities.delete', 'Delete activities'),

-- CRM: Notes (NEW - Consistent)
('crm_notes.read', 'View notes'),
('crm_notes.write', 'Create/Edit notes'),
('crm_notes.delete', 'Delete notes')

ON CONFLICT (code) DO UPDATE 
SET description = EXCLUDED.description;