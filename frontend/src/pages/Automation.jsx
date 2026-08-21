import { useEffect, useState } from "react";
import { api } from "../lib/api";
import { PageHeader, DataTable, StatusPill, FormModal } from "../components/primitives";

export function Automation() {
  const [rules, setRules] = useState([]);
  const [creating, setCreating] = useState(false);
  const load = () => api.get("/automation-rules").then(setRules).catch(() => setRules([]));
  useEffect(() => { load(); }, []);
  const toggle = (rule) => api.patch(`/automation-rules/${rule.id}`, { is_active: !rule.is_active }).then(load);
  const columns = [
    { key: "name", label: "Rule", render: (r) => <strong>{r.name}</strong> },
    { key: "trigger_type", label: "Trigger", render: (r) => <code style={{ fontSize: 12 }}>{r.trigger_type}</code> },
    { key: "action_type", label: "Action", render: (r) => <code style={{ fontSize: 12 }}>{r.action_type}</code> },
    { key: "is_active", label: "Status", render: (r) => <StatusPill status={r.is_active ? "active" : "inactive"} /> },
    { key: "actions", label: "", align: "right", render: (r) => (
      <button className="btn btn-ghost" style={{ padding: "4px 10px", fontSize: 12 }} onClick={() => toggle(r)}>
        {r.is_active ? "Disable" : "Enable"}</button>) },
  ];
  return (
    <>
      <PageHeader title="Automation" subtitle="Trigger → Condition → Action rules" action={<button className="btn btn-primary" onClick={() => setCreating(true)}>+ New Rule</button>} />
      <DataTable columns={columns} rows={rules} empty="No automation rules." />
      {creating && (
        <FormModal title="New Automation Rule" submitLabel="Create"
          fields={[
            { name: "name", label: "Rule Name", required: true },
            { name: "description", label: "Description" },
            { name: "trigger_type", label: "Trigger", type: "select", required: true,
              options: ["schedule.daily", "event.payment_received", "event.customer_created",
                        "event.ticket_created", "event.onu_los", "event.target_down", "event.stock_low"] },
            { name: "action_type", label: "Action", type: "select", required: true,
              options: ["mikrotik.disconnect", "mikrotik.reconnect", "sms.send",
                        "ticket.create", "notification.send", "webhook.call"] },
          ]}
          onSubmit={(v) => api.post("/automation-rules", v)}
          onClose={(saved) => { setCreating(false); if (saved) load(); }} />
      )}
    </>
  );
}
