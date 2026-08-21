// Fails the build if Bengali is missing any English key (or has extras).
// Bengali is a market requirement, not a nice-to-have — a missing string
// renders an English key to a Bangla-speaking operator.
import { readFileSync } from "node:fs";

const keys = (f) => new Set(
  [...readFileSync(new URL(f, import.meta.url), "utf8")
    .matchAll(/"([a-zA-Z]+\.[a-zA-Z]+)":/g)].map((m) => m[1])
);

const en = keys("../src/i18n/en.js");
const bn = keys("../src/i18n/bn.js");

const missing = [...en].filter((k) => !bn.has(k));
const extra = [...bn].filter((k) => !en.has(k));

console.log(`en=${en.size} bn=${bn.size}`);
if (missing.length) console.error("Missing in bn.js:", missing.join(", "));
if (extra.length) console.error("Extra in bn.js:", extra.join(", "));

if (missing.length || extra.length) process.exit(1);
console.log("i18n parity PASS");
