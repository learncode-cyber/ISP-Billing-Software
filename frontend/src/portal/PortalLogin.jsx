import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { portalApi, setPortalToken } from "./portalApi";
import { useI18n } from "../i18n";

export function PortalLogin() {
  const { t } = useI18n();
  const navigate = useNavigate();
  const [form, setForm] = useState({ tenant_slug: "", login_identifier: "", password: "" });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true); setError(null);
    try {
      const res = await portalApi.post("/login", form);
      setPortalToken(res.token);
      localStorage.setItem("arq_portal_customer", res.customer_id);
      navigate("/portal");
    } catch (err) {
      setError(err.message);
    } finally { setBusy(false); }
  };

  const set = (k, v) => setForm((f) => ({ ...f, [k]: v }));
  const inp = { width: "100%", padding: "10px 12px", border: "1px solid var(--border-strong)", borderRadius: 6, fontSize: 16 };
  const lbl = { display: "block", fontSize: 12, fontWeight: 600, color: "var(--ink-soft)", margin: "12px 0 5px" };

  return (
    <div style={{ minHeight: "100vh", display: "grid", placeItems: "center", padding: 16, background: "var(--bg-shell)" }}>
      <form onSubmit={submit} className="card" style={{ width: "min(380px, 100%)", padding: "clamp(20px, 5vw, 30px)" }}>
        <div style={{ fontWeight: 700, fontSize: 18 }}>{t("app.name")}</div>
        <div style={{ fontSize: 12, color: "var(--ink-faint)", marginBottom: 20 }}>
          {t("portal.subtitle") === "portal.subtitle" ? "Customer Portal" : t("portal.subtitle")}
        </div>

        {error && (
          <div style={{ background: "var(--danger-bg)", color: "var(--danger)", padding: "9px 12px",
            borderRadius: 6, fontSize: 13, marginBottom: 12 }}>{error}</div>
        )}

        <label style={lbl} htmlFor="tenant">{t("portal.provider") === "portal.provider" ? "Service Provider ID" : t("portal.provider")}</label>
        <input id="tenant" style={inp} value={form.tenant_slug} onChange={(e) => set("tenant_slug", e.target.value)}
          placeholder="e.g. mo-network" autoCapitalize="none" required />

        <label style={lbl} htmlFor="ident">{t("portal.identifier") === "portal.identifier" ? "Mobile or Customer ID" : t("portal.identifier")}</label>
        <input id="ident" style={inp} value={form.login_identifier} onChange={(e) => set("login_identifier", e.target.value)}
          inputMode="tel" autoCapitalize="none" required />

        <label style={lbl} htmlFor="pw">{t("auth.password")}</label>
        <input id="pw" type="password" style={inp} value={form.password} onChange={(e) => set("password", e.target.value)} required />

        <button className="btn btn-primary" style={{ width: "100%", justifyContent: "center", marginTop: 16 }} disabled={busy}>
          {busy ? t("auth.signingIn") : t("auth.signIn")}
        </button>
      </form>
    </div>
  );
}
