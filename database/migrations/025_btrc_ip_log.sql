-- ============================================================
-- 025_btrc_ip_log.sql — BTRC IP Log Server (compliance domain).
--
-- Bangladeshi ISPs are required to retain subscriber IP-assignment
-- history so that a given public IP + timestamp can be traced back to a
-- subscriber for law-enforcement requests. Competitors (notably Maxim)
-- built their market position on providing exactly this.
--
-- Design notes:
--  * APPEND-ONLY. UPDATE/DELETE are revoked from the application role,
--    like audit.activity_logs — a log that can be edited is worthless as
--    legal evidence.
--  * Session-based: one row per IP assignment (start .. stop), sourced
--    from RADIUS accounting or MikroTik session polling.
--  * NAT/CGNAT aware: public IP + port range recorded, because with
--    carrier-grade NAT the public IP alone does not identify a
--    subscriber — the port block is what makes the trace unambiguous.
--  * Retention is configurable per tenant; purge is an explicit,
--    audited operation rather than a silent cascade.
-- ============================================================

CREATE TABLE IF NOT EXISTS compliance.ip_session_logs (
    id                  BIGSERIAL PRIMARY KEY,
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE RESTRICT,
    customer_id         UUID REFERENCES isp.customers(id) ON DELETE SET NULL,
    customer_service_id UUID REFERENCES isp.customer_services(id) ON DELETE SET NULL,
    -- Denormalised identity snapshot: the log must stay meaningful even
    -- if the customer record is later edited or removed.
    subscriber_name     VARCHAR(255),
    subscriber_mobile   VARCHAR(30),
    subscriber_nid      VARCHAR(50),
    username            VARCHAR(150),                 -- PPPoE/RADIUS username
    framed_ip           INET NOT NULL,                -- private/assigned IP
    public_ip           INET,                         -- post-NAT public IP
    nat_port_start      INT,                          -- CGNAT port block
    nat_port_end        INT,
    mac_address         MACADDR,
    nas_ip              INET,                         -- router/NAS that issued it
    session_id          VARCHAR(100),
    started_at          TIMESTAMPTZ NOT NULL,
    ended_at            TIMESTAMPTZ,
    bytes_in            BIGINT DEFAULT 0,
    bytes_out           BIGINT DEFAULT 0,
    source              VARCHAR(20) NOT NULL DEFAULT 'radius'
                         CHECK (source IN ('radius','mikrotik','manual')),
    recorded_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (ended_at IS NULL OR ended_at >= started_at),
    CHECK (nat_port_end IS NULL OR nat_port_start IS NULL OR nat_port_end >= nat_port_start)
);

-- The trace query is "who had this IP at this time" — index for exactly that.
CREATE INDEX IF NOT EXISTS idx_iplog_trace
    ON compliance.ip_session_logs (tenant_id, framed_ip, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_iplog_public_trace
    ON compliance.ip_session_logs (tenant_id, public_ip, started_at DESC)
    WHERE public_ip IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_iplog_customer
    ON compliance.ip_session_logs (customer_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_iplog_open_sessions
    ON compliance.ip_session_logs (tenant_id) WHERE ended_at IS NULL;

-- Retention policy per tenant (BTRC guidance has historically been in the
-- 6–12 month range; kept configurable rather than hard-coded).
CREATE TABLE IF NOT EXISTS compliance.ip_log_settings (
    tenant_id           UUID PRIMARY KEY REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    retention_days      INT NOT NULL DEFAULT 365 CHECK (retention_days >= 180),
    cgnat_enabled       BOOLEAN NOT NULL DEFAULT false,
    last_purged_at      TIMESTAMPTZ,
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Law-enforcement trace: resolve an IP at a point in time to a subscriber.
CREATE OR REPLACE FUNCTION compliance.trace_ip(
    p_tenant_id UUID, p_ip INET, p_at TIMESTAMPTZ, p_port INT DEFAULT NULL
) RETURNS TABLE (
    subscriber_name VARCHAR, subscriber_mobile VARCHAR, subscriber_nid VARCHAR,
    username VARCHAR, framed_ip INET, public_ip INET,
    started_at TIMESTAMPTZ, ended_at TIMESTAMPTZ, nas_ip INET
) AS $$
    SELECT l.subscriber_name, l.subscriber_mobile, l.subscriber_nid,
           l.username, l.framed_ip, l.public_ip, l.started_at, l.ended_at, l.nas_ip
    FROM compliance.ip_session_logs l
    WHERE l.tenant_id = p_tenant_id
      AND (l.framed_ip = p_ip OR l.public_ip = p_ip)
      AND l.started_at <= p_at
      AND (l.ended_at IS NULL OR l.ended_at >= p_at)
      -- With CGNAT the port block disambiguates which subscriber held the
      -- shared public IP at that instant.
      AND (p_port IS NULL OR l.nat_port_start IS NULL
           OR (p_port BETWEEN l.nat_port_start AND l.nat_port_end))
    ORDER BY l.started_at DESC;
$$ LANGUAGE sql STABLE;

-- RLS
ALTER TABLE compliance.ip_session_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE compliance.ip_session_logs FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON compliance.ip_session_logs;
CREATE POLICY tenant_isolation ON compliance.ip_session_logs
    USING (tenant_id = platform.current_tenant_id());

ALTER TABLE compliance.ip_log_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE compliance.ip_log_settings FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON compliance.ip_log_settings;
CREATE POLICY tenant_isolation ON compliance.ip_log_settings
    USING (tenant_id = platform.current_tenant_id());
