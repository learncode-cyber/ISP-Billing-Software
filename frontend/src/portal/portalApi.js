// portalApi.js — API client for the customer self-service portal.
// Separate token key from the staff app so a customer session and a staff
// session can coexist in one browser without either impersonating the other.

const BASE = import.meta.env.VITE_API_BASE || "/api/v1";
let token = localStorage.getItem("arq_portal_token") || null;

export function setPortalToken(t) {
  token = t;
  if (t) localStorage.setItem("arq_portal_token", t);
  else localStorage.removeItem("arq_portal_token");
}
export const portalToken = () => token;

async function request(path, { method = "GET", body } = {}) {
  const res = await fetch(`${BASE}/portal${path}`, {
    method,
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  if (res.status === 401) { setPortalToken(null); location.href = "/portal/login"; return; }
  if (res.status === 422) {
    const d = await res.json().catch(() => ({}));
    throw new Error(Object.values(d.errors || {})[0]?.[0] || d.message || "Validation failed");
  }
  if (!res.ok) throw new Error(`Request failed (${res.status})`);
  if (res.status === 204) return null;
  return res.json();
}

export const portalApi = {
  get: (p) => request(p),
  post: (p, body) => request(p, { method: "POST", body }),
};
