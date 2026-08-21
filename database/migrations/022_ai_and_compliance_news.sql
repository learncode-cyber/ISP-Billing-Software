-- ============================================================
-- 022_ai_and_compliance_news.sql
-- AI Layer (Blueprint Section 22) + BTRC Regulatory News (Section 23).
--
-- News is PLATFORM-LEVEL (no tenant_id) and free on every plan
-- (compliance.news.view is is_platform_default=true, seeded in Phase 0).
-- Alerts/reports/advanced tools remain subscription-gated per the
-- explicit two-tier product decision.
-- ============================================================

-- ---- AI request log (every AI call, for audit + cost tracking) ----
-- Enforces the Blueprint rule that AI obeys tenant isolation, user
-- permissions, and entitlements: each row records WHO asked, in WHICH
-- tenant, so an AI answer can never be produced outside the caller's
-- RLS-scoped, permission-checked context.
CREATE TABLE ai.request_logs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    user_id               UUID REFERENCES identity.users(id),
    capability              VARCHAR(50) NOT NULL,   -- 'nl_analytics','churn_prediction','ticket_classification', ...
    prompt_summary            TEXT,
    tokens_used                 INT,
    status                        VARCHAR(20) NOT NULL DEFAULT 'success' CHECK (status IN ('success','failed','blocked')),
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ai_request_logs_tenant_time ON ai.request_logs(tenant_id, created_at DESC);

-- ---- Churn prediction results (written by the AI batch job) ----
CREATE TABLE ai.churn_predictions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    customer_id           UUID NOT NULL REFERENCES isp.customers(id) ON DELETE CASCADE,
    churn_risk_score        NUMERIC(5,2) NOT NULL,   -- 0.00 - 100.00
    risk_band                 VARCHAR(10) NOT NULL CHECK (risk_band IN ('low','medium','high')),
    top_factors_json            JSONB,               -- explainability: what drove the score
    predicted_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, customer_id, predicted_at)
);
CREATE INDEX idx_churn_predictions_tenant_band ON ai.churn_predictions(tenant_id, risk_band);

-- ---- Ticket classification suggestions ----
CREATE TABLE ai.ticket_classifications (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    ticket_id             UUID NOT NULL REFERENCES support.tickets(id) ON DELETE CASCADE,
    suggested_category_id   UUID REFERENCES support.ticket_categories(id),
    suggested_priority        VARCHAR(10),
    confidence                  NUMERIC(5,2),
    accepted                      BOOLEAN,   -- did a human accept the suggestion?
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---- BTRC Regulatory News (PLATFORM-LEVEL, no tenant_id) ----
CREATE TABLE compliance.btrc_news (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title                 VARCHAR(500) NOT NULL,
    body                    TEXT,
    source_url                VARCHAR(500),
    category                    VARCHAR(50),          -- 'license','spectrum','directive','notice','tariff'
    published_at                  TIMESTAMPTZ,
    ingestion_method                VARCHAR(20) NOT NULL DEFAULT 'manual'
                                     CHECK (ingestion_method IN ('scraped','manual')),
    review_status                      VARCHAR(20) NOT NULL DEFAULT 'draft'
                                        CHECK (review_status IN ('draft','pending_review','published','rejected')),
    reviewed_by                          UUID REFERENCES identity.users(id),   -- AR Qudrix platform staff
    is_published                           BOOLEAN NOT NULL DEFAULT false,
    created_at                               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                               TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_btrc_news_updated_at BEFORE UPDATE ON compliance.btrc_news
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_btrc_news_published ON compliance.btrc_news(published_at DESC) WHERE is_published;

-- Staging table for the hybrid scraper: candidates land here, get
-- deduplicated against btrc_news, and a platform admin approves before
-- anything becomes visible to tenants (moderation queue — balances
-- freshness with accuracy, since btrc.gov.bd exposes no official RSS/API).
CREATE TABLE compliance.btrc_news_candidates (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title                 VARCHAR(500) NOT NULL,
    source_url              VARCHAR(500) NOT NULL UNIQUE,   -- dedupe key
    raw_excerpt               TEXT,
    scraped_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed                     BOOLEAN NOT NULL DEFAULT false
);

-- ---- Tenant-level regulatory alert subscriptions (GATED: compliance.alerts) ----
CREATE TABLE compliance.alert_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    keyword                 VARCHAR(150) NOT NULL,   -- notify when news matching this keyword publishes
    channel                   VARCHAR(20) NOT NULL DEFAULT 'in_app' CHECK (channel IN ('in_app','sms','email')),
    is_active                   BOOLEAN NOT NULL DEFAULT true,
    created_at                    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_alert_subs_tenant ON compliance.alert_subscriptions(tenant_id) WHERE is_active;

-- ---- RLS ----
-- AI tables + tenant alert subscriptions are tenant-owned -> RLS.
-- btrc_news + btrc_news_candidates are PLATFORM-level -> NO RLS (readable
-- by all tenants when published; writable only by the platform-admin role).
DO $$
DECLARE stmt RECORD;
BEGIN
    FOR stmt IN SELECT * FROM (VALUES
        ('ai','request_logs'), ('ai','churn_predictions'), ('ai','ticket_classifications'),
        ('compliance','alert_subscriptions')
    ) AS v(sch, tbl) LOOP
        EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', stmt.sch, stmt.tbl);
        EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', stmt.sch, stmt.tbl);
        EXECUTE format('CREATE POLICY tenant_isolation ON %I.%I USING (tenant_id = platform.current_tenant_id())', stmt.sch, stmt.tbl);
    END LOOP;
END $$;
