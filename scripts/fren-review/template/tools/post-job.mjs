#!/usr/bin/env node
/**
 * Post one Fren Review deep review to IMD as a paid `job.open` (imd.fun/docs, "Paid requests"):
 * six different seats for one price — four hunters, a report, a verifier (jobs/deep-review.json).
 *
 *   node tools/post-job.mjs --commit <sha> --slot 0 --dry
 *   node tools/post-job.mjs --commit <sha> --foci perp-book,rotation,vault,value-flow --prior <jobId>,<jobId> --quote
 *
 * --slot N   picks foci N*4 .. N*4+3 of the rotation below, so consecutive jobs cover every focus
 *            every three jobs; --foci names four explicitly.
 * --prior    earlier jobs whose accepted report and findings files are attached as `inputs`, so the
 *            hunters build on them (they land in .imd/reads/artifacts/). Needs network.
 * --dry      fill and check against the documented limits, print the body; nothing is sent.
 * --quote    also ask IMD for a quote. Free: nothing is charged until the paid submit, and an
 *            invalid body comes back 422 with the problems. Prints the order and stops.
 * (default)  quote, then fetch the 402 payment challenge and print what the paying wallet must sign.
 *
 * IMD_PAID_TOKEN (64 hex, `openssl rand -hex 32`) names your orders; keep it to read them later.
 * A quote lives 600 s. Add each admitted job id to ledger/jobs.txt for tools/aggregate.mjs.
 */
import { readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";

const API = process.env.IMD_API ?? "https://api.imd.fun";
const ROOT = new URL("../", import.meta.url);
const argv = process.argv.slice(2);
const flag = (name) => argv.includes(`--${name}`);
const opt = (name) => {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < argv.length ? argv[i + 1] : undefined;
};
const die = (msg) => { console.error(msg); process.exit(1); };

//  Ordered so that any four consecutive entries spread across the machine.
const FOCI = ["perp-book", "value-flow", "hook-deltas", "rotation", "lifecycle", "genesis-nft",
              "perp-requote", "vault", "registry-facet", "randomness", "governance", "seed-deploy"];

const commit = opt("commit") ?? "";
if (!/^[0-9a-f]{40}$/.test(commit)) die("--commit must be the review repository's round commit, 40 lowercase hex");
let foci;
if (opt("foci")) {
  foci = opt("foci").split(",").map((f) => f.trim());
  if (foci.length !== 4 || new Set(foci).size !== 4 || foci.some((f) => !FOCI.includes(f))) {
    die(`--foci takes four different foci from: ${FOCI.join(", ")}`);
  }
} else {
  const slot = Number(opt("slot") ?? NaN);
  if (!Number.isInteger(slot) || slot < 0) die("give --slot <n> (n = 0, 1, 2, …) or --foci a,b,c,d");
  foci = [0, 1, 2, 3].map((i) => FOCI[(slot * 4 + i) % FOCI.length]);
}
const vars = { "<COMMIT>": commit, "<FOCUS_A>": foci[0], "<FOCUS_B>": foci[1], "<FOCUS_C>": foci[2], "<FOCUS_D>": foci[3] };

const fill = (value) => {
  if (typeof value === "string") return Object.entries(vars).reduce((s, [k, v]) => s.split(k).join(v), value);
  if (Array.isArray(value)) return value.map(fill);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).filter(([k]) => !k.startsWith("_")).map(([k, v]) => [k, fill(v)]));
  }
  return value;
};
const input = fill(JSON.parse(readFileSync(new URL("jobs/deep-review.json", ROOT), "utf8")));

// ── earlier reports as inputs ───────────────────────────────────────────────
const prior = (opt("prior") ?? "").split(",").map((s) => s.trim()).filter(Boolean);
if (prior.length) {
  input.inputs = [];
  for (const [n, jobId] of prior.entries()) {
    const res = await fetch(`${API}/jobs/${jobId}/result`, { signal: AbortSignal.timeout(20_000) });
    if (!res.ok) die(`job ${jobId}: result HTTP ${res.status}`);
    const result = await res.json();
    for (const f of result.files ?? []) {
      if (!["report", "findings"].includes(f.name)) continue;
      input.inputs.push({ name: `prior${n + 1}_${f.name}`, path: f.path, hash: f.hash, mediaType: f.mediaType,
                          bytes: f.bytes, submissionHash: f.submissionHash });
    }
  }
  if (!input.inputs.length) die("none of the --prior jobs has an accepted report or findings file yet");
}

// ── the documented limits (imd.fun/docs, "Job body") ─────────────────────────
const problems = [];
const leftover = JSON.stringify(input).match(/<[A-Z_]+>/g);
if (leftover) problems.push(`unfilled placeholders: ${[...new Set(leftover)].join(", ")}`);
if (!input.objective || input.objective.length > 8000) problems.push("objective must be 1–8,000 characters");
if ((input.references ?? []).length > 8) problems.push("at most 8 references");
if (!Array.isArray(input.steps) || input.steps.length < 1 || input.steps.length > 6) problems.push("steps must hold 1–6 entries");
const keys = new Set((input.steps ?? []).map((s) => s.key));
for (const [i, s] of (input.steps ?? []).entries()) {
  if (!s.skill) problems.push(`steps[${i}].skill is required`);
  if (!/^[a-z][a-z0-9_]{0,31}$/.test(s.key ?? "")) problems.push(`steps[${i}].key is required in a dag`);
  if (!Array.isArray(s.dependsOn) || s.dependsOn.length > 6 || s.dependsOn.some((d) => !keys.has(d))) problems.push(`steps[${i}].dependsOn must name up to 6 step keys`);
  if ((s.objective ?? "").length > 3000) problems.push(`steps[${i}].objective: at most 3,000 characters`);
  const ac = s.acceptanceCriteria ?? [];
  if (ac.length > 8 || ac.some((c) => !c || c.length > 500)) problems.push(`steps[${i}].acceptanceCriteria: 1–8 strings of 1–500 characters`);
  if ((s.paths ?? []).length > 16 || (s.paths ?? []).some((p) => p.startsWith("/") || p.includes(".."))) problems.push(`steps[${i}].paths: at most 16, repository-relative`);
  if ((s.outputs ?? []).some((o) => !o.path.startsWith("artifacts/"))) problems.push(`steps[${i}].outputs must live under artifacts/`);
}
const finals = [...keys].filter((k) => !(input.steps ?? []).some((s) => (s.dependsOn ?? []).includes(k)));
if (finals.length !== 1) problems.push(`every branch must join into one final step (found: ${finals.join(", ")})`);
if ((input.inputs ?? []).length > 32) problems.push("at most 32 inputs");
const body = { requestKey: opt("request-key") ?? randomUUID(), action: "job.open", input };
const bytes = Buffer.byteLength(JSON.stringify(body));
if (bytes > 16 * 1024) problems.push(`quote body is ${bytes} bytes; the limit is 16 KiB`);

console.log(JSON.stringify(body, null, 2));
console.error(`\ndeep review, foci ${foci.join(", ")}${prior.length ? `, ${input.inputs.length} prior file(s)` : ""}: ` +
  `${bytes} bytes, ${problems.length ? "PROBLEMS:\n  - " + problems.join("\n  - ") : "within the documented limits"}`);
if (problems.length) process.exit(1);
if (flag("dry")) process.exit(0);

// ── quote (free) ─────────────────────────────────────────────────────────────
const token = process.env.IMD_PAID_TOKEN ?? "";
if (!/^[0-9a-f]{64}$/.test(token)) die("set IMD_PAID_TOKEN to 64 lowercase hex (openssl rand -hex 32) and keep it");
const auth = { Authorization: `Bearer ${token}` };
const q = await fetch(`${API}/requests/quote`, {
  method: "POST", headers: { ...auth, "Content-Type": "application/json" }, body: JSON.stringify(body),
});
const quoted = await q.json().catch(() => ({}));
if (!q.ok) die(`quote refused: HTTP ${q.status}\n${JSON.stringify(quoted, null, 2)}`);
const order = quoted.order;
console.error(`\nquoted: order ${order.id}, ${order.quote?.amount} atomic units to ${order.quote?.payTo}, ` +
  `expires ${new Date(order.quote?.expiresAt * 1000).toISOString()} (requestKey ${body.requestKey})`);
if (flag("quote")) process.exit(0);

// ── the payment challenge ───────────────────────────────────────────────────
//  Submitting with no body returns 402: the x402 v2 requirements in the PAYMENT-REQUIRED header,
//  repeated in the JSON with the quote. The wallet then signs the Permit2 payment and an EIP-712
//  approval of that payment for this quote, and both go back to the same route. That signing is
//  deliberately not automated here: print the challenge and let the paying wallet's owner sign it.
const c = await fetch(`${API}/requests/${order.id}/submit`, { method: "POST", headers: auth });
const challenge = await c.json().catch(() => ({}));
console.log(JSON.stringify({ status: c.status, paymentRequired: c.headers.get("payment-required"), challenge }, null, 2));
console.error(`\nNext: sign the Permit2 payment and the quote approval with the paying wallet, then POST ` +
  `${API}/requests/${order.id}/submit with header PAYMENT-SIGNATURE and body {"quoteSignature": "0x…"}; ` +
  `poll GET /requests/${order.id} until admitted, and add admission.result.jobId to ledger/jobs.txt.`);
