CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    claims jsonb;
    user_profile RECORD;
    user_permissions text[];
    user_parent_roles uuid[];
BEGIN
    SELECT * INTO user_profile 
    FROM public.profiles 
    WHERE id = (event->>'user_id')::uuid;

    IF user_profile IS NULL OR user_profile.role_id IS NULL THEN
        RETURN event;
    END IF;

    SELECT array_agg(p.code) INTO user_permissions
    FROM public.role_permissions rp
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE rp.role_id = user_profile.role_id;

    SELECT array_agg(child_role_id) INTO user_parent_roles
    FROM public.role_closure
    WHERE parent_role_id = user_profile.role_id;

    claims := event->'claims';

    claims := jsonb_set(claims, '{app_metadata, org_id}', to_jsonb(user_profile.org_id));
    claims := jsonb_set(claims, '{app_metadata, role_id}', to_jsonb(user_profile.role_id));
    claims := jsonb_set(claims, '{app_metadata, permissions}', to_jsonb(COALESCE(user_permissions, '{}'::text[])));
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

REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook FROM public, anon, authenticated;