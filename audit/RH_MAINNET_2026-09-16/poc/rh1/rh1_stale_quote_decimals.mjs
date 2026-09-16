// RH1 — REGRESSION TEST (was an attack PoC; inverted onto post-fix behaviour).
//
// BEFORE THE FIX (fix-induced by the T5D remediation, commit 72cff8b):
//   useQuoteDecimals seeded `useState(native ? 18 : null)` while useCurrentQuote
//   was still returning its NATIVE_QUOTE placeholder, and usePoll's effect deps
//   are [intervalMs, enabled] ONLY — `enabled` was already true, so the effect
//   never re-ran when the quote resolved to a real 6-decimal ERC20. For 300 s of
//   every session the hook served 18, and TheCauldron preferred that stale 18
//   over the manifest's correct 6. Sells signed a floor 1e12 too high; BUYS
//   signed a token floor 1e12 too LOW — nonzero, so the `minOut <= 0n` refusal
//   never fired — i.e. an effectively-zero slippage floor on a chain whose
//   pending calldata is publicly readable.
//
// AFTER THE FIX:
//   - the read is KEYED to the quote it read, and an effect on [load, key]
//     invalidates and re-reads whenever the quote address changes;
//   - the hook refuses to answer for a key it has not read (`null`), and 18 is
//     returned only for the EXPLICIT native zero address, never as a seed;
//   - useCurrentQuote reports `resolved`, so the native placeholder is no
//     longer indistinguishable from a real ETH-quoted generation;
//   - the TheCauldron gate is an AND, and a manifest/chain DISAGREEMENT is
//     treated as unknown-and-refuse.
//
// Verified FROM THE BUILT BUNDLE, because that is where the defect was visible.
// PASS = exit 0 and "RESULT: SAFE".
// Run:  npm run build && node audit/RH_MAINNET_2026-09-16/poc/rh1/rh1_stale_quote_decimals.mjs
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../../..");
const read = (p) => readFileSync(join(ROOT, p), "utf8");
const DIST = join(ROOT, "dist/assets");
let bundle = "";
try {
  for (const f of readdirSync(DIST)) if (f.endsWith(".js")) bundle += readFileSync(join(DIST, f), "utf8");
} catch { /* no dist */ }

let fail = 0;
const chk = (desc, ok) => { console.log(`  ${ok ? "ok  " : "FAIL"} — ${desc}`); if (!ok) fail = 1; };

console.log("── dist/ (the emitted bundle, not the source) ──");
chk("a build exists to inspect", bundle.length > 0);

//  The load-bearing shape: the decimals useEffect's deps array must carry the
//  KEY as well as the loader. Minified: useEffect(()=>{...{key:"",dec:null}...},[o,e]).
const effect = bundle.match(/useEffect\(\(\)=>\{[^}]*key===([A-Za-z_$][\w$]*)\?[^}]*\{key:"",dec:null\}\)[^}]*\},\[([^\]]*)\]\)/);
chk("the decimals read's effect exists in the bundle", !!effect);
if (effect) {
  const keyIdent = effect[1];
  const deps = effect[2].split(",").map((d) => d.trim());
  console.log(`     compiled deps: [${deps.join(", ")}]   (key identifier: ${keyIdent})`);
  chk("the effect re-runs when the QUOTE ADDRESS changes (key is a dep)", deps.includes(keyIdent));
  chk("the effect has more than the pre-fix 2 poll deps", deps.length >= 2 && deps.includes(keyIdent));
}
//  18 must never be a seed. The only `dec:18` in the bundle is inside the
//  explicit native branch (`key===NATIVE ? {key,dec:18}`), never in useState.
chk("no useState seeds 18", !/useState\(\{key:[^}]*dec:18\}\)/.test(bundle) && !/useState\([A-Za-z_$][\w$]*\?18:null\)/.test(bundle));
chk("the hook refuses to answer for a key it has not read",
  /!==""&&[A-Za-z_$][\w$]*\.key===[A-Za-z_$][\w$]*\?[A-Za-z_$][\w$]*\.dec:null/.test(bundle));

console.log("── source: the mechanism the bundle reflects ──");
const hook = read("src/hooks/useAllowedQuotes.ts");
const cauldron = read("src/components/cauldron/TheCauldron.tsx");
const chains = read("src/config/chains.ts");
chk("useQuoteDecimals state is keyed by the quote", /useState<\{ key: string; dec: number \| null \}>/.test(hook));
chk("18 is set only for the EXPLICIT native address", /if \(key === NATIVE_QUOTE\) \{ setState\(\{ key, dec: 18 \}\); return; \}/.test(hook));
chk("useCurrentQuote reports whether the read actually landed", /export interface CurrentQuote/.test(hook) && /resolved: boolean/.test(hook));
chk("useCurrentQuote is also keyed (a generation flip invalidates it)", /useState<\{ gen: number; quote: Address \| null \}>/.test(hook));
chk("RH1B: the decimals gate is an AND over resolved + on-chain + agreement",
  /quoteResolved &&\s*\n\s*onChainQuoteDecimals !== null &&/.test(cauldron)
  && /manifestDecimals === null \|\| manifestDecimals === onChainQuoteDecimals/.test(cauldron));
chk("RH1B: an unresolved quote is not passed off as native", /useQuoteDecimals\(quoteResolved \? liveQuoteAddr : null\)/.test(cauldron));

console.log("── RH1C: the target chain's transport ──");
chk("the target chain has ordered failover, not a single un-retried http()",
  !/\[targetChain\.id\]: http\(RPC_URL\),/.test(chains) && /\[targetChain\.id\]: fallback\(/.test(chains));
chk("with retries", /TARGET_RPCS\.map\(\(u\) => http\(u, \{ batch: \{ wait: 24 \}, retryCount: 2/.test(chains));
//  CHAIN_PROFILE.md §8 verified exactly two working 4663 endpoints and warns
//  that lookalike hosts exist. Nothing else may appear as a backup.
const VERIFIED_4663 = ["https://rpc.mainnet.chain.robinhood.com", "https://robinhood-rpc.publicnode.com"];
const backups = [...chains.matchAll(/4663: \[([^\]]*)\]/g)].flatMap((m) => m[1].match(/"[^"]+"/g) ?? []).map((q) => q.slice(1, -1));
console.log(`     4663 backups: ${backups.join(", ") || "(none)"}`);
chk("every 4663 endpoint is one CHAIN_PROFILE §8 verified", backups.every((u) => VERIFIED_4663.includes(u)));
for (const bad of ["rpc.ordofi.network", "rpc.arrowrpc.com", "https://rpc.chain.robinhood.com\""]) {
  chk(`the unverified/dead host ${bad} appears nowhere`, !chains.includes(bad));
}

console.log("\nThe arithmetic the old PoC demonstrated (buy 1,000 USDG, 6-dec quote):");
console.log("  pre-fix  signed minOut = 980100000000 token-wei vs an honest 980100000000007340032");
console.log("           — 1e-12 of fair, i.e. an effectively-zero floor that `minOut <= 0n` misses.");
console.log("  post-fix the decimals read is invalidated the moment the quote address changes, and");
console.log("           the panel is unpriceable (refuses to sign) until it resolves.");

console.log();
if (fail) { console.log("RESULT: REGRESSED — RH1 is back."); process.exit(1); }
console.log("RESULT: SAFE — decimals are keyed to the quote; 18 is never a seed; the gate is an AND.");
