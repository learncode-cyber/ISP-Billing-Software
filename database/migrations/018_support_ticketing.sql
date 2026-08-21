-- ============================================================
-- 018_support_ticketing.sql — support domain (Blueprint Section 19)
-- Preserves the audit's verified full complaint workflow (creation ->
-- assignment -> status tracking -> resolution) exactly: Select Customer,
-- Complain Template, Priority (High/Medium/Low), Note, single Employee-
-- for-Solve, Multiple Support Employees, Customer SMS + Assigned Employee
-- SMS toggles. Extends into ticket numbering, SLA, categories,
-- escalation, attachments, customer reply thread, resolution time, CSAT.
-- ============================================================

CREATE TABLE support.ticket_categories (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    parent_id             UUID REFERENCES support.ticket_categories(id),  -- category/subcategory via self-FK
    name                    VARCHAR(150) NOT NULL,
    default_sla_minutes        INT,
    UNIQUE (tenant_id, parent_id, name)
);

CREATE TABLE support.ticket_templates (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(150) NOT NULL,
    body_template         TEXT,
    UNIQUE (tenant_id, name)
);

CREATE TABLE support.ticket_sequences (
    tenant_id           UUID PRIMARY KEY REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    next_number          BIGINT NOT NULL DEFAULT 1
);

CREATE TABLE support.tickets (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    ticket_no             VARCHAR(50) NOT NULL,
    customer_id             UUID NOT NULL REFERENCES isp.customers(id) ON DELETE CASCADE,
    category_id               UUID REFERENCES support.ticket_categories(id),
    template_id                 UUID REFERENCES support.ticket_templates(id),
    priority                       VARCHAR(10) NOT NULL DEFAULT 'medium' CHECK (priority IN ('high','medium','low')),
    note                             TEXT,
    assigned_employee_id               UUID REFERENCES hr.employees(id),   -- "Employee-for-Solve" (single)
    status                                VARCHAR(20) NOT NULL DEFAULT 'pending'
                                          CHECK (status IN ('pending','processing','solved','not_solved','escalated')),
    sla_due_at                              TIMESTAMPTZ,
    resolved_at                               TIMESTAMPTZ,
    resolution_time_minutes                     INT,
    csat_rating                                   SMALLINT CHECK (csat_rating BETWEEN 1 AND 5),
    customer_sms_enabled                            BOOLEAN NOT NULL DEFAULT true,
    employee_sms_enabled                              BOOLEAN NOT NULL DEFAULT true,
    created_by                                          UUID REFERENCES identity.users(id),
    created_at                                            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                                            TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, ticket_no)
);
CREATE TRIGGER trg_tickets_updated_at BEFORE UPDATE ON support.tickets
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_tickets_tenant_status ON support.tickets(tenant_id, status);
CREATE INDEX idx_tickets_customer ON support.tickets(customer_id);
CREATE INDEX idx_tickets_assigned ON support.tickets(assigned_employee_id, status);

-- "Multiple Support Employees" — preserved as a separate join table since
-- the audit found this distinct from the single assigned_employee_id.
CREATE TABLE support.ticket_support_staff (
    ticket_id           UUID NOT NULL REFERENCES support.tickets(id) ON DELETE CASCADE,
    employee_id           UUID NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
    PRIMARY KEY (ticket_id, employee_id)
);

-- Internal notes + customer-visible reply thread — kept as separate
-- tables (not a single "comments" table) so internal notes can never
-- accidentally be exposed on the Customer Portal (Phase 5).
CREATE TABLE support.ticket_internal_notes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    ticket_id             UUID NOT NULL REFERENCES support.tickets(id) ON DELETE CASCADE,
    note                     TEXT NOT NULL,
    created_by                 UUID REFERENCES identity.users(id),
    created_at                    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE support.ticket_replies (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    ticket_id             UUID NOT NULL REFERENCES support.tickets(id) ON DELETE CASCADE,
    author_type              VARCHAR(10) NOT NULL CHECK (author_type IN ('staff','customer')),
    author_id                  UUID,   -- identity.users.id or isp.customers.id, resolved by author_type
    message                       TEXT NOT NULL,
    created_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ticket_replies_ticket ON support.ticket_replies(ticket_id, created_at);

CREATE TABLE support.ticket_attachments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    ticket_id             UUID NOT NULL REFERENCES support.tickets(id) ON DELETE CASCADE,
    file_path                VARCHAR(500) NOT NULL,
    uploaded_by                 UUID REFERENCES identity.users(id),
    uploaded_at                    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---- Escalation trail (feeds Automation Engine SLA-breach rule) ----
CREATE TABLE support.ticket_escalations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    ticket_id             UUID NOT NULL REFERENCES support.tickets(id) ON DELETE CASCADE,
    escalated_to             UUID REFERENCES identity.users(id),
    reason                      TEXT,
    escalated_at                   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Auto-set resolution_time_minutes when status flips to solved
CREATE OR REPLACE FUNCTION support.calc_resolution_time()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'solved' AND OLD.status <> 'solved' THEN
        NEW.resolved_at := now();
        NEW.resolution_time_minutes := EXTRACT(EPOCH FROM (now() - NEW.created_at)) / 60;
    END IF;
    RETURN NEW;
END; $$ LANGUAGE plpgsql;
CREATE TRIGGER trg_calc_resolution_time BEFORE UPDATE ON support.tickets
    FOR EACH ROW EXECUTE FUNCTION support.calc_resolution_time();

-- ============================================================
-- Field Service / Technician (Blueprint Section 19 second half)
-- Installation/Repair/Maintenance jobs, GPS check-in/out, photos,
-- signature, spare parts — links into inventory.stock_items for
-- parts consumption.
-- ============================================================
CREATE TABLE support.field_jobs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    ticket_id             UUID REFERENCES support.tickets(id) ON DELETE SET NULL,
    customer_id             UUID NOT NULL REFERENCES isp.customers(id) ON DELETE CASCADE,
    job_type                  VARCHAR(20) NOT NULL CHECK (job_type IN ('installation','repair','maintenance')),
    assigned_technician_id       UUID REFERENCES hr.employees(id),
    status                          VARCHAR(20) NOT NULL DEFAULT 'assigned'
                                     CHECK (status IN ('assigned','en_route','in_progress','completed','cancelled')),
    scheduled_at                       TIMESTAMPTZ,
    check_in_at                          TIMESTAMPTZ,
    check_in_lat                           NUMERIC(10,7),
    check_in_lng                             NUMERIC(10,7),
    check_out_at                               TIMESTAMPTZ,
    check_out_lat                                NUMERIC(10,7),
    check_out_lng                                  NUMERIC(10,7),
    customer_signature_path                          VARCHAR(500),
    created_at                                          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                                          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_field_jobs_updated_at BEFORE UPDATE ON support.field_jobs
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_field_jobs_technician ON support.field_jobs(assigned_technician_id, status);

CREATE TABLE support.field_job_photos (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    field_job_id          UUID NOT NULL REFERENCES support.field_jobs(id) ON DELETE CASCADE,
    photo_type              VARCHAR(10) NOT NULL CHECK (photo_type IN ('before','after')),
    file_path                  VARCHAR(500) NOT NULL,
    uploaded_at                   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE support.field_job_parts_used (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    field_job_id          UUID NOT NULL REFERENCES support.field_jobs(id) ON DELETE CASCADE,
    stock_item_id            UUID REFERENCES inventory.stock_items(id),   -- serialized (e.g. ONU)
    product_id                  UUID REFERENCES inventory.products(id),   -- non-serialized (e.g. cable, connector)
    quantity                       INT NOT NULL DEFAULT 1
);

-- ---- RLS ----
DO $$
DECLARE t TEXT;
BEGIN
    FOR t IN SELECT unnest(ARRAY[
        'ticket_categories','ticket_templates','tickets','ticket_internal_notes',
        'ticket_replies','ticket_attachments','ticket_escalations',
        'field_jobs','field_job_photos','field_job_parts_used'
    ]) LOOP
        EXECUTE format('ALTER TABLE support.%I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('ALTER TABLE support.%I FORCE ROW LEVEL SECURITY', t);
        EXECUTE format('CREATE POLICY tenant_isolation ON support.%I USING (tenant_id = platform.current_tenant_id())', t);
    END LOOP;
END $$;

ALTER TABLE support.ticket_support_staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE support.ticket_support_staff FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON support.ticket_support_staff USING (
    EXISTS (SELECT 1 FROM support.tickets t WHERE t.id = ticket_support_staff.ticket_id AND t.tenant_id = platform.current_tenant_id())
);

-- FIX S1 (found by live schema audit): ticket_sequences carries tenant_id
-- but was omitted from the RLS loop above, leaving per-tenant ticket
-- numbering readable/writable across tenants. Added here.
ALTER TABLE support.ticket_sequences ENABLE ROW LEVEL SECURITY;
ALTER TABLE support.ticket_sequences FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON support.ticket_sequences
    USING (tenant_id = platform.current_tenant_id());
