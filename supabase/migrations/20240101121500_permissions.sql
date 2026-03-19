INSERT INTO
    permission_manifest (bit_index, slug, description)
VALUES (
        0,
        'GRAPH_READ',
        'Can view the graph structure'
    ),
    (
        1,
        'NODE_CREATE',
        'Can create new nodes'
    ),
    (
        2,
        'NODE_DELETE',
        'Can delete leaf nodes'
    ),
    (
        3,
        'EDGE_LINK',
        'Can link existing nodes'
    ),
    (
        4,
        'EDGE_UNLINK',
        'Can unlink nodes'
    ),
    (
        10,
        'ROLE_MANAGE',
        'Can edit role permission bits'
    ),
    (
        31,
        'CRM_LABEL_INSERT',
        'Create CRM labels'
    ),
    (
        32,
        'CRM_LABEL_UPDATE',
        'Update CRM labels'
    ),
    (
        33,
        'CRM_LABEL_DELETE',
        'Delete CRM labels'
    ),
    (
        40,
        'ACCOUNT_SELECT',
        'View accounts'
    ),
    (
        41,
        'ACCOUNT_INSERT',
        'Create accounts'
    ),
    (
        42,
        'ACCOUNT_UPDATE',
        'Edit accounts'
    ),
    (
        43,
        'ACCOUNT_DELETE',
        'Delete accounts'
    ),
    (
        50,
        'CONTACT_SELECT',
        'View contacts'
    ),
    (
        51,
        'CONTACT_INSERT',
        'Create contacts'
    ),
    (
        52,
        'CONTACT_UPDATE',
        'Edit contacts'
    ),
    (
        53,
        'CONTACT_DELETE',
        'Delete contacts'
    ),
    (
        60,
        'OPP_SELECT',
        'View opportunities'
    ),
    (
        61,
        'OPP_INSERT',
        'Create opportunities'
    ),
    (
        62,
        'OPP_UPDATE',
        'Edit opportunities'
    ),
    (
        63,
        'OPP_DELETE',
        'Delete opportunities'
    ),
    (
        64,
        'OPP_ACTIVITY_INSERT',
        'Create activity logs'
    ),
    (
        65,
        'OPP_ACTIVITY_UPDATE',
        'Edit opportunity activities'
    ),
    (
        66,
        'OPP_ACTIVITY_DELETE',
        'Delete opportunity activities'
    ),
    (
        70,
        'PROJ_SELECT',
        'View projects'
    ),
    (
        71,
        'PROJ_INSERT',
        'Create projects'
    ),
    (
        72,
        'PROJ_UPDATE',
        'Edit projects'
    ),
    (
        73,
        'PROJ_DELETE',
        'Delete projects'
    ) ON CONFLICT DO NOTHING;

ALTER TABLE permission_manifest ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_permission_manifest_read" ON permission_manifest FOR
SELECT TO public, authenticated USING (TRUE);