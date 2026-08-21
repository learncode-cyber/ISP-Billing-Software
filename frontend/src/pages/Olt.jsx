import { useEffect, useState } from "react";
import { api } from "../lib/api";
import { PageHeader, DataTable, StatusPill, FormModal } from "../components/primitives";

export function Olt() {
  const [devices, setDevices] = useState([]);
  const [creating, setCreating] = useState(false);
  const load = () => api.get("/network/olt-devices").then(setDevices).catch(() => setDevices([]));
  useEffect(() => { load(); }, []);
  const columns = [
    { key: "device_name", label: "Device", render: (r) => <strong>{r.device_name}</strong> },
    { key: "device_type", label: "Type", render: (r) => <span className="pill pill-info">{r.device_type}</span> },
    { key: "device_ip", label: "IP", num: true },
    { key: "connection_status", label: "Status", render: (r) => <StatusPill status={r.connection_status} /> },
    { key: "actions", label: "", align: "right", render: () => (
      <div style={{ display: "flex", gap: 6, justifyContent: "flex-end" }}>
        <button className="btn btn-ghost" style={{ padding: "4px 10px", fontSize: 12 }}
          onClick={() => api.post(`/network/olt-devices/${r.id}/check-connection`).then((x) => { alert(x.message || (x.reachable ? "Reachable" : "Unreachable")); load(); })}>Check</button>
        <button className="btn btn-ghost" style={{ padding: "4px 10px", fontSize: 12 }}
          onClick={() => api.post(`/network/olt-devices/${r.id}/discover-onus`).then(() => alert("ONU discovery queued"))}>Discover ONUs</button>
      </div>) },
  ];
  return (
    <>
      <PageHeader title="OLT / GPON" subtitle="Optical line terminals and ONUs"
        action={<button className="btn btn-primary" onClick={() => setCreating(true)}>+ Register OLT</button>} />
      <DataTable columns={columns} rows={devices} empty="No OLT devices registered. Add BDCOM / V-SOL / ZTE / Huawei / Fiberhome." />
      {creating && (
        <FormModal
          title="Register OLT Device"
          submitLabel="Register"
          fields={[
            { name: "device_name", label: "Device Name", required: true },
            { name: "device_type", label: "Device Type", type: "select", required: true,
              options: ["bdcom", "v-sol", "zte", "huawei", "fiberhome"] },
            { name: "device_ip", label: "Device IP", required: true },
            { name: "login_username", label: "Login Username", required: true },
            { name: "password", label: "Password", required: true },
            { name: "snmp_port", label: "SNMP Port", type: "number", default: 161 },
            { name: "snmp_community", label: "SNMP Community", default: "public" },
            { name: "telnet_port", label: "Telnet Port", type: "number" },
          ]}
          onSubmit={(v) => api.post("/network/olt-devices", v)}
          onClose={(saved) => { setCreating(false); if (saved) load(); }}
        />
      )}
    </>
  );
}
