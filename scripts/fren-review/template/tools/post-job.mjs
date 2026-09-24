#!/usr/bin/env node
/**
 * Post one Fren Review job to IMD as a paid `job.open` request (imd.fun/docs, "Paid requests").
 *
 *   node tools/post-job.mjs hunt  --commit <sha> --focus perp-book            [--dry | --quote]
 *   node tools/post-job.mjs prove --commit <sha> --id FR-1a2b3c --title "…" --claim "…"
 *   node tools/post-job.mjs fix   --commit <sha> --id FR-1a2b3c --title "…" --paths cauldron/PerpEngine.sol,…
 *
 * --dry    fill jobs/<job>.json, check it against the documented limits, print it; no network.
 * --quote  also ask IMD for a quote. Free: nothing is charged until the paid submit, and an
 *          invalid body comes back 422 with the problems. Prints the order and stops.
 * (default) quote, then request the payment challenge and print what the wallet must sign.
 *
 * IMD_PAID_TOKEN (64 hex, `openssl rand -hex 32`) names your orders; keep it to read them later.
 * A quote lives 600 s. Add each admitted job id to ledger/jobs.txt for tools/aggregate.mjs.
 */
import { readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";

const API = process.env.IMD_API ?? "https://api.imd.fun";
const ROOT = new URL("../", import.meta.url);
const argv = process.argv.slice(2);
const job = argv[0];
const flag = (name) => argv.includes(`--${name}`);
const opt = (name) => {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < argv.length ? argv[i + 1] : undefined;
};
const die = (msg) => { console.error(msg); process.exit(1); };

if (!["hunt", "prove", "fix"].includes(job)) die("usage: node tools/post-job.mjs hunt|prove|fix --commit <sha> [...] [--dry|--quote]");

// ── fill the template ───────────────────────────────────────────────────────
const commit = opt("commit") ?? "";
if (!/^[0-9a-f]{40}$/.test(commit)) die("--commit must be this repository's round commit, 40 lowercase hex");
const vars = { "<COMMIT>": commit };
if (job === "hunt") {
  const focus = opt("focus");
  const FOCI = ["hook-deltas", "lifecycle", "perp-book", "perp-requote", "vault", "rotation", "registry-facet",
                "genesis-nft", "randomness", "governance", "seed-deploy", "value-flow"];
  if (focus && !FOCI.includes(focus)) die(`--focus must be one of: ${FOCI.join(", ")}`);
  vars["<FOCUS>"] = focus ?? null;   // null: drop the Focus sentence, the seat draws one
} else {
  const id = opt("id") ?? "";
  if (!/^FR-[0-9a-f]{6}$/.test(id)) die("--id must be a ledger id like FR-1a2b3c");
  vars["<ID>"] = id;
  vars["<TITLE>"] = opt("title") ?? die("--title is required");
  if (job === "prove") vars["<CLAIM>"] = opt("claim") ?? die("--claim is required");
}

const template = JSON.parse(readFileSync(new URL(`jobs/${job}.json`, ROOT), "utf8"));
const fill = (value) => {
  if (typeof value === "string") {
    let s = value;
    if (vars["<FOCUS>"] === null) s = s.replace(/ Focus: <FOCUS>\./, "");
    for (const [k, v] of Object.entries(vars)) if (v !== null) s = s.split(k).join(v);
    return s;
  }
  if (Array.isArray(value)) {
    return value.flatMap((v) => (v === "<PATHS>"
      ? (opt("paths") ?? die("--paths is required (comma-separated source files)")).split(",").map((p) => p.trim()).filter(Boolean)
      : [fill(v)]));
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).filter(([k]) => !k.startsWith("_")).map(([k, v]) => [k, fill(v)]));
  }
  return value;
};
const input = fill(template);

// ── the documented limits (imd.fun/docs, "Job body") ─────────────────────────
const problems = [];
const text = JSON.stringify(input);
const leftover = text.match(/<[A-Z]+>/g);
if (leftover) problems.push(`unfilled placeholders: ${[...new Set(leftover)].join(", ")}`);
if (!input.objective || input.objective.length > 8000) problems.push("objective must be 1–8,000 characters");
if ((input.references ?? []).length > 8) problems.push("at most 8 references");
if (!Array.isArray(input.steps) || input.steps.length < 1 || input.steps.length > 6) problems.push("steps must hold 1–6 entries");
for (const [i, s] of (input.steps ?? []).entries()) {
  if (!s.skill) problems.push(`steps[${i}].skill is required`);
  const ac = s.acceptanceCriteria ?? [];
  if (ac.length > 8 || ac.some((c) => !c || c.length > 500)) problems.push(`steps[${i}].acceptanceCriteria: 1–8 strings of 1–500 characters`);
  if ((s.paths ?? []).length > 16) problems.push(`steps[${i}].paths: at most 16`);
  if ((s.paths ?? []).some((p) => p.startsWith("/") || p.includes(".."))) problems.push(`steps[${i}].paths must be repository-relative`);
}
const body = { requestKey: opt("request-key") ?? randomUUID(), action: "job.open", input };
const bytes = Buffer.byteLength(JSON.stringify(body));
if (bytes > 16 * 1024) problems.push(`quote body is ${bytes} bytes; the limit is 16 KiB`);

console.log(JSON.stringify(body, null, 2));
console.error(`\n${job}: ${bytes} bytes, ${problems.length ? "PROBLEMS:\n  - " + problems.join("\n  - ") : "within the documented limits"}`);
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
