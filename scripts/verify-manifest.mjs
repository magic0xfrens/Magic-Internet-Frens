#!/usr/bin/env node
/**
 * Manifest guard. Runs on prebuild.
 *
 * indexer/deployments/round.json is the ONE place the live deployment is
 * described. The frontend and the indexer both import it, so they cannot
 * disagree by construction — but only as long as nothing reintroduces a second
 * source. This script fails the build if either happens:
 *
 *   1. the manifest itself is malformed, or
 *   2. a deployment address gets hardcoded or env-overridden somewhere.
 *
 * Both failures are silent at runtime — the app just shows stale or empty data,
 * with no error saying an address was wrong — which is exactly why they are
 * worth catching here instead.
 */
import { readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const MANIFEST = join(ROOT, "indexer", "deployments", "round.json");

const REQUIRED_CONTRACTS = [
  "registry", "hook", "poolManager", "positionManager", "governor", "dividend",
  "presale", "gachaRouter", "timelock", "collectionLedger", "perpEngine", "perpVault",
];

const isAddress = (v) => typeof v === "string" && /^0x[0-9a-fA-F]{40}$/.test(v);
const isHash32 = (v) => typeof v === "string" && /^0x[0-9a-fA-F]{64}$/.test(v);

const errors = [];
const warnings = [];

let m;
try {
  m = JSON.parse(readFileSync(MANIFEST, "utf8"));
} catch (e) {
  console.error(`✗ cannot read/parse ${relative(ROOT, MANIFEST)}\n  ${e.message}`);
  process.exit(1);
}

/* ── 1. the manifest is well-formed ──────────────────────────────────────── */
if (!Number.isInteger(m.chainId)) errors.push("`chainId` must be an integer");
if (typeof m.schema !== "string" || !/^[a-z0-9_]+$/.test(m.schema))
  errors.push("`schema` must be lowercase [a-z0-9_] — it becomes a Postgres schema name");
if (typeof m.indexerUrl !== "string" || !/^https?:\/\/[^/]+/.test(m.indexerUrl))
  errors.push("`indexerUrl` must be an absolute http(s) URL");
if (typeof m.indexerUrl === "string" && /\/$/.test(m.indexerUrl))
  warnings.push("`indexerUrl` has a trailing slash; it is stripped at read time");

for (const k of REQUIRED_CONTRACTS) {
  const v = m.contracts?.[k];
  if (v === undefined) errors.push(`contracts.${k} is missing`);
  else if (!isAddress(v)) errors.push(`contracts.${k} is not a 20-byte address: ${v}`);
}

// A duplicated address is almost always a copy/paste slip during a redeploy.
const seen = new Map();
for (const [k, v] of Object.entries(m.contracts ?? {})) {
  if (!isAddress(v)) continue;
  const lower = v.toLowerCase();
  if (seen.has(lower)) errors.push(`contracts.${k} duplicates contracts.${seen.get(lower)} (${v})`);
  else seen.set(lower, k);
}

for (const k of ["deploy", "perp", "indexer"]) {
  const v = m.blocks?.[k];
  if (!Number.isInteger(v) || v <= 0) errors.push(`blocks.${k} must be a positive integer`);
}
// Indexing from after the deploy block silently drops the genesis mints, which
// shows up much later as "My MiFrens is empty" rather than as an indexer error.
if (Number.isInteger(m.blocks?.indexer) && Number.isInteger(m.blocks?.deploy)
    && m.blocks.indexer > m.blocks.deploy) {
  errors.push(
    `blocks.indexer (${m.blocks.indexer}) is AFTER blocks.deploy (${m.blocks.deploy}) — ` +
    "the indexer would miss the genesis mints",
  );
}

if (!Array.isArray(m.poolIds) || m.poolIds.length === 0)
  errors.push("`poolIds` must be non-empty — without it the indexer would index EVERY V4 swap on the chain");
else m.poolIds.forEach((p, i) => {
  if (!isHash32(p)) errors.push(`poolIds[${i}] is not a 32-byte pool id: ${p}`);
});

/* ── 2. nothing bypasses the manifest ────────────────────────────────────── */
const SCAN_DIRS = ["src", "api", "indexer/src", "indexer/ponder.config.ts"];
const SKIP = /node_modules|\.ponder|generated|dist|deployments|abis|\.test\./;

// Deployment identity must never come from env. Infra (RPC endpoints, database
// URLs, secrets, tuning) legitimately does, so only these names are rejected.
const BANNED_ENV = [
  "VITE_CAULDRON_INDEXER", "VITE_PERP_ENGINE", "VITE_PERP_VAULT",
  "VITE_PERP_START_BLOCK", "VITE_CAULDRON_REGISTRY", "CHAIN_ID",
  "POSITION_MANAGER", "REGISTRY_ADDRESS", "POOL_MANAGER_ADDRESS", "START_BLOCK",
];

const manifestAddresses = new Set(
  Object.values(m.contracts ?? {}).filter(isAddress).map((a) => a.toLowerCase()),
);

function* walk(p) {
  const abs = join(ROOT, p);
  let st;
  try { st = statSync(abs); } catch { return; }
  if (st.isFile()) { yield p; return; }
  for (const e of readdirSync(abs)) {
    const next = `${p}/${e}`;
    if (SKIP.test(next)) continue;
    yield* walk(next);
  }
}

for (const dir of SCAN_DIRS) {
  for (const rel of walk(dir)) {
    if (!/\.(ts|tsx|mjs|js)$/.test(rel)) continue;
    const text = readFileSync(join(ROOT, rel), "utf8");

    // Match an actual env READ, not any mention of the name — otherwise
    // ACTIVE_CHAIN_ID trips the CHAIN_ID rule and POSITION_MANAGER_ABI trips
    // POSITION_MANAGER.
    for (const name of BANNED_ENV) {
      const read = new RegExp(
        String.raw`(?:process\.env|import\.meta\.env)\??\.` + name + String.raw`\b`,
      );
      if (read.test(text)) {
        errors.push(`${rel} reads ${name} — deployment identity must come from the manifest`);
      }
    }

    // A hardcoded address that the manifest also defines is a second source of
    // truth, and the one most likely to be missed on a redeploy.
    for (const lit of text.match(/0x[0-9a-fA-F]{40}/g) ?? []) {
      if (manifestAddresses.has(lit.toLowerCase())) {
        errors.push(`${rel} hardcodes ${lit}, which the manifest already defines`);
      }
    }
  }
}

/* ── report ──────────────────────────────────────────────────────────────── */
for (const w of new Set(warnings)) console.warn(`⚠ ${w}`);

const unique = [...new Set(errors)];
if (unique.length) {
  console.error(`\n✗ manifest check failed (${unique.length}):`);
  for (const e of unique) console.error(`  · ${e}`);
  console.error("\n  Everything about the live deployment lives in");
  console.error("  indexer/deployments/round.json. Change it there.\n");
  process.exit(1);
}

console.log(`✓ manifest OK — chain ${m.chainId}, schema ${m.schema}, ${m.poolIds.length} pool(s)`);
console.log(`  indexer  ${m.indexerUrl}`);
console.log(`  registry ${m.contracts.registry}`);
console.log("  no hardcoded addresses, no env overrides");
