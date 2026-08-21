// SyncConflicts.jsx — the review screen the spec requires: conflicts must
// never be silently resolved. When the server holds a newer revision than
// the one an offline edit was based on, the operation lands here and an
// authorised user chooses explicitly.

import { useEffect, useState } from "react";
import * as outbox from "../offline/outbox";
import { sync } from "../offline/syncEngine";
import { PageHeader, DataTable } from "../components/primitives";

export function SyncConflicts() {
  const [rows, setRows] = useState([]);
  const [pending, setPending] = useState([]);

  const load = async () => {
    setRows(await outbox.conflicts());
    setPending(await outbox.pending());
  };
  useEffect(() => { load(); }, []);

  const resolve = async (op, choice) => {
    await outbox.resolveConflict(op.id, choice);
    await load();
    sync();
  };

  const conflictCols = [
    { key: "op_type", label: "Operation", render: (r) => <strong>{r.op_type.replace(/_/g, " ")}</strong> },
    { key: "created_at", label: "Made", num: true, render: (r) => new Date(r.created_at).toLocaleString() },
    { key: "last_error", label: "Reason", render: (r) => <span style={{ color: "var(--warn)" }}>{r.last_error}</span> },
    { key: "actions", label: "", align: "right", render: (r) => (
      <div style={{ display: "flex", gap: 6, justifyContent: "flex-end", flexWrap: "wrap" }}>
        <button className="btn btn-ghost" style={{ padding: "4px 10px", fontSize: 12 }}
          onClick={() => resolve(r, "keep_server")}>Discard mine</button>
        <button className="btn btn-primary" style={{ padding: "4px 10px", fontSize: 12 }}
          onClick={() => resolve(r, "keep_mine")}>Re-apply mine</button>
      </div>
    ) },
  ];

  const pendingCols = [
    { key: "op_type", label: "Operation", render: (r) => r.op_type.replace(/_/g, " ") },
    { key: "created_at", label: "Queued", num: true, render: (r) => new Date(r.created_at).toLocaleString() },
    { key: "attempts", label: "Attempts", align: "right", num: true },
    { key: "status", label: "Status", render: (r) => (
      <span className={`pill pill-${r.status === "failed" ? "danger" : "warn"}`}>{r.status}</span>
    ) },
  ];

  return (
    <>
      <PageHeader
        title="Sync"
        subtitle="Pending changes and conflicts from offline work"
        action={<button className="btn btn-primary" onClick={() => sync().then(load)}>Sync now</button>}
      />

      <h3 style={{ fontSize: 14, margin: "0 0 8px", color: "var(--ink-soft)" }}>
        Conflicts ({rows.length})
      </h3>
      <DataTable columns={conflictCols} rows={rows}
        empty="No conflicts — every offline change applied cleanly." />

      <h3 style={{ fontSize: 14, margin: "22px 0 8px", color: "var(--ink-soft)" }}>
        Pending changes ({pending.length})
      </h3>
      <DataTable columns={pendingCols} rows={pending}
        empty="Nothing waiting to sync." />
    </>
  );
}
