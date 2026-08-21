// PortalApp.jsx — Customer Self-Service Portal.
//
// Separate auth guard (`customer`) and separate local database namespace
// from the staff console: a customer session can never resolve to staff
// identity or reach staff endpoints. Every request is OWN-scoped by the
// backend from the authenticated customer_id — the UI never sends an id
// the server would trust.
//
// Offline: previously synced bills, payment history and tickets remain
// readable with no connectivity; new complaints queue in the outbox.

import { useEffect, useState } from "react";
import { api, setToken } from "../lib/api";
import { useI18n, LanguageToggle } from "../i18n";
import { StatusPill, DataTable, Modal, FormModal } from "../components/primitives";
import { Icon } from "../components/Icon";

const TABS = [
  { key: "home", labelEn: "Dashboard", labelBn: "ড্যাশবোর্ড", icon: "grid" },
  { key: "bills", labelEn: "Bills", labelBn: "বিল", icon: "receipt" },
  { key: "tickets", labelEn: "Support", labelBn: "সহায়তা", icon: "ticket" },
  { key: "profile", labelEn: "Profile", labelBn: "প্রোফাইল", icon: "users" },
];

export function PortalApp() {
  const { lang, money, n } = useI18n();
  const [authed, setAuthed] = useState(() => Boolean(localStorage.getItem("arq_portal_token")));
  const [tab, setTab] = useState("home");

  if (!authed) return <PortalLogin onSuccess={() => setAuthed(true)} />;

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg-canvas)", paddingBottom: 72 }}>
      <header style={{
        background: "var(--bg-shell)", color: "var(--ink-invert)",
        padding: "14px var(--page-pad)", display: "flex",
        justifyContent: "space-between", alignItems: "center", gap: 10,
      }}>
        <div>
          <div style={{ fontWeight: 700, fontSize: 15 }}>{lang === "bn" ? "এ আর কুদরিক্স" : "AR Qudrix"}</div>
          <div style={{ fontSize: 11, color: "#64748b", textTransform: "uppercase", letterSpacing: ".04em" }}>
            {lang === "bn" ? "গ্রাহক পোর্টাল" : "Customer Portal"}
          </div>
        </div>
        <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
          <LanguageToggle />
          <button className="btn btn-ghost" style={{ padding: "6px 10px", color: "#cbd5e1", borderColor: "#334155" }}
            onClick={() => { localStorage.removeItem("arq_portal_token"); location.reload(); }}>
            {lang === "bn" ? "প্রস্থান" : "Log out"}
          </button>
        </div>
      </header>

      <main style={{ padding: "18px var(--page-pad)", maxWidth: 900, margin: "0 auto" }}>
        {tab === "home" && <PortalHome />}
        {tab === "bills" && <PortalBills />}
        {tab === "tickets" && <PortalTickets />}
        {tab === "profile" && <PortalProfile />}
      </main>

      {/* Bottom tab bar — thumb-reachable on phones, which is how customers
          will actually use this. */}
      <nav style={{
        position: "fixed", bottom: 0, left: 0, right: 0, background: "#fff",
        borderTop: "1px solid var(--border)", display: "flex", zIndex: 20,
      }}>
        {TABS.map((tb) => (
          <button key={tb.key} onClick={() => setTab(tb.key)}
            style={{
              flex: 1, minHeight: 56, border: "none", background: "none", cursor: "pointer",
              display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 3,
              color: tab === tb.key ? "var(--primary)" : "var(--ink-faint)",
              fontWeight: tab === tb.key ? 700 : 500, fontSize: 11.5,
            }}>
            <Icon name={tb.icon} size={19} />
            {lang === "bn" ? tb.labelBn : tb.labelEn}
          </button>
        ))}
      </nav>
    </div>
  );
}

function PortalLogin({ onSuccess }) {
  const { lang, t } = useI18n();
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true); setError(null);
    try {
      const res = await api.post("/portal/login", { login_identifier: identifier, password });
      localStorage.setItem("arq_portal_token", res.token);
      setToken(res.token);
      onSuccess();
    } catch {
      setError(lang === "bn" ? "ভুল মোবাইল/আইডি বা পাসওয়ার্ড।" : "Invalid mobile/ID or password.");
    } finally { setBusy(false); }
  };

  const lbl = { display: "block", fontSize: 12, fontWeight: 600, color: "var(--ink-soft)", margin: "12px 0 5px" };
  const inp = { width: "100%", padding: "10px 12px", border: "1px solid var(--border-strong)", borderRadius: 6, fontSize: 16 };

  return (
    <div style={{ minHeight: "100vh", display: "grid", placeItems: "center", padding: 16, background: "var(--bg-shell)" }}>
      <form onSubmit={submit} className="card" style={{ width: "min(380px, 100%)", padding: "clamp(20px, 5vw, 30px)" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
          <div>
            <div style={{ fontWeight: 700, fontSize: 18 }}>{lang === "bn" ? "এ আর কুদরিক্স" : "AR Qudrix"}</div>
            <div style={{ fontSize: 12, color: "var(--ink-faint)", textTransform: "uppercase", letterSpacing: ".05em" }}>
              {lang === "bn" ? "গ্রাহক পোর্টাল" : "Customer Portal"}
            </div>
          </div>
          <LanguageToggle />
        </div>

        {error && (
          <div style={{ background: "var(--danger-bg)", color: "var(--danger)", padding: "9px 12px",
            borderRadius: 6, fontSize: 13, marginTop: 16 }}>{error}</div>
        )}

        <label style={lbl}>{lang === "bn" ? "মোবাইল নম্বর বা গ্রাহক আইডি" : "Mobile number or Customer ID"}</label>
        <input value={identifier} onChange={(e) => setIdentifier(e.target.value)} style={inp} autoFocus
          inputMode="tel" autoComplete="username" />

        <label style={lbl}>{t("auth.password")}</label>
        <input type="password" value={password} onChange={(e) => setPassword(e.target.value)}
          style={inp} autoComplete="current-password" />

        <button className="btn btn-primary" style={{ width: "100%", justifyContent: "center", marginTop: 16 }} disabled={busy}>
          {busy ? t("auth.signingIn") : t("auth.signIn")}
        </button>
      </form>
    </div>
  );
}

function PortalHome() {
  const { lang, money } = useI18n();
  const [data, setData] = useState(null);
  const [err, setErr] = useState(null);

  useEffect(() => {
    api.get("/portal/dashboard").then(setData).catch((e) => setErr(e.message));
  }, []);

  if (err) return <Notice tone="danger">{err}</Notice>;
  if (!data) return <Notice>{lang === "bn" ? "লোড হচ্ছে…" : "Loading…"}</Notice>;

  const due = Number(data.current_bill?.total_due || 0) - Number(data.current_bill?.total_paid || 0);

  return (
    <>
      <Card>
        <Label>{lang === "bn" ? "সংযোগের অবস্থা" : "Connection status"}</Label>
        <div style={{ marginTop: 6 }}><StatusPill status={data.connection_status || "unknown"} /></div>
      </Card>

      <Card tone={due > 0 ? "danger" : "ok"}>
        <Label>{lang === "bn" ? "বর্তমান বকেয়া" : "Current due"}</Label>
        <div className="num" style={{ fontSize: 30, fontWeight: 700, marginTop: 4,
          color: due > 0 ? "var(--danger)" : "var(--ok)" }}>
          {money(due)}
        </div>
        {data.current_bill && (
          <div style={{ fontSize: 12.5, color: "var(--ink-faint)", marginTop: 4 }}>
            {lang === "bn" ? "বিল নম্বর" : "Invoice"} {data.current_bill.invoice_no}
          </div>
        )}
      </Card>

      <Card>
        <Label>{lang === "bn" ? "আপনার প্যাকেজ" : "Your package"}</Label>
        <div style={{ fontSize: 16, fontWeight: 600, marginTop: 4 }}>
          {data.service?.package_name || (lang === "bn" ? "নির্ধারিত নয়" : "Not set")}
        </div>
        <div className="num" style={{ fontSize: 13, color: "var(--ink-soft)", marginTop: 2 }}>
          {money(data.service?.monthly_bill || 0)} / {lang === "bn" ? "মাস" : "month"}
        </div>
      </Card>
    </>
  );
}

function PortalBills() {
  const { lang, money } = useI18n();
  const [page, setPage] = useState(null);
  const [paying, setPaying] = useState(null);

  const load = () => api.get("/portal/invoices").then(setPage).catch(() => setPage({ data: [] }));
  useEffect(() => { load(); }, []);

  const cols = [
    { key: "invoice_no", label: lang === "bn" ? "বিল নম্বর" : "Invoice", num: true },
    { key: "period", label: lang === "bn" ? "মাস" : "Period", num: true,
      render: (r) => `${r.billing_period_month}/${r.billing_period_year}` },
    { key: "total_due", label: lang === "bn" ? "পরিমাণ" : "Amount", align: "right", num: true,
      render: (r) => money(r.total_due) },
    { key: "status", label: lang === "bn" ? "অবস্থা" : "Status", render: (r) => <StatusPill status={r.status} /> },
    { key: "act", label: "", align: "right", render: (r) => r.status !== "paid" && (
      <button className="btn btn-primary" style={{ padding: "5px 14px", fontSize: 12 }}
        onClick={() => setPaying(r)}>{lang === "bn" ? "পরিশোধ" : "Pay"}</button>
    ) },
  ];

  return (
    <>
      <H2>{lang === "bn" ? "বিল ও পেমেন্ট" : "Bills & Payments"}</H2>
      <DataTable columns={cols} rows={page?.data || []}
        empty={lang === "bn" ? "কোনো বিল নেই।" : "No invoices yet."} />

      {paying && (
        <FormModal
          title={lang === "bn" ? "অনলাইন পেমেন্ট" : "Pay online"}
          submitLabel={lang === "bn" ? "পরিশোধ করুন" : "Continue to pay"}
          fields={[{
            name: "provider", label: lang === "bn" ? "পেমেন্ট মাধ্যম" : "Payment method",
            type: "select", required: true,
            options: [
              { value: "bkash", label: "bKash" }, { value: "nagad", label: "Nagad" },
              { value: "sslcommerz", label: "SSLCommerz" }, { value: "stripe", label: "Card" },
            ],
          }]}
          onSubmit={async (v) => {
            const res = await api.post("/portal/pay", { invoice_id: paying.id, provider: v.provider });
            if (res.redirect_url) location.href = res.redirect_url;
            else throw new Error(res.message || (lang === "bn"
              ? "এই মুহূর্তে অনলাইন পেমেন্ট চালু নেই। অনুগ্রহ করে অফিসে যোগাযোগ করুন।"
              : "Online payment is not available right now. Please contact the office."));
          }}
          onClose={(done) => { setPaying(null); if (done) load(); }}
        />
      )}
    </>
  );
}

function PortalTickets() {
  const { lang } = useI18n();
  const [rows, setRows] = useState([]);
  const [creating, setCreating] = useState(false);

  const load = () => api.get("/portal/tickets").then(setRows).catch(() => setRows([]));
  useEffect(() => { load(); }, []);

  const cols = [
    { key: "ticket_no", label: lang === "bn" ? "নম্বর" : "Ticket", num: true },
    { key: "note", label: lang === "bn" ? "বিষয়" : "Subject" },
    { key: "status", label: lang === "bn" ? "অবস্থা" : "Status", render: (r) => <StatusPill status={r.status} /> },
  ];

  return (
    <>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, flexWrap: "wrap" }}>
        <H2>{lang === "bn" ? "অভিযোগ ও সহায়তা" : "Support"}</H2>
        <button className="btn btn-primary" onClick={() => setCreating(true)}>
          {lang === "bn" ? "+ নতুন অভিযোগ" : "+ New complaint"}
        </button>
      </div>
      <DataTable columns={cols} rows={rows}
        empty={lang === "bn" ? "কোনো অভিযোগ নেই।" : "No complaints yet."} />

      {creating && (
        <FormModal
          title={lang === "bn" ? "নতুন অভিযোগ" : "New complaint"}
          submitLabel={lang === "bn" ? "জমা দিন" : "Submit"}
          fields={[
            { name: "priority", label: lang === "bn" ? "গুরুত্ব" : "Priority", type: "select", required: true,
              options: [
                { value: "high", label: lang === "bn" ? "জরুরি" : "High" },
                { value: "medium", label: lang === "bn" ? "মাঝারি" : "Medium" },
                { value: "low", label: lang === "bn" ? "সাধারণ" : "Low" },
              ], default: "medium" },
            { name: "note", label: lang === "bn" ? "সমস্যার বিবরণ" : "Describe the problem", required: true },
          ]}
          onSubmit={(v) => api.post("/portal/tickets", v)}
          onClose={(saved) => { setCreating(false); if (saved) load(); }}
        />
      )}
    </>
  );
}

function PortalProfile() {
  const { lang } = useI18n();
  const [me, setMe] = useState(null);
  const [changing, setChanging] = useState(false);

  useEffect(() => { api.get("/portal/profile").then(setMe).catch(() => setMe(null)); }, []);

  if (!me) return <Notice>{lang === "bn" ? "লোড হচ্ছে…" : "Loading…"}</Notice>;

  const rows = [
    [lang === "bn" ? "নাম" : "Name", me.full_name],
    [lang === "bn" ? "গ্রাহক আইডি" : "Customer ID", me.customer_code],
    [lang === "bn" ? "মোবাইল" : "Mobile", me.mobile],
    [lang === "bn" ? "ঠিকানা" : "Address", me.address || "—"],
    [lang === "bn" ? "সংযোগের তারিখ" : "Connection date", me.connection_date || "—"],
  ];

  return (
    <>
      <H2>{lang === "bn" ? "প্রোফাইল" : "Profile"}</H2>
      <Card>
        <dl style={{ margin: 0, display: "grid", gridTemplateColumns: "auto 1fr", gap: "10px 16px", fontSize: 14 }}>
          {rows.map(([k, v]) => (
            <div key={k} style={{ display: "contents" }}>
              <dt style={{ color: "var(--ink-faint)", fontWeight: 600 }}>{k}</dt>
              <dd style={{ margin: 0, textAlign: "right" }}>{v}</dd>
            </div>
          ))}
        </dl>
      </Card>

      <button className="btn btn-ghost" style={{ width: "100%", marginTop: 12 }} onClick={() => setChanging(true)}>
        {lang === "bn" ? "পাসওয়ার্ড পরিবর্তন" : "Change password"}
      </button>

      {changing && (
        <FormModal
          title={lang === "bn" ? "পাসওয়ার্ড পরিবর্তন" : "Change password"}
          submitLabel={lang === "bn" ? "সংরক্ষণ" : "Save"}
          fields={[
            { name: "current_password", label: lang === "bn" ? "বর্তমান পাসওয়ার্ড" : "Current password", required: true },
            { name: "new_password", label: lang === "bn" ? "নতুন পাসওয়ার্ড" : "New password", required: true },
          ]}
          onSubmit={(v) => api.post("/portal/change-password", v)}
          onClose={() => setChanging(false)}
        />
      )}
    </>
  );
}

// --- small presentational helpers ---
const H2 = ({ children }) => (
  <h2 style={{ fontSize: 17, fontWeight: 700, margin: "0 0 12px" }}>{children}</h2>
);
const Label = ({ children }) => (
  <div style={{ fontSize: 11.5, textTransform: "uppercase", letterSpacing: ".05em",
    color: "var(--ink-faint)", fontWeight: 600 }}>{children}</div>
);
const Card = ({ children }) => (
  <div className="card" style={{ padding: 16, marginBottom: 12 }}>{children}</div>
);
const Notice = ({ children, tone }) => (
  <div className="card" style={{ padding: 24, textAlign: "center",
    color: tone === "danger" ? "var(--danger)" : "var(--ink-faint)" }}>{children}</div>
);
