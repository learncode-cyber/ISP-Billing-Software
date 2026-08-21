// AppShell.jsx — the signature element: a sidebar that renders only the
// modules the tenant's plan + the user's role actually allow, driven by
// /api/v1/me/capabilities (Blueprint Section 37).
//
// Responsive (spec Section 4): at ≥1024px the sidebar is a fixed column;
// below that it becomes an off-canvas drawer opened by a hamburger, with
// a backdrop, Escape-to-close, and focus not trapped behind it. The grid
// collapses to a single column so content always gets the full viewport
// width — no 244px sidebar eating a 320px screen.

import { useEffect, useState } from "react";
import { NavLink, Outlet, useLocation } from "react-router-dom";
import { NAV_SECTIONS } from "../lib/navigation";
import { useCapabilities } from "../context/CapabilitiesContext";
import { Icon } from "../components/Icon";
import { useI18n, LanguageToggle } from "../i18n";
import { SyncStatus, OfflineBanner } from "../components/SyncStatus";
import { purgeTenant } from "../offline/db";

export function AppShell() {
  const { t } = useI18n();
  const { loading, hasFeature, can } = useCapabilities();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [isDesktop, setIsDesktop] = useState(() =>
    typeof window !== "undefined" ? window.matchMedia("(min-width: 1024px)").matches : true
  );
  const location = useLocation();

  useEffect(() => {
    const mq = window.matchMedia("(min-width: 1024px)");
    const onChange = (e) => { setIsDesktop(e.matches); if (e.matches) setDrawerOpen(false); };
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, []);

  // Close the drawer on navigation and on Escape.
  useEffect(() => { setDrawerOpen(false); }, [location.pathname]);
  useEffect(() => {
    const onKey = (e) => e.key === "Escape" && setDrawerOpen(false);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  // Prevent body scroll behind an open drawer.
  useEffect(() => {
    document.body.style.overflow = drawerOpen && !isDesktop ? "hidden" : "";
    return () => { document.body.style.overflow = ""; };
  }, [drawerOpen, isDesktop]);

  if (loading) {
    return <div style={{ padding: 40, color: "var(--ink-faint)" }}>{t("app.loading")}</div>;
  }

  const visibleSections = NAV_SECTIONS.map((s) => ({
    ...s,
    items: s.items.filter(
      (it) => (it.feature === null || hasFeature(it.feature)) && (it.perm === null || can(it.perm))
    ),
  })).filter((s) => s.items.length > 0);

  const sidebarVisible = isDesktop || drawerOpen;

  return (
    <div style={{ minHeight: "100vh", display: "flex" }}>
      {/* Backdrop (mobile drawer only) */}
      {!isDesktop && drawerOpen && (
        <div
          onClick={() => setDrawerOpen(false)}
          aria-hidden="true"
          style={{ position: "fixed", inset: 0, background: "rgba(15,23,42,.45)", zIndex: 40 }}
        />
      )}

      <aside
        aria-label="Main navigation"
        style={{
          background: "var(--bg-shell)", color: "var(--ink-invert)",
          display: "flex", flexDirection: "column",
          width: "var(--sidebar-w)", flexShrink: 0,
          ...(isDesktop
            ? { position: "sticky", top: 0, height: "100vh" }
            : {
                position: "fixed", top: 0, bottom: 0, left: 0, zIndex: 41,
                transform: drawerOpen ? "translateX(0)" : "translateX(-100%)",
                transition: "transform .2s ease",
                boxShadow: drawerOpen ? "var(--shadow-pop)" : "none",
              }),
        }}
        {...(!sidebarVisible ? { inert: "" } : {})}
      >
        <div style={{ padding: "18px 20px 14px", borderBottom: "1px solid rgba(255,255,255,.08)", display: "flex", justifyContent: "space-between", alignItems: "flex-start" }}>
          <div>
            <div style={{ fontWeight: 700, fontSize: 15, letterSpacing: "-.01em" }}>{t("app.name")}</div>
            <div style={{ fontSize: 11, color: "#64748b", marginTop: 2, letterSpacing: ".04em", textTransform: "uppercase" }}>
              {t("app.tagline")}
            </div>
          </div>
          {!isDesktop && (
            <button onClick={() => setDrawerOpen(false)} aria-label="Close navigation"
              style={{ background: "none", border: "none", color: "#94a3b8", cursor: "pointer", padding: 4, minWidth: 44, minHeight: 44 }}>
              ✕
            </button>
          )}
        </div>

        <nav style={{ flex: 1, overflowY: "auto", padding: "12px 10px", WebkitOverflowScrolling: "touch" }}>
          {visibleSections.map((section) => (
            <div key={t(section.i18nKey || "nav.overview")} style={{ marginBottom: 18 }}>
              <div style={{ fontSize: 10.5, textTransform: "uppercase", letterSpacing: ".06em", color: "#475569", padding: "0 10px 6px", fontWeight: 600 }}>
                {t(section.i18nKey || "nav.overview")}
              </div>
              {section.items.map((it) => (
                <NavLink
                  key={it.key} to={it.path} end={it.path === "/"}
                  style={({ isActive }) => ({
                    display: "flex", alignItems: "center", gap: 10,
                    padding: "10px", borderRadius: 6, marginBottom: 1, minHeight: 40,
                    color: isActive ? "#fff" : "#cbd5e1",
                    background: isActive ? "var(--primary)" : "transparent",
                    fontSize: 13.5, fontWeight: isActive ? 600 : 500, textDecoration: "none",
                  })}
                >
                  <Icon name={it.icon} size={16} />
                  {t(it.i18nKey || it.label)}
                </NavLink>
              ))}
            </div>
          ))}
        </nav>
      </aside>

      <main style={{ display: "flex", flexDirection: "column", flex: 1, minWidth: 0 }}>
        <TopBar isDesktop={isDesktop} onOpenDrawer={() => setDrawerOpen(true)} />
        <OfflineBanner />
        <div style={{ padding: "20px var(--page-pad)", flex: 1, minWidth: 0 }}>
          <Outlet />
        </div>
      </main>
    </div>
  );
}

function TopBar({ isDesktop, onOpenDrawer }) {
  return (
    <header
      style={{
        minHeight: 56, borderBottom: "1px solid var(--border)", background: "#fff",
        display: "flex", alignItems: "center", gap: 12,
        padding: "8px var(--page-pad)", position: "sticky", top: 0, zIndex: 30,
      }}
    >
      {!isDesktop && (
        <button onClick={onOpenDrawer} aria-label="Open navigation" className="btn btn-ghost"
          style={{ padding: "6px 10px", minWidth: 40 }}>
          <span aria-hidden="true" style={{ fontSize: 16, lineHeight: 1 }}>☰</span>
        </button>
      )}

      <div style={{ position: "relative", flex: 1, minWidth: 0, maxWidth: 360 }}>
        <label htmlFor="global-search" className="sr-only">Search</label>
        <input
          id="global-search"
          placeholder={isDesktop ? "Search customers, tickets, invoices…" : "Search…"}
          style={{
            width: "100%", padding: "8px 12px 8px 34px", border: "1px solid var(--border-strong)",
            borderRadius: 6, fontSize: 13, background: "var(--bg-canvas)",
          }}
        />
        <span aria-hidden="true" style={{ position: "absolute", left: 11, top: "50%", transform: "translateY(-50%)", color: "var(--ink-faint)", display: "flex" }}>
          <Icon name="search" size={15} />
        </span>
      </div>

      <div style={{ display: "flex", alignItems: "center", gap: 10, fontSize: 13, color: "var(--ink-soft)", flexShrink: 0 }}>
        <SyncStatus compact={!isDesktop} />
        <LanguageToggle />
        {isDesktop && <span className="num" title="SMS wallet balance">৳ 689.96</span>}
        <button className="btn btn-ghost" style={{ padding: "6px 10px" }}
          onClick={async () => {
            // Purge this tenant's cached records, outbox and files before
            // releasing the device — so the next login (possibly a different
            // tenant) can never reach the previous tenant's offline data.
            const t = localStorage.getItem("arq_tenant_id");
            if (t) { try { await purgeTenant(t); } catch { /* proceed with logout regardless */ } }
            if ("caches" in window) { try { const ks = await caches.keys(); await Promise.all(ks.map((k) => caches.delete(k))); } catch {} }
            localStorage.removeItem("arq_token");
            localStorage.removeItem("arq_tenant_id");
            location.href = "/login";
          }}>
          {isDesktop ? "Sign out" : "Exit"}
        </button>
      </div>
    </header>
  );
}
