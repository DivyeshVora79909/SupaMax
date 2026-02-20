CREATE TABLE IF NOT EXISTS opportunity_activity(
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    opportunity_id uuid NOT NULL REFERENCES opportunity(id) ON DELETE CASCADE,
    activity_type text NOT NULL,
    title text NOT NULL,
    description text,
    start_time timestamptz,
    end_time timestamptz,
    changes jsonb,
    created_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_opportunity_activity_parent ON opportunity_activity(opportunity_id);

ALTER TABLE opportunity_activity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_opportunity_activity_select" ON opportunity_activity
    FOR SELECT
        USING (predicate_has_perm(get_graph_context(), 'OPP_SELECT')
            AND EXISTS (
                SELECT
                    1
                FROM
                    opportunity o
                    JOIN account a ON o.account_id = a.id
                WHERE
                    o.id = opportunity_activity.opportunity_id AND (a.owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                        SELECT
                            1
                        FROM
                            closure_dominance cd
                        WHERE
                            cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = a.owner_id))));

GRANT SELECT ON public.opportunity_activity TO authenticated;

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
        IF OLD.status_label IS DISTINCT FROM NEW.status_label THEN
            v_changes := jsonb_set(v_changes, '{status_label}', jsonb_build_object('from', OLD.status_label, 'to', NEW.status_label));
        END IF;
        IF OLD.probability IS DISTINCT FROM NEW.probability THEN
            v_changes := jsonb_set(v_changes, '{probability}', jsonb_build_object('from', OLD.probability, 'to', NEW.probability));
        END IF;
        IF v_changes <> '{}'::jsonb THEN
            INSERT INTO opportunity_activity(opportunity_id, activity_type, title, changes, created_by_node)
                VALUES (NEW.id, 'system', 'System Update', v_changes, current_node_id());
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_opportunity_activity_log
    AFTER UPDATE ON opportunity
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_log_opportunity_activity();

CREATE OR REPLACE FUNCTION rpc_log_opportunity_activity(p_opportunity_id uuid, p_activity_type text, p_title text, p_description text DEFAULT NULL, p_start_time timestamptz DEFAULT NULL, p_end_time timestamptz DEFAULT NULL)
    RETURNS uuid
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
DECLARE
    ctx graph_context;
    v_new_id uuid;
BEGIN
    ctx := assert_authenticated();
    PERFORM
        assert_permission(ctx, 'OPP_ACTIVITY_INSERT');
    IF NOT EXISTS (
        SELECT
            1
        FROM
            opportunity o
            JOIN account a ON o.account_id = a.id
        WHERE
            o.id = p_opportunity_id
            AND (a.owner_id = ANY (ctx.membership_ids)
                OR predicate_dominates(ctx.node_id, a.owner_id))) THEN
    RAISE EXCEPTION 'ERR_ACCESS_DENIED: Opportunity not found or you lack dominance';
END IF;
INSERT INTO opportunity_activity(opportunity_id, activity_type, title, description, start_time, end_time, created_by_node)
    VALUES (p_opportunity_id, p_activity_type, p_title, p_description, p_start_time, p_end_time, ctx.node_id)
RETURNING
    id INTO v_new_id;
    RETURN v_new_id;
END;
$$;

