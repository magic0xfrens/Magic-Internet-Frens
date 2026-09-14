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
//  Run after every deploy:  node scripts/verify-selectors.mjs
import { readFileSync } from "node:fs";
import { toFunctionSelector } from "viem";

const round = JSON.parse(readFileSync(new URL("../indexer/deployments/round.json", import.meta.url), "utf8"));
const RPC = process.env.RPC_URL ?? "https://ethereum-sepolia-rpc.publicnode.com";

const sel = (sig) => toFunctionSelector(sig).slice(2).toLowerCase();

//  The signatures the frontend actually sends, by manifest contract key. Keep in
//  step with src/config/cauldron.ts — anything the app can call belongs here.
const REQUIRED = {
  gachaRouter: [
    "play(uint256,uint256,uint256,uint256,uint256)",
    "playChurn(uint256,uint256,uint256,uint256)",
    "openReady(uint256)",
  ],
  registry: ["currentGeneration()", "currentToken()", "generationQuote(uint256)", "generationPoolId(uint256)"],
  governor: ["propose(string,string,uint8,string,address,string,string,uint256,uint256,address)", "vote(uint256)", "getProposal(uint256)"],
  perpEngine: ["openLong(uint8,uint256,uint256,uint256)", "openShort(uint8,uint256,uint256,uint256)", "close(uint256,uint256)"],
  dividend: ["claim(uint256)", "castSpell(uint256)"],
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
  for (const sig of sigs) {
    const s = sel(sig);
    if (bytecode.includes(s)) continue;
    console.log(`  FAIL ${key} ${addr}: 0x${s} ${sig} ABSENT from deployed code`);
    bad++;
  }
}
console.log(bad === 0
  ? `\nselector parity OK for round ${round.round} on chain ${round.chainId}`
  : `\n${bad} missing selector(s) — the app will revert with EMPTY data on those calls`);
process.exit(bad === 0 ? 0 : 1);
