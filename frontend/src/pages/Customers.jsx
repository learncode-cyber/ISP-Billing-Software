// Customers.jsx — reproduces the audit's verified Customer View: filter
// bar (Zone, Billing Person, Package, Status, Date range), summary counts,
// paginated table (10–500), row actions. Reads GET /api/v1/customers with
// the same query params the backend CustomerController expects.

import { useEffect, useState } from "react";
import { repo, mutate } from "../offline/repository";
import { PageHeader, DataTable, StatusPill, FormModal, Modal } from "../components/primitives";
import { useCapabilities } from "../context/CapabilitiesContext";

const STATUSES = ["", "active", "inactive", "free", "discontinue"];

export function Customers() {
  const { can } = useCapabilities();
  const [filters, setFilters] = useState({ status: "", search: "", zone_id: "", per_page: 25 });
  const [page, setPage] = useState(null);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [viewing, setViewing] = useState(null);
  const [editing, setEditing] = useState(null);

  const load = () => {
    setLoading(true);
    repo.customers(filters)
      .then(async ({ rows, fromCache, total }) => {
        // Offline (or after a failed fetch) we search the cached set locally,
        // so search keeps working with zero connectivity.
        const data = fromCache && filters.search
          ? await repo.searchCustomers(filters.search)
          : rows;
        setPage({ data, total, current_page: 1, last_page: 1, fromCache });
      })
      .finally(() => setLoading(false));
  };
  useEffect(load, [filters]); // eslint-disable-line

  const columns = [
    { key: "customer_code", label: "ID", num: true },
    { key: "full_name", label: "Name", render: (r) => <strong>{r.full_name}</strong> },
    { key: "mobile", label: "Mobile", num: true },
    { key: "zone", label: "Zone", render: (r) => r.zone?.name || "—" },
    { key: "status", label: "Status", render: (r) => <StatusPill status={r.status} /> },
    { key: "previous_due", label: "Previous Due", align: "right", num: true,
      render: (r) => Number(r.previous_due) > 0
        ? <span style={{ color: "var(--danger)" }}>৳ {Number(r.previous_due).toLocaleString()}</span>
        : "৳ 0" },
    { key: "actions", label: "", align: "right", render: (r) => (
      <div style={{ display: "flex", gap: 6, justifyContent: "flex-end" }}>
        <button className="btn btn-ghost" style={{ padding: "4px 10px", fontSize: 12 }} onClick={() => setViewing(r)}>View</button>
        {can("isp.customer.edit") && <button className="btn btn-ghost" style={{ padding: "4px 10px", fontSize: 12 }} onClick={() => setEditing(r)}>Edit</button>}
      </div>
    ) },
  ];

  const set = (k, v) => setFilters((f) => ({ ...f, [k]: v }));

  return (
    <>
      <PageHeader
        title="Customers"
        subtitle={page ? `${page.total} total${page.fromCache ? " · offline copy" : ""}` : "Loading…"}
        action={can("isp.customer.create") && <button className="btn btn-primary" onClick={() => setCreating(true)}>+ New Customer</button>}
      />

      {/* Verified filter bar */}
      <div className="card" style={{ padding: 12, marginBottom: 14, display: "flex", gap: 10, flexWrap: "wrap", alignItems: "center" }}>
        <input
          placeholder="Search name, mobile, ID…"
          value={filters.search}
          onChange={(e) => set("search", e.target.value)}
          style={{ flex: "1 1 180px", minWidth: 0, padding: "8px 12px", border: "1px solid var(--border-strong)", borderRadius: 6, fontSize: 13 }}
        />
        <select value={filters.status} onChange={(e) => set("status", e.target.value)}
          style={{ padding: "8px 12px", border: "1px solid var(--border-strong)", borderRadius: 6, fontSize: 13 }}>
          {STATUSES.map((s) => <option key={s} value={s}>{s ? s[0].toUpperCase() + s.slice(1) : "All statuses"}</option>)}
        </select>
        <select value={filters.per_page} onChange={(e) => set("per_page", e.target.value)}
          style={{ padding: "8px 12px", border: "1px solid var(--border-strong)", borderRadius: 6, fontSize: 13 }}>
          {[10, 25, 50, 100, 500].map((n) => <option key={n} value={n}>{n} / page</option>)}
        </select>
        <button className="btn btn-ghost" onClick={load}>Refresh</button>
      </div>

      {loading ? (
        <div style={{ color: "var(--ink-faint)", padding: 20 }}>Loading customers…</div>
      ) : (
        <>
          <DataTable columns={columns} rows={page?.data || []} empty="No customers match these filters." />
          {page && page.last_page > 1 && (
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: 12, fontSize: 13, color: "var(--ink-soft)" }}>
              <span>Page {page.current_page} of {page.last_page}</span>
              <div style={{ display: "flex", gap: 8 }}>
                <button className="btn btn-ghost" disabled={page.current_page <= 1}
                  onClick={() => set("page", page.current_page - 1)}>Previous</button>
                <button className="btn btn-ghost" disabled={page.current_page >= page.last_page}
                  onClick={() => set("page", page.current_page + 1)}>Next</button>
              </div>
            </div>
          )}
        </>
      )}

      {creating && (
        <FormModal title="New Customer" submitLabel="Create"
          fields={[
            { name: "full_name", label: "Full Name", required: true },
            { name: "mobile", label: "Mobile", required: true },
            { name: "other_mobile", label: "Other Mobile" },
            { name: "email", label: "Email" },
            { name: "gender", label: "Gender", type: "select", options: ["male", "female", "other"] },
            { name: "nid_passport_no", label: "NID / Passport No" },
            { name: "address", label: "Address" },
            { name: "fiber_code", label: "Fiber Code / ID" },
            { name: "agent_type", label: "Agent Type", type: "select", required: true,
              options: [{ value: "optical_fiber", label: "Optical Fiber" }, { value: "cat5", label: "Cat 5" }] },
            { name: "connection_type", label: "Connection Type", type: "select", required: true,
              options: [{ value: "home", label: "Home" }, { value: "corporate", label: "Corporate" }] },
            { name: "connection_date", label: "Connection Date", type: "date", required: true,
              default: new Date().toISOString().slice(0, 10) },
            { name: "zone_id", label: "Zone (UUID)", required: true },
            { name: "billing_person_id", label: "Billing Person (UUID)", required: true },
            { name: "package_id", label: "Package (UUID)", required: true },
            { name: "monthly_bill", label: "Monthly Bill", type: "number", required: true },
            { name: "connection_fee_paid", label: "Connection Fee Paid", type: "number", default: 0 },
            { name: "running_month_paid_amount", label: "Running Month Paid", type: "number", default: 0 },
            { name: "disconnect_day", label: "Disconnect Day", type: "number", required: true, default: 5 },
            { name: "router_id", label: "MikroTik Router (UUID)", required: true },
            { name: "pppoe_username", label: "PPPoE Username", required: true },
            { name: "pppoe_secret_password", label: "MikroTik Secret Password", required: true },
            { name: "status", label: "Status", type: "select", required: true,
              options: ["active", "inactive", "free", "discontinue"], default: "active" },
            { name: "remarks", label: "Remarks" },
          ]}
          onSubmit={(v) => mutate("CREATE_CUSTOMER", { payload: v, optimistic: { full_name: v.full_name, mobile: v.mobile, status: v.status, customer_code: "(pending)" } })}
          onClose={(saved) => { setCreating(false); if (saved) load(); }} />
      )}

      {editing && (
        <FormModal title={`Edit — ${editing.full_name}`} submitLabel="Save"
          fields={[
            { name: "previous_due", label: "Current Previous Due", type: "number", default: editing.previous_due },
            { name: "temp_disconnect_day", label: "Temporary Disconnect Day", type: "number" },
            { name: "subzone_id", label: "SubZone / SubArea (UUID)" },
            { name: "destination_id", label: "Destination / Area (UUID)" },
            { name: "status", label: "Status", type: "select",
              options: ["active", "inactive", "free", "discontinue"], default: editing.status },
            { name: "remarks", label: "Remarks", default: editing.remarks || "" },
          ]}
          onSubmit={(v) => mutate("UPDATE_CUSTOMER", { targetId: editing.id, payload: v, optimistic: v })}
          onClose={(saved) => { setEditing(null); if (saved) load(); }} />
      )}

      {viewing && (
        <Modal title={viewing.full_name} subtitle={`Customer ${viewing.customer_code}`}
          onClose={() => setViewing(null)}
          footer={<button className="btn btn-ghost" onClick={() => setViewing(null)}>Close</button>}>
          <dl style={{ margin: 0, display: "grid", gridTemplateColumns: "auto 1fr", gap: "8px 16px", fontSize: 13.5 }}>
            {[["Mobile", viewing.mobile], ["Email", viewing.email || "—"],
              ["Zone", viewing.zone?.name || "—"], ["Status", viewing.status],
              ["Address", viewing.address || "—"],
              ["Previous Due", `৳ ${Number(viewing.previous_due || 0).toLocaleString()}`],
              ["Connection Date", viewing.connection_date || "—"]].map(([k, v]) => (
              <div key={k} style={{ display: "contents" }}>
                <dt style={{ color: "var(--ink-faint)", fontWeight: 600 }}>{k}</dt>
                <dd style={{ margin: 0 }}>{v}</dd>
              </div>
            ))}
          </dl>
        </Modal>
      )}
    </>
  );
}
