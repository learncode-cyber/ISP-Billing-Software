// PortalShell.jsx — customer-facing layout. Mobile-first: subscribers open
// this on a phone, so navigation is a bottom tab bar rather than a sidebar.
import { NavLink, Outlet, useNavigate } from "react-router-dom";
import { Icon } from "../components/Icon";
import { useI18n, LanguageToggle } from "../i18n";
import { portalApi, setPortalToken } from "./portalApi";
import { OfflineBanner } from "../components/SyncStatus";

const TABS = [
  { to: "/portal", end: true, icon: "grid", key: "portal.home", fallback: "Home" },
  { to: "/portal/bills", icon: "receipt", key: "portal.bills", fallback: "Bills" },
  { to: "/portal/support", icon: "ticket", key: "portal.support", fallback: "Support" },
  { to: "/portal/account", icon: "users", key: "portal.account", fallback: "Account" },
];

export function PortalShell() {
  const { t } = useI18n();
  const navigate = useNavigate();

  const signOut = async () => {
    try { await portalApi.post("/logout"); } catch { /* offline: drop locally anyway */ }
    setPortalToken(null);
    navigate("/portal/login");
  };

  return (
    <div style={{ minHeight: "100vh", display: "flex", flexDirection: "column", background: "var(--bg-canvas)" }}>
      <header style={{
        background: "var(--bg-shell)", color: "var(--ink-invert)",
        padding: "12px var(--page-pad)", display: "flex",
        alignItems: "center", justifyContent: "space-between", gap: 10,
      }}>
        <div>
          <div style={{ fontWeight: 700, fontSize: 15 }}>{t("app.name")}</div>
          <div style={{ fontSize: 11, color: "#94a3b8" }}>{t("portal.title", {}) || "Customer Portal"}</div>
        </div>
        <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
          <LanguageToggle />
          <button className="btn btn-ghost" style={{ padding: "6px 10px", color: "#cbd5e1", borderColor: "#334155" }}
            onClick={signOut}>{t("app.signOut")}</button>
        </div>
      </header>

      <main style={{ flex: 1, padding: "16px var(--page-pad) 84px", minWidth: 0 }}>
        <OfflineBanner />
        <Outlet />
      </main>

      <nav aria-label="Portal navigation" style={{
        position: "fixed", bottom: 0, left: 0, right: 0, background: "#fff",
        borderTop: "1px solid var(--border)", display: "flex",
        justifyContent: "space-around", padding: "6px 0 max(6px, env(safe-area-inset-bottom))",
        zIndex: 30,
      }}>
        {TABS.map((tab) => (
          <NavLink key={tab.to} to={tab.to} end={tab.end}
            style={({ isActive }) => ({
              display: "flex", flexDirection: "column", alignItems: "center", gap: 3,
              padding: "6px 12px", minWidth: 64, minHeight: 48, borderRadius: 8,
              textDecoration: "none", fontSize: 11, fontWeight: 600,
              color: isActive ? "var(--primary)" : "var(--ink-faint)",
            })}>
            <Icon name={tab.icon} size={20} />
            {t(tab.key) === tab.key ? tab.fallback : t(tab.key)}
          </NavLink>
        ))}
      </nav>
    </div>
  );
}
