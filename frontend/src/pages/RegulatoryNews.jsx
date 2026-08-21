// RegulatoryNews.jsx — BTRC regulatory news feed. Platform-level content,
// free on every plan (no feature gate) — every admin/staff can read it.
// Reads GET /api/v1/compliance/news.

import { useEffect, useState } from "react";
import { api } from "../lib/api";
import { PageHeader } from "../components/primitives";

export function RegulatoryNews() {
  const [page, setPage] = useState(null);

  useEffect(() => { api.get("/compliance/news").then(setPage).catch(() => setPage({ data: [] })); }, []);

  return (
    <>
      <PageHeader title="Regulatory News" subtitle="Latest BTRC notices and directives" />
      {!page ? (
        <div style={{ color: "var(--ink-faint)" }}>Loading…</div>
      ) : page.data.length === 0 ? (
        <div className="card" style={{ padding: 40, textAlign: "center", color: "var(--ink-faint)" }}>
          No published regulatory news yet.
        </div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          {page.data.map((n) => (
            <article key={n.id} className="card" style={{ padding: 18 }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 12 }}>
                <h3 style={{ margin: 0, fontSize: 16 }}>{n.title}</h3>
                {n.category && <span className="pill pill-info">{n.category}</span>}
              </div>
              {n.published_at && (
                <div style={{ fontSize: 12, color: "var(--ink-faint)", marginTop: 4 }}>
                  {new Date(n.published_at).toLocaleDateString("en-BD", { year: "numeric", month: "long", day: "numeric" })}
                </div>
              )}
              {n.body && <p style={{ margin: "10px 0 0", fontSize: 13.5, color: "var(--ink-soft)", lineHeight: 1.6 }}>{n.body}</p>}
              {n.source_url && (
                <a href={n.source_url} target="_blank" rel="noreferrer"
                  style={{ display: "inline-flex", alignItems: "center", minHeight: 44,
                    marginTop: 6, fontSize: 13, color: "var(--primary)", fontWeight: 600 }}>
                  Read on BTRC →
                </a>
              )}
            </article>
          ))}
        </div>
      )}
    </>
  );
}
