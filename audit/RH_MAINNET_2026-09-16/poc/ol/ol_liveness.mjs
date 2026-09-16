// OFF-CHAIN LIVENESS — regression test for OL-1 (Critical), OL-2, OL-3, OL-4.
//
// OL-1  Ponder's reorg tolerance on chain 4663 was its unknown-chain DEFAULT of
//       30 blocks ("assume a 2-second block time"), i.e. ~3 SECONDS on a 0.10s
//       chain whose `finalized` tag lags the head by ~9,650 blocks (~16 min).
//       A reorg inside that gap rewrites rows Ponder already treated as final
//       and whose reorg journals it has PRUNED: unrevertable, wrong, ok:true.
//       VERIFIED: ponder 0.11.44 exposes no config lever — build/config.js:115
//       takes it only from getFinalityBlockCount(), and the user-facing
//       ChainConfig type has no such field. So the fix is a COMMITTED,
//       self-verifying patch (postinstall + start.mjs), plus a continuous
//       live check in /freshness so the constant cannot drift from the chain.
// OL-2  scripts/keeper.sh resolved gacha every ~64s on a chain whose 256-block
//       commit window is 25.6s — 2.5x OUTSIDE it.
// OL-3  indexer/seed-keeper.mjs hardcoded `chain: sepolia`, so every poke() was
//       signed for 11155111 and rejected, swallowed as "poke skipped".
// OL-4  /freshness carried no height or lag, so a 40-minute-stale indexer read
//       as healthy to the only thing that polls it.
//
// PASS = exit 0 and "RESULT: SAFE".
// Run:  node audit/RH_MAINNET_2026-09-16/poc/ol/ol_liveness.mjs
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../../..");
const read = (p) => readFileSync(join(ROOT, p), "utf8");
let fail = 0;
const chk = (d, ok) => { console.log(`  ${ok ? "ok  " : "FAIL"} — ${d}`); if (!ok) fail = 1; };

console.log("── OL-1: reorg tolerance ──");
const { FINALITY_BLOCKS, verifyFinality } = await import(
  join(ROOT, "indexer/scripts/patch-ponder-finality.mjs")
);
// Ponder's own default, quoted from the module we are correcting.
const ponderSrc = read("indexer/node_modules/ponder/dist/esm/utils/finality.js");
chk("Ponder's unknown-chain default is still the 30 we are overriding",
  /finalityBlockCount = 30;/.test(ponderSrc) && /Assume a 2-second block time/.test(ponderSrc));
chk("the patch is applied to the installed module", ponderSrc.includes("case 4663:"));
// The load-bearing assertion: CALL the patched module, do not re-read its text.
let verified = false;
try { verified = await verifyFinality({ quiet: true }); } catch (e) { console.log(`     ${e.message}`); }
chk("the patched module RETURNS the intended tolerance when called", verified === true);
const lagBlocks = 9650;   // measured latest-finalized on 4663, CHAIN_PROFILE §3
console.log(`     chain 4663: tolerance ${FINALITY_BLOCKS[4663]} blocks vs a measured ${lagBlocks}-block finality lag`);
chk("4663's tolerance covers its measured finality lag", FINALITY_BLOCKS[4663] >= lagBlocks);
chk("…with headroom, since being early costs memory and being late costs corruption",
  FINALITY_BLOCKS[4663] >= lagBlocks * 1.2);
// Durability: an edit inside node_modules that is not re-applied is not a fix.
const pkg = JSON.parse(read("indexer/package.json"));
chk("the patch runs from postinstall", /patch-ponder-finality/.test(pkg.scripts?.postinstall ?? ""));
const start = read("indexer/start.mjs");
chk("…and again from start.mjs, before Ponder is spawned",
  /patchFinality\(\);/.test(start) && /await verifyFinality\(\)/.test(start)
  && start.indexOf("verifyFinality") < start.indexOf('spawn("npx"'));
chk("a failure to prove the tolerance is FATAL, not a warning",
  /refusing to index without a proven reorg tolerance/.test(start) && /process\.exit\(1\)/.test(start));

console.log("── OL-4: /freshness is machine-checkable ──");
const api = read("indexer/src/api/index.ts");
for (const f of ["chainHeight", "indexedHeight", "lagBlocks", "lagSeconds", "finalizedHeight", "finalityLagBlocks", "finalityBlockCount", "reorgToleranceOk"]) {
  chk(`/freshness reports \`${f}\``, new RegExp(`\\b${f}\\b`).test(api));
}
chk("an exceeded reorg tolerance makes the beacon NOT ok",
  /ok: ok && reorgToleranceOk !== false/.test(api) && /reorgToleranceExceeded/.test(api));
chk("an unknown finality (no `finalized` tag) is null, not a claim of health",
  /finalityLagBlocks === null \? null :/.test(api));
chk("the tolerance reported is the SAME table the patch applies",
  /import \{ FINALITY_BLOCKS \} from "\.\.\/\.\.\/scripts\/patch-ponder-finality\.mjs"/.test(api));

console.log("── OL-2: keeper cadence vs the 256-block gacha window ──");
const keeper = read("scripts/keeper.sh");
chk("the stale '~51 min on Sepolia' justification is gone", !/order of magnitude inside the window/.test(keeper));
chk("cadence is derived from the chain's block time", /case "\$CHAIN_ID" in/.test(keeper) && /4663\|46630\) BLOCK_MS=100/.test(keeper));
chk("an unknown chain assumes the SLOW case (resolves too often, never too rarely)",
  /\*\)\s*BLOCK_MS=12000/.test(keeper));
const sim = (blockMs) => {
  const w = Math.floor(256 * blockMs / 1000);
  let sleep = Math.floor(w / 4); if (sleep < 2) sleep = 2; if (sleep > 8) sleep = 8;
  let rs = Math.floor(w / 4); if (rs > 64) rs = 64;
  let every = Math.floor(rs / sleep); if (every < 1) every = 1;
  return { w, period: sleep * every };
};
for (const [name, ms] of [["4663", 100], ["arc", 1000], ["sepolia", 12000]]) {
  const { w, period } = sim(ms);
  console.log(`     ${name.padEnd(8)} window ${w}s · resolve every ${period}s · ${(w / period).toFixed(1)}x inside`);
  chk(`${name}: the resolve period is at least 4x inside the commit window`, w / period >= 4);
}
chk("sepolia's long-standing 64s cadence is not slowed down", sim(12000).period === 64);

console.log("── OL-3: the launch-liquidity keeper signs for the right chain ──");
const sk = read("indexer/seed-keeper.mjs");
// (the comment in seed-keeper.mjs quotes the old line on purpose — assert the
// CODE is gone, not the string.)
chk("`chain: sepolia` is gone as code", !/createPublicClient\(\{ chain: sepolia/.test(sk) && !/import \{ sepolia \}/.test(sk));
chk("the chain is built from the manifest's chainId", /id: chainId,/.test(sk) && /const chainId = Number\(manifest\.chainId\)/.test(sk));
chk("the identity is PROVEN against the RPC before anything is signed", /await pub\.getChainId\(\)/.test(sk) && /CHAIN MISMATCH/.test(sk));
chk("a mismatch refuses loudly instead of poking forever", /Keeper not started/.test(sk) && /console\.error/.test(sk));
chk("a chain-identity rejection is no longer logged as routine 'poke skipped'", /REJECTED \(chain identity\?\)/.test(sk));

console.log("── property that must NOT regress: every sender stays level-triggered ──");
chk("seed-keeper recomputes target-placed from fresh reads each tick",
  /const step = target > placed \? target - placed : 0n;/.test(sk));
chk("no off-chain memory of a completed poke (no 'already done' flag)",
  !/alreadyPoked|lastPokedAt|doneOnce|hasPoked/.test(sk));
chk("keeper.sh re-reads liquidatability every sweep", /isLiquidatable/.test(keeper));

console.log();
if (fail) { console.log("RESULT: REGRESSED."); process.exit(1); }
console.log("RESULT: SAFE — reorg tolerance is proven at boot and re-checked live; the keepers match their chain.");
