#!/usr/bin/env node
/**
 * Rebuild ledger/ from every Fren Review job the swarm has run.
 *
 *   node tools/aggregate.mjs            # reads ledger/jobs.txt, writes ledger/ledger.json + LEDGER.md
 *
 * ledger/jobs.txt   one IMD job id per line (anything after `#` is a note) — every round, cumulative
 * ledger/triage.json  our own calls, applied last: { "FR-…": { "status": "...", "severity": "...", "note": "..." } }
 *
 * Everything else comes from IMD's public API (api.imd.fun/jobs/<id>/submissions and /result), so
 * anyone can re-run this and get the same ledger. Only ACCEPTED submissions count.
 *
 * A job is a six-step deep review (jobs/deep-review.json), told apart by each submission's nodeKey:
 *   hunt_a … hunt_d  findings + the FREN-REVIEW v1 coverage block          -> issues, coverage, leads
 *   report           the merged report; its findings JSON (job artifact)   -> confirmed / refuted
 *   verify           FREN-REVIEW VERIFY v1 lines + its own new findings    -> verified / overturned
 * Each job's report is saved as ledger/reports/<job id>.md.
 *
 * An issue is one function (file + contract.function, located through map/) — so independent
 * seats reporting the same bug land on the same FR- id and count as confirmations. Two different
 * bugs in one function share an id until triage.json says otherwise.
 *
 * Leads are what hunters suspected but could not prove: `lead:` lines and `suspect` verdict notes
 * from the coverage block. They carry no FR- id; LEDGER.md lists them so the next round digs there.
 */
import { createHash } from "node:crypto";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";

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
const coverage = Object.fromEntries(CLUSTERS.map((c) => [c, { solid: 0, suspect: 0, defect: 0, examined: [] }]));
const leads = new Map();
let skipped = 0;

const lead = (cluster, where, text, seat, jobId) => {
  const key = `${cluster}|${where || text.toLowerCase()}`;
  if (!leads.has(key)) leads.set(key, { cluster, where, text, seats: new Set(), jobs: new Set() });
  leads.get(key).seats.add(seat);
  leads.get(key).jobs.add(jobId);
};
const issue = (id, where) => {
  if (!issues.has(id)) issues.set(id, { id, ...where, titles: [], severities: {}, reporters: new Set(), reports: [], confirms: new Set(), refutes: [], checks: [] });
  return issues.get(id);
};

const cleanPath = (p) => String(p ?? "").replace(/^\.?\//, "").replace(/^contracts\/solidity\//, "");
const pathLine = (text) => {
  const m = /([\w./-]+\.sol):(\d+)/.exec(String(text ?? ""));
  return m ? locate(m[1], Number(m[2])) : null;
};
const reports = [];
await mkdir(new URL("ledger/reports/", ROOT), { recursive: true });

for (const jobId of jobIds) {
  const res = await fetch(`${API}/jobs/${jobId}/submissions`, { signal: AbortSignal.timeout(20_000) });
  if (!res.ok) throw new Error(`job ${jobId}: HTTP ${res.status}`);
  const all = (await res.json()).submissions ?? [];
  skipped += all.filter((s) => s.accepted !== true).length;
  //  The latest accepted attempt of each step wins: a reopened report is revised, not duplicated.
  const latest = new Map();
  for (const s of all.filter((s) => s.accepted === true)) {
    const prev = latest.get(s.nodeKey);
    if (!prev || String(s.createdAt) > String(prev.createdAt)) latest.set(s.nodeKey, s);
  }
  for (const s of latest.values()) {
    const seat = s.seat?.tokenId ?? "?";
    seats.set(seat, (seats.get(seat) ?? 0) + 1);
    const summary = String(s.summary ?? "");
    const head = summary.split("\n")[0].trim();
    const step = String(s.nodeKey ?? "");

    // A hunt, or the verifier's own new findings: reported issues.
    const addFindings = (who) => {
      let n = 0;
      for (const f of s.findings ?? []) {
        if (cleanPath(f.path).startsWith("review/")) continue;   // a verifier's "Report error:" is not a protocol issue
        const where = locate(f.path, f.line);
        const it = issue(issueId(where.file, where.fn), where);
        it.titles.includes(f.title) || it.titles.push(f.title);
        it.severities[f.severity] = (it.severities[f.severity] ?? 0) + 1;
        it.reporters.add(seat);
        it.reports.push({ job: jobId, step, seat, severity: f.severity, title: f.title, line: f.line, submission: s.hash, by: who });
        n++;
      }
      return n;
    };

    if (step === "report") {
      const r = await fetch(`${API}/jobs/${jobId}/result`, { signal: AbortSignal.timeout(20_000) }).then((x) => (x.ok ? x.json() : null)).catch(() => null);
      const file = (name) => (r?.files ?? []).find((f) => f.name === name);
      const text = async (f) => (f ? fetch(new URL(f.url, API), { signal: AbortSignal.timeout(30_000) }).then((x) => (x.ok ? x.text() : null)).catch(() => null) : null);
      const md = await text(file("report"));
      if (md) await writeFile(new URL(`ledger/reports/${jobId}.md`, ROOT), md);
      let parsed = null;
      try { parsed = JSON.parse(await text(file("findings")) ?? "null"); } catch { parsed = null; }
      for (const f of parsed?.findings ?? []) {
        const where = locate(f.path, f.line);
        const it = issue(issueId(where.file, where.fn), where);
        it.titles.includes(f.title) || it.titles.push(f.title);
        it.severities[f.severity] = (it.severities[f.severity] ?? 0) + 1;
        it.checks.push({ job: jobId, step, seat, result: "confirmed", severity: f.severity, poc: f.poc ?? null });
      }
      for (const f of parsed?.refuted ?? []) {
        if (!f.path) continue;
        const where = locate(f.path, f.line);
        issue(issueId(where.file, where.fn), where).refutes.push({ seat, why: String(f.why ?? f.guard ?? "").slice(0, 300), job: jobId });
      }
      for (const l of parsed?.leads ?? []) if (CLUSTERS.includes(l.cluster)) lead(l.cluster, cleanPath(l.path) || null, String(l.text ?? "").slice(0, 300), seat, jobId);
      for (const id of parsed?.ledger?.confirms ?? []) issue(id, {}).confirms.add(seat);
      reports.push({ job: jobId, seat, submission: s.hash, head, saved: Boolean(md), findings: parsed?.findings?.length ?? null });
      continue;
    }

    if (step === "verify") {
      for (const line of summary.split("\n")) {
        const m = /^\s*(upheld|overturned|severity|refutation-upheld|refutation-overturned):\s*(.+)$/i.exec(line);
        if (!m) continue;
        const where = pathLine(m[2]);
        if (!where) continue;
        const result = { upheld: "verified", overturned: "overturned", severity: "verified", "refutation-upheld": "refutation-upheld", "refutation-overturned": "verified" }[m[1].toLowerCase()];
        issue(issueId(where.file, where.fn), where).checks.push({ job: jobId, step, seat, result, note: m[2].slice(0, 300) });
      }
      addFindings("verify");
      continue;
    }

    // A hunt: findings + the coverage block.
    const review = { job: jobId, step, seat, submission: s.hash, findings: 0, focus: null, verdicts: {}, formatted: head === "FREN-REVIEW v1" };
    let leadLines = 0;
    review.findings = addFindings("hunt");
    for (const line of summary.split("\n")) {
      const v = /^\s*([a-z]+):\s*(solid|suspect|exploitable|defect)\s*\|\s*(\d+)\s*(?:\|\s*(.*))?$/i.exec(line);
      if (v && coverage[v[1].toLowerCase()]) {
        const c = coverage[v[1].toLowerCase()];
        if (v[2].toLowerCase() === "exploitable") v[2] = "defect";   // the verdict's old name
        c[v[2].toLowerCase()]++;
        c.examined.push(Number(v[3]));
        review.verdicts[v[1].toLowerCase()] = v[2].toLowerCase();
        if (v[2].toLowerCase() === "suspect" && v[4]?.trim()) lead(v[1].toLowerCase(), null, v[4].trim().slice(0, 300), seat, jobId);
      }
      const foc = /^\s*focus:\s*([a-z][a-z-]*)/i.exec(line);
      if (foc && !review.focus) review.focus = foc[1].toLowerCase();
      const ld = /^\s*lead:\s*([a-z]+)\s*\|\s*([^|]*?)\s*\|\s*(.+)$/i.exec(line);
      if (ld && CLUSTERS.includes(ld[1].toLowerCase()) && leadLines++ < 5) {
        lead(ld[1].toLowerCase(), cleanPath(ld[2]) || null, ld[3].trim().slice(0, 300), seat, jobId);
      }
      const conf = /^\s*confirms:\s*(.+)$/i.exec(line);
      if (conf) for (const id of conf[1].match(/FR-[0-9a-f]{6}/gi) ?? []) issue(id, {}).confirms.add(seat);
      const ref = /^\s*refutes:\s*(.+)$/i.exec(line);
      if (ref) for (const id of ref[1].match(/FR-[0-9a-f]{6}/gi) ?? []) issue(id, {}).refutes.push({ seat, why: ref[1].slice(0, 300), job: jobId });
    }
    reviews.push(review);
  }
}

// ── Status: evidence first, our triage last ────────────────────────────────────
const worst = (sev) => SEVERITY.find((s) => sev[s]) ?? "info";
const out = [...issues.values()].map((it) => {
  //  reported (a hunter or the verifier) -> confirmed (the report re-ran its PoC) -> verified (the
  //  verifier upheld it); refuted when the report refuted it or the verifier overturned it.
  let status = "reported";
  if (it.checks.some((c) => c.result === "confirmed")) status = "confirmed";
  if (it.checks.some((c) => c.result === "verified")) status = "verified";
  else if (it.checks.some((c) => c.result === "overturned") || (it.refutes.length && !it.checks.some((c) => c.result === "confirmed"))) status = "refuted";
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
  updatedAt: new Date().toISOString(), jobs: jobIds.length, hunts: reviews.length, reports: reports.length,
  skippedUnaccepted: skipped, seats: Object.fromEntries(seats), coverage, foci, issues: out, leads: leadList, reviews, reportsIndex: reports,
};
await writeFile(new URL("ledger/ledger.json", ROOT), `${JSON.stringify(ledger, null, 1)}\n`);

// ── LEDGER.md ──────────────────────────────────────────────────────────────────
const esc = (s) => String(s ?? "").replace(/\|/g, "\\|").replace(/\s+/g, " ").slice(0, 110);
const md = [
  "# 🐸 The Fren Review ledger",
  "",
  `Rebuilt ${ledger.updatedAt} by \`node tools/aggregate.mjs\` from ${jobIds.length} IMD jobs: **${reviews.length} accepted hunts**, **${reports.length} reports**, **${seats.size} seats** taking part, ${out.length} issues. Each job's report is in \`ledger/reports/\`.`,
  "An issue groups every report that lands in the same function. Hunters: confirm or refute these in your coverage block — do not re-report them.",
  "",
  "## The machine, cluster by cluster",
  "",
  "| cluster | hunts | solid | suspect | defect | median entry points examined | open issues |",
  "|---|---|---|---|---|---|---|",
  ...CLUSTERS.map((c) => {
    const k = coverage[c];
    const ex = [...k.examined].sort((a, b) => a - b);
    const open = out.filter((i) => i.cluster === c && !["fixed", "refuted", "wontfix", "duplicate"].includes(i.status)).length;
    return `| ${c} | ${k.solid + k.suspect + k.defect} | ${k.solid} | ${k.suspect} | ${k.defect} | ${ex.length ? ex[ex.length >> 1] : "-"} | ${open} |`;
  }),
  "",
  "## Issues",
  "",
  out.length ? "| id | severity | where | what | reporters | confirms / refutes | status |" : "_Nothing yet. The cauldron waits._",
  ...(out.length ? ["|---|---|---|---|---|---|---|"] : []),
  ...out.map((i) => `| ${i.id} | ${i.severity} | \`${i.file ?? "?"}\` ${esc(i.fn)} | ${esc(i.titles[0])}${i.titles.length > 1 ? ` (+${i.titles.length - 1} more)` : ""} | ${i.reporters.length} | ${i.confirms.length} / ${i.refutes.length} | ${i.status}${i.note ? ` — ${esc(i.note)}` : ""} |`),
  "",
  "Statuses: `reported` (a hunter or the verifier) → `confirmed` (the report re-ran its PoC) → `verified` (the verifier upheld it), or `refuted`; `fixed` / `wontfix` / `duplicate` are set upstream in triage.json.",
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
console.log(`${jobIds.length} jobs, ${reviews.length} accepted hunts, ${reports.length} reports, ${seats.size} seats taking part, ${out.length} issues, ${leadList.length} leads -> ledger/LEDGER.md`);
