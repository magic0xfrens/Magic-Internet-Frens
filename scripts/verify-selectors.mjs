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
//  ── THE DEFAULT RPC MUST FOLLOW THE MANIFEST'S OWN CHAIN ───────────────────
//  This used to default to a SEPOLIA gateway unconditionally. Against a chain
//  4663 manifest that is not a near-miss: every address returns `0x`, so the
//  gate prints "NO CODE" for every contract and exits non-zero. The operator
//  then reads a misaimed gate as "the deploy is broken" — and the likeliest
//  recovery from that is to ignore or disable the gate, which is precisely how
//  `playChurn` shipped twice.
//
//  The manifest already declares its own chainId, so derive the endpoint from
//  it. RPC_URL still overrides (a paid endpoint is better for a deploy gate),
//  but an UNSET RPC_URL can no longer silently point at the wrong chain.
//  Never write a keyed URL into this file.
const DEFAULT_RPC_BY_CHAIN = {
  11155111: "https://sepolia.gateway.tenderly.co",
  //  VERIFIED 2026-09-16: eth_chainId -> 0x1237 (4663). The host
  //  `rpc.chain.robinhood.com` carried by older docs does not exist.
  4663: "https://rpc.mainnet.chain.robinhood.com",
  46630: "https://rpc.testnet.chain.robinhood.com",
};
//  `||`, not `??`: CI passes `RPC_URL: ${{ secrets.RPC_URL }}`, and an UNSET
//  secret arrives as the EMPTY STRING, which `??` keeps. That made every CI run
//  since 2026-09-06 die here with "no default RPC" while the default sat one
//  line up. An empty override is no override.
const RPC = process.env.RPC_URL?.trim() || DEFAULT_RPC_BY_CHAIN[round.chainId];
if (!RPC) {
  console.error(
    `no default RPC known for chainId ${round.chainId}. Set RPC_URL explicitly —\n` +
      `refusing to guess, because guessing Sepolia is what made this gate lie.`,
  );
  process.exit(1);
}

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

async function ethCall(to, data) {
  const r = await fetch(RPC, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_call", params: [{ to, data }, "latest"] }),
  });
  const j = await r.json();
  if (j.error || !j.result) return null;
  return j.result;
}

//  ── ASSERT THE ENDPOINT IS THE MANIFEST'S CHAIN ────────────────────────────
//  RPC_URL overrides the default, so it can still be pointed at the wrong
//  chain by hand. Every address would then read `0x` and the gate would blame
//  the deploy. Check once, up front, and say so plainly.
{
  const r = await fetch(RPC, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_chainId", params: [] }),
  });
  const j = await r.json();
  const live = j.result ? parseInt(j.result, 16) : null;
  if (live === null) { console.error(`cannot read eth_chainId from the RPC — it is unreachable.`); process.exit(1); }
  if (live !== round.chainId) {
    console.error(
      `RPC is chain ${live} but the manifest declares ${round.chainId}.\n` +
        `Every lookup would report NO CODE and blame the deploy. Refusing.`,
    );
    process.exit(1);
  }
  console.log(`  rpc chain ${live} matches the manifest`);
}

//  ── THE VAULT CHECK THAT COULD NEVER RUN ───────────────────────────────────
//  `vault` is a PER-GENERATION address created during the summon, so it is
//  never a manifest key — which meant `vault: ["redeem(uint256)"]` hit the
//  `not in the manifest` SKIP on every single run. A listed check that can
//  never execute is exactly the `playChurn` shape this file exists to catch:
//  it reads as covered and verifies nothing.
//
//  `CauldronCollection.vault` is public (CauldronCollection.sol:51) and
//  `collection` IS a manifest key, so the address is resolvable. Resolve it and
//  run the check for real.
if (!round.contracts.vault && round.contracts.collection) {
  const got = await ethCall(round.contracts.collection, "0xfbfa77cf"); // vault()
  const addr = got && got.length >= 42 ? "0x" + got.slice(-40) : null;
  if (addr && !/^0x0{40}$/.test(addr)) {
    round.contracts.vault = addr;
    console.log(`  resolved vault ${addr} from collection.vault()`);
  } else {
    console.log(`  NOTE vault unresolved from collection.vault() — redeem(uint256) stays unchecked`);
  }
}

//  ── D2 (R46): A SKIP IS AN EXEMPTION, NOT A DEFAULT ────────────────────────
//  PROVEN BY EXECUTION during the 4663 fork rehearsal: pointed at a manifest
//  whose `contracts` was `{}`, this file printed eleven `SKIP ... not in the
//  manifest` lines, then `selector parity OK`, and exited 0. The one gate whose
//  entire purpose is catching a missing `playChurn` green-lit a manifest that
//  named no contracts at all — "I found no evidence of a problem" over an input
//  it never confirmed it had. That is reachable for real: `--stage manifest`
//  copies the 4663 template over round.json and lets apply-deployment.mjs fill
//  it, and a partial fill lands exactly here.
//
//  So keys are now classified. Missing OPTIONAL keys still SKIP (a round with
//  no zap, or a pre-ignition manifest with no collection yet, is legitimate).
//  Missing REQUIRED keys FAIL. And if nothing executed at all, that is never a
//  pass, whatever the classification says.
const ALWAYS_REQUIRED = new Set([
  //  Created by DeployLaunchpad, so present in every manifest from the deploy
  //  stage onward. `perpEngine`/`perpVault` come from the later DeployPerp
  //  stage and `collection`/`vault` only exist after ignition, so those stay
  //  optional-but-reported rather than required.
  "registry", "governor", "dividend", "presale", "gachaRouter", "treasuryGovernor",
]);

let bad = 0;
let executed = 0;
const skipped = [];
for (const [key, sigs] of Object.entries(REQUIRED)) {
  const addr = round.contracts[key];
  //  ── A PLACEHOLDER IS NOT AN ADDRESS ────────────────────────────────────
  //  D2 (R46): this tested only for the `__ASK_CHAIN__` sentinel, so the 4663
  //  template's OTHER placeholder shape — `<FILL from DeployPerp>` — was passed
  //  straight to eth_getCode. The RPC answered "invalid string length", which
  //  `code()` rethrows, and the whole gate died with an unhandled rejection
  //  mid-run: every key after it went unchecked, and the crash was reported by
  //  the caller as "selector parity FAILED". Anything that is not a well-formed
  //  address is an unfilled slot, whatever its spelling.
  const unfilled = !addr || typeof addr !== "string" || !/^0x[0-9a-fA-F]{40}$/.test(addr);
  if (unfilled) {
    if (ALWAYS_REQUIRED.has(key)) {
      console.log(`  FAIL ${key}: REQUIRED but absent from the manifest — nothing was verified for it`);
      bad++;
    } else {
      console.log(`  SKIP ${key}: not in the manifest (optional)`);
      skipped.push(key);
    }
    continue;
  }
  executed++;
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
//  An all-SKIP run is the "I could not check" case and must never read as a pass.
if (executed === 0) {
  console.error(
    `\nNOTHING WAS VERIFIED — every contract key was absent from the manifest.\n` +
      `An empty check is not a passing check. Refusing.`,
  );
  process.exit(1);
}
if (skipped.length) {
  console.log(`\n  ${skipped.length} optional key(s) unverified: ${skipped.join(", ")}`);
  //  `collection`/`vault` carry reveal()/revealBatch()/redeem(), and they only
  //  become resolvable AFTER ignition. Say plainly that they are still
  //  unchecked, so "it passed" is never mistaken for "redeem was verified".
  for (const k of ["collection", "vault"]) {
    if (skipped.includes(k)) {
      console.log(`  NOTE  ${k} is per-generation and does not exist until ignition —`);
      console.log(`        re-run this gate AFTER the first summon or its selectors ship unverified.`);
    }
  }
}
console.log(bad === 0
  ? `\nselector parity OK for round ${round.round} on chain ${round.chainId} (${executed} contract(s) actually checked)`
  : `\n${bad} missing selector(s) — the app will revert with EMPTY data on those calls`);
process.exit(bad === 0 ? 0 : 1);
