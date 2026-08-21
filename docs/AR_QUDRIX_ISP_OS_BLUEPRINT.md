# AR QUDRIX ISP OS — FINAL TECHNICAL BLUEPRINT v1.0

**Status:** Architecture baseline for engineering execution
**Source of truth for existing functionality:** AS-IS Audit — "ISP Network" ISP Management Admin Dashboard (349 customers, 24 zones, 5 packages, live MikroTik integration)
**Classification legend used throughout:** `[VERIFIED]` = observed live in client system · `[INFERRED]` = logically implied, not directly tested · `[NOT VERIFIED]` = insufficient evidence · `[NEW]` = not in client system, added for SaaS/competitive parity

---

## 0. COMPETITOR / MARKET GAP ANALYSIS

Benchmarked against category-leading ISP/WISP billing-OSS/BSS platforms (Splynx, UISP, Sonar, Powercode-class systems, RADIUS-based ISP suites common in South Asia).

### 0.1 What the client software already does well (keep, don't regress)
- Deep MikroTik live integration (online/offline/static/unmatched secrets, live sessions) `[VERIFIED]`
- BTRC regulatory export — this is a genuine Bangladesh-market differentiator most global competitors don't have `[VERIFIED]`
- Granular per-menu × per-action permission matrix (already better than typical 2-role systems) `[VERIFIED]`
- Cron-based auto-disconnect with audit trail `[VERIFIED]`
- CSV bulk customer import `[VERIFIED]`

### 0.2 Confirmed market-standard capabilities the client system is missing (gap → becomes `[NEW]` in ARQ ISP OS)

| Gap Area | Why competitors have it | ARQ ISP OS Response |
|---|---|---|
| **Built-in RADIUS server (AAA)** | Industry leaders run their own RADIUS (PPPoE/DHCP/IPoE/Hotspot), not just MikroTik API polling — enables multi-vendor NAS, not just MikroTik | New `network.radius` domain — FreeRADIUS-compatible schema, vendor-agnostic NAS table |
| **Customer self-service portal with online payment** | Standard across all competitors — reduces support load, speeds collection | Customer Portal + Payment Gateway module (Section 25) |
| **Multi-protocol support (DHCP/IPoE/Hotspot, not only PPPoE)** | WISP/FTTH operators mix protocols | RADIUS + NAS abstraction supports all AAA types |
| **Native payment gateway integrations (bKash, Nagad, SSLCommerz, Stripe)** | Competitors integrate multiple gateways; client only had an external SSO billing portal | Section 14 — pluggable Payment Gateway Adapter pattern |
| **Real network monitoring (ping/latency/uptime/alerting)** | Client has zero live monitoring beyond MikroTik session state | Section 13 — Network Monitoring subsystem with SNMP/ICMP pollers |
| **Formal inventory-to-customer linkage (serialized ONU/router assignment)** | Competitors track hardware lifecycle to the subscriber | Inventory ↔ Customer Service FK (Section 17) |
| **API-first / webhook ecosystem** | Competitors expose full REST APIs for integration | Section 12 — API-first from day one |
| **Multi-tenant / reseller hierarchy** | Client is single-tenant; competitors serving MSPs support reseller/franchise layers | Core differentiator already scoped by AR Qudrix |
| **Proper double-entry accounting (GL, Chart of Accounts)** | Client has a flat income/expense ledger, not real accounting | Section 15 |
| **Field service / technician mobile workflow** | Competitors offer GPS check-in, job photos, signature capture | Section 19 |
| **AI-assisted operations (churn prediction, anomaly detection)** | Emerging differentiator among modern platforms | Section 22 |

### 0.3 Verdict
The client's core billing/network operational depth is solid and must be preserved feature-for-feature. The gap is entirely in **platform architecture** (multi-tenant, RADIUS-native, API-first, real accounting, real network monitoring, self-service, payments) — exactly the direction already set in the Master Specification. No existing verified feature is discarded anywhere below.

---

## 1. FINAL A-Z MODULE TREE

```
AR QUDRIX ISP OS
│
├── 00. Platform / Super Admin Console
├── 01. SaaS Subscription & Billing (platform-level, AR Qudrix → Tenant)
├── 02. Multi-Tenancy & Organization
├── 03. Branch Management
├── 04. Identity, Auth & RBAC
├── 05. Dashboard & Command Center
├── 06. CRM & Lead Management
├── 07. Customer Management
├── 08. ISP Configuration (Package/Zone/Area/SubZone/Destination)
├── 09. Billing & Invoicing
├── 10. Payment & Payment Gateway
├── 11. MikroTik Integration
├── 12. RADIUS (AAA)
├── 13. IP Address Management (IPAM)
├── 14. OLT Management
├── 15. GPON / PON
├── 16. ONU / ONT
├── 17. Network Monitoring
├── 18. Network Diagram / Topology
├── 19. FTTH / WISP / Cable TV / IP Phone / CCTV / Corporate Network (service-type extensions)
├── 20. Reseller / Dealer / Franchise / Commission
├── 21. Accounting & Finance
├── 22. HR & Payroll
├── 23. Inventory & Warehouse
├── 24. Purchase / Sales / Returns
├── 25. Complaint / Ticketing
├── 26. Field Service / Technician
├── 27. SMS / Email / WhatsApp / Push (Communication)
├── 28. Automation Engine
├── 29. AI Layer
├── 30. Business Intelligence / Analytics
├── 31. BTRC Compliance
├── 32. BTRC Regulatory News (platform-level)
├── 33. Reports Center
├── 34. Audit & Activity Logs
├── 35. API Platform & Webhooks
├── 36. PWA / Mobile (Admin, Customer, Technician)
├── 37. Customer Self-Service Portal
├── 38. Security & Compliance
└── 39. Backup / Disaster Recovery
```

---

## 2 & 3. COMPLETE FEATURE TREE — MODULE → SUBMODULE → FEATURE MAPPING

> Legend: `[V]` verified-preserve · `[N]` new for SaaS

**06. CRM & Lead Management**
Lead Capture `[N]` → Lead Source `[N]` → Follow-up Scheduler `[N]` → Lead-to-Customer Conversion `[N]` → Customer Tags/Groups `[N]` → Communication History `[N]` → Campaigns `[N]`

**07. Customer Management**
Customer List/View `[V]` → Create Customer (full field set, Section 5 of audit) `[V]` → Edit Customer (+Previous Due, Temp Disconnect Day, SubZone, Destination) `[V]` → Delete Log `[V]` → CSV Bulk Import `[V]` → Bulk Update `[N]` → Customer Ledger `[V]` → Billing History `[V]` → Customer Documents (NID photo) `[V]` → Customer Portal Access `[N]` → Customer Hardware Assignment `[N]`

**08. ISP Configuration**
Package/Bandwidth Profile `[V]` → Zone/Area `[V]` → SubZone `[V]` → Destination `[V]` → Service Type (Home/Corporate → extended to FTTH/WISP/CableTV/IPPhone/CCTV) `[V+N]` → Connection Type `[V]` → Billing Cycle `[N]` → Disconnect Rules (Disconnect Day) `[V]` → Grace Period `[N]` → Tax/VAT Config `[N]` → Discount Rules `[V]`

**09–10. Billing & Payment**
Bill Collection (All Due/Full Paid/Previous Due/Not Generated) `[V]` → Payment Modal (Due/Pay/Discount/Description) `[V]` → Recurring Billing Engine `[N]` → Proration `[N]` → Partial/Advance Payment `[V+N]` → Invoice (PDF, auto-numbered) `[N]` → Refund/Credit Note/Debit Note `[N]` → Payment Allocation `[N]` → Payment Gateway (bKash/Nagad/SSLCommerz/Stripe adapters) `[N]` → Payment Reconciliation `[N]` → Auto Due Reminder `[N]` → Auto Suspend/Reconnect (extends existing cron) `[V+N]`

**11–18. Network Stack**
MikroTik: Router Mgmt `[V]`, Secret List `[V]`, Online/Offline/Static/Unmatched `[V]`, Bulk Disconnect/Reconnect `[V]`, Live Session `[V]`, Router Health `[N]`, Router Alerts `[N]`
RADIUS `[N]`: NAS Registry, AAA (Auth/Authz/Accounting), CoA (Change of Authorization), multi-protocol (PPPoE/DHCP/IPoE/Hotspot)
IPAM `[N]`: IP Pool, Static IP Assignment, Subnet Management, IPv4/IPv6
OLT `[V]`: Device Registration (BDCOM/V-SOL/ZTE/Huawei/Fiberhome), SNMP+Telnet — extended with `[N]` ONU Discovery, Signal/RX-TX Power, LOS Alarm, VLAN, PON Port Mapping
Network Monitoring `[N]`: Ping/Latency/Packet-loss pollers, Uptime/Downtime, Threshold Alerts, Incident Management
Network Diagram `[V→N]`: existing "Root only" stub rebuilt into real interactive Router→OLT→PON→ONU→Customer topology

**20. Reseller/Dealer/Franchise** `[N]` — full chain: Tenant → Franchise → Reseller → Sub-Reseller → Customer; Commission Rules; Reseller Wallet; Credit Limit; Settlement; Customer Ownership scoping.

**21. Accounting** — Income `[V]`, Expense `[V]`, Account Head/Sub-head `[V]`, Statement/GL `[V→N upgraded]`, Balance Sheet `[V]`, Monthly/Yearly Reports `[V]` — extended with `[N]` Chart of Accounts, Journal, AR/AP, Cash/Bank/Wallet, P&L, Cash Flow, Expense Approval Workflow.

**22. HR & Payroll** — Employee `[V]`, Pay Salary/Conveyance/Punishment `[V]` — extended `[N]` Departments, Designations, Attendance, Leave, Payroll runs, Allowances/Deductions.

**23–24. Inventory** — Stock/Product/Category/Supplier/Purchase/Sale/Returns `[V]` — extended `[N]` Multi-Warehouse, Serial/IMEI tracking, Stock Transfer/Adjustment, Purchase Order, Low Stock Alert, ONU/Router-to-Customer assignment FK.

**25–26. Complaint / Field Service** — Add/View Complaint, Templates, Priority, Assignment, SMS toggle `[V]` — extended `[N]` Ticket Number, SLA, Category/Subcategory, Escalation, Attachments, Customer Reply, Resolution Time, CSAT rating, Technician GPS check-in/out, Photo/Signature capture, Spare Parts used.

**27. Communication** — General/Due/Paid/Advance-Paid/New-Customer/Complaint SMS with merge tags `[V]` — extended `[N]` WhatsApp, Email, Push, Scheduled/Bulk SMS, unified Notification Center, delivery-status tracking.

**28. Automation Engine** `[N]` — generalizes the one verified automation (cron auto-disconnect) into a reusable Trigger→Condition→Action→Execution→Log engine (Section 21 detail).

**29. AI Layer** `[N]` — churn prediction, revenue forecasting, ticket auto-classification, NL analytics query, network anomaly detection — all permission/entitlement gated.

**31–32. BTRC** — BTRC Report export (exact verified column set) `[V]`, extended `[N]` into configurable Compliance Report Builder + platform-level Regulatory News Feed (two-tier entitlement per your instruction: news = free for all tenants; alerts/reports/advanced tools = subscription-gated).

---

## 4. MULTI-TENANT ARCHITECTURE

**Model:** Shared database, shared schema, **row-level tenant isolation** (not schema-per-tenant) — chosen for SaaS operability at scale (thousands of tenants) without the migration/ops overhead of schema-per-tenant.

- Every tenant-owned table carries `tenant_id UUID NOT NULL REFERENCES tenancy.tenants(id)`.
- **PostgreSQL Row-Level Security (RLS)** enabled on every tenant-owned table: policy `USING (tenant_id = current_setting('app.current_tenant_id')::uuid)`. The application sets this session variable per request, immediately after authentication, before any query runs.
- Backend service layer (Laravel) enforces tenant scope via a global model scope/middleware in addition to RLS — **defense in depth**, never relying on frontend filtering, per project rule.
- Platform-level tables (plans, features, BTRC news, system settings) have **no** `tenant_id` — visible to all tenants read-only, writable only by Super Admin.
- Cross-tenant queries (Super Admin analytics) run under a privileged DB role that bypasses RLS (`BYPASSRLS`), used only by the platform-admin service account, never by tenant-facing code paths.
- Tenant-aware cache keys: `tenant:{tenant_id}:*` prefix on all Redis keys to prevent cross-tenant cache leakage.
- File storage: `storage/tenants/{tenant_id}/...` path convention on the abstraction layer (S3-compatible), even before a CDN/bucket-per-tenant decision is made.

---

## 5. SUBSCRIPTION & ENTITLEMENT ARCHITECTURE

```
Plan ──< PlanFeature >── Feature
  │
  └──< TenantSubscription >── Tenant
                │
                └──< TenantFeatureOverride >── Feature
```

- `subscription.plans` (id, code, name, price, billing_cycle, trial_days, is_active)
- `subscription.features` (id, key e.g. `mikrotik.manage`, `olt.manage`, `ai.churn_prediction`, module, description)
- `subscription.plan_features` (plan_id, feature_id, is_enabled, limit_value nullable e.g. max_customers)
- `subscription.tenant_subscriptions` (tenant_id, plan_id, status: trial/active/past_due/suspended/cancelled, current_period_start/end, grace_period_ends_at)
- `subscription.tenant_feature_overrides` (tenant_id, feature_id, is_enabled, limit_value, reason, expires_at) — lets AR Qudrix grant/revoke a specific feature per tenant regardless of plan.

**Effective access resolution (server-side, cached per request):**
```
effective_access = (
    (override exists ? override.is_enabled : plan_feature.is_enabled)
    AND
    user_permission.is_allowed
)
```
Both must be true. Example enforced exactly as specified: Plan says OLT = NO → even Admin role with OLT permission = **denied**. Middleware `CheckEntitlement::class` runs before `CheckPermission::class` on every protected route; frontend nav renders from the same resolved capability object returned by `/api/v1/me/capabilities` (single source of truth — no hard-coded plan logic scattered across components, per project rule).

**BTRC News exception (per your direction):** `compliance.news.view` is a feature key that is **force-enabled at the plan level for every plan including the free tier** — implemented as a system default rather than a per-tenant override, so it can never accidentally be excluded when new plans are created. `compliance.alerts`, `compliance.reports.btrc`, `compliance.advanced_tools` remain normal gated feature keys.

Super Admin capabilities: create/edit plans, toggle features, set limits, assign/upgrade/downgrade/suspend/renew/cancel subscriptions, add custom overrides — all via `platform` domain admin console, no direct DB access needed.

---

## 6. RBAC / PERMISSION MATRIX

**Model:** `Role → Permission (Module.Resource.Action) → Data Scope`, evaluated per tenant (roles are tenant-scoped except platform Super Admin).

Actions: `view, create, edit, delete, approve, export, import, pay, refund, disconnect, reconnect, send, assign, manage`
Data Scopes: `ALL | BRANCH | OWN | ASSIGNED`

System roles seeded per tenant on creation (all customizable/clone-able):

| Role | Typical Scope |
|---|---|
| Owner | ALL |
| Admin | ALL (within tenant) |
| Manager | BRANCH |
| Accountant | ALL (finance modules only) |
| Billing Operator | BRANCH/ASSIGNED |
| NOC Operator | ALL (network modules only) |
| Technician | ASSIGNED (own tickets/jobs) |
| HR Manager | ALL (HR module only) |
| Inventory Manager | BRANCH (inventory only) |
| Reseller | OWN (own customers only) |
| Franchise Manager | BRANCH-equivalent (franchise subtree) |
| Custom Role | tenant-defined combination |

Storage: `identity.roles`, `identity.permissions` (module, resource, action — canonical list, ~14 legacy menu groups from audit expanded to ~35 modules), `identity.role_permissions` (role_id, permission_id, data_scope), `identity.user_roles` (user_id, role_id, branch_id nullable). The original client's per-menu × per-action matrix `[VERIFIED]` maps 1:1 into this generalized model — no capability lost, only extended with data-scope and new modules.

---

## 7–11. DATABASE ARCHITECTURE, ERD, TABLE DICTIONARY, PK/FK, INDEXES

### 7.1 Domains (PostgreSQL schemas)
`platform · tenancy · subscription · identity · crm · isp · billing · network · support · accounting · hr · inventory · reseller · communication · automation · analytics · compliance · audit · integrations · ai`

### 7.2 Identifier strategy
All primary keys: `UUID DEFAULT gen_random_uuid()`. Human-facing sequential numbers (invoice no, ticket no) generated via a per-tenant sequence table, stored as a separate indexed column — never used as PK.

### 7.3 Core ERD (textual — top-level entities and cardinality)

```
tenancy.tenants (1) ──< tenancy.branches (M)
tenancy.tenants (1) ──< identity.users (M)
tenancy.tenants (1) ──< subscription.tenant_subscriptions (1)
tenancy.branches (1) ──< isp.customers (M)
isp.customers (1) ──< isp.customer_services (M)          -- a customer can have multiple services
isp.customer_services (1) ──< billing.invoices (M)
isp.customer_services (1) ──< network.pppoe_secrets (1)
isp.customer_services (1) ──< network.onu_devices (0..1)
network.onu_devices (M) ──> network.pon_ports (1)
network.pon_ports (M) ──> network.olt_devices (1)
network.pppoe_secrets (M) ──> network.mikrotik_routers (1)
network.pppoe_secrets (M) ──> network.radius_nas (1)      -- when RADIUS-managed
billing.invoices (1) ──< billing.payments (M)
billing.invoices (1) ──< billing.invoice_lines (M)
billing.payments (1) ──< accounting.ledger_entries (M)
isp.customers (1) ──< support.tickets (M)
support.tickets (M) ──> hr.employees (1)                  -- assigned technician
reseller.resellers (1) ──< isp.customers (M)               -- customer ownership
inventory.products (1) ──< inventory.stock_items (M)
inventory.stock_items (0..1) ──> isp.customer_services (0..1) -- serialized hardware assignment
automation.rules (1) ──< automation.executions (M)
audit.activity_logs (M) ──> identity.users (1)
```

### 7.4 Table Dictionary (key tables; full column-level DDL to be generated per-domain during implementation phase)

**tenancy.tenants**
`id UUID PK, name, slug UNIQUE, business_type (isp/wisp/ftth/cable_tv/...), status (active/suspended/trial), created_at, updated_at, deleted_at`

**tenancy.branches**
`id UUID PK, tenant_id FK→tenants, name, code, address, is_head_office BOOL, created_at, updated_at`

**identity.users**
`id UUID PK, tenant_id FK NULLABLE (null = platform staff), branch_id FK NULLABLE, name, username UNIQUE(tenant_id,username), email, password_hash, phone, nid, address, avatar_path, status, two_factor_secret NULLABLE, last_login_at, created_at, updated_at, deleted_at`

**isp.customers**  *(preserving every verified field from audit §5)*
`id UUID PK, tenant_id FK, branch_id FK, customer_code UNIQUE(tenant_id), full_name, mobile, other_mobile, email, gender, nid_passport_no, nid_passport_photo_path, address, fiber_code, agent_type, connection_type, connection_date, zone_id FK, subzone_id FK NULLABLE, destination_id FK NULLABLE, billing_person_id FK→users, status (active/inactive/free/discontinue), remarks, sms_notification_enabled BOOL, previous_due NUMERIC(12,2), temp_disconnect_day INT NULLABLE, created_at, updated_at, deleted_at`

**isp.customer_services** *(NEW — decouples "a customer" from "a billed service", enabling multi-service-per-customer for FTTH/CableTV/IPPhone bundles)*
`id UUID PK, customer_id FK, service_type (internet/cable_tv/ip_phone/cctv), package_id FK, monthly_bill NUMERIC(12,2), effective_from_current_month BOOL, connection_fee_paid NUMERIC(12,2), disconnect_day INT, status, created_at, updated_at`

**isp.packages**
`id UUID PK, tenant_id FK, mikrotik_id FK NULLABLE, mikrotik_profile_name, name, monthly_bill NUMERIC(12,2), bandwidth_down, bandwidth_up, is_active`

**isp.zones / isp.subzones / isp.destinations**
`id UUID PK, tenant_id FK, name, parent_id FK (for subzone→zone, destination→subzone), is_active`

**network.mikrotik_routers**
`id UUID PK, tenant_id FK, name, ip_address, port, username, password_encrypted (AES-256, key from KMS/secrets manager, never plaintext per project rule), status, last_connected_at`

**network.pppoe_secrets**
`id UUID PK, tenant_id FK, customer_service_id FK, router_id FK NULLABLE, radius_nas_id FK NULLABLE, username, secret_password_encrypted, profile, status (enabled/disabled), disabled_reason, last_sync_at`

**network.radius_nas** *(NEW)*
`id UUID PK, tenant_id FK, name, ip_address, secret_encrypted, vendor, type (pppoe/dhcp/ipoe/hotspot)`

**network.olt_devices**
`id UUID PK, tenant_id FK, device_type (BDCOM/V-SOL/ZTE/Huawei/Fiberhome), ip_address, username, password_encrypted, snmp_port DEFAULT 161, snmp_community_encrypted DEFAULT 'public', telnet_port, status, last_checked_at`

**network.pon_ports / network.onu_devices** *(NEW — architecture-ready extension of existing OLT registration form)*
`onu_devices: id UUID PK, tenant_id FK, pon_port_id FK, customer_service_id FK NULLABLE, serial_number, mac_address, rx_power, tx_power, status (online/offline/los), vlan, last_seen_at`

**billing.invoices**
`id UUID PK, tenant_id FK, customer_service_id FK, invoice_no (per-tenant sequence), billing_period_month, billing_period_year, amount_due, discount_amount, previous_due, total_due, status (unpaid/partial/paid/void), due_date, generated_at`

**billing.payments**
`id UUID PK, tenant_id FK, invoice_id FK, amount, discount_amount, method (cash/bkash/nagad/sslcommerz/stripe/bank), transaction_reference, collector_id FK→users, description, paid_at, created_at`

**accounting.chart_of_accounts / accounting.ledger_entries** *(NEW, upgrades flat Statement/Expense to real GL)*
`ledger_entries: id UUID PK, tenant_id FK, account_id FK, debit NUMERIC, credit NUMERIC, reference_type, reference_id, description, entry_date, created_by`

**support.tickets**
`id UUID PK, tenant_id FK, ticket_no, customer_id FK, category_id FK, priority, status, assigned_employee_id FK NULLABLE, sla_due_at, resolution_time_minutes, csat_rating NULLABLE, created_at`

**reseller.resellers**
`id UUID PK, tenant_id FK, parent_reseller_id FK NULLABLE (self-referential for sub-reseller), name, wallet_balance, credit_limit, commission_rule_id FK`

**automation.rules / automation.executions**
`rules: id UUID PK, tenant_id FK, name, trigger_type, condition_json, action_type, action_config_json, is_active`
`executions: id UUID PK, rule_id FK, triggered_at, status (success/failed), result_json`

**compliance.btrc_news** *(platform-level, NO tenant_id)*
`id UUID PK, title, body, source_url, published_at, category, is_published, ingestion_method (scraped/manual), reviewed_by FK→users NULLABLE`

**audit.activity_logs**
`id UUID PK, tenant_id FK NULLABLE, user_id FK, action, entity_type, entity_id, ip_address, device, before_json, after_json, result, created_at` — append-only, no update/delete permitted at application layer.

### 7.5 Index Strategy (representative — full list generated per table at implementation)
- Every `tenant_id` column: B-tree index (mandatory — every query filters by it first, RLS also relies on it).
- `isp.customers`: composite index `(tenant_id, status)`, `(tenant_id, zone_id)`, `(tenant_id, billing_person_id)` — matches audit's verified filter bar (Zone, Billing Person, Package, Status, Date).
- `billing.invoices`: `(tenant_id, status, due_date)` for due/overdue queries; `(customer_service_id, billing_period_year, billing_period_month)` unique.
- `network.pppoe_secrets`: unique `(router_id, username)`; index `(status)` for online/offline list queries.
- `audit.activity_logs`: `(tenant_id, created_at DESC)`, `(user_id, created_at DESC)` — logs are append-heavy, read-by-recency.
- Partial indexes for soft-deletes: `WHERE deleted_at IS NULL` on all soft-deletable tables to keep default queries fast.
- GIN index on any JSONB columns (automation `condition_json`, audit `before_json`/`after_json`) if queried by content.

---

## 12. API ARCHITECTURE

- **Style:** REST, JSON:API-influenced response envelope, versioned at URL path: `/api/v1/...`
- **Auth:** Laravel Sanctum/Passport — session cookies for the web app, Bearer tokens (personal access tokens / OAuth2 client-credentials) for mobile apps and third-party integrations.
- **API Keys:** per-tenant, scoped to specific feature keys, rate-limited independently, rotatable, revocable, logged in `integrations.api_keys` + `integrations.api_logs`.
- **Webhooks:** `integrations.webhook_subscriptions` (tenant_id, event_type, target_url, secret_for_hmac_signature, is_active) firing on domain events (payment.received, ticket.created, customer.disconnected, invoice.overdue) via queued jobs with retry/backoff.
- **Rate limiting:** per-tenant + per-API-key token bucket (Redis), separate limits for read vs write vs bulk-export endpoints.
- **Versioning policy:** additive changes in-place; breaking changes get a new `/v2` namespace with a documented deprecation window.
- Mobile apps (Customer, Technician, Admin PWA) consume the **exact same** `/api/v1` surface as the React web app — no parallel/undocumented endpoints, per project rule.

---

## 13. MIKROTIK / RADIUS / OLT / GPON ARCHITECTURE

**MikroTik layer** — preserves every verified capability: router registration, live RouterOS API polling for online/offline/static/unmatched secrets, bulk disconnect/reconnect, per-secret enable. Credentials encrypted at rest (AES-256-GCM, keys in a secrets manager, never in the `mikrotik_routers` table plaintext — closing the one real security gap implied by the audit).

**RADIUS layer (new)** — introduced as a **parallel, optional AAA path** alongside direct MikroTik API control, not a replacement — tenants can keep pure-MikroTik operation (matching current behavior) or opt into FreeRADIUS-compatible AAA for multi-vendor NAS support (routers beyond MikroTik, DHCP/IPoE/Hotspot). Accounting packets feed the same session-monitoring tables used by the Mikrotik Online/Offline views, so the UI is protocol-agnostic.

**OLT/GPON layer** — preserves verified device registration (device type, IP, credentials, SNMP/Telnet, "Check Connection"). Extends into full PON hierarchy: `OLT → PON Port → ONU/ONT → Customer Service`, with SNMP-polled signal (RX/TX power), LOS alarms, VLAN, and serial/MAC — exactly the data the audit flagged as `[NOT VERIFIED — post-registration behavior]` because no device was live; architecture is built so this activates automatically the moment a tenant registers a real OLT.

**Network Diagram** — the existing single "Root" node stub is rebuilt as a real graph rendering `Router → OLT → PON → ONU → Customer`, sourced live from the tables above (no separate manually-maintained diagram data).

---

## 14. BILLING & PAYMENT ARCHITECTURE

Preserves the verified flow: Bill Collection views (All Due/Full Paid/Previous Due/Not Generated) with Zone/Billing-Person/Status/date filters; Payment modal (Due Amount readonly, Pay Amount, Discount, auto-generated description). Bill generation — currently `[INFERRED]` scheduled job — becomes an explicit queued job (`GenerateMonthlyInvoices`) run per tenant per billing cycle, idempotent, logged.

New layer: `billing.invoices` as first-class entities (not just a running due balance) enabling proper partial/advance payment allocation, PDF invoice generation, refunds/credit-notes/debit-notes, and a **Payment Gateway Adapter interface** (`PaymentGatewayContract`) with concrete adapters for bKash, Nagad, SSLCommerz, and card gateways (Stripe-class) for markets beyond Bangladesh — all writing to the same `billing.payments` table regardless of channel, so collector attribution, ledger posting, and the auto-reconnect automation trigger work identically whether payment came from a field collector or the customer portal.

---

## 15. ACCOUNTING ARCHITECTURE

Preserves Income, Expense, Account Head/Sub-head, Statement, Monthly/Yearly Balance exactly as verified (including the salary→Expense posting link under head "Employee"). Adds a real double-entry layer underneath: Chart of Accounts, Journal, `accounting.ledger_entries` (debit/credit), Cash/Bank/Wallet accounts, Accounts Receivable (tied to `billing.invoices`) and Accounts Payable (tied to `inventory.purchases`), with the existing Balance Sheet/P&L reports becoming **derived views** over the ledger rather than separately-maintained numbers — eliminating the reconciliation drift risk implicit in the client's current flat-ledger design.

---

## 16. CRM ARCHITECTURE

New pre-sale layer the audit confirmed doesn't exist (`[VERIFIED] "no visible Lead/pre-sale stage before Create Customer"`): `crm.leads → crm.follow_ups → crm.opportunities → installation → isp.customers`. Lead conversion creates the customer record directly, preserving the existing Create Customer field set and MikroTik-secret auto-creation step.

---

## 17. INVENTORY ARCHITECTURE

Preserves Stock/Product/Category/Supplier/Purchase/Sale/Customer-Return/Supplier-Return exactly. Adds Multi-Warehouse, Stock Transfer/Adjustment, Serial/IMEI tracking (the audit noted Sales form already has Model No/Serial No/Expire Date columns, `[VERIFIED]` implying intent), Purchase Orders, Supplier Ledger, Low Stock Alerts, and — closing the gap the audit explicitly flagged as unlinked — a real FK from `inventory.stock_items` to `isp.customer_services` so ONU/router hardware sold or assigned to a customer is traceable end-to-end.

---

## 18. RESELLER / DEALER / FRANCHISE ARCHITECTURE

`Tenant → Franchise → Reseller → Sub-Reseller → Customer`, self-referential `reseller.resellers.parent_reseller_id`. Resellers see only customers they own (`data_scope = OWN`, enforced by RLS + RBAC, not just UI filtering). Commission rules configurable per reseller tier; wallet + credit limit + settlement ledger integrated into the accounting domain (reseller payouts post as ledger entries).

---

## 19. COMPLAINT / FIELD SERVICE ARCHITECTURE

Preserves the full verified ticketing workflow: Add Complaint (customer, template, priority, note, single + multiple assigned employees, customer/employee SMS toggles), View All Complaint (filters, 4 counters), Complaint Templates. Extends into: ticket numbering, SLA timers, category/subcategory, escalation rules (feeds the Automation Engine), attachments, customer reply thread, resolution-time tracking, CSAT rating — and a Field Service layer for installation/repair jobs with GPS check-in/out, before/after photos, digital signature, and spare-parts consumption (linked to Inventory).

---

## 20. SMS / NOTIFICATION ARCHITECTURE

Preserves every verified template (General, Due, Paid, Advance Paid, New Customer, Complaint) with their exact merge tags (`{CUSTOMER_NAME}`, `{PACKAGE_NAME}`, `{MONTHLY_BILL}`, `{CUSTOMER_ID}`, `{IP_ADDRESS}`, `{DUE_AMOUNT}`), the per-zone Due SMS breakdown, "Exclude Partially Paid Clients" toggle, and per-template active/inactive switches (the audit found Complaint SMS and Advance Paid SMS currently disabled — that per-tenant toggle state is preserved as tenant configuration, not hard-coded). Adds a channel-agnostic `communication.notifications` table so the same trigger can fan out to SMS, WhatsApp, Email, and Push through one Notification Center, with delivery-status tracking per channel.

---

## 21. AUTOMATION ENGINE

Generalizes the one fully-verified automation (daily cron auto-disconnect, logged in Auto MikroTik Disable Log) into a reusable engine:

```
TRIGGER (event or schedule)
   → CONDITION (JSON rule evaluated against entity state)
      → ACTION (disconnect / reconnect / send SMS / create ticket / notify / webhook)
         → EXECUTION (queued job)
            → LOG (automation.executions, mirrors existing Auto Mikrotik Disable Log / Auto SMS Log format)
```

Seeded default rules reproduce exactly what the client system does today (Bill Overdue → Disconnect; the currently-inactive Advance-Paid/Complaint SMS rules are seeded but left disabled per tenant, matching audit findings) — plus new rules (Payment Received → Reconnect, New Customer → Welcome SMS, ONU LOS → Ticket, Router Down → NOC Alert, Stock Low → Alert). Tenant admins can author custom rules through a UI builder without code changes.

---

## 22. AI ARCHITECTURE

AI is an orchestration layer, never a bypass of tenant isolation or entitlements: every AI query is executed as the requesting user, against RLS-scoped data, and gated by `ai.*` feature keys. Capabilities: churn prediction, revenue/payment forecasting, ticket auto-classification and reply drafting, network anomaly detection (feeding off Network Monitoring data), and natural-language analytics ("which zone had highest churn this month?") implemented as a constrained query-generation layer over the Analytics domain's pre-aggregated views — never raw free-form SQL generation against production tables.

---

## 23. BTRC COMPLIANCE + REGULATORY NEWS

**Compliance export** — preserves the verified BTRC Report exactly (Operator, Client Type, Distribution Location, Client Name, Connection Type, Connectivity Type, Activation Date, Bandwidth, Allocated IP, Address/District/Thana, Phone, Email, Selling Bandwidth), rebuilt as a configurable Report Template so column sets can evolve with regulation without a code deploy. This is subscription-gated (`compliance.reports.btrc`).

**Regulatory News** — platform-level, tenant-agnostic `compliance.btrc_news` table, **free on every plan** per your explicit instruction. Ingestion is hybrid: scheduled monitor checks btrc.gov.bd's news page (no official RSS/API exists — confirmed by research), stages candidates in a moderation queue, AR Qudrix Super Admin approves before publish — balancing freshness with accuracy. `compliance.alerts` (push notifications on new news matching tenant-configured keywords) and `compliance.advanced_tools` (license renewal tracking, document repository) remain plan-gated, per your instruction.

---

## 24. ANALYTICS & BI

Centralized `analytics` domain with pre-aggregated materialized views (refreshed via queue jobs, not computed live) for Revenue, Collection Rate, Customer Growth/Churn, ARPU, Package/Zone/Branch/Reseller/Employee/Network performance — feeding both the Dashboard (preserving all verified cards: Total/Active/Inactive/Discontinue/Free customers, monthly new/inactive, Total Collected Bill) and the Reports Center (Copy/Print/PDF/Excel export preserved exactly, plus scheduled report delivery as new capability).

---

## 25. CUSTOMER PORTAL

New — addresses the single largest confirmed competitive gap. Customer-facing PWA: login, current package, bill, pay online (via the Payment Gateway adapters), payment history, due amount, connection status, usage (where NAS/RADIUS accounting data available), submit complaint, view ticket status, notifications, profile, documents. Consumes the same `/api/v1` surface, scoped to a `customer` auth guard with `OWN`-only data scope.

---

## 26. PWA / MOBILE ARCHITECTURE

Three surfaces, one API:
- **Admin PWA** — the React web app itself, installable, offline-tolerant shell for dashboard/search/payment-collection/tickets/notifications (per Master Spec §18).
- **Customer Mobile App** — thin client over Customer Portal API.
- **Technician App** — assigned jobs, customer location/map, installation/repair workflow, GPS, photo/signature, spare parts, job status — offline-capable with sync-on-reconnect for field areas with poor connectivity.

---

## 27. SECURITY ARCHITECTURE

Password hashing (bcrypt/argon2id), RBAC + tenant isolation (RLS + service-layer, dual enforcement), input validation on every endpoint, parameterized queries only (Laravel Eloquent/query builder — no raw string SQL), CSRF tokens on session-based routes, XSS output-escaping by default (React), rate limiting (per-IP, per-user, per-API-key), session security (httpOnly/secure cookies, idle timeout), 2FA architecture (TOTP, optional-then-mandatory-for-admins rollout), immutable audit logs, secure file upload (type/size validation, virus-scan hook, private-by-default storage with signed URLs), all secrets (MikroTik/OLT/RADIUS/DB/API) encrypted at rest via a secrets manager — never plaintext, per project rule — HTTPS-only, automated encrypted backups with tested restore procedure.

---

## 28. AUDIT ARCHITECTURE

Append-only `audit.activity_logs` capturing who/what/when/where(IP)/device/before/after/result for every sensitive action (login, customer CRUD, payment, refund, billing, disconnect/reconnect, permission changes, subscription changes, financial changes, network config changes) — generalizing the verified 665-entry Activity Log plus the two verified cron logs (Auto MikroTik Disable, Auto SMS) into the same structured schema so all three become filterable/queryable together instead of separate ad-hoc tables.

---

## 29. QUEUE / WORKER ARCHITECTURE

Redis-backed queues (Laravel Horizon) with dedicated queues per workload class: `billing` (invoice generation), `notifications` (SMS/WhatsApp/Email/Push), `network` (MikroTik/RADIUS/OLT polling), `automation` (rule execution), `reports` (exports), `ai` (inference calls), `webhooks` (outbound delivery with retry/backoff). Nothing user-facing blocks on these — HTTP responses return immediately, results delivered via websocket/polling/notification.

---

## 30. BACKUP / DISASTER RECOVERY

Automated nightly full + continuous WAL-based point-in-time recovery for PostgreSQL; encrypted off-site backup storage; documented, **tested** restore runbook (quarterly restore drills, not just "backup exists"); file storage replicated cross-region; RPO/RTO targets defined per tenant SLA tier once pricing plans are finalized.

---

## 31. DEPLOYMENT ARCHITECTURE

Containerized services (Docker), orchestrated (Kubernetes or managed equivalent) separating: web (Laravel API), workers (queue consumers), scheduler (cron→automation triggers), React frontend (static/CDN-served), PostgreSQL (managed, with read replicas as scale demands), Redis (cache+queue+ratelimit), object storage (S3-compatible). Environments: local → staging → production, with tenant data never touching non-production environments except sanitized/anonymized fixtures.

---

## 32. TESTING STRATEGY

Unit tests (business logic, especially entitlement resolution and RBAC scope logic — these are the highest-risk-of-regression areas), feature/integration tests per module (billing generation, MikroTik sync, automation execution), contract tests for external integrations (MikroTik API, RADIUS, payment gateways — mocked), tenant-isolation regression suite (explicit tests asserting Tenant A can never read Tenant B's data via any endpoint), load testing before major releases given the "thousands of tenants" target.

---

## 33. MIGRATION STRATEGY

Old client data → new schema mapping, preserving original source data (never destroyed during migration, per project rule):

| Legacy | ARQ ISP OS |
|---|---|
| Single-tenant customer table | `isp.customers` + `isp.customer_services`, all rows tagged with the client's new `tenant_id` |
| MikroTik secrets | `network.pppoe_secrets` |
| Zones/SubZones/Destinations | `isp.zones/subzones/destinations` |
| Employees | `hr.employees` |
| Products/Suppliers/Purchases/Sales | `inventory.*` |
| Flat Income/Expense ledger | Backfilled into `accounting.ledger_entries` as opening-balance journal entries, with legacy Income/Expense views retained read-only for audit continuity |
| Activity/Cron logs | `audit.activity_logs` |

Migration runs as a scripted, idempotent, dry-run-first ETL job; the original client becomes ARQ ISP OS's first production tenant, validated against the AS-IS audit numbers (349 customers, 24 zones, 5 packages, 665 activity entries) as an acceptance check.

---

## 34. DEVELOPMENT PHASES

| Phase | Scope |
|---|---|
| **0 — Foundation** | Postgres schemas, tenancy + RLS, identity/RBAC, subscription/entitlement engine, API skeleton, CI/CD |
| **1 — Core ISP (parity)** | Customer, ISP Config, Billing/Payment (matching verified client flow), MikroTik integration, SMS, Activity Log, Dashboard |
| **2 — Financial depth** | Accounting/GL, Inventory, HR/Payroll, Reports Center |
| **3 — Network expansion** | RADIUS, OLT/PON/ONU live data, Network Monitoring, real Network Diagram |
| **4 — Growth features** | CRM, Complaint→full Ticketing, Field Service, Automation Engine |
| **5 — SaaS scale-out** | Reseller/Franchise/Multi-Branch, Payment Gateways, Customer Portal, Admin PWA |
| **6 — Advanced** | AI Layer, Mobile apps (Customer/Technician), Webhooks/public API docs, Regulatory News feed |
| **7 — Hardening & GA** | Security audit, load testing, DR drills, migration of the reference client as first tenant, public launch |

---

*End of Blueprint v1.0 — ready for detailed per-domain DDL generation and Phase 0 implementation kickoff.*
