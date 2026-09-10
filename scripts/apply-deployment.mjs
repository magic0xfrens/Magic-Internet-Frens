#!/usr/bin/env node
/**
 * Fold a deployment's broadcast artifacts into the manifest.
 *
 * `indexer/deployments/round.json` is the single source of truth the frontend
 * AND the indexer both read, and its own header warns that mirroring these
 * values into hosting env vars makes them drift the moment one is changed alone.
 * Editing it by hand after a deploy is that hazard one step removed: sixteen
 * addresses copied from console output, and a typo in any of them points half
 * the app at a contract that does not exist.
 *
 * Reads the addresses back out of Foundry's own broadcast artifacts — the record
 * of what was actually MINED, not what a script intended — and writes them in.
 *
 * Reads BOTH deploy scripts, because a full redeploy runs both and a manifest
 * that captured only one would be half-stale, which is worse than one that is
 * wholly stale: the app would half-work and the failures would look like bugs.
 *
 * Usage:
 *   node scripts/apply-deployment.mjs [--chain 11155111] [--dry]
 */
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const argv = process.argv.slice(2);
const dry = argv.includes("--dry");
const ci = argv.indexOf("--chain");
const chain = ci >= 0 && argv[ci + 1] ? argv[ci + 1] : "11155111";

const manifestPath = join(root, "indexer/deployments/round.json");

/** CREATE records from one broadcast, newest wins. Missing file is not fatal —
 *  the rotation stack is optional if you only redeployed the core. */
function loadBroadcast(script) {
  const p = join(root, `contracts/solidity/broadcast/${script}/${chain}/run-latest.json`);
  if (!existsSync(p)) return { found: false, creates: [], path: p };
  const run = JSON.parse(readFileSync(p, "utf8"));
  const creates = (run.transactions ?? []).filter(
    (t) => t.transactionType === "CREATE" && t.contractAddress,
  );
  return { found: true, creates, path: p };
}

const launchpad = loadBroadcast("DeployLaunchpad.s.sol");
const rotation = loadBroadcast("DeployRotationStack.s.sol");
const perp = loadBroadcast("DeployPerp.s.sol");

if (!launchpad.found && !rotation.found && !perp.found) {
  console.error(
    `No broadcast found for chain ${chain}.\n` +
      `Run a deploy with --broadcast first, e.g.:\n` +
      `  forge script deploy/DeployLaunchpad.s.sol --tc DeployLaunchpad --rpc-url $RPC --broadcast`,
  );
  process.exit(1);
}

/** Last CREATE with this contractName across the given broadcasts. */
function pick(name, ...sources) {
  for (const src of sources) {
    const hit = [...src.creates].reverse().find((t) => t.contractName === name);
    if (hit) return hit.contractAddress;
  }
  return null;
}

/** Nth CREATE of a repeated contract (MockQuoteToken is deployed twice). */
function pickNth(name, n, src) {
  const all = src.creates.filter((t) => t.contractName === name);
  return all[n]?.contractAddress ?? null;
}

//  CauldronHook is CREATE2-deployed via a mined salt, and Foundry records those
//  without a `contractName`. Recover it from the deploy log instead of guessing.
function hookFromLog() {
  const p = join(root, `contracts/solidity/broadcast/DeployLaunchpad.s.sol/${chain}/run-latest.json`);
  if (!existsSync(p)) return null;
  const run = JSON.parse(readFileSync(p, "utf8"));
  const c2 = (run.transactions ?? []).find(
    (t) => t.transactionType === "CREATE2" && t.contractAddress,
  );
  return c2?.contractAddress ?? null;
}

const m = JSON.parse(readFileSync(manifestPath, "utf8"));
const prevRound = Number(m.round ?? 0);

//  Only overwrite what was actually redeployed. A partial redeploy must not
//  blank the addresses it did not touch.
const updates = {
  registry: pick("CauldronRegistry", launchpad),
  hook: hookFromLog(),
  governor: pick("CauldronGovernor", launchpad),
  dividend: pick("MiFrensDividend", launchpad),
  presale: pick("MiFrensGenesis", launchpad),
  gachaRouter: pick("CauldronGachaRouter", launchpad),
  collectionLedger: pick("CollectionLedger", launchpad),
  factory: pick("CauldronFactory", launchpad),
  quoteRotator: pick("QuoteRotator", rotation, launchpad),
  treasuryGovernor: pick("TreasuryGovernor", rotation, launchpad),
  quoteOracle: pick("QuoteOracle", rotation, launchpad),
  perpEngine: pick("PerpEngine", perp),
  perpVault: pick("PerpVault", perp),
};

//  Addresses compare case-INSENSITIVELY. Foundry writes them lowercase and the
//  manifest carries EIP-55 checksums, so a naive !== reports every address as
//  changed — which would bump `schema` and force a full, pointless reindex on a
//  run that deployed nothing.
const same = (a, b) => !!a && !!b && a.toLowerCase() === b.toLowerCase();

const applied = [];
for (const [k, v] of Object.entries(updates)) {
  if (!v) continue;
  if (!same(m.contracts[k], v)) {
    applied.push([k, m.contracts[k] ?? "(new)", v]);
    m.contracts[k] = v;   // only rewrite on a REAL change, so checksums survive
  }
}

//  The quote mocks, if the rotation stack ran. USDG is the first MockQuoteToken
//  CREATE; a second would be a synthetic equity (not deployed by default).
if (rotation.found) {
  const usdg = pickNth("MockQuoteToken", 0, rotation);
  const xnvda = pickNth("MockQuoteToken", 1, rotation);
  for (const q of m.quoteAssets ?? []) {
    if (q.symbol === "USDG" && usdg && !same(q.address, usdg)) {
      applied.push(["quoteAssets.USDG", q.address, usdg]);
      q.address = usdg;
    }
    if (q.symbol === "xNVDA" && xnvda && !same(q.address, xnvda)) {
      applied.push(["quoteAssets.xNVDA", q.address, xnvda]);
      q.address = xnvda;
    }
  }
}

//  A fresh set of contracts means the indexed history describes contracts that
//  no longer exist. Bumping `schema` is what forces Ponder to drop the old
//  tables and reindex — without it the app serves the PREVIOUS round's data
//  against the NEW addresses, which is the exact failure this field exists to
//  prevent. Only bump when something actually moved.
if (applied.length > 0) {
  m.round = prevRound + 1;
  m.schema = `cauldron_r${m.round}`;
  applied.push(["round", prevRound, m.round]);
  applied.push(["schema", "", m.schema]);
}

console.log(`chain ${chain}`);
console.log(
  `  broadcasts: launchpad=${launchpad.found} rotation=${rotation.found} perp=${perp.found}`,
);
if (applied.length === 0) {
  console.log("\n  nothing changed — the manifest already matches the broadcasts.");
  process.exit(0);
}
console.log("");
for (const [k, from, to] of applied) {
  console.log(`  ${String(k).padEnd(22)} ${String(from).slice(0, 12).padEnd(14)} -> ${to}`);
}

//  Anything the app reads that is STILL unset after this is a wiring hole. Say
//  so loudly: a missing address does not fail at deploy, it fails later as a
//  feature that silently does nothing.
const required = [
  "registry", "hook", "governor", "dividend", "presale",
  "gachaRouter", "collectionLedger", "poolManager", "positionManager",
];
const missing = required.filter((k) => !m.contracts[k] || /^0x0{40}$/.test(m.contracts[k]));
if (missing.length) {
  console.log(`\n  WARNING - still unset, the app will half-work: ${missing.join(", ")}`);
}
if (!m.contracts.treasuryGovernor || !m.contracts.quoteRotator) {
  console.log("  WARNING - rotation stack not in the manifest: the treasury UI will show 'not wired'.");
}

if (dry) {
  console.log("\n--dry: manifest NOT written.");
  process.exit(0);
}
writeFileSync(manifestPath, JSON.stringify(m, null, 2) + "\n");
console.log(`\nWrote ${manifestPath}`);
console.log("Next: cd indexer && railway up   (schema bumped -> clean reindex)");
console.log("      npm run build");
