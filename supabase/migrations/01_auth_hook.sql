CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    claims jsonb;
    user_profile RECORD;
    user_role_permissions text[];
    org_module_permissions text[];
    final_permissions text[];
    user_parent_roles uuid[];
BEGIN
    -- 1. Get User Profile
    SELECT * INTO user_profile 
    FROM public.profiles 
    WHERE id = (event->>'user_id')::uuid;

    IF user_profile IS NULL OR user_profile.role_id IS NULL THEN
        RETURN event;
    END IF;

    -- 2. Get permissions specifically assigned to the user's ROLE
    SELECT array_agg(p.code) INTO user_role_permissions
    FROM public.role_permissions rp
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE rp.role_id = user_profile.role_id;

    -- 3. Get permissions unlocked by the Organization's SUBSCRIPTIONS
    -- We join subscriptions -> modules -> expand array -> distinct
    SELECT array_agg(DISTINCT perm) INTO org_module_permissions
    FROM public.org_subscriptions os
    JOIN public.app_modules am ON am.code = os.module_code
    CROSS JOIN unnest(am.included_permissions) as perm
    WHERE os.org_id = user_profile.org_id;

    -- 4. INTERSECTION: Final Permissions = Role Perms AND Subscription Perms
    -- If user has role 'Sales', but Org doesn't have 'CRM' module, result is empty.
    SELECT array_agg(x) INTO final_permissions
    FROM unnest(user_role_permissions) x
    WHERE x = ANY(org_module_permissions);

    -- 5. Hierarchy Helper
    SELECT array_agg(child_role_id) INTO user_parent_roles
    FROM public.role_closure
    WHERE parent_role_id = user_profile.role_id;

    -- 6. Construct Claims
    claims := event->'claims';

    claims := jsonb_set(claims, '{app_metadata, org_id}', to_jsonb(user_profile.org_id));
    claims := jsonb_set(claims, '{app_metadata, role_id}', to_jsonb(user_profile.role_id));
    
    -- Inject the INTERSECTED permissions
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

REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook FROM public, anon, authenticated;