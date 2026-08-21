-- ============================================================
-- 007_billing.sql — billing domain (Blueprint Section 14)
-- Reproduces AS-IS audit's verified Bill Collection + Payment modal
-- exactly; adds invoice as first-class entity (audit had running-due
-- balance only, not discrete invoices) to support partial/advance
-- payment allocation cleanly.
-- ============================================================

-- Per-tenant human-facing invoice numbering
CREATE TABLE billing.invoice_sequences (
    tenant_id           UUID PRIMARY KEY REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    next_number          BIGINT NOT NULL DEFAULT 1
);

CREATE TABLE billing.invoices (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id              UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    customer_service_id    UUID NOT NULL REFERENCES isp.customer_services(id) ON DELETE CASCADE,
    invoice_no              VARCHAR(50) NOT NULL,
    billing_period_month     INT NOT NULL CHECK (billing_period_month BETWEEN 1 AND 12),
    billing_period_year       INT NOT NULL,
    amount_due                 NUMERIC(12,2) NOT NULL DEFAULT 0,   -- package monthly_bill at generation time
    discount_amount             NUMERIC(12,2) NOT NULL DEFAULT 0,
    previous_due_carried          NUMERIC(12,2) NOT NULL DEFAULT 0,
    total_due                      NUMERIC(12,2) NOT NULL DEFAULT 0,   -- amount_due - discount + previous_due_carried
    total_paid                      NUMERIC(12,2) NOT NULL DEFAULT 0,
    status                           VARCHAR(20) NOT NULL DEFAULT 'unpaid'
                                      CHECK (status IN ('unpaid','partial','paid','void')),
    due_date                          DATE,
    generated_at                       TIMESTAMPTZ NOT NULL DEFAULT now(),
    generated_by                        VARCHAR(20) NOT NULL DEFAULT 'system' CHECK (generated_by IN ('system','manual')),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, customer_service_id, billing_period_year, billing_period_month),
    UNIQUE (tenant_id, invoice_no)
);
CREATE TRIGGER trg_invoices_updated_at BEFORE UPDATE ON billing.invoices
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_invoices_tenant_status_due ON billing.invoices(tenant_id, status, due_date);
CREATE INDEX idx_invoices_customer_service ON billing.invoices(customer_service_id);

-- ---- Payments ----
-- Preserves exactly the verified Payment modal fields: Due Amount (readonly,
-- derived), Pay Amount, Discount Amount, auto-generated Description,
-- Payment Date, Collector (Billing Person). Description auto-generation
-- ("Bill collection for {Month}-{Year} From Customer {Name}") is an
-- application-layer concern, not stored redundantly here beyond the field.
CREATE TABLE billing.payments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    invoice_id           UUID NOT NULL REFERENCES billing.invoices(id) ON DELETE CASCADE,
    amount                NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    discount_amount        NUMERIC(12,2) NOT NULL DEFAULT 0,
    method                  VARCHAR(30) NOT NULL DEFAULT 'cash'
                             CHECK (method IN ('cash','bkash','nagad','sslcommerz','stripe','bank','other')),
    transaction_reference     VARCHAR(150),
    collector_id                UUID REFERENCES identity.users(id),   -- "Billing Person" in audit
    description                  TEXT,
    is_advance                    BOOLEAN NOT NULL DEFAULT false,
    paid_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at                     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_payments_tenant_paid_at ON billing.payments(tenant_id, paid_at DESC);
CREATE INDEX idx_payments_invoice ON billing.payments(invoice_id);
CREATE INDEX idx_payments_collector ON billing.payments(tenant_id, collector_id);

-- ---- Discount / Bonus ledger ----
-- Audit found this is an agent/referral-bonus style ledger, not simple
-- bill discounts [INFERRED business rule] — modeled generically so both
-- interpretations are supported without a later migration.
CREATE TABLE billing.discount_beneficiaries (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    agent_name           VARCHAR(255) NOT NULL,
    agent_address          TEXT,
    agent_phone              VARCHAR(30),
    agent_email                CITEXT,
    bonus_amount                 NUMERIC(12,2) NOT NULL DEFAULT 0,
    related_customer_id           UUID REFERENCES isp.customers(id),
    status                         VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','cancelled')),
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_discount_beneficiaries_updated_at BEFORE UPDATE ON billing.discount_beneficiaries
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_discount_beneficiaries_tenant ON billing.discount_beneficiaries(tenant_id);

-- ---- Connection Charge (audit: verified one-time fee ledger) ----
CREATE TABLE billing.connection_charges (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    customer_id           UUID NOT NULL REFERENCES isp.customers(id) ON DELETE CASCADE,
    amount                 NUMERIC(12,2) NOT NULL,
    description              TEXT,
    charged_by                 UUID REFERENCES identity.users(id),   -- "Agent Email" in audit -> normalized to user FK
    charged_at                   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_connection_charges_tenant_date ON billing.connection_charges(tenant_id, charged_at DESC);

-- ---- RLS ----
ALTER TABLE billing.invoices ENABLE ROW LEVEL SECURITY;              ALTER TABLE billing.invoices FORCE ROW LEVEL SECURITY;
ALTER TABLE billing.payments ENABLE ROW LEVEL SECURITY;               ALTER TABLE billing.payments FORCE ROW LEVEL SECURITY;
ALTER TABLE billing.discount_beneficiaries ENABLE ROW LEVEL SECURITY;  ALTER TABLE billing.discount_beneficiaries FORCE ROW LEVEL SECURITY;
ALTER TABLE billing.connection_charges ENABLE ROW LEVEL SECURITY;       ALTER TABLE billing.connection_charges FORCE ROW LEVEL SECURITY;
ALTER TABLE billing.invoice_sequences ENABLE ROW LEVEL SECURITY;         ALTER TABLE billing.invoice_sequences FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON billing.invoices USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON billing.payments USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON billing.discount_beneficiaries USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON billing.connection_charges USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON billing.invoice_sequences USING (tenant_id = platform.current_tenant_id());

-- ---- Trigger: keep invoice.total_paid / status in sync with payments ----
CREATE OR REPLACE FUNCTION billing.recalc_invoice_on_payment()
RETURNS TRIGGER AS $$
DECLARE
    v_total_paid NUMERIC(12,2);
    v_total_due NUMERIC(12,2);
BEGIN
    SELECT COALESCE(SUM(amount),0) INTO v_total_paid
    FROM billing.payments WHERE invoice_id = COALESCE(NEW.invoice_id, OLD.invoice_id);

    SELECT total_due INTO v_total_due FROM billing.invoices WHERE id = COALESCE(NEW.invoice_id, OLD.invoice_id);

    UPDATE billing.invoices
    SET total_paid = v_total_paid,
        status = CASE
            WHEN v_total_paid <= 0 THEN 'unpaid'
            WHEN v_total_paid < v_total_due THEN 'partial'
            ELSE 'paid'
        END
    WHERE id = COALESCE(NEW.invoice_id, OLD.invoice_id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_recalc_invoice_on_payment
AFTER INSERT OR UPDATE OR DELETE ON billing.payments
FOR EACH ROW EXECUTE FUNCTION billing.recalc_invoice_on_payment();
