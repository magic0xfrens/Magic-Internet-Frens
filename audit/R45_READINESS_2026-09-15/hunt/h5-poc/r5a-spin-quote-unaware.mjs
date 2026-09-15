// R5A REGRESSION — was: the gacha SPIN call site never passed the live quote, so
// `spin` fell back to its NATIVE_QUOTE default and signed `value: parseEther(..)`.
// On an ERC20-quoted generation the router takes no value → revert, and the floor
// divided an ETH stake by a quote-denominated price.
// This now asserts the FIXED shape. Static proof over the shipped source.
import { readFileSync } from "node:fs";
const rd = (p) => readFileSync(new URL(`../../../../${p}`, import.meta.url), "utf8");

const hook = rd("src/hooks/useCauldronSwap.ts");
const game = rd("src/components/cauldron/CrystalCauldronGame.tsx");
const cauldron = rd("src/components/cauldron/TheCauldron.tsx");

const sig = hook.match(/const spin = useCallback\(\s*async \(([^)]*)\)/s)[1].replace(/\s+/g, " ").trim();
if (!/quote: Address = NATIVE_QUOTE/.test(sig)) throw new Error("spin signature changed; re-read");

const call = game.split("\n").map((l, i) => [i + 1, l]).filter(([, l]) => /await spin\(/.test(l));
if (call.length !== 1) throw new Error(`expected exactly one spin() call site, found ${call.length}`);
const [line, text] = call[0];
const args = text.match(/spin\(([^)]*)\)/)[1].split(",").map((s) => s.trim());
console.log(`spin signature (useCauldronSwap.ts): (${sig})`);
console.log(`call site  CrystalCauldronGame.tsx:${line}: ${text.trim()}`);
console.log(`args passed: ${args.length} -> [${args.join(" | ")}]`);

// 1. the call site must pass quote, quoteExpected and quoteSymbol (params 5-7).
if (args.length < 7) throw new Error(`REGRESSION: spin() called with ${args.length} args — the quote is not threaded`);
if (args[4] !== "quote") throw new Error(`REGRESSION: arg 5 is "${args[4]}", expected "quote"`);
if (args[5] !== "quoteExpected") throw new Error(`REGRESSION: arg 6 is "${args[5]}", expected "quoteExpected"`);
if (args[6].replace(/\)$/, "") !== "quoteSymbol") throw new Error(`REGRESSION: arg 7 is "${args[6]}", expected "quoteSymbol"`);

// 2. the component must ACCEPT a quote (address + decimals + symbol).
const props = game.match(/interface Props \{([\s\S]*?)\n\}/)[1];
for (const k of ["quote?: Address", "quoteSymbol?: string", "quoteDecimals?: number"]) {
  if (!props.includes(k)) throw new Error(`REGRESSION: Props is missing \`${k}\``);
}

// 3. TheCauldron must PASS the live quote to the game, the same one it gives the swap widget.
const gameBlock = cauldron.match(/<CrystalCauldronGame[\s\S]*?\/>/)[0];
for (const k of ["quote={liveQuoteAddr}", "quoteSymbol={liveQuote.symbol}", "quoteDecimals={liveQuote.decimals}"]) {
  if (!gameBlock.includes(k)) throw new Error(`REGRESSION: TheCauldron does not pass \`${k}\` to CrystalCauldronGame`);
}

// 4. the floor must be sized off the QUOTE that enters the pool, not the raw ether.
const floor = game.match(/const spinFloor = useMemo\(\(\) => \{[\s\S]*?\}, \[[^\]]*\]\);/)[0];
if (!/formatUnits\(quoteExpected, quoteDecimals\)/.test(floor)) {
  throw new Error("REGRESSION: spinFloor no longer converts the stake into quote units");
}
if (!/qNative \? stake :/.test(floor)) throw new Error("REGRESSION: spinFloor lost its native/ERC20 split");

// 5. and `spin`'s ERC20 branch (the one a non-native quote now reaches) still
//    zaps, bounds the approval to `spend`, and sends value: 0n.
const erc20 = hook.slice(hook.indexOf("if (!isNativeQuote(quote)) {"), hook.indexOf("const canChurnNative"));
for (const k of ["zapNativeToQuote", "args: [CAULDRON.gachaRouter as Address, spend]", "value: 0n"]) {
  if (!erc20.includes(k)) throw new Error(`REGRESSION: spin's ERC20 branch lost \`${k}\``);
}

console.log("\nPASS: the crystal spin now selects spin()'s branch from the LIVE quote —");
console.log("      ERC20 quote → zap + approval bounded to `spend` + quoteIn + value 0n;");
console.log("      native quote → msg.value; and the floor is sized in quote units.");
