CREATE TABLE IF NOT EXISTS crm_audit_log (
    id uuid DEFAULT gen_random_uuid (),
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    owner_id uuid NOT NULL,
    operation text NOT NULL,
    payload jsonb NOT NULL,
    created_by_node uuid REFERENCES dag_node (id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id, created_at)
);

CREATE INDEX IF NOT EXISTS idx_audit_log_entity ON crm_audit_log (entity_type, entity_id);

CREATE INDEX IF NOT EXISTS idx_audit_log_time ON crm_audit_log (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_log_owner ON crm_audit_log (owner_id);

ALTER TABLE crm_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_audit_select_via_dominance" ON crm_audit_log FOR
SELECT TO authenticated USING (
        has_perm ('GRAPH_READ')
        AND _i_dominate (owner_id)
    );

CREATE POLICY "rls_audit_select_via_parent" ON crm_audit_log FOR
SELECT TO authenticated USING (
        has_perm ('GRAPH_READ')
        AND _is_nonuser_parent (owner_id)
    );

GRANT SELECT ON public.crm_audit_log TO authenticated;

CREATE OR REPLACE FUNCTION trigger_universal_audit_log()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_payload   jsonb;
    v_entity_id uuid;
    v_owner_id  uuid;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_payload   := to_jsonb(OLD);
        v_entity_id := OLD.id;
        v_owner_id  := OLD.owner_id;
    ELSE
        v_payload   := to_jsonb(NEW);
        v_entity_id := NEW.id;
        v_owner_id  := NEW.owner_id;
    END IF;

    INSERT INTO crm_audit_log(entity_type, entity_id, owner_id, operation, payload, created_by_node)
    VALUES (TG_TABLE_NAME, v_entity_id, v_owner_id, TG_OP, v_payload, (_auth_context()).node_id);

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_account_auto_audit
    AFTER INSERT OR UPDATE OR DELETE ON account
    FOR EACH ROW EXECUTE FUNCTION trigger_universal_audit_log();

CREATE TRIGGER trg_contact_auto_audit
    AFTER INSERT OR UPDATE OR DELETE ON contact
    FOR EACH ROW EXECUTE FUNCTION trigger_universal_audit_log();

CREATE TRIGGER trg_opportunity_auto_audit
    AFTER INSERT OR UPDATE OR DELETE ON opportunity
    FOR EACH ROW EXECUTE FUNCTION trigger_universal_audit_log();

CREATE TRIGGER trg_project_auto_audit
    AFTER INSERT OR UPDATE OR DELETE ON project
    FOR EACH ROW EXECUTE FUNCTION trigger_universal_audit_log();

CREATE TRIGGER trg_opportunity_activity_auto_audit
    AFTER INSERT OR UPDATE OR DELETE ON opportunity_activity
    FOR EACH ROW EXECUTE FUNCTION trigger_universal_audit_log();