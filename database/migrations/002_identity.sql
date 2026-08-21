-- ============================================================
-- 002_identity.sql — identity & RBAC domain (Blueprint Section 6)
-- ============================================================

CREATE TABLE identity.users (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID REFERENCES tenancy.tenants(id) ON DELETE CASCADE, -- NULL = platform staff
    branch_id           UUID REFERENCES tenancy.branches(id),
    name                VARCHAR(255) NOT NULL,
    username            CITEXT NOT NULL,
    email               CITEXT,
    password_hash       VARCHAR(255) NOT NULL,
    phone               VARCHAR(30),
    nid                 VARCHAR(50),
    address             TEXT,
    avatar_path         VARCHAR(500),
    status              VARCHAR(20) NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
    two_factor_secret   VARCHAR(255),
    two_factor_enabled  BOOLEAN NOT NULL DEFAULT false,
    last_login_at       TIMESTAMPTZ,
    last_login_ip       INET,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ,
    -- username must be unique within a tenant; platform staff (tenant_id NULL)
    -- unique globally — handled via two partial unique indexes below.
    UNIQUE (tenant_id, username)
);
CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON identity.users
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE UNIQUE INDEX idx_users_platform_username ON identity.users(username) WHERE tenant_id IS NULL;
CREATE INDEX idx_users_tenant ON identity.users(tenant_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_email ON identity.users(email) WHERE deleted_at IS NULL;

-- Canonical permission catalog: Module.Resource.Action
CREATE TABLE identity.permissions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    module              VARCHAR(100) NOT NULL,      -- e.g. 'billing', 'network.mikrotik'
    resource            VARCHAR(100) NOT NULL,      -- e.g. 'invoice', 'router'
    action              VARCHAR(20) NOT NULL CHECK (action IN
                         ('view','create','edit','delete','approve','export',
                          'import','pay','refund','disconnect','reconnect',
                          'send','assign','manage')),
    key                 VARCHAR(200) GENERATED ALWAYS AS (module || '.' || resource || '.' || action) STORED,
    description         VARCHAR(255),
    UNIQUE (module, resource, action)
);
CREATE UNIQUE INDEX idx_permissions_key ON identity.permissions(key);

CREATE TABLE identity.roles (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID REFERENCES tenancy.tenants(id) ON DELETE CASCADE, -- NULL = system role template
    name                VARCHAR(100) NOT NULL,
    code                VARCHAR(100) NOT NULL,       -- e.g. 'owner','admin','noc_operator','custom_xyz'
    is_system           BOOLEAN NOT NULL DEFAULT false, -- true = seeded template role (Owner/Admin/...)
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, code)
);
CREATE TRIGGER trg_roles_updated_at BEFORE UPDATE ON identity.roles
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TABLE identity.role_permissions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id             UUID NOT NULL REFERENCES identity.roles(id) ON DELETE CASCADE,
    permission_id       UUID NOT NULL REFERENCES identity.permissions(id) ON DELETE CASCADE,
    data_scope          VARCHAR(20) NOT NULL DEFAULT 'OWN'
                         CHECK (data_scope IN ('ALL','BRANCH','OWN','ASSIGNED')),
    UNIQUE (role_id, permission_id)
);
CREATE INDEX idx_role_permissions_role ON identity.role_permissions(role_id);

CREATE TABLE identity.user_roles (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES identity.users(id) ON DELETE CASCADE,
    role_id             UUID NOT NULL REFERENCES identity.roles(id) ON DELETE CASCADE,
    branch_id           UUID REFERENCES tenancy.branches(id), -- optional branch-restricted assignment
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, role_id, branch_id)
);
CREATE INDEX idx_user_roles_user ON identity.user_roles(user_id);

-- Personal access tokens (mobile apps / API key issuance for individual users)
CREATE TABLE identity.personal_access_tokens (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES identity.users(id) ON DELETE CASCADE,
    name                VARCHAR(100) NOT NULL,
    token_hash          VARCHAR(255) NOT NULL UNIQUE,
    abilities           JSONB NOT NULL DEFAULT '["*"]',
    last_used_at        TIMESTAMPTZ,
    expires_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_pat_user ON identity.personal_access_tokens(user_id);
