CREATE OR REPLACE FUNCTION public.debug(p_actor_id uuid, p_fn_name text, p_args jsonb)
    RETURNS jsonb
    LANGUAGE plpgsql
    SET search_path = public, extensions
    AS $$
DECLARE
    v_result jsonb;
    v_sql text;
BEGIN
    -- A. Context Switch (Impersonate the Actor)
    PERFORM
        set_config('request.jwt.claim.sub', p_actor_id::text, TRUE);
    PERFORM
        set_config('role', 'authenticated', TRUE);
    -- B. Dynamic Dispatch (Whitelist)
    CASE p_fn_name
    WHEN 'rpc_create_group' THEN
        v_sql := format('SELECT rpc_create_group(%L, %L)', p_args ->> 'parent_id', p_args ->> 'label');
    WHEN 'rpc_create_role' THEN
        -- Note: We cast inside the generated SQL to ensure strict typing
        v_sql := format('SELECT rpc_create_role(%L, %L, %L::bit(256))', p_args ->> 'parent_id', p_args ->> 'label', p_args ->> 'bits');
    WHEN 'rpc_invite_user' THEN
        v_sql := format('SELECT rpc_invite_user(%L, %L)', p_args ->> 'parent_id', p_args ->> 'label');
    WHEN 'rpc_link_node' THEN
        v_sql := format('SELECT rpc_link_node(%L, %L)', p_args ->> 'parent_id', p_args ->> 'child_id');
    WHEN 'rpc_unlink_node' THEN
        v_sql := format('SELECT rpc_unlink_node(%L, %L)', p_args ->> 'parent_id', p_args ->> 'child_id');
    WHEN 'rpc_delete_node' THEN
        v_sql := format('SELECT rpc_delete_node(%L)', p_args ->> 'target_id');
    ELSE
        RAISE EXCEPTION 'Invariant Violation: Unknown function signature %', p_fn_name;
    END CASE;
    -- C. Execution
    EXECUTE format('SELECT to_jsonb(t) FROM (%s) t', v_sql) INTO v_result;
    RETURN jsonb_build_object('success', TRUE, 'payload', v_result);
EXCEPTION
    WHEN OTHERS THEN
        -- D. Error Capture (RLS/Constraint violations return as JSON, not 500s)
        RETURN jsonb_build_object('success', FALSE, 'error', SQLERRM, 'code', SQLSTATE);
END;

$$;

