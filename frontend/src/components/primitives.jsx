// primitives.jsx — small reusable building blocks shared across pages.
// Kept deliberately minimal and prop-driven (no business logic) so every
// page composes the same visual vocabulary.

import { useEffect, useState } from "react";
import { Icon } from "./Icon";

export function PageHeader({ title, subtitle, action }) {
  return (
    <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between", gap: 12, flexWrap: "wrap", marginBottom: 20 }}>
      <div>
        <h1 style={{ margin: 0, fontSize: "clamp(18px, 4vw, 22px)", fontWeight: 700, letterSpacing: "-0.02em" }}>{title}</h1>
        {subtitle && <p style={{ margin: "4px 0 0", color: "var(--ink-soft)", fontSize: 13.5 }}>{subtitle}</p>}
      </div>
      {action}
    </div>
  );
}

/** Responsive stat grid: never a fixed column count, so cards reflow
 *  cleanly from 320px to desktop. */
export function StatGrid({ children, min = 150 }) {
  return (
    <div style={{
      display: "grid",
      gridTemplateColumns: `repeat(auto-fit, minmax(${min}px, 1fr))`,
      gap: 12, marginBottom: 14,
    }}>
      {children}
    </div>
  );
}

export function StatCard({ label, value, tone = "default", hint }) {
  const toneColor = {
    default: "var(--ink)", ok: "var(--ok)", danger: "var(--danger)",
    warn: "var(--warn)", info: "var(--info)", primary: "var(--primary)",
  }[tone];
  return (
    <div className="card" style={{ padding: "16px 18px" }}>
      <div style={{ fontSize: 11.5, textTransform: "uppercase", letterSpacing: "0.05em", color: "var(--ink-faint)", fontWeight: 600 }}>
        {label}
      </div>
      <div className="num" style={{ fontSize: 26, fontWeight: 700, color: toneColor, marginTop: 6, letterSpacing: "-0.02em" }}>
        {value}
      </div>
      {hint && <div style={{ fontSize: 12, color: "var(--ink-faint)", marginTop: 2 }}>{hint}</div>}
    </div>
  );
}

// Maps a domain status string to the functional pill palette.
const STATUS_TONE = {
  active: "ok", online: "ok", paid: "ok", connected: "ok", solved: "ok",
  inactive: "danger", offline: "danger", due: "danger", discontinue: "danger",
  unpaid: "danger", los: "danger", critical: "danger", unreachable: "danger",
  partial: "warn", processing: "warn", pending: "warn", warning: "warn",
  free: "info", trial: "info",
};
export function StatusPill({ status }) {
  const tone = STATUS_TONE[String(status).toLowerCase()] || "info";
  return <span className={`pill pill-${tone}`}>{status}</span>;
}

export function DataTable({ columns, rows, empty = "Nothing here yet.", rowKey = "id" }) {
  if (!rows?.length) {
    return (
      <div className="card" style={{ padding: 40, textAlign: "center", color: "var(--ink-faint)" }}>
        {empty}
      </div>
    );
  }
  // .table-scroll contains any horizontal overflow to the table itself
  // (never the page). Below 640px `responsive-cards` restacks each row as
  // a labelled card, so no data is lost and no sideways scrolling is
  // needed on phones (spec Section 4).
  return (
    <div className="card" style={{ overflow: "hidden" }}>
      <div className="table-scroll">
        <table className="responsive-cards">
          <thead>
            <tr>{columns.map((c) => <th key={c.key} style={{ textAlign: c.align || "left" }}>{c.label}</th>)}</tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row[rowKey]}>
                {columns.map((c) => (
                  <td
                    key={c.key}
                    data-label={c.label}
                    style={{ textAlign: c.align || "left" }}
                    className={c.num ? "num" : ""}
                  >
                    {c.render ? c.render(row) : row[c.key]}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export function PlanRequired({ feature }) {
  return (
    <div className="card" style={{ padding: 32, textAlign: "center" }}>
      <div style={{ color: "var(--warn)", marginBottom: 8 }}><Icon name="zap" size={28} /></div>
      <h3 style={{ margin: "0 0 6px" }}>Not included in your plan</h3>
      <p style={{ color: "var(--ink-soft)", margin: 0, fontSize: 13.5 }}>
        The <strong>{feature}</strong> module isn’t part of your current subscription.
        Contact AR Qudrix to upgrade.
      </p>
    </div>
  );
}


/** Modal — responsive dialog. Width is capped by the viewport (never a
 *  fixed 420px that overflows a 320px phone), scrolls internally when
 *  tall, closes on Escape and backdrop click. */
export function Modal({ title, subtitle, onClose, children, footer }) {
  useEffect(() => {
    const onKey = (e) => e.key === "Escape" && onClose?.();
    window.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => { window.removeEventListener("keydown", onKey); document.body.style.overflow = ""; };
  }, [onClose]);

  return (
    <div
      onClick={onClose}
      role="dialog"
      aria-modal="true"
      style={{
        position: "fixed", inset: 0, background: "rgba(15,23,42,.45)",
        display: "flex", alignItems: "center", justifyContent: "center",
        padding: 12, zIndex: 60,
      }}
    >
      <div
        className="card"
        onClick={(e) => e.stopPropagation()}
        style={{
          width: "min(440px, 100%)", maxHeight: "calc(100vh - 24px)",
          overflowY: "auto", padding: 20, boxShadow: "var(--shadow-pop)",
        }}
      >
        {title && <h3 style={{ margin: "0 0 4px", fontSize: 17 }}>{title}</h3>}
        {subtitle && <p style={{ margin: "0 0 16px", color: "var(--ink-soft)", fontSize: 13 }}>{subtitle}</p>}
        {children}
        {footer && (
          <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", flexWrap: "wrap", marginTop: 18 }}>
            {footer}
          </div>
        )}
      </div>
    </div>
  );
}


/** FormModal — schema-driven create/edit form. Fields are declared by the
 *  calling page, submitted to a real API endpoint, with inline validation
 *  errors surfaced from the server response. Used by every "+ New X"
 *  action so no create button is ever a dead control. */
export function FormModal({ title, fields, onSubmit, onClose, submitLabel = "Save" }) {
  const [values, setValues] = useState(() =>
    Object.fromEntries(fields.map((f) => [f.name, f.default ?? ""]))
  );
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const set = (k, v) => setValues((prev) => ({ ...prev, [k]: v }));

  const submit = async () => {
    setBusy(true); setError(null);
    try {
      await onSubmit(values);
      onClose(true);
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  const inputStyle = {
    width: "100%", padding: "8px 11px", border: "1px solid var(--border-strong)",
    borderRadius: 6, fontSize: 13.5,
  };

  return (
    <Modal
      title={title}
      onClose={() => onClose(false)}
      footer={<>
        <button className="btn btn-ghost" onClick={() => onClose(false)} disabled={busy}>Cancel</button>
        <button className="btn btn-primary" onClick={submit} disabled={busy}>
          {busy ? "Saving…" : submitLabel}
        </button>
      </>}
    >
      {error && (
        <div style={{ background: "var(--danger-bg)", color: "var(--danger)", padding: "9px 12px", borderRadius: 6, fontSize: 13, marginBottom: 12 }}>
          {error}
        </div>
      )}
      {fields.map((f) => (
        <label key={f.name} style={{ display: "block", marginBottom: 12 }}>
          <span style={{ display: "block", fontSize: 12, fontWeight: 600, color: "var(--ink-soft)", marginBottom: 4 }}>
            {f.label}{f.required && <span style={{ color: "var(--danger)" }}> *</span>}
          </span>
          {f.type === "select" ? (
            <select value={values[f.name]} onChange={(e) => set(f.name, e.target.value)} style={inputStyle}>
              <option value="">Select…</option>
              {(f.options || []).map((o) => (
                <option key={o.value ?? o} value={o.value ?? o}>{o.label ?? o}</option>
              ))}
            </select>
          ) : (
            <input
              type={f.type === "number" ? "number" : f.type === "date" ? "date" : "text"}
              inputMode={f.type === "number" ? "decimal" : undefined}
              value={values[f.name]}
              onChange={(e) => set(f.name, e.target.value)}
              style={inputStyle}
            />
          )}
        </label>
      ))}
    </Modal>
  );
}
