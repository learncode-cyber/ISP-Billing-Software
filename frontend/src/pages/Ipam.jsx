// Ipam.jsx — IP Address Management UI.
// Subnets with live utilisation bars, allocation table, allocate/release
// actions, and "next free address" lookup. Conflicts are rejected by the
// database and surfaced here as inline errors rather than silent failure.

import { useEffect, useState } from "react";
import { api } from "../lib/api";
import { PageHeader, DataTable, StatusPill, FormModal } from "../components/primitives";
import { OfflineBanner } from "../components/SyncStatus";

export function Ipam() {
  const [tab, setTab] = useState("subnets");
  const [subnets, setSubnets] = useState([]);
  const [allocs, setAllocs] = useState([]);
  const [creatingSubnet, setCreatingSubnet] = useState(false);
  const [allocating, setAllocating] = useState(false);
  const [error, setError] = useState(null);

  const load = () => {
    api.get("/ipam/subnets").then(setSubnets).catch(() => setSubnets([]));
    api.get("/ipam/allocations").then((r) => setAllocs(r.data || [])).catch(() => setAllocs([]));
  };
  useEffect(() => { load(); }, []);

  const subnetCols = [
    { key: "name", label: "Subnet", render: (r) => <strong>{r.name}</strong> },
    { key: "cidr", label: "CIDR", num: true },
    { key: "used", label: "Utilisation", render: (r) => {
      const total = Number(r.total_addresses || 0);
      const used = Number(r.used_addresses || 0);
      const pct = total ? Math.round((used / total) * 100) : 0;
      return (
        <div style={{ minWidth: 120 }}>
          <div style={{ fontSize: 12, marginBottom: 3 }} className="num">{used}/{total || "—"} ({pct}%)</div>
          <div style={{ height: 6, background: "var(--border)", borderRadius: 999 }}>
            <div style={{ width: `${Math.min(pct, 100)}%`, height: "100%", borderRadius: 999,
              background: pct > 85 ? "var(--danger)" : pct > 60 ? "var(--warn)" : "var(--ok)" }} />
          </div>
        </div>
      );
    } },
    { key: "actions", label: "", align: "right", render: (r) => (
      <button className="btn btn-ghost" style={{ padding: "4px 10px", fontSize: 12 }}
        onClick={() => api.get(`/ipam/subnets/${r.subnet_id}/next-free`)
          .then((x) => alert(x.next_free ? `Next free: ${x.next_free}` : "Subnet is full"))
          .catch((e) => setError(e.message))}>
        Next free
      </button>
    ) },
  ];

  const allocCols = [
    { key: "ip_address", label: "IP Address", num: true, render: (r) => <strong className="num">{r.ip_address}</strong> },
    { key: "subnet_name", label: "Subnet" },
    { key: "hostname", label: "Hostname", render: (r) => r.hostname || "—" },
    { key: "status", label: "Status", render: (r) => <StatusPill status={r.status} /> },
    { key: "actions", label: "", align: "right", render: (r) => r.status !== "released" && (
      <button className="btn btn-ghost" style={{ padding: "4px 10px", fontSize: 12 }}
        onClick={() => api.post(`/ipam/allocations/${r.id}/release`).then(load)}>Release</button>
    ) },
  ];

  return (
    <>
      <PageHeader
        title="IP Management"
        subtitle="Subnets, pools and address allocation"
        action={
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <button className="btn btn-ghost" onClick={() => setCreatingSubnet(true)}>+ Subnet</button>
            <button className="btn btn-primary" onClick={() => setAllocating(true)}>+ Allocate IP</button>
          </div>
        }
      />
      <OfflineBanner />

      {error && (
        <div style={{ background: "var(--danger-bg)", color: "var(--danger)", padding: "9px 12px",
          borderRadius: 6, fontSize: 13, marginBottom: 12 }}>{error}</div>
      )}

      <div style={{ display: "flex", gap: 6, marginBottom: 16, borderBottom: "1px solid var(--border)", overflowX: "auto" }}>
        {[["subnets", "Subnets"], ["allocations", "Allocations"]].map(([k, label]) => (
          <button key={k} onClick={() => setTab(k)}
            className="tab-btn" aria-selected={tab === k}>
            {label}
          </button>
        ))}
      </div>

      {tab === "subnets"
        ? <DataTable columns={subnetCols} rows={subnets} rowKey="subnet_id"
            empty="No subnets defined. Add one to start allocating addresses." />
        : <DataTable columns={allocCols} rows={allocs} empty="No IP allocations yet." />}

      {creatingSubnet && (
        <FormModal title="Add Subnet" submitLabel="Create"
          fields={[
            { name: "name", label: "Name", required: true },
            { name: "cidr", label: "CIDR (e.g. 10.20.0.0/24)", required: true },
            { name: "gateway", label: "Gateway" },
            { name: "vlan_id", label: "VLAN ID", type: "number" },
            { name: "description", label: "Description" },
          ]}
          onSubmit={(v) => api.post("/ipam/subnets", v)}
          onClose={(saved) => { setCreatingSubnet(false); if (saved) load(); }} />
      )}

      {allocating && (
        <FormModal title="Allocate IP Address" submitLabel="Allocate"
          fields={[
            { name: "subnet_id", label: "Subnet", type: "select", required: true,
              options: subnets.map((s) => ({ value: s.subnet_id, label: `${s.name} (${s.cidr})` })) },
            { name: "ip_address", label: "IP Address", required: true },
            { name: "status", label: "Status", type: "select",
              options: ["allocated", "reserved", "quarantined"], default: "allocated" },
            { name: "hostname", label: "Hostname" },
            { name: "note", label: "Note" },
          ]}
          onSubmit={(v) => api.post("/ipam/allocations", v)}
          onClose={(saved) => { setAllocating(false); if (saved) load(); }} />
      )}
    </>
  );
}
