import { useEffect, useState } from "react";
import { api } from "../lib/api";
import { PageHeader } from "../components/primitives";

export function NetworkDiagram() {
  const [graph, setGraph] = useState(null);
  useEffect(() => { api.get("/network/diagram").then(setGraph).catch(() => setGraph({ nodes: [], edges: [] })); }, []);
  return (
    <>
      <PageHeader title="Network Diagram" subtitle="Router → OLT → PON → ONU → Customer" />
      <div className="card" style={{ padding: 20, minHeight: 300 }}>
        {!graph ? <div style={{ color: "var(--ink-faint)" }}>Loading topology…</div>
          : graph.nodes.length === 0 ? (
            <div style={{ textAlign: "center", color: "var(--ink-faint)", padding: 40 }}>
              No topology yet — register routers/OLTs and link customers to see the live graph.
            </div>
          ) : (
            <div style={{ display: "flex", flexWrap: "wrap", gap: 10 }}>
              {graph.nodes.map((n) => (
                <div key={`${n.type}:${n.id}`} className="pill pill-info" style={{ fontSize: 13, padding: "6px 12px" }}>
                  {n.type}: {n.label}
                </div>
              ))}
            </div>
          )}
      </div>
    </>
  );
}
