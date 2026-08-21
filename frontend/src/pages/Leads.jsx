import { useEffect, useState } from "react";
import { api } from "../lib/api";
import { mutate } from "../offline/repository";
import { PageHeader, DataTable, StatusPill, FormModal } from "../components/primitives";

export function Leads() {
  const [page, setPage] = useState(null);
  const [creating, setCreating] = useState(false);
  const [converting, setConverting] = useState(null);
  const load = () => api.get("/leads").then(setPage).catch(() => setPage({ data: [] }));
  useEffect(() => { load(); }, []);
  const columns = [
    { key: "full_name", label: "Name", render: (r) => <strong>{r.full_name}</strong> },
    { key: "mobile", label: "Mobile", num: true },
    { key: "status", label: "Status", render: (r) => <StatusPill status={r.status} /> },
    { key: "actions", label: "", align: "right", render: (r) => r.status !== "converted" && (
      <button className="btn btn-primary" style={{ padding: "4px 12px", fontSize: 12 }} onClick={() => setConverting(r)}>Convert</button>) },
  ];
  return (
    <>
      <PageHeader title="Leads" subtitle="Pre-sale pipeline" action={<button className="btn btn-primary" onClick={() => setCreating(true)}>+ New Lead</button>} />
      <DataTable columns={columns} rows={page?.data || []} empty="No leads yet." />
      {creating && (
        <FormModal title="New Lead" submitLabel="Create"
          fields={[
            { name: "full_name", label: "Full Name", required: true },
            { name: "mobile", label: "Mobile", required: true },
            { name: "email", label: "Email" },
            { name: "address", label: "Address" },
          ]}
          onSubmit={(v) => mutate("CREATE_LEAD", { payload: v, optimistic: v })}
          onClose={(saved) => { setCreating(false); if (saved) load(); }} />
      )}
      {converting && (
        <FormModal title={`Convert Lead — ${converting.full_name}`} submitLabel="Convert to Customer"
          fields={[
            { name: "package_id", label: "Package (UUID)", required: true },
            { name: "zone_id", label: "Zone (UUID)", required: true },
            { name: "billing_person_id", label: "Billing Person (UUID)", required: true },
            { name: "router_id", label: "MikroTik Router (UUID)", required: true },
            { name: "pppoe_username", label: "PPPoE Username", required: true },
            { name: "pppoe_secret_password", label: "PPPoE Password", required: true },
            { name: "monthly_bill", label: "Monthly Bill", type: "number", required: true },
            { name: "disconnect_day", label: "Disconnect Day", type: "number", required: true, default: 5 },
          ]}
          onSubmit={(v) => api.post(`/leads/${converting.id}/convert`, v)}
          onClose={(saved) => { setConverting(null); if (saved) load(); }} />
      )}
    </>
  );
}
