// fileQueue.js — offline capture queue for technician photos, customer
// signatures, and installation/repair evidence.
//
// Files are stored as Blobs in IndexedDB (not base64 strings in
// localStorage — that would blow the 5 MB quota on the second photo) and
// uploaded automatically when connectivity returns, with progress, retry
// and failure states surfaced to the UI.

import { STORES, put, all, remove, get, deviceId } from "./db";

export const FILE_STATUS = {
  QUEUED: "queued",
  UPLOADING: "uploading",
  UPLOADED: "uploaded",
  FAILED: "failed",
};

/** Queue a captured file. Returns the local record (with an object URL the
 *  UI can preview immediately, offline). */
export async function queueFile(blob, { kind, relatedType, relatedId, filename } = {}) {
  const id = crypto.randomUUID();
  const record = {
    id,
    idempotency_key: crypto.randomUUID(),
    device_id: await deviceId(),
    kind,                 // 'before_photo' | 'after_photo' | 'signature' | 'document'
    related_type: relatedType, // 'field_job' | 'ticket' | 'customer'
    related_id: relatedId,
    filename: filename || `${kind}-${Date.now()}`,
    size: blob.size,
    mime: blob.type,
    blob,                 // IndexedDB stores Blobs natively
    status: FILE_STATUS.QUEUED,
    attempts: 0,
    progress: 0,
    created_at: new Date().toISOString(),
  };
  await put(STORES.files, id, record);
  return record;
}

export async function queued() {
  const rows = await all(STORES.files);
  return rows.filter((f) => f.status === FILE_STATUS.QUEUED || f.status === FILE_STATUS.FAILED);
}

export async function allFiles() {
  return all(STORES.files);
}

export async function setStatus(id, status, extra = {}) {
  const row = await get(STORES.files, id);
  if (!row) return;
  await put(STORES.files, id, { ...row, status, ...extra });
}

/** Preview URL for an offline-captured file (revoke after use). */
export function previewUrl(record) {
  return record?.blob ? URL.createObjectURL(record.blob) : null;
}

/**
 * Upload every queued file. Called by the sync engine after the outbox
 * drains, so a photo attaches to a field job that itself may only just
 * have been created on the server.
 */
export async function uploadQueued(baseUrl, token) {
  const files = await queued();
  for (const f of files) {
    await setStatus(f.id, FILE_STATUS.UPLOADING, { progress: 0 });
    try {
      const form = new FormData();
      form.append("file", f.blob, f.filename);
      form.append("kind", f.kind);
      form.append("related_type", f.related_type);
      form.append("related_id", f.related_id);

      const res = await fetch(`${baseUrl}/uploads`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Idempotency-Key": f.idempotency_key, // same file never stored twice
          "X-Device-Id": f.device_id,
        },
        body: form,
      });

      if (res.ok) {
        await setStatus(f.id, FILE_STATUS.UPLOADED, { progress: 100 });
        await remove(STORES.files, f.id); // free the Blob once it's safely server-side
      } else {
        await setStatus(f.id, FILE_STATUS.FAILED, {
          attempts: (f.attempts || 0) + 1,
          last_error: `HTTP ${res.status}`,
        });
      }
    } catch (e) {
      await setStatus(f.id, FILE_STATUS.FAILED, {
        attempts: (f.attempts || 0) + 1,
        last_error: e.message,
      });
      break; // network gone again — resume on next reconnect
    }
  }
}
