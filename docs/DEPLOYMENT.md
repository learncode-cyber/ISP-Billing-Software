# AR Qudrix ISP OS — Local Setup (end-to-end)

Bring the whole stack up: PostgreSQL (with RLS) → Laravel API → React console.

## 1. Database

```bash
createdb arq_isp_os

# Create the two roles (app + platform-admin) — see database README.
psql arq_isp_os -c "CREATE ROLE arq_app_role LOGIN PASSWORD 'devpass';"
psql arq_isp_os -c "CREATE ROLE arq_platform_admin_role LOGIN PASSWORD 'devpass' BYPASSRLS;"

# Run migrations in order, then seeds.
for f in database/migrations/*.sql; do psql arq_isp_os -f "$f"; done
psql arq_isp_os -f database/seeders/001_phase0_seed.sql
psql arq_isp_os -f database/seeders/002_seed_default_automation_rules.sql

# Grants so the app role can use the schemas.
psql arq_isp_os -c "GRANT USAGE ON ALL SCHEMAS IN DATABASE arq_isp_os TO arq_app_role, arq_platform_admin_role;" 2>/dev/null || \
  psql arq_isp_os -c "GRANT USAGE ON SCHEMA platform,tenancy,subscription,identity,isp,billing,network,accounting,hr,inventory,crm,support,reseller,communication,automation,analytics,compliance,audit,integrations,ai TO arq_app_role, arq_platform_admin_role;"
psql arq_isp_os -c "GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA tenancy,identity,subscription,isp,billing,network,accounting,hr,inventory,crm,support,reseller,communication,automation,analytics,compliance,audit,integrations,ai TO arq_app_role;"
psql arq_isp_os -c "REVOKE UPDATE,DELETE ON audit.activity_logs FROM arq_app_role;"
```

## 2. Backend (Laravel)

```bash
cd backend
composer install
cp .env.example .env
php artisan key:generate
# set DB_PASSWORD=devpass and DB_PLATFORM_PASSWORD=devpass in .env

# Create the first tenant (its Owner user is what you log in as):
php artisan tinker
>>> app(App\Services\TenantProvisioningService::class)->provision([
      'name' => 'MO Network', 'plan' => 'enterprise',
      'owner_username' => 'owner', 'owner_password' => 'secret123',
    ]);

php artisan serve   # http://localhost:8000
php artisan horizon  # queue workers (separate terminal)
```

## 3. Frontend (React)

```bash
cd frontend
npm install
VITE_API_TARGET=http://localhost:8000 npm run dev   # http://localhost:5173
```

Log in with `owner` / `secret123`. The sidebar renders every module
because the tenant is on the Enterprise plan and the Owner role has all
permissions. Provision a `starter`-plan tenant to watch the sidebar
shrink to just Customers + Billing — the entitlement engine in action.

## 4. Verify tenant isolation

```bash
cd backend
php artisan test --filter=TenantIsolationTest
php artisan test --filter=EntitlementAndPermissionTest
```

## What runs vs. what's a stubbed integration boundary

**Runs end-to-end now:** auth, tenant provisioning, RLS isolation,
entitlement+permission gating, customer CRUD, payment collection (+
invoice recalc trigger), dashboard, expenses/payroll→GL, tickets,
automation rule execution + logging, capabilities-driven frontend.

**Stubbed (needs live credentials/hardware — marked in-code):** RouterOS
API calls, OLT SNMP, payment gateway HTTP round-trips, LLM intent
classification, BTRC HTML scraping. Each has its contract + surrounding
logic complete; only the external wire-up remains.
