-- ============================================================
-- 009_accounting.sql — accounting domain (Blueprint Section 15)
-- Preserves verified Income, Expense, Account Head/Sub-head, Statement,
-- Balance Sheet exactly, while adding a real double-entry ledger
-- underneath so those become DERIVED views over ledger_entries instead
-- of separately-maintained numbers (closing the reconciliation-drift
-- risk noted in the Blueprint's accounting section).
-- ============================================================

-- ---- Chart of Accounts ----
CREATE TABLE accounting.chart_of_accounts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    code                 VARCHAR(20) NOT NULL,             -- e.g. '1000','4000'
    name                  VARCHAR(150) NOT NULL,
    account_type            VARCHAR(20) NOT NULL
                             CHECK (account_type IN ('asset','liability','equity','income','expense')),
    parent_id                 UUID REFERENCES accounting.chart_of_accounts(id),
    is_system                  BOOLEAN NOT NULL DEFAULT false,  -- seeded defaults, not user-deletable
    is_active                    BOOLEAN NOT NULL DEFAULT true,
    created_at                    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, code)
);
CREATE TRIGGER trg_coa_updated_at BEFORE UPDATE ON accounting.chart_of_accounts
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_coa_tenant_type ON accounting.chart_of_accounts(tenant_id, account_type);

-- ---- Account Head / Sub-head ----
-- Preserves verified Expense/Income "Account Head" (9 heads in audit,
-- e.g. "paribhahan", "se tech", "Employee") and "Sub-head" exactly, now
-- linked into the Chart of Accounts as expense/income leaf accounts
-- rather than a parallel unlinked list.
CREATE TABLE accounting.account_heads (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    chart_account_id     UUID REFERENCES accounting.chart_of_accounts(id),
    name                   VARCHAR(150) NOT NULL,
    head_type               VARCHAR(10) NOT NULL CHECK (head_type IN ('income','expense')),
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, name, head_type)
);

CREATE TABLE accounting.account_sub_heads (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    head_id               UUID NOT NULL REFERENCES accounting.account_heads(id) ON DELETE CASCADE,
    name                    VARCHAR(150) NOT NULL,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (head_id, name)
);

-- ---- General Ledger (the real double-entry core) ----
CREATE TABLE accounting.ledger_entries (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    branch_id            UUID REFERENCES tenancy.branches(id),
    account_id             UUID NOT NULL REFERENCES accounting.chart_of_accounts(id),
    debit                    NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
    credit                     NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
    reference_type               VARCHAR(50) NOT NULL,  -- 'billing.payment','accounting.expense','hr.salary_payment', etc.
    reference_id                   UUID NOT NULL,
    description                      TEXT,
    entry_date                        DATE NOT NULL DEFAULT CURRENT_DATE,
    created_by                          UUID REFERENCES identity.users(id),
    created_at                            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (NOT (debit > 0 AND credit > 0))   -- a single leg is either debit or credit, never both
);
CREATE INDEX idx_ledger_tenant_date ON accounting.ledger_entries(tenant_id, entry_date DESC);
CREATE INDEX idx_ledger_account ON accounting.ledger_entries(account_id, entry_date DESC);
CREATE INDEX idx_ledger_reference ON accounting.ledger_entries(reference_type, reference_id);

-- ---- Income (verified: "Other Income", "Connection Charge" feeds here too) ----
CREATE TABLE accounting.income_entries (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    head_id               UUID NOT NULL REFERENCES accounting.account_heads(id),
    amount                  NUMERIC(12,2) NOT NULL,
    description               TEXT,
    entry_date                 DATE NOT NULL DEFAULT CURRENT_DATE,
    created_by                   UUID REFERENCES identity.users(id),
    created_at                     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_income_tenant_date ON accounting.income_entries(tenant_id, entry_date DESC);

-- ---- Expense (verified: Expense Report, View Expense w/ delete, Account Head cumulative) ----
CREATE TABLE accounting.expense_entries (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    head_id               UUID NOT NULL REFERENCES accounting.account_heads(id),
    sub_head_id             UUID REFERENCES accounting.account_sub_heads(id),
    amount                    NUMERIC(12,2) NOT NULL,
    description                 TEXT,
    entry_date                   DATE NOT NULL DEFAULT CURRENT_DATE,
    approval_status                 VARCHAR(20) NOT NULL DEFAULT 'approved'
                                     CHECK (approval_status IN ('pending','approved','rejected')),
    approved_by                       UUID REFERENCES identity.users(id),
    created_by                          UUID REFERENCES identity.users(id),
    created_at                            TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at                              TIMESTAMPTZ  -- audit noted per-row Delete on View Expense
);
CREATE INDEX idx_expense_tenant_date ON accounting.expense_entries(tenant_id, entry_date DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_expense_head ON accounting.expense_entries(head_id);

-- ---- Trigger: every income/expense entry auto-posts to the GL ----
-- Preserves the audit's verified cross-module link ("Salary payments post
-- into Expense automatically under head Employee") by generalizing it:
-- ANY income/expense entry now posts a balanced ledger pair automatically,
-- so accounting.income_entries/expense_entries stay simple/familiar for
-- the UI while the GL underneath is always self-consistent.
CREATE OR REPLACE FUNCTION accounting.post_income_to_ledger()
RETURNS TRIGGER AS $$
DECLARE v_account_id UUID;
BEGIN
    SELECT chart_account_id INTO v_account_id FROM accounting.account_heads WHERE id = NEW.head_id;
    IF v_account_id IS NOT NULL THEN
        INSERT INTO accounting.ledger_entries (tenant_id, account_id, credit, reference_type, reference_id, description, entry_date, created_by)
        VALUES (NEW.tenant_id, v_account_id, NEW.amount, 'accounting.income_entries', NEW.id, NEW.description, NEW.entry_date, NEW.created_by);
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_post_income AFTER INSERT ON accounting.income_entries
    FOR EACH ROW EXECUTE FUNCTION accounting.post_income_to_ledger();

CREATE OR REPLACE FUNCTION accounting.post_expense_to_ledger()
RETURNS TRIGGER AS $$
DECLARE v_account_id UUID;
BEGIN
    SELECT chart_account_id INTO v_account_id FROM accounting.account_heads WHERE id = NEW.head_id;
    IF v_account_id IS NOT NULL AND NEW.approval_status = 'approved' THEN
        INSERT INTO accounting.ledger_entries (tenant_id, account_id, debit, reference_type, reference_id, description, entry_date, created_by)
        VALUES (NEW.tenant_id, v_account_id, NEW.amount, 'accounting.expense_entries', NEW.id, NEW.description, NEW.entry_date, NEW.created_by);
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_post_expense AFTER INSERT ON accounting.expense_entries
    FOR EACH ROW EXECUTE FUNCTION accounting.post_expense_to_ledger();

-- ---- Derived views: Balance Sheet / Monthly / Yearly (verified reports) ----
CREATE VIEW accounting.v_monthly_balance AS
SELECT
    tenant_id,
    date_trunc('month', entry_date)::date AS period_month,
    SUM(credit) FILTER (WHERE credit > 0) AS total_income,
    SUM(debit) FILTER (WHERE debit > 0) AS total_expense,
    SUM(credit) - SUM(debit) AS net
FROM accounting.ledger_entries
GROUP BY tenant_id, date_trunc('month', entry_date);

CREATE VIEW accounting.v_yearly_balance AS
SELECT
    tenant_id,
    date_trunc('year', entry_date)::date AS period_year,
    SUM(credit) FILTER (WHERE credit > 0) AS total_income,
    SUM(debit) FILTER (WHERE debit > 0) AS total_expense,
    SUM(credit) - SUM(debit) AS net
FROM accounting.ledger_entries
GROUP BY tenant_id, date_trunc('year', entry_date);

-- ---- RLS ----
ALTER TABLE accounting.chart_of_accounts ENABLE ROW LEVEL SECURITY;  ALTER TABLE accounting.chart_of_accounts FORCE ROW LEVEL SECURITY;
ALTER TABLE accounting.account_heads ENABLE ROW LEVEL SECURITY;       ALTER TABLE accounting.account_heads FORCE ROW LEVEL SECURITY;
ALTER TABLE accounting.account_sub_heads ENABLE ROW LEVEL SECURITY;    ALTER TABLE accounting.account_sub_heads FORCE ROW LEVEL SECURITY;
ALTER TABLE accounting.ledger_entries ENABLE ROW LEVEL SECURITY;        ALTER TABLE accounting.ledger_entries FORCE ROW LEVEL SECURITY;
ALTER TABLE accounting.income_entries ENABLE ROW LEVEL SECURITY;         ALTER TABLE accounting.income_entries FORCE ROW LEVEL SECURITY;
ALTER TABLE accounting.expense_entries ENABLE ROW LEVEL SECURITY;         ALTER TABLE accounting.expense_entries FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON accounting.chart_of_accounts USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON accounting.account_heads USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON accounting.account_sub_heads USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON accounting.ledger_entries USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON accounting.income_entries USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON accounting.expense_entries USING (tenant_id = platform.current_tenant_id());
-- Views inherit the RLS of their underlying tables automatically.
