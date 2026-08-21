-- ============================================================
-- 015_network_monitoring.sql — Network Monitoring (Blueprint Section 13,
-- Gap 0.2: "client has zero live monitoring beyond MikroTik session state")
--
-- Generic monitored-target model so routers, OLTs, and (later) arbitrary
-- NAS/servers all flow through one alerting/incident pipeline rather than
-- separate bolted-on monitors per device type.
-- ============================================================

CREATE TABLE network.monitored_targets (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    target_type           VARCHAR(30) NOT NULL
                           CHECK (target_type IN ('mikrotik_router','olt_device','radius_nas','custom_host')),
    target_ref_id            UUID,       -- FK to mikrotik_routers.id / olt_devices.id / radius_nas.id, resolved by target_type
    label                       VARCHAR(150) NOT NULL,
    ip_address                    INET NOT NULL,
    check_interval_seconds           INT NOT NULL DEFAULT 60,
    is_active                          BOOLEAN NOT NULL DEFAULT true,
    created_at                           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_monitored_targets_tenant_active ON network.monitored_targets(tenant_id) WHERE is_active;

-- ---- Check results (ping/latency/packet-loss, rolled up) ----
-- High-volume, append-only, short-retention (app-layer job prunes rows
-- older than 7 days; 5-minute rollups persist longer via
-- analytics materialized views in a later phase if trend charts are needed).
CREATE TABLE network.monitoring_checks (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    target_id             UUID NOT NULL REFERENCES network.monitored_targets(id) ON DELETE CASCADE,
    is_reachable             BOOLEAN NOT NULL,
    latency_ms                  NUMERIC(8,2),
    packet_loss_pct                NUMERIC(5,2),
    checked_at                       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_monitoring_checks_target_time ON network.monitoring_checks(target_id, checked_at DESC);

-- ---- Alerts ----
CREATE TABLE network.network_alerts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    target_id             UUID REFERENCES network.monitored_targets(id) ON DELETE SET NULL,
    alert_type               VARCHAR(30) NOT NULL
                              CHECK (alert_type IN ('down','high_latency','packet_loss','onu_los','router_unreachable')),
    severity                    VARCHAR(20) NOT NULL DEFAULT 'warning' CHECK (severity IN ('info','warning','critical')),
    message                        TEXT NOT NULL,
    status                            VARCHAR(20) NOT NULL DEFAULT 'open' CHECK (status IN ('open','acknowledged','resolved')),
    acknowledged_by                     UUID REFERENCES identity.users(id),
    acknowledged_at                       TIMESTAMPTZ,
    resolved_at                             TIMESTAMPTZ,
    created_at                                TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_network_alerts_tenant_status ON network.network_alerts(tenant_id, status);
CREATE INDEX idx_network_alerts_target ON network.network_alerts(target_id, created_at DESC);

-- ---- Incidents (grouping of related alerts, for NOC workflow) ----
CREATE TABLE network.incidents (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    title                 VARCHAR(255) NOT NULL,
    status                  VARCHAR(20) NOT NULL DEFAULT 'investigating'
                             CHECK (status IN ('investigating','identified','monitoring','resolved')),
    started_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at                   TIMESTAMPTZ,
    created_by                       UUID REFERENCES identity.users(id)
);

CREATE TABLE network.incident_alerts (
    incident_id         UUID NOT NULL REFERENCES network.incidents(id) ON DELETE CASCADE,
    alert_id             UUID NOT NULL REFERENCES network.network_alerts(id) ON DELETE CASCADE,
    PRIMARY KEY (incident_id, alert_id)
);

-- ---- Trigger: uptime breach auto-creates an alert ----
-- Fires from the monitoring-poll job's INSERT into monitoring_checks
-- when three consecutive unreachable checks occur (debounced in the job,
-- not here, to avoid alert storms from a single blip) — this trigger
-- handles the simple single-check-based cases (e.g. ONU LOS, which the
-- OLT poller writes directly rather than via monitoring_checks).
CREATE OR REPLACE FUNCTION network.raise_alert_if_needed()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_reachable = false THEN
        INSERT INTO network.network_alerts (tenant_id, target_id, alert_type, severity, message)
        SELECT NEW.tenant_id, NEW.target_id, 'down', 'critical',
               'Target unreachable: ' || mt.label
        FROM network.monitored_targets mt WHERE mt.id = NEW.target_id
        AND NOT EXISTS (
            SELECT 1 FROM network.network_alerts na
            WHERE na.target_id = NEW.target_id AND na.status = 'open' AND na.alert_type = 'down'
        );
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_raise_alert AFTER INSERT ON network.monitoring_checks
    FOR EACH ROW EXECUTE FUNCTION network.raise_alert_if_needed();

-- ---- RLS ----
ALTER TABLE network.monitored_targets ENABLE ROW LEVEL SECURITY;   ALTER TABLE network.monitored_targets FORCE ROW LEVEL SECURITY;
ALTER TABLE network.monitoring_checks ENABLE ROW LEVEL SECURITY;    ALTER TABLE network.monitoring_checks FORCE ROW LEVEL SECURITY;
ALTER TABLE network.network_alerts ENABLE ROW LEVEL SECURITY;        ALTER TABLE network.network_alerts FORCE ROW LEVEL SECURITY;
ALTER TABLE network.incidents ENABLE ROW LEVEL SECURITY;              ALTER TABLE network.incidents FORCE ROW LEVEL SECURITY;
ALTER TABLE network.incident_alerts ENABLE ROW LEVEL SECURITY;         ALTER TABLE network.incident_alerts FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON network.monitored_targets USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON network.monitoring_checks USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON network.network_alerts USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON network.incidents USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON network.incident_alerts USING (
    EXISTS (SELECT 1 FROM network.incidents i WHERE i.id = incident_alerts.incident_id AND i.tenant_id = platform.current_tenant_id())
);
