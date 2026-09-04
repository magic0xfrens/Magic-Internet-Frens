#!/usr/bin/env node
/**
 * deploy-round.mjs — ONE command to ship a round, from ONE source of truth.
 *
 * The canonical manifest is `indexer/deployments/round.json`. Both sides import it
 * directly (no regex patching that can silently fail):
 *   • indexer  — ponder.config.ts, src/api/index.ts, start.mjs (schema)
 *   • frontend — src/config/cauldron.ts, src/config/perp.ts
 * So the frontend and indexer can NEVER point at different addresses/pool/schema
 * (that drift once served round-29 data as round-31).
 *
 * Usage:
 *   node scripts/deploy-round.mjs             # deploy indexer (railway up) + verify
 *   node scripts/deploy-round.mjs --push      # also `git push` → Vercel redeploys the frontend
 *   node scripts/deploy-round.mjs --yes       # skip the confirm prompt
 *   node scripts/deploy-round.mjs --no-verify # don't poll the live indexer afterwards
 *
 * Prereqs: `railway` CLI logged in + linked to the indexer service (railway link).
 * To ship a NEW round: edit indexer/deployments/round.json (bump `round` + `schema`
 * for a clean reindex; update addresses/poolIds/blocks), commit, then run this.
 */
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const INDEXER = join(ROOT, "indexer");
const MANIFEST = join(INDEXER, "deployments", "round.json");
const args = new Set(process.argv.slice(2));
const wantPush = args.has("--push");
const skipConfirm = args.has("--yes") || args.has("-y");
const skipVerify = args.has("--no-verify");

const m = JSON.parse(readFileSync(MANIFEST, "utf8"));
const poolId = m.poolIds[m.poolIds.length - 1];

function run(cmd, cmdArgs, opts = {}) {
  const r = spawnSync(cmd, cmdArgs, { stdio: "inherit", ...opts });
  if (r.status !== 0) { console.error(`\n✗ \`${cmd} ${cmdArgs.join(" ")}\` failed (exit ${r.status})`); process.exit(r.status ?? 1); }
  return r;
}

console.log(`\n╔═ DEPLOY ROUND ${m.round} ═════════════════════════════════════════`);
console.log(`║ schema     ${m.schema}   (same schema = resume; new = clean reindex)`);
console.log(`║ registry   ${m.contracts.registry}`);
console.log(`║ hook       ${m.contracts.hook}`);
console.log(`║ perpEngine ${m.contracts.perpEngine}`);
console.log(`║ poolId     ${poolId}`);
console.log(`║ blocks     deploy ${m.blocks.deploy} · perp ${m.blocks.perp} · indexer ${m.blocks.indexer}`);
console.log(`║ indexerUrl ${m.indexerUrl}`);
console.log(`║ frontend   ${wantPush ? "git push → Vercel" : "NOT pushed (add --push)"}`);
console.log(`╚══════════════════════════════════════════════════════════════════\n`);

// Guard: never let a stale Railway env var silently override the manifest schema.
// (DATABASE_SCHEMA / POOL_IDS / PERP_ENGINE overrides caused the r29-as-r31 bug.)
const DRIFT_VARS = /DATABASE_SCHEMA|POOL_IDS|PERP_ENGINE|START_BLOCK|COLLECTION_LEDGER|GOVERNOR_ADDRESS|HOOK_ADDRESS|REGISTRY_ADDRESS|POOL_MANAGER_ADDRESS/;
const vars = spawnSync("railway", ["variables"], { cwd: INDEXER, encoding: "utf8" });
if (vars.stdout && DRIFT_VARS.test(vars.stdout)) {
  const hits = vars.stdout.split("\n").map((l) => (l.match(DRIFT_VARS) || [])[0]).filter(Boolean);
  console.warn(`⚠  Railway has address/schema ENV VARS set (${[...new Set(hits)].join(", ")}) — these OVERRIDE the manifest and cause drift.`);
  console.warn("   Delete each:  echo y | railway variable delete <KEY>\n");
}

async function confirm() {
  if (skipConfirm) return;
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  const ans = await new Promise((res) => rl.question("Proceed with deploy? [y/N] ", res));
  rl.close();
  if (!/^y(es)?$/i.test(ans.trim())) { console.log("aborted."); process.exit(0); }
}

async function verify() {
  if (skipVerify) return;
  const base = m.indexerUrl.replace(/\/+$/, "");
  console.log(`\n⏳ verifying ${base} (pool + freshness)…`);
  const deadline = Date.now() + 10 * 60_000; // 10 min
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 15_000));
    try {
      const cauldron = await (await fetch(`${base}/cauldron?t=${Date.now()}`)).json();
      const fresh = await (await fetch(`${base}/freshness?t=${Date.now()}`)).json();
      const livePool = (cauldron.poolId ?? "").toLowerCase();
      const match = livePool === poolId.toLowerCase();
      console.log(`  pool=${livePool.slice(0, 12)}… match=${match} ok=${fresh.ok} warmingUp=${fresh.warmingUp ?? "?"}`);
      if (match && fresh.ok && fresh.warmingUp === false) { console.log("\n✅ indexer live + fully synced for this round."); return; }
    } catch { console.log("  (indexer not responding yet — still building/backfilling)"); }
  }
  console.warn("\n⚠  verify timed out. Check `railway logs` — a fresh backfill can take a few minutes.");
}

await confirm();

if (wantPush) {
  console.log("\n→ git push (frontend → Vercel)…");
  run("git", ["push"], { cwd: ROOT });
}

console.log("\n→ railway up (indexer)…");
run("railway", ["up", "--detach"], { cwd: INDEXER });

await verify();
console.log("\nDone. If you didn't --push, remember to push for the frontend to match.\n");
