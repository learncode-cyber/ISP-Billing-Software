# SECURITY AUDIT

## Tested live (PostgreSQL 16.14)
| Control | Test | Result |
|---|---|---|
| Tenant isolation (read) | 9 cross-tenant SELECT attacks incl. UUID substitution, JOIN, ILIKE search, aggregate, subquery bypass | **PASS** — 0 leaks |
| Tenant isolation (write) | UPDATE/DELETE against another tenant's customer and invoice | **PASS** — 0 rows affected |
| RLS coverage | `pg_class.relrowsecurity` across all 106 tables | **PASS** after fixing S1 — 0 tenant tables unprotected |
| `FORCE ROW LEVEL SECURITY` | applied to all 97 policies | **PASS** — table owner also subject to RLS |
| Audit log immutability | UPDATE and DELETE as app role | **PASS** — `permission denied` both times |
| Entitlement secure-default | unknown feature key | **PASS** — denies |
| Credential storage | schema inspection | **PASS** — every credential column is `*_encrypted`; models list them in `$hidden` |

## Defects found and fixed
- **S1 (HIGH)** — `support.ticket_sequences` had `tenant_id` but no RLS policy: per-tenant ticket numbering was cross-tenant readable/writable. Found by live `pg_class` inspection, not source reading. Fixed and re-verified.
- **B3 (CRITICAL, availability)** — `SetTenantContext` used `SET LOCAL` outside a transaction; Postgres ignores it (`WARNING: SET LOCAL can only be used in transaction blocks`), so **every RLS query returned zero rows** and the application would have been entirely non-functional. Fail-closed, so not a leak — but a total outage. Fixed with session-scoped `set_config(..., false)` plus explicit reset-to-empty on unauthenticated requests so a reused connection can never inherit a previous tenant's scope.
- **B2 (CRITICAL)** — 13 files used `DB::statement('SET x = ?', [...])`. Postgres `SET` does not accept bind parameters — this is a hard syntax error (`ERROR: syntax error at or near "$1"`), meaning **all 11 queue jobs would have crashed on first execution**. Verified by live PDO test, then fixed across every occurrence.
- **B1 (HIGH)** — `apiResource` registered `show`/`update`/`destroy` routes for 4 controllers lacking those methods → 500 at runtime. Constrained with `->only()`.

## Not tested (requires HTTP layer — Composer/Packagist blocked, verified 403)
SQL injection via API, XSS, CSRF, IDOR through endpoints, mass assignment, file-upload security, rate-limit bypass, session fixation, webhook/payment-callback forgery. The code-level protections exist (parameterized queries throughout, `$fillable` on every model, HMAC verification on webhooks, signature checks in gateway adapters) but are **unproven at the HTTP layer.**

## Repository hygiene
No `.env`, keys, or credentials committed. `.env.example` documents every variable. Encryption keys sourced from the environment, never hardcoded.
