#!/usr/bin/env node
/**
 * PONDER'S REORG TOLERANCE, MADE TO MATCH THE CHAIN WE ACTUALLY INDEX.
 *
 *  ── THE DEFECT ────────────────────────────────────────────────────────────
 *  `ponder/dist/esm/utils/finality.js` switches on the chain id and falls
 *  through to `finalityBlockCount = 30` for anything it does not know, with the
 *  comment "Assume a 2-second block time". Robinhood Chain 4663 produces a block
 *  roughly every 0.10 s, so 30 blocks is about THREE SECONDS of reorg tolerance
 *  against a chain whose `finalized` tag lags the head by ~9,650 blocks
 *  (~16 minutes) — measured, see audit/RH_MAINNET_2026-09-16/CHAIN_PROFILE.md §3.
 *
 *  Two failure modes follow, and the second is worse than the first:
 *    - a reorg deeper than 30 blocks throws in the realtime sync, retries ~14
 *      times, then exits: loud, recoverable, visible.
 *    - a reorg between 30 and ~9,650 blocks rewrites rows Ponder already treated
 *      as final and whose reorg journals it has PRUNED. Unrevertable, wrong, and
 *      the service still reports ok:true.
 *
 *  ── WHY A PATCH AND NOT CONFIG ────────────────────────────────────────────
 *  VERIFIED against ponder 0.11.44: `finalityBlockCount` is NOT settable from
 *  ponder.config.ts. `build/config.js:115` assigns it solely from
 *  `getFinalityBlockCount({ chain: matchedChain })`, and the user-facing
 *  `ChainConfig` type (dist/types/config/index.d.ts:68-90) exposes only
 *  id/rpc/ws/pollingInterval/maxRequestsPerSecond/disableCache. There is no
 *  supported override, and Ponder never requests `blockTag:"finalized"`
 *  (`build/config.js:141-145` uses `latest - finalityBlockCount`).
 *
 *  So the lever is the installed module — but an ad-hoc edit inside
 *  node_modules is lost on the next install, silently, restoring the Critical.
 *  This script is that edit made durable and auditable: it is committed, it runs
 *  from `postinstall` AND from `start.mjs` before Ponder is spawned, it is
 *  idempotent, and it VERIFIES the result by importing the patched module and
 *  calling it rather than trusting that the text edit did what it looked like.
 *  Every failure path exits non-zero: the indexer must not boot with a tolerance
 *  it cannot prove.
 *
 *  ── THE NUMBERS ARE MEASURED, NOT ASSUMED ─────────────────────────────────
 *  The live `latest - finalized` gap is checked against the value patched here
 *  CONTINUOUSLY, by `/freshness` (`indexer/src/api/index.ts:1497-1513`), which
 *  reports `reorgToleranceOk` and 503s when the chain's real finality distance
 *  outgrows this table. A constant alone would be the same class of mistake as
 *  the one it replaces; that runtime check is what makes it self-correcting.
 *
 *  (`start.mjs` does NOT make that comparison — it calls `patchFinality` and
 *  `verifyFinality` only, `start.mjs:34-41`. An earlier version of this comment
 *  claimed otherwise. The check is real; it lives in the API, not at boot.)
 */
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");
const TARGET = join(ROOT, "node_modules/ponder/dist/esm/utils/finality.js");

/**
 * Reorg tolerance per chain, in BLOCKS, derived from each chain's own measured
 * `latest - finalized` distance — not from an assumed block time.
 *   4663  : ~9,650 blocks ≈ 16 min at ~0.10 s/block (CHAIN_PROFILE §3), rounded
 *           up to 12,000 for headroom, since being early costs memory and being
 *           late costs unrevertable corruption. Re-measured 2026-09-16: latest
 *           64,645,113 @ ts 1,789,575,427 vs finalized 64,636,839 @ ts
 *           1,789,574,597 → 8,274 blocks over 830 s → 0.1003 s/block. Both
 *           measurements sit under 12,000; the block time is confirmed.
 *   46630 : same architecture (Robinhood testnet), same allowance.
 *   5042002: Arc testnet, ~1 s blocks; 1,200 blocks ≈ 20 min.
 *   11155111: Sepolia. NOT a leftover — it is here because Ponder's OWN value
 *           for Sepolia is 65 blocks while the chain's measured `finalized` lag
 *           is 77 (latest 11,717,848 vs finalized 11,717,771, 2026-09-16).
 *           Ethereum finalises at 2 epochs = 64 slots, so the tag legitimately
 *           trails by 64-95 blocks; 65 is inside that range, which means
 *           Ponder was already treating rewritable blocks as final on the chain
 *           this stack runs on TODAY — the same defect this file was written to
 *           fix for 4663, simply never noticed because Sepolia is in Ponder's
 *           table and so looked deliberate. 128 = 2 x the 64-slot epoch, clear
 *           of the 95-block worst case, ~25 min at 12 s blocks. The journal
 *           cost of 128 blocks is negligible.
 */
export const FINALITY_BLOCKS = {
  4663: 12_000,
  46630: 12_000,
  5042002: 1_200,
  11155111: 128,
};

const MARK = "/* mifrens: chain-aware finality */";

export function patchFinality({ quiet = false } = {}) {
  let src;
  try {
    src = readFileSync(TARGET, "utf8");
  } catch (e) {
    throw new Error(
      `[finality] cannot read ${TARGET}: ${e.message}\n` +
        `  Ponder is not installed, or its layout changed. The indexer must NOT start with ` +
        `Ponder's default 30-block reorg tolerance on a sub-second chain.`,
    );
  }

  //  ── WHERE THE CASES GO, AND WHY IT IS THE TOP ─────────────────────────
  //  These cases are inserted at the HEAD of the switch, not ahead of
  //  `default:`. A switch takes the FIRST matching case, so anything inserted
  //  before `default:` is reachable only for chains Ponder does not already
  //  know. For 4663 that happened to be true, which is why it worked. For any
  //  chain Ponder DOES list — Sepolia among them — an inserted case is dead
  //  code that changes nothing, and `verifyFinality` below would then see the
  //  module return Ponder's value instead of ours and abort the boot.
  //  VERIFIED by execution: a `case 11155111: 128` placed before `default:`
  //  left the module still returning 65.
  //  Inserting at the head makes this table authoritative for every chain,
  //  which is the only reading under which "the tolerance we prove is the
  //  tolerance we run" is true.
  const anchor = "    switch (chain?.id) {";
  if (!src.includes(anchor)) {
    throw new Error(
      `[finality] anchor not found in ${TARGET}. Ponder's getFinalityBlockCount has changed shape; ` +
        `re-derive this patch against the new source before deploying.`,
    );
  }

  //  Strip any block a previous version of this script wrote, then insert
  //  fresh. That keeps the script idempotent AND migrates a tree still
  //  carrying the old before-`default:` placement — which a plain
  //  `includes(MARK)` early-return would have left in place forever, since it
  //  reads as "already patched".
  const existing = new RegExp(
    `${MARK.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\n(?:        case \\d+:\\n            finalityBlockCount = \\d+;\\n            break;\\n)+`,
    "g",
  );
  const had = existing.test(src);
  src = src.replace(existing, "");

  const cases = Object.entries(FINALITY_BLOCKS)
    .map(([id, n]) => `        case ${id}:\n            finalityBlockCount = ${n};\n            break;`)
    .join("\n");
  const next = src.replace(anchor, `${anchor}\n${MARK}\n${cases}`);

  if (next !== readFileSync(TARGET, "utf8")) {
    writeFileSync(TARGET, next);
    if (!quiet) console.log(`[finality] ${had ? "re-patched" : "patched"} ${TARGET}`);
  } else if (!quiet) {
    console.log("[finality] already patched");
  }
  return TARGET;
}

/** Prove the patch by CALLING the patched module, not by re-reading the text. */
export async function verifyFinality({ quiet = false } = {}) {
  const mod = await import(`${pathToFileURL(TARGET).href}?v=${Date.now()}`);
  const bad = [];
  for (const [id, want] of Object.entries(FINALITY_BLOCKS)) {
    const got = mod.getFinalityBlockCount({ chain: { id: Number(id) } });
    if (got !== want) bad.push(`chain ${id}: expected ${want}, module returned ${got}`);
    else if (!quiet) console.log(`[finality] chain ${id} → ${got} blocks`);
  }
  if (bad.length) {
    throw new Error(`[finality] patch did not take effect:\n  ${bad.join("\n  ")}`);
  }
  return true;
}

//  Run directly (postinstall, or by hand) — any failure is fatal on purpose.
if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  try {
    patchFinality();
    await verifyFinality();
  } catch (e) {
    console.error(String(e.message ?? e));
    process.exit(1);
  }
}
