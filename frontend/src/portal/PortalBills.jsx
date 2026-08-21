import { useEffect, useState } from "react";
import { portalApi } from "./portalApi";
import { useI18n } from "../i18n";
import { PageHeader, DataTable, StatusPill, Modal } from "../components/primitives";

export function PortalBills() {
  const { t, money } = useI18n();
  const [tab, setTab] = useState("invoices");
  const [invoices, setInvoices] = useState([]);
  const [payments, setPayments] = useState([]);
  const [paying, setPaying] = useState(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState(null);

  const load = () => {
    portalApi.get("/invoices").then((r) => setInvoices(r.data || [])).catch(() => setInvoices([]));
    portalApi.get("/payments").then((r) => setPayments(r.data || [])).catch(() => setPayments([]));
  };
  useEffect(load, []);

  const payNow = async (provider) => {
    setBusy(true); setMsg(null);
    try {
      const r = await portalApi.post("/pay", { invoice_id: paying.id, provider });
      if (r.redirect_url) { location.href = r.redirect_url; return; }
      // Gateway not yet wired to live credentials — say so plainly rather
      // than pretending the payment succeeded.
      setMsg(r.message || "Payment could not be started. Please contact your provider.");
    } catch (e) { setMsg(e.message); } finally { setBusy(false); }
  };

  const invoiceCols = [
    { key: "invoice_no", label: t("portal.invoice") === "portal.invoice" ? "Invoice" : t("portal.invoice"),
      num: true, render: (r) => <strong className="num">{r.invoice_no}</strong> },
    { key: "period", label: t("portal.period") === "portal.period" ? "Period" : t("portal.period"), num: true,
      render: (r) => `${r.billing_period_month}/${r.billing_period_year}` },
    { key: "total_due", label: t("bill.dueAmount"), align: "right", num: true, render: (r) => money(r.total_due) },
    { key: "status", label: t("common.status"), render: (r) => <StatusPill status={r.status} /> },
    { key: "act", label: "", align: "right", render: (r) => r.status !== "paid" && (
      <button className="btn btn-primary" style={{ padding: "5px 14px", fontSize: 12 }}
        onClick={() => setPaying(r)}>{t("bill.pay")}</button>
    ) },
  ];

  const paymentCols = [
    { key: "paid_at", label: t("portal.date") === "portal.date" ? "Date" : t("portal.date"), num: true,
      render: (r) => new Date(r.paid_at).toLocaleDateString() },
    { key: "invoice_no", label: "Invoice", num: true },
    { key: "method", label: t("bill.method") },
    { key: "amount", label: t("bill.payAmount"), align: "right", num: true, render: (r) => money(r.amount) },
  ];

  return (
    <>
      <PageHeader title={t("portal.bills") === "portal.bills" ? "Bills" : t("portal.bills")} />

      <div style={{ display: "flex", gap: 6, marginBottom: 14, borderBottom: "1px solid var(--border)", overflowX: "auto" }}>
        {[["invoices", "Invoices"], ["payments", "Payment History"]].map(([k, label]) => (
          <button key={k} onClick={() => setTab(k)}
            className="tab-btn" aria-selected={tab === k}>
            {label}
          </button>
        ))}
      </div>

      {tab === "invoices"
        ? <DataTable columns={invoiceCols} rows={invoices} empty="No invoices yet." />
        : <DataTable columns={paymentCols} rows={payments} empty="No payments recorded yet." />}

      {paying && (
        <Modal title={t("bill.pay")} subtitle={`${paying.invoice_no} · ${money(paying.total_due)}`}
          onClose={() => { setPaying(null); setMsg(null); }}
          footer={<button className="btn btn-ghost" onClick={() => { setPaying(null); setMsg(null); }}>{t("common.close")}</button>}>
          {msg && (
            <div style={{ background: "var(--warn-bg)", color: "var(--warn)", padding: "9px 12px",
              borderRadius: 6, fontSize: 13, marginBottom: 12 }}>{msg}</div>
          )}
          <div style={{ fontSize: 13, color: "var(--ink-soft)", marginBottom: 10 }}>
            {t("portal.choosePayment") === "portal.choosePayment" ? "Choose a payment method" : t("portal.choosePayment")}
          </div>
          <div style={{ display: "grid", gap: 8 }}>
            {["bkash", "nagad", "sslcommerz"].map((p) => (
              <button key={p} className="btn btn-ghost" disabled={busy}
                style={{ justifyContent: "flex-start", textTransform: "capitalize" }}
                onClick={() => payNow(p)}>
                {busy ? t("common.saving") : p}
              </button>
            ))}
          </div>
          <p style={{ fontSize: 12, color: "var(--ink-faint)", marginTop: 12, marginBottom: 0 }}>
            {t("sync.requiresNet")} Online payment needs an internet connection.
          </p>
        </Modal>
      )}
    </>
  );
}
