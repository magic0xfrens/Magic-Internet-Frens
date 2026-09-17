# COHERENCE A — core pool / lifecycle / perps / liquidation / vault

Scope: does the protocol do what it tells users it does. Target chain 4663.
Tree state: committed (`git status` shows only `.claude/agents/hunter.md` + the OZ
submodule dirty; `PerpEngine.sol`/`CauldronHook.sol` are **not** modified, so
nothing below is the in-flight fixer's churn).

## Execution log (what makes the rows below VERIFIED)

| # | Run | Result |
|---|-----|--------|
| E1 | `npm run build` → exit 0, 5 prerendered routes | `dist/` emitted; grepped below |
| E2 | `forge test --match-path test/attacks/T02_PerpAfterRotation.t.sol -vv` (FOUNDRY_PROFILE=cauldron, Sepolia v4 fork) | **2 passed, 0 failed, 22.86s**. Logs: `engine quote : 0xa0Cb889707d426A7A386870A03bc70d1b0697598` (MockQuoteToken "USDG", **6 dec**); `minCollateral (raw units) : 3000000000000000`; `...as WHOLE USDG ($) : 3000000000`. Assertions ran (non-vacuous — `assertEq(perp.quote(), address(usdg))` at T02:209). |
| E3 | `grep` over `dist/assets/TheCauldron-n0FREZIH.js` | contains `collateralEth.toFixed(4)," Ξ collateral · "`, `pnlEth.toFixed(4)," Ξ"`, `collateralEth.toFixed(4)," Ξ"` |
| E4 | `grep` over `dist/assets/*.js` | contains `"0x42b0b17a":"QueueInsolvent"` + the full QueueInsolvent remedy string + `"0x38dc5cd1":"LiqGasStarved"` |
| E5 | `node -e` replaying the indexer's exact expressions on the raw values a 6-dec engine emits | `$50,000` collateral → renders `0.0000 Ξ collateral`; pnl `+0.0000 Ξ`; entry price off by `5e11×`; **roiPct still correct at 22%** |

E2 is the load-bearing one: it proves on a real v4 fork that `PerpEngine.quote`
really does become a 6-decimal ERC20 after a governance rotation. Everything in
CA-1 is that state meeting a read layer that assumes 18.

---

## Mismatch table

| id | Promise (where it is made) | What the code does | Where it breaks | Sev | Tag |
|----|---------------------------|--------------------|-----------------|-----|-----|
| **CA-1** | The perp panel shows "your collateral / your PnL / the vault's lending capacity" as real amounts. `PerpPanel.tsx:670` `{agg.collateralEth.toFixed(4)} Ξ collateral`, `PnlCard.tsx:167` `{pnlEth.toFixed(4)} Ξ` | `PerpEngine.sol:2034` emits `Opened(..., collateral, size, leverage)` where `collateral = sent − fee` (`_takeFee`) in the **live quote's raw units** (`PerpEngine.sol:221 address public quote`). The indexer divides by a hardcoded `1e18`. | `indexer/src/index.ts:430` `Number(event.args.collateral)/1e18`; `:431` size; `:506` payout; `:507` pnl. Also `indexer/src/api/index.ts:205` `const n = (v:bigint)=>Number(formatEther(v))` applied at `:211`/`:226` to `longOiEth`, `shortOiEth`, `plvEth`, `plvToken`, `depthEth`. Served by `api/index.ts:1286,1299`; consumed `usePerpEngine.ts:216-220`; rendered `PerpPanel.tsx:600,637,643,670`, `PnlCard.tsx:167`, and `PerpPanel.tsx:211` `longCap` (the "Vault can lend" sizing number). | **High** | **VERIFIED** (E2+E3+E5) |
| **CA-2** | The number's unit is whatever the generation is quoted in. | The `Ξ` glyph is a literal in the shipped bundle, not derived from `quote.symbol` — `PerpPanel` receives `quoteSymbol` (`:73`) and uses it in the trade form, but every perp **stat/PnL** line hardcodes `Ξ`. Fixing CA-1's decimals alone still mislabels a USDG book as ether. | `dist/assets/TheCauldron-n0FREZIH.js` (E3); source `PerpPanel.tsx:600,637,643,670`, `PnlCard.tsx:167` | Medium | **VERIFIED** (E3) |
| **CA-3** | Entry price / liquidation line on the chart. | `index.ts:~436` `avgExec = notionalEth/sizeTok`; both operands are 1e18-scaled, so on a 6-dec quote `avgExec` is ~5e11× low (E5). The API overrides entry with the post-open spot looked up by `openTx`, so this is the **fallback** path only; I did not execute the fallback. | `indexer/src/index.ts:430-436`, `api/index.ts:1240,1248` `liqFrom(entry, …)` | Medium | **DERIVED** |
| **CA-4** | `usePerpVault.depositEth` stakes the quote side. | Still native-only: `parseEther(eth.toFixed(18))` + a native `value`. No component caller found (`StakePanel.tsx:110` now correctly calls `v.depositQuote(raw)` after `parseUnits(..., qDec)`), so this is an exported-but-unused footgun rather than a live path. | `src/hooks/usePerpVault.ts:129` | Low | **DERIVED** |
| **CA-5** | Disclosure: "a stranger's swap can close your position." | **Still undisclosed to the position holder.** `PerpPanel.tsx:620` discloses only TWAP-mark liquidation ("Liquidations trigger off a manipulation-resistant TWAP mark"); `wouldLiquidateOnOpen` (`:198,294,608`) warns only about *your own* open. The in-swap sweep introduced by `0f71309` **is** described — but only in `src/config/perp.ts:252 LiqGasStarved`, which is shown to the **swapper who under-gassed**, never to the trader whose position gets swept. No string in `src/` or `dist/` tells a holder a third party's trade closes them. | `src/config/perp.ts:252` vs `PerpPanel.tsx:620` | Medium | **VERIFIED** (E3 — no such string in the shipped bundle) |
| **CA-6** | Disclosure: `QueueInsolvent` has no in-app remedy. | **Now closed.** `src/config/perp.ts:248` gives the cause, states it is queue-wide (takes nothing from any individual staker), names the remedy (`settlePendingEth`/`settlePendingToken`, permissionless), and says retrying will fail identically. Selector-mapped at `:292`, and both the map and the string ship. | n/a — resolved | — | **VERIFIED** (E4) |

### Is the decimals class closed?

**No — it is closed on three of four surfaces.** Closed and confirmed:
write paths (`StakePanel.tsx:94-96` `parseUnits` with live decimals + a refusal
instead of the old full-balance clamp; `usePerpEngine` `prepareCollateral` /
`floorFrom(..., quote.decimals)` at `:291`; `SwapWidget.tsx:200` `qDec`), the
swap/candle read path (`index.ts:372-380` via `rawToQuoteAmount`), and the vault
position read path (`api/index.ts:1568` uses a quote-aware `q()` for the quote
side and `n()` only for the 18-dec token side).

**Still open: the perp-position and perp-stats read path** (CA-1). The class
regenerated in exactly the place the last pass did not reach.

---

## Verdict (≤200 words)

The lifecycle and vault promises hold up, and the two surfaces that ate last
run's Highs — the swap/candle pipeline and the vault stake form — are genuinely
fixed, not patched instance-by-instance. `QueueInsolvent` went from a dead end to
a disclosed, permissionless remedy that ships in the bundle. Good.

The class is not closed. `PerpEngine.quote` becomes a 6-decimal ERC20 after an
ordinary governance rotation — executed on a fork, not inferred — and the perp
read layer still divides by `1e18` in four places and labels the result `Ξ`. The
consequence is not a rounding error; it is a book that reads as wiped. A $50,000
position renders `0.0000 Ξ collateral`, the vault's lending capacity renders
zero, and — the cruel part — `roiPct` is a ratio of two equally-wrong numbers, so
the percentage stays correct. The panel looks *internally consistent* and
totally wrong.

Nothing here is exploitable; CA-1 is a trust and sizing failure, not a drain. But
it lands on every perp user simultaneously, the first time the treasury rotates.

**The single most likely way a user loses money or trust through a mismatch
rather than an exploit:** the first quote rotation to a 6-decimal stable makes
every trader's position panel show zero collateral and zero PnL beside a
correct-looking ROI percentage. Believing they have been liquidated or that the
engine is insolvent, traders close good positions at a loss and stakers withdraw
into the exit queue — a self-inflicted bank run caused entirely by a missing
`10**decimals` in `indexer/src/index.ts:430`.

**Smallest honest disclosures.** CA-5: one line in the PerpPanel risk footer —
"Anyone's trade can close your position: a swap that would bankrupt you
liquidates you inside that swap, at the TWAP mark." CA-6: already shipped; no
action.
