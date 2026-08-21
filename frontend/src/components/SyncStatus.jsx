// SyncStatus.jsx — the connectivity indicator required by the spec:
// 🟢 Online · 🟡 Syncing · 🔴 Offline · 🟠 Sync Error · ⚠️ Conflicts Pending
// plus "Last synchronised: X ago" and "Pending changes: X".
//
// Rendered in the top bar so the user always knows whether their work has
// reached the server — the single most important piece of feedback in an
// offline-first app.

import { useEffect, useState } from "react";
import { subscribe, sync, SYNC_STATE } from "../offline/syncEngine";

const PRESENTATION = {
  [SYNC_STATE.ONLINE]:    { dot: "🟢", label: "Online",    tone: "var(--ok)" },
  [SYNC_STATE.SYNCING]:   { dot: "🟡", label: "Syncing",   tone: "var(--warn)" },
  [SYNC_STATE.OFFLINE]:   { dot: "🔴", label: "Offline",   tone: "var(--danger)" },
  [SYNC_STATE.ERROR]:     { dot: "🟠", label: "Sync error", tone: "var(--warn)" },
  [SYNC_STATE.CONFLICTS]: { dot: "⚠️", label: "Conflicts",  tone: "var(--warn)" },
};

function ago(iso) {
  if (!iso) return "never";
  const mins = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins} min ago`;
  const h = Math.floor(mins / 60);
  if (h < 24) return `${h} h ago`;
  return `${Math.floor(h / 24)} d ago`;
}

export function SyncStatus({ compact = false }) {
  const [status, setStatus] = useState({ state: SYNC_STATE.ONLINE, pendingCount: 0, conflictCount: 0 });
  useEffect(() => subscribe(setStatus), []);

  const p = PRESENTATION[status.state] || PRESENTATION[SYNC_STATE.ONLINE];
  const title =
    `${p.label} · last synced ${ago(status.lastSyncAt)}` +
    (status.pendingCount ? ` · ${status.pendingCount} pending` : "") +
    (status.conflictCount ? ` · ${status.conflictCount} conflicts` : "");

  return (
    <button
      onClick={() => sync()}
      title={title}
      aria-label={title}
      className="btn btn-ghost"
      style={{ padding: "5px 10px", gap: 6, borderColor: "transparent", fontSize: 12.5 }}
    >
      <span aria-hidden="true">{p.dot}</span>
      {!compact && <span style={{ color: p.tone, fontWeight: 600 }}>{p.label}</span>}
      {status.pendingCount > 0 && (
        <span
          className="num"
          style={{
            background: "var(--warn-bg)", color: "var(--warn)",
            borderRadius: 999, padding: "1px 7px", fontWeight: 700, fontSize: 11.5,
          }}
        >
          {status.pendingCount}
        </span>
      )}
    </button>
  );
}

/** Full-width banner shown while offline so the state is unmissable. */
export function OfflineBanner() {
  const [status, setStatus] = useState({ state: SYNC_STATE.ONLINE });
  useEffect(() => subscribe(setStatus), []);

  if (status.state !== SYNC_STATE.OFFLINE) return null;

  return (
    <div
      role="status"
      style={{
        background: "var(--danger-bg)", color: "var(--danger)",
        padding: "7px var(--page-pad)", fontSize: 13, fontWeight: 600,
        display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap",
      }}
    >
      <span aria-hidden="true">🔴</span>
      Working offline — your changes are saved on this device and will sync automatically.
      {status.pendingCount > 0 && <span className="num">({status.pendingCount} pending)</span>}
    </div>
  );
}

/** Inline notice for actions that genuinely cannot work without a network. */
export function RequiresNetwork({ what }) {
  return (
    <div className="card" style={{ padding: 20, textAlign: "center" }}>
      <div style={{ fontSize: 22, marginBottom: 6 }} aria-hidden="true">📡</div>
      <strong>Requires internet connection</strong>
      <p style={{ margin: "6px 0 0", color: "var(--ink-soft)", fontSize: 13.5 }}>
        {what} talks to live equipment, so it can't run offline. Your other work
        continues normally, and any command you queue here will be sent
        automatically once you're back online.
      </p>
    </div>
  );
}
