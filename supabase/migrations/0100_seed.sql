DO $$
DECLARE
    v_root uuid := '00000000-0000-0000-0000-000000000001';
    v_role uuid := '00000000-0000-0000-0000-000000000003';
    v_admin uuid := '00000000-0000-0000-0000-000000000002';
    v_all_perms bit(256) := ~(B'0'::bit(256));
BEGIN
    -- 1. Manifest
    INSERT INTO permission_manifest(bit_index, slug, description)
    VALUES
        -- Graph Structural
(0, 'GRAPH_READ', 'Can view the graph structure (siblings/descendants)'),
(1, 'NODE_CREATE', 'Can create new nodes (group/role/user)'),
(2, 'NODE_DELETE', 'Can delete leaf nodes'),
(3, 'EDGE_LINK', 'Can link existing nodes'),
(4, 'EDGE_UNLINK', 'Can unlink nodes'),
        -- Role
(10, 'ROLE_MANAGE', 'Can edit role permission bits'),
        -- Invoice Resources
(20, 'INV_SELECT', 'Can view invoices'),
(21, 'INV_INSERT', 'Can create invoices'),
(22, 'INV_UPDATE', 'Can edit invoices'),
(23, 'INV_DELETE', 'Can delete invoices'),
        -- Customers
(30, 'CUST_SELECT', 'View customers'),
(31, 'CUST_INSERT', 'Create customers'),
(32, 'CUST_UPDATE', 'Edit customers'),
(33, 'CUST_DELETE', 'Delete customers')
    ON CONFLICT
        DO NOTHING;
    -- 2. Nodes
    INSERT INTO dag_node(id, type, label)
        VALUES (v_root, 'group', 'ROOT_ORG')
    ON CONFLICT
        DO NOTHING;
    INSERT INTO dag_node(id, type, label, permission_bits)
        VALUES (v_role, 'role', 'SUPER_ADMIN', v_all_perms)
    ON CONFLICT
        DO NOTHING;
    INSERT INTO dag_node(id, type, label, invite_hash, invite_expires)
        VALUES (v_admin, 'user', 'ROOT_ADMIN', crypt('password123', gen_salt('bf')), now() + interval '2 years')
    ON CONFLICT
        DO NOTHING;
    -- 3. Closures & Edges
    PERFORM
        _algo_init_node(v_root);
    PERFORM
        _algo_init_node(v_role);
    PERFORM
        _algo_init_node(v_admin);
    -- 4. Edges & Attachments
    INSERT INTO dag_edge(parent_id, child_id)
        VALUES (v_root, v_role)
    ON CONFLICT
        DO NOTHING;
    PERFORM
        _algo_attach_subtree(v_root, v_role);
    INSERT INTO dag_edge(parent_id, child_id)
        VALUES (v_role, v_admin)
    ON CONFLICT
        DO NOTHING;
    PERFORM
        _algo_attach_subtree(v_role, v_admin);
    -- 5. Locked
    ALTER TABLE permission_manifest ENABLE ROW LEVEL SECURITY;
    CREATE POLICY "Allow public read" ON permission_manifest
        FOR SELECT TO public, authenticated
            USING (TRUE );
END
$$;

