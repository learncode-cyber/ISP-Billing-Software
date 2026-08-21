-- ============================================================
-- 004_audit.sql — audit domain (Blueprint Section 28)
-- Generalizes: Activity Log, Auto MikroTik Disable Log, Auto SMS Log
-- ============================================================

CREATE TABLE audit.activity_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID REFERENCES tenancy.tenants(id) ON DELETE SET NULL,
    user_id             UUID REFERENCES identity.users(id) ON DELETE SET NULL,
    action              VARCHAR(100) NOT NULL,      -- e.g. 'customer.created','payment.received','mikrotik.auto_disconnect'
    entity_type         VARCHAR(100),                -- e.g. 'isp.customers'
    entity_id           UUID,
    ip_address          INET,
    device              VARCHAR(255),
    before_json         JSONB,
    after_json          JSONB,
    result              VARCHAR(20) NOT NULL DEFAULT 'success' CHECK (result IN ('success','failed')),
    source              VARCHAR(30) NOT NULL DEFAULT 'user' CHECK (source IN ('user','cron','automation','system')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
    -- No updated_at / deleted_at: append-only by design, never mutated.
);
CREATE INDEX idx_activity_tenant_created ON audit.activity_logs(tenant_id, created_at DESC);
CREATE INDEX idx_activity_user_created ON audit.activity_logs(user_id, created_at DESC);
CREATE INDEX idx_activity_entity ON audit.activity_logs(entity_type, entity_id);
CREATE INDEX idx_activity_before_gin ON audit.activity_logs USING GIN (before_json);
CREATE INDEX idx_activity_after_gin ON audit.activity_logs USING GIN (after_json);

-- Revoke UPDATE/DELETE at the DB role level (defense in depth beyond app code)
-- Actual role name to be created during environment provisioning, e.g.:
--   REVOKE UPDATE, DELETE ON audit.activity_logs FROM arq_app_role;
