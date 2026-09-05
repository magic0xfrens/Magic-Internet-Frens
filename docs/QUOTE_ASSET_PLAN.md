# Choosable quote assets — implementation plan

**Goal.** Let an iteration pair against something other than native ETH — a
stablecoin, or a tokenized equity — chosen by MiFren governance from a
treasury-curated allowlist. Longer term, let the community allocate LP depth
*across* several quotes at once, making the guild an actively-managed book
rather than a single static pair.

**Status.** Phase 1 in progress. This file is the working spec; it supersedes
nothing and is written against the source as it stands.

> Lineage: the reasoning behind the additive-over-migratory choice, the
> no-oracle argument, and the allowlist-curation split were worked out in the
> seven-guild design notes. This plan applies those conclusions to the current
> single-token-per-iteration architecture, where there is no guild dimension.

---

## 0. The one hard constraint

Uniswap v4 orders a pool's currencies **by address**: `currency0 < currency1`.

Native ETH is `address(0)`, so it is *always* `currency0`. That is why the code
can say "the quote is currency0, our token is currency1" everywhere and be
right. With an ERC20 quote, the iteration token — deployed with plain `CREATE`,
so its address is effectively arbitrary — sorts to **either side**.

Every place that hardcodes that ordering has to branch instead. Measured:

| File | `currency1` assumptions |
| --- | --- |
| `cauldron/PoolOps.sol` | 10 |
| `CauldronHook.sol` | 3 (plus `zeroForOne` direction logic) |
| `cauldron/CauldronSeeder.sol` | 3 |
| `cauldron/PerpEngine.sol` | 2 |

Get one wrong and buys count as sells, fees skim the wrong side, or
liquidations settle backwards. This is the single largest source of risk in the
work, and it is why `quoteIsCurrency0` is stored **once at adoption** and read
everywhere, rather than re-derived per call site.

## 0.1 What is *not* a problem

Two things looked blocking on a first read and are not:

**The fee take is already currency-agnostic.**
```solidity
poolManager.take(key.currency0, address(this), total);   // CauldronHook.sol
```
`take` works for any currency. The quadrant derivation that forces
`beforeSwapReturnDelta` depends only on knowing *which side is the quote* — not
on that side being ETH.

**The adoption gate's ETH check is not load-bearing for C-01.**
```solidity
if (sender != registry) return selector;                        // (a) the security property
if (Currency.unwrap(key.currency0) != address(0)) return sel;   // (b) an assumption assert
```
C-01 was "anyone can initialise a pool naming this hook". **(a)** fixes that.
**(b)** asserts the fee logic's ETH assumption. Replacing (b) with
"quote ∈ allowlist" leaves C-01 fully fixed.

## 0.2 What genuinely breaks

| Item | Fix |
| --- | --- |
| Currency ordering (above) | `quoteIsCurrency0[id]`, stored at adoption |
| `guild.call{value:}`, `vault.call{value:}`, keeper payouts | branch native → `call{value:}`, ERC20 → `safeTransfer` |
| `relaunchETH` — one ETH-denominated scalar | `relaunchQuote`, denominated in that generation's quote |
| `legacyBuyStep` — hardcoded `zeroForOne: true` + `settle{value:}` | **Deferred.** See §5 |
| `PerpEngine` — 14 ETH value sites, `plvEth`, collateral, principal | Phase 3, its own audit pass |

The redemption floor needs **no** change: the reserve is denominated in the
*iteration token*, and `_pullGrow` pulls `generationToken[g]` regardless of quote.

---

## 1. Phases

Ordered so each lands green and reviewable. Nothing later depends on
speculative work in an earlier phase.

### Phase 1 — the allowlist (no behaviour change)
Treasury-curated set of permitted quotes on the registry. Native ETH allowed by
default. Nothing reads it yet, so this cannot break a live deployment.

**Why first:** it is the guardrail. Every later phase reads from it, and landing
it alone means the permission model is reviewable before any money path moves.

- `mapping(address => bool) allowedQuote` + `setAllowedQuote(address,bool)`, `onlyOwner` (the timelock)
- `QuoteAllowed(address,bool)` event
- ETH (`address(0)`) allowed in the constructor
- Tests: only the timelock may curate; ETH is allowed by default; unknown quotes are rejected

### Phase 2 — pair choice at summon and relaunch
The proposal names a quote; the registry builds the pool against it.

- `Proposal.quote` (address; `address(0)` = ETH, i.e. today's behaviour)
- `propose()` rejects a quote not on the allowlist **at proposal time**, so a
  bad pair cannot reach a vote
- Re-check at consumption: the allowlist can change between proposal and
  relaunch, and the check that matters is the one at the moment liquidity moves
- `PoolOps` sorts currencies and returns `quoteIsCurrency0`
- Hook stores it at adoption; gate becomes allowlist membership
- Fee take/route branches native vs ERC20

**The pricing needs no oracle.** Teardown yields `T` tokens and `E` of the old
quote; swapping `E → N` of the new quote and seeding at `N/T` prices the new
pool at exactly the rate the swap executed at. Execution *is* discovery.

### Phase 3 — perps and vault
The largest single surface: `PerpEngine` holds quote-denominated collateral,
principal and `plvEth`; `PerpVault` is two-sided.

Handled *after* Phase 2 is green and audited, because it is where user funds
sit and a half-converted money path is worse than none. Until then, perps are
**disabled for non-ETH-quoted generations** — an explicit revert, not silent
breakage.

### Phase 4 — frontend
Quote selector on the proposal form, sourced from the on-chain allowlist. Quote
symbol shown wherever a price is quoted, since "8.41 gwei" means nothing on a
USDG pair.

### Phase 5 — multi-quote allocation (the fund-manager layer)
Target depth allocation across allowed quotes, rebalanced by the **existing**
in-swap streaming seeder:

| Target | Behaviour |
| --- | --- |
| `{ETH: 100%}` | today |
| `{ETH: 50%, xNVDA: 50%}` | permanent dual pool, with cross-rate arbitrage |
| `{ETH: 80%, xNVDA: 20%}` | a tilt — deep ETH book plus a patron satellite |
| `{ETH: 0%, xNVDA: 100%}` | full migration, as a gradual ramp |

One code path; governance picks the endpoint. Migration stops being a distinct
dangerous operation and becomes "set the old quote's target to zero".

Guardrails, all enforced on-chain:
- **allowlist** — curated by the timelock, never by the proposer
- **max share per non-primary quote** so one vote cannot move the whole book
- **min share in the primary quote** so the deep book always survives
- **cooldown** between reallocations, or churn bleeds slippage every rotation
- **cost borne by the generation's own fees**, so a bad call is paid for by
  those who made it

---

## 2. Allowlist admission criteria

The timelock curates; a proposer only picks from the set. A proposer curating
their own allowlist is the obvious capture vector — they add a honeypot and
drain the pool into it.

A quote should be admitted only if:

1. **It is a real ERC20 with no transfer hook.** A fee-on-transfer or
   rebasing token silently breaks every amount the pool accounts for.
2. **It has independent depth**, so the conversion swap at relaunch cannot be
   manipulated cheaply by whoever proposed it.
3. **Its decimals are known and handled.** USDG is 6, ETH is 18. Price maths
   that assumes 18 will be wrong by 10^12.
4. **It cannot be paused or blacklisted out from under the pool**, or a third
   party can freeze protocol liquidity. Where that is unavoidable (most
   tokenized equities), it is a disclosed risk of that pair, not a surprise.

## 3. Decimals

`_sqrtPrice(tokenAmount, quoteAmount)` takes raw amounts, so it is decimal-
agnostic by construction. What is *not* is anything formatting a price for
display or comparing across quotes. Every such site must read the quote's
`decimals()` rather than assuming 18. Frontend included.

## 4. Perps on non-ETH quotes

Explicitly refused until Phase 3. `PerpEngine` denominates collateral,
principal, funding and the insurance buffer in ETH, and its vault is two-sided
ETH/token. Allowing a non-ETH generation to open positions before that work is
done would mis-denominate real user funds.

The refusal is a revert with a named error, so the frontend can say "perps are
ETH-only for now" rather than failing opaquely.

## 5. Legacy buyback — deferred, deliberately

`legacyBuyStep` hardcodes `SwapParams({ zeroForOne: true })` and settles with
`poolManager.settle{value: spent}()`. Both assume a native quote at
`currency0`. Generalizing it means computing `zeroForOne` from
`quoteIsCurrency0` and branching the settle to transfer-then-sync.

`_maybeLegacyBuyback` already early-returns when `legacyRegistry == address(0)`,
so **not enabling legacy buyback for a non-ETH generation costs zero code**.
Its `floorBps` share is routed to the relaunch reserve instead of being left
stuck.

This is a real, bounded piece of work — deferred, not hand-waved.

## 6. Audit checkpoints

An audit pass at the end of each phase, not once at the end:

- **After Phase 1** — permission model only. Small, fast.
- **After Phase 2** — the currency-ordering branch is the whole risk. Every
  `zeroForOne`, every `amount0/amount1`, every fee-side derivation, against a
  generation whose token sorts *below* the quote. A fork test with a token
  mined to sort first is the single highest-value test in this work.
- **After Phase 3** — perp/vault re-denomination, where user funds sit.
- **After Phase 5** — governance-triggered movement of protocol-owned
  liquidity; the highest-consequence path in the system.

## 7. Invariants that must hold throughout

1. A pool the registry did not create is never tracked. *(C-01)*
2. A generation's quote never changes after summon. Reallocation adds pools; it
   does not mutate one.
3. The reserve only leaves against a burn or a debited claim, whatever the quote.
4. A failed payout never bricks a swap — it rolls to the relaunch reserve, in
   the quote, exactly as the ETH path does today.
5. Depth in the primary quote never falls below the governed floor.

---

## Re-pairing a LIVE generation

A pool's currencies are inside its `PoolId` (`keccak256(abi.encode(PoolKey))`),
so a different quote is a different pool — always. "Changing the pair" therefore
means standing up a second pool and moving value into it.

### The constraint that shapes everything

Converting the LP's ETH into USDG requires **selling ETH for USDG somewhere**,
and that somewhere is an external pool. Today nothing in the protocol swaps
outside its own pools (verified: every `poolManager.swap` call site targets a
pool we created). Adding that would introduce a dependency whose depth and
honesty we do not control, on trades made with protocol-owned liquidity — and a
thin or manipulated USDG/ETH market turns into a bad fill on the treasury.

### The approach that avoids it

We hold 777,000,000 tokens, most parked in the out-of-range reserve. So seed the
new `(USDG, token)` pool **single-sided with tokens only**, below spot — exactly
what `_seedReserve` already does for the reserve position.

- No ETH is sold, so there is **no conversion swap and no sandwich surface**.
- The pool is live and tradeable immediately: anyone can buy the token with USDG.
- **Traders bring the USDG in.** The quote side fills from organic demand rather
  than from a scheduled protocol sale.
- The ETH pool is untouched and keeps trading; the two pools arbitrage against
  each other, which is what actually equalises price.

This satisfies the stated requirements directly:

| Requirement | How |
| --- | --- |
| Never remove 100% of the old LP | Removes **none** of it |
| Community sets the share | Governance picks the % of TOKEN supply placed in the new pool |
| Gradual + automatic | Fills with organic demand; no timer, no protocol swap |
| No sandwich slippage | There is no protocol trade to sandwich |

### What still has to be built

1. **`generationPools[gen]` — a set, not a single id.** Today
   `generationPoolId[gen]` is 1:1 and the LP position, seed and death check all
   assume it.
2. **Death detection must aggregate.** `isDead(PoolId)` measures volume per
   pool. Split liquidity and the primary pool's volume can fall under
   `deathThreshold` while the generation is healthy — a spurious relaunch. This
   is the one thing that genuinely breaks, and it must land before any second
   pool goes live.
3. **Guardrails.** Max share per non-primary quote, minimum share in the primary,
   and a cooldown between changes.
4. **Frontend.** Show which pool a price came from and let the user pick.

### If a true ETH→USDG conversion is still wanted later

Mirror `CauldronSeeder`: a time-windowed target, `step = target - done`, poked
from inside `afterSwap`, with a minimum step so dust is skipped. Gradual and
automatic falls straight out of that machinery. It still needs the external
market, so it should be gated on a per-step slippage bound and a floor that
keeps a fixed share of liquidity in ETH.

