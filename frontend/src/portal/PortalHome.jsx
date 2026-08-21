import { useEffect, useState } from "react";
import { portalApi } from "./portalApi";
import { useI18n } from "../i18n";
import { StatCard, StatGrid, StatusPill, PageHeader } from "../components/primitives";

export function PortalHome() {
  const { t, money } = useI18n();
  const [data, setData] = useState(null);
  const [profile, setProfile] = useState(null);
  const [err, setErr] = useState(null);

  useEffect(() => {
    portalApi.get("/dashboard").then(setData).catch((e) => setErr(e.message));
    portalApi.get("/profile").then(setProfile).catch(() => {});
  }, []);

  if (err) return <div className="card" style={{ padding: 20, color: "var(--danger)" }}>{err}</div>;
  if (!data) return <div style={{ color: "var(--ink-faint)" }}>{t("common.loading")}</div>;

  const bill = data.current_bill;
  const due = bill ? Number(bill.total_due || 0) - Number(bill.total_paid || 0) : 0;

  return (
    <>
      <PageHeader
        title={profile?.customer?.full_name || (t("portal.home") === "portal.home" ? "Home" : t("portal.home"))}
        subtitle={profile?.customer?.customer_code}
      />

      <div className="card" style={{ padding: 18, marginBottom: 14 }}>
        <div style={{ fontSize: 12, color: "var(--ink-faint)", textTransform: "uppercase",
          letterSpacing: ".05em", fontWeight: 600 }}>
          {t("portal.currentDue") === "portal.currentDue" ? "Current Due" : t("portal.currentDue")}
        </div>
        <div className="num" style={{ fontSize: 32, fontWeight: 700, marginTop: 6,
          color: due > 0 ? "var(--danger)" : "var(--ok)" }}>
          {money(due)}
        </div>
        {bill && (
          <div style={{ fontSize: 13, color: "var(--ink-soft)", marginTop: 4 }}>
            {bill.invoice_no} · {bill.billing_period_month}/{bill.billing_period_year}
          </div>
        )}
        {due > 0 && (
          <a href="/portal/bills" className="btn btn-primary"
            style={{ marginTop: 14, textDecoration: "none", display: "inline-flex" }}>
            {t("bill.pay")}
          </a>
        )}
      </div>

      <StatGrid min={150}>
        <StatCard
          label={t("portal.package") === "portal.package" ? "Package" : t("portal.package")}
          value={profile?.service?.package_name || "—"}
          hint={profile?.service ? money(profile.service.monthly_bill) + " / month" : ""}
        />
        <StatCard
          label={t("portal.connection") === "portal.connection" ? "Connection" : t("portal.connection")}
          value={<StatusPill status={data.connection_status || "unknown"} />}
        />
      </StatGrid>
    </>
  );
}
