-- ============================================================
-- 020_reseller.sql — reseller domain (Blueprint Section 18)
-- Tenant -> Franchise -> Reseller -> Sub-Reseller -> Customer, with
-- self-referential parent_reseller_id. Resellers see ONLY customers they
-- own — enforced by RLS tenant isolation PLUS an application-layer
-- OWN/ASSIGNED data-scope check (defense in depth), never UI filtering.
-- ============================================================

CREATE TABLE reseller.commission_rules (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(150) NOT NULL,
    calculation_type      VARCHAR(20) NOT NULL DEFAULT 'percentage'
                           CHECK (calculation_type IN ('percentage','fixed_per_customer','tiered')),
    percentage              NUMERIC(5,2),           -- for 'percentage'
    fixed_amount              NUMERIC(12,2),         -- for 'fixed_per_customer'
    tier_config_json            JSONB,               -- for 'tiered'
    created_at                    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE reseller.resellers (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    branch_id             UUID REFERENCES tenancy.branches(id),
    parent_reseller_id      UUID REFERENCES reseller.resellers(id),  -- self-FK: sub-reseller/franchise chain
    user_id                   UUID REFERENCES identity.users(id),     -- reseller's login account
    reseller_type               VARCHAR(20) NOT NULL DEFAULT 'reseller'
                                 CHECK (reseller_type IN ('franchise','dealer','reseller','sub_reseller')),
    name                          VARCHAR(255) NOT NULL,
    mobile                          VARCHAR(30),
    email                             CITEXT,
    address                             TEXT,
    commission_rule_id                    UUID REFERENCES reseller.commission_rules(id),
    wallet_balance                          NUMERIC(14,2) NOT NULL DEFAULT 0,
    credit_limit                              NUMERIC(14,2) NOT NULL DEFAULT 0,
    status                                      VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended')),
    created_at                                    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                                    TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at                                    TIMESTAMPTZ
);
CREATE TRIGGER trg_resellers_updated_at BEFORE UPDATE ON reseller.resellers
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_resellers_tenant ON reseller.resellers(tenant_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_resellers_parent ON reseller.resellers(parent_reseller_id);

-- Customer ownership — which reseller "owns" a customer. Added as a FK
-- on the customer side so the RLS/scope check on isp.customers can filter
-- by it. Nullable: direct-tenant customers have no reseller owner.
ALTER TABLE isp.customers
    ADD COLUMN reseller_id UUID REFERENCES reseller.resellers(id) ON DELETE SET NULL;
CREATE INDEX idx_customers_reseller ON isp.customers(reseller_id) WHERE reseller_id IS NOT NULL;

-- ---- Reseller wallet transactions (recharge, commission credit, customer-bill debit, settlement) ----
CREATE TABLE reseller.wallet_transactions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    reseller_id           UUID NOT NULL REFERENCES reseller.resellers(id) ON DELETE CASCADE,
    txn_type                VARCHAR(20) NOT NULL
                             CHECK (txn_type IN ('recharge','commission','bill_debit','settlement','adjustment')),
    amount                    NUMERIC(14,2) NOT NULL,   -- signed: + credit, - debit
    balance_after               NUMERIC(14,2) NOT NULL,
    reference_type                VARCHAR(50),
    reference_id                    UUID,
    description                       TEXT,
    created_by                          UUID REFERENCES identity.users(id),
    created_at                            TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_wallet_txns_reseller_time ON reseller.wallet_transactions(reseller_id, created_at DESC);

-- ---- Commission earnings ledger ----
CREATE TABLE reseller.commission_earnings (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    reseller_id           UUID NOT NULL REFERENCES reseller.resellers(id) ON DELETE CASCADE,
    payment_id              UUID REFERENCES billing.payments(id),   -- the customer payment that generated commission
    amount                    NUMERIC(12,2) NOT NULL,
    status                      VARCHAR(20) NOT NULL DEFAULT 'accrued' CHECK (status IN ('accrued','settled')),
    earned_at                     TIMESTAMPTZ NOT NULL DEFAULT now(),
    settled_at                      TIMESTAMPTZ
);
CREATE INDEX idx_commission_earnings_reseller ON reseller.commission_earnings(reseller_id, status);

-- ---- RLS ----
DO $$
DECLARE t TEXT;
BEGIN
    FOR t IN SELECT unnest(ARRAY['commission_rules','resellers','wallet_transactions','commission_earnings']) LOOP
        EXECUTE format('ALTER TABLE reseller.%I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('ALTER TABLE reseller.%I FORCE ROW LEVEL SECURITY', t);
        EXECUTE format('CREATE POLICY tenant_isolation ON reseller.%I USING (tenant_id = platform.current_tenant_id())', t);
    END LOOP;
END $$;
