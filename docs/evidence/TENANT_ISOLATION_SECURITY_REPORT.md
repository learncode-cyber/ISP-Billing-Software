# TENANT ISOLATION SECURITY REPORT
**Executed:** 2026-08-10 · **Environment:** PostgreSQL 16.14 (live) · **Status:** RELEASE BLOCKER — CLEARED

## Method
Two tenants seeded with equivalent data (branch, user, zone, customer, service, invoice, audit log) via the `BYPASSRLS` platform role. All attack traffic then issued as `arq_app_role` — the ordinary application role — with RLS active, exactly as the running application connects.

## Results — 17/17 PASS

| # | Attack | Result | Verdict |
|---|---|---|---|
| T1 | Enumerate all customers | 1 row (own only) | PASS |
| T2 | Read Tenant B customer by UUID | 0 rows | PASS — blocked |
| T3 | Enumerate invoices | 1 row | PASS |
| T4 | Read Tenant B invoice by UUID | 0 rows | PASS — blocked |
| T5 | Read audit logs | 1 row | PASS |
| T6 | Read branches | 1 row | PASS |
| T7 | Read users | 1 row | PASS |
| T8 | Read zones | 1 row | PASS |
| T9 | Read services | 1 row | PASS |
| T10 | **UPDATE** Tenant B customer | 0 rows affected | PASS — blocked |
| T11 | **DELETE** Tenant B customer | 0 rows affected | PASS — blocked |
| T12 | **DELETE** Tenant B invoice | 0 rows affected | PASS — blocked |
| T13 | Aggregate COUNT leak | own only | PASS |
| T14 | Revenue SUM leak | 500.00 (own only, not 1200) | PASS |
| T15 | JOIN across tenant boundary | 1 row | PASS |
| T16 | Search/ILIKE filter leak | 0 rows | PASS — blocked |
| T17 | Subquery bypass via `tenant_id IN (SELECT id FROM tenancy.tenants)` | 1 row (own) | PASS — RLS holds despite the platform table being unrestricted |

## Schema-level audit
- Tables with `tenant_id` and **no** RLS: **0** (was 1 — see defect S1 below)
- RLS-enabled tables: **97**
- `tenant_isolation` policies: **97**
- All policies use `FORCE ROW LEVEL SECURITY`, so even the table owner is subject to them.

## Defect found and fixed
**S1 — `support.ticket_sequences` had `tenant_id` but no RLS.** Discovered by querying `pg_class.relrowsecurity` against live schema, not by reading source. Per-tenant ticket numbering was readable and writable across tenants. Policy added to migration `018` and applied. Re-verified: 0 unprotected tenant tables.

## Residual risk (documented, not fixed by code)
Session variable `app.current_tenant_id` is set by `SetTenantContext` from the **authenticated user's** `tenant_id`, never from request input. Any future code path that lets user-supplied data reach that call would be a full tenant escape. This is enforced by code review, and the middleware is the single place the value is set.

**Verdict: tenant isolation is proven at the database layer. Release blocker cleared.**
