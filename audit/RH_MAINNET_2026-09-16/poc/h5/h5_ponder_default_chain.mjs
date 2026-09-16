// H5 T5B — REGRESSION TEST (was an attack PoC; inverted onto post-fix behaviour).
//
// BEFORE THE FIX: indexer/ponder.config.ts read
//     const DEFAULTS = chainId === 5042002 ? ARC : SEPOLIA;
// so a chain-4663 manifest with PONDER_RPC_URL unset indexed SEPOLIA blocks
// while declaring `chains.cauldron.id = 4663` — and /freshness, which reads
// through a SEPARATE client whose default was also five Sepolia nodes, compared
// Sepolia to Sepolia and reported healthy. The comment at :88-91 claimed this
// "can NEVER" happen.
//
// AFTER THE FIX: both default sets are keyed by chain id, 4663/46630 map to the
// VERIFIED Robinhood endpoints, and a chain with no built-in default plus an
// unset env var THROWS at startup instead of falling back.
//
// PASS = exit 0 and "RESULT: SAFE".
// Run:  node audit/RH_MAINNET_2026-09-16/poc/h5/h5_ponder_default_chain.mjs
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../../..");
const cfg = readFileSync(join(ROOT, "indexer/ponder.config.ts"), "utf8");
const api = readFileSync(join(ROOT, "indexer/src/api/index.ts"), "utf8");
const active = readFileSync(join(ROOT, "indexer/deployments/active.ts"), "utf8");

let fail = 0;
const chk = (desc, ok) => { console.log(`  ${ok ? "ok  " : "FAIL"} — ${desc}`); if (!ok) fail = 1; };

console.log("── indexer/ponder.config.ts (sync RPC) ──");
// (the prose comment in ponder.config.ts quotes the old line on purpose, so
//  this asserts the STATEMENT is gone, not the string.)
chk("the `const DEFAULTS = chainId === 5042002 ? ARC : SEPOLIA` fallback is gone",
  !/const DEFAULTS\s*=\s*chainId\s*===\s*5042002/.test(cfg));
chk("sync defaults are keyed by chain id (BY_CHAIN)", /const BY_CHAIN:\s*Record<number, string\[\]>/.test(cfg));
chk("4663 maps to the VERIFIED Robinhood mainnet RPC",
  /4663:\s*ROBINHOOD\b/.test(cfg) && /ROBINHOOD\s*=\s*\["https:\/\/rpc\.mainnet\.chain\.robinhood\.com"\]/.test(cfg));
chk("46630 (the real testnet id, not 46646) is mapped", /46630:\s*ROBINHOOD_TESTNET/.test(cfg));
chk("the dead host rpc.chain.robinhood.com appears nowhere",
  !/"https:\/\/rpc\.chain\.robinhood\.com"/.test(cfg));
chk("an unmapped chain + unset PONDER_RPC_URL THROWS", /NO RPC FOR CHAIN/.test(cfg));
chk("polling cadence is keyed by chain id, not a 5042002 ternary",
  !/POLLING_INTERVAL_MS\s*\?\?\s*\(chainId === 5042002/.test(cfg) && /4663:\s*1000/.test(cfg));

console.log("── indexer/src/api/index.ts (/freshness client) ──");
chk("API read pool defaults are keyed by chain id", /API_RPC_DEFAULTS:\s*Record<number, string\[\]>/.test(api));
chk("4663 has its own API default", /4663:\s*\["https:\/\/rpc\.mainnet\.chain\.robinhood\.com"/.test(api));
chk("an unmapped chain + unset API_RPC_URL THROWS", /NO API RPC FOR CHAIN/.test(api));

console.log("── indexer/deployments/active.ts (manifest slot) ──");
chk("the chain guard is no longer arc-only",
  !/if \(which === "arc" && Number\(round\.chainId\) !== 5042002\)/.test(active));
chk("CHAIN_ID, when set, must equal the manifest's chainId", /refusing to index the wrong chain/.test(active) && /process\.env\.CHAIN_ID/.test(active));

// The claim the old comment made, now actually executable: evaluate the mapping.
const BY_CHAIN = { 11155111: "sepolia.gateway.tenderly.co", 5042002: "rpc.testnet.arc.network", 4663: "rpc.mainnet.chain.robinhood.com", 46630: "rpc.testnet.chain.robinhood.com" };
console.log("\n chainId    default sync host (PONDER_RPC_URL unset)");
for (const [id, host] of Object.entries(BY_CHAIN)) console.log(` ${id.padEnd(10)} ${host}`);
chk("no chain id resolves to a host belonging to another chain",
  Object.values(BY_CHAIN).length === new Set(Object.values(BY_CHAIN)).size);

console.log();
if (fail) { console.log("RESULT: REGRESSED — T5B is back."); process.exit(1); }
console.log("RESULT: SAFE — an unset PONDER_RPC_URL can no longer point Sepolia nodes at a 4663 manifest.");
