CREATE OR REPLACE FUNCTION public.debug(p_actor_id uuid, p_fn_name text, p_args jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_result       jsonb;
    v_sql          text;
    v_node_id      uuid;
    v_auth_user_id uuid;
    v_mock_jwt     jsonb;
BEGIN
    SELECT id, auth_user_id INTO v_node_id, v_auth_user_id 
    FROM dag_node WHERE auth_user_id = p_actor_id OR id = p_actor_id LIMIT 1;

    IF v_node_id IS NULL THEN
        RAISE EXCEPTION 'Actor not found in graph';
    END IF;

    IF v_auth_user_id IS NULL THEN
        UPDATE dag_node SET auth_user_id = id WHERE id = v_node_id;
        v_auth_user_id := v_node_id;
    END IF;

    v_mock_jwt := jsonb_build_object(
        'sub',          v_auth_user_id,
        'role',         'authenticated',
        'app_metadata', jsonb_build_object('node_id', v_node_id)
    );

    PERFORM set_config('request.jwt.claims', v_mock_jwt::text, TRUE);
    PERFORM set_config('role', 'authenticated', TRUE);

    CASE p_fn_name
        WHEN 'insert_node' THEN 
            v_sql := format('SELECT to_jsonb(insert_node(%L, %L, %L, %L::bit(256)))', p_args->>'parent_id', p_args->>'type', p_args->>'label', p_args->>'bits');
        WHEN 'update_node' THEN 
            v_sql := format('SELECT to_jsonb(update_node(%L, %L, %L::bit(256)))', p_args->>'node_id', p_args->>'label', p_args->>'bits');
        WHEN 'delete_node' THEN 
            v_sql := format('SELECT to_jsonb(delete_node(%L))', p_args->>'node_id');
        WHEN 'insert_edge' THEN 
            v_sql := format('SELECT to_jsonb(insert_edge(%L, %L))', p_args->>'parent_id', p_args->>'child_id');
        WHEN 'delete_edge' THEN 
            v_sql := format('SELECT to_jsonb(delete_edge(%L, %L))', p_args->>'parent_id', p_args->>'child_id');
        ELSE 
            RAISE EXCEPTION 'Invariant Violation: Unknown function signature %', p_fn_name;
    END CASE;

    EXECUTE v_sql INTO v_result;
    RETURN jsonb_build_object('success', TRUE, 'payload', COALESCE(v_result, '{"status": "ok"}'::jsonb));

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', FALSE, 'error', SQLERRM, 'code', SQLSTATE);
END;
$$;

REVOKE
EXECUTE ON FUNCTION debug (uuid, text, jsonb)
FROM public, authenticated;