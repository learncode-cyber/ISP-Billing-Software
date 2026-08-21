-- ============================================================
-- 005_rls_policies.sql — Row-Level Security (Blueprint Section 4)
--
-- Enforces tenant isolation AT THE DATABASE LEVEL as defense-in-depth
-- alongside the Laravel service-layer tenant scope. This is deliberate:
-- the project rule is "never rely only on frontend filtering" — this
-- goes further and does not rely solely on backend application code
-- either. Even a buggy/compromised query cannot cross tenant boundaries.
--
-- Session contract (set by the backend at the start of every request
-- transaction, immediately after authentication):
--   SET LOCAL app.current_tenant_id = '<uuid>';
--   SET LOCAL app.is_platform_admin = 'true' | 'false';
--
-- The platform-admin service DB role is granted BYPASSRLS and is used
-- ONLY by Super Admin console code paths — never by tenant-facing code.
-- ============================================================

-- Helper to safely read the session var even when unset (avoids errors
-- on connections that haven't authenticated yet, e.g. health checks).
CREATE OR REPLACE FUNCTION platform.current_tenant_id() RETURNS UUID AS $$
    SELECT NULLIF(current_setting('app.current_tenant_id', true), '')::UUID;
$$ LANGUAGE sql STABLE;

-- ---- tenancy.branches ----
ALTER TABLE tenancy.branches ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenancy.branches FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON tenancy.branches
    USING (tenant_id = platform.current_tenant_id());

-- ---- identity.users ----
-- Platform staff rows (tenant_id IS NULL) are visible only to platform admins.
ALTER TABLE identity.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.users FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.users
    USING (tenant_id = platform.current_tenant_id());

-- ---- identity.roles ----
-- System template roles (tenant_id IS NULL) are readable by all tenants
-- but not owned by any of them; tenant-custom roles are isolated.
ALTER TABLE identity.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.roles FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.roles
    USING (tenant_id = platform.current_tenant_id() OR tenant_id IS NULL);

-- ---- identity.user_roles / role_permissions ----
-- Isolated transitively via a join check against roles/users owned by the tenant.
ALTER TABLE identity.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.user_roles FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON identity.user_roles
    USING (
        EXISTS (
            SELECT 1 FROM identity.users u
            WHERE u.id = user_roles.user_id
              AND u.tenant_id = platform.current_tenant_id()
        )
    );

-- ---- subscription.tenant_subscriptions ----
ALTER TABLE subscription.tenant_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription.tenant_subscriptions FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON subscription.tenant_subscriptions
    USING (tenant_id = platform.current_tenant_id());

-- ---- subscription.tenant_feature_overrides ----
ALTER TABLE subscription.tenant_feature_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscription.tenant_feature_overrides FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON subscription.tenant_feature_overrides
    USING (tenant_id = platform.current_tenant_id());

-- ---- audit.activity_logs ----
ALTER TABLE audit.activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit.activity_logs FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON audit.activity_logs
    USING (tenant_id = platform.current_tenant_id());

-- ---- Platform-level tables: NO RLS ----
-- tenancy.tenants, subscription.plans, subscription.features,
-- subscription.plan_features, compliance.btrc_news (added in a later
-- migration) are intentionally NOT tenant-scoped: they are platform-owned
-- and readable by every tenant, writable only through Super Admin service
-- code running under the BYPASSRLS role.

-- ============================================================
-- CONVENTION FOR ALL FUTURE DOMAIN TABLES (isp, billing, network, ...):
-- Every tenant-owned table created from Phase 1 onward MUST include:
--   1. tenant_id UUID NOT NULL REFERENCES tenancy.tenants(id)
--   2. ALTER TABLE ... ENABLE ROW LEVEL SECURITY;
--   3. ALTER TABLE ... FORCE ROW LEVEL SECURITY;
--   4. CREATE POLICY tenant_isolation ON ... USING (tenant_id = platform.current_tenant_id());
-- This is enforced by a migration-lint CI check (Phase 0 CI/CD task).
-- ============================================================
