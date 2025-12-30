CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    claims jsonb;
    v_org_id uuid;
    v_role_id uuid;
    v_permissions text[];
    user_role_permissions text[];
    org_module_permissions text[];
    final_permissions text[];
    user_parent_roles uuid[];
    v_user_id uuid;
BEGIN
    v_user_id := (event->>'user_id')::uuid;
    claims := event->'claims';
    RAISE LOG 'Custom access token hook fired for user: %', v_user_id;

    -- 1. Get Org and Role from claims metadata (populated by BEFORE trigger)
    v_org_id := (claims->'app_metadata'->>'org_id')::uuid;
    v_role_id := (claims->'app_metadata'->>'role_id')::uuid;
    
    -- Try to get permissions from metadata too (for first login)
    IF claims->'app_metadata' ? 'permissions' THEN
        v_permissions := ARRAY(SELECT jsonb_array_elements_text(claims->'app_metadata'->'permissions'));
    END IF;

    -- 2. Fallback/Refresh from database
    IF v_org_id IS NULL OR v_role_id IS NULL THEN
        SELECT org_id, role_id INTO v_org_id, v_role_id 
        FROM public.profiles 
        WHERE id = v_user_id;
    END IF;

    IF v_org_id IS NULL OR v_role_id IS NULL THEN
        RETURN event;
    END IF;

    -- 3. Get permissions specifically assigned to the user's ROLE
    SELECT array_agg(p.code) INTO user_role_permissions
    FROM public.role_permissions rp
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE rp.role_id = v_role_id;

    -- 4. Get permissions unlocked by the Organization's SUBSCRIPTIONS
    SELECT array_agg(DISTINCT perm) INTO org_module_permissions
    FROM public.org_subscriptions os
    JOIN public.app_modules am ON am.code = os.module_code
    CROSS JOIN unnest(am.included_permissions) as perm
    WHERE os.org_id = v_org_id;

    -- 5. INTERSECTION: Final Permissions = Role Perms AND Subscription Perms
    SELECT array_agg(x) INTO final_permissions
    FROM unnest(COALESCE(user_role_permissions, '{}'::text[])) x
    WHERE x = ANY(COALESCE(org_module_permissions, '{}'::text[]));
    
    -- If DB query returned nothing (maybe transaction not committed), use metadata permissions if available
    IF (final_permissions IS NULL OR array_length(final_permissions, 1) IS NULL) AND v_permissions IS NOT NULL THEN
        final_permissions := v_permissions;
    END IF;

    -- 6. Hierarchy Helper
    SELECT array_agg(child_role_id) INTO user_parent_roles
    FROM public.role_closure
    WHERE parent_role_id = v_role_id;

    -- 7. Construct Claims
    claims := jsonb_set(claims, '{app_metadata, org_id}', to_jsonb(v_org_id));
    claims := jsonb_set(claims, '{app_metadata, role_id}', to_jsonb(v_role_id));
    claims := jsonb_set(claims, '{app_metadata, permissions}', to_jsonb(COALESCE(final_permissions, '{}'::text[])));
    claims := jsonb_set(claims, '{app_metadata, accessible_roles}', to_jsonb(COALESCE(user_parent_roles, '{}'::uuid[])));

    event := jsonb_set(event, '{claims}', claims);

    RETURN event;
END;
$$;

GRANT EXECUTE ON FUNCTION public.custom_access_token_hook TO supabase_auth_admin;
GRANT SELECT ON public.profiles TO supabase_auth_admin;
GRANT SELECT ON public.role_permissions TO supabase_auth_admin;
GRANT SELECT ON public.permissions TO supabase_auth_admin;
GRANT SELECT ON public.role_closure TO supabase_auth_admin;
GRANT SELECT ON public.app_modules TO supabase_auth_admin;
GRANT SELECT ON public.org_subscriptions TO supabase_auth_admin;
GRANT SELECT ON public.roles TO supabase_auth_admin;

REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook FROM public, anon, authenticated;