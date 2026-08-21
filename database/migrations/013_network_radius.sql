-- ============================================================
-- 013_network_radius.sql — RADIUS AAA (Blueprint Section 13, Gap 0.2)
--
-- New, optional, PARALLEL AAA path alongside direct MikroTik API control
-- (Phase 1). A tenant can keep pure-MikroTik operation (matching the
-- verified client behavior exactly) or opt into RADIUS for multi-vendor
-- NAS support and DHCP/IPoE/Hotspot protocols beyond PPPoE-via-MikroTik.
-- Schema is FreeRADIUS-compatible in shape (radcheck/radacct-equivalent
-- concepts) so a tenant's RADIUS data can interoperate with standard
-- tooling if they later self-host or migrate.
-- ============================================================

CREATE TABLE network.radius_nas (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(150) NOT NULL,
    ip_address            INET NOT NULL,
    secret_encrypted        TEXT NOT NULL,            -- app-layer AES-256-GCM, same convention as MikroTik creds
    vendor                    VARCHAR(50) NOT NULL DEFAULT 'mikrotik',  -- mikrotik, cisco, huawei, generic
    nas_type                    VARCHAR(20) NOT NULL DEFAULT 'pppoe'
                                 CHECK (nas_type IN ('pppoe','dhcp','ipoe','hotspot')),
    status                        VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, ip_address)
);
CREATE TRIGGER trg_radius_nas_updated_at BEFORE UPDATE ON network.radius_nas
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

-- Link pppoe_secrets (Phase 1) to a NAS when RADIUS-managed rather than
-- direct-MikroTik-managed. Nullable — pure-MikroTik tenants leave this null.
ALTER TABLE network.pppoe_secrets
    ADD COLUMN radius_nas_id UUID REFERENCES network.radius_nas(id) ON DELETE SET NULL,
    ADD COLUMN auth_protocol VARCHAR(20) NOT NULL DEFAULT 'mikrotik_api'
        CHECK (auth_protocol IN ('mikrotik_api','radius'));
CREATE INDEX idx_pppoe_secrets_radius_nas ON network.pppoe_secrets(radius_nas_id) WHERE radius_nas_id IS NOT NULL;

-- ---- RADIUS Accounting (session records — radacct-equivalent) ----
-- For RADIUS-managed secrets, this REPLACES network.pppoe_sessions as the
-- source of session state (same conceptual data, RADIUS Accounting-sourced
-- instead of MikroTik-API-polled). The Online/Offline UI views read from
-- whichever source is active per secret via auth_protocol.
CREATE TABLE network.radius_accounting (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    pppoe_secret_id      UUID NOT NULL REFERENCES network.pppoe_secrets(id) ON DELETE CASCADE,
    nas_id                 UUID NOT NULL REFERENCES network.radius_nas(id),
    session_id                VARCHAR(100) NOT NULL,     -- Acct-Session-Id
    framed_ip_address            INET,                     -- assigned IP (PPPoE/DHCP/IPoE)
    calling_station_id              MACADDR,                -- client MAC
    session_start                     TIMESTAMPTZ NOT NULL,
    session_stop                        TIMESTAMPTZ,
    input_octets                          BIGINT NOT NULL DEFAULT 0,
    output_octets                           BIGINT NOT NULL DEFAULT 0,
    terminate_cause                           VARCHAR(50),
    UNIQUE (nas_id, session_id)
);
CREATE INDEX idx_radius_accounting_secret ON network.radius_accounting(pppoe_secret_id, session_start DESC);
CREATE INDEX idx_radius_accounting_active ON network.radius_accounting(tenant_id) WHERE session_stop IS NULL;

-- ---- RADIUS CoA (Change of Authorization) audit trail ----
-- Every disconnect/reconnect/bandwidth-change sent to a RADIUS-managed
-- NAS is logged here — the RADIUS-path equivalent of
-- network.auto_disconnect_logs for MikroTik-API-managed secrets.
CREATE TABLE network.radius_coa_requests (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    pppoe_secret_id      UUID NOT NULL REFERENCES network.pppoe_secrets(id) ON DELETE CASCADE,
    request_type           VARCHAR(20) NOT NULL CHECK (request_type IN ('disconnect','reconnect','bandwidth_change')),
    status                    VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','ack','nak','timeout')),
    requested_by                UUID REFERENCES identity.users(id),
    requested_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    responded_at                     TIMESTAMPTZ
);
CREATE INDEX idx_coa_requests_tenant_requested ON network.radius_coa_requests(tenant_id, requested_at DESC);

-- ---- RLS ----
ALTER TABLE network.radius_nas ENABLE ROW LEVEL SECURITY;             ALTER TABLE network.radius_nas FORCE ROW LEVEL SECURITY;
ALTER TABLE network.radius_accounting ENABLE ROW LEVEL SECURITY;       ALTER TABLE network.radius_accounting FORCE ROW LEVEL SECURITY;
ALTER TABLE network.radius_coa_requests ENABLE ROW LEVEL SECURITY;      ALTER TABLE network.radius_coa_requests FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON network.radius_nas USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON network.radius_accounting USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON network.radius_coa_requests USING (tenant_id = platform.current_tenant_id());
