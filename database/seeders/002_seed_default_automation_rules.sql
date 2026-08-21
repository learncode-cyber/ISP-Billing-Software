-- ============================================================
-- 002_seed_default_automation_rules.sql
--
-- Not a per-database seed (automation rules are tenant-owned, so there's
-- nothing global to insert here). Instead, this defines the reusable
-- provisioning function called once per NEW tenant — from
-- TenantProvisioningService::provision() in the backend — so every
-- tenant starts with the audit's verified automation behavior
-- reproduced exactly, including the two SMS rules seeded DISABLED to
-- match the audit's observed "Complaint SMS / Advance Paid SMS: Inactive"
-- state rather than silently turning them on for new tenants.
-- ============================================================

CREATE OR REPLACE FUNCTION automation.seed_default_rules_for_tenant(p_tenant_id UUID)
RETURNS void AS $$
BEGIN
    -- 1. Auto MikroTik Disconnect — [VERIFIED]: daily ~10:00 AM, past
    --    disconnect_day + unpaid invoice -> disable secret, logged.
    INSERT INTO automation.rules (tenant_id, name, description, trigger_type, trigger_config_json,
        condition_json, action_type, action_config_json, is_active, is_system_default)
    VALUES (p_tenant_id, 'Auto Disconnect Overdue Customers',
        'Daily check: disconnect MikroTik secret for customers past their disconnect day with an unpaid bill.',
        'schedule.daily', '{"time": "10:00", "timezone": "Asia/Dhaka"}',
        '{"invoice.status": "unpaid", "past_disconnect_day": true}',
        'mikrotik.disconnect', '{}', true, true);

    -- 2. Due SMS — [VERIFIED present, active by default per audit's General/Due SMS pages]
    INSERT INTO automation.rules (tenant_id, name, description, trigger_type, trigger_config_json,
        condition_json, action_type, action_config_json, is_active, is_system_default)
    VALUES (p_tenant_id, 'Due Bill SMS Reminder',
        'Send due-bill SMS reminder using the customer''s configured merge-tag template.',
        'schedule.daily', '{"time": "09:00", "timezone": "Asia/Dhaka"}',
        '{"invoice.status": "unpaid", "exclude_partially_paid": true}',
        'sms.send', '{"template": "due_sms"}', true, true);

    -- 3. New Customer SMS — [VERIFIED template exists]
    INSERT INTO automation.rules (tenant_id, name, description, trigger_type,
        condition_json, action_type, action_config_json, is_active, is_system_default)
    VALUES (p_tenant_id, 'New Customer Welcome SMS', 'Send welcome SMS on customer creation.',
        'event.customer_created', '{}', 'sms.send', '{"template": "new_customer_sms"}', true, true);

    -- 4. Paid SMS — [VERIFIED template exists]
    INSERT INTO automation.rules (tenant_id, name, description, trigger_type,
        condition_json, action_type, action_config_json, is_active, is_system_default)
    VALUES (p_tenant_id, 'Payment Received SMS', 'Send confirmation SMS when a payment is received.',
        'event.payment_received', '{}', 'sms.send', '{"template": "paid_sms"}', true, true);

    -- 5. Complaint SMS — [VERIFIED template exists BUT audit found Status: Inactive]
    --    Seeded matching that exact observed state — not silently enabled.
    INSERT INTO automation.rules (tenant_id, name, description, trigger_type,
        condition_json, action_type, action_config_json, is_active, is_system_default)
    VALUES (p_tenant_id, 'Complaint SMS Notification', 'Notify customer + assigned employee on complaint creation.',
        'event.ticket_created', '{}', 'sms.send', '{"template": "complaint_sms"}', false, true);

    -- 6. Advance Paid SMS — [VERIFIED template exists BUT audit found Status: Inactive]
    INSERT INTO automation.rules (tenant_id, name, description, trigger_type,
        condition_json, action_type, action_config_json, is_active, is_system_default)
    VALUES (p_tenant_id, 'Advance Payment SMS', 'Notify customer when an advance payment is recorded.',
        'event.advance_payment_received', '{}', 'sms.send', '{"template": "advance_paid_sms"}', false, true);

    -- ---- New rules (Blueprint Section 21 examples, disabled by default —
    -- tenant opts in explicitly, since these change customer-facing
    -- network behavior beyond what the client system did) ----
    INSERT INTO automation.rules (tenant_id, name, description, trigger_type,
        condition_json, action_type, action_config_json, is_active, is_system_default)
    VALUES
        (p_tenant_id, 'Payment Received -> Reconnect',
         'Auto re-enable MikroTik secret when a disconnected customer''s due invoice is fully paid.',
         'event.payment_received', '{"invoice.status": "paid", "secret.status": "disabled"}',
         'mikrotik.reconnect', '{}', false, true),
        (p_tenant_id, 'ONU LOS -> Auto Ticket',
         'Create a support ticket automatically when an ONU reports Loss of Signal.',
         'event.onu_los', '{}', 'ticket.create', '{"category": "network_outage", "priority": "high"}', false, true),
        (p_tenant_id, 'Router Unreachable -> NOC Alert',
         'Notify NOC Operators when a MikroTik router or OLT stops responding to monitoring checks.',
         'event.target_down', '{}', 'notification.send', '{"role": "noc_operator"}', false, true),
        (p_tenant_id, 'Low Stock Alert',
         'Notify Inventory Manager when a product''s stock falls below its low-stock threshold.',
         'event.stock_low', '{}', 'notification.send', '{"role": "inventory_manager"}', false, true);
END;
$$ LANGUAGE plpgsql;

-- Called from TenantProvisioningService::provision() immediately after a
-- new tenant + head-office branch + Owner user are created, e.g.:
--   SELECT automation.seed_default_rules_for_tenant('<new-tenant-uuid>');
