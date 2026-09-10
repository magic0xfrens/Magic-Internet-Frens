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
  //  CREATE **AND** CREATE2. Filtering to CREATE alone made every CREATE2
  //  deployment invisible to `pick()`, which is why the hook — mined to a salt
  //  and therefore always CREATE2 — could never be found by name and fell
  //  through to the "ask the chain" path. Foundry does record its contractName,
  //  so there was never a reason to guess.
  const creates = (run.transactions ?? []).filter(
    (t) => (t.transactionType === "CREATE" || t.transactionType === "CREATE2") && t.contractAddress,
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

//  CauldronHook is CREATE2-deployed via a mined salt.
//
//  Taking "the first CREATE2" is WRONG and shipped a broken manifest once:
//  linked libraries (FeeRouteLib, PoolOps) are CREATE2-deployed too and come
//  first, so `hook` ended up pointing at FeeRouteLib — an address with real code
//  that answers no hook call, which fails at runtime rather than at deploy.
//
//  Foundry DOES record the name on a CREATE2, so the fix is simply to look it up
//  like any other contract; `loadBroadcast` was dropping CREATE2 entirely, which
//  is what made it look nameless. The registry lookup below stays as the
//  fallback for a broadcast that genuinely lacks it — that is the address the
//  protocol actually uses, which is the only definition that matters.
function hookFromRegistry(registry) {
  const tx = launchpad.creates.find((t) => t.contractName === "CauldronHook");
  if (tx?.contractAddress) return tx.contractAddress;   // named CREATE, if present
  return registry ? "__ASK_CHAIN__" : null;
}

const m = JSON.parse(readFileSync(manifestPath, "utf8"));
const m0 = m;
const prevRound = Number(m.round ?? 0);

//  Only overwrite what was actually redeployed. A partial redeploy must not
//  blank the addresses it did not touch.
const updates = {
  registry: pick("CauldronRegistry", launchpad),
  hook: hookFromRegistry(m0.contracts?.registry),
  governor: pick("CauldronGovernor", launchpad),
  dividend: pick("MiFrensDividend", launchpad),
  presale: pick("MiFrensGenesis", launchpad),
  gachaRouter: pick("CauldronGachaRouter", launchpad),
  collectionLedger: pick("CollectionLedger", launchpad),
  factory: pick("CauldronFactory", launchpad),
  // The launch poke keeper reads this to know what to poke; without it the
  // keeper is inert and the stream depends entirely on organic trades.
  seeder: pick("CauldronSeeder", launchpad),
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

//  The quote mocks. DeployLaunchpad now deploys these itself (the rotation stack
//  was folded into it so the venue cannot end up curated on the wrong rotator),
//  so look there FIRST and fall back to a standalone DeployRotationStack run.
//  Missing this is why an earlier version left `quoteAssets[].address` pointing
//  at the previous round's USDG while every other address moved — the frontend
//  would then offer a quote the new registry has never allowlisted.
const quoteSrc = launchpad.creates.some((t) => t.contractName === "MockQuoteToken")
  ? launchpad
  : rotation;
if (quoteSrc.found) {
  const usdg = pickNth("MockQuoteToken", 0, quoteSrc);
  const xnvda = pickNth("MockQuoteToken", 1, quoteSrc);
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

//  ── THE START BLOCK MUST MOVE WITH THE ADDRESSES ────────────────────────
//  `ponder.config.ts` uses `blocks.indexer` as its startBlock. Leaving it at the
//  PREVIOUS round's block makes the indexer rescan every block since the old
//  deployment — slow, and it indexes events from contracts that are no longer
//  the live ones. Take it from the earliest block this deployment actually
//  touched, minus a small margin so nothing at the boundary is missed.
let firstBlock = null;
for (const src of [launchpad, rotation, perp]) {
  if (!src.found) continue;
  const p = src.path.replace("run-latest.json", "run-latest.json");
  try {
    const run = JSON.parse(readFileSync(p, "utf8"));
    for (const r of run.receipts ?? []) {
      const b = Number(r.blockNumber);
      if (Number.isFinite(b) && b > 0 && (firstBlock === null || b < firstBlock)) firstBlock = b;
    }
  } catch { /* no receipts yet */ }
}
if (firstBlock !== null && applied.length > 0) {
  const start = Math.max(0, firstBlock - 10);
  const before = m.blocks?.indexer;
  m.blocks = { deploy: start, perp: start, indexer: start };
  applied.push(["blocks.indexer", before ?? "(new)", start]);
}

//  ── THE POOL ID, READ FROM THE CHAIN ────────────────────────────────────
//  `poolIds` is what stops the indexer from watching EVERY Uniswap v4 swap on
//  the chain, so a stale one means the indexer watches the PREVIOUS round's pool
//  and reports no activity at all for the new one — a failure that looks like a
//  dead protocol rather than a misconfiguration.
//
//  It cannot come from the broadcast: the pool does not exist until `finalize()`
//  summons it, which is a later transaction than the deploy. So it is read from
//  the registry, and this step is skipped (with a warning) when no RPC is
//  reachable — a manifest with old addresses and a new poolId would be worse
//  than one this script left alone.
async function readPoolId(registry) {
  const rpc = process.env.RPC_URL || process.env.SEPOLIA_RPC ||
    "https://ethereum-sepolia-rpc.publicnode.com";
  const call = async (data) => {
    const r = await fetch(rpc, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_call",
        params: [{ to: registry, data }, "latest"] }),
    });
    const j = await r.json();
    if (j.error) throw new Error(j.error.message);
    return j.result;
  };
  //  Selectors verified with `cast sig`, not derived by hand — an invented
  //  selector reverts, and a reverting read here would silently leave `poolIds`
  //  pointing at the previous round.
  //    currentGeneration()        0x8ddb428a
  //    generationPoolId(uint256)  0xcb648bed
  const gen = BigInt(await call("0x8ddb428a"));
  const arg = gen.toString(16).padStart(64, "0");
  const id = await call("0xcb648bed" + arg);
  return { gen: Number(gen), poolId: id };
}

//  Resolve the hook from the registry when the broadcast could not name it.
if (m.contracts.hook === "__ASK_CHAIN__") {
  try {
    const rpc = process.env.RPC_URL || "https://ethereum-sepolia-rpc.publicnode.com";
    const r = await fetch(rpc, { method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_call",
        params: [{ to: m.contracts.registry, data: "0x7f5a7c7b" }, "latest"] }) });
    const j = await r.json();
    m.contracts.hook = "0x" + String(j.result).slice(-40);
  } catch { m.contracts.hook = m0.contracts.hook; }
}

if (applied.length > 0 && m.contracts.registry) {
  try {
    const { gen, poolId } = await readPoolId(m.contracts.registry);
    if (poolId && !/^0x0{64}$/.test(poolId)) {
      if (!same(m.poolIds?.[0], poolId)) {
        applied.push(["poolIds[0]", m.poolIds?.[0] ?? "(new)", poolId]);
        m.poolIds = [poolId];
      }
    } else {
      console.log(`\n  NOTE: generation ${gen} has no pool yet — run finalize() to summon,`);
      console.log("        then re-run this script so `poolIds` is updated.");
    }
  } catch (e) {
    console.log(`\n  WARNING: could not read the pool id (${e.message}).`);
    console.log("           `poolIds` is UNCHANGED and may point at the previous round.");
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
  "gachaRouter", "collectionLedger", "poolManager", "positionManager", "seeder",
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
