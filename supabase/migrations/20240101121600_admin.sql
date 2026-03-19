DO $$
DECLARE
    v_role  uuid := '00000000-0000-0000-0000-000000000001';
    v_admin uuid := '00000000-0000-0000-0000-000000000002';
    v_all_perms bit(256) := ~(B'0'::bit(256));
BEGIN

    INSERT INTO dag_node(id, type, label, permission_bits)
        VALUES (v_role, 'role', 'ADMIN_ROLE', v_all_perms)
    ON CONFLICT DO NOTHING;


    INSERT INTO dag_node(id, type, label, invite_hash, invite_expires)
        VALUES (
            v_admin, 'user', 'ADMIN',
            extensions.crypt('password123', extensions.gen_salt('bf')),
            now() + interval '2 years'
        )
    ON CONFLICT DO NOTHING;


    PERFORM _algo_init_node(v_role);
    PERFORM _algo_init_node(v_admin);


    INSERT INTO dag_edge(parent_id, child_id)
        VALUES (v_role, v_admin)
    ON CONFLICT DO NOTHING;

    PERFORM _algo_attach_subtree(v_role, v_admin);
END
$$;