-- ============================================================
-- 019_automation.sql — automation domain (Blueprint Section 21)
--
-- Generalizes the audit's single fully-verified automation (daily cron
-- auto-disconnect, ~10:00 AM, logged to "Auto Mikrotik Disable Log") into
-- a reusable TRIGGER -> CONDITION -> ACTION -> EXECUTION -> LOG engine.
--
-- Seeded default rules (in the seed data file) reproduce exactly what the
-- client system does today, including the two verified-but-currently-
-- INACTIVE SMS automations (Complaint SMS, Advance Paid SMS) — seeded
-- disabled per tenant, matching the audit's observed state, not silently
-- turned on.
-- ============================================================

CREATE TABLE automation.rules (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(150) NOT NULL,
    description           TEXT,
    trigger_type            VARCHAR(50) NOT NULL,
                             -- 'schedule.daily','event.payment_received','event.customer_created',
                             -- 'event.ticket_created','event.onu_los','event.stock_low', etc.
    trigger_config_json        JSONB NOT NULL DEFAULT '{}',  -- e.g. {"time": "10:00", "timezone": "Asia/Dhaka"}
    condition_json                JSONB NOT NULL DEFAULT '{}', -- e.g. {"invoice.status": "unpaid", "days_overdue_gte": 0}
    action_type                     VARCHAR(50) NOT NULL,
                                     -- 'mikrotik.disconnect','mikrotik.reconnect','sms.send','ticket.create',
                                     -- 'notification.send','webhook.call'
    action_config_json                 JSONB NOT NULL DEFAULT '{}',
    is_active                            BOOLEAN NOT NULL DEFAULT true,
    is_system_default                       BOOLEAN NOT NULL DEFAULT false, -- seeded rule, not user-authored
    created_by                                 UUID REFERENCES identity.users(id),
    created_at                                    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                                    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TRIGGER trg_automation_rules_updated_at BEFORE UPDATE ON automation.rules
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_automation_rules_tenant_active ON automation.rules(tenant_id) WHERE is_active;
CREATE INDEX idx_automation_rules_trigger_type ON automation.rules(trigger_type) WHERE is_active;

CREATE TABLE automation.executions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    rule_id               UUID NOT NULL REFERENCES automation.rules(id) ON DELETE CASCADE,
    trigger_context_json     JSONB,      -- e.g. which customer/invoice/ticket triggered this run
    status                      VARCHAR(20) NOT NULL DEFAULT 'success' CHECK (status IN ('success','failed','skipped')),
    result_json                    JSONB,   -- e.g. {"disconnected_count": 3} — mirrors verified log format
    error_message                     TEXT,
    triggered_at                         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_automation_executions_rule_time ON automation.executions(rule_id, triggered_at DESC);
CREATE INDEX idx_automation_executions_tenant_time ON automation.executions(tenant_id, triggered_at DESC);

-- ---- RLS ----
ALTER TABLE automation.rules ENABLE ROW LEVEL SECURITY;        ALTER TABLE automation.rules FORCE ROW LEVEL SECURITY;
ALTER TABLE automation.executions ENABLE ROW LEVEL SECURITY;    ALTER TABLE automation.executions FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON automation.rules USING (tenant_id = platform.current_tenant_id());
CREATE POLICY tenant_isolation ON automation.executions USING (tenant_id = platform.current_tenant_id());
