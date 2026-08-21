-- ============================================================
-- 008_network_mikrotik.sql — network domain, MikroTik scope only
-- (Blueprint Section 13; RADIUS/OLT/GPON tables land in Phase 3
-- per the phased roadmap — kept out of Phase 1 deliberately)
-- ============================================================

-- Credential columns store an application-layer encrypted blob
-- (Laravel Crypt::encrypt — AES-256-GCM, key from the app's
-- secrets manager / APP_KEY). The database never sees plaintext,
-- and no column here is queryable/filterable by credential value —
-- per project rule "never store sensitive credentials as plaintext".
CREATE TABLE network.mikrotik_routers (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(150) NOT NULL,
    ip_address           INET NOT NULL,
    port                  INT NOT NULL DEFAULT 8728
                          CHECK (port IN (8721,8725,8728,8011,9000)),
    username_encrypted     TEXT NOT NULL,
    password_encrypted      TEXT NOT NULL,
    status                   VARCHAR(20) NOT NULL DEFAULT 'disconnected'
                             CHECK (status IN ('connected','disconnected','error')),
    last_connected_at         TIMESTAMPTZ,
    last_error                 TEXT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at                  TIMESTAMPTZ
);
CREATE TRIGGER trg_mikrotik_routers_updated_at BEFORE UPDATE ON network.mikrotik_routers
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_mikrotik_routers_tenant ON network.mikrotik_routers(tenant_id) WHERE deleted_at IS NULL;

-- ---- PPPoE Secrets ----
-- Preserves: Mikrotik Secret List, Online/Offline/Static/Unmatched lists —
-- all of these are QUERIES (filtered views) over this one table's `status`
-- and `last_seen_at`/`ip_type` columns, not separate tables, matching how
-- the live RouterOS API actually reports state.
CREATE TABLE network.pppoe_secrets (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    customer_service_id  UUID REFERENCES isp.customer_services(id) ON DELETE SET NULL,
    router_id             UUID NOT NULL REFERENCES network.mikrotik_routers(id) ON DELETE CASCADE,
    username                VARCHAR(150) NOT NULL,           -- "PPPoE User" in audit
    secret_password_encrypted TEXT NOT NULL,                 -- "MikroTik Secret Password" in audit
    profile                    VARCHAR(150),                  -- bound to package.mikrotik_profile_name
    ip_type                      VARCHAR(20) NOT NULL DEFAULT 'dynamic' CHECK (ip_type IN ('dynamic','static')),
    static_ip                     INET,
    status                          VARCHAR(20) NOT NULL DEFAULT 'enabled'
                                     CHECK (status IN ('enabled','disabled','unmatched')),
    disabled_reason                  VARCHAR(255),
    is_online                          BOOLEAN NOT NULL DEFAULT false,   -- last known live-session state
    last_synced_at                       TIMESTAMPTZ,
    created_at                            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                             TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (router_id, username)
);
CREATE TRIGGER trg_pppoe_secrets_updated_at BEFORE UPDATE ON network.pppoe_secrets
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_pppoe_secrets_tenant_status ON network.pppoe_secrets(tenant_id, status);
CREATE INDEX idx_pppoe_secrets_customer_service ON network.pppoe_secrets(customer_service_id);
CREATE INDEX idx_pppoe_secrets_online ON network.pppoe_secrets(tenant_id, is_online);

-- ---- Live Session snapshots ----
-- Populated by the periodic MikroTik-poll queue worker (Blueprint
-- Section 29, `network` queue). Preserves verified fields: Name,
-- CallerID(MAC), IP, connected duration, "Running" status.
CREATE TABLE network.pppoe_sessions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    pppoe_secret_id      UUID NOT NULL REFERENCES network.pppoe_secrets(id) ON DELETE CASCADE,
    caller_id_mac          MACADDR,
    assigned_ip              INET,
    uptime_seconds             INT,
    status                     VARCHAR(20) NOT NULL DEFAULT 'running',
    polled_at                    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_pppoe_sessions_secret_polled ON network.pppoe_sessions(pppoe_secret_id, polled_at DESC);
-- Retention: application-layer job prunes rows older than 30 days
-- (session history is a trend/audit aid, not permanent record).

-- ---- Auto-disconnect cron log ----
-- Generalizes verified "Auto Mikrotik Disable Log" (router IP, users
-- disabled count, "No user found to disconnect." message) as a
-- specialization of automation.executions once the Automation Engine
-- lands (Phase 4); for Phase 1 parity it is its own simple table so the
-- existing daily cron behavior can ship immediately without waiting on
-- the full engine.
CREATE TABLE network.auto_disconnect_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    router_id            UUID REFERENCES network.mikrotik_routers(id) ON DELETE SET NULL,
    run_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    users_disabled_count     INT NOT NULL DEFAULT 0,
    message                    TEXT NOT NULL DEFAULT 'No user found to disconnect.'
);
CREATE INDEX idx_auto_disconnect_logs_tenant_run ON network.auto_disconnect_logs(tenant_id, run_at DESC);

-- ---- RLS ----
ALTER TABLE network.mikrotik_routers ENABLE ROW LEVEL SECURITY;    ALTER TABLE network.mikrotik_routers FORCE ROW LEVEL SECURITY;
ALTER TABLE network.pppoe_secrets ENABLE ROW LEVEL SECURITY;        ALTER TABLE network.pppoe_secrets FORCE ROW LEVEL SECURITY;
ALTER TABLE network.pppoe_sessions ENABLE ROW LEVEL SECURITY;        ALTER TABLE network.pppoe_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE network.auto_disconnect_logs ENABLE ROW LEVEL SECURITY;   ALTER TABLE network.auto_disconnect_logs FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON network.mikrotik_routers USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON network.pppoe_secrets USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON network.pppoe_sessions USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON network.auto_disconnect_logs USING (tenant_id = platform.current_tenant_id());
