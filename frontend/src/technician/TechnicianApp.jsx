// TechnicianApp.jsx — field technician PWA.
//
// Offline-first by necessity: technicians work in stairwells, rooftops and
// basements where there is no signal. Every job action writes to the local
// outbox first and syncs later; photos and signatures go to the file queue
// as blobs. Nothing here blocks on connectivity except the map link.
//
// GPS degrades gracefully: if geolocation is denied or unavailable the
// check-in still succeeds and is flagged as location-unavailable rather
// than failing the technician's work.

import { useEffect, useRef, useState } from "react";
import { api } from "../lib/api";
import { useI18n, LanguageToggle } from "../i18n";
import { StatusPill, Modal } from "../components/primitives";
import { Icon } from "../components/Icon";
import { mutate } from "../offline/repository";
import { queueFile, previewUrl } from "../offline/fileQueue";
import { SyncStatus, OfflineBanner } from "../components/SyncStatus";

export function TechnicianApp() {
  const { lang } = useI18n();
  const [jobs, setJobs] = useState([]);
  const [active, setActive] = useState(null);
  const [loading, setLoading] = useState(true);

  const load = () => {
    setLoading(true);
    api.get("/field-jobs/mine")
      .then((r) => setJobs(Array.isArray(r) ? r : r.data || []))
      .catch(() => setJobs([]))
      .finally(() => setLoading(false));
  };
  useEffect(() => { load(); }, []);

  if (active) return <JobDetail job={active} onBack={() => { setActive(null); load(); }} />;

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg-canvas)" }}>
      <Header title={lang === "bn" ? "আমার কাজ" : "My Jobs"} />
      <main style={{ padding: "16px var(--page-pad)", maxWidth: 720, margin: "0 auto" }}>
        <OfflineBanner />

        {loading ? (
          <Empty>{lang === "bn" ? "লোড হচ্ছে…" : "Loading…"}</Empty>
        ) : jobs.length === 0 ? (
          <Empty>{lang === "bn" ? "আপনার জন্য কোনো কাজ বরাদ্দ নেই।" : "No jobs assigned to you."}</Empty>
        ) : (
          jobs.map((j) => (
            <button key={j.id} onClick={() => setActive(j)}
              style={{
                display: "block", width: "100%", textAlign: "left", cursor: "pointer",
                background: "#fff", border: "1px solid var(--border)", borderRadius: "var(--radius)",
                padding: 14, marginBottom: 10, boxShadow: "var(--shadow-card)",
              }}>
              <div style={{ display: "flex", justifyContent: "space-between", gap: 10, alignItems: "flex-start" }}>
                <div style={{ minWidth: 0 }}>
                  <div style={{ fontWeight: 700, fontSize: 15 }}>
                    {JOB_LABEL[j.job_type]?.[lang] || j.job_type}
                  </div>
                  <div style={{ fontSize: 13, color: "var(--ink-soft)", marginTop: 2 }}>
                    {j.customer_name || j.customer_id}
                  </div>
                  {j.address && (
                    <div style={{ fontSize: 12.5, color: "var(--ink-faint)", marginTop: 4 }}>{j.address}</div>
                  )}
                </div>
                <StatusPill status={j.status} />
              </div>
            </button>
          ))
        )}
      </main>
    </div>
  );
}

const JOB_LABEL = {
  installation: { en: "Installation", bn: "নতুন সংযোগ" },
  repair: { en: "Repair", bn: "মেরামত" },
  maintenance: { en: "Maintenance", bn: "রক্ষণাবেক্ষণ" },
};

function JobDetail({ job, onBack }) {
  const { lang } = useI18n();
  const [status, setStatus] = useState(job.status);
  const [note, setNote] = useState("");
  const [photos, setPhotos] = useState([]);
  const [signing, setSigning] = useState(false);
  const [signature, setSignature] = useState(null);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState(null);

  /** Geolocation with graceful degradation — never blocks the workflow. */
  const getPosition = () =>
    new Promise((resolve) => {
      if (!navigator.geolocation) return resolve(null);
      const timer = setTimeout(() => resolve(null), 8000);
      navigator.geolocation.getCurrentPosition(
        (pos) => { clearTimeout(timer); resolve({ lat: pos.coords.latitude, lng: pos.coords.longitude }); },
        () => { clearTimeout(timer); resolve(null); },
        { enableHighAccuracy: true, timeout: 8000 }
      );
    });

  const checkIn = async () => {
    setBusy(true); setMsg(null);
    const pos = await getPosition();
    await mutate("UPDATE_FIELD_JOB", {
      targetId: job.id,
      payload: { action: "check_in", lat: pos?.lat ?? null, lng: pos?.lng ?? null },
      optimistic: { status: "in_progress" },
    });
    setStatus("in_progress");
    setMsg(pos
      ? (lang === "bn" ? "চেক-ইন সম্পন্ন।" : "Checked in.")
      : (lang === "bn" ? "চেক-ইন সম্পন্ন (অবস্থান পাওয়া যায়নি)।" : "Checked in (location unavailable)."));
    setBusy(false);
  };

  const complete = async () => {
    setBusy(true); setMsg(null);
    const pos = await getPosition();
    await mutate("UPDATE_FIELD_JOB", {
      targetId: job.id,
      payload: {
        action: "check_out", lat: pos?.lat ?? null, lng: pos?.lng ?? null,
        note, signature_ref: signature?.id ?? null,
        photo_refs: photos.map((p) => p.id),
      },
      optimistic: { status: "completed" },
    });
    setStatus("completed");
    setMsg(lang === "bn" ? "কাজ সম্পন্ন হিসেবে জমা হয়েছে।" : "Job submitted as completed.");
    setBusy(false);
  };

  const addPhoto = async (e, kind) => {
    const file = e.target.files?.[0];
    if (!file) return;
    // Photos go to the local file queue as blobs and upload on reconnect,
    // so evidence capture works with zero signal.
    const rec = await queueFile({ file, kind, relatedType: "field_job", relatedId: job.id });
    setPhotos((p) => [...p, rec]);
  };

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg-canvas)" }}>
      <Header title={JOB_LABEL[job.job_type]?.[lang] || job.job_type} onBack={onBack} />
      <main style={{ padding: "16px var(--page-pad)", maxWidth: 720, margin: "0 auto", paddingBottom: 40 }}>
        <OfflineBanner />

        {msg && (
          <div style={{ background: "var(--ok-bg)", color: "var(--ok)", padding: "9px 12px",
            borderRadius: 6, fontSize: 13, marginBottom: 12 }}>{msg}</div>
        )}

        <section className="card" style={{ padding: 16, marginBottom: 12 }}>
          <Row k={lang === "bn" ? "গ্রাহক" : "Customer"} v={job.customer_name || job.customer_id} />
          <Row k={lang === "bn" ? "ঠিকানা" : "Address"} v={job.address || "—"} />
          <Row k={lang === "bn" ? "অবস্থা" : "Status"} v={<StatusPill status={status} />} />
          {job.address && (
            <a className="btn btn-ghost" style={{ width: "100%", marginTop: 10, justifyContent: "center" }}
               href={`https://maps.google.com/?q=${encodeURIComponent(job.address)}`}
               target="_blank" rel="noreferrer">
              <Icon name="map-pin" size={15} />
              {lang === "bn" ? "মানচিত্রে দেখুন" : "Open in Maps"}
            </a>
          )}
        </section>

        <section className="card" style={{ padding: 16, marginBottom: 12 }}>
          <SectionTitle>{lang === "bn" ? "কাজের প্রমাণ" : "Job evidence"}</SectionTitle>

          <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 8 }}>
            <PhotoButton label={lang === "bn" ? "আগের ছবি" : "Before photo"} onChange={(e) => addPhoto(e, "before")} />
            <PhotoButton label={lang === "bn" ? "পরের ছবি" : "After photo"} onChange={(e) => addPhoto(e, "after")} />
            <button className="btn btn-ghost" onClick={() => setSigning(true)}>
              {lang === "bn" ? "গ্রাহকের স্বাক্ষর" : "Customer signature"}
            </button>
          </div>

          {(photos.length > 0 || signature) && (
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 12 }}>
              {photos.map((p) => (
                <Thumb key={p.id} rec={p} caption={p.kind} />
              ))}
              {signature && <Thumb rec={signature} caption={lang === "bn" ? "স্বাক্ষর" : "signature"} />}
            </div>
          )}

          <label style={{ display: "block", marginTop: 14 }}>
            <span style={{ fontSize: 12, fontWeight: 600, color: "var(--ink-soft)" }}>
              {lang === "bn" ? "নোট" : "Notes"}
            </span>
            <textarea value={note} onChange={(e) => setNote(e.target.value)} rows={3}
              style={{ width: "100%", marginTop: 5, padding: "9px 11px",
                border: "1px solid var(--border-strong)", borderRadius: 6, fontSize: 16 }} />
          </label>
        </section>

        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          {status === "assigned" && (
            <button className="btn btn-primary" style={{ flex: 1, justifyContent: "center" }}
              onClick={checkIn} disabled={busy}>
              {busy ? "…" : (lang === "bn" ? "কাজ শুরু (চেক-ইন)" : "Start job (check in)")}
            </button>
          )}
          {status === "in_progress" && (
            <button className="btn btn-primary" style={{ flex: 1, justifyContent: "center", background: "var(--ok)" }}
              onClick={complete} disabled={busy}>
              {busy ? "…" : (lang === "bn" ? "কাজ সম্পন্ন" : "Complete job")}
            </button>
          )}
          {status === "completed" && (
            <div style={{ flex: 1, textAlign: "center", color: "var(--ok)", fontWeight: 600, padding: 10 }}>
              {lang === "bn" ? "✓ সম্পন্ন" : "✓ Completed"}
            </div>
          )}
        </div>
      </main>

      {signing && (
        <SignaturePad
          onCancel={() => setSigning(false)}
          onSave={async (blob) => {
            const rec = await queueFile({
              file: new File([blob], "signature.png", { type: "image/png" }),
              kind: "signature", relatedType: "field_job", relatedId: job.id,
            });
            setSignature(rec); setSigning(false);
          }}
        />
      )}
    </div>
  );
}

/** Canvas signature capture — works fully offline, exports a PNG blob
 *  straight into the file queue. Touch and mouse both supported. */
function SignaturePad({ onSave, onCancel }) {
  const { lang } = useI18n();
  const ref = useRef(null);
  const drawing = useRef(false);

  useEffect(() => {
    const c = ref.current;
    if (!c) return;
    const ctx = c.getContext("2d");
    ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, c.width, c.height);
    ctx.strokeStyle = "#1e293b"; ctx.lineWidth = 2.2;
    ctx.lineCap = "round"; ctx.lineJoin = "round";
  }, []);

  const pos = (e) => {
    const c = ref.current, r = c.getBoundingClientRect();
    const t = e.touches?.[0];
    return {
      x: ((t ? t.clientX : e.clientX) - r.left) * (c.width / r.width),
      y: ((t ? t.clientY : e.clientY) - r.top) * (c.height / r.height),
    };
  };
  const start = (e) => { e.preventDefault(); drawing.current = true; const ctx = ref.current.getContext("2d"); const p = pos(e); ctx.beginPath(); ctx.moveTo(p.x, p.y); };
  const move = (e) => { if (!drawing.current) return; e.preventDefault(); const ctx = ref.current.getContext("2d"); const p = pos(e); ctx.lineTo(p.x, p.y); ctx.stroke(); };
  const end = () => { drawing.current = false; };
  const clear = () => { const c = ref.current, ctx = c.getContext("2d"); ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, c.width, c.height); };

  return (
    <Modal
      title={lang === "bn" ? "গ্রাহকের স্বাক্ষর" : "Customer signature"}
      onClose={onCancel}
      footer={<>
        <button className="btn btn-ghost" onClick={clear}>{lang === "bn" ? "মুছুন" : "Clear"}</button>
        <button className="btn btn-ghost" onClick={onCancel}>{lang === "bn" ? "বাতিল" : "Cancel"}</button>
        <button className="btn btn-primary"
          onClick={() => ref.current.toBlob((b) => onSave(b), "image/png")}>
          {lang === "bn" ? "সংরক্ষণ" : "Save"}
        </button>
      </>}
    >
      <canvas ref={ref} width={560} height={220}
        onMouseDown={start} onMouseMove={move} onMouseUp={end} onMouseLeave={end}
        onTouchStart={start} onTouchMove={move} onTouchEnd={end}
        style={{ width: "100%", height: 180, border: "1px dashed var(--border-strong)",
          borderRadius: 6, touchAction: "none", background: "#fff" }} />
      <p style={{ fontSize: 12, color: "var(--ink-faint)", margin: "8px 0 0" }}>
        {lang === "bn" ? "গ্রাহককে এখানে স্বাক্ষর করতে বলুন।" : "Ask the customer to sign above."}
      </p>
    </Modal>
  );
}

function PhotoButton({ label, onChange }) {
  return (
    <label className="btn btn-ghost" style={{ cursor: "pointer" }}>
      {label}
      <input type="file" accept="image/*" capture="environment"
        onChange={onChange} style={{ display: "none" }} />
    </label>
  );
}

function Thumb({ rec, caption }) {
  const [url, setUrl] = useState(null);
  useEffect(() => { previewUrl(rec).then(setUrl).catch(() => setUrl(null)); }, [rec]);
  return (
    <figure style={{ margin: 0, width: 84 }}>
      <div style={{ width: 84, height: 84, borderRadius: 6, overflow: "hidden",
        border: "1px solid var(--border)", background: "var(--bg-canvas)" }}>
        {url && <img src={url} alt={caption} style={{ width: "100%", height: "100%", objectFit: "cover" }} />}
      </div>
      <figcaption style={{ fontSize: 10.5, color: "var(--ink-faint)", textAlign: "center", marginTop: 3 }}>
        {caption}
      </figcaption>
    </figure>
  );
}

function Header({ title, onBack }) {
  const { lang } = useI18n();
  return (
    <header style={{ background: "var(--bg-shell)", color: "var(--ink-invert)",
      padding: "12px var(--page-pad)", display: "flex", alignItems: "center", gap: 10,
      position: "sticky", top: 0, zIndex: 20 }}>
      {onBack && (
        <button onClick={onBack} aria-label={lang === "bn" ? "ফিরে যান" : "Back"}
          style={{ background: "none", border: "none", color: "#cbd5e1", cursor: "pointer",
            minWidth: 44, minHeight: 44, fontSize: 20 }}>←</button>
      )}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontWeight: 700, fontSize: 15 }}>{title}</div>
        <div style={{ fontSize: 11, color: "#64748b", textTransform: "uppercase", letterSpacing: ".04em" }}>
          {lang === "bn" ? "টেকনিশিয়ান" : "Technician"}
        </div>
      </div>
      <SyncStatus compact />
      <LanguageToggle />
    </header>
  );
}

const Row = ({ k, v }) => (
  <div style={{ display: "flex", justifyContent: "space-between", gap: 12, padding: "6px 0", fontSize: 14 }}>
    <span style={{ color: "var(--ink-faint)", fontWeight: 600 }}>{k}</span>
    <span style={{ textAlign: "right" }}>{v}</span>
  </div>
);
const SectionTitle = ({ children }) => (
  <div style={{ fontSize: 12, fontWeight: 700, textTransform: "uppercase",
    letterSpacing: ".05em", color: "var(--ink-faint)" }}>{children}</div>
);
const Empty = ({ children }) => (
  <div className="card" style={{ padding: 40, textAlign: "center", color: "var(--ink-faint)" }}>{children}</div>
);
