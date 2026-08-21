import { useEffect, useState } from "react";
import { api } from "../lib/api";
import { mutate } from "../offline/repository";
import { PageHeader, DataTable, FormModal } from "../components/primitives";

export function Expenses() {
  const [page, setPage] = useState(null);
  const [creating, setCreating] = useState(false);
  const [heads, setHeads] = useState([]);
  const load = () => api.get("/expenses").then(setPage).catch(() => setPage({ data: [] }));
  useEffect(() => { load(); }, []);
  const columns = [
    { key: "entry_date", label: "Date", num: true },
    { key: "head", label: "Head", render: (r) => r.head?.name || "—" },
    { key: "description", label: "Description" },
    { key: "amount", label: "Amount", align: "right", num: true, render: (r) => `৳ ${Number(r.amount).toLocaleString()}` },
  ];
  return (
    <>
      <PageHeader title="Expenses" subtitle="Expense entries — auto-posted to the ledger" action={<button className="btn btn-primary" onClick={() => setCreating(true)}>+ Expense</button>} />
      <DataTable columns={columns} rows={page?.data || []} empty="No expenses recorded." />
      {creating && (
        <FormModal title="Add Expense" submitLabel="Save"
          fields={[
            { name: "head_id", label: "Account Head (UUID)", required: true },
            { name: "amount", label: "Amount", type: "number", required: true },
            { name: "entry_date", label: "Date", type: "date", required: true,
              default: new Date().toISOString().slice(0, 10) },
            { name: "description", label: "Description" },
          ]}
          onSubmit={(v) => mutate("CREATE_EXPENSE", { payload: v, optimistic: v })}
          onClose={(saved) => { setCreating(false); if (saved) load(); }} />
      )}
    </>
  );
}
