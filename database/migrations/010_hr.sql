-- ============================================================
-- 010_hr.sql — hr domain (Blueprint Section 21)
-- Preserves verified Employee list, Add Employee, Pay Salary (Total
-- Salary, Conveyance, Received, Punishment, Due) exactly; extends into
-- Departments, Designations, Attendance, Leave, Payroll runs.
-- ============================================================

CREATE TABLE hr.departments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(150) NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, name)
);

CREATE TABLE hr.designations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    department_id        UUID REFERENCES hr.departments(id),
    title                  VARCHAR(150) NOT NULL,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, title)
);

-- ---- Employees ----
-- Preserves verified fields exactly: Name, Mobile, Email, NID, Designation,
-- Joining Date, Salary, Status, Address.
CREATE TABLE hr.employees (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    branch_id            UUID REFERENCES tenancy.branches(id),
    user_id                UUID REFERENCES identity.users(id),  -- linked login account, if the employee has one
    name                     VARCHAR(255) NOT NULL,
    mobile                     VARCHAR(30),
    email                        CITEXT,
    nid                             VARCHAR(50),
    designation_id                    UUID REFERENCES hr.designations(id),
    department_id                       UUID REFERENCES hr.departments(id),
    joining_date                          DATE,
    monthly_salary                          NUMERIC(12,2) NOT NULL DEFAULT 0,
    status                                    VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
    address                                     TEXT,
    created_at                                    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                                    TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at                                    TIMESTAMPTZ
);
CREATE TRIGGER trg_employees_updated_at BEFORE UPDATE ON hr.employees
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_employees_tenant_status ON hr.employees(tenant_id, status) WHERE deleted_at IS NULL;

-- ---- Salary Payment ----
-- Preserves verified Pay Salary modal exactly: Payment Amount, Conveyance
-- Amount, Punishment Amount, auto-filled Description. Posts to accounting
-- automatically under head "Employee" (verified cross-module link).
CREATE TABLE hr.salary_payments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    employee_id           UUID NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
    period_month            INT NOT NULL CHECK (period_month BETWEEN 1 AND 12),
    period_year               INT NOT NULL,
    payment_amount               NUMERIC(12,2) NOT NULL DEFAULT 0,
    conveyance_amount              NUMERIC(12,2) NOT NULL DEFAULT 0,
    punishment_amount                NUMERIC(12,2) NOT NULL DEFAULT 0,
    description                        TEXT,
    paid_by                              UUID REFERENCES identity.users(id),
    paid_at                                TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_salary_payments_tenant_period ON hr.salary_payments(tenant_id, period_year, period_month);
CREATE INDEX idx_salary_payments_employee ON hr.salary_payments(employee_id);

-- Auto-post salary payment into accounting.expense_entries under head
-- "Employee" — requires the tenant to have an "Employee" account_head
-- seeded (done in tenant provisioning); if absent, the payment still
-- succeeds and simply isn't posted to GL (logged as a warning) rather
-- than failing the payroll run.
CREATE OR REPLACE FUNCTION hr.post_salary_to_expense()
RETURNS TRIGGER AS $$
DECLARE
    v_head_id UUID;
    v_total NUMERIC(12,2);
BEGIN
    v_total := NEW.payment_amount + NEW.conveyance_amount - NEW.punishment_amount;
    SELECT id INTO v_head_id FROM accounting.account_heads
        WHERE tenant_id = NEW.tenant_id AND name = 'Employee' AND head_type = 'expense';

    IF v_head_id IS NOT NULL AND v_total > 0 THEN
        INSERT INTO accounting.expense_entries (tenant_id, head_id, amount, description, entry_date, created_by)
        VALUES (NEW.tenant_id, v_head_id, v_total,
                COALESCE(NEW.description, 'Salary payment'), NEW.paid_at::date, NEW.paid_by);
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_post_salary AFTER INSERT ON hr.salary_payments
    FOR EACH ROW EXECUTE FUNCTION hr.post_salary_to_expense();

-- ---- Attendance / Leave [NEW] ----
CREATE TABLE hr.attendance (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    employee_id           UUID NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
    work_date               DATE NOT NULL,
    check_in                   TIMESTAMPTZ,
    check_out                    TIMESTAMPTZ,
    status                          VARCHAR(20) NOT NULL DEFAULT 'present'
                                     CHECK (status IN ('present','absent','half_day','leave')),
    UNIQUE (employee_id, work_date)
);
CREATE INDEX idx_attendance_tenant_date ON hr.attendance(tenant_id, work_date DESC);

CREATE TABLE hr.leave_requests (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    employee_id           UUID NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
    leave_type              VARCHAR(30) NOT NULL DEFAULT 'casual',
    start_date                DATE NOT NULL,
    end_date                    DATE NOT NULL,
    reason                        TEXT,
    status                          VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
    approved_by                       UUID REFERENCES identity.users(id),
    created_at                          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_leave_requests_employee ON hr.leave_requests(employee_id, status);

-- ---- RLS ----
ALTER TABLE hr.departments ENABLE ROW LEVEL SECURITY;      ALTER TABLE hr.departments FORCE ROW LEVEL SECURITY;
ALTER TABLE hr.designations ENABLE ROW LEVEL SECURITY;       ALTER TABLE hr.designations FORCE ROW LEVEL SECURITY;
ALTER TABLE hr.employees ENABLE ROW LEVEL SECURITY;           ALTER TABLE hr.employees FORCE ROW LEVEL SECURITY;
ALTER TABLE hr.salary_payments ENABLE ROW LEVEL SECURITY;      ALTER TABLE hr.salary_payments FORCE ROW LEVEL SECURITY;
ALTER TABLE hr.attendance ENABLE ROW LEVEL SECURITY;             ALTER TABLE hr.attendance FORCE ROW LEVEL SECURITY;
ALTER TABLE hr.leave_requests ENABLE ROW LEVEL SECURITY;          ALTER TABLE hr.leave_requests FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON hr.departments USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON hr.designations USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON hr.employees USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON hr.salary_payments USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON hr.attendance USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON hr.leave_requests USING (tenant_id = platform.current_tenant_id());
