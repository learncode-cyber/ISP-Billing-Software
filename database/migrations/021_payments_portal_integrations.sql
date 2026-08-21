-- ============================================================
-- 021_payments_portal_integrations.sql
-- Payment Gateway adapters (Blueprint Section 14), Customer Portal auth
-- (Section 25), and the integrations domain (API keys, webhooks — Section
-- 12). Closes the largest confirmed competitive gap (Section 0.2):
-- customer self-service online payment.
-- ============================================================

-- ---- Payment gateway configuration (per tenant, encrypted secrets) ----
CREATE TABLE billing.payment_gateways (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    provider              VARCHAR(30) NOT NULL
                           CHECK (provider IN ('bkash','nagad','sslcommerz','stripe')),
    display_name            VARCHAR(100) NOT NULL,
    credentials_encrypted     TEXT NOT NULL,     -- JSON blob (api key/secret/merchant id), AES-256-GCM
    is_sandbox                  BOOLEAN NOT NULL DEFAULT true,
    is_active                     BOOLEAN NOT NULL DEFAULT false,
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, provider)
);
CREATE TRIGGER trg_payment_gateways_updated_at BEFORE UPDATE ON billing.payment_gateways
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

-- ---- Online payment attempts (gateway round-trip tracking + reconciliation) ----
CREATE TABLE billing.payment_gateway_transactions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    gateway_id            UUID NOT NULL REFERENCES billing.payment_gateways(id),
    invoice_id              UUID REFERENCES billing.invoices(id),
    payment_id                UUID REFERENCES billing.payments(id),  -- set once confirmed + payment row created
    gateway_reference           VARCHAR(200),
    amount                        NUMERIC(12,2) NOT NULL,
    status                          VARCHAR(20) NOT NULL DEFAULT 'initiated'
                                     CHECK (status IN ('initiated','pending','success','failed','cancelled','refunded')),
    raw_response_json                 JSONB,
    initiated_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at                          TIMESTAMPTZ
);
CREATE INDEX idx_pg_txns_tenant_status ON billing.payment_gateway_transactions(tenant_id, status);
CREATE INDEX idx_pg_txns_gateway_ref ON billing.payment_gateway_transactions(gateway_reference);

-- ---- Customer Portal accounts ----
-- Separate auth identity from staff identity.users — a customer logs in
-- with mobile/customer_code + password/OTP, scoped strictly to their own
-- data (OWN). Never mixed into identity.users to keep staff RBAC and
-- customer auth cleanly separated.
CREATE TABLE isp.customer_portal_accounts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    customer_id           UUID NOT NULL REFERENCES isp.customers(id) ON DELETE CASCADE,
    login_identifier        VARCHAR(50) NOT NULL,   -- mobile or customer_code
    password_hash             VARCHAR(255),
    otp_secret                  VARCHAR(255),
    is_active                     BOOLEAN NOT NULL DEFAULT true,
    last_login_at                   TIMESTAMPTZ,
    created_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, login_identifier)
);
CREATE INDEX idx_portal_accounts_customer ON isp.customer_portal_accounts(customer_id);

-- ---- Integrations: API keys + webhooks (Blueprint Section 12) ----
CREATE TABLE integrations.api_keys (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(100) NOT NULL,
    key_prefix            VARCHAR(12) NOT NULL,       -- shown in UI, e.g. 'arq_live_'
    key_hash                VARCHAR(255) NOT NULL UNIQUE,  -- full key hashed, never stored plaintext
    scopes_json               JSONB NOT NULL DEFAULT '[]',  -- feature keys this API key may access
    rate_limit_per_minute       INT NOT NULL DEFAULT 60,
    last_used_at                  TIMESTAMPTZ,
    expires_at                      TIMESTAMPTZ,
    revoked_at                        TIMESTAMPTZ,
    created_by                          UUID REFERENCES identity.users(id),
    created_at                            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_api_keys_tenant ON integrations.api_keys(tenant_id) WHERE revoked_at IS NULL;

CREATE TABLE integrations.webhook_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    event_type            VARCHAR(50) NOT NULL,      -- 'payment.received','ticket.created','customer.disconnected', ...
    target_url              VARCHAR(500) NOT NULL,
    signing_secret_encrypted  TEXT NOT NULL,          -- HMAC signing secret for payload verification
    is_active                   BOOLEAN NOT NULL DEFAULT true,
    created_at                    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_webhook_subs_tenant_event ON integrations.webhook_subscriptions(tenant_id, event_type) WHERE is_active;

CREATE TABLE integrations.webhook_deliveries (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    subscription_id       UUID NOT NULL REFERENCES integrations.webhook_subscriptions(id) ON DELETE CASCADE,
    payload_json            JSONB NOT NULL,
    response_status           INT,
    attempt_count               INT NOT NULL DEFAULT 0,
    status                        VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','delivered','failed')),
    next_retry_at                   TIMESTAMPTZ,
    delivered_at                      TIMESTAMPTZ,
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_webhook_deliveries_pending ON integrations.webhook_deliveries(status, next_retry_at) WHERE status = 'pending';

CREATE TABLE integrations.api_request_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    api_key_id            UUID REFERENCES integrations.api_keys(id) ON DELETE SET NULL,
    method                  VARCHAR(10) NOT NULL,
    path                      VARCHAR(255) NOT NULL,
    response_status             INT,
    ip_address                    INET,
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_api_logs_tenant_time ON integrations.api_request_logs(tenant_id, created_at DESC);

-- ---- RLS ----
DO $$
DECLARE stmt RECORD;
BEGIN
    FOR stmt IN SELECT * FROM (VALUES
        ('billing','payment_gateways'),
        ('billing','payment_gateway_transactions'),
        ('isp','customer_portal_accounts'),
        ('integrations','api_keys'),
        ('integrations','webhook_subscriptions'),
        ('integrations','webhook_deliveries'),
        ('integrations','api_request_logs')
    ) AS v(sch, tbl) LOOP
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', stmt.sch, stmt.tbl);
        EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', stmt.sch, stmt.tbl);
        EXECUTE format('CREATE POLICY tenant_isolation ON %I.%I USING (tenant_id = platform.current_tenant_id())', stmt.sch, stmt.tbl);
    END LOOP;
END $$;
