INSERT INTO public.permissions (code, description) VALUES
-- Organization
('orgs.read',    'Can view organization details'),
('orgs.write',   'Can update organization settings'),

-- Roles & Permissions
('roles.read',   'Can view roles and hierarchy'),
('roles.write',  'Can create and edit roles'),
('roles.delete', 'Can delete roles'),

-- Profiles (Members)
('profiles.read',   'Can view member profiles'),
('profiles.write',  'Can invite or edit members'),
('profiles.delete', 'Can remove members from organization'),

-- Projects
('projects.read',   'Can view projects'),
('projects.write',  'Can create and edit projects'),
('projects.delete', 'Can delete projects'),

-- Tasks
('tasks.read',   'Can view tasks'),
('tasks.write',  'Can create and edit tasks'),
('tasks.delete', 'Can delete tasks')

ON CONFLICT (code) DO UPDATE 
SET description = EXCLUDED.description;