-- ============================================================
-- 014_network_olt_gpon.sql — OLT / PON / ONU (Blueprint Section 13)
--
-- Extends the audit's verified OLT device registration form fields
-- exactly (Device Type: BDCOM/V-SOL/ZTE/Huawei/Fiberhome, Device IP,
-- Login Username, Password, SNMP Port default 161, SNMP Community
-- default 'public', Telnet Port, "Check Connection") into the full
-- hierarchy the audit flagged as [NOT VERIFIED post-registration
-- behavior] because no device was live during the audit — activates
-- automatically the moment a tenant registers a real device.
-- ============================================================

CREATE TABLE network.olt_devices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    device_name           VARCHAR(150) NOT NULL,
    device_type              VARCHAR(30) NOT NULL
                              CHECK (device_type IN ('bdcom','v-sol','zte','huawei','fiberhome')),
    device_ip                  INET NOT NULL,
    login_username_encrypted     TEXT NOT NULL,
    password_encrypted             TEXT NOT NULL,
    snmp_port                        INT NOT NULL DEFAULT 161,
    snmp_community_encrypted           TEXT NOT NULL,   -- default 'public', still encrypted at rest
    telnet_port                          INT,
    connection_status                      VARCHAR(20) NOT NULL DEFAULT 'unknown'
                                            CHECK (connection_status IN ('unknown','connected','unreachable','error')),
    last_checked_at                          TIMESTAMPTZ,
    created_at                                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at                                 TIMESTAMPTZ
);
CREATE TRIGGER trg_olt_devices_updated_at BEFORE UPDATE ON network.olt_devices
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_olt_devices_tenant ON network.olt_devices(tenant_id) WHERE deleted_at IS NULL;

-- ---- PON Ports ----
CREATE TABLE network.pon_ports (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    olt_device_id         UUID NOT NULL REFERENCES network.olt_devices(id) ON DELETE CASCADE,
    port_label              VARCHAR(50) NOT NULL,     -- e.g. '0/1/1'
    max_onu_capacity          INT,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (olt_device_id, port_label)
);
CREATE INDEX idx_pon_ports_olt ON network.pon_ports(olt_device_id);

-- ---- ONU / ONT ----
-- customer_service_id links straight into the billed service, closing
-- the audit's [NOT VERIFIED] Customer<->ONU<->PON<->OLT mapping gap.
-- onu_mac_address here is authoritative post-registration; isp.customers
-- .onu_mac_address (Phase 1 field, preserved from the audit's Create
-- Customer form) remains the pre-registration/manually-entered value —
-- kept in sync by the discovery job when they match.
CREATE TABLE network.onu_devices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    pon_port_id           UUID NOT NULL REFERENCES network.pon_ports(id) ON DELETE CASCADE,
    customer_service_id     UUID REFERENCES isp.customer_services(id) ON DELETE SET NULL,
    serial_number              VARCHAR(150),
    mac_address                   MACADDR,
    vlan_id                          INT,
    rx_power_dbm                       NUMERIC(6,2),   -- received optical power
    tx_power_dbm                         NUMERIC(6,2),
    status                                  VARCHAR(20) NOT NULL DEFAULT 'offline'
                                             CHECK (status IN ('online','offline','los')),  -- LOS = Loss of Signal
    last_seen_at                              TIMESTAMPTZ,
    created_at                                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, serial_number)
);
CREATE TRIGGER trg_onu_devices_updated_at BEFORE UPDATE ON network.onu_devices
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_onu_devices_pon_port ON network.onu_devices(pon_port_id);
CREATE INDEX idx_onu_devices_customer_service ON network.onu_devices(customer_service_id);
CREATE INDEX idx_onu_devices_status ON network.onu_devices(tenant_id, status);

-- ---- ONU status history (LOS alarm trail — feeds Automation Engine
-- "ONU LOS -> Ticket" rule in Phase 4, and Network Monitoring alerts) ----
CREATE TABLE network.onu_status_events (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    onu_device_id         UUID NOT NULL REFERENCES network.onu_devices(id) ON DELETE CASCADE,
    previous_status          VARCHAR(20),
    new_status                  VARCHAR(20) NOT NULL,
    rx_power_dbm                  NUMERIC(6,2),
    occurred_at                     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_onu_status_events_device ON network.onu_status_events(onu_device_id, occurred_at DESC);

-- Trigger: log a status_event row whenever onu_devices.status changes
-- (SNMP-poll job updates onu_devices.status; this keeps the history
-- automatically without every poller having to remember to insert it).
CREATE OR REPLACE FUNCTION network.log_onu_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO network.onu_status_events (tenant_id, onu_device_id, previous_status, new_status, rx_power_dbm)
        VALUES (NEW.tenant_id, NEW.id, OLD.status, NEW.status, NEW.rx_power_dbm);
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_onu_status_change AFTER UPDATE ON network.onu_devices
    FOR EACH ROW EXECUTE FUNCTION network.log_onu_status_change();

-- ---- RLS ----
ALTER TABLE network.olt_devices ENABLE ROW LEVEL SECURITY;        ALTER TABLE network.olt_devices FORCE ROW LEVEL SECURITY;
ALTER TABLE network.pon_ports ENABLE ROW LEVEL SECURITY;           ALTER TABLE network.pon_ports FORCE ROW LEVEL SECURITY;
ALTER TABLE network.onu_devices ENABLE ROW LEVEL SECURITY;          ALTER TABLE network.onu_devices FORCE ROW LEVEL SECURITY;
ALTER TABLE network.onu_status_events ENABLE ROW LEVEL SECURITY;     ALTER TABLE network.onu_status_events FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON network.olt_devices USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON network.pon_ports USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON network.onu_devices USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON network.onu_status_events USING (tenant_id = platform.current_tenant_id());
