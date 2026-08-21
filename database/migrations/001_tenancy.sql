-- ============================================================
-- 001_tenancy.sql — tenancy domain (Blueprint Section 4, 7.4)
-- ============================================================

CREATE TABLE tenancy.tenants (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                VARCHAR(255) NOT NULL,
    slug                CITEXT NOT NULL UNIQUE,
    business_type       VARCHAR(50) NOT NULL DEFAULT 'isp'
                         CHECK (business_type IN ('isp','wisp','ftth','cable_tv','ip_phone','cctv','corporate_network')),
    status              VARCHAR(20) NOT NULL DEFAULT 'trial'
                         CHECK (status IN ('trial','active','suspended','cancelled')),
    contact_email       CITEXT,
    contact_phone       VARCHAR(30),
    default_timezone    VARCHAR(64) NOT NULL DEFAULT 'Asia/Dhaka',
    default_currency    CHAR(3) NOT NULL DEFAULT 'BDT',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ
);
CREATE TRIGGER trg_tenants_updated_at BEFORE UPDATE ON tenancy.tenants
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_tenants_status ON tenancy.tenants(status) WHERE deleted_at IS NULL;

CREATE TABLE tenancy.branches (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(255) NOT NULL,
    code                VARCHAR(50) NOT NULL,
    address             TEXT,
    is_head_office      BOOLEAN NOT NULL DEFAULT false,
    status              VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ,
    UNIQUE (tenant_id, code)
);
CREATE TRIGGER trg_branches_updated_at BEFORE UPDATE ON tenancy.branches
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_branches_tenant ON tenancy.branches(tenant_id) WHERE deleted_at IS NULL;

-- Every tenant must have exactly one head office branch enforced at app layer
-- (a partial unique index can't express "exactly one" cleanly across inserts,
-- so this is enforced in the TenantProvisioningService, not the DB).
