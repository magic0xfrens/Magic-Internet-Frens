// R5B REGRESSION — was: StakePanel parsed the QUOTE side with parseEther (18 dec)
// regardless of the live quote's decimals, then CLAMPED to the wallet balance, so
// typing "1" on 6-decimal USDG staked the ENTIRE balance; the approval was
// maxUint256. This replays the arithmetic with the FIXED shape and asserts the
// source no longer contains the old one.
import { parseEther, parseUnits, formatUnits } from "viem";
import { readFileSync } from "node:fs";
const rd = (p) => readFileSync(new URL(`../../../../${p}`, import.meta.url), "utf8");
const m = JSON.parse(rd("indexer/deployments/round.json"));
const usdg = m.quoteAssets.find((q) => q.symbol === "USDG");
console.log(`quote ${usdg.symbol} decimals=${usdg.decimals}`);

const typed = 1;                                                 // user types "1 USDG"
const walletBalance = 10_000n * 10n ** BigInt(usdg.decimals);    // holds 10,000 USDG
const intended = BigInt(typed) * 10n ** BigInt(usdg.decimals);

// --- the OLD shape, for contrast ---
let old = parseEther(typed.toFixed(18));
if (old > walletBalance) old = walletBalance;
console.log(`OLD parseEther+clamp : ${old} (${formatUnits(old, usdg.decimals)} ${usdg.symbol}) — the whole wallet`);

// --- the FIXED shape, StakePanel.tsx verbatim ---
const qDec = usdg.decimals;
const raw = parseUnits(typed.toFixed(Math.min(qDec, 18)), qDec);
const rejected = raw > walletBalance;                            // refuse, never substitute
console.log(`NEW parseUnits       : ${raw} (${formatUnits(raw, qDec)} ${usdg.symbol})`);
if (raw !== intended) throw new Error(`REGRESSION: parsed ${raw}, intended ${intended}`);
if (rejected) throw new Error("REGRESSION: a 1 USDG stake against a 10,000 USDG balance must not be rejected");

// over-typing must ERROR, not silently become the balance
const over = parseUnits("999999", qDec);
if (!(over > walletBalance)) throw new Error("test setup wrong: `over` should exceed the balance");
console.log(`over-typed 999999    : ${over} > balance ${walletBalance} → StakePanel shows an error and does NOT deposit`);

// --- static assertions over the shipped source ---
const panel = rd("src/components/cauldron/StakePanel.tsx");
const vault = rd("src/hooks/usePerpVault.ts");
if (!/const raw = parseUnits\(amount\.toFixed\(Math\.min\(qDec, 18\)\), qDec\);/.test(panel)) {
  throw new Error("REGRESSION: the quote side no longer parses with the live decimals");
}
if (/if \(raw > v\.(quoteBalance|tokenBalance)\) raw = v\.(quoteBalance|tokenBalance);/.test(panel)) {
  throw new Error("REGRESSION: the silent balance-substituting clamp is back");
}
if (!/Not enough \$\{quoteSymbol\}/.test(panel)) throw new Error("REGRESSION: no over-balance error for the quote side");
if (!/const qDec = v\.quoteIsErc20 \? quoteDecimals : 18;/.test(panel)) throw new Error("REGRESSION: qDec is not taken from the live quote");
for (const fn of ["approveQuote", "approveToken"]) {
  const body = vault.match(new RegExp(`const ${fn} = useCallback\\(async \\(([^)]*)\\)[\\s\\S]*?\\}, \\[`))[0];
  if (!/amount: bigint/.test(body)) throw new Error(`REGRESSION: ${fn} no longer takes an amount`);
  if (/maxUint256/.test(body)) throw new Error(`REGRESSION: ${fn} approves maxUint256 again`);
  if (!/args: \[PERP\.vault, amount\]/.test(body)) throw new Error(`REGRESSION: ${fn} does not bound the allowance to the stake`);
}
console.log(`\nPASS: "stake 1 ${usdg.symbol}" signs deposit(${raw}) = ${formatUnits(raw, qDec)} ${usdg.symbol};`);
console.log(`      over-balance is an error, not a full-wallet stake; approvals are bounded to the stake.`);
