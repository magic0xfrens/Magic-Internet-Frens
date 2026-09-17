// Production entrypoint: derive the Postgres schema from the SAME manifest the
// rest of the stack reads (deployments/round.json), then exec Ponder. This keeps
// the schema in ONE place — no hardcoded `--schema` in railway.json (which
// silently overrode both the config and DATABASE_SCHEMA env in past rounds and
// pinned the indexer to a dead schema). Bump `schema` in round.json → next deploy
// reindexes cleanly; keep it the same → Ponder resumes (crash recovery, no wipe).
import { readFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { startSeedKeeper } from "./seed-keeper.mjs";
import { patchFinality, verifyFinality } from "./scripts/patch-ponder-finality.mjs";

const manifest = JSON.parse(
  readFileSync(new URL("./deployments/round.json", import.meta.url), "utf8"),
);
const schema = manifest.schema;
if (!schema || !/^[a-z0-9_]+$/.test(schema)) {
  console.error(`[start] invalid schema in round.json: ${JSON.stringify(schema)}`);
  process.exit(1);
}
console.log(`[start] round ${manifest.round} → ponder start --schema ${schema}`);

//  ── REORG TOLERANCE, BEFORE ANYTHING INDEXES ──────────────────────────────
//  Ponder's finality is a hardcoded block count with no config lever (VERIFIED
//  against 0.11.44 — see scripts/patch-ponder-finality.mjs for the citation),
//  and its unknown-chain default of 30 blocks is ~3 SECONDS on a 0.1s chain
//  whose `finalized` tag lags the head by ~16 minutes. A reorg inside that gap
//  rewrites rows Ponder already pruned the journals for: unrevertable, wrong,
//  and still reported ok. This also runs from `postinstall`; it runs again here
//  because a deploy that skipped postinstall must not boot with the default,
//  and because being idempotent makes the second run free.
//
//  FATAL on failure, deliberately. An indexer that cannot prove its reorg
//  tolerance is worse than one that is down: down is visible.
try {
  patchFinality();
  await verifyFinality();
} catch (e) {
  console.error(String(e?.message ?? e));
  console.error("[start] refusing to index without a proven reorg tolerance");
  process.exit(1);
}

// Launch poke keeper — advances the seeder's liquidity stream + prime-buy
// tranches when the pool is quiet. Inert unless SEED_KEEPER_PK is set, and it
// runs in THIS process so it ships with the already-wired indexer deploy rather
// than needing a second Railway service.
//  Async now (it proves its chain identity before signing). Fire-and-forget,
//  but never silently: an unhandled rejection here would take the whole indexer
//  down for something that is meant to be optional.
startSeedKeeper().catch((e) => console.error(`[keeper] failed to start: ${String(e?.message ?? e)}`));

const child = spawn("npx", ["ponder", "start", "--schema", schema], {
  stdio: "inherit",
  env: process.env,
});
child.on("exit", (code) => process.exit(code ?? 1));
process.on("SIGTERM", () => child.kill("SIGTERM"));
process.on("SIGINT", () => child.kill("SIGINT"));
