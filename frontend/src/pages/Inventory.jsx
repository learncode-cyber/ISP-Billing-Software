import { useEffect, useState } from "react";
import { api } from "../lib/api";
import { repo, mutate } from "../offline/repository";
import { PageHeader, DataTable, FormModal } from "../components/primitives";

export function Inventory() {
  const [tab, setTab] = useState("products");
  const [products, setProducts] = useState([]);
  const [stock, setStock] = useState([]);
  const [creating, setCreating] = useState(false);
  const load = () => repo.products().then(({ rows }) => setProducts(rows)).catch(() => setProducts([]));
  useEffect(() => {
    repo.products().then(({ rows }) => setProducts(rows)).catch(() => setProducts([]));
    api.get("/inventory/stock").then(setStock).catch(() => setStock([]));
  }, []);
  const productCols = [
    { key: "name", label: "Product", render: (r) => <strong>{r.name}</strong> },
    { key: "sku", label: "SKU", num: true },
    { key: "unit", label: "Unit" },
    { key: "is_serialized", label: "Serialized", render: (r) => r.is_serialized ? "Yes" : "No" },
  ];
  const stockCols = [
    { key: "product", label: "Product", render: (r) => <strong>{r.product}</strong> },
    { key: "warehouse", label: "Warehouse" },
    { key: "quantity", label: "Qty", align: "right", num: true },
    { key: "is_low", label: "", render: (r) => r.is_low && <span className="pill pill-danger">Low</span> },
  ];
  return (
    <>
      <PageHeader title="Inventory" subtitle="Stock, products, hardware" action={<button className="btn btn-primary" onClick={() => setCreating(true)}>+ Product</button>} />
      <div className="tabstrip" style={{ display: "flex", gap: 6, marginBottom: 16, borderBottom: "1px solid var(--border)", overflowX: "auto" }}>
        {["products", "stock"].map((t) => (
          <button key={t} onClick={() => setTab(t)} className="tab-btn" aria-selected={tab === t}>{t}</button>
        ))}
      </div>
      {tab === "products"
        ? <DataTable columns={productCols} rows={products} empty="No products yet." />
        : <DataTable columns={stockCols} rows={stock} rowKey="product" empty="No stock recorded." />}
      {creating && (
        <FormModal title="Add Product" submitLabel="Create"
          fields={[
            { name: "name", label: "Product Name", required: true },
            { name: "sku", label: "SKU" },
            { name: "unit", label: "Unit", default: "piece" },
            { name: "is_serialized", label: "Serialized (ONU/Router)", type: "select",
              options: [{ value: "1", label: "Yes" }, { value: "0", label: "No" }], default: "0" },
            { name: "low_stock_threshold", label: "Low Stock Threshold", type: "number", default: 5 },
          ]}
          onSubmit={(v) => mutate("UPDATE_INVENTORY", { payload: { ...v, is_serialized: v.is_serialized === "1" }, optimistic: { ...v, is_serialized: v.is_serialized === "1" } })}
          onClose={(saved) => { setCreating(false); if (saved) load(); }} />
      )}
    </>
  );
}
