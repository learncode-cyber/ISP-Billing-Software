-- ============================================================
-- 024_ipam.sql — IP Address Management (Blueprint module 13).
-- IPv4 + IPv6 subnets, pools, allocations, reservations, conflict
-- detection, customer/service + router/NAS linkage, utilisation.
-- Uses native inet/cidr types so overlap and containment checks are
-- enforced by PostgreSQL rather than application string maths.
-- ============================================================

CREATE TABLE IF NOT EXISTS network.ip_subnets (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name            VARCHAR(150) NOT NULL,
    cidr            CIDR NOT NULL,
    family          SMALLINT GENERATED ALWAYS AS (family(cidr)) STORED,  -- 4 or 6
    gateway         INET,
    vlan_id         INT,
    description     TEXT,
    router_id       UUID REFERENCES network.mikrotik_routers(id) ON DELETE SET NULL,
    nas_id          UUID REFERENCES network.radius_nas(id) ON DELETE SET NULL,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, cidr)
);
CREATE INDEX IF NOT EXISTS idx_ip_subnets_tenant ON network.ip_subnets(tenant_id);
CREATE INDEX IF NOT EXISTS idx_ip_subnets_cidr ON network.ip_subnets USING gist (cidr inet_ops);

CREATE TABLE IF NOT EXISTS network.ip_pools (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    subnet_id       UUID NOT NULL REFERENCES network.ip_subnets(id) ON DELETE CASCADE,
    name            VARCHAR(150) NOT NULL,
    range_start     INET NOT NULL,
    range_end       INET NOT NULL,
    purpose         VARCHAR(30) NOT NULL DEFAULT 'pppoe'
                     CHECK (purpose IN ('pppoe','dhcp','static','hotspot','management')),
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (range_end >= range_start),
    UNIQUE (tenant_id, name)
);
CREATE INDEX IF NOT EXISTS idx_ip_pools_subnet ON network.ip_pools(subnet_id);

CREATE TABLE IF NOT EXISTS network.ip_allocations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    subnet_id           UUID NOT NULL REFERENCES network.ip_subnets(id) ON DELETE CASCADE,
    pool_id             UUID REFERENCES network.ip_pools(id) ON DELETE SET NULL,
    ip_address          INET NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'allocated'
                         CHECK (status IN ('allocated','reserved','quarantined','released')),
    customer_service_id UUID REFERENCES isp.customer_services(id) ON DELETE SET NULL,
    pppoe_secret_id     UUID REFERENCES network.pppoe_secrets(id) ON DELETE SET NULL,
    hostname            VARCHAR(150),
    mac_address         MACADDR,
    note                TEXT,
    allocated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    released_at         TIMESTAMPTZ,
    created_by          UUID REFERENCES identity.users(id),
    -- CONFLICT DETECTION: the same address cannot be live twice in a tenant.
    -- Partial unique index so released addresses can be re-allocated.
    CONSTRAINT ip_alloc_addr_valid CHECK (masklen(ip_address) = 32 OR family(ip_address) = 6)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_ip_alloc_unique_live
    ON network.ip_allocations (tenant_id, ip_address)
    WHERE status IN ('allocated','reserved','quarantined');
CREATE INDEX IF NOT EXISTS idx_ip_alloc_subnet ON network.ip_allocations(subnet_id);
CREATE INDEX IF NOT EXISTS idx_ip_alloc_service ON network.ip_allocations(customer_service_id);

-- Guard: an allocation must fall inside its subnet.
CREATE OR REPLACE FUNCTION network.assert_ip_in_subnet()
RETURNS TRIGGER AS $$
DECLARE v_cidr CIDR;
BEGIN
    SELECT cidr INTO v_cidr FROM network.ip_subnets WHERE id = NEW.subnet_id;
    IF v_cidr IS NULL THEN RAISE EXCEPTION 'Subnet not found'; END IF;
    IF NOT (NEW.ip_address <<= v_cidr) THEN
        RAISE EXCEPTION 'IP % is outside subnet %', NEW.ip_address, v_cidr;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_ip_in_subnet ON network.ip_allocations;
CREATE TRIGGER trg_ip_in_subnet BEFORE INSERT OR UPDATE ON network.ip_allocations
    FOR EACH ROW EXECUTE FUNCTION network.assert_ip_in_subnet();

-- Guard: subnets within a tenant must not overlap.
CREATE OR REPLACE FUNCTION network.assert_no_subnet_overlap()
RETURNS TRIGGER AS $$
DECLARE v_conflict CIDR;
BEGIN
    SELECT cidr INTO v_conflict FROM network.ip_subnets
     WHERE tenant_id = NEW.tenant_id
       AND (TG_OP = 'INSERT' OR id <> NEW.id)
       AND id IS DISTINCT FROM NEW.id
       AND (cidr && NEW.cidr) LIMIT 1;
    IF v_conflict IS NOT NULL THEN
        RAISE EXCEPTION 'Subnet % overlaps existing subnet %', NEW.cidr, v_conflict;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_subnet_overlap ON network.ip_subnets;
CREATE TRIGGER trg_subnet_overlap BEFORE INSERT OR UPDATE ON network.ip_subnets
    FOR EACH ROW EXECUTE FUNCTION network.assert_no_subnet_overlap();

-- Utilisation view
DROP VIEW IF EXISTS network.v_subnet_utilisation;
CREATE VIEW network.v_subnet_utilisation AS
SELECT s.tenant_id, s.id AS subnet_id, s.name, s.cidr,
       CASE WHEN family(s.cidr) = 4
            THEN POWER(2, 32 - masklen(s.cidr))::BIGINT
            ELSE NULL END AS total_addresses,
       COUNT(a.id) FILTER (WHERE a.status IN ('allocated','reserved','quarantined')) AS used_addresses
FROM network.ip_subnets s
LEFT JOIN network.ip_allocations a ON a.subnet_id = s.id
GROUP BY s.tenant_id, s.id, s.name, s.cidr;

-- RLS
DO $$ DECLARE t TEXT; BEGIN
  FOR t IN SELECT unnest(ARRAY['ip_subnets','ip_pools','ip_allocations']) LOOP
    EXECUTE format('ALTER TABLE network.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE network.%I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON network.%I', t);
    EXECUTE format('CREATE POLICY tenant_isolation ON network.%I USING (tenant_id = platform.current_tenant_id())', t);
  END LOOP;
END $$;
