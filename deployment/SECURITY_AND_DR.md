# AR Qudrix ISP OS — Security Hardening & Disaster Recovery
Blueprint Sections 27 (Security), 30 (Backup/DR), 32 (Testing).

## Security hardening checklist (Phase 7 — verify before GA)

### Authentication & authorization
- [x] Password hashing: argon2id / bcrypt (Laravel default) — never plaintext.
- [x] RBAC: Module.Resource.Action + data scope (ALL/BRANCH/OWN/ASSIGNED).
- [x] Tenant isolation: PostgreSQL RLS (`FORCE ROW LEVEL SECURITY`) + app-layer `BelongsToTenant` scope — dual enforcement.
- [x] Entitlement AND permission both required (CheckEntitlement → CheckPermission chain).
- [ ] 2FA (TOTP) — schema present (`identity.users.two_factor_secret`); enable optional-then-mandatory-for-admins rollout before GA.
- [x] Separate auth guards: staff (`sanctum`) vs customer portal (`customer`) — never mixed.
- [x] Platform-admin DB role (`BYPASSRLS`) isolated to Super Admin code paths only.

### Data protection
- [x] All secrets encrypted at rest (MikroTik/OLT/RADIUS creds, payment gateway creds, webhook signing secrets) — AES-256-GCM via Laravel Crypt, keyed from secrets manager. Verified: every credential column is `*_encrypted` and every model with such columns lists them in `$hidden`.
- [x] Append-only audit log (`audit.activity_logs`): UPDATE/DELETE revoked from app DB role.
- [ ] Field-level PII review (NID numbers, NID photos) — confirm private-by-default storage with signed URLs; run before GA.

### Application security
- [x] Parameterized queries only (Eloquent / query builder) — no raw string SQL concatenation.
- [x] Input validation on every write endpoint (Laravel form request / validate()).
- [ ] CSRF on session routes; XSS via React default escaping — verify no `dangerouslySetInnerHTML` on user data.
- [ ] Rate limiting: per-IP (auth), per-user, per-API-key — configured in Phase 6; load-test the limits.
- [x] AI cannot generate free-form SQL — constrained intent → parameterized view queries only.
- [ ] Secure file upload: type/size validation + AV-scan hook + private storage — verify on ticket/customer-doc/field-photo uploads.

### Pre-GA penetration focus areas (highest risk)
1. Cross-tenant access via every endpoint (automated by `TenantIsolationTest`, plus manual pentest).
2. Entitlement bypass (can a Starter tenant reach a Business feature by crafting requests?).
3. Customer-portal scope escape (can customer A see customer B's invoice/ticket?).
4. Payment gateway callback forgery (HMAC/signature verification on every provider).
5. Reseller OWN-scope escape (can a reseller list customers they don't own?).

## Disaster Recovery runbook (Blueprint Section 30 — "restore must be testable")

### Backup
- PostgreSQL: nightly full dump + continuous WAL archiving → encrypted off-site (cross-region) storage.
- Object storage (NID photos, invoices, ticket attachments, field photos): cross-region replication.
- Retention: 30 daily, 12 monthly, per-tenant SLA tier may extend.

### Restore (TESTED quarterly — "backup exists" is NOT sufficient)
1. Provision a clean PostgreSQL instance.
2. Restore latest full dump, replay WAL to the target point-in-time (RPO target: ≤ 5 min).
3. Re-point object storage / restore replicated bucket.
4. Run the acceptance validation queries (see migration_etl) against a known tenant.
5. Smoke test: login, load dashboard, collect a test payment, verify RLS isolation still enforced.
6. Record restore duration; assert within RTO target (define per SLA tier at pricing finalization).

### Failure-mode drills to run before GA
- Single AZ loss (DB replica promotion).
- Redis loss (cache rebuilds; queue jobs re-enqueued — verify no double-charge on payment jobs; jobs are idempotent).
- Full region loss (cross-region restore, measured against RTO).
