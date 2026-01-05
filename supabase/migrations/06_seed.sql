INSERT INTO public.permissions (code, description) VALUES
-- Role Management (rl)
('rl:c', 'Create Role'),
('rl:r', 'View Role'),
('rl:u', 'Update Role Structure'),
('rl:d', 'Delete Role'),

-- Invitations (iv)
('iv:c', 'Invite User'),
('iv:r', 'View Invites'),
('iv:d', 'Cancel Invite'),

-- Tenant Management (tn)
('tn:u', 'Update Tenant Details'),

-- Deals Resource (dl)
('dl:c', 'Create Deal'),
('dl:r', 'View Public Deal'),
('dl:u', 'Edit Public Deal'),
('dl:d', 'Delete Public Deal')
ON CONFLICT (code) DO NOTHING;