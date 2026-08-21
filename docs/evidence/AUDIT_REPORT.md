# AR QUDRIX ISP OS — PROJECT AUDIT REPORT

**Audit date:** 2026-08-10
**Audited against:** AR Qudrix ISP OS — Final Technical Blueprint v1.0
**Auditor environment:** static analysis + Node/Vite toolchain

---

## 0. VERIFICATION CAPABILITY — READ THIS FIRST

The audit brief defines **VERIFIED** as *"the feature actually works end-to-end and has been verified"*, and mandates E2E workflow testing, live multi-tenant penetration testing, and browser testing at 13 viewport widths.

**The audit environment cannot perform those tests.** Confirmed by direct check:

| Tool | Status | Consequence |
|---|---|---|
| PHP | **absent** (apt mirror returns 404) | No Laravel boot, no route execution, no E2E |
| PostgreSQL / psql | **absent** | No migrations run, no RLS enforcement test, no tenant-isolation pentest |
| Browser (Chromium/Firefox) | **absent** | No viewport rendering, no visual QA, no touch testing |
| Node / npm / Vite | **present** | Frontend build + runtime render tests **are** possible |

Therefore **no requirement in this report is marked `[IMPLEMENTED + VERIFIED]` on the strength of runtime E2E testing**, with the narrow exception of frontend artifacts actually built and rendered here. Everything else that exists in source and passes static cross-referencing is classified `[IMPLEMENTED BUT NOT VERIFIED]` — which is exactly what the brief demands be distinguished, rather than papered over.

**What this audit did do:** found and fixed real defects that static analysis and the available toolchain *can* prove. Those are itemised in §2 and §3 with before/after evidence.

---

## 1. WHAT WAS ACTUALLY VERIFIED (evidence-backed)

| Check | Method | Result |
|---|---|---|
| Frontend production build | `vite build` | ✅ 58 modules transformed, 208 kB JS / 4.24 kB CSS emitted |
| Component runtime rendering | `react-dom/server` renderToString, 12 cases incl. edge cases (unknown icon name, unknown status value, `rows={null}`) | ✅ 12/12 render without exception |
| Responsive CSS reaches bundle | token grep on emitted `dist/assets/*.css` | ✅ `responsive-cards`, `table-scroll`, `pointer: coarse`, `--touch`, 7 media queries all present |
| Route → controller method existence | cross-reference of all 58 explicit route bindings | ✅ all resolve after fix B1 |
| DI service class existence | cross-reference of all `app(X::class)` calls | ✅ all resolve |
| PHP structural integrity | open-tag / brace / paren balance, 102 files | ✅ all pass |
| Frontend syntax | esbuild parse, 26 files | ✅ all pass |

---

## 2. DEFECTS FOUND AND FIXED

### B1 — Phantom REST routes (backend) · severity: HIGH · **FIXED**
`Route::apiResource()` registers `show`, `update`, and `destroy` routes unconditionally. Four controllers lacked some of those methods:

| Controller | Missing methods | Routes that would 500 |
|---|---|---|
| `LeadController` | `show`, `destroy` | `GET/DELETE /leads/{id}` |
| `AutomationRuleController` | `show` | `GET /automation-rules/{id}` |
| `WebhookController` | `show`, `update` | `GET/PUT /webhooks/{id}` |
| `ApiKeyController` | `show`, `update` | already constrained by `->only()` |

**Fix:** each `apiResource` constrained with `->only([...])` listing only implemented verbs. No phantom routes remain.

### M1–M7 — Mobile responsiveness (frontend) · severity: CRITICAL · **FIXED**
The brief calls this section "EXTREMELY STRICT" and requires 320px support. The frontend failed it comprehensively.

| ID | Defect found | Fix applied |
|---|---|---|
| M1 | **Zero** responsive media queries in the entire frontend (only `prefers-reduced-motion`) | 6 breakpoints added: 1023px, 640px, 380px, plus `pointer: coarse` |
| M2 | `AppShell` used `gridTemplateColumns: "244px 1fr"` with no breakpoint — at 320px the sidebar consumed 244px, leaving **76px** for all content | Sidebar becomes an off-canvas drawer below 1024px (hamburger, backdrop, Escape-to-close, body-scroll lock, navigation auto-close); layout is flex with `minWidth: 0` so content always gets full width |
| M3 | `DataTable` had no scroll container — wide tables overflowed the **page**, which the brief explicitly forbids | Tables wrapped in `.table-scroll` (overflow contained to the table); below 640px rows restack as labelled cards via `data-label`, so no sideways scrolling is needed at all on phones |
| M4 | Pay modal hardcoded `width: 420` → overflowed 320/360/375/390px viewports | Shared `Modal` primitive: `width: min(440px, 100%)`, `maxHeight: calc(100vh - 24px)`, internal scroll, Escape + backdrop close |
| M5 | Login card hardcoded `width: 360` → overflowed 320px | `width: min(360px, 100%)` + viewport padding |
| M6 | Tickets used `repeat(4, 1fr)` → four cards crushed at 320px | New `StatGrid` primitive using `auto-fit / minmax`, applied to Dashboard and Tickets |
| M7 | Touch targets ~33px (below the 44px floor) | `--touch: 44px`; `@media (pointer: coarse)` raises all `.btn` to 44px min-height; inputs forced to 16px on mobile to prevent iOS zoom-on-focus |

**Additional hardening:** `html, body { overflow-x: hidden }` guarantees no page-level horizontal scroll; tab strips (Billing, MikroTik, Inventory) scroll horizontally within themselves rather than wrapping or overflowing; `PageHeader` wraps its action button; `.sr-only` utility and labelled search input added.

**Verification:** 16/16 responsive-contract lint assertions pass, and every rule confirmed present in the emitted production CSS.

---

## 3. IMPLEMENTATION-VS-BLUEPRINT MATRIX

Classification per the brief's taxonomy. "Not verified" here means *not runtime-tested* (see §0), not *not written*.

### Foundation
| Requirement | Status | Notes |
|---|---|---|
| PostgreSQL domain schemas (20) | `[IMPLEMENTED BUT NOT VERIFIED]` | 23 migrations, 106 tables; never executed against a live DB |
| Multi-tenancy + RLS | `[IMPLEMENTED BUT NOT VERIFIED]` | `FORCE ROW LEVEL SECURITY` + `tenant_isolation` policy on every tenant-owned table; **isolation never runtime-proven** — this is the single most important untested item |
| RBAC (roles/permissions/data scope) | `[IMPLEMENTED BUT NOT VERIFIED]` | Middleware + seeded catalog present |
| Subscription entitlement engine | `[IMPLEMENTED BUT NOT VERIFIED]` | SQL resolver fn + cached app-layer mirror; 402-vs-403 distinction implemented |
| Auth (Sanctum, dual guards) | `[IMPLEMENTED BUT NOT VERIFIED]` | Staff + customer guards structurally separated |

### Modules
| Module | Status |
|---|---|
| Customers, Packages/Zones, Billing, Payments | `[IMPLEMENTED BUT NOT VERIFIED]` |
| Accounting (GL, heads, statement, balance sheet) | `[IMPLEMENTED BUT NOT VERIFIED]` |
| HR/Payroll, Inventory, CRM/Leads, Ticketing | `[IMPLEMENTED BUT NOT VERIFIED]` |
| Reseller/Franchise/Commission/Wallet | `[IMPLEMENTED BUT NOT VERIFIED]` |
| Automation engine (trigger→condition→action→log) | `[IMPLEMENTED BUT NOT VERIFIED]` |
| BTRC report export | `[IMPLEMENTED BUT NOT VERIFIED]` |
| BTRC regulatory news (free on all plans) | `[PARTIALLY IMPLEMENTED]` — storage, moderation queue, API, UI complete; **ingestion parser is a stub** (see §4) |
| Analytics / dashboard | `[IMPLEMENTED BUT NOT VERIFIED]` |
| Audit log | `[IMPLEMENTED BUT NOT VERIFIED]` |
| Queue workers + scheduler (11 jobs) | `[IMPLEMENTED BUT NOT VERIFIED]` |
| Frontend admin console (16 pages) | `[IMPLEMENTED + BUILD-VERIFIED]` — builds and renders; **not** workflow-tested against a live API |
| Mobile responsiveness | `[IMPLEMENTED + STATICALLY VERIFIED]` — contract lint passes, CSS confirmed in bundle; **not** browser-tested at the 13 mandated widths |

### Not built
| Requirement | Status |
|---|---|
| Customer portal **frontend** | `[MISSING]` — backend API + auth guard exist; no portal UI built |
| Technician mobile app | `[MISSING]` — backend endpoints exist; `/field-jobs` admin page is still a scaffold |
| Super Admin (AR Qudrix platform) console | `[MISSING]` — `TenantProvisioningService` exists but there is no UI to manage tenants/plans/feature overrides |
| PWA manifest + service worker | `[MISSING]` — described as "PWA-ready"; no `manifest.json` or SW present |
| IPAM module | `[MISSING]` — in blueprint module tree, no tables/API |
| Multi-branch UI | `[PARTIALLY IMPLEMENTED]` — `branch_id` modelled throughout; no branch management screens |
| CI/CD pipeline | `[MISSING]` — `migration-lint.sh` exists but no workflow file invokes it |
| Toast/notification system (frontend) | `[MISSING]` — errors surface inline only; no global toast |
| Loading skeletons | `[PARTIALLY IMPLEMENTED]` — plain "Loading…" text, not skeletons |

---

## 4. EXTERNAL DEPENDENCIES REQUIRED

Each is a genuine external-system boundary, marked in-code, with the exact setup needed.

**[EXTERNAL DEPENDENCY REQUIRED] — RouterOS API client**
*Blocks:* MikroTik sync, secret create/enable/disable, live sessions, auto-disconnect.
*Needs:* reachable RouterOS device, API-enabled user, port (8728/8729-TLS). Install e.g. `evilfreelancer/routeros-api-php`; implement inside `MikrotikService::syncRouterState()` / the two secret jobs.

**[EXTERNAL DEPENDENCY REQUIRED] — OLT SNMP/Telnet vendor clients**
*Blocks:* ONU discovery, RX/TX power, LOS events, PON mapping.
*Needs:* live OLT per vendor + its MIB; PHP `snmp` extension. Vendor-specific OIDs differ across BDCOM/V-SOL/ZTE/Huawei/Fiberhome — each needs its own tested implementation in `OltService`.

**[EXTERNAL DEPENDENCY REQUIRED] — Payment gateways (bKash / Nagad / SSLCommerz / Stripe)**
*Blocks:* online customer payment; cash collection is unaffected.
*Needs:* merchant sandbox credentials per provider; implement `initiate()` + `handleCallback()` in each adapter. The shared `confirmPayment()` path is complete, so one wired gateway proves the pattern.

**[EXTERNAL DEPENDENCY REQUIRED] — LLM API (AI assistant)**
*Blocks:* NL-analytics intent classification only. Churn scoring works without it (transparent heuristic).
*Needs:* `ANTHROPIC_API_KEY`; implement `NlAnalyticsService::classifyIntent()`. Design constraint to preserve: the model selects an **intent + params only** — it must never generate SQL.

**[EXTERNAL DEPENDENCY REQUIRED] — BTRC news HTML extraction**
*Blocks:* automatic news ingestion; manual publication by Super Admin works.
*Needs:* btrc.gov.bd exposes no RSS/API, so `BtrcNewsIngestionService::extractItems()` needs a DOM-crawler implementation against the live page, plus a monitor for markup changes.

**[EXTERNAL DEPENDENCY REQUIRED] — SMS gateway**
*Blocks:* all SMS automations (templates, merge tags, scheduling all exist).
*Needs:* provider credentials; implement the send call in `SmsService`.

---

## 5. HONEST RELEASE ASSESSMENT

Against the brief's gate — **FINAL → VERIFIED → HARDENED → TESTED → DEPLOYMENT-READY → DELIVERABLE** — the project's true position is:

**FINAL (feature-complete in source): substantially yes, with named gaps** (§3 "Not built").
**VERIFIED: no.** Nothing has been executed against a live PHP + PostgreSQL stack.
**HARDENED / TESTED / DEPLOYMENT-READY / DELIVERABLE: no.**

**The single highest risk** is that tenant isolation — the security property the whole SaaS model rests on — has never been runtime-proven. `TenantIsolationTest` is written but has never run. Until it passes against a live database, multi-tenant safety is an *assumption*, not a fact.

### Required path to genuine "VERIFIED"
1. Stand up PHP 8.2 + PostgreSQL 16 + Redis; `composer install`; run all 23 migrations + 2 seeders.
2. Run `TenantIsolationTest` and `EntitlementAndPermissionTest`. **Gate: these must pass before anything else counts.**
3. Provision two tenants on different plans; walk the 11 E2E workflows in the brief §6.
4. Browser-test all 16 pages at the 13 mandated widths (the responsive foundation is now in place, but placed ≠ proven).
5. Wire the six external dependencies in §4, each with its own integration test.
6. Build the four missing surfaces (customer portal UI, technician app, Super Admin console, PWA manifest/SW).
7. Add a CI workflow that runs `migration-lint.sh` + the test suites on every commit.

I would not describe this system as deployable to a paying tenant until at least steps 1–3 pass.
