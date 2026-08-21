import { useState } from "react";
import { api } from "../lib/api";
import { PageHeader } from "../components/primitives";

export function AiAssistant() {
  const [question, setQuestion] = useState("");
  const [answer, setAnswer] = useState(null);
  const [busy, setBusy] = useState(false);
  const ask = async () => {
    if (!question.trim()) return;
    setBusy(true); setAnswer(null);
    try { setAnswer(await api.post("/ai/ask", { question })); }
    catch (e) { setAnswer({ answer: e.message }); }
    finally { setBusy(false); }
  };
  const examples = ["Which zone had the highest churn this month?", "Total collected this month", "How many active customers?"];
  return (
    <>
      <PageHeader title="AI Assistant" subtitle="Ask about your business in plain language" />
      <div className="card" style={{ padding: 20 }}>
        <div style={{ display: "flex", gap: 8 }}>
          <input value={question} onChange={(e) => setQuestion(e.target.value)} onKeyDown={(e) => e.key === "Enter" && ask()}
            placeholder="Ask a question…" style={{ flex: 1, padding: "10px 12px", border: "1px solid var(--border-strong)", borderRadius: 6, fontSize: 14 }} />
          <button className="btn btn-primary" onClick={ask} disabled={busy}>{busy ? "Thinking…" : "Ask"}</button>
        </div>
        <div style={{ display: "flex", gap: 6, marginTop: 10, flexWrap: "wrap" }}>
          {examples.map((ex) => <button key={ex} className="btn btn-ghost" style={{ fontSize: 12, padding: "4px 10px" }} onClick={() => setQuestion(ex)}>{ex}</button>)}
        </div>
        {answer && (
          <div style={{ marginTop: 18, padding: 16, background: "var(--bg-canvas)", borderRadius: 8, fontSize: 14 }}>
            {answer.answer}
          </div>
        )}
      </div>
      <p style={{ fontSize: 12, color: "var(--ink-faint)", marginTop: 12 }}>
        Answers stay within your organisation’s data and your permissions.
      </p>
    </>
  );
}
