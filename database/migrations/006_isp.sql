-- ============================================================
-- 006_isp.sql — isp domain (Blueprint Section 7.4, 9)
-- Reproduces AS-IS audit's verified Customer Setting + Customers
-- modules exactly, extended with customer_services for multi-service
-- support (FTTH/CableTV/IPPhone bundles per one customer).
-- ============================================================

-- ---- Zone / SubZone / Destination hierarchy ----
-- (audit: 24 real zones observed; SubZone/Destination defined but
-- unused in current data — preserved as first-class optional hierarchy)
CREATE TABLE isp.zones (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(150) NOT NULL,
    is_active           BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ,
    UNIQUE (tenant_id, name)
);
CREATE TRIGGER trg_zones_updated_at BEFORE UPDATE ON isp.zones
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TABLE isp.subzones (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    zone_id             UUID NOT NULL REFERENCES isp.zones(id) ON DELETE CASCADE,
    name                VARCHAR(150) NOT NULL,
    is_active           BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_subzones_updated_at BEFORE UPDATE ON isp.subzones
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TABLE isp.destinations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    subzone_id          UUID REFERENCES isp.subzones(id) ON DELETE SET NULL,
    name                VARCHAR(150) NOT NULL,
    is_active           BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_destinations_updated_at BEFORE UPDATE ON isp.destinations
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

-- ---- Packages (audit: 5 packages, Mikrotik profile linkage, bill amount) ----
CREATE TABLE isp.packages (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(150) NOT NULL,             -- e.g. '12MB','100MB'
    mikrotik_profile_name VARCHAR(150),
    monthly_bill        NUMERIC(12,2) NOT NULL DEFAULT 0,
    bandwidth_down_mbps  NUMERIC(10,2),
    bandwidth_up_mbps    NUMERIC(10,2),
    is_active           BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ
);
CREATE TRIGGER trg_packages_updated_at BEFORE UPDATE ON isp.packages
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

-- ---- Customers ----
-- Every field below maps 1:1 to a [VERIFIED] field in the AS-IS audit's
-- Create/Edit Customer form (Section 5 of the audit). Nothing renamed
-- away from recognizable meaning; nothing dropped.
CREATE TABLE isp.customers (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    branch_id               UUID REFERENCES tenancy.branches(id),
    customer_code           VARCHAR(50) NOT NULL,           -- human-facing sequential ID
    full_name               VARCHAR(255) NOT NULL,
    mobile                  VARCHAR(30) NOT NULL,
    other_mobile             VARCHAR(30),
    email                    CITEXT,
    gender                   VARCHAR(10) CHECK (gender IN ('male','female','other')),
    onu_mac_address           MACADDR,
    nid_passport_no           VARCHAR(50),
    nid_passport_photo_path   VARCHAR(500),
    address                   TEXT,
    fiber_code                VARCHAR(100),
    agent_type                VARCHAR(30) CHECK (agent_type IN ('optical_fiber','cat5')),
    connection_type            VARCHAR(30) CHECK (connection_type IN ('home','corporate')),
    connection_date             DATE,
    zone_id                     UUID REFERENCES isp.zones(id),
    subzone_id                  UUID REFERENCES isp.subzones(id),
    destination_id               UUID REFERENCES isp.destinations(id),
    billing_person_id             UUID REFERENCES identity.users(id),
    status                        VARCHAR(20) NOT NULL DEFAULT 'active'
                                   CHECK (status IN ('active','inactive','free','discontinue')),
    remarks                       TEXT,
    sms_notification_enabled       BOOLEAN NOT NULL DEFAULT true,
    previous_due                    NUMERIC(12,2) NOT NULL DEFAULT 0,
    temp_disconnect_day             INT,
    created_by                       UUID REFERENCES identity.users(id),
    created_at                       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                       TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at                       TIMESTAMPTZ,
    UNIQUE (tenant_id, customer_code)
);
CREATE TRIGGER trg_customers_updated_at BEFORE UPDATE ON isp.customers
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_customers_tenant_status ON isp.customers(tenant_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_customers_tenant_zone ON isp.customers(tenant_id, zone_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_customers_billing_person ON isp.customers(tenant_id, billing_person_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_customers_mobile ON isp.customers(tenant_id, mobile);

-- ---- Customer Delete Log (audit: verified separate list of deleted customers) ----
CREATE TABLE isp.customer_delete_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    customer_snapshot_json JSONB NOT NULL,   -- full row snapshot at time of delete
    deleted_by          UUID REFERENCES identity.users(id),
    reason               TEXT,
    deleted_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_customer_delete_log_tenant ON isp.customer_delete_logs(tenant_id, deleted_at DESC);

-- ---- Customer Services ----
-- [NEW] Decouples "a customer" from "a billed service", enabling
-- multi-service-per-customer (Section 0.2 gap: FTTH/CableTV/IPPhone
-- bundles). For pure Phase-1 parity, every legacy customer gets exactly
-- ONE customer_service row of type 'internet' created at migration time.
CREATE TABLE isp.customer_services (
    id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    customer_id              UUID NOT NULL REFERENCES isp.customers(id) ON DELETE CASCADE,
    service_type             VARCHAR(30) NOT NULL DEFAULT 'internet'
                              CHECK (service_type IN ('internet','cable_tv','ip_phone','cctv')),
    package_id               UUID REFERENCES isp.packages(id),
    monthly_bill              NUMERIC(12,2) NOT NULL DEFAULT 0,
    effective_from_current_month BOOLEAN NOT NULL DEFAULT true,
    running_month_paid_amount  NUMERIC(12,2) NOT NULL DEFAULT 0,
    connection_fee_paid        NUMERIC(12,2) NOT NULL DEFAULT 0,
    disconnect_day              INT NOT NULL DEFAULT 5,
    status                       VARCHAR(20) NOT NULL DEFAULT 'active'
                                  CHECK (status IN ('active','inactive','free','discontinue')),
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at                   TIMESTAMPTZ
);
CREATE TRIGGER trg_customer_services_updated_at BEFORE UPDATE ON isp.customer_services
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_customer_services_customer ON isp.customer_services(customer_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_customer_services_tenant_status ON isp.customer_services(tenant_id, status);

-- ---- Business Target (audit: verified module) ----
CREATE TABLE isp.business_targets (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(150) NOT NULL,
    target_type         VARCHAR(30) NOT NULL
                         CHECK (target_type IN ('bill_collection','user_growth','complaint_rate')),
    year                INT NOT NULL,
    yearly_target        NUMERIC(14,2) NOT NULL,
    monthly_targets_json  JSONB NOT NULL DEFAULT '{}', -- {"1": 10000, "2": 12000, ...}
    created_by            UUID REFERENCES identity.users(id),
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_business_targets_updated_at BEFORE UPDATE ON isp.business_targets
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_business_targets_tenant_year ON isp.business_targets(tenant_id, year);

-- ---- RLS ----
ALTER TABLE isp.zones ENABLE ROW LEVEL SECURITY;              ALTER TABLE isp.zones FORCE ROW LEVEL SECURITY;
ALTER TABLE isp.subzones ENABLE ROW LEVEL SECURITY;            ALTER TABLE isp.subzones FORCE ROW LEVEL SECURITY;
ALTER TABLE isp.destinations ENABLE ROW LEVEL SECURITY;         ALTER TABLE isp.destinations FORCE ROW LEVEL SECURITY;
ALTER TABLE isp.packages ENABLE ROW LEVEL SECURITY;              ALTER TABLE isp.packages FORCE ROW LEVEL SECURITY;
ALTER TABLE isp.customers ENABLE ROW LEVEL SECURITY;              ALTER TABLE isp.customers FORCE ROW LEVEL SECURITY;
ALTER TABLE isp.customer_delete_logs ENABLE ROW LEVEL SECURITY;    ALTER TABLE isp.customer_delete_logs FORCE ROW LEVEL SECURITY;
ALTER TABLE isp.customer_services ENABLE ROW LEVEL SECURITY;        ALTER TABLE isp.customer_services FORCE ROW LEVEL SECURITY;
ALTER TABLE isp.business_targets ENABLE ROW LEVEL SECURITY;          ALTER TABLE isp.business_targets FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON isp.zones USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON isp.subzones USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON isp.destinations USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON isp.packages USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON isp.customers USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON isp.customer_delete_logs USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON isp.customer_services USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON isp.business_targets USING (tenant_id = platform.current_tenant_id());
