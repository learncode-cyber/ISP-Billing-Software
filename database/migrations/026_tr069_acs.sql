-- ============================================================
-- 026_tr069_acs.sql — TR-069 / CWMP Auto Configuration Server.
--
-- Market context: this is Splynx's headline differentiator over Sonar,
-- and no Bangladeshi competitor (ISP Digital, NetFee, Maxim, ISP Robot)
-- offers it. It removes the single most expensive recurring cost an FTTH
-- ISP has — sending a technician to configure or reset a customer router.
--
-- What TR-069 gives the ISP:
--   * zero-touch provisioning: CPE calls home on first boot, ACS pushes
--     PPPoE credentials, WiFi SSID/password, VLAN — no truck roll
--   * remote diagnostics: signal, uptime, connected clients, WAN status
--   * batch firmware upgrade across a fleet
--   * customer-initiated reboot / WiFi password change from the portal
--
-- Protocol shape (CWMP): the CPE opens the session with an Inform; the
-- ACS replies with queued RPCs (SetParameterValues, Download, Reboot,
-- Factory Reset...). So the ACS is a *task queue* the device drains,
-- which is exactly how this schema is modelled.
-- ============================================================

CREATE TABLE IF NOT EXISTS network.cpe_devices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    customer_service_id UUID REFERENCES isp.customer_services(id) ON DELETE SET NULL,
    -- CWMP identity (from the Inform message)
    serial_number       VARCHAR(150) NOT NULL,
    oui                 VARCHAR(20),                 -- Organizationally Unique Identifier
    product_class       VARCHAR(100),
    manufacturer        VARCHAR(100),
    model_name          VARCHAR(100),
    software_version    VARCHAR(80),
    hardware_version    VARCHAR(80),
    -- Connection Request: how the ACS wakes the device between Informs
    connection_request_url      VARCHAR(500),
    connection_request_user     VARCHAR(100),
    connection_request_pass_enc TEXT,
    -- Live state, refreshed on each Inform
    external_ip         INET,
    mac_address         MACADDR,
    uptime_seconds      BIGINT,
    wifi_ssid           VARCHAR(120),
    connected_clients   INT,
    rx_power_dbm        NUMERIC(6,2),                -- for GPON-capable CPE
    last_inform_at      TIMESTAMPTZ,
    status              VARCHAR(20) NOT NULL DEFAULT 'never_seen'
                         CHECK (status IN ('never_seen','online','offline','provisioning','error')),
    provisioned_at      TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, serial_number)
);
CREATE INDEX IF NOT EXISTS idx_cpe_tenant_status ON network.cpe_devices(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_cpe_service ON network.cpe_devices(customer_service_id);
CREATE INDEX IF NOT EXISTS idx_cpe_stale ON network.cpe_devices(tenant_id, last_inform_at);

-- Provisioning profiles: what to push to a class of device.
CREATE TABLE IF NOT EXISTS network.cpe_profiles (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(150) NOT NULL,
    -- Match rules decide which CPE gets this profile on first contact.
    match_manufacturer  VARCHAR(100),
    match_product_class VARCHAR(100),
    -- TR-098/TR-181 parameter paths → values. Kept as JSONB because the
    -- parameter tree differs per vendor and data model version.
    parameters_json     JSONB NOT NULL DEFAULT '{}',
    firmware_url        VARCHAR(500),
    firmware_version    VARCHAR(80),
    is_default          BOOLEAN NOT NULL DEFAULT false,
    is_active           BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, name)
);

-- The RPC queue a CPE drains on its next session.
CREATE TABLE IF NOT EXISTS network.cpe_tasks (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    cpe_device_id       UUID NOT NULL REFERENCES network.cpe_devices(id) ON DELETE CASCADE,
    rpc                 VARCHAR(40) NOT NULL
                         CHECK (rpc IN ('SetParameterValues','GetParameterValues','Download',
                                        'Reboot','FactoryReset','AddObject','DeleteObject')),
    payload_json        JSONB NOT NULL DEFAULT '{}',
    status              VARCHAR(20) NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending','sent','succeeded','failed','expired')),
    attempts            INT NOT NULL DEFAULT 0,
    max_attempts        INT NOT NULL DEFAULT 3,
    fault_code          VARCHAR(20),
    fault_string        TEXT,
    requested_by        UUID REFERENCES identity.users(id),
    -- Customer-initiated actions (portal reboot / WiFi change) are flagged
    -- so support can distinguish them from staff actions in the history.
    requested_by_customer BOOLEAN NOT NULL DEFAULT false,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    sent_at             TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_cpe_tasks_pending
    ON network.cpe_tasks(cpe_device_id, created_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_cpe_tasks_tenant ON network.cpe_tasks(tenant_id, created_at DESC);

-- Session log: every CWMP conversation, for diagnosing provisioning faults.
CREATE TABLE IF NOT EXISTS network.cpe_sessions (
    id                  BIGSERIAL PRIMARY KEY,
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    cpe_device_id       UUID REFERENCES network.cpe_devices(id) ON DELETE CASCADE,
    event_codes         VARCHAR(200),        -- "0 BOOTSTRAP", "1 BOOT", "6 CONNECTION REQUEST"
    source_ip           INET,
    tasks_delivered     INT NOT NULL DEFAULT 0,
    outcome             VARCHAR(20) NOT NULL DEFAULT 'ok' CHECK (outcome IN ('ok','fault','timeout')),
    started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at            TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_cpe_sessions_device ON network.cpe_sessions(cpe_device_id, started_at DESC);

-- Auto-link a CPE to the subscriber whose ONU MAC matches, so the device
-- appears on the customer record without manual pairing.
CREATE OR REPLACE FUNCTION network.autolink_cpe_to_service()
RETURNS TRIGGER AS $$
DECLARE v_service UUID;
BEGIN
    IF NEW.customer_service_id IS NULL AND NEW.mac_address IS NOT NULL THEN
        SELECT cs.id INTO v_service
        FROM isp.customers c
        JOIN isp.customer_services cs ON cs.customer_id = c.id
        WHERE c.tenant_id = NEW.tenant_id
          AND c.onu_mac_address = NEW.mac_address
          AND cs.deleted_at IS NULL
        LIMIT 1;
        IF v_service IS NOT NULL THEN
            NEW.customer_service_id := v_service;
        END IF;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_autolink_cpe ON network.cpe_devices;
CREATE TRIGGER trg_autolink_cpe BEFORE INSERT OR UPDATE ON network.cpe_devices
    FOR EACH ROW EXECUTE FUNCTION network.autolink_cpe_to_service();

-- Fleet view for the CPE dashboard.
DROP VIEW IF EXISTS network.v_cpe_fleet;
CREATE VIEW network.v_cpe_fleet AS
SELECT d.tenant_id, d.id, d.serial_number, d.manufacturer, d.model_name,
       d.software_version, d.status, d.last_inform_at, d.external_ip,
       d.wifi_ssid, d.connected_clients, d.uptime_seconds,
       c.full_name AS customer_name, c.customer_code,
       (SELECT count(*) FROM network.cpe_tasks t
         WHERE t.cpe_device_id = d.id AND t.status = 'pending') AS pending_tasks
FROM network.cpe_devices d
LEFT JOIN isp.customer_services cs ON cs.id = d.customer_service_id
LEFT JOIN isp.customers c ON c.id = cs.customer_id;

-- RLS
DO $$ DECLARE t TEXT; BEGIN
  FOR t IN SELECT unnest(ARRAY['cpe_devices','cpe_profiles','cpe_tasks','cpe_sessions']) LOOP
    EXECUTE format('ALTER TABLE network.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE network.%I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON network.%I', t);
    EXECUTE format('CREATE POLICY tenant_isolation ON network.%I USING (tenant_id = platform.current_tenant_id())', t);
  END LOOP;
END $$;
