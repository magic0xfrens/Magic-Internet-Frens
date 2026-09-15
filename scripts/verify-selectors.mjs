#!/usr/bin/env node
//
// SELECTOR PARITY: every function the app calls must exist in the DEPLOYED code.
//
//  ── WHY THIS EXISTS ─────────────────────────────────────────────────────────
//  Rounds 43 AND 44 both shipped a CauldronGachaRouter whose runtime is 8,580
//  bytes while the source compiles to 8,814. The 234-byte gap is `playChurn`, so
//  the selector was absent from the dispatcher and every "spin" reverted with
//  EMPTY data after ~537 gas — no reason string, nothing in the console.
//
//  No test could have caught it. `forge test` compiles the local source; the app
//  calls whatever bytecode is actually on chain. The two only diverge at deploy
//  time, which is exactly where nothing was looking. Same family as the stale
//  `perpEngine` address in r44's manifest: the deploy pipeline lying quietly.
//
//  WIRED IN, NOT OPTIONAL. This used to be a file nothing referenced — which is
//  why the bug survived two rounds. It now runs automatically from
//  scripts/apply-deployment.mjs (the ONE place every deploy path writes the
//  manifest), from auto-deploy.sh, and in .github/workflows/deploy.yml next to
//  verify-manifest.mjs. A non-zero exit ABORTS the deploy.
//
//  Manual run:  node scripts/verify-selectors.mjs      (RPC_URL= to override)
import { readFileSync } from "node:fs";
import { toFunctionSelector } from "viem";

const round = JSON.parse(readFileSync(new URL("../indexer/deployments/round.json", import.meta.url), "utf8"));
//  Default pinned to the gateway that served the CANONICAL block through the
//  Sepolia reorg at 11704817 (see indexer/ponder.config.ts). Override with
//  RPC_URL — a paid endpoint is better for a deploy gate, but never write a
//  keyed URL into this file.
const RPC = process.env.RPC_URL ?? "https://sepolia.gateway.tenderly.co";

const sel = (sig) => toFunctionSelector(sig).slice(2).toLowerCase();

//  ── THE SIGNATURES THE FRONTEND ACTUALLY SENDS, BY MANIFEST KEY ────────────
//  Every entry was derived from the ABI the app encodes with (src/config/*.ts,
//  src/hooks/useCauldronSwap.ts's ZAP_ABI, src/hooks/useTreasuryRotation.ts) —
//  none guessed. A nested array means OVERLOADS: at least one must be present.
//  Keys absent from the manifest are SKIPped, so a round without a zap or a
//  rotation stack still passes.
//  NOTE: `collection` / `vault` are PER-GENERATION addresses read from the
//  registry, not manifest keys — their functions are listed under the key the
//  manifest uses when it pins one, and skipped otherwise.
const REQUIRED = {
  gachaRouter: [
    "play(uint256,uint256,uint256,uint256,uint256)",
    "playChurn(uint256,uint256,uint256,uint256)",   // ← ABSENT on r43 and r44
    "openReady(uint256)",
  ],
  nativeZap: ["zap((address,address,uint24,int24,address),uint256)"],
  //  `reveal`/`revealBatch` are on the COLLECTION (CauldronCollection); `redeem`
  //  is on the per-generation VAULT (VAULT_ABI, src/config/cauldron.ts), not the
  //  collection — asserting it on the collection reports a false FAIL.
  collection: ["reveal(uint256)", "revealBatch(uint256[])"],
  vault: ["redeem(uint256)"],
  registry: [
    "currentGeneration()", "currentToken()", "generationQuote(uint256)", "generationPoolId(uint256)",
    "relaunch()", "claimByBurn(uint256,uint256)", "redeemOgFren(uint256)",
    "recycleCollectionNFT(uint256,uint256)", "buyCollectionNFT(uint256,uint256)",
    "rotateSliceFrom(uint8,uint16,uint256,(address,address,uint24,int24,address))",
  ],
  governor: [
    // `propose` is overloaded across generations of the governor; the app picks
    // by arity, so ANY ONE of these being present is a working propose button.
    [
      "propose(string,string,uint8,string,address,string,string,uint256,uint256,address)",
      "propose(string,string,uint8,string,address,string,string,string,string,uint256,uint256,address)",
      "propose(string,string,uint8,string,address,string,string,uint256,uint256)",
    ],
    "vote(uint256)", "getProposal(uint256)",
  ],
  //  uint16, NOT uint256 — it is a BPS envelope. A uint256 here would compute a
  //  different selector and "prove" a working governor that reverts on every call.
  treasuryGovernor: ["propose(address,uint16)", "vote(uint256,bool)", "execute(uint256)"],
  dividend: [
    "claim(uint256)", "castSpell(uint256)", "claimMany(uint256[])", "castMany(uint256[])",
    "claimTokens(uint256)", "withdrawOwedToken(address)", "withdrawOwed()",
  ],
  perpEngine: [
    "openLong(uint8,uint256,uint256,uint256)", "openShort(uint8,uint256,uint256,uint256)",
    "close(uint256,uint256)", "claimLiquidatorBadges(uint256)",
  ],
  perpVault: [
    "depositEth()", "deposit(uint256)", "withdrawEth(uint256)", "withdrawToken(uint256)",
    "depositToken(uint256)", "claimPendingEth()", "claimPendingToken()", "claimTokYield()",
  ],
  presale: ["mint(uint256)"],
};

async function code(address) {
  const r = await fetch(RPC, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_getCode", params: [address, "latest"] }),
  });
  const j = await r.json();
  if (j.error) throw new Error(`${address}: ${j.error.message}`);
  return (j.result ?? "0x").toLowerCase();
}

let bad = 0;
for (const [key, sigs] of Object.entries(REQUIRED)) {
  const addr = round.contracts[key];
  if (!addr || addr.startsWith("__")) { console.log(`  SKIP ${key}: not in the manifest`); continue; }
  const bytecode = await code(addr);
  if (bytecode === "0x") { console.log(`  FAIL ${key} ${addr}: NO CODE`); bad++; continue; }
  let okHere = 0;
  for (const entry of sigs) {
    //  An overload GROUP passes if any member is in the runtime.
    const group = Array.isArray(entry) ? entry : [entry];
    const hit = group.find((sig) => bytecode.includes(sel(sig)));
    if (hit) { okHere++; continue; }
    for (const sig of group) console.log(`  FAIL ${key} ${addr}: 0x${sel(sig)} ${sig} ABSENT from deployed code`);
    if (group.length > 1) console.log(`         (none of the ${group.length} overloads above is present)`);
    bad++;
  }
  console.log(`  ok   ${key} ${addr}: ${okHere}/${sigs.length} present`);
}
console.log(bad === 0
  ? `\nselector parity OK for round ${round.round} on chain ${round.chainId}`
  : `\n${bad} missing selector(s) — the app will revert with EMPTY data on those calls`);
process.exit(bad === 0 ? 0 : 1);
