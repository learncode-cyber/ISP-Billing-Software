// Fails the build on buttons with no handler and no submit role.
// The spec forbids dead controls: every visible action must do something.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const roots = ["src/pages", "src/portal", "src/technician", "src/platform", "src/layouts"];
const dead = [];

const walk = (dir) => {
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) walk(p);
    else if (p.endsWith(".jsx")) scan(p);
  }
};

// Finding the end of a JSX opening tag needs brace awareness: expressions
// like disabled={a >= b} contain ">" characters that a naive [^>] scan
// mistakes for the tag end, which produced false "dead button" reports.
const openingTagEnd = (src, from) => {
  let depth = 0;
  for (let i = from; i < src.length; i++) {
    const ch = src[i];
    if (ch === "{") depth++;
    else if (ch === "}") depth--;
    else if (ch === ">" && depth === 0) return i;
  }
  return -1;
};

const scan = (file) => {
  const s = readFileSync(file, "utf8");
  for (const m of s.matchAll(/<button\b/g)) {
    const tagEnd = openingTagEnd(s, m.index);
    if (tagEnd === -1) continue;
    const attrs = s.slice(m.index, tagEnd + 1);
    const closeIdx = s.indexOf("</button>", tagEnd);
    const label = (closeIdx === -1 ? "" : s.slice(tagEnd + 1, closeIdx))
      .trim().replace(/\s+/g, " ").slice(0, 40);

    if (!attrs.includes("onClick") && !attrs.includes('type="submit"')) {
      // A button inside a <form> submits by default — not dead.
      const before = s.slice(0, m.index);
      const inForm = before.lastIndexOf("<form") > before.lastIndexOf("</form>");
      if (!inForm) dead.push(`${file}: "${label}"`);
    }
  }
};

roots.forEach((r) => { try { walk(r); } catch {} });

if (dead.length) {
  console.error(`Dead buttons found (${dead.length}):`);
  dead.forEach((d) => console.error("  " + d));
  process.exit(1);
}
console.log("dead UI scan PASS — no handler-less buttons");
