// PlatformApp.jsx — AR Qudrix Super Admin console.
//
// Separate document, separate route namespace (/api/v1/platform/*), and a
// server-side guard that rejects any account carrying a tenant_id. A
// tenant administrator cannot reach this console no matter what role or
// permissions they hold inside their own tenant.

import { useEffect, useState } from "react";
import { api } from "../lib/api";
import { PageHeader, DataTable, StatusPill, StatCard, StatGrid, Modal, FormModal } from "../components/primitives";
import { Icon } from "../components/Icon";

const TABS = [
  { key: "overview", label: "Overview", icon: "grid" },
  { key: "tenants", label: "Tenants", icon: "network" },
  { key: "plans", label: "Plans & Features", icon: "zap" },
  { key: "news", label: "BTRC News", icon: "newspaper" },
  { key: "audit", label: "Platform Audit", icon: "activity" },
];

export function PlatformApp() {
  const [tab, setTab] = useState("overview");
  const [denied, setDenied] = useState(false);

  useEffect(() => {
    // Probe the guard immediately: a tenant account landing here should be
    // told plainly rather than shown an empty console.
    api.get("/platform/stats").catch((e) => {
      if (e.code === "FORBIDDEN") setDenied(true);
    });
  }, []);

  if (denied) {
    return (
      <div style={{ minHeight: "100vh", display: "grid", placeItems: "center", padding: 20 }}>
        <div className="card" style={{ padding: 32, maxWidth: 420, textAlign: "center" }}>
          <div style={{ color: "var(--danger)", marginBottom: 10 }}><Icon name="zap" size={28} /></div>
          <h2 style={{ margin: "0 0 8px", fontSize: 18 }}>Platform access only</h2>
          <p style={{ margin: 0, color: "var(--ink-soft)", fontSize: 13.5 }}>
            This console is restricted to AR Qudrix platform staff. Tenant accounts
            cannot access platform administration.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg-canvas)" }}>
      <header style={{
        background: "#0b1220", color: "var(--ink-invert)", padding: "12px var(--page-pad)",
        display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12, flexWrap: "wrap",
      }}>
        <div>
          <div style={{ fontWeight: 700, fontSize: 15 }}>AR Qudrix</div>
          <div style={{ fontSize: 11, color: "#f59e0b", textTransform: "uppercase", letterSpacing: ".06em", fontWeight: 700 }}>
            Platform Console
          </div>
        </div>
        <button className="btn btn-ghost" style={{ color: "#cbd5e1", borderColor: "#334155" }}
          onClick={() => { localStorage.removeItem("arq_token"); location.href = "/login"; }}>
          Sign out
        </button>
      </header>

      <div style={{ display: "flex", gap: 4, padding: "0 var(--page-pad)", background: "#0b1220",
        overflowX: "auto", borderBottom: "1px solid #1e293b" }}>
        {TABS.map((t) => (
          <button key={t.key} onClick={() => setTab(t.key)}
            style={{
              display: "flex", alignItems: "center", gap: 7, padding: "10px 14px", minHeight: 44,
              border: "none", background: "none", cursor: "pointer", whiteSpace: "nowrap", flexShrink: 0,
              fontSize: 13.5, fontWeight: 600,
              color: tab === t.key ? "#fff" : "#94a3b8",
              borderBottom: tab === t.key ? "2px solid #f59e0b" : "2px solid transparent",
            }}>
            <Icon name={t.icon} size={15} />{t.label}
          </button>
        ))}
      </div>

      <main style={{ padding: "20px var(--page-pad)", maxWidth: 1200, margin: "0 auto" }}>
        {tab === "overview" && <Overview />}
        {tab === "tenants" && <Tenants />}
        {tab === "plans" && <Plans />}
        {tab === "news" && <NewsModeration />}
        {tab === "audit" && <PlatformAudit />}
      </main>
    </div>
  );
}

function Overview() {
  const [s, setS] = useState(null);
  useEffect(() => { api.get("/platform/stats").then(setS).catch(() => setS(null)); }, []);
  if (!s) return <div style={{ color: "var(--ink-faint)" }}>Loading platform statistics…</div>;

  const taka = (v) => "৳ " + Number(v || 0).toLocaleString();

  return (
    <>
      <PageHeader title="Platform Overview" subtitle="Across all tenants" />
      <StatGrid min={150}>
        <StatCard label="Total Tenants" value={s.tenants_total} tone="primary" />
        <StatCard label="Active" value={s.tenants_active} tone="ok" />
        <StatCard label="Trial" value={s.tenants_trial} tone="info" />
        <StatCard label="Suspended" value={s.tenants_suspended} tone="danger" />
      </StatGrid>
      <StatGrid min={200}>
        <StatCard label="Subscribers (all tenants)" value={Number(s.customers_total).toLocaleString()} />
        <StatCard label="MRR estimate" value={taka(s.mrr_estimate)} tone="ok"
          hint="Sum of active + trial plan prices" />
      </StatGrid>

      <h3 style={{ fontSize: 14, marginTop: 20 }}>Plan distribution</h3>
      <DataTable
        columns={[
          { key: "code", label: "Plan", render: (r) => <strong>{r.code}</strong> },
          { key: "tenants", label: "Tenants", align: "right", num: true },
        ]}
        rows={(s.plan_distribution || []).map((p, i) => ({ ...p, id: p.code || i }))}
        empty="No subscriptions yet."
      />
    </>
  );
}

function Tenants() {
  const [page, setPage] = useState(null);
  const [creating, setCreating] = useState(false);
  const [detail, setDetail] = useState(null);
  const [search, setSearch] = useState("");

  const load = () => api.get("/platform/tenants", { search }).then(setPage).catch(() => setPage({ data: [] }));
  useEffect(() => { load(); }, [search]); // eslint-disable-line

  const cols = [
    { key: "name", label: "Tenant", render: (r) => <strong>{r.name}</strong> },
    { key: "slug", label: "Slug", num: true },
    { key: "plan_name", label: "Plan", render: (r) => r.plan_name || "—" },
    { key: "status", label: "Status", render: (r) => <StatusPill status={r.status} /> },
    { key: "act", label: "", align: "right", render: (r) => (
      <button className="btn btn-ghost" style={{ padding: "4px 10px", fontSize: 12 }}
        onClick={() => api.get(`/platform/tenants/${r.id}`).then(setDetail)}>Manage</button>
    ) },
  ];

  return (
    <>
      <PageHeader title="Tenants" subtitle={page ? `${page.total} total` : "Loading…"}
        action={<button className="btn btn-primary" onClick={() => setCreating(true)}>+ New Tenant</button>} />

      <div className="card" style={{ padding: 12, marginBottom: 14 }}>
        <input placeholder="Search tenants…" value={search} onChange={(e) => setSearch(e.target.value)}
          style={{ width: "100%", padding: "8px 12px", border: "1px solid var(--border-strong)",
            borderRadius: 6, fontSize: 13 }} />
      </div>

      <DataTable columns={cols} rows={page?.data || []} empty="No tenants yet." />

      {creating && (
        <FormModal title="Provision New Tenant" submitLabel="Create tenant"
          fields={[
            { name: "name", label: "ISP / Company name", required: true },
            { name: "business_type", label: "Business type", type: "select",
              options: ["isp", "wisp", "ftth", "cable_tv", "ip_phone", "cctv", "corporate_network"], default: "isp" },
            { name: "plan", label: "Plan", type: "select", required: true,
              options: ["starter", "professional", "business", "enterprise"], default: "starter" },
            { name: "owner_name", label: "Owner name", required: true },
            { name: "owner_username", label: "Owner username", required: true, default: "owner" },
            { name: "owner_email", label: "Owner email" },
            { name: "owner_password", label: "Owner password (min 8)", required: true },
          ]}
          onSubmit={(v) => api.post("/platform/tenants", v)}
          onClose={(saved) => { setCreating(false); if (saved) load(); }} />
      )}

      {detail && <TenantDetail detail={detail} onClose={() => { setDetail(null); load(); }} />}
    </>
  );
}

function TenantDetail({ detail, onClose }) {
  const t = detail.tenant || detail.t;
  const [busy, setBusy] = useState(false);
  const [overriding, setOverriding] = useState(false);
  const [features, setFeatures] = useState([]);

  useEffect(() => { api.get("/platform/features").then(setFeatures).catch(() => setFeatures([])); }, []);

  const setStatus = async (status) => {
    setBusy(true);
    try { await api.patch(`/platform/tenants/${t.id}/status`, { status }); onClose(); }
    finally { setBusy(false); }
  };

  const u = detail.usage || {};

  return (
    <Modal title={t.name} subtitle={`${t.slug} · ${t.business_type}`} onClose={onClose}
      footer={<>
        <button className="btn btn-ghost" onClick={onClose}>Close</button>
        {t.status !== "suspended" && (
          <button className="btn btn-ghost" style={{ color: "var(--danger)", borderColor: "var(--danger)" }}
            disabled={busy} onClick={() => setStatus("suspended")}>Suspend</button>
        )}
        {t.status !== "active" && (
          <button className="btn btn-primary" disabled={busy} onClick={() => setStatus("active")}>Activate</button>
        )}
      </>}>

      <Section title="Usage">
        <dl style={{ margin: 0, display: "grid", gridTemplateColumns: "1fr auto", gap: "6px 12px", fontSize: 13.5 }}>
          {[["Customers", u.customers], ["Users", u.users], ["Branches", u.branches],
            ["Routers", u.routers], ["OLT devices", u.olts], ["Invoices this month", u.invoices_this_month]]
            .map(([k, v]) => (
              <div key={k} style={{ display: "contents" }}>
                <dt style={{ color: "var(--ink-faint)" }}>{k}</dt>
                <dd className="num" style={{ margin: 0, textAlign: "right", fontWeight: 600 }}>{v ?? 0}</dd>
              </div>
            ))}
        </dl>
      </Section>

      <Section title="Subscription">
        <div style={{ fontSize: 13.5 }}>
          <strong>{detail.subscription?.plan_name || "No plan"}</strong>
          {detail.subscription && <> · <StatusPill status={detail.subscription.status} /></>}
        </div>
      </Section>

      <Section title="Feature overrides">
        {(detail.overrides || []).length === 0
          ? <div style={{ fontSize: 13, color: "var(--ink-faint)" }}>No overrides — plan entitlements apply.</div>
          : (detail.overrides || []).map((o) => (
              <div key={o.id} style={{ display: "flex", justifyContent: "space-between",
                alignItems: "center", gap: 10, fontSize: 13, padding: "5px 0" }}>
                <span><code style={{ fontSize: 12 }}>{o.key}</code></span>
                <span style={{ display: "flex", gap: 8, alignItems: "center" }}>
                  <StatusPill status={o.is_enabled ? "active" : "inactive"} />
                  <button className="btn btn-ghost" style={{ padding: "2px 8px", fontSize: 11 }}
                    onClick={() => api.del(`/platform/tenants/${t.id}/overrides/${o.id}`).then(onClose)}>
                    Remove
                  </button>
                </span>
              </div>
            ))}
        <button className="btn btn-ghost" style={{ marginTop: 10, width: "100%" }}
          onClick={() => setOverriding(true)}>+ Add override</button>
      </Section>

      {overriding && (
        <FormModal title="Feature override" submitLabel="Save override"
          fields={[
            { name: "feature_key", label: "Feature", type: "select", required: true,
              options: features.map((f) => ({ value: f.key, label: `${f.name} (${f.key})` })) },
            { name: "is_enabled", label: "Enabled", type: "select", required: true,
              options: [{ value: "1", label: "Enabled" }, { value: "0", label: "Disabled" }], default: "1" },
            { name: "reason", label: "Reason (shown in audit)" },
          ]}
          onSubmit={(v) => api.post(`/platform/tenants/${t.id}/overrides`, {
            ...v, is_enabled: v.is_enabled === "1",
          })}
          onClose={(saved) => { setOverriding(false); if (saved) onClose(); }} />
      )}
    </Modal>
  );
}

function Plans() {
  const [plans, setPlans] = useState([]);
  useEffect(() => { api.get("/platform/plans").then(setPlans).catch(() => setPlans([])); }, []);

  return (
    <>
      <PageHeader title="Plans & Features" subtitle="Subscription catalogue" />
      {plans.map((p) => (
        <div key={p.id} className="card" style={{ padding: 16, marginBottom: 12 }}>
          <div style={{ display: "flex", justifyContent: "space-between", flexWrap: "wrap", gap: 8 }}>
            <div>
              <strong style={{ fontSize: 15 }}>{p.name}</strong>
              <code style={{ fontSize: 12, color: "var(--ink-faint)", marginLeft: 8 }}>{p.code}</code>
            </div>
            <div className="num" style={{ fontWeight: 700 }}>
              ৳ {Number(p.price_amount).toLocaleString()} / {p.billing_cycle}
            </div>
          </div>
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginTop: 10 }}>
            {(p.features || []).map((f) => (
              <span key={f} className="pill pill-ok" style={{ fontSize: 11 }}>{f}</span>
            ))}
            {(p.features || []).length === 0 && (
              <span style={{ fontSize: 12.5, color: "var(--ink-faint)" }}>No features assigned.</span>
            )}
          </div>
        </div>
      ))}
    </>
  );
}

function NewsModeration() {
  const [candidates, setCandidates] = useState([]);
  const [publishing, setPublishing] = useState(null);

  const load = () => api.get("/platform/news/candidates").then(setCandidates).catch(() => setCandidates([]));
  useEffect(() => { load(); }, []);

  return (
    <>
      <PageHeader title="BTRC News Moderation"
        subtitle="Scraped candidates require approval before tenants see them"
        action={<button className="btn btn-primary" onClick={() => setPublishing({})}>+ Publish manually</button>} />

      <DataTable
        columns={[
          { key: "title", label: "Headline", render: (r) => <strong>{r.title}</strong> },
          { key: "scraped_at", label: "Found", num: true,
            render: (r) => new Date(r.scraped_at).toLocaleDateString() },
          { key: "act", label: "", align: "right", render: (r) => (
            <button className="btn btn-primary" style={{ padding: "4px 12px", fontSize: 12 }}
              onClick={() => setPublishing(r)}>Review</button>
          ) },
        ]}
        rows={candidates}
        empty="No pending candidates. Nothing reaches tenants until it is approved here."
      />

      {publishing && (
        <FormModal title="Publish regulatory news" submitLabel="Publish to all tenants"
          fields={[
            { name: "title", label: "Headline", required: true, default: publishing.title || "" },
            { name: "body", label: "Summary", default: publishing.raw_excerpt || "" },
            { name: "source_url", label: "Source URL", default: publishing.source_url || "" },
            { name: "category", label: "Category", type: "select",
              options: ["directive", "notice", "license", "tariff", "spectrum"], default: "notice" },
          ]}
          onSubmit={(v) => api.post("/platform/news/publish", { ...v, candidate_id: publishing.id || null })}
          onClose={(saved) => { setPublishing(null); if (saved) load(); }} />
      )}
    </>
  );
}

function PlatformAudit() {
  const [page, setPage] = useState(null);
  useEffect(() => { api.get("/platform/audit").then(setPage).catch(() => setPage({ data: [] })); }, []);

  return (
    <>
      <PageHeader title="Platform Audit" subtitle="Append-only record of platform-level actions" />
      <DataTable
        columns={[
          { key: "created_at", label: "When", num: true,
            render: (r) => new Date(r.created_at).toLocaleString() },
          { key: "action", label: "Action", render: (r) => <code style={{ fontSize: 12 }}>{r.action}</code> },
          { key: "tenant_id", label: "Tenant", num: true, render: (r) => r.tenant_id?.slice(0, 8) || "—" },
          { key: "result", label: "Result", render: (r) => <StatusPill status={r.result === "success" ? "active" : "inactive"} /> },
          { key: "ip_address", label: "IP", num: true },
        ]}
        rows={page?.data || []}
        empty="No platform activity recorded yet."
      />
    </>
  );
}

const Section = ({ title, children }) => (
  <div style={{ marginBottom: 16 }}>
    <div style={{ fontSize: 11.5, fontWeight: 700, textTransform: "uppercase",
      letterSpacing: ".05em", color: "var(--ink-faint)", marginBottom: 6 }}>{title}</div>
    {children}
  </div>
);
