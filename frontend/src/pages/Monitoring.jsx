import { useEffect, useState } from "react";
import { api } from "../lib/api";
import { PageHeader, DataTable, StatusPill } from "../components/primitives";

export function Monitoring() {
  const [alerts, setAlerts] = useState(null);
  const load = () => api.get("/network/alerts").then((r) => setAlerts(r.data || [])).catch(() => setAlerts([]));
  useEffect(() => { load(); }, []);
  const columns = [
    { key: "severity", label: "Severity", render: (r) => <StatusPill status={r.severity} /> },
    { key: "alert_type", label: "Type" },
    { key: "message", label: "Message" },
    { key: "status", label: "Status", render: (r) => <StatusPill status={r.status} /> },
    { key: "actions", label: "", align: "right", render: (r) => r.status === "open" && (
      <button className="btn btn-ghost" style={{ padding: "4px 10px", fontSize: 12 }}
        onClick={() => api.post(`/network/alerts/${r.id}/acknowledge`).then(load)}>Acknowledge</button>) },
  ];
  return (
    <>
      <PageHeader title="Network Monitoring" subtitle="Uptime and alerts" action={<button className="btn btn-ghost" onClick={load}>Refresh</button>} />
      <DataTable columns={columns} rows={alerts || []} empty="No active alerts — all monitored targets healthy." />
    </>
  );
}
