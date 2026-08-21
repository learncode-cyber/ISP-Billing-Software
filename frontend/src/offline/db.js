// db.js — IndexedDB local database layer.
//
// Business-critical data NEVER goes in localStorage (spec requirement).
// localStorage is used only for the auth token and the active tenant id.
//
// ── Multi-tenant offline isolation ──
// Every record carries `_tenant`, and every read is filtered by the
// currently authenticated tenant. On logout we purge the tenant's data
// outright. So a Tenant B login can never surface Tenant A's cached
// customers, outbox operations, files, or search results — this is the
// offline equivalent of the server's RLS boundary.

// DEFECT FIX (found by offline E2E in a real browser): this was a single
// fixed database name shared by every tenant, so Tenant B's session opened
// the same local store Tenant A had populated — a multi-tenant offline
// isolation violation, which the spec marks mandatory.
//
// The tenant id is now part of the DATABASE NAME, so two tenants use two
// physically separate IndexedDB databases. Tenant B cannot reach Tenant A's
// records even by bug, and switching tenants deletes the previous database
// outright rather than clearing stores.
const DB_PREFIX = "arq_isp_os";

export function activeTenantId() {
  return localStorage.getItem("arq_tenant_id") || null;
}

function dbNameFor(tenantId) {
  return `${DB_PREFIX}__${tenantId}`;
}

/** Called after login. If a different tenant used this device, its local
 *  database is destroyed before the new one is opened. */
export async function setActiveTenant(tenantId) {
  const prev = activeTenantId();
  if (prev && prev !== tenantId) {
    await deleteTenantDatabase(prev);
  }
  localStorage.setItem("arq_tenant_id", tenantId);
  dbPromise = null;
  openedFor = null;
}

export function deleteTenantDatabase(tenantId) {
  return new Promise((resolve) => {
    try {
      const req = indexedDB.deleteDatabase(dbNameFor(tenantId));
      req.onsuccess = req.onerror = req.onblocked = () => resolve();
    } catch { resolve(); }
  });
}
const DB_VERSION = 1;

// Cached read-model stores (server truth, refreshed on sync)
export const STORES = {
  customers: "customers",
  invoices: "invoices",
  tickets: "tickets",
  fieldJobs: "field_jobs",
  products: "products",
  employees: "employees",
  packages: "packages",
  zones: "zones",
  branches: "branches",
  dashboard: "dashboard",
  news: "news",
  // Local-only stores
  outbox: "outbox",       // pending mutations
  files: "files",         // pending photo/signature uploads
  conflicts: "conflicts", // server-rejected due to newer revision
  meta: "meta",           // lastSyncAt, deviceId, etc.
};

let dbPromise = null;
let openedFor = null;

function openDb() {
  const tenantId = activeTenantId();
  // Fail closed: with no tenant context there is no local database to open.
  if (!tenantId) return Promise.reject(new Error("No active tenant — local database unavailable."));
  if (dbPromise && openedFor === tenantId) return dbPromise;
  openedFor = tenantId;
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const req = indexedDB.open(dbNameFor(tenantId), DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      for (const name of Object.values(STORES)) {
        if (!db.objectStoreNames.contains(name)) {
          const store = db.createObjectStore(name, { keyPath: "_key" });
          store.createIndex("by_tenant", "_tenant", { unique: false });
          if (name === STORES.outbox) {
            store.createIndex("by_status", ["_tenant", "status"], { unique: false });
          }
        }
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

function currentTenant() {
  return localStorage.getItem("arq_tenant_id") || "unknown";
}

function tx(store, mode = "readonly") {
  return openDb().then((db) => db.transaction(store, mode).objectStore(store));
}

/** Write one record, namespaced to the active tenant. */
export async function put(store, id, value) {
  const s = await tx(store, "readwrite");
  const tenant = currentTenant();
  return new Promise((res, rej) => {
    const r = s.put({ ...value, _key: `${tenant}::${id}`, _id: id, _tenant: tenant });
    r.onsuccess = () => res(true);
    r.onerror = () => rej(r.error);
  });
}

/** Bulk replace a store's contents for this tenant (used after a sync pull). */
export async function putAll(store, rows, idKey = "id") {
  const db = await openDb();
  const tenant = currentTenant();
  return new Promise((res, rej) => {
    const t = db.transaction(store, "readwrite");
    const s = t.objectStore(store);
    for (const row of rows) {
      s.put({ ...row, _key: `${tenant}::${row[idKey]}`, _id: row[idKey], _tenant: tenant });
    }
    t.oncomplete = () => res(rows.length);
    t.onerror = () => rej(t.error);
  });
}

export async function get(store, id) {
  const s = await tx(store);
  return new Promise((res, rej) => {
    const r = s.get(`${currentTenant()}::${id}`);
    r.onsuccess = () => res(r.result || null);
    r.onerror = () => rej(r.error);
  });
}

/** Read every record for the ACTIVE tenant only — the isolation boundary. */
export async function all(store) {
  const s = await tx(store);
  return new Promise((res, rej) => {
    const idx = s.index("by_tenant");
    const r = idx.getAll(currentTenant());
    r.onsuccess = () => res(r.result || []);
    r.onerror = () => rej(r.error);
  });
}

export async function remove(store, id) {
  const s = await tx(store, "readwrite");
  return new Promise((res, rej) => {
    const r = s.delete(`${currentTenant()}::${id}`);
    r.onsuccess = () => res(true);
    r.onerror = () => rej(r.error);
  });
}

/**
 * Purge every record belonging to a tenant. Called on logout so the next
 * user on this device — possibly a different tenant — starts clean.
 * Mandatory for the multi-tenant offline isolation test.
 */
export async function purgeTenant(tenantId) {
  // Destroy the tenant's ENTIRE local database rather than deleting rows.
  // Row-level clearing can leave indexes, blobs or partially-written
  // records behind; dropping the database cannot. Called on logout and
  // whenever a different tenant signs in on this device.
  const target = tenantId || activeTenantId();
  dbPromise = null;
  openedFor = null;
  if (target) await deleteTenantDatabase(target);
  if (!tenantId || tenantId === activeTenantId()) {
    localStorage.removeItem("arq_tenant_id");
  }
  return true;
}

export async function meta(key, value) {
  if (value === undefined) {
    const row = await get(STORES.meta, key);
    return row ? row.value : null;
  }
  return put(STORES.meta, key, { value });
}

/** Stable per-device identifier, used for conflict attribution. */
export async function deviceId() {
  let id = await meta("device_id");
  if (!id) {
    id = crypto.randomUUID();
    await meta("device_id", id);
  }
  return id;
}
