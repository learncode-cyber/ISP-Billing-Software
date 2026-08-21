-- ============================================================
-- 017_crm.sql — crm domain (Blueprint Section 16)
-- New pre-sale layer the audit explicitly confirmed doesn't exist:
-- "There is no visible Lead/pre-sale stage before Create Customer —
-- the software starts the lifecycle at paid-connection creation."
-- [VERIFIED absence]. Lead conversion creates the customer record via
-- the exact same Phase-1 Customer creation path (MikroTik secret
-- auto-creation preserved), so nothing about verified behavior changes
-- once a lead becomes a customer.
-- ============================================================

CREATE TABLE crm.lead_sources (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(100) NOT NULL,     -- 'Facebook Ad','Referral','Walk-in','Website'
    UNIQUE (tenant_id, name)
);

CREATE TABLE crm.leads (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    branch_id            UUID REFERENCES tenancy.branches(id),
    source_id              UUID REFERENCES crm.lead_sources(id),
    full_name                VARCHAR(255) NOT NULL,
    mobile                     VARCHAR(30) NOT NULL,
    email                        CITEXT,
    address                        TEXT,
    interested_package_id           UUID REFERENCES isp.packages(id),
    assigned_to_user_id                UUID REFERENCES identity.users(id),
    status                               VARCHAR(20) NOT NULL DEFAULT 'new'
                                          CHECK (status IN ('new','contacted','qualified','converted','lost')),
    lost_reason                            TEXT,
    converted_customer_id                    UUID REFERENCES isp.customers(id),
    created_at                                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                                 TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_leads_updated_at BEFORE UPDATE ON crm.leads
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_leads_tenant_status ON crm.leads(tenant_id, status);
CREATE INDEX idx_leads_assigned ON crm.leads(tenant_id, assigned_to_user_id);

CREATE TABLE crm.lead_follow_ups (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    lead_id               UUID NOT NULL REFERENCES crm.leads(id) ON DELETE CASCADE,
    note                    TEXT NOT NULL,
    scheduled_at               TIMESTAMPTZ,
    completed_at                  TIMESTAMPTZ,
    created_by                       UUID REFERENCES identity.users(id),
    created_at                         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_lead_follow_ups_lead ON crm.lead_follow_ups(lead_id, scheduled_at);

-- Tags/Groups usable on both leads and existing customers
CREATE TABLE crm.tags (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(100) NOT NULL,
    UNIQUE (tenant_id, name)
);

CREATE TABLE crm.customer_tags (
    customer_id         UUID NOT NULL REFERENCES isp.customers(id) ON DELETE CASCADE,
    tag_id               UUID NOT NULL REFERENCES crm.tags(id) ON DELETE CASCADE,
    PRIMARY KEY (customer_id, tag_id)
);

-- Communication history — unified across SMS/WhatsApp/Email/Call log,
-- referenced by communication.notifications (Phase 4 SMS section) once sent.
CREATE TABLE crm.communication_history (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    customer_id           UUID REFERENCES isp.customers(id) ON DELETE CASCADE,
    lead_id                 UUID REFERENCES crm.leads(id) ON DELETE CASCADE,
    channel                   VARCHAR(20) NOT NULL CHECK (channel IN ('sms','whatsapp','email','call','note')),
    direction                   VARCHAR(10) NOT NULL DEFAULT 'outbound' CHECK (direction IN ('outbound','inbound')),
    summary                       TEXT NOT NULL,
    created_by                      UUID REFERENCES identity.users(id),
    created_at                        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (customer_id IS NOT NULL OR lead_id IS NOT NULL)
);
CREATE INDEX idx_comm_history_customer ON crm.communication_history(customer_id, created_at DESC);
CREATE INDEX idx_comm_history_lead ON crm.communication_history(lead_id, created_at DESC);

-- ---- RLS ----
DO $$
DECLARE t TEXT;
BEGIN
    FOR t IN SELECT unnest(ARRAY['lead_sources','leads','lead_follow_ups','tags','communication_history']) LOOP
        EXECUTE format('ALTER TABLE crm.%I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('ALTER TABLE crm.%I FORCE ROW LEVEL SECURITY', t);
        EXECUTE format('CREATE POLICY tenant_isolation ON crm.%I USING (tenant_id = platform.current_tenant_id())', t);
    END LOOP;
END $$;

ALTER TABLE crm.customer_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.customer_tags FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON crm.customer_tags USING (
    EXISTS (SELECT 1 FROM isp.customers c WHERE c.id = customer_tags.customer_id AND c.tenant_id = platform.current_tenant_id())
);
