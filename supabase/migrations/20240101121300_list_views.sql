CREATE OR REPLACE VIEW v_account_list
WITH (security_invoker = TRUE) AS
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
    o.label AS owner_label
FROM account a
    LEFT JOIN dag_node o ON a.owner_id = o.id;

CREATE OR REPLACE VIEW v_contact_list
WITH (security_invoker = TRUE) AS
SELECT
    c.id,
    c.first_name,
    c.last_name,
    c.email,
    c.phone,
    c.contact_status,
    c.department,
    c.contact_type,
    c.created_at,
    c.updated_at,
    c.owner_id,
    c.account_id,
    a.name AS account_name,
    o.label AS owner_label
FROM
    contact c
    LEFT JOIN account a ON c.account_id = a.id
    LEFT JOIN dag_node o ON c.owner_id = o.id;

CREATE OR REPLACE VIEW v_opportunity_list
WITH (security_invoker = TRUE) AS
SELECT
    op.id,
    op.title,
    op.opportunity_status,
    op.amount,
    op.currency,
    op.close_date,
    op.probability,
    op.forecast_category,
    op.created_at,
    op.updated_at,
    op.owner_id,
    op.account_id,
    a.name AS account_name,
    o.label AS owner_label
FROM
    opportunity op
    LEFT JOIN account a ON op.account_id = a.id
    LEFT JOIN dag_node o ON op.owner_id = o.id;

CREATE OR REPLACE VIEW v_project_list
WITH (security_invoker = TRUE) AS
SELECT
    p.id,
    p.title,
    p.project_status,
    p.health_status,
    p.priority,
    p.completion_percent,
    p.start_date,
    p.target_end_date,
    p.created_at,
    p.updated_at,
    p.owner_id,
    p.opportunity_id,
    op.title AS opportunity_title,
    o.label AS owner_label
FROM
    project p
    LEFT JOIN opportunity op ON p.opportunity_id = op.id
    LEFT JOIN dag_node o ON p.owner_id = o.id;

CREATE OR REPLACE VIEW v_activity_list
WITH (security_invoker = TRUE) AS
SELECT
    act.id,
    act.activity_type,
    act.title,
    act.start_time,
    act.end_time,
    act.created_at,
    act.updated_at,
    act.owner_id,
    act.opportunity_id,
    op.title AS opportunity_title,
    o.label AS owner_label
FROM
    opportunity_activity act
    LEFT JOIN opportunity op ON act.opportunity_id = op.id
    LEFT JOIN dag_node o ON act.owner_id = o.id;