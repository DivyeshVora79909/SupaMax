-- 1. ONBOARDING (Map Invite -> Profile)
CREATE OR REPLACE FUNCTION public.handle_new_user() 
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_invitation public.invitations%ROWTYPE;
BEGIN
    SELECT * INTO v_invitation FROM public.invitations WHERE email = NEW.email;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Access Denied: No invitation found.';
    END IF;

    INSERT INTO public.profiles (id, tenant_id, role_id, full_name, email)
    VALUES (
        NEW.id,
        v_invitation.tenant_id,
        v_invitation.role_id,
        NEW.raw_user_meta_data->>'full_name',
        NEW.email
    );

    DELETE FROM public.invitations WHERE email = NEW.email;
    RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 2. JWT HOOK (Inject Hierarchy & Permissions)
CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
    claims jsonb;
    v_role_id uuid;
    v_subordinates uuid[];
    v_permissions text[];
BEGIN
    claims := event->'claims';
    SELECT role_id INTO v_role_id FROM public.profiles WHERE id = (event->>'user_id')::uuid;

    IF v_role_id IS NULL THEN RETURN event; END IF;

    -- Fetch Hierarchy
    SELECT array_agg(descendant_id) INTO v_subordinates
    FROM public.role_closure WHERE ancestor_id = v_role_id;

    -- Fetch Permissions (Self + Subordinates)
    SELECT array_agg(DISTINCT permission_code) INTO v_permissions
    FROM public.role_permissions WHERE role_id = ANY(v_subordinates);

    -- Inject Claims
    claims := jsonb_set(claims, '{app_metadata, tenant_id}', to_jsonb((SELECT tenant_id FROM public.profiles WHERE id = (event->>'user_id')::uuid)));
    claims := jsonb_set(claims, '{app_metadata, role_id}', to_jsonb(v_role_id));
    claims := jsonb_set(claims, '{app_metadata, subordinate_role_ids}', to_jsonb(COALESCE(v_subordinates, '{}'::uuid[])));
    claims := jsonb_set(claims, '{app_metadata, permissions}', to_jsonb(COALESCE(v_permissions, '{}'::text[])));

    event := jsonb_set(event, '{claims}', claims);
    RETURN event;
END;
$$;

GRANT EXECUTE ON FUNCTION public.custom_access_token_hook TO supabase_auth_admin;
GRANT SELECT ON public.profiles TO supabase_auth_admin;
GRANT SELECT ON public.role_closure TO supabase_auth_admin;
GRANT SELECT ON public.role_permissions TO supabase_auth_admin;