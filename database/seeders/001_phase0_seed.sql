-- ============================================================
-- 001_phase0_seed.sql
-- Seeds: canonical permission catalog, system role templates,
-- subscription plans (Starter/Professional/Business/Enterprise),
-- and the initial feature catalog including the BTRC-news
-- platform-default feature.
-- ============================================================

-- ------------------------------------------------------------
-- 1. PERMISSIONS — generalizes the audit's verified ~14 menu-group
--    matrix (Admin User, Package/Profile, Zone, SubZone, Destination,
--    Customer, Mikrotik, Bill Collection, Income, Discount, Expense,
--    Employee, Balance Sheet, Statement, Complain, Diagram, Inventory)
--    plus new SaaS-era modules, using Module.Resource.Action.
-- ------------------------------------------------------------
INSERT INTO identity.permissions (module, resource, action, description) VALUES
  -- Admin / identity
  ('identity','user','view','View admin users'),
  ('identity','user','create','Create admin users'),
  ('identity','user','edit','Edit admin users'),
  ('identity','user','delete','Delete admin users'),
  ('identity','role','manage','Manage roles & permissions'),
  -- ISP configuration
  ('isp','package','view','View packages'),
  ('isp','package','create','Create packages'),
  ('isp','package','edit','Edit packages'),
  ('isp','zone','view','View zones/areas'),
  ('isp','zone','create','Create zones/areas'),
  ('isp','zone','edit','Edit zones/areas'),
  ('isp','subzone','manage','Manage sub-zones'),
  ('isp','destination','manage','Manage destinations'),
  -- Customers
  ('isp','customer','view','View customers'),
  ('isp','customer','create','Create customers'),
  ('isp','customer','edit','Edit customers'),
  ('isp','customer','delete','Delete customers'),
  ('isp','customer','import','Bulk import customers (CSV)'),
  ('isp','customer','export','Export customer data'),
  -- Billing
  ('billing','invoice','view','View bills/invoices'),
  ('billing','invoice','create','Generate bills'),
  ('billing','payment','pay','Collect payment'),
  ('billing','payment','refund','Process refund'),
  ('billing','discount','manage','Manage discounts'),
  -- Network
  ('network','mikrotik','manage','Manage MikroTik routers'),
  ('network','mikrotik','disconnect','Disconnect PPPoE secret'),
  ('network','mikrotik','reconnect','Reconnect PPPoE secret'),
  ('network','olt','manage','Manage OLT devices'),
  ('network','radius','manage','Manage RADIUS/NAS'),
  ('network','diagram','view','View network diagram'),
  -- Income / Expense
  ('accounting','income','manage','Manage income entries'),
  ('accounting','expense','manage','Manage expense entries'),
  ('accounting','expense','approve','Approve expenses'),
  ('accounting','statement','view','View accounts statement / GL'),
  ('accounting','balance_sheet','view','View balance sheet reports'),
  -- HR
  ('hr','employee','view','View employees'),
  ('hr','employee','manage','Manage employees'),
  ('hr','salary','pay','Pay employee salary'),
  -- Complaint / support
  ('support','ticket','view','View complaints/tickets'),
  ('support','ticket','create','Create complaint/ticket'),
  ('support','ticket','assign','Assign ticket to staff'),
  ('support','ticket','manage','Manage ticket lifecycle'),
  -- Inventory
  ('inventory','stock','manage','Manage stock/products'),
  ('inventory','purchase','manage','Manage purchases'),
  ('inventory','sale','manage','Manage sales'),
  -- Communication
  ('communication','sms','send','Send SMS'),
  ('communication','sms','manage','Manage SMS templates'),
  -- Reseller
  ('reseller','account','manage','Manage reseller/franchise accounts'),
  -- Compliance
  ('compliance','btrc_report','export','Export BTRC report'),
  ('compliance','news','view','View regulatory news feed')
ON CONFLICT (module, resource, action) DO NOTHING;

-- ------------------------------------------------------------
-- 2. SYSTEM ROLE TEMPLATES (tenant_id NULL = clonable template,
--    instantiated per-tenant on tenant provisioning)
-- ------------------------------------------------------------
INSERT INTO identity.roles (tenant_id, name, code, is_system) VALUES
  (NULL, 'Owner', 'owner', true),
  (NULL, 'Admin', 'admin', true),
  (NULL, 'Manager', 'manager', true),
  (NULL, 'Accountant', 'accountant', true),
  (NULL, 'Billing Operator', 'billing_operator', true),
  (NULL, 'NOC Operator', 'noc_operator', true),
  (NULL, 'Technician', 'technician', true),
  (NULL, 'HR Manager', 'hr_manager', true),
  (NULL, 'Inventory Manager', 'inventory_manager', true),
  (NULL, 'Reseller', 'reseller', true),
  (NULL, 'Franchise Manager', 'franchise_manager', true)
ON CONFLICT (tenant_id, code) DO NOTHING;

-- Owner + Admin templates get every permission at ALL scope.
INSERT INTO identity.role_permissions (role_id, permission_id, data_scope)
SELECT r.id, p.id, 'ALL'
FROM identity.roles r
CROSS JOIN identity.permissions p
WHERE r.code IN ('owner','admin') AND r.tenant_id IS NULL
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Accountant: accounting.* + billing.* view/pay, ALL scope
INSERT INTO identity.role_permissions (role_id, permission_id, data_scope)
SELECT r.id, p.id, 'ALL'
FROM identity.roles r
JOIN identity.permissions p ON p.module IN ('accounting') OR p.key IN ('billing.invoice.view','billing.payment.pay','billing.payment.refund')
WHERE r.code = 'accountant' AND r.tenant_id IS NULL
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- NOC Operator: network.* ALL scope
INSERT INTO identity.role_permissions (role_id, permission_id, data_scope)
SELECT r.id, p.id, 'ALL'
FROM identity.roles r
JOIN identity.permissions p ON p.module = 'network'
WHERE r.code = 'noc_operator' AND r.tenant_id IS NULL
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Technician: support.ticket.* at ASSIGNED scope only
INSERT INTO identity.role_permissions (role_id, permission_id, data_scope)
SELECT r.id, p.id, 'ASSIGNED'
FROM identity.roles r
JOIN identity.permissions p ON p.module = 'support'
WHERE r.code = 'technician' AND r.tenant_id IS NULL
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Reseller: isp.customer.view/edit at OWN scope only
INSERT INTO identity.role_permissions (role_id, permission_id, data_scope)
SELECT r.id, p.id, 'OWN'
FROM identity.roles r
JOIN identity.permissions p ON p.key IN ('isp.customer.view','isp.customer.edit','billing.invoice.view')
WHERE r.code = 'reseller' AND r.tenant_id IS NULL
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- ------------------------------------------------------------
-- 3. FEATURE CATALOG (subset shown — extended per-domain as each
--    Phase's tables land). BTRC news is marked platform-default:
--    always on, on every plan, per explicit product decision.
-- ------------------------------------------------------------
INSERT INTO subscription.features (key, module, name, is_platform_default) VALUES
  ('isp.customer.manage', 'isp', 'Customer Management', false),
  ('billing.core', 'billing', 'Core Billing & Payment Collection', false),
  ('network.mikrotik.manage', 'network', 'MikroTik Integration', false),
  ('network.radius.manage', 'network', 'RADIUS AAA', false),
  ('network.olt.manage', 'network', 'OLT/GPON Management', false),
  ('network.monitoring', 'network', 'Network Monitoring', false),
  ('accounting.core', 'accounting', 'Income/Expense/Statement', false),
  ('accounting.advanced_gl', 'accounting', 'General Ledger / Chart of Accounts', false),
  ('hr.payroll', 'hr', 'HR & Payroll', false),
  ('inventory.core', 'inventory', 'Inventory & Warehouse', false),
  ('support.ticketing', 'support', 'Complaint / Ticketing', false),
  ('support.field_service', 'support', 'Field Service / Technician App', false),
  ('crm.core', 'crm', 'CRM & Lead Management', false),
  ('reseller.management', 'reseller', 'Reseller / Franchise Management', false),
  ('automation.engine', 'automation', 'Automation Engine', false),
  ('ai.churn_prediction', 'ai', 'AI Churn Prediction', false),
  ('ai.nl_analytics', 'ai', 'AI Natural-Language Analytics', false),
  ('compliance.reports.btrc', 'compliance', 'BTRC Compliance Report Export', false),
  ('compliance.alerts', 'compliance', 'BTRC Regulatory Alerts', false),
  ('compliance.advanced_tools', 'compliance', 'Advanced Compliance Tools', false),
  ('compliance.news.view', 'compliance', 'BTRC Regulatory News Feed', true),  -- always free
  ('api.access', 'integrations', 'API & Webhook Access', false)
ON CONFLICT (key) DO NOTHING;

-- ------------------------------------------------------------
-- 4. PLANS
-- ------------------------------------------------------------
INSERT INTO subscription.plans (code, name, price_amount, billing_cycle, trial_days, sort_order) VALUES
  ('starter', 'Starter', 1500, 'monthly', 14, 1),
  ('professional', 'Professional', 4000, 'monthly', 14, 2),
  ('business', 'Business', 9000, 'monthly', 14, 3),
  ('enterprise', 'Enterprise', 20000, 'monthly', 30, 4)
ON CONFLICT (code) DO NOTHING;

-- Starter: Customer + core billing only
INSERT INTO subscription.plan_features (plan_id, feature_id, is_enabled)
SELECT p.id, f.id, true FROM subscription.plans p, subscription.features f
WHERE p.code = 'starter' AND f.key IN ('isp.customer.manage','billing.core')
ON CONFLICT (plan_id, feature_id) DO NOTHING;

-- Professional: + MikroTik, SMS(comm), Accounting core, Ticketing
INSERT INTO subscription.plan_features (plan_id, feature_id, is_enabled)
SELECT p.id, f.id, true FROM subscription.plans p, subscription.features f
WHERE p.code = 'professional' AND f.key IN
  ('isp.customer.manage','billing.core','network.mikrotik.manage','accounting.core','support.ticketing','crm.core')
ON CONFLICT (plan_id, feature_id) DO NOTHING;

-- Business: + OLT, Inventory, HR, Automation, Reseller
INSERT INTO subscription.plan_features (plan_id, feature_id, is_enabled)
SELECT p.id, f.id, true FROM subscription.plans p, subscription.features f
WHERE p.code = 'business' AND f.key IN
  ('isp.customer.manage','billing.core','network.mikrotik.manage','network.olt.manage',
   'accounting.core','accounting.advanced_gl','support.ticketing','support.field_service',
   'crm.core','inventory.core','hr.payroll','automation.engine','reseller.management',
   'compliance.reports.btrc')
ON CONFLICT (plan_id, feature_id) DO NOTHING;

-- Enterprise: everything
INSERT INTO subscription.plan_features (plan_id, feature_id, is_enabled)
SELECT p.id, f.id, true FROM subscription.plans p, subscription.features f
WHERE p.code = 'enterprise'
ON CONFLICT (plan_id, feature_id) DO NOTHING;
