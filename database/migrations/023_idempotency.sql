-- ============================================================
-- 023_idempotency.sql — offline-first sync support.
--
-- Every mutation created offline carries a client-generated idempotency
-- key. The server records the key on first successful processing and
-- returns the ORIGINAL result for any replay. This is what makes
-- "duplicate payment through retry" technically impossible rather than
-- merely unlikely.
--
-- Also adds optimistic-concurrency revisions so an offline edit based on
-- a stale copy is detected as a CONFLICT instead of silently overwriting
-- newer server data.
-- ============================================================

CREATE TABLE IF NOT EXISTS integrations.idempotency_keys (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    idempotency_key     VARCHAR(100) NOT NULL,
    operation_type      VARCHAR(60) NOT NULL,       -- CREATE_PAYMENT, CREATE_CUSTOMER, ...
    device_id           VARCHAR(80),
    request_fingerprint VARCHAR(128) NOT NULL,      -- sha256 of the payload
    response_json       JSONB,                      -- original result, replayed verbatim
    response_status     INT NOT NULL DEFAULT 201,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- The key is unique PER TENANT: a replay from any device of the same
    -- tenant resolves to the same stored result.
    UNIQUE (tenant_id, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_idem_tenant_created ON integrations.idempotency_keys(tenant_id, created_at DESC);

ALTER TABLE integrations.idempotency_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE integrations.idempotency_keys FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON integrations.idempotency_keys;
CREATE POLICY tenant_isolation ON integrations.idempotency_keys
    USING (tenant_id = platform.current_tenant_id());

-- ---- Optimistic concurrency: revision counters ----
-- An offline client sends the revision it last saw. If the server's
-- revision has moved on, the write is rejected as a conflict.
ALTER TABLE isp.customers      ADD COLUMN IF NOT EXISTS revision INT NOT NULL DEFAULT 1;
ALTER TABLE support.tickets    ADD COLUMN IF NOT EXISTS revision INT NOT NULL DEFAULT 1;
ALTER TABLE isp.customer_services ADD COLUMN IF NOT EXISTS revision INT NOT NULL DEFAULT 1;
ALTER TABLE support.field_jobs    ADD COLUMN IF NOT EXISTS revision INT NOT NULL DEFAULT 1;
ALTER TABLE inventory.products    ADD COLUMN IF NOT EXISTS revision INT NOT NULL DEFAULT 1;

CREATE OR REPLACE FUNCTION platform.bump_revision()
RETURNS TRIGGER AS $$
BEGIN
    NEW.revision := COALESCE(OLD.revision, 0) + 1;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_customers_revision ON isp.customers;
CREATE TRIGGER trg_customers_revision BEFORE UPDATE ON isp.customers
    FOR EACH ROW EXECUTE FUNCTION platform.bump_revision();
DROP TRIGGER IF EXISTS trg_tickets_revision ON support.tickets;
CREATE TRIGGER trg_tickets_revision BEFORE UPDATE ON support.tickets
    FOR EACH ROW EXECUTE FUNCTION platform.bump_revision();
DROP TRIGGER IF EXISTS trg_services_revision ON isp.customer_services;
DROP TRIGGER IF EXISTS trg_field_jobs_revision ON support.field_jobs;
CREATE TRIGGER trg_field_jobs_revision BEFORE UPDATE ON support.field_jobs
    FOR EACH ROW EXECUTE FUNCTION platform.bump_revision();
DROP TRIGGER IF EXISTS trg_products_revision ON inventory.products;
CREATE TRIGGER trg_products_revision BEFORE UPDATE ON inventory.products
    FOR EACH ROW EXECUTE FUNCTION platform.bump_revision();

CREATE TRIGGER trg_services_revision BEFORE UPDATE ON isp.customer_services
    FOR EACH ROW EXECUTE FUNCTION platform.bump_revision();

-- ---- Offline sync device registry (spec: device registration / revocation) ----
CREATE TABLE IF NOT EXISTS identity.devices (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    user_id             UUID NOT NULL REFERENCES identity.users(id) ON DELETE CASCADE,
    device_id           VARCHAR(80) NOT NULL,
    label               VARCHAR(150),
    last_seen_at        TIMESTAMPTZ,
    revoked_at          TIMESTAMPTZ,          -- remote wipe: client purges local DB on next contact
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, device_id)
);
CREATE INDEX IF NOT EXISTS idx_devices_user ON identity.devices(user_id) WHERE revoked_at IS NULL;

ALTER TABLE identity.devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.devices FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON identity.devices;
CREATE POLICY tenant_isolation ON identity.devices
    USING (tenant_id = platform.current_tenant_id());
