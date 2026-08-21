import { useEffect, useState } from "react";
import { repo, mutate } from "../offline/repository";
import { PageHeader, DataTable, StatusPill, StatCard, StatGrid, FormModal } from "../components/primitives";

export function Tickets() {
  const [res, setRes] = useState(null);
  const [creating, setCreating] = useState(false);
  const load = () => repo.tickets()
    .then(({ rows }) => {
      const c = rows.reduce((acc, t) => ({ ...acc, [t.status]: (acc[t.status] || 0) + 1 }), {});
      setRes({ counters: c, data: { data: rows } });
    })
    .catch(() => setRes({ counters: {}, data: { data: [] } }));
  useEffect(() => { load(); }, []);
  const c = res?.counters || {};
  const columns = [
    { key: "ticket_no", label: "Ticket", num: true, render: (r) => <strong>{r.ticket_no}</strong> },
    { key: "priority", label: "Priority", render: (r) => <StatusPill status={r.priority} /> },
    { key: "note", label: "Note" },
    { key: "status", label: "Status", render: (r) => <StatusPill status={r.status} /> },
  ];
  return (
    <>
      <PageHeader title="Complaints" subtitle="Customer tickets" action={<button className="btn btn-primary" onClick={() => setCreating(true)}>+ New Complaint</button>} />
      <StatGrid min={130}>
        <StatCard label="Pending" value={c.pending || 0} tone="warn" />
        <StatCard label="Processing" value={c.processing || 0} tone="info" />
        <StatCard label="Solved" value={c.solved || 0} tone="ok" />
        <StatCard label="Not Solved" value={c.not_solved || 0} tone="danger" />
      </StatGrid>
      <DataTable columns={columns} rows={res?.data?.data || []} empty="No complaints logged." />
      {creating && (
        <FormModal title="New Complaint" submitLabel="Create"
          fields={[
            { name: "customer_id", label: "Customer (UUID)", required: true },
            { name: "priority", label: "Priority", type: "select", required: true,
              options: ["high", "medium", "low"], default: "medium" },
            { name: "note", label: "Note" },
          ]}
          onSubmit={(v) => mutate("CREATE_TICKET", { payload: v, optimistic: { ...v, ticket_no: "(pending)", status: "pending" } })}
          onClose={(saved) => { setCreating(false); if (saved) load(); }} />
      )}
    </>
  );
}
