// outbox.js — the offline mutation queue.
//
// Every mutation made while offline (and, deliberately, while online too —
// so there is exactly ONE write path) gets:
//   • a local UUID so the UI can show it immediately
//   • an idempotency_key so the server processes it exactly once even if
//     the device retries after a timeout it never saw the answer to
//   • a device_id + base_revision for conflict detection
//
// This is what makes a duplicate payment technically impossible: the retry
// carries the same idempotency_key, and the server returns the original
// result instead of charging again.

import { STORES, put, all, remove, get, deviceId } from "./db";

export const OPS = {
  CREATE_CUSTOMER: { method: "POST", path: () => "/customers", store: STORES.customers },
  UPDATE_CUSTOMER: { method: "PATCH", path: (o) => `/customers/${o.targetId}`, store: STORES.customers },
  CREATE_PAYMENT: { method: "POST", path: (o) => `/invoices/${o.targetId}/payments`, store: STORES.invoices },
  CREATE_TICKET: { method: "POST", path: () => "/tickets", store: STORES.tickets },
  UPDATE_TICKET: { method: "PATCH", path: (o) => `/tickets/${o.targetId}/status`, store: STORES.tickets },
  CREATE_FIELD_JOB_CHECKIN: { method: "POST", path: (o) => `/field-jobs/${o.targetId}/check-in`, store: STORES.fieldJobs },
  CREATE_FIELD_JOB_CHECKOUT: { method: "POST", path: (o) => `/field-jobs/${o.targetId}/check-out`, store: STORES.fieldJobs },
  CREATE_LEAD: { method: "POST", path: () => "/leads", store: null },
  CREATE_EXPENSE: { method: "POST", path: () => "/expenses", store: null },
  CREATE_EMPLOYEE: { method: "POST", path: () => "/employees", store: STORES.employees },
  PAY_SALARY: { method: "POST", path: (o) => `/employees/${o.targetId}/pay-salary`, store: null },
  UPDATE_INVENTORY: { method: "POST", path: () => "/inventory/products", store: STORES.products },
  CREATE_RESELLER: { method: "POST", path: () => "/resellers", store: null },
  CREATE_AUTOMATION_RULE: { method: "POST", path: () => "/automation-rules", store: null },
  // Queued network commands — cannot execute offline, but the intent is
  // recorded and dispatched the moment connectivity returns.
  MIKROTIK_DISCONNECT: { method: "POST", path: (o) => `/network/pppoe-secrets/${o.targetId}/disconnect`, store: null, requiresNetwork: true },
  MIKROTIK_RECONNECT: { method: "POST", path: (o) => `/network/pppoe-secrets/${o.targetId}/reconnect`, store: null, requiresNetwork: true },
};

export const STATUS = {
  PENDING: "pending",
  SYNCING: "syncing",
  FAILED: "failed",
  CONFLICT: "conflict",
};

/**
 * Enqueue a mutation. Returns the local operation record so the caller can
 * optimistically render it before the server has ever seen it.
 */
export async function enqueue(opType, { payload = {}, targetId = null, baseRevision = null } = {}) {
  if (!OPS[opType]) throw new Error(`Unknown operation type: ${opType}`);

  const op = {
    id: crypto.randomUUID(),               // local UUID
    idempotency_key: crypto.randomUUID(),  // server-side exactly-once key
    device_id: await deviceId(),
    op_type: opType,
    target_id: targetId,
    base_revision: baseRevision,           // server revision the edit was based on
    payload,
    status: STATUS.PENDING,
    attempts: 0,
    last_error: null,
    created_at: new Date().toISOString(),
  };

  await put(STORES.outbox, op.id, op);
  return op;
}

export async function pending() {
  const rows = await all(STORES.outbox);
  return rows
    .filter((o) => o.status === STATUS.PENDING || o.status === STATUS.FAILED)
    .sort((a, b) => a.created_at.localeCompare(b.created_at)); // FIFO — order matters
}

export async function pendingCount() {
  return (await pending()).length;
}

export async function conflicts() {
  const rows = await all(STORES.outbox);
  return rows.filter((o) => o.status === STATUS.CONFLICT);
}

export async function markStatus(opId, status, error = null) {
  const row = await get(STORES.outbox, opId);
  if (!row) return;
  await put(STORES.outbox, opId, {
    ...row,
    status,
    last_error: error,
    attempts: status === STATUS.FAILED ? (row.attempts || 0) + 1 : row.attempts,
  });
}

export async function complete(opId) {
  await remove(STORES.outbox, opId);
}

/** Resolve a conflict: keep-mine re-queues with the server's revision;
 *  keep-server discards the local change. Never silently overwrites. */
export async function resolveConflict(opId, resolution, serverRevision = null) {
  const row = await get(STORES.outbox, opId);
  if (!row) return;
  if (resolution === "keep_server") {
    await remove(STORES.outbox, opId);
  } else {
    await put(STORES.outbox, opId, {
      ...row,
      base_revision: serverRevision,
      status: STATUS.PENDING,
      last_error: null,
      idempotency_key: crypto.randomUUID(), // new intent, new key
    });
  }
}
