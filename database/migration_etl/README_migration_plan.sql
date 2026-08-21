-- ============================================================
-- MIGRATION ETL — Reference client -> ARQ ISP OS Tenant #1
-- (Blueprint Section 33). Idempotent, dry-run-first. The original client
-- database is READ-ONLY throughout; nothing in the source is modified or
-- destroyed. The reference client becomes ARQ ISP OS's first production
-- tenant, validated against the AS-IS audit's numbers as acceptance.
-- ============================================================

-- STEP 0: create the destination tenant + head-office branch + Owner user
--   SELECT ... TenantProvisioningService::provision(['name' => 'MO Network']);
-- Capture the resulting :tenant_id and :branch_id for every step below.

-- STEP 1: Zones (audit: 24 real zones)
--   INSERT INTO isp.zones (id, tenant_id, name, is_active)
--   SELECT gen_random_uuid(), :tenant_id, src.zone_name, true FROM legacy.zones src;
--   Keep a mapping table legacy_zone_id -> new_zone_id for later FK remap.

-- STEP 2: Packages (audit: 5 packages, MikroTik profile + monthly bill)
--   Map legacy package -> isp.packages, preserving mikrotik_profile_name
--   and monthly_bill exactly.

-- STEP 3: Employees (audit: 5 employees) -> hr.employees
-- STEP 4: Account Heads (audit: 9 heads incl. "Employee") -> accounting.account_heads
--   The "Employee" head MUST be created so the salary->expense trigger works.

-- STEP 5: Customers (audit: 349 customers)
--   For each legacy customer:
--     a. INSERT isp.customers preserving EVERY verified field (full_name,
--        mobile, other_mobile, email, gender, onu_mac, nid, address,
--        fiber_code, agent_type, connection_type, connection_date,
--        zone via mapping, billing_person, status, remarks,
--        sms_notification, previous_due, temp_disconnect_day).
--     b. INSERT one isp.customer_services row (service_type='internet')
--        carrying package, monthly_bill, disconnect_day, connection_fee.
--     c. INSERT network.pppoe_secrets from the legacy MikroTik secret
--        (username + encrypted secret password), linked to the router.

-- STEP 6: MikroTik router(s) (audit: 1 router @ 103.151.118.46:8728)
--   -> network.mikrotik_routers with credentials ENCRYPTED at insert time.

-- STEP 7: Historical payments & ledger
--   a. Legacy bill payments -> billing.invoices (backfilled per period) +
--      billing.payments. The invoice-recalc trigger will set statuses.
--   b. Legacy income/expense -> accounting.income_entries/expense_entries;
--      the GL-posting triggers backfill accounting.ledger_entries so the
--      Balance Sheet views reconcile to the audit's figures.

-- STEP 8: Inventory (audit: 3 categories, 1 product, 2 suppliers) -> inventory.*

-- STEP 9: Activity log history (audit: 665 entries) -> audit.activity_logs
--   Preserved as-is for continuity; new entries append going forward.

-- ============================================================
-- ACCEPTANCE VALIDATION (run after ETL; must match AS-IS audit)
-- ============================================================
--   SELECT count(*) FROM isp.customers WHERE tenant_id = :tenant_id;      -- expect 349
--   SELECT count(*) FROM isp.zones WHERE tenant_id = :tenant_id;          -- expect 24
--   SELECT count(*) FROM isp.packages WHERE tenant_id = :tenant_id;       -- expect 5
--   SELECT count(*) FROM accounting.account_heads WHERE tenant_id = :tenant_id; -- expect 9
--   SELECT count(*) FROM audit.activity_logs WHERE tenant_id = :tenant_id; -- expect ~665
-- Any mismatch fails the migration and triggers rollback of the
-- destination tenant (source is untouched, so re-running is safe).
