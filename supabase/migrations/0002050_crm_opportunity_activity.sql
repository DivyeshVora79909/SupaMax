CREATE TABLE IF NOT EXISTS opportunity_activity(
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    opportunity_id uuid NOT NULL REFERENCES opportunity(id) ON DELETE CASCADE,
    activity_type text NOT NULL,
    title text NOT NULL,
    description text,
    start_time timestamptz,
    end_time timestamptz,
    changes jsonb,
    source text NOT NULL DEFAULT 'user',
    created_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    updated_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_opportunity_activity_time_order CHECK (end_time IS NULL OR start_time IS NULL OR end_time >= start_time)
);

CREATE INDEX IF NOT EXISTS idx_opportunity_activity_parent ON opportunity_activity(opportunity_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_opportunity_activity_source ON opportunity_activity(source);

CREATE OR REPLACE FUNCTION _activity_can_access_opportunity(p_opportunity_id uuid)
    RETURNS boolean
    LANGUAGE sql
    STABLE
    SECURITY DEFINER
    SET search_path = public
    AS $$
    SELECT
        EXISTS(
            SELECT
                1
            FROM
                opportunity o
                JOIN account a ON o.account_id = a.id
            WHERE
                o.id = p_opportunity_id
                AND(a.owner_id = ANY((get_graph_context()).membership_ids)
                    OR EXISTS(
                        SELECT
                            1
                        FROM
                            closure_dominance cd
                        WHERE
                            cd.ancestor_id =(get_graph_context()).node_id
                            AND cd.descendant_id = a.owner_id)));
$$;

CREATE OR REPLACE FUNCTION _activity_add_change(p_changes jsonb, p_key text, p_old jsonb, p_new jsonb)
    RETURNS jsonb
    LANGUAGE sql
    IMMUTABLE
    AS $$
    SELECT
        CASE WHEN p_old IS DISTINCT FROM p_new THEN
            p_changes || jsonb_build_object(p_key, jsonb_build_object('from', p_old, 'to', p_new))
        ELSE
            p_changes
        END;
$$;

ALTER TABLE opportunity_activity ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rls_opportunity_activity_select ON opportunity_activity;

DROP POLICY IF EXISTS rls_opportunity_activity_insert ON opportunity_activity;

DROP POLICY IF EXISTS rls_opportunity_activity_update ON opportunity_activity;

DROP POLICY IF EXISTS rls_opportunity_activity_delete ON opportunity_activity;

CREATE POLICY rls_opportunity_activity_select ON opportunity_activity
    FOR SELECT TO authenticated
        USING (predicate_has_perm(get_graph_context(), 'OPP_SELECT')
            AND _activity_can_access_opportunity(opportunity_activity.opportunity_id));

CREATE POLICY rls_opportunity_activity_insert ON opportunity_activity
    FOR INSERT TO authenticated
        WITH CHECK (source <> 'system'
        AND predicate_has_perm(get_graph_context(), 'OPP_ACTIVITY_INSERT')
        AND _activity_can_access_opportunity(opportunity_activity.opportunity_id));

CREATE POLICY rls_opportunity_activity_update ON opportunity_activity
    FOR UPDATE TO authenticated
        USING (source = 'user'
            AND predicate_has_perm(get_graph_context(), 'OPP_ACTIVITY_UPDATE')
            AND _activity_can_access_opportunity(opportunity_activity.opportunity_id))
            WITH CHECK (source = 'user'
            AND predicate_has_perm(get_graph_context(), 'OPP_ACTIVITY_UPDATE')
            AND _activity_can_access_opportunity(opportunity_activity.opportunity_id));

CREATE POLICY rls_opportunity_activity_delete ON opportunity_activity
    FOR DELETE TO authenticated
        USING (source = 'user'
            AND predicate_has_perm(get_graph_context(), 'OPP_ACTIVITY_DELETE')
            AND _activity_can_access_opportunity(opportunity_activity.opportunity_id));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.opportunity_activity TO authenticated;

CREATE OR REPLACE FUNCTION _trigger_audit_opportunity_activity()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
DECLARE
    v_input opportunity_activity;
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.source := CASE WHEN NEW.source = 'system' THEN
            'system'
        ELSE
            'user'
        END;
        IF NEW.source = 'user' THEN
            NEW.changes := NULL;
        END IF;
        NEW.created_by_node := COALESCE(NEW.created_by_node, current_node_id());
        NEW.updated_by_node := COALESCE(NEW.updated_by_node, NEW.created_by_node);
        NEW.created_at := COALESCE(NEW.created_at, now());
        NEW.updated_at := COALESCE(NEW.updated_at, NEW.created_at);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.source = 'system' THEN
            RETURN NULL;
        END IF;
        v_input := NEW;
        NEW := OLD;
        NEW.title := v_input.title;
        NEW.description := v_input.description;
        NEW.start_time := v_input.start_time;
        NEW.end_time := v_input.end_time;
        NEW.updated_by_node := current_node_id();
        NEW.updated_at := now();
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        IF OLD.source = 'system' THEN
            RETURN NULL;
        END IF;
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_opportunity_activity_audit ON opportunity_activity;

CREATE TRIGGER trg_opportunity_activity_audit
    BEFORE INSERT OR UPDATE OR DELETE ON opportunity_activity
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_audit_opportunity_activity();

CREATE OR REPLACE FUNCTION _trigger_log_opportunity_activity()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
DECLARE
    v_changes jsonb := '{}'::jsonb;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        v_changes := _activity_add_change(v_changes, 'title', to_jsonb(OLD.title), to_jsonb(NEW.title));
        v_changes := _activity_add_change(v_changes, 'opportunity_status', to_jsonb(OLD.opportunity_status), to_jsonb(NEW.opportunity_status));
        v_changes := _activity_add_change(v_changes, 'forecast_category', to_jsonb(OLD.forecast_category), to_jsonb(NEW.forecast_category));
        v_changes := _activity_add_change(v_changes, 'lead_source', to_jsonb(OLD.lead_source), to_jsonb(NEW.lead_source));
        v_changes := _activity_add_change(v_changes, 'probability', to_jsonb(OLD.probability), to_jsonb(NEW.probability));
        v_changes := _activity_add_change(v_changes, 'amount', to_jsonb(OLD.amount), to_jsonb(NEW.amount));
        v_changes := _activity_add_change(v_changes, 'close_date', to_jsonb(OLD.close_date), to_jsonb(NEW.close_date));
        v_changes := _activity_add_change(v_changes, 'description', to_jsonb(OLD.description), to_jsonb(NEW.description));
        IF v_changes <> '{}'::jsonb THEN
            INSERT INTO opportunity_activity(opportunity_id, activity_type, title, description, changes, source, created_by_node, updated_by_node)
                VALUES (NEW.id, 'system', 'System Update', 'Automatically recorded opportunity change', v_changes, 'system', current_node_id(), current_node_id());
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_opportunity_activity_log ON opportunity;

CREATE TRIGGER trg_opportunity_activity_log
    AFTER UPDATE ON opportunity
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_log_opportunity_activity();

