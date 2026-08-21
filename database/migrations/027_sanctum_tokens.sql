-- ============================================================
-- 027_sanctum_tokens.sql — Laravel Sanctum token storage.
--
-- REAL DEFECT FOUND by HTTP-layer boot testing: Sanctum's HasApiTokens
-- trait (used on both App\Models\User and CustomerPortalAccount) expects
-- its own standard token table. The project's existing
-- identity.personal_access_tokens (migration 002) used an incompatible
-- schema designed for a different purpose (manual API key issuance) and
-- was never wired to Sanctum. This migration adds Sanctum's real,
-- required schema under a distinctly-named table so both can coexist.
--
-- tenant_id is denormalized onto the token row (populated at issuance,
-- not derived from the polymorphic tokenable relationship) specifically
-- so this table can carry the same RLS enforcement as every other
-- tenant-owned table in this project — Sanctum's own schema has no
-- tenant concept, so without this column the token store would be the
-- one table in the system NOT defended by RLS.
-- ============================================================

CREATE TABLE IF NOT EXISTS identity.sanctum_tokens (
    id                  BIGSERIAL PRIMARY KEY,
    tenant_id           UUID REFERENCES tenancy.tenants(id) ON DELETE CASCADE,  -- NULL for platform-staff tokens
    tokenable_type       VARCHAR(255) NOT NULL,
    tokenable_id          UUID NOT NULL,
    name                    VARCHAR(255) NOT NULL,
    token                     VARCHAR(64) NOT NULL UNIQUE,
    abilities                  TEXT,
    last_used_at                 TIMESTAMPTZ,
    expires_at                     TIMESTAMPTZ,
    created_at                       TIMESTAMPTZ,
    updated_at                       TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_sanctum_tokenable ON identity.sanctum_tokens (tokenable_type, tokenable_id);
CREATE INDEX IF NOT EXISTS idx_sanctum_tenant ON identity.sanctum_tokens (tenant_id);

ALTER TABLE identity.sanctum_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity.sanctum_tokens FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tenant_isolation ON identity.sanctum_tokens;
-- Platform-staff tokens (tenant_id NULL) are only visible under the
-- platform BYPASSRLS connection, matching every other platform-scope
-- table's convention in this project — an ordinary tenant session must
-- not enumerate or touch NULL-tenant token rows.
CREATE POLICY tenant_isolation ON identity.sanctum_tokens
    USING (tenant_id = platform.current_tenant_id());
