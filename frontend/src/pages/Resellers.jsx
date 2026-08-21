import { useEffect, useState } from "react";
import { api } from "../lib/api";
import { mutate } from "../offline/repository";
import { PageHeader, DataTable, StatusPill, FormModal } from "../components/primitives";

export function Resellers() {
  const [rows, setRows] = useState([]);
  const [creating, setCreating] = useState(false);
  const load = () => api.get("/resellers").then(setRows).catch(() => setRows([]));
  useEffect(() => { load(); }, []);
  const columns = [
    { key: "name", label: "Name", render: (r) => <strong>{r.name}</strong> },
    { key: "reseller_type", label: "Type", render: (r) => <span className="pill pill-info">{r.reseller_type}</span> },
    { key: "wallet_balance", label: "Wallet", align: "right", num: true, render: (r) => `৳ ${Number(r.wallet_balance).toLocaleString()}` },
    { key: "credit_limit", label: "Credit Limit", align: "right", num: true, render: (r) => `৳ ${Number(r.credit_limit).toLocaleString()}` },
    { key: "status", label: "Status", render: (r) => <StatusPill status={r.status} /> },
  ];
  return (
    <>
      <PageHeader title="Resellers" subtitle="Dealers, franchises, commission" action={<button className="btn btn-primary" onClick={() => setCreating(true)}>+ Reseller</button>} />
      <DataTable columns={columns} rows={rows} empty="No resellers yet." />
      {creating && (
        <FormModal title="New Reseller" submitLabel="Create"
          fields={[
            { name: "name", label: "Name", required: true },
            { name: "reseller_type", label: "Type", type: "select", required: true,
              options: ["franchise", "dealer", "reseller", "sub_reseller"], default: "reseller" },
            { name: "mobile", label: "Mobile" },
            { name: "email", label: "Email" },
            { name: "credit_limit", label: "Credit Limit", type: "number", default: 0 },
          ]}
          onSubmit={(v) => mutate("CREATE_RESELLER", { payload: v, optimistic: v })}
          onClose={(saved) => { setCreating(false); if (saved) load(); }} />
      )}
    </>
  );
}
