CREATE OR REPLACE VIEW v_account_list WITH ( security_invoker = TRUE
) AS
SELECT
    a.id,
    a.name,
    a.account_status,
    a.account_type,
    a.industry,
    a.rating,
    a.created_at,
    a.updated_at,
    a.owner_id,
    o.label AS owner_label,
    o.auth_user_id AS owner_auth_user_id
FROM
    account a
    LEFT JOIN dag_node o ON a.owner_id = o.id;

CREATE OR REPLACE VIEW v_account_detail WITH ( security_invoker = TRUE
) AS
SELECT
    l.*,
    a.description,
    a.website,
    a.billing_address,
    a.annual_revenue,
    COALESCE((
            SELECT
                SUM(
                    amount
) FROM opportunity o
            WHERE
                o.account_id = l.id
                AND o.opportunity_status != 'closed_lost'
), 0
) AS total_pipeline_value,
    COALESCE((
            SELECT
                jsonb_agg(
                    jsonb_build_object(
                        'id', c.id, 'first_name', c.first_name, 'last_name', c.last_name, 'email', c.email, 'contact_status', c.contact_status, 'avatar_path', c.avatar_path
)
) FROM contact c
            WHERE
                c.account_id = l.id
), '[]'::jsonb
) AS contacts,
    COALESCE((
            SELECT
                jsonb_agg(
                    jsonb_build_object(
                        'id', oa.id, 'title', oa.title, 'activity_type', oa.activity_type, 'source', oa.source, 'changes', oa.changes, 'created_at', oa.created_at
)
) FROM (
                SELECT
                    *
                FROM opportunity_activity act
            WHERE
                act.opportunity_id IN (
                    SELECT
                        id
                    FROM opportunity
                WHERE
                    account_id = l.id
) ORDER BY act.created_at DESC LIMIT 5
) oa
), '[]'::jsonb
) AS recent_activities
FROM
    v_account_list l
    JOIN account a ON l.id = a.id;

