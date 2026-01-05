-- 1. SCOPED REBUILD (Only rebuilds the specific tenant's tree)
CREATE OR REPLACE FUNCTION public.rebuild_tenant_closure() RETURNS TRIGGER AS $$ 
DECLARE
    v_tenant_id UUID;
    v_target_role_id UUID;
BEGIN
    v_target_role_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.parent_id ELSE NEW.parent_id END;
    SELECT tenant_id INTO v_tenant_id FROM public.roles WHERE id = v_target_role_id;
    
    IF v_tenant_id IS NULL THEN RETURN NULL; END IF;

    DELETE FROM public.role_closure 
    WHERE ancestor_id IN (SELECT id FROM public.roles WHERE tenant_id = v_tenant_id);

    INSERT INTO public.role_closure (ancestor_id, descendant_id, depth)
    SELECT id, id, 0 FROM public.roles WHERE tenant_id = v_tenant_id;

    INSERT INTO public.role_closure (ancestor_id, descendant_id, depth)
    SELECT DISTINCT ancestor_id, descendant_id, depth FROM (
        WITH RECURSIVE hierarchy AS (
            SELECT rh.parent_id AS ancestor_id, rh.child_id AS descendant_id, 1 AS depth 
            FROM public.role_hierarchy rh
            JOIN public.roles r ON rh.parent_id = r.id
            WHERE r.tenant_id = v_tenant_id
            UNION ALL
            SELECT c.ancestor_id, rh.child_id, c.depth + 1
            FROM hierarchy c
            JOIN public.role_hierarchy rh ON c.descendant_id = rh.parent_id
            WHERE c.depth < 20
        )
        SELECT ancestor_id, descendant_id, depth FROM hierarchy
    ) sub
    ON CONFLICT (ancestor_id, descendant_id) DO UPDATE SET depth = EXCLUDED.depth;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_hierarchy_change AFTER INSERT OR UPDATE OR DELETE ON public.role_hierarchy
FOR EACH ROW EXECUTE FUNCTION public.rebuild_tenant_closure();

-- 2. SELF CLOSURE
CREATE OR REPLACE FUNCTION public.maintain_role_self_closure() RETURNS TRIGGER AS $$ BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.role_closure (ancestor_id, descendant_id, depth) VALUES (NEW.id, NEW.id, 0) ON CONFLICT DO NOTHING;
    ELSIF TG_OP = 'DELETE' THEN
        DELETE FROM public.role_closure WHERE ancestor_id = OLD.id AND descendant_id = OLD.id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_role_change AFTER INSERT OR DELETE ON public.roles
FOR EACH ROW EXECUTE FUNCTION public.maintain_role_self_closure();

-- 3. INTEGRITY RULES (DAG & ROOT POSITION)
CREATE OR REPLACE FUNCTION public.enforce_tree_rules() RETURNS TRIGGER AS $$ 
DECLARE 
    v_is_root BOOLEAN;
    v_has_path BOOLEAN;
BEGIN
    -- A. Root Position Lock: Root cannot be a child (must stay at top)
    SELECT is_root INTO v_is_root FROM public.roles WHERE id = NEW.child_id;
    IF v_is_root THEN
        RAISE EXCEPTION 'Constraint Violation: Root Role cannot be a subordinate.';
    END IF;

    -- B. DAG Enforcement (Cycle Detection)
    SELECT EXISTS(
        SELECT 1 FROM public.role_closure 
        WHERE ancestor_id = NEW.child_id AND descendant_id = NEW.parent_id
    ) INTO v_has_path;

    IF v_has_path THEN
        RAISE EXCEPTION 'Constraint Violation: Cycle detected. The proposed child is already an ancestor of the parent.';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER check_tree_rules BEFORE INSERT OR UPDATE ON public.role_hierarchy
FOR EACH ROW EXECUTE FUNCTION public.enforce_tree_rules();