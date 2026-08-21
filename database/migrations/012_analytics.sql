-- ============================================================
-- 012_analytics.sql — analytics domain (Blueprint Section 24)
-- Reports Center: materialized views feeding the Dashboard (preserving
-- every verified card) and the broader Reports Center. Refreshed by a
-- scheduled queue job (Blueprint Section 29, `reports` queue) — never
-- computed live on every dashboard page load, per the performance rule
-- against N+1/expensive aggregate queries on hot paths.
-- ============================================================

-- ---- Dashboard summary (verified cards: Total/Active/Inactive/
-- Discontinue/Free Customers, monthly new/inactive, Total Collected Bill) ----
CREATE MATERIALIZED VIEW analytics.mv_dashboard_summary AS
SELECT
    c.tenant_id,
    COUNT(*) AS total_customers,
    COUNT(*) FILTER (WHERE c.status = 'active') AS active_customers,
    COUNT(*) FILTER (WHERE c.status = 'inactive') AS inactive_customers,
    COUNT(*) FILTER (WHERE c.status = 'discontinue') AS discontinue_customers,
    COUNT(*) FILTER (WHERE c.status = 'free') AS free_customers,
    COUNT(*) FILTER (WHERE date_trunc('month', c.connection_date) = date_trunc('month', CURRENT_DATE)) AS monthly_new_customers,
    COUNT(*) FILTER (WHERE c.status = 'inactive' AND date_trunc('month', c.updated_at) = date_trunc('month', CURRENT_DATE)) AS monthly_inactive_customers
FROM isp.customers c
WHERE c.deleted_at IS NULL
GROUP BY c.tenant_id;

CREATE UNIQUE INDEX idx_mv_dashboard_summary_tenant ON analytics.mv_dashboard_summary(tenant_id);

CREATE MATERIALIZED VIEW analytics.mv_collection_summary AS
SELECT
    tenant_id,
    date_trunc('month', paid_at)::date AS period_month,
    SUM(amount) AS total_collected
FROM billing.payments
GROUP BY tenant_id, date_trunc('month', paid_at);

CREATE INDEX idx_mv_collection_summary_tenant_month ON analytics.mv_collection_summary(tenant_id, period_month);

-- ---- Package / Zone performance (Business Intelligence, Blueprint 24) ----
CREATE MATERIALIZED VIEW analytics.mv_zone_performance AS
SELECT
    c.tenant_id,
    c.zone_id,
    z.name AS zone_name,
    COUNT(*) AS customer_count,
    COUNT(*) FILTER (WHERE c.status = 'active') AS active_count,
    SUM(cs.monthly_bill) FILTER (WHERE c.status = 'active') AS active_revenue_potential
FROM isp.customers c
JOIN isp.zones z ON z.id = c.zone_id
LEFT JOIN isp.customer_services cs ON cs.customer_id = c.id AND cs.deleted_at IS NULL
WHERE c.deleted_at IS NULL
GROUP BY c.tenant_id, c.zone_id, z.name;

CREATE INDEX idx_mv_zone_performance_tenant ON analytics.mv_zone_performance(tenant_id);

-- ---- Churn (verified need for "which zone had highest churn" — AI Section 22) ----
CREATE MATERIALIZED VIEW analytics.mv_monthly_churn AS
SELECT
    tenant_id,
    zone_id,
    date_trunc('month', updated_at)::date AS period_month,
    COUNT(*) AS churned_count
FROM isp.customers
WHERE status = 'discontinue' AND deleted_at IS NULL
GROUP BY tenant_id, zone_id, date_trunc('month', updated_at);

CREATE INDEX idx_mv_monthly_churn_tenant_month ON analytics.mv_monthly_churn(tenant_id, period_month);

-- ---- Refresh function, called by the scheduled `reports` queue job ----
-- CONCURRENTLY requires the unique index above on at least one view;
-- others fall back to a plain (briefly-locking) refresh — acceptable at
-- Phase 2 scale, revisited if a tenant's data volume demands it later.
CREATE OR REPLACE FUNCTION analytics.refresh_all_materialized_views()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.mv_dashboard_summary;
    REFRESH MATERIALIZED VIEW analytics.mv_collection_summary;
    REFRESH MATERIALIZED VIEW analytics.mv_zone_performance;
    REFRESH MATERIALIZED VIEW analytics.mv_monthly_churn;
END;
$$ LANGUAGE plpgsql;

-- NOTE: Materialized views do not support RLS policies directly in
-- PostgreSQL. Tenant isolation for these is enforced at the application
-- query layer (always filter by tenant_id — these views retain the
-- tenant_id column from their source tables specifically to make that
-- filter mandatory and explicit) and additionally by never exposing a
-- raw "list all tenants' rows" endpoint — the AnalyticsController (Phase
-- 2 backend) always injects `WHERE tenant_id = ?` from the authenticated
-- user's context, mirroring the RLS convention even though the DB can't
-- enforce it here directly.
