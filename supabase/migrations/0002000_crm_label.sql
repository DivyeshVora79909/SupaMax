CREATE TYPE label_column AS ENUM(
    -- Shared
    'lead_source',
    'industry',
    'priority',
    -- Account
    'account_status',
    'account_type',
    'rating',
    -- Contact
    'contact_status',
    'activity_status',
    'contact_type',
    'department',
    -- Opportunity
    'opportunity_status',
    'forecast_category',
    -- Opportunity Activity
    'activity_type',
    -- Project
    'project_status',
    'health_status',
    'project_type'
);

CREATE TABLE IF NOT EXISTS crm_label(
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    column_name label_column NOT NULL,
    label text NOT NULL,
    sort_order integer DEFAULT 0,
    color text,
    icon text,
    owner_id uuid NOT NULL REFERENCES dag_node(id) ON DELETE CASCADE,
    created_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    updated_by_node uuid REFERENCES dag_node(id) ON DELETE SET NULL,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now(),
    CONSTRAINT unq_crm_label UNIQUE (owner_id, column_name, label)
);

CREATE INDEX IF NOT EXISTS idx_crm_label_lookup ON crm_label(owner_id, column_name);

CREATE OR REPLACE FUNCTION _trigger_audit_crm_label()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.created_by_node := current_node_id();
        NEW.updated_by_node := current_node_id();
    ELSIF TG_OP = 'UPDATE' THEN
        NEW.updated_by_node := current_node_id();
        NEW.updated_at := now();
        IF NEW.owner_id IS DISTINCT FROM OLD.owner_id THEN
            PERFORM
                assert_dominance(assert_authenticated(), NEW.owner_id);
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_crm_label_audit ON crm_label;

CREATE TRIGGER trg_crm_label_audit
    BEFORE INSERT OR UPDATE ON crm_label
    FOR EACH ROW
    EXECUTE FUNCTION _trigger_audit_crm_label();

ALTER TABLE crm_label ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rls_crm_label_select ON crm_label;

CREATE POLICY rls_crm_label_select ON crm_label
    FOR SELECT
        USING (owner_id = ANY ((get_graph_context()).membership_ids)
            OR EXISTS (
                SELECT
                    1
                FROM
                    closure_dominance cd
                WHERE
                    cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = crm_label.owner_id));

DROP POLICY IF EXISTS rls_crm_label_insert ON crm_label;

CREATE POLICY rls_crm_label_insert ON crm_label
    FOR INSERT
        WITH CHECK (predicate_has_perm(get_graph_context(), 'CRM_LABEL_INSERT')
        AND (owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
            SELECT
                1
            FROM
                closure_dominance cd
            WHERE
                cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = crm_label.owner_id)));

DROP POLICY IF EXISTS rls_crm_label_update ON crm_label;

CREATE POLICY rls_crm_label_update ON crm_label
    FOR UPDATE
        USING (predicate_has_perm(get_graph_context(), 'CRM_LABEL_UPDATE')
            AND (owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                SELECT
                    1
                FROM
                    closure_dominance cd
                WHERE
                    cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = crm_label.owner_id)));

DROP POLICY IF EXISTS rls_crm_label_delete ON crm_label;

CREATE POLICY rls_crm_label_delete ON crm_label
    FOR DELETE
        USING (predicate_has_perm(get_graph_context(), 'CRM_LABEL_DELETE')
            AND (owner_id = ANY ((get_graph_context()).membership_ids) OR EXISTS (
                SELECT
                    1
                FROM
                    closure_dominance cd
                WHERE
                    cd.ancestor_id =(get_graph_context()).node_id AND cd.descendant_id = crm_label.owner_id)));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.crm_label TO authenticated;

