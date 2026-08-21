-- ============================================================
-- AR QUDRIX ISP OS — Phase 0: Foundation
-- 000_extensions_and_schemas.sql
-- Creates required extensions and all logical domain schemas.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS citext;     -- case-insensitive email/username

-- Domain schemas (per Blueprint Section 7.1)
CREATE SCHEMA IF NOT EXISTS platform;
CREATE SCHEMA IF NOT EXISTS tenancy;
CREATE SCHEMA IF NOT EXISTS subscription;
CREATE SCHEMA IF NOT EXISTS identity;
CREATE SCHEMA IF NOT EXISTS crm;
CREATE SCHEMA IF NOT EXISTS isp;
CREATE SCHEMA IF NOT EXISTS billing;
CREATE SCHEMA IF NOT EXISTS network;
CREATE SCHEMA IF NOT EXISTS support;
CREATE SCHEMA IF NOT EXISTS accounting;
CREATE SCHEMA IF NOT EXISTS hr;
CREATE SCHEMA IF NOT EXISTS inventory;
CREATE SCHEMA IF NOT EXISTS reseller;
CREATE SCHEMA IF NOT EXISTS communication;
CREATE SCHEMA IF NOT EXISTS automation;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS compliance;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS integrations;
CREATE SCHEMA IF NOT EXISTS ai;

-- Standard trigger function: auto-update updated_at on any row change.
-- Applied to every table that has an updated_at column (Phase 0 tables below,
-- and every future domain table per project convention).
CREATE OR REPLACE FUNCTION platform.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Session variable convention used everywhere for RLS:
--   app.current_tenant_id  -> UUID of the authenticated request's tenant
--   app.is_platform_admin  -> 'true'/'false', set only by the privileged
--                              platform-admin service connection role
-- The backend MUST set these via `SET LOCAL` at the start of every
-- request-scoped transaction, immediately after authentication.
