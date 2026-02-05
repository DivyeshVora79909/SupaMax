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
        (10, 'GRAPH_EDIT', 'Can add/remove nodes and edges'),
(11, 'ROLE_MANAGE', 'Can edit role permissions'),
(20, 'INVOICE_READ', 'Can view invoices'),
(21, 'INVOICE_WRITE', 'Can create/update/delete invoices')
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
        VALUES (v_admin, 'user', 'ROOT_ADMIN', crypt('password123', gen_salt('bf')), now() + interval '10 years')
    ON CONFLICT
        DO NOTHING;
    -- 3. Closures
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
END
$$;

