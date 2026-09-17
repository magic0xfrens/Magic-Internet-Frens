// H5 T5D — REGRESSION TEST (was an attack PoC; inverted onto post-fix behaviour).
//
// BEFORE THE FIX: the LIVE generation's quote ADDRESS was read on-chain
// (useCurrentQuote → registry.generationQuote) while its DECIMALS came from the
// bundled manifest, with a silent `decimals: 18` for anything unlisted — and the
// Robinhood template had no `quoteAssets` key at all. On a 6-decimal quote,
// SwapWidget signed a sell floor 1e12 above the best possible fill (every sell
// reverts) while rendering "970.000000", which looks correct.
//
// AFTER THE FIX: decimals come from the SAME source as the address — an on-chain
// `decimals()` read (useQuoteDecimals) — the manifest fallback is marked
// `decimalsKnown: false`, and SwapWidget REFUSES to sign while decimals are
// unknown rather than substituting 18.
//
// PASS = exit 0 and "RESULT: SAFE".
// Run:  node audit/RH_MAINNET_2026-09-16/poc/h5/h5_quote_decimals.mjs
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../../../..");
const read = (p) => readFileSync(join(ROOT, p), "utf8");
const quotes = read("src/config/quotes.ts");
const hook = read("src/hooks/useAllowedQuotes.ts");
const widget = read("src/components/cauldron/SwapWidget.tsx");
const cauldron = read("src/components/cauldron/TheCauldron.tsx");
const tpl = JSON.parse(read("indexer/deployments/round.robinhood.template.json"));

let fail = 0;
const chk = (desc, ok) => { console.log(`  ${ok ? "ok  " : "FAIL"} — ${desc}`); if (!ok) fail = 1; };

console.log("── src/config/quotes.ts ──");
chk("the manifest is the ACTIVE one, not round.json hardcoded",
  /import \{ ACTIVE_ROUND as round \} from "\.\/deployments"/.test(quotes));
chk("the unlisted-quote fallback is flagged decimalsKnown: false", /decimalsKnown:\s*false/.test(quotes));
chk("manifest-listed quotes are flagged decimalsKnown: true", /decimalsKnown:\s*true/.test(quotes));

console.log("── src/hooks/useAllowedQuotes.ts ──");
chk("useQuoteDecimals exists and reads ERC20 decimals() on-chain",
  /export function useQuoteDecimals/.test(hook) && /functionName:\s*"decimals"/.test(hook));
chk("an unreadable/absurd decimals stays null — no 18 guess",
  /setState\(\{ key, dec: null \}\)/.test(hook) && /n <= 36 \? n : null/.test(hook));
// RH1A hardened this further: the read is KEYED to the quote, so it cannot
// latch a stale value when the quote address changes under it.
chk("the read is keyed to the quote it read (RH1A)",
  /useState<\{ key: string; dec: number \| null \}>/.test(hook)
  && /\}, \[load, key\]\);/.test(hook));

console.log("── src/components/cauldron/TheCauldron.tsx ──");
chk("the live quote's decimals come from the chain read, and only once the quote itself resolved",
  /useQuoteDecimals\(quoteResolved \? liveQuoteAddr : null\)/.test(cauldron));
chk("and the 'known' flag is threaded to the trade panel",
  /quoteDecimalsKnown=\{quoteDecimalsKnown\}/.test(cauldron));
chk("no panel is still fed liveQuote.decimals from the manifest",
  !/quoteDecimals=\{liveQuote\.decimals\}/.test(cauldron));

console.log("── src/components/cauldron/SwapWidget.tsx ──");
chk("the panel is unpriceable while decimals are unknown",
  /const decimalsResolved = qNative \|\| quoteDecimalsKnown/.test(widget)
  && /priceable = spotPrice > 0 && decimalsResolved/.test(widget));
chk("and both submit paths refuse to sign",
  (widget.match(/if \(!decimalsResolved\)/g) ?? []).length >= 2);

console.log("── indexer/deployments/round.robinhood.template.json ──");
chk("the template now carries quoteAssets", Array.isArray(tpl.quoteAssets) && tpl.quoteAssets.length > 0);
chk("every templated quote declares integer decimals",
  (tpl.quoteAssets ?? []).every((q) => Number.isInteger(q.decimals) && q.decimals >= 0 && q.decimals <= 36));
chk("the template carries positionManager", typeof tpl.contracts?.positionManager === "string");
chk("the template carries the legacy-floor params",
  typeof tpl.legacyThresholdEth === "number" && Number.isInteger(tpl.legacyBps));

console.log("\nThe 1e12 arithmetic the old PoC demonstrated (quote 0x3bfc…48e3, true decimals 6):");
console.log("  pre-fix  signed minOut = 970000000000000000000  (best possible out = 1000000000)");
console.log("  post-fix the floor is never computed at all until decimals() resolves — the");
console.log("  panel is unpriceable and both submit paths return early with a reason.");

console.log();
if (fail) { console.log("RESULT: REGRESSED — T5D is back."); process.exit(1); }
console.log("RESULT: SAFE — quote decimals share a source with the quote address; unknown = refuse.");
