// Dashboard.jsx — preserves every verified dashboard card from the AS-IS
// audit: Total/Active/Inactive/Discontinue/Free customers, monthly new/
// inactive, Total Collected Bill. Reads GET /api/v1/dashboard (served
// from analytics materialized views).

import { useEffect, useState } from "react";
import { repo } from "../offline/repository";
import { PageHeader, StatCard, StatGrid } from "../components/primitives";

export function Dashboard() {
  const [data, setData] = useState(null);
  const [fromCache, setFromCache] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    repo.dashboard()
      .then(({ data: d, fromCache: c }) => { setData(d); setFromCache(c); })
      .catch((e) => setError(e.message));
  }, []);

  if (error) return <div className="card" style={{ padding: 24, color: "var(--danger)" }}>{error}</div>;
  if (!data) return <div style={{ color: "var(--ink-faint)" }}>Loading dashboard…</div>;

  const taka = (n) => "৳ " + Number(n || 0).toLocaleString("en-BD");

  return (
    <>
      <PageHeader title="Dashboard" subtitle={fromCache ? "Showing last synced data (offline)" : "Business overview at a glance"} />

      <StatGrid min={140}>
        <StatCard label="Total Customers" value={data.total_customers} tone="primary" />
        <StatCard label="Active" value={data.active_customers} tone="ok" />
        <StatCard label="Inactive" value={data.inactive_customers} tone="danger" />
        <StatCard label="Discontinued" value={data.discontinue_customers} tone="danger" />
        <StatCard label="Free" value={data.free_customers} tone="info" />
      </StatGrid>

      <StatGrid min={160}>
        <StatCard label="New This Month" value={data.monthly_new_customers} tone="ok" hint="Connections added this month" />
        <StatCard label="Inactive This Month" value={data.monthly_inactive_customers} tone="warn" />
        <StatCard label="Collected This Month" value={taka(data.total_collected_this_month)} tone="primary" hint="Bill collection to date" />
      </StatGrid>
    </>
  );
}
