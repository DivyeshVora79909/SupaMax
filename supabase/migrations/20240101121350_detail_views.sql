
CREATE OR REPLACE VIEW v_account_detail
WITH (security_invoker = TRUE) AS
SELECT l.*, a.annual_revenue, a.head_count, a.website, a.billing_address, a.shipping_address, a.description, a.other, a.pdf_path, a.excel_path,

COALESCE(opp_stats.metrics, '[]'::jsonb) AS pipeline_metrics,

COALESCE(cnt_stats.metrics, '[]'::jsonb) AS contact_metrics,
    
    COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'id', c.id, 'name', c.first_name || ' ' || c.last_name,
            'email', c.email, 'status', c.contact_status, 'avatar_path', c.avatar_path
        ))
        FROM contact c WHERE c.account_id = l.id
    ), '[]'::jsonb) AS contacts,
    
    COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'id', op.id, 'title', op.title, 'amount', op.amount,
            'status', op.opportunity_status, 'close_date', op.close_date
        ))
        FROM opportunity op WHERE op.account_id = l.id
    ), '[]'::jsonb) AS opportunities

FROM v_account_list l
JOIN account a ON l.id = a.id
LEFT JOIN (
    SELECT parent_id, jsonb_agg(jsonb_build_object('status', final_grp, 'amount', val, 'count', cnt)) as metrics
    FROM (
        SELECT parent_id, CASE WHEN rn <= 8 THEN grp ELSE 'other' END AS final_grp, SUM(val) AS val, SUM(cnt) AS cnt
        FROM (
            SELECT account_id AS parent_id, COALESCE(opportunity_status, 'unassigned') AS grp, COALESCE(SUM(amount), 0) AS val, COUNT(id) AS cnt,
                   ROW_NUMBER() OVER(PARTITION BY account_id ORDER BY SUM(amount) DESC NULLS LAST) as rn
            FROM opportunity GROUP BY account_id, opportunity_status
        ) ranked GROUP BY parent_id, CASE WHEN rn <= 8 THEN grp ELSE 'other' END
    ) grouped GROUP BY parent_id
) opp_stats ON opp_stats.parent_id = l.id
LEFT JOIN (
    SELECT parent_id, jsonb_agg(jsonb_build_object('status', final_grp, 'count', cnt)) as metrics
    FROM (
        SELECT parent_id, CASE WHEN rn <= 8 THEN grp ELSE 'other' END AS final_grp, SUM(cnt) AS cnt
        FROM (
            SELECT account_id AS parent_id, COALESCE(contact_status, 'unassigned') AS grp, COUNT(id) AS cnt,
                   ROW_NUMBER() OVER(PARTITION BY account_id ORDER BY COUNT(id) DESC) as rn
            FROM contact GROUP BY account_id, contact_status
        ) ranked GROUP BY parent_id, CASE WHEN rn <= 8 THEN grp ELSE 'other' END
    ) grouped GROUP BY parent_id
) cnt_stats ON cnt_stats.parent_id = l.id;


CREATE OR REPLACE VIEW v_opportunity_detail
WITH (security_invoker = TRUE) AS
SELECT l.*, op.lead_source, op.description, op.other, op.proposal_path, op.contract_path,

COALESCE(proj_stats.metrics, '[]'::jsonb) AS project_metrics,



COALESCE(act_stats.metrics, '[]'::jsonb) AS activity_metrics,
    
    COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'id', p.id, 'title', p.title, 'status', p.project_status,
            'health', p.health_status, 'completion', p.completion_percent
        ))
        FROM project p WHERE p.opportunity_id = l.id
    ), '[]'::jsonb) AS projects,
    
    COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
            'id', act.id, 'type', act.activity_type,
            'title', act.title, 'start_time', act.start_time
        ))
        FROM opportunity_activity act WHERE act.opportunity_id = l.id
    ), '[]'::jsonb) AS activities

FROM v_opportunity_list l
JOIN opportunity op ON l.id = op.id
LEFT JOIN (
    SELECT parent_id, jsonb_agg(jsonb_build_object('status', final_grp, 'budget', val, 'count', cnt)) as metrics
    FROM (
        SELECT parent_id, CASE WHEN rn <= 8 THEN grp ELSE 'other' END AS final_grp, SUM(val) AS val, SUM(cnt) AS cnt
        FROM (
            SELECT opportunity_id AS parent_id, COALESCE(project_status, 'unassigned') AS grp, COALESCE(SUM(budget), 0) AS val, COUNT(id) AS cnt,
                   ROW_NUMBER() OVER(PARTITION BY opportunity_id ORDER BY SUM(budget) DESC NULLS LAST) as rn
            FROM project GROUP BY opportunity_id, project_status
        ) ranked GROUP BY parent_id, CASE WHEN rn <= 8 THEN grp ELSE 'other' END
    ) grouped GROUP BY parent_id
) proj_stats ON proj_stats.parent_id = l.id
LEFT JOIN (
    SELECT parent_id, jsonb_agg(jsonb_build_object('type', final_grp, 'count', cnt)) as metrics
    FROM (
        SELECT parent_id, CASE WHEN rn <= 8 THEN grp ELSE 'other' END AS final_grp, SUM(cnt) AS cnt
        FROM (
            SELECT opportunity_id AS parent_id, COALESCE(activity_type, 'unassigned') AS grp, COUNT(id) AS cnt,
                   ROW_NUMBER() OVER(PARTITION BY opportunity_id ORDER BY COUNT(id) DESC) as rn
            FROM opportunity_activity GROUP BY opportunity_id, activity_type
        ) ranked GROUP BY parent_id, CASE WHEN rn <= 8 THEN grp ELSE 'other' END
    ) grouped GROUP BY parent_id
) act_stats ON act_stats.parent_id = l.id;

CREATE OR REPLACE VIEW v_contact_detail
WITH (security_invoker = TRUE) AS
SELECT l.*, c.mobile, c.activity_status, c.social_links, c.profile, c.other, c.avatar_path, c.document_path
FROM v_contact_list l
    JOIN contact c ON l.id = c.id;

CREATE OR REPLACE VIEW v_project_detail
WITH (security_invoker = TRUE) AS
SELECT l.*, p.description, p.project_type, p.probability, p.budget, p.actual_cost, p.project_manager, p.actual_end_date, p.other, p.brief_path, p.spec_path
FROM v_project_list l
    JOIN project p ON l.id = p.id;

CREATE OR REPLACE VIEW v_activity_detail
WITH (security_invoker = TRUE) AS
SELECT l.*, act.description
FROM
    v_activity_list l
    JOIN opportunity_activity act ON l.id = act.id;