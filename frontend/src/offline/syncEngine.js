// syncEngine.js — drains the outbox to the server and pulls fresh read
// models down. Runs on: app start, the browser `online` event, a periodic
// timer, and Background Sync where the platform supports it.
//
// Deliberately NOT dependent on Background Sync alone — support varies
// across browsers, so the foreground `online` listener is the primary path
// and Background Sync is an enhancement.

import { api, rawRequest } from "../lib/api";
import { STORES, putAll, meta } from "./db";
import * as outbox from "./outbox";

export const SYNC_STATE = {
  ONLINE: "online",
  OFFLINE: "offline",
  SYNCING: "syncing",
  ERROR: "error",
  CONFLICTS: "conflicts",
};

const listeners = new Set();
let state = navigator.onLine ? SYNC_STATE.ONLINE : SYNC_STATE.OFFLINE;
let syncing = false;

export function subscribe(fn) {
  listeners.add(fn);
  fn(getStatus());
  return () => listeners.delete(fn);
}

function emit() {
  const s = getStatus();
  listeners.forEach((fn) => fn(s));
}

let lastSyncAt = null;
let pendingCount = 0;
let conflictCount = 0;

export function getStatus() {
  return { state, lastSyncAt, pendingCount, conflictCount, online: navigator.onLine };
}

async function refreshCounts() {
  pendingCount = await outbox.pendingCount();
  conflictCount = (await outbox.conflicts()).length;
  if (conflictCount > 0 && state === SYNC_STATE.ONLINE) state = SYNC_STATE.CONFLICTS;
}

/** Pull server read models into IndexedDB so the app works offline next time. */
export async function pullAll() {
  const pulls = [
    ["/customers", STORES.customers, (r) => r.data || []],
    ["/tickets", STORES.tickets, (r) => r.data?.data || []],
    ["/employees", STORES.employees, (r) => (Array.isArray(r) ? r : [])],
    ["/inventory/products", STORES.products, (r) => r.data || []],
    ["/config/packages", STORES.packages, (r) => (Array.isArray(r) ? r : [])],
    ["/config/zones", STORES.zones, (r) => (Array.isArray(r) ? r : [])],
    ["/compliance/news", STORES.news, (r) => r.data || []],
  ];

  for (const [path, store, extract] of pulls) {
    try {
      const res = await api.get(path);
      await putAll(store, extract(res));
    } catch {
      // A single endpoint failing (e.g. not on this tenant's plan) must not
      // abort the whole sync — skip it and continue.
    }
  }

  try {
    const dash = await api.get("/dashboard");
    await putAll(STORES.dashboard, [{ id: "current", ...dash }]);
  } catch { /* non-fatal */ }

  lastSyncAt = new Date().toISOString();
  await meta("last_sync_at", lastSyncAt);
}

/**
 * Push the outbox. Each operation carries its idempotency key, so a retry
 * after an unseen success is safe — the server returns the original result.
 */
export async function pushOutbox() {
  const ops = await outbox.pending();
  for (const op of ops) {
    const spec = outbox.OPS[op.op_type];
    if (!spec) { await outbox.markStatus(op.id, outbox.STATUS.FAILED, "unknown op type"); continue; }

    await outbox.markStatus(op.id, outbox.STATUS.SYNCING);
    try {
      const res = await rawRequest(spec.path(op), {
        method: spec.method,
        body: op.payload,
        headers: {
          "Idempotency-Key": op.idempotency_key,
          "X-Device-Id": op.device_id,
          ...(op.base_revision ? { "If-Match-Revision": String(op.base_revision) } : {}),
        },
      });

      if (res.status === 409) {
        // Server holds a newer revision. Never overwrite — surface it.
        const body = await res.json().catch(() => ({}));
        await outbox.markStatus(op.id, outbox.STATUS.CONFLICT,
          body.message || "Server has a newer version of this record.");
        continue;
      }
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        await outbox.markStatus(op.id, outbox.STATUS.FAILED, body.message || `HTTP ${res.status}`);
        continue;
      }

      await outbox.complete(op.id);
    } catch (e) {
      // Network died mid-drain: leave it pending and stop; we'll resume.
      await outbox.markStatus(op.id, outbox.STATUS.PENDING, e.message);
      break;
    }
  }
}

export async function sync({ pull = true } = {}) {
  if (syncing || !navigator.onLine) return;
  syncing = true;
  state = SYNC_STATE.SYNCING;
  emit();

  try {
    await pushOutbox();     // push first: local intent wins the race to the server
    if (pull) await pullAll();
    await refreshCounts();
    state = conflictCount > 0 ? SYNC_STATE.CONFLICTS : SYNC_STATE.ONLINE;
  } catch {
    state = SYNC_STATE.ERROR;
  } finally {
    syncing = false;
    emit();
  }
}

/** Wire up connectivity listeners. Called once from App. */
export function initSync() {
  window.addEventListener("online", () => { state = SYNC_STATE.ONLINE; emit(); sync(); });
  window.addEventListener("offline", () => { state = SYNC_STATE.OFFLINE; emit(); });

  meta("last_sync_at").then((v) => { lastSyncAt = v; emit(); });
  refreshCounts().then(emit);

  // Periodic retry while online — covers the case where `online` fires but
  // the connection is still unusable (captive portals, flaky mobile data).
  setInterval(() => { if (navigator.onLine) sync({ pull: false }); }, 60000);

  // Background Sync as an enhancement only.
  if ("serviceWorker" in navigator && "SyncManager" in window) {
    navigator.serviceWorker.ready
      .then((reg) => reg.sync.register("arq-outbox-sync"))
      .catch(() => { /* unsupported — foreground path already covers us */ });
  }

  if (navigator.onLine) sync();
}

export async function notifyMutation() {
  await refreshCounts();
  emit();
  if (navigator.onLine) sync({ pull: false });
}
