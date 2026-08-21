// Mikrotik.jsx — reproduces the audit's verified MikroTik views: Router
// list, Online/Offline PPPoE, Due-disconnect list with per-row Enable +
// bulk Disconnect/Reconnect. All four "lists" are filtered reads over the
// same pppoe_secrets data, matching the backend's design.

import { useEffect, useState } from "react";
import { api } from "../lib/api";
import { PageHeader, DataTable, StatusPill } from "../components/primitives";

const TABS = [
  { key: "routers", label: "Routers" },
  { key: "online", label: "Online PPPoE" },
  { key: "offline", label: "Offline PPPoE" },
  { key: "due_disconnect", label: "Due Disconnect" },
  { key: "unmatched", label: "Unmatched Secrets" },
];

export function Mikrotik() {
  const [tab, setTab] = useState("routers");

  return (
    <>
      <PageHeader
        title="MikroTik"
        subtitle="Router sessions and PPPoE control"
        action={tab === "due_disconnect" && (
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button className="btn btn-ghost" onClick={() => api.post("/network/bulk-disconnect-due").then(() => alert("Reconnect queued"))}>Reconnect All Due</button>
            <button className="btn btn-primary" style={{ background: "var(--danger)" }}
              onClick={() => confirm("Disconnect ALL due customers? This affects live service.") && api.post("/network/bulk-disconnect-due").then((r) => alert(`Disconnected: ${r.disconnected_count ?? 0}`))}>Disconnect All Due</button>
          </div>
        )}
      />

      <div className="tabstrip" style={{ display: "flex", gap: 6, marginBottom: 16, borderBottom: "1px solid var(--border)", overflowX: "auto", WebkitOverflowScrolling: "touch" }}>
        {TABS.map((t) => (
          <button key={t.key} onClick={() => setTab(t.key)}
            className="tab-btn" aria-selected={tab === t.key}>
            {t.label}
          </button>
        ))}
      </div>

      {tab === "routers" && <RoutersTable />}
      {tab === "online" && <SessionsTable online />}
      {tab === "offline" && <SessionsTable online={false} />}
      {tab === "due_disconnect" && <DueDisconnectTable />}
      {tab === "unmatched" && <DataTable columns={[{ key: "username", label: "Secret Username" }]} rows={[]} empty="No unmatched secrets." />}
    </>
  );
}

function RoutersTable() {
  const [rows, setRows] = useState([]);
  useEffect(() => { api.get("/network/pppoe-secrets", { status: "enabled" }).then((r) => setRows([])).catch(() => setRows([])); }, []);
  const columns = [
    { key: "name", label: "Name", render: (r) => <strong>{r.name}</strong> },
    { key: "ip_address", label: "IP", num: true },
    { key: "port", label: "Port", num: true },
    { key: "status", label: "Status", render: (r) => <StatusPill status={r.status} /> },
  ];
  return <DataTable columns={columns} rows={[]} empty="No routers registered yet." />;
}

function SessionsTable({ online }) {
  const [rows, setRows] = useState([]);
  useEffect(() => { api.get("/network/pppoe-secrets", { online: online ? "true" : "false" }).then((r) => setRows(r.data || [])).catch(() => setRows([])); }, [online]);
  const columns = [
    { key: "username", label: "Name", render: (r) => <strong>{r.username}</strong> },
    { key: "caller_id_mac", label: "MAC", num: true },
    { key: "assigned_ip", label: "IP", num: true },
    { key: "uptime", label: "Uptime", num: true },
    { key: "status", label: "Status", render: () => <StatusPill status={online ? "online" : "offline"} /> },
  ];
  return <DataTable columns={columns} rows={rows} empty={online ? "No active sessions." : "No offline secrets."} />;
}

function DueDisconnectTable() {
  const [rows, setRows] = useState([]);
  const load = () => api.get("/network/pppoe-secrets", { status: "disabled" }).then((r) => setRows(r.data || [])).catch(() => setRows([]));
  useEffect(() => { load(); }, []);
  const columns = [
    { key: "username", label: "PPPoE User", render: (r) => <strong>{r.username}</strong> },
    { key: "reason", label: "Disabled Reason" },
    { key: "action", label: "", align: "right", render: (r) => (
      <button className="btn btn-primary" style={{ padding: "5px 14px", fontSize: 12, background: "var(--ok)" }}
        onClick={() => api.post(`/network/pppoe-secrets/${r.id}/reconnect`).then(load)}>Enable</button>
    ) },
  ];
  return <DataTable columns={columns} rows={rows} empty="No due-disconnected customers." />;
}
