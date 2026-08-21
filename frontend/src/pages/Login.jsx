// Login.jsx — staff authentication. POSTs to /api/v1/auth/login (returns
// a Sanctum token), stores it, then the app loads /me/capabilities.

import { useState } from "react";
import { api, setToken } from "../lib/api";
import { setActiveTenant } from "../offline/db";

export function Login() {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true); setError(null);
    try {
      const res = await api.post("/auth/login", { username, password });
      setToken(res.token);
      // Bind the local database to this tenant BEFORE any data is cached.
      // If a different tenant used this device, their local database is
      // destroyed here — offline data never crosses tenants.
      await setActiveTenant(res.user?.tenant_id);
      location.href = "/";
    } catch {
      setError("Invalid username or password.");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div style={{ minHeight: "100vh", display: "grid", placeItems: "center", padding: 16, background: "var(--bg-shell)" }}>
      <form onSubmit={submit} className="card" style={{ width: "min(360px, 100%)", padding: "clamp(20px, 5vw, 30px)" }}>
        <div style={{ fontWeight: 700, fontSize: 18 }}>AR Qudrix</div>
        <div style={{ fontSize: 12, color: "var(--ink-faint)", textTransform: "uppercase", letterSpacing: "0.05em", marginBottom: 22 }}>
          ISP Operating System
        </div>

        {error && (
          <div style={{ background: "var(--danger-bg)", color: "var(--danger)", padding: "9px 12px", borderRadius: 6, fontSize: 13, marginBottom: 14 }}>
            {error}
          </div>
        )}

        <label style={lbl}>Username</label>
        <input value={username} onChange={(e) => setUsername(e.target.value)} style={inp} autoFocus />
        <label style={lbl}>Password</label>
        <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} style={inp} />

        <button className="btn btn-primary" style={{ width: "100%", justifyContent: "center", marginTop: 8 }} disabled={busy}>
          {busy ? "Signing in…" : "Sign in"}
        </button>
      </form>
    </div>
  );
}

const lbl = { display: "block", fontSize: 12, fontWeight: 600, color: "var(--ink-soft)", margin: "12px 0 5px" };
const inp = { width: "100%", padding: "9px 12px", border: "1px solid var(--border-strong)", borderRadius: 6, fontSize: 14 };
