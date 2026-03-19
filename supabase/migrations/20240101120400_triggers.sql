CREATE OR REPLACE FUNCTION audit_meta_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_node_id uuid := (_auth_context()).node_id;
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_by_node := v_node_id;
        NEW.updated_by_node := v_node_id;
        NEW.created_at      := now();
        NEW.updated_at      := now();
    ELSIF TG_OP = 'UPDATE' THEN
        NEW.created_by_node := OLD.created_by_node;
        NEW.created_at      := OLD.created_at;
        NEW.updated_by_node := v_node_id;
        NEW.updated_at      := now();
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION enforce_ownership_root_res()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF OLD.owner_id IS DISTINCT FROM NEW.owner_id THEN
        IF NOT _i_dominate(OLD.owner_id) THEN
            RAISE EXCEPTION 'ERR_OWNERSHIP_UNAUTHORIZED: You do not dominate the current owner of this resource.';
        END IF;
        IF NOT (_i_dominate(NEW.owner_id) OR _is_nonuser_parent(NEW.owner_id)) THEN
            RAISE EXCEPTION 'ERR_OWNERSHIP_SCOPE: Ownership can only be transferred to yourself, subordinates, or your immediate parent.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;