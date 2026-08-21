// repository.js — the single data access layer every page uses.
//
// Read:  online → fetch + refresh cache;  offline → serve from IndexedDB.
// Write: ALWAYS through the outbox. There is exactly one write path, so an
//        operation behaves identically whether the device was online or not
//        at the moment the user pressed the button. Online just means the
//        queue drains immediately.
//
// This is what "offline-first" means in practice: the local database is the
// source of truth for the UI, and the server is a peer that it syncs with.

import { api } from "../lib/api";
import { STORES, all, get as dbGet, putAll, put } from "./db";
import * as outbox from "./outbox";
import { notifyMutation } from "./syncEngine";

/** Operations that fundamentally need a live connection (spec §Offline
 *  limitations). The UI shows "Requires internet connection" for these
 *  rather than pretending they worked. */
export const ONLINE_ONLY = {
  "mikrotik.live_sessions": "Live PPPoE session data",
  "mikrotik.sync": "Router synchronisation",
  "olt.check_connection": "OLT connection test",
  "olt.discover": "ONU discovery (SNMP)",
  "network.monitoring": "Live network monitoring",
  "radius.auth": "RADIUS live authentication",
  "payment.gateway": "Online payment authorisation",
  "btrc.ingest": "BTRC live news ingestion",
  "ai.ask": "AI analytics",
};

export function requiresNetwork(key) {
  return Boolean(ONLINE_ONLY[key]);
}

export function isOnline() {
  return navigator.onLine;
}

// ── READS ──────────────────────────────────────────────────────────────

async function readList(path, store, extract, params) {
  if (navigator.onLine) {
    try {
      const res = await api.get(path, params);
      const rows = extract(res);
      await putAll(store, rows);
      return { rows, fromCache: false, total: res.total ?? rows.length };
    } catch {
      // Fall through to cache — a failed request offline-in-practice
      // should still show the user their data.
    }
  }
  try {
    const rows = await all(store);
    return { rows, fromCache: true, total: rows.length };
  } catch {
    // No local database (e.g. no tenant bound yet) — degrade to empty
    // rather than throwing an unhandled rejection into the page.
    return { rows: [], fromCache: true, total: 0, unavailable: true };
  }
}

export const repo = {
  customers: (params) => readList("/customers", STORES.customers, (r) => r.data || [], params),
  tickets: () => readList("/tickets", STORES.tickets, (r) => r.data?.data || []),
  employees: () => readList("/employees", STORES.employees, (r) => (Array.isArray(r) ? r : [])),
  products: () => readList("/inventory/products", STORES.products, (r) => r.data || []),
  news: () => readList("/compliance/news", STORES.news, (r) => r.data || []),
  packages: () => readList("/config/packages", STORES.packages, (r) => (Array.isArray(r) ? r : [])),
  zones: () => readList("/config/zones", STORES.zones, (r) => (Array.isArray(r) ? r : [])),

  async dashboard() {
    if (navigator.onLine) {
      try {
        const d = await api.get("/dashboard");
        await putAll(STORES.dashboard, [{ id: "current", ...d }]);
        return { data: d, fromCache: false };
      } catch { /* fall through */ }
    }
    try {
      const row = await dbGet(STORES.dashboard, "current");
      return { data: row || {}, fromCache: true };
    } catch {
      return { data: {}, fromCache: true, unavailable: true };
    }
  },

  /** Local search over the cached customer set — works with zero network. */
  async searchCustomers(term) {
    let rows = [];
    try { rows = await all(STORES.customers); } catch { return []; }
    if (!term) return rows;
    const t = term.toLowerCase();
    return rows.filter((c) =>
      [c.full_name, c.mobile, c.customer_code, c.email]
        .filter(Boolean)
        .some((v) => String(v).toLowerCase().includes(t))
    );
  },
};

// ── WRITES (always via outbox) ─────────────────────────────────────────

/**
 * Queue a mutation and optimistically update the local cache so the UI
 * reflects it immediately, offline or not.
 */
export async function mutate(opType, { payload, targetId, optimistic } = {}) {
  const spec = outbox.OPS[opType];
  if (!spec) throw new Error(`Unknown operation: ${opType}`);

  if (spec.requiresNetwork && !navigator.onLine) {
    // Still queued — the intent is preserved and dispatched on reconnect —
    // but the caller is told so the UI can say so honestly.
    const op = await outbox.enqueue(opType, { payload, targetId });
    await notifyMutation();
    return { op, queuedForNetwork: true };
  }

  const op = await outbox.enqueue(opType, { payload, targetId });

  // Optimistic local write so the record appears instantly.
  if (optimistic && spec.store) {
    const localId = targetId || op.id;
    const existing = targetId ? await dbGet(spec.store, targetId) : null;
    await put(spec.store, localId, {
      ...(existing || {}),
      ...optimistic,
      id: localId,
      _pendingSync: true,
    });
  }

  await notifyMutation();
  return { op, queuedForNetwork: false };
}
