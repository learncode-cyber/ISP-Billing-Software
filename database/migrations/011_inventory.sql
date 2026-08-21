-- ============================================================
-- 011_inventory.sql — inventory domain (Blueprint Section 17)
-- Preserves verified Stock, Product/Category, Supplier, Purchase, Sales,
-- Customer/Supplier Returns exactly; adds Multi-Warehouse, Serial/IMEI
-- tracking, Stock Transfer/Adjustment, and — closing the audit's
-- explicitly-flagged gap — a real FK linking sold/assigned hardware to
-- isp.customer_services (ONU/router assignment).
-- ============================================================

CREATE TABLE inventory.warehouses (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    branch_id            UUID REFERENCES tenancy.branches(id),
    name                  VARCHAR(150) NOT NULL,
    is_default              BOOLEAN NOT NULL DEFAULT false,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, name)
);

CREATE TABLE inventory.product_categories (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(150) NOT NULL,        -- audit: 'onu','splitar','fiber'
    UNIQUE (tenant_id, name)
);

CREATE TABLE inventory.products (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    category_id           UUID REFERENCES inventory.product_categories(id),
    name                    VARCHAR(255) NOT NULL,       -- audit: 'onu', SKU 'epon onu'
    sku                       VARCHAR(100),
    unit                        VARCHAR(30) NOT NULL DEFAULT 'piece',
    is_serialized                 BOOLEAN NOT NULL DEFAULT false, -- true for ONU/router-class hardware
    low_stock_threshold              INT NOT NULL DEFAULT 5,
    created_at                         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                         TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at                         TIMESTAMPTZ
);
CREATE TRIGGER trg_products_updated_at BEFORE UPDATE ON inventory.products
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();

CREATE TABLE inventory.suppliers (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    name                VARCHAR(255) NOT NULL,
    contact_phone         VARCHAR(30),
    contact_email           CITEXT,
    address                    TEXT,
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---- Stock (per warehouse per product, aggregate quantity) ----
CREATE TABLE inventory.stock_levels (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    warehouse_id          UUID NOT NULL REFERENCES inventory.warehouses(id) ON DELETE CASCADE,
    product_id              UUID NOT NULL REFERENCES inventory.products(id) ON DELETE CASCADE,
    quantity                  INT NOT NULL DEFAULT 0,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (warehouse_id, product_id)
);

-- ---- Serialized units (ONU/router individual device tracking) ----
CREATE TABLE inventory.stock_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    product_id            UUID NOT NULL REFERENCES inventory.products(id),
    warehouse_id             UUID REFERENCES inventory.warehouses(id),
    serial_number               VARCHAR(150),
    imei                           VARCHAR(50),
    status                           VARCHAR(20) NOT NULL DEFAULT 'in_stock'
                                      CHECK (status IN ('in_stock','assigned','sold','returned','defective')),
    customer_service_id                UUID REFERENCES isp.customer_services(id), -- closes audit's flagged gap
    purchase_item_id                     UUID,   -- FK added after purchases table below
    created_at                             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                             TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, serial_number)
);
CREATE TRIGGER trg_stock_items_updated_at BEFORE UPDATE ON inventory.stock_items
    FOR EACH ROW EXECUTE FUNCTION platform.set_updated_at();
CREATE INDEX idx_stock_items_customer_service ON inventory.stock_items(customer_service_id);
CREATE INDEX idx_stock_items_status ON inventory.stock_items(tenant_id, status);

-- ---- Purchase (audit: "Add Purchase" form) ----
CREATE TABLE inventory.purchases (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    supplier_id           UUID NOT NULL REFERENCES inventory.suppliers(id),
    warehouse_id            UUID NOT NULL REFERENCES inventory.warehouses(id),
    purchase_no                VARCHAR(50) NOT NULL,
    total_amount                  NUMERIC(14,2) NOT NULL DEFAULT 0,
    status                           VARCHAR(20) NOT NULL DEFAULT 'received' CHECK (status IN ('ordered','received','cancelled')),
    purchased_at                       TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                            UUID REFERENCES identity.users(id),
    UNIQUE (tenant_id, purchase_no)
);

CREATE TABLE inventory.purchase_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    purchase_id           UUID NOT NULL REFERENCES inventory.purchases(id) ON DELETE CASCADE,
    product_id              UUID NOT NULL REFERENCES inventory.products(id),
    quantity                  INT NOT NULL,
    unit_cost                   NUMERIC(12,2) NOT NULL
);
ALTER TABLE inventory.stock_items
    ADD CONSTRAINT fk_stock_items_purchase_item
    FOREIGN KEY (purchase_item_id) REFERENCES inventory.purchase_items(id);

-- ---- Sale (audit: "Add Sale" form — Model No/Serial No/Expire Date columns
-- implying serialized tracking, exactly what stock_items above provides) ----
CREATE TABLE inventory.sales (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    customer_id           UUID REFERENCES isp.customers(id),   -- nullable: not every sale is to a subscriber
    sale_no                 VARCHAR(50) NOT NULL,
    total_amount               NUMERIC(14,2) NOT NULL DEFAULT 0,
    sold_at                       TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by                       UUID REFERENCES identity.users(id),
    UNIQUE (tenant_id, sale_no)
);

CREATE TABLE inventory.sale_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    sale_id                UUID NOT NULL REFERENCES inventory.sales(id) ON DELETE CASCADE,
    stock_item_id             UUID REFERENCES inventory.stock_items(id),  -- for serialized products
    product_id                  UUID NOT NULL REFERENCES inventory.products(id),
    quantity                       INT NOT NULL DEFAULT 1,
    unit_price                       NUMERIC(12,2) NOT NULL,
    expire_date                        DATE   -- audit-verified column on the Sale form
);

-- ---- Returns (audit: Customer Return / Supplier Return, both with Reason/Entry-By) ----
CREATE TABLE inventory.customer_returns (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    sale_item_id           UUID NOT NULL REFERENCES inventory.sale_items(id),
    reason                    TEXT,
    entry_by                    UUID REFERENCES identity.users(id),
    returned_at                   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE inventory.supplier_returns (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    purchase_item_id       UUID NOT NULL REFERENCES inventory.purchase_items(id),
    reason                    TEXT,
    entry_by                    UUID REFERENCES identity.users(id),
    returned_at                   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---- Stock Transfer / Adjustment [NEW] ----
CREATE TABLE inventory.stock_transfers (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    from_warehouse_id     UUID NOT NULL REFERENCES inventory.warehouses(id),
    to_warehouse_id         UUID NOT NULL REFERENCES inventory.warehouses(id),
    product_id                 UUID NOT NULL REFERENCES inventory.products(id),
    quantity                      INT NOT NULL,
    transferred_by                  UUID REFERENCES identity.users(id),
    transferred_at                     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (from_warehouse_id <> to_warehouse_id)
);

CREATE TABLE inventory.stock_adjustments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID NOT NULL REFERENCES tenancy.tenants(id) ON DELETE CASCADE,
    warehouse_id          UUID NOT NULL REFERENCES inventory.warehouses(id),
    product_id              UUID NOT NULL REFERENCES inventory.products(id),
    quantity_delta             INT NOT NULL,     -- signed: +found / -damaged/lost
    reason                        TEXT,
    adjusted_by                     UUID REFERENCES identity.users(id),
    adjusted_at                        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_stock_levels_tenant ON inventory.stock_levels(tenant_id, product_id);
CREATE INDEX idx_purchases_tenant ON inventory.purchases(tenant_id, purchased_at DESC);
CREATE INDEX idx_sales_tenant ON inventory.sales(tenant_id, sold_at DESC);
CREATE UNIQUE INDEX idx_low_stock_lookup ON inventory.products(tenant_id, low_stock_threshold);

-- ---- RLS (applied uniformly to every table above) ----
DO $$
DECLARE t TEXT;
BEGIN
    FOR t IN SELECT unnest(ARRAY[
        'warehouses','product_categories','products','suppliers','stock_levels',
        'stock_items','purchases','purchase_items','sales','sale_items',
        'customer_returns','supplier_returns','stock_transfers','stock_adjustments'
    ]) LOOP
        EXECUTE format('ALTER TABLE inventory.%I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('ALTER TABLE inventory.%I FORCE ROW LEVEL SECURITY', t);
        EXECUTE format('CREATE POLICY tenant_isolation ON inventory.%I USING (tenant_id = platform.current_tenant_id())', t);
    END LOOP;
END $$;
