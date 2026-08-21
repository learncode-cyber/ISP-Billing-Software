# AR Qudrix ISP OS

Multi-tenant ISP SaaS platform — PostgreSQL (RLS-enforced) + Laravel API +
four React/Vite apps sharing one codebase (staff console, customer portal,
technician app, AR Qudrix platform console). Offline-first, Bengali/English,
BTRC IP-log compliant, TR-069/ACS auto-provisioning.

## 📋 Start here

**[docs/FINAL_RELEASE_REPORT.md](docs/FINAL_RELEASE_REPORT.md)** is the
single authoritative release document — status, every test actually
executed, every defect found and fixed, exact deployment steps, and the
one layer that remains unverified (with the script to close it).

Raw evidence files (full test output, per-topic detail) live in
`docs/evidence/` and are referenced from the final report — read the
final report first.

## Quick start

```bash
# Database
createdb arq_isp_os
psql arq_isp_os -c "CREATE ROLE arq_app_role LOGIN PASSWORD '<secret>';"
psql arq_isp_os -c "CREATE ROLE arq_platform_admin_role LOGIN PASSWORD '<secret>' BYPASSRLS;"
DB_DATABASE=arq_isp_os DB_USER=postgres bash scripts/migrate.sh
for f in database/seeders/*.sql; do psql -d arq_isp_os -f "$f"; done

# Backend
cd backend && composer install && cp .env.example .env && php artisan key:generate
php artisan serve

# Verify the HTTP layer (the one thing not yet proven — see the final report)
BASE_URL=http://localhost:8000 bash scripts/verify-http-layer.sh

# Frontend (4 apps: index.html, portal.html, technician.html, platform.html)
cd frontend && npm install && npm run build
```

## Structure

```
backend/        Laravel API — controllers, models, jobs, services, tests
frontend/       React/Vite — 4 apps, offline layer, i18n (bn/en)
database/       27 migrations, 2 seeders — 118 tables, 108 RLS-protected
scripts/        migrate.sh (tracked), backup.sh, restore.sh, verify-http-layer.sh
deployment/     docker-compose.yml, CI gate scripts
.github/        CI/CD pipeline
docs/           FINAL_RELEASE_REPORT.md + evidence/
```

## What makes this different

Bengali UI, BTRC IP-Log Server (CGNAT-aware subscriber tracing), a
Customer Portal, Technician PWA and Super Admin console sharing one
codebase, TR-069/ACS zero-touch CPE provisioning, and — unique in this
market — a genuinely offline-first architecture: field staff keep working
with zero signal and everything syncs automatically on reconnect, with
idempotency keys that make duplicate payments technically impossible.
