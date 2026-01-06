-- 1. ONBOARDING (Map Invite -> Profile)
CREATE OR REPLACE FUNCTION public.handle_new_user() 
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$ DECLARE
    v_invitation public.invitations%ROWTYPE;
BEGIN
    RAISE NOTICE 'handle_new_user: Attempting onboarding for email %', NEW.email;
    
    -- Attempt to find invitation
    SELECT * INTO v_invitation FROM public.invitations WHERE email = NEW.email;
    
    -- SECURITY: If no invitation exists, BLOCK user creation entirely
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Access Denied: No valid invitation found for email %. Please contact your administrator.', NEW.email;
    END IF;

    -- Create Profile using data from Invitation (Tenant & Role)
    -- This prevents NULL values
    INSERT INTO public.profiles (id, tenant_id, role_id, full_name, email)
    VALUES (
        NEW.id,
        v_invitation.tenant_id,
        v_invitation.role_id,
        NEW.raw_user_meta_data->>'full_name',
        NEW.email
    );

    -- Cleanup Invitation
    DELETE FROM public.invitations WHERE email = NEW.email;
    
    RAISE NOTICE 'Profile created successfully for user %', NEW.email;
    RETURN NEW;
END;
 $$;

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 2. JWT HOOK (Inject Hierarchy & Permissions) - Optimized
CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$ DECLARE
    claims jsonb;
    v_role_id uuid;
    v_subordinates uuid[];
    v_permissions text[];
BEGIN
    claims := event->'claims';
    
    -- Safe fetch of Role ID
    SELECT role_id INTO v_role_id FROM public.profiles WHERE id = (event->>'user_id')::uuid;
    IF v_role_id IS NULL THEN RETURN event; END IF;

    -- Fetch Hierarchy (Self + Subordinates)
    -- Coalesce to empty array to handle users with no subordinates cleanly
    SELECT array_agg(descendant_id) INTO v_subordinates
    FROM public.role_closure WHERE ancestor_id = v_role_id;
    v_subordinates := COALESCE(v_subordinates, '{}'::uuid[]);

    -- Fetch Permissions
    -- Check both direct role and subordinate roles (implicit inheritance)
    SELECT array_agg(DISTINCT permission_code) INTO v_permissions
    FROM public.role_permissions WHERE role_id = ANY(v_subordinates);
    v_permissions := COALESCE(v_permissions, '{}'::text[]);

    -- Inject Claims
    claims := jsonb_set(COALESCE(claims, '{}'::jsonb), '{app_metadata}', COALESCE(claims->'app_metadata', '{}'::jsonb));
    
    claims := jsonb_set(claims, '{app_metadata, tenant_id}', to_jsonb((SELECT tenant_id FROM public.profiles WHERE id = (event->>'user_id')::uuid)));
    claims := jsonb_set(claims, '{app_metadata, role_id}', to_jsonb(v_role_id));
    
    -- Ensure subordinate_role_ids is always an array (never null)
    claims := jsonb_set(claims, '{app_metadata, subordinate_role_ids}', to_jsonb(v_subordinates));
    claims := jsonb_set(claims, '{app_metadata, permissions}', to_jsonb(v_permissions));

    event := jsonb_set(event, '{claims}', claims);
    RETURN event;
END;
 $$;

-- Grants
GRANT EXECUTE ON FUNCTION public.custom_access_token_hook TO supabase_auth_admin;
GRANT EXECUTE ON FUNCTION public.handle_new_user TO supabase_auth_admin;
GRANT SELECT ON public.profiles TO supabase_auth_admin;
GRANT SELECT ON public.invitations TO supabase_auth_admin;
GRANT SELECT ON public.roles, public.role_hierarchy, public.role_permissions, public.role_closure TO supabase_auth_admin;