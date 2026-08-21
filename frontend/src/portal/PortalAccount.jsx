import { useEffect, useState } from "react";
import { portalApi } from "./portalApi";
import { useI18n } from "../i18n";
import { PageHeader, Modal, StatusPill } from "../components/primitives";

export function PortalAccount() {
  const { t, money, n } = useI18n();
  const [profile, setProfile] = useState(null);
  const [usage, setUsage] = useState([]);
  const [notes, setNotes] = useState([]);
  const [changing, setChanging] = useState(false);
  const [pw, setPw] = useState({ current_password: "", new_password: "", new_password_confirmation: "" });
  const [msg, setMsg] = useState(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    portalApi.get("/profile").then(setProfile).catch(() => {});
    portalApi.get("/usage").then((r) => setUsage(r.sessions || [])).catch(() => setUsage([]));
    portalApi.get("/notifications").then(setNotes).catch(() => setNotes([]));
  }, []);

  const submitPw = async () => {
    setBusy(true); setMsg(null);
    try {
      await portalApi.post("/change-password", pw);
      setMsg("Password changed. Other devices have been signed out.");
      setPw({ current_password: "", new_password: "", new_password_confirmation: "" });
    } catch (e) { setMsg(e.message); } finally { setBusy(false); }
  };

  const c = profile?.customer, s = profile?.service;
  const inp = { width: "100%", padding: "9px 11px", border: "1px solid var(--border-strong)", borderRadius: 6, fontSize: 16 };
  const row = (k, v) => (
    <div key={k} style={{ display: "flex", justifyContent: "space-between", gap: 12,
      padding: "9px 0", borderBottom: "1px solid var(--border)", fontSize: 13.5 }}>
      <span style={{ color: "var(--ink-faint)", fontWeight: 600 }}>{k}</span>
      <span style={{ textAlign: "right" }}>{v ?? "—"}</span>
    </div>
  );

  const mb = (bytes) => `${n(Math.round((Number(bytes || 0)) / 1048576))} MB`;

  return (
    <>
      <PageHeader title={t("portal.account") === "portal.account" ? "Account" : t("portal.account")} />

      <div className="card" style={{ padding: 16, marginBottom: 14 }}>
        {row(t("cust.name"), c?.full_name)}
        {row(t("cust.id"), c?.customer_code)}
        {row(t("cust.mobile"), c?.mobile)}
        {row("Email", c?.email)}
        {row("Address", c?.address)}
        {row(t("common.status"), c ? <StatusPill status={c.status} /> : null)}
        {row(t("portal.package") === "portal.package" ? "Package" : t("portal.package"),
             s ? `${s.package_name || "—"} · ${money(s.monthly_bill)}` : null)}
      </div>

      <button className="btn btn-ghost" style={{ width: "100%", justifyContent: "center", marginBottom: 18 }}
        onClick={() => { setChanging(true); setMsg(null); }}>
        Change password
      </button>

      <h3 style={{ fontSize: 15, margin: "0 0 8px" }}>
        {t("portal.usage") === "portal.usage" ? "Recent Usage" : t("portal.usage")}
      </h3>
      <div className="card" style={{ padding: 14, marginBottom: 18 }}>
        {usage.length === 0
          ? <p style={{ margin: 0, color: "var(--ink-faint)", fontSize: 13 }}>
              No session data available. Usage appears once RADIUS accounting is active.
            </p>
          : usage.slice(0, 8).map((u, i) => (
            <div key={i} style={{ display: "flex", justifyContent: "space-between", gap: 10,
              padding: "7px 0", borderBottom: "1px solid var(--border)", fontSize: 13 }}>
              <span>{new Date(u.session_start).toLocaleString()}</span>
              <span className="num">↓{mb(u.output_octets)} ↑{mb(u.input_octets)}</span>
            </div>
          ))}
      </div>

      <h3 style={{ fontSize: 15, margin: "0 0 8px" }}>
        {t("portal.notifications") === "portal.notifications" ? "Notifications" : t("portal.notifications")}
      </h3>
      <div className="card" style={{ padding: 14 }}>
        {notes.length === 0
          ? <p style={{ margin: 0, color: "var(--ink-faint)", fontSize: 13 }}>No notifications.</p>
          : notes.slice(0, 10).map((nt) => (
            <div key={nt.id} style={{ padding: "8px 0", borderBottom: "1px solid var(--border)", fontSize: 13 }}>
              <div style={{ fontSize: 11, color: "var(--ink-faint)", fontWeight: 600 }}>
                {nt.channel.toUpperCase()} · {new Date(nt.created_at).toLocaleDateString()}
              </div>
              {nt.summary}
            </div>
          ))}
      </div>

      {changing && (
        <Modal title="Change password" onClose={() => setChanging(false)}
          footer={<>
            <button className="btn btn-ghost" onClick={() => setChanging(false)} disabled={busy}>{t("common.cancel")}</button>
            <button className="btn btn-primary" onClick={submitPw} disabled={busy}>
              {busy ? t("common.saving") : t("common.save")}
            </button>
          </>}>
          {msg && (
            <div style={{ background: "var(--info-bg)", color: "var(--info)", padding: "9px 12px",
              borderRadius: 6, fontSize: 13, marginBottom: 12 }}>{msg}</div>
          )}
          {[["current_password", "Current password"], ["new_password", "New password"],
            ["new_password_confirmation", "Confirm new password"]].map(([k, label]) => (
            <label key={k} style={{ display: "block", marginBottom: 12 }}>
              <span style={{ display: "block", fontSize: 12, fontWeight: 600, color: "var(--ink-soft)", marginBottom: 4 }}>{label}</span>
              <input type="password" style={inp} value={pw[k]}
                onChange={(e) => setPw((p) => ({ ...p, [k]: e.target.value }))} />
            </label>
          ))}
        </Modal>
      )}
    </>
  );
}
