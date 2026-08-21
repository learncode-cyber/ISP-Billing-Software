-- ============================================================
-- 003_subscription.sql — subscription & entitlement engine
-- (Blueprint Section 5)
-- ============================================================

CREATE TABLE subscription.plans (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code                VARCHAR(50) NOT NULL UNIQUE,   -- 'starter','professional','business','enterprise'
    name                VARCHAR(100) NOT NULL,
    description         TEXT,
    price_amount        NUMERIC(12,2) NOT NULL DEFAULT 0,
    price_currency      CHAR(3) NOT NULL DEFAULT 'BDT',
    billing_cycle       VARCHAR(20) NOT NULL DEFAULT 'monthly' CHECK (billing_cycle IN ('monthly','yearly')),
    trial_days          INT NOT NULL DEFAULT 14,
    is_active           BOOLEAN NOT NULL DEFAULT true,
    sort_order          INT NOT NULL DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_plans_updated_at BEFORE UPDATE ON subscription.plans
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

-- Canonical feature key catalog. `is_platform_default` = force-enabled on
-- every plan regardless of plan_features rows — used for compliance.news.view
-- per explicit product decision (BTRC news is free on all tiers).
CREATE TABLE subscription.features (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key                 VARCHAR(150) NOT NULL UNIQUE,  -- e.g. 'network.olt.manage'
    module              VARCHAR(100) NOT NULL,
    name                VARCHAR(150) NOT NULL,
    description         TEXT,
    is_platform_default BOOLEAN NOT NULL DEFAULT false,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_features_module ON subscription.features(module);

CREATE TABLE subscription.plan_features (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id             UUID NOT NULL REFERENCES subscription.plans(id) ON DELETE CASCADE,
    feature_id          UUID NOT NULL REFERENCES subscription.features(id) ON DELETE CASCADE,
    is_enabled          BOOLEAN NOT NULL DEFAULT true,
    limit_value         INT,          -- e.g. max_customers, max_routers; NULL = unlimited
    UNIQUE (plan_id, feature_id)
);

CREATE TABLE subscription.tenant_subscriptions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    plan_id             UUID NOT NULL REFERENCES subscription.plans(id),
    status              VARCHAR(20) NOT NULL DEFAULT 'trial'
                         CHECK (status IN ('trial','active','past_due','suspended','cancelled')),
    current_period_start TIMESTAMPTZ NOT NULL DEFAULT now(),
    current_period_end   TIMESTAMPTZ NOT NULL,
    grace_period_ends_at  TIMESTAMPTZ,
    cancelled_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id)   -- one active subscription record per tenant (history kept in a log table, Phase 1)
);
CREATE TRIGGER trg_tenant_subs_updated_at BEFORE UPDATE ON subscription.tenant_subscriptions
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_tenant_subs_status ON subscription.tenant_subscriptions(status);

CREATE TABLE subscription.tenant_feature_overrides (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    feature_id          UUID NOT NULL REFERENCES subscription.features(id) ON DELETE CASCADE,
    is_enabled          BOOLEAN NOT NULL,
    limit_value         INT,
    reason              VARCHAR(255),
    granted_by          UUID REFERENCES identity.users(id),
    expires_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, feature_id)
);
CREATE INDEX idx_overrides_tenant ON subscription.tenant_feature_overrides(tenant_id);

-- ------------------------------------------------------------
-- Effective-entitlement resolver (used by CheckEntitlement middleware;
-- backend should also cache this per-request, this function is the
-- authoritative fallback / used for admin diagnostics).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION subscription.resolve_feature_access(
    p_tenant_id UUID,
    p_feature_key VARCHAR
) RETURNS BOOLEAN AS $$
DECLARE
    v_feature_id UUID;
    v_is_platform_default BOOLEAN;
    v_override BOOLEAN;
    v_plan_enabled BOOLEAN;
BEGIN
    SELECT id, is_platform_default INTO v_feature_id, v_is_platform_default
    FROM subscription.features WHERE key = p_feature_key;

    IF v_feature_id IS NULL THEN
        RETURN false; -- unknown feature key = deny by default (secure default)
    END IF;

    IF v_is_platform_default THEN
        RETURN true; -- e.g. compliance.news.view — always on, per product decision
    END IF;

    SELECT is_enabled INTO v_override
    FROM subscription.tenant_feature_overrides
    WHERE tenant_id = p_tenant_id AND feature_id = v_feature_id
      AND (expires_at IS NULL OR expires_at > now());

    IF v_override IS NOT NULL THEN
        RETURN v_override;
    END IF;

    SELECT pf.is_enabled INTO v_plan_enabled
    FROM subscription.tenant_subscriptions ts
    JOIN subscription.plan_features pf ON pf.plan_id = ts.plan_id AND pf.feature_id = v_feature_id
    WHERE ts.tenant_id = p_tenant_id
      AND ts.status IN ('trial','active');

    RETURN COALESCE(v_plan_enabled, false);
END;
$$ LANGUAGE plpgsql STABLE;
