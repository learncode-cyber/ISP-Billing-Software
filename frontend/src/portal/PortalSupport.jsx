import { useEffect, useState } from "react";
import { portalApi } from "./portalApi";
import { useI18n } from "../i18n";
import { PageHeader, DataTable, StatusPill, FormModal, Modal } from "../components/primitives";

export function PortalSupport() {
  const { t } = useI18n();
  const [tickets, setTickets] = useState([]);
  const [creating, setCreating] = useState(false);
  const [open, setOpen] = useState(null);
  const [replies, setReplies] = useState([]);
  const [reply, setReply] = useState("");

  const load = () => portalApi.get("/tickets").then(setTickets).catch(() => setTickets([]));
  useEffect(load, []);

  const openTicket = async (tk) => {
    setOpen(tk); setReplies([]);
    try { setReplies(await portalApi.get(`/tickets/${tk.id}/replies`)); } catch { /* offline */ }
  };

  const sendReply = async () => {
    if (!reply.trim()) return;
    await portalApi.post(`/tickets/${open.id}/replies`, { message: reply });
    setReply("");
    setReplies(await portalApi.get(`/tickets/${open.id}/replies`));
  };

  const cols = [
    { key: "ticket_no", label: "Ticket", num: true, render: (r) => <strong className="num">{r.ticket_no}</strong> },
    { key: "priority", label: "Priority", render: (r) => <StatusPill status={r.priority} /> },
    { key: "note", label: "Issue" },
    { key: "status", label: t("common.status"), render: (r) => <StatusPill status={r.status} /> },
    { key: "act", label: "", align: "right", render: (r) => (
      <button className="btn btn-ghost" style={{ padding: "4px 10px", fontSize: 12 }}
        onClick={() => openTicket(r)}>{t("common.view")}</button>
    ) },
  ];

  return (
    <>
      <PageHeader
        title={t("portal.support") === "portal.support" ? "Support" : t("portal.support")}
        action={<button className="btn btn-primary" onClick={() => setCreating(true)}>+ New Complaint</button>}
      />
      <DataTable columns={cols} rows={tickets} empty="No complaints raised yet." />

      {creating && (
        <FormModal title="Raise a Complaint" submitLabel="Submit"
          fields={[
            { name: "priority", label: "Priority", type: "select", required: true,
              options: ["high", "medium", "low"], default: "medium" },
            { name: "note", label: "Describe the issue", required: true },
          ]}
          onSubmit={(v) => portalApi.post("/tickets", v)}
          onClose={(saved) => { setCreating(false); if (saved) load(); }} />
      )}

      {open && (
        <Modal title={open.ticket_no} subtitle={open.note} onClose={() => setOpen(null)}
          footer={<>
            <button className="btn btn-ghost" onClick={() => setOpen(null)}>{t("common.close")}</button>
            <button className="btn btn-primary" onClick={sendReply} disabled={!reply.trim()}>Send</button>
          </>}>
          <div style={{ maxHeight: 220, overflowY: "auto", marginBottom: 12 }}>
            {replies.length === 0
              ? <p style={{ color: "var(--ink-faint)", fontSize: 13 }}>No replies yet.</p>
              : replies.map((r) => (
                <div key={r.id} style={{
                  padding: "8px 10px", borderRadius: 6, marginBottom: 6, fontSize: 13,
                  background: r.author_type === "customer" ? "var(--info-bg)" : "var(--bg-canvas)",
                }}>
                  <div style={{ fontSize: 11, color: "var(--ink-faint)", fontWeight: 600, marginBottom: 2 }}>
                    {r.author_type === "customer" ? "You" : "Support"}
                  </div>
                  {r.message}
                </div>
              ))}
          </div>
          <textarea value={reply} onChange={(e) => setReply(e.target.value)} rows={3}
            placeholder="Type your reply…"
            style={{ width: "100%", padding: "8px 11px", border: "1px solid var(--border-strong)",
              borderRadius: 6, fontSize: 14, resize: "vertical" }} />
        </Modal>
      )}
    </>
  );
}
