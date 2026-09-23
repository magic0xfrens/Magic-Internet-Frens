#!/usr/bin/env node
/**
 * Rebuild ledger/ from every Fren Review job the swarm has run.
 *
 *   node tools/aggregate.mjs            # reads ledger/jobs.txt, writes ledger/ledger.json + LEDGER.md
 *
 * ledger/jobs.txt   one IMD job id per line (anything after `#` is a note) — every round, cumulative
 * ledger/triage.json  our own calls, applied last: { "FR-…": { "status": "...", "severity": "...", "note": "..." } }
 *
 * Everything else comes from IMD's public API (api.imd.fun/jobs/<id>/submissions), so anyone can
 * re-run this and get the same ledger. Only ACCEPTED submissions count.
 *
 * An issue is one function (file + contract.function, located through map/) — so independent
 * seats reporting the same bug land on the same FR- id and count as confirmations. Two different
 * bugs in one function share an id until triage.json says otherwise.
 *
 * Leads are what hunters suspected but could not prove: `lead:` lines and `suspect` verdict notes
 * from the coverage block. They carry no FR- id; LEDGER.md lists them so the next round digs there.
 */
import { createHash } from "node:crypto";
import { readFile, readdir, writeFile } from "node:fs/promises";

const ROOT = new URL("../", import.meta.url);
const API = "https://api.imd.fun";
const CLUSTERS = ["hook", "registry", "pool", "perp", "rotation", "nft", "governance", "seed", "art", "deploy"];
const SEVERITY = ["critical", "high", "medium", "low", "info"];
const read = async (p, fallback) => readFile(new URL(p, ROOT), "utf8").then(JSON.parse).catch(() => fallback);

// ── The map: file -> functions with spans, and file -> cluster ─────────────────
const spans = new Map();
const clusterOf = new Map();
for (const f of await readdir(new URL("map/", ROOT))) {
  const { cluster, nodes } = JSON.parse(await readFile(new URL(`map/${f}`, ROOT), "utf8"));
  for (const n of nodes) {
    clusterOf.set(n.file, cluster);
    if (!n.body_lines?.length) continue;
    if (!spans.has(n.file)) spans.set(n.file, []);
    spans.get(n.file).push({ fn: `${n.contract}.${n.name || n.kind}`, from: n.line, to: n.body_lines[1] });
  }
}
const locate = (path, line) => {
  const file = String(path ?? "").replace(/^\.?\//, "").replace(/^contracts\/solidity\//, "");
  const hit = (spans.get(file) ?? []).filter((s) => line >= s.from && line <= s.to).sort((a, b) => a.to - a.from - (b.to - b.from))[0];
  return { file, fn: hit?.fn ?? (line ? `L${line}` : "(file)"), cluster: clusterOf.get(file) ?? "?" };
};
const issueId = (file, fn) => `FR-${createHash("sha1").update(`${file}::${fn}`).digest("hex").slice(0, 6)}`;

// ── Pull every job ──────────────────────────────────────────────────────────────
const jobIds = (await readFile(new URL("ledger/jobs.txt", ROOT), "utf8").catch(() => ""))
  .split("\n").map((l) => l.split("#")[0].trim()).filter(Boolean);
const triage = await read("ledger/triage.json", {});

const issues = new Map();
const reviews = [];
const seats = new Map();
const coverage = Object.fromEntries(CLUSTERS.map((c) => [c, { solid: 0, suspect: 0, exploitable: 0, examined: [] }]));
const leads = new Map();
let skipped = 0;

const issue = (id, where) => {
  if (!issues.has(id)) issues.set(id, { id, ...where, titles: [], severities: {}, reporters: new Set(), reports: [], confirms: new Set(), refutes: [], proofs: [], fixes: [] });
  return issues.get(id);
};

for (const jobId of jobIds) {
  const res = await fetch(`${API}/jobs/${jobId}/submissions`, { signal: AbortSignal.timeout(20_000) });
  if (!res.ok) throw new Error(`job ${jobId}: HTTP ${res.status}`);
  for (const s of (await res.json()).submissions ?? []) {
    if (s.accepted !== true) { skipped++; continue; }
    const seat = s.seat?.tokenId ?? "?";
    seats.set(seat, (seats.get(seat) ?? 0) + 1);
    const summary = String(s.summary ?? "");
    const head = summary.split("\n")[0].trim();

    const prove = /^FREN-REVIEW PROVE (FR-[0-9a-f]{6}):\s*(reproduced|not-reproducible)/i.exec(head);
    const fix = /^FREN-REVIEW FIX (FR-[0-9a-f]{6}):\s*(fixed|cannot-fix)/i.exec(head);
    if (prove) { issue(prove[1], {}).proofs.push({ job: jobId, seat, result: prove[2].toLowerCase(), submission: s.hash }); continue; }
    if (fix) { issue(fix[1], {}).fixes.push({ job: jobId, seat, result: fix[2].toLowerCase(), submission: s.hash }); continue; }

    // A hunt: findings + the coverage block.
    const review = { job: jobId, seat, submission: s.hash, findings: 0, focus: null, verdicts: {}, formatted: head === "FREN-REVIEW v1" };
    const lead = (cluster, where, text) => {
      const key = `${cluster}|${where || text.toLowerCase()}`;
      if (!leads.has(key)) leads.set(key, { cluster, where, text, seats: new Set(), jobs: new Set() });
      leads.get(key).seats.add(seat);
      leads.get(key).jobs.add(jobId);
    };
    let leadLines = 0;
    for (const f of s.findings ?? []) {
      const where = locate(f.path, f.line);
      const it = issue(issueId(where.file, where.fn), where);
      it.titles.includes(f.title) || it.titles.push(f.title);
      it.severities[f.severity] = (it.severities[f.severity] ?? 0) + 1;
      it.reporters.add(seat);
      it.reports.push({ job: jobId, seat, severity: f.severity, title: f.title, line: f.line, submission: s.hash });
      review.findings++;
    }
    for (const line of summary.split("\n")) {
      const v = /^\s*([a-z]+):\s*(solid|suspect|exploitable)\s*\|\s*(\d+)\s*(?:\|\s*(.*))?$/i.exec(line);
      if (v && coverage[v[1].toLowerCase()]) {
        const c = coverage[v[1].toLowerCase()];
        c[v[2].toLowerCase()]++;
        c.examined.push(Number(v[3]));
        review.verdicts[v[1].toLowerCase()] = v[2].toLowerCase();
        if (v[2].toLowerCase() === "suspect" && v[4]?.trim()) lead(v[1].toLowerCase(), null, v[4].trim().slice(0, 300));
      }
      const foc = /^\s*focus:\s*([a-z][a-z-]*)/i.exec(line);
      if (foc && !review.focus) review.focus = foc[1].toLowerCase();
      const ld = /^\s*lead:\s*([a-z]+)\s*\|\s*([^|]*?)\s*\|\s*(.+)$/i.exec(line);
      if (ld && CLUSTERS.includes(ld[1].toLowerCase()) && leadLines++ < 5) {
        lead(ld[1].toLowerCase(), ld[2].replace(/^\.?\//, "").replace(/^contracts\/solidity\//, "") || null, ld[3].trim().slice(0, 300));
      }
      const conf = /^\s*confirms:\s*(.+)$/i.exec(line);
      if (conf) for (const id of conf[1].match(/FR-[0-9a-f]{6}/gi) ?? []) issue(id, {}).confirms.add(seat);
      const ref = /^\s*refutes:\s*(.+)$/i.exec(line);
      if (ref) for (const id of ref[1].match(/FR-[0-9a-f]{6}/gi) ?? []) issue(id, {}).refutes.push({ seat, why: ref[1].slice(0, 300) });
    }
    reviews.push(review);
  }
}

// ── Status: evidence first, our triage last ────────────────────────────────────
const worst = (sev) => SEVERITY.find((s) => sev[s]) ?? "info";
const out = [...issues.values()].map((it) => {
  let status = "reported";
  if (it.proofs.some((p) => p.result === "reproduced")) status = "proven";
  else if (it.proofs.length && it.proofs.every((p) => p.result === "not-reproducible")) status = "refuted";
  if (it.fixes.some((f) => f.result === "fixed")) status = "fix-submitted";
  const t = triage[it.id] ?? {};
  return {
    ...it, reporters: [...it.reporters], confirms: [...it.confirms],
    severity: t.severity ?? worst(it.severities), status: t.status ?? status, note: t.note ?? null,
  };
}).sort((a, b) => SEVERITY.indexOf(a.severity) - SEVERITY.indexOf(b.severity)
  || b.reporters.length + b.confirms.length - (a.reporters.length + a.confirms.length));

const leadList = [...leads.values()].map((l) => ({ ...l, seats: [...l.seats], jobs: [...l.jobs] }))
  .sort((a, b) => CLUSTERS.indexOf(a.cluster) - CLUSTERS.indexOf(b.cluster) || b.seats.length - a.seats.length);
const foci = {};
for (const r of reviews) if (r.focus) foci[r.focus] = (foci[r.focus] ?? 0) + 1;

const ledger = {
  updatedAt: new Date().toISOString(), jobs: jobIds.length, acceptedSubmissions: reviews.length + out.reduce((n, i) => n + i.proofs.length + i.fixes.length, 0),
  hunts: reviews.length, skippedUnaccepted: skipped, seats: Object.fromEntries(seats), coverage, foci, issues: out, leads: leadList, reviews,
};
await writeFile(new URL("ledger/ledger.json", ROOT), `${JSON.stringify(ledger, null, 1)}\n`);

// ── LEDGER.md ──────────────────────────────────────────────────────────────────
const esc = (s) => String(s ?? "").replace(/\|/g, "\\|").replace(/\s+/g, " ").slice(0, 110);
const md = [
  "# 🐸 The Fren Review ledger",
  "",
  `Rebuilt ${ledger.updatedAt} by \`node tools/aggregate.mjs\` from ${jobIds.length} IMD jobs: **${reviews.length} accepted hunts**, **${seats.size} seats** taking part, ${out.length} issues.`,
  "An issue groups every report that lands in the same function. Hunters: confirm or refute these in your coverage block — do not re-report them.",
  "",
  "## The machine, cluster by cluster",
  "",
  "| cluster | hunts | solid | suspect | exploitable | median entry points examined | open issues |",
  "|---|---|---|---|---|---|---|",
  ...CLUSTERS.map((c) => {
    const k = coverage[c];
    const ex = [...k.examined].sort((a, b) => a - b);
    const open = out.filter((i) => i.cluster === c && !["fixed", "refuted", "wontfix", "duplicate"].includes(i.status)).length;
    return `| ${c} | ${k.solid + k.suspect + k.exploitable} | ${k.solid} | ${k.suspect} | ${k.exploitable} | ${ex.length ? ex[ex.length >> 1] : "-"} | ${open} |`;
  }),
  "",
  "## Issues",
  "",
  out.length ? "| id | severity | where | what | reporters | confirms / refutes | status |" : "_Nothing yet. The cauldron waits._",
  ...(out.length ? ["|---|---|---|---|---|---|---|"] : []),
  ...out.map((i) => `| ${i.id} | ${i.severity} | \`${i.file ?? "?"}\` ${esc(i.fn)} | ${esc(i.titles[0])}${i.titles.length > 1 ? ` (+${i.titles.length - 1} more)` : ""} | ${i.reporters.length} | ${i.confirms.length} / ${i.refutes.length} | ${i.status}${i.note ? ` — ${esc(i.note)}` : ""} |`),
  "",
  "Statuses: `reported` → `proven` / `refuted` (PROVE jobs) → `fix-submitted` (FIX jobs) → `fixed` (merged upstream, set in triage.json).",
  "",
  "## Leads for the next round",
  "",
  "What hunters suspected but could not prove (`lead:` lines and `suspect` notes). Not issues — places to dig. Prove one and it becomes a finding.",
  "",
  ...(Object.keys(foci).length ? [`Hunts by focus: ${Object.entries(foci).sort((a, b) => b[1] - a[1]).map(([f, n]) => `${f} ${n}`).join(", ")}.`, ""] : []),
  ...(leadList.length ? CLUSTERS.flatMap((c) => {
    const ls = leadList.filter((l) => l.cluster === c);
    if (!ls.length) return [];
    return [`**${c}**`, "", ...ls.slice(0, 20).map((l) => `- ${l.where ? `\`${esc(l.where)}\` ` : ""}${String(l.text).replace(/\s+/g, " ").slice(0, 240)} _(${l.seats.length} seat${l.seats.length === 1 ? "" : "s"})_`),
      ...(ls.length > 20 ? [`- …and ${ls.length - 20} more in ledger.json`] : []), ""];
  }) : ["_No leads yet._", ""]),
];
await writeFile(new URL("ledger/LEDGER.md", ROOT), md.join("\n"));
console.log(`${jobIds.length} jobs, ${reviews.length} accepted hunts, ${seats.size} seats taking part, ${out.length} issues, ${leadList.length} leads -> ledger/LEDGER.md`);
