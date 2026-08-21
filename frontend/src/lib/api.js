// api.js — single axios-style fetch wrapper for the /api/v1 surface.
// Handles bearer auth, JSON, and the 402-vs-403 distinction the backend
// deliberately returns (402 = feature not on plan, 403 = no permission).

const BASE = import.meta.env.VITE_API_BASE || "/api/v1";

let authToken = localStorage.getItem("arq_token") || null;

export function setToken(token) {
  authToken = token;
  if (token) localStorage.setItem("arq_token", token);
  else localStorage.removeItem("arq_token");
}

async function request(path, { method = "GET", body, params } = {}) {
  const url = new URL(BASE + path, window.location.origin);
  if (params) Object.entries(params).forEach(([k, v]) => v != null && url.searchParams.set(k, v));

  const res = await fetch(url, {
    method,
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      ...(authToken ? { Authorization: `Bearer ${authToken}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  if (res.status === 402) {
    const err = new Error("This feature is not included in your subscription plan.");
    err.code = "PLAN_REQUIRED";
    throw err;
  }
  if (res.status === 403) {
    const err = new Error("You do not have permission to perform this action.");
    err.code = "FORBIDDEN";
    throw err;
  }
  if (res.status === 401) {
    setToken(null);
    window.location.href = "/login";
    return;
  }
  if (!res.ok) {
    const err = new Error(`Request failed (${res.status})`);
    err.code = "REQUEST_FAILED";
    err.status = res.status;
    throw err;
  }
  if (res.status === 204) return null;
  return res.json();
}

/** Raw request returning the Response object — the sync engine needs the
 *  status code (notably 409 Conflict) rather than a thrown error. */
export async function rawRequest(path, { method = "GET", body, headers = {} } = {}) {
  return fetch(BASE + path, {
    method,
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      ...(authToken ? { Authorization: `Bearer ${authToken}` } : {}),
      ...headers,
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

export const api = {
  get: (path, params) => request(path, { params }),
  post: (path, body) => request(path, { method: "POST", body }),
  patch: (path, body) => request(path, { method: "PATCH", body }),
  del: (path) => request(path, { method: "DELETE" }),
};
