# 06 — The Hook

`contracts/solidity/CauldronHook.sol` (2,473 lines), built on the vendored
`contracts/solidity/vendor/BaseHook.sol`.

This document describes what the hook does on every swap, in the order the code
runs it, with the gate on each branch. Every mechanism carries the source line it
was read from. Where a comment, a README or an older spec disagrees with the code,
the code is documented and the disagreement is listed in **Documentation debt** at
the end.

---

## 1. What the hook is

A Uniswap V4 hook attached to one pool per generation. It does five jobs inside the
pool manager's swap callbacks:

1. **Charges a trading fee** and routes it (see `07-FEES.md`).
2. **Accounts trading volume** into a 24-hour sliding window, which is what
   "death" is measured against (`CauldronHook.sol:1502`, `:1605`).
3. **Accrues NFT mint credit** to the trader (`CauldronHook.sol:892-902`).
4. **Fires three best-effort side-effects** with leftover gas: a perp liquidation
   sweep, a progressive-seeder nudge, and a native gacha step.
5. **Runs a nested buyback swap** against the live pool when a buffer crosses a
   threshold (`CauldronHook.sol:1016`).

It holds custody of the fees it takes. `relaunchETH` (`CauldronHook.sol:286`) and
`relaunchAsset` (`CauldronHook.sol:2452`) are the counters the registry pulls from
to fund the next generation.

---

## 2. Permission bits

Declared once in `getHookPermissions` (`CauldronHook.sol:573-595`) and checked
against the deployed address during construction: `BaseHook` calls
`validateHookAddress(this)` (`vendor/BaseHook.sol:19`), which calls
`Hooks.validateHookPermissions` (`vendor/BaseHook.sol:32`). A V4 hook's address
encodes its permissions, so this is a constructor-time assertion that the CREATE2
salt was mined correctly.

| bit | value | line | why it is needed |
|---|---|---:|---|
| `beforeInitialize` | false | 580 | no body |
| `afterInitialize` | **true** | 581 | the adoption gate — see §3 |
| `beforeAddLiquidity` | false | 582 | no body |
| `afterAddLiquidity` | false | 583 | no body |
| `beforeRemoveLiquidity` | false | 584 | no body |
| `afterRemoveLiquidity` | false | 585 | no body |
| `beforeSwap` | **true** | 586 | charges the fee on the buy leg, before the swap executes (`:1217`) |
| `afterSwap` | **true** | 587 | volume, credit, side-effects, and the sell-leg fee |
| `beforeDonate` | false | 588 | no body |
| `afterDonate` | false | 589 | no body |
| `beforeSwapReturnDelta` | **true** | 590 | without it the manager ignores the `BeforeSwapDelta` returned at `:1223` and the buy-leg fee is never collected |
| `afterSwapReturnDelta` | **true** | 591 | without it the manager ignores the `int128` returned at `:1003` and the sell-leg fee is never collected |
| `afterAddLiquidityReturnDelta` | false | 592 | no body |
| `afterRemoveLiquidityReturnDelta` | false | 593 | no body |

The nine disabled callbacks fall through to `BaseHook`'s defaults, which revert
`HookNotImplemented` (`vendor/BaseHook.sol:16`, e.g. `:45`).

All callbacks are gated by `onlyPoolManager`, a modifier inherited from
v4-periphery's `ImmutableState` (`vendor/BaseHook.sol:10`) and applied at each
entrypoint (e.g. `vendor/BaseHook.sol:38`). The manager address is fixed at
construction and cannot be rotated.

---

## 3. Pool adoption — `_afterInitialize`

`CauldronHook.sol:622-654`.

**What it does.** It decides whether a pool exists as far as this protocol is
concerned, and it refuses every pool the registry did not create.

```
require(sender == registry);                                   // :631
bool q0 = IRegistryQuotes(registry).allowedQuote(currency0);   // :645
quoteIsCurrency0[id] = q0;                                     // :648
trackedPools[id]     = true;                                   // :649
_lastUpdateTs[id]    = block.timestamp;                        // :650
poolInitBlock[id]    = block.number;                           // :651
```

Three consequences a reader should hold onto:

- **A foreign initialize reverts; it is not merely ignored.** The reasoning is
  recorded at `:601-621`: the next generation's token address is CREATE2-mined from
  public inputs, so its `PoolKey` is computable before the token exists. An
  outsider who initialized that key first would make every future `relaunch()`
  revert. Reverting here is what makes the key unsquattable.
- **Which side is the quote is decided once, here, and never re-derived.**
  `quoteIsCurrency0[id]` (`:672`) governs every later fee take, volume read and
  buyback gate for that pool. Native ETH is `address(0)` and always sorts first, so
  an ether pair is always `true`; an ERC20 quote can land on either side.
- **The anti-sniper window is anchored in `block.number`** (`:651`), not in
  wall-clock seconds. See §8.

`trackedPools[id]` is the master gate. An unadopted pool gets no fee, no volume, no
credit, no buyback and no seeder poke — the hook is inert for it
(`:792`, `:1180`).

---

## 4. `_beforeSwap`, in execution order

`CauldronHook.sol:1170-1226`.

| # | line | gate | effect |
|---:|---:|---|---|
| 1 | 1177 | `_inSelfBuy \|\| _inRelaunchClose` | return zero delta — the hook's own nested swaps pay nothing |
| 2 | 1179 | — | `PoolId id = key.toId()` — hashed once for the whole callback |
| 3 | 1180 | `!trackedPools[id]` | return zero delta |
| 4 | 1182-1183 | — | load `q0`; `exactInput = params.amountSpecified < 0` |
| 5 | 1204 | `!exactInput && !inputIsQuote` | **revert `ExactOutSellUnsupported`** |
| 6 | 1205-1207 | `!exactInput \|\| !inputIsQuote` | return zero delta — this leg is charged in `afterSwap` instead |
| 7 | 1209-1211 | `_isExemptPlayer(sender, hookData)` | return zero delta |
| 8 | 1216-1217 | — | `amountIn = uint256(-params.amountSpecified)`; `fee = _takeEthFee(..., isBuy = true)` |
| 9 | 1218-1220 | `fee == 0` | return zero delta |
| 10 | 1221-1225 | — | return `toBeforeSwapDelta(int128(int256(fee)), 0)` |

`_beforeSwap` reads **no pool state at all**. Every decision comes from `params`
and from storage.

### Which quadrant is charged where

"Buy" means the quote is the input. "Sell" means the iteration token is the input.

| quadrant | `_beforeSwap` | `_afterSwap` | fee base |
|---|---|---|---|
| exact-input buy | charges (`:1217`) | skips (`:985-989`) | gross quote in, `-params.amountSpecified` (`:1216`) |
| exact-output buy | zero delta (`:1205-1207`) | charges (`:996-1001`) | realised quote leg of the `BalanceDelta` (`:996`) |
| exact-input sell | zero delta (`:1205-1207`) | charges (`:996-1001`) | realised quote out (`:996`) |
| exact-output sell | **reverts** (`:1204`) | — | — |

The exact-output sell revert is deliberate and is the one swap shape the hook
cannot price: on that quadrant the quote is the *specified* leg, and a hook cannot
skim a specified exact-output amount without changing what the trader asked for.
The error name is `ExactOutSellUnsupported` (`:144`).

---

## 5. `_afterSwap`, in execution order

`CauldronHook.sol:779-1004`. Every step below is in the order the code runs it.

| # | line | gate | effect |
|---:|---:|---|---|
| 1 | 788 | `_inSelfBuy \|\| _inRelaunchClose` | return `(selector, 0)` — no fee, no volume, no side-effects |
| 2 | 789 | — | `PoolId id = key.toId()` |
| 3 | 792 | `!trackedPools[id]` | return `(selector, 0)` |
| 4 | 795 | — | `bool q0 = quoteIsCurrency0[id]` |
| 5 | **799** | see §7 | **`_maybeLegacyBuyback(id, key)`** — a nested swap against the live pool |
| 6 | 801 | see §6 | `_maybePoke()` — the progressive seeder's in-swap nudge |
| 7 | 812-815 | — | read the quote leg of the delta; take its absolute value |
| 8 | 836 | — | `_toUsd(...)` — external, state-changing oracle call |
| 9 | 837-840 | `absVolume > 0` | `_recordVolume(id, absVolume)`; `cumulativeVolume += absVolume` |
| 10 | 857-859 | `collection != 0 && absVolume > 0 && key.currency1 == _liveKey.currency1` | enter the credit branch |
| 11 | 874-877 | `hookData.length >= 32` → decode; else `creditUntaggedSwaps ? tx.origin : 0` | pick the credited player |
| 12 | 882 | `player == registry` | drop the credit |
| 13 | 888-889 | `isBuy = params.zeroForOne == q0` | `weighted = absVolume * (isBuy ? buyWeightBps : sellWeightBps) / BPS` |
| 14 | 892-902 | — | saturating add to `nftCredit`, `lifetimeVolumeOf`, `totalLifetimeVolume` |
| 15 | 907-910 | `tagged && quest != 0` | low-level `quest.call(onSwap(address,uint256))`, result ignored |
| 16 | 911-917 | `!tagged` | defer a native gacha step to step 18 |
| 17 | 946-953 | `perpEngine != 0 && sender != perpEngine && gasleft() > 580_000` | `perpEngine.call{gas: gasleft()-180_000}(sweepLiquidations(tx.origin))`, result ignored |
| 18 | 963-969 | `gachaPlayer != 0 && gasleft() > 500_000` | `address(this).call{gas: gasleft()-200_000}(nativeGachaStep(...))`, result ignored |
| 19 | 985-989 | unspecified leg is not the quote | return `(selector, 0)` — already charged in `_beforeSwap` |
| 20 | 991-993 | `_isExemptPlayer` | return `(selector, 0)` |
| 21 | 996-1001 | — | `fee = _takeEthFee(..., isBuy = false)` on the realised quote leg |
| 22 | **1002** | see §7 | **`_maybeLegacyBuyback(id, key)` again** |
| 23 | 1003 | — | return `(selector, int128(uint128(fee)))` |

Two things in that list are easy to miss:

- **`_maybeLegacyBuyback` runs twice per `afterSwap`** — once at `:799` and once at
  `:1002`. The second call can fire when the first did not, because the fee taken
  at step 21 may be exactly what pushes `legacyBuffer` over `legacyThreshold`
  (`:320`, default `0.02 ether`).
- **Credit is gated on the token, not the pool.** Step 10 requires
  `key.currency1 == _liveKey.currency1` (`:859`) — a sibling pool trading the same
  iteration token accrues credit; a pool trading anything else does not.

---

## 6. What is computed from live pool state during your swap

This is the sharp edge of the design and deserves a plain statement.

### 6a. The hook itself makes no direct pool-state read

`CauldronHook.sol` imports `StateLibrary` (`:13`) and declares
`using StateLibrary for IPoolManager` (`:119`), but **calls nothing through it**.
There is no `getSlot0`, no `getLiquidity`, no `extsload` anywhere in the hook's own
body. The `using` declaration is vestigial.

This is a behaviour change from earlier builds. Until commit `69dc15d` the
anti-sniper surtax folded the pool's **live tick** into its jitter seed, read via
`poolManager.getSlot0` inside `_beforeSwap`. That was removed because a swapper
could place a probe swap ahead of its real one in the same transaction and move the
tick — i.e. steer its own tax rate (`cauldron/SurtaxLib.sol:69-75`). The measured
figure recorded there is 6,402 bps instead of 9,600 bps in one block.

### 6b. What `_afterSwap` reads

It reads the **manager's already-computed `BalanceDelta`** (`:783`), twice:

| read | line | derived from it |
|---|---:|---|
| quote leg, for volume | 812 | `_toUsd` (`:836`) → bucket write (`:1523`) → `cumulativeVolume` (`:839`) → `weighted` (`:889`) → `nftCredit` / `lifetimeVolumeOf` / `totalLifetimeVolume` (`:893-901`) → the in-swap gacha play size (`:916`) |
| quote leg, for the sell-leg fee | 996 | `ethAmount` → the entire sell-leg fee (`:1001`) |

Which side is read is decided by the **stored** `quoteIsCurrency0` (`:795`), not by
inspecting the key. The answer recorded at adoption governs every later swap.

### 6c. What *nested* calls read and write

Three best-effort calls run inside your `afterSwap`, while the pool manager's
unlock is still held. They are the real live-state consumers, and one of them
**moves the price you just traded at**:

| callee | fired at | reads / writes live pool state |
|---|---:|---|
| `CauldronSeeder.pokeInSwap()` | `:1072` | reads `getSlot0` (`cauldron/CauldronSeeder.sol:331`, `:368`, `:463`) and adds liquidity via core `modifyLiquidity`. Out of scope — see the seeder doc. |
| `PerpEngine.sweepLiquidations(tx.origin)` | `:949` | reads `getSlot0` / `getLiquidity` through `cauldron/PerpMarkSource.sol:162`, `:170`, `:175`, `:177`, and performs nested settlement swaps. Out of scope — see the perp doc. |
| `CauldronHook.legacyBuyStep(live)` | `:1055` | **reads `poolManager.getSlot0` at `cauldron/LegacyBuyLib.sol:97` and then executes `poolManager.swap` at `:100`.** |

The buyback is the one to understand. It:

- reads the **current** sqrt price (`LegacyBuyLib.sol:97`) and derives its own price
  limit as `sqrtP * 9486 / 10_000` (`:98`, constant at `:47`). That is ~0.8998 of
  the *price*, i.e. the buy may move the pool at most ~10% before it stops early
  (`:44-46`);
- executes an exact-input `zeroForOne` swap for up to the whole `legacyBuffer`
  (`:100-108`);
- reverts `NoOutput()` if it bought nothing (`:135`), which rolls the whole
  `legacyBuyStep` frame back and preserves the buffer (`:37-39`).

So: **another swap can execute against the pool between your `beforeSwap` and the
end of your `afterSwap`, initiated by the hook, bounded by a ~10% price move.** It
is skipped cheaply below `LEGACY_GAS_MIN` (`:344`) and it only ever spends into
`_liveKey`, never into the key of the swap that triggered it (`:1051`).

### 6d. The oracle call

`_toUsd` (`:742-751`) is a **`call`, not a `staticcall`** (`:745`), because the
cached oracle entrypoint writes. That means the oracle can re-enter the hook. The
code states this plainly (`:732-740`): `quoteOracle` sits in the same trusted tier
as `feeRouter`, `deathChecker` and `surtaxPolicy` — all timelock-set, and a
compromised oracle is a compromised hook.

A failed call, short returndata, or a zero factor all produce `0` (`:748-750`),
which means **"cannot judge"**, not "no volume". Nothing is recorded for such a
swap (`:837`) and `_lastUpdateTs` is deliberately not advanced (`:829-835`), so the
existing 24-hour window doubles as the outage grace period.

### 6e. `tx.origin`

Two paths use `tx.origin` rather than `msg.sender`:

- untagged-swap credit attribution (`:877`), enabled by `creditUntaggedSwaps`
  (`:430`, default `true`);
- the liquidation sweep's credited keeper (`:950`).

---

## 7. The legacy buyback gate

`_maybeLegacyBuyback` (`CauldronHook.sol:1016-1059`), in order:

| # | line | condition | effect |
|---:|---:|---|---|
| 1 | 1017 | `legacyRegistry == 0 \|\| legacyBuffer == 0` | return |
| 2 | 1028-1036 | `legacyBufferAsset != live.currency0` | **zero the buffer and credit its whole balance to the reserve in its own asset** via `_creditFor`, then return |
| 3 | 1037 | `legacyBuffer < legacyThreshold` | return |
| 4 | 1048 | `!quoteIsCurrency0[id]` | return — the library assumes the quote is `currency0` |
| 5 | 1050 | `live.currency1 == address(0)` | return — live key not wired yet |
| 6 | 1051 | `id != live.toId()` | return — only the live pool |
| 7 | 1053-1058 | `gasleft() > LEGACY_GAS_MIN` (300,000) | `address(this).call{gas: gasleft()-220_000}(legacyBuyStep(live))` |

Step 2 is the denomination self-heal added by `f9c775f`: a buffer left over in a
previous generation's quote is not spent as the new quote, it is handed back to the
per-asset reserve.

`legacyBuyStep` (`:1083-1121`) is `OnlySelf` (`:1084`), sets `_inSelfBuy` around the
nested swap (`:1094`, `:1109`), re-checks the buffer asset against `key.currency0`
and reverts `BadParam` on a mismatch (`:1101-1102`), and passes the matching
reserve counter as `encumbered` so the buy can never spend balance another counter
still claims (`:1108`). Any unspent remainder goes back into the buffer (`:1113`).
The tokens bought are held on the hook and counted in `legacyOwedToReserve`
(`:1119`), to be pulled later by `sweepLegacyReserve` (`:1154-1161`).

---

## 8. Volume, the 24-hour window, and death

**What it does.** It answers one question: has this generation's trading fallen
below `deathThreshold` over the last 24 hours? A `true` answer is what unlocks the
permissionless relaunch (gated separately by the registry).

### The clock

The window is denominated in **wall-clock seconds**, not blocks:

| constant | value | line |
|---|---|---:|
| `HOURS_PER_DAY` | 24 | 195 |
| `SECONDS_PER_HOUR` | `1 hours` | 196 |
| `SECONDS_PER_DAY` | `1 days` | 197 |

`_getCurrentBucket() = (block.timestamp / SECONDS_PER_HOUR) % HOURS_PER_DAY`
(`:1627-1629`). The rationale is recorded at `:175-199`: on Arbitrum Nitro and
Orbit chains `block.number` reports the *parent* chain's block number, so a
block-counted window would have had a wall-clock length set by the settlement
layer.

### Recording

`_recordVolume` (`:1502-1530`):

- if more than a day has passed since the last update, **all 24 buckets are wiped**
  (`:1507-1510`);
- otherwise every bucket strictly between the last written index and the current
  one is zeroed, capped at 24 steps (`:1511-1520`);
- the add into the current bucket **saturates** at `type(uint128).max` rather than
  wrapping (`:1523-1525`).

Buckets are `uint128[24]` (`:273`) so two share a storage slot and the sum costs 12
SLOADs.

`getVolume24h` (`:1532-1540`) returns **`0` outright** if
`block.timestamp > _lastUpdateTs[id] + SECONDS_PER_DAY` (`:1533`) — a hard cliff for
total inactivity, independent of per-bucket eviction.

### Aggregating siblings

`isDead` (`:1605-1625`):

```
vol = getVolume24h(id) + Σ getVolume24h(sibling)     // :1611-1613
if (deathChecker set) try checker.isDead(id, vol, deathThreshold)
                      catch  return vol < deathThreshold   // :1618-1622
return vol < deathThreshold                                 // :1624
```

`_volumeSiblings` (`:765`) is written only by `linkVolume` (`:1573-1600`), which is
**registry-only** (`:1574`), **reverts `PerpsOpen` while any perp position is open**
(`:1575-1577`), is idempotent (`:1595-1597`) and is capped at
`MAX_SIBLINGS = 9` (`:770`, enforced `:1593`). The link is one-directional: it is
keyed under the primary only.

### Units

| oracle wired? | bucket unit |
|---|---|
| no (`quoteOracle == 0`) | **raw units of the quote asset** — `_toUsd` returns `raw` (`:744`) |
| yes | **USD at 1e18** — `raw * factor / 1e18` (`:750`) |

There is no `decimals()` read anywhere in the hook. The entire scale conversion is
whatever `cachedUsdPerRawUnit` returns. Wiring the oracle therefore re-denominates
the ledger, and `setDeathThreshold` (`:1748`) forces the caller to restate
`deathThreshold`, `volumePerNFT`, `nftPriceStep` and `oddsFullVolumeWei` in the same
call, rejecting zeros (`:1757-1760` region).

---

## 9. The fee rate: base tax plus surtax

`_takeEthFee` (`CauldronHook.sol:1437-1489`) computes the rate, takes the money, and
hands it to the routing described in `07-FEES.md`.

```
taxRate  = _getHolderTaxRate(_taxedPlayer(sender, hookData));   // :1450
totalBps = taxRate + snipeSurtaxBps(id);                        // :1452
if (totalBps > MAX_TOTAL_FEE_BPS) totalBps = MAX_TOTAL_FEE_BPS;  // :1453
total    = ethAmount * totalBps / BPS;                          // :1454
baseBps  = min(taxRate, totalBps);                              // :1459
baseFee  = ethAmount * baseBps / BPS;                           // :1460
surtax   = total - baseFee;                                     // :1461
feeCur   = quoteIsCurrency0[id] ? currency0 : currency1;        // :1469
_feeAsset = Currency.unwrap(feeCur);                            // :1470
poolManager.take(feeCur, address(this), total);                 // :1471
```

### Base rate

| source | value | units | line |
|---|---|---|---:|
| `nftContract == address(0)` | `defaultTaxBps` | bps of the quote leg | 1636 |
| `defaultTaxBps` default | 300 | bps (3%) | 234 |
| `defaultTaxBps` cap (`MAX_TAX_BPS`) | 1,000 | bps (10%) | 153, enforced 1648 |
| `nftContract` set | `INFTContract.getHolderTaxRate(holder)` in a `try`/`catch` falling back to `defaultTaxBps` | bps | 1638-1642 |

The "holder" charged is `_taxedPlayer` (`:2402-2406`): for a whitelisted opener
passing at least 32 bytes of `hookData`, the decoded player; otherwise `sender`.

`taxExempt` (`:449`) zeroes both base and surtax, but only when the *player* is
exempt **and** the sender is a registered opener (`_isExemptPlayer`, `:2394-2396`) —
so it exempts a specific wallet, never a router.

### Anti-sniper surtax

`snipeSurtaxBps` (`:1418-1427`) delegates to `SurtaxLib.surtaxBps`
(`cauldron/SurtaxLib.sol:33-51`), which tries a pluggable `surtaxPolicy` first,
clamps its answer to the hard cap, and falls through to the built-in curve on any
revert (`:45-49`).

Built-in curve, `SurtaxLib.defaultSurtaxBps` (`:54-105`):

```
if (maxBps == 0 || window == 0 || start == 0) return 0;         // :59
elapsed   = block.number - start;                               // :60
if (elapsed >= window) return 0;                                // :61
remaining = window - elapsed;                                   // :63
decayed   = maxBps * remaining / window;                        // :65
rnd       = keccak256(blockhash(block.number-1), poolId,
                      block.number, block.prevrandao)
            % (maxBps + 1);                                     // :97-101
jitter    = rnd * remaining / window;                           // :102
total     = decayed + jitter;                                   // :103
return total > maxBps ? maxBps : total;                         // :104
```

| parameter | default | units | line | ceiling |
|---|---|---|---:|---|
| `snipeWindowBlocks` | 30 | **blocks** | 507 | none |
| `snipeMaxBps` | 9,600 | bps | 513 | `MAX_SNIPE_BPS = 9_900` (516), enforced 1493 |
| combined base + surtax | — | bps | — | `MAX_TOTAL_FEE_BPS = 9_900` (523), enforced 1453 |

**Entropy, stated honestly.** The seed is per-**block**, not per-call:

- `blockhash(block.number - 1)` is fixed for the whole of block N and is already
  public when block N is being built. A searcher can compute the exact surtax for
  block N once block N-1 exists — but cannot choose which block their transaction
  lands in, and cannot change the value from inside their own transaction.
- `block.prevrandao` is noted in the code as a **constant on Arbitrum/Orbit**
  (`SurtaxLib.sol:79-82`), so on the intended deployment target it contributes
  nothing. It is an addition, not a replacement.
- A block **proposer** knows and influences both terms. The surtax is not
  unpredictable to whoever builds the block.
- The jitter **adds** to the decay rather than taking a `max` of the two. The code
  records why (`:85-96`): under a `max`, `jitter <= decayed` for all inputs, so the
  jitter branch was dead and the rate was fully predictable from the block number
  alone.
- Because the window is counted in `block.number` (`:60`) while the volume window
  is counted in seconds, the surtax window's wall-clock length is a property of the
  settlement layer — the exact asymmetry the volume clock was changed to avoid
  (`CauldronHook.sol:175-199`). Flagged as an observation, not a judgement; whether
  it matters depends on the chain, and the L2 `block.number` claim is taken from the
  in-code comment, not independently verified here.

---

## 10. Gas gates on the best-effort branches

Every one of these is a low-level call whose result is **discarded**. None can
revert the parent swap; all can silently not happen.

| branch | fires when | forwards | lines |
|---|---|---|---:|
| seeder poke | `gasleft() > 750_000` | `gasleft() - 350_000` | 1071-1072; constants 361-362 |
| perp sweep | `gasleft() > 180_000 + 400_000` | `gasleft() - 180_000` | 948-951; constants 157, 168 |
| native gacha | `gasleft() > 500_000` | `gasleft() - 200_000` | 965-968; constants 171-172 |
| legacy buyback | `gasleft() > 300_000` | `gasleft() - 220_000` | 1054-1057; constants 343-344 |

`LIQ_GAS_MIN` was raised to 400,000 from a measured kill cost of ~388,000; the
comment at `:158-167` records that at the old value there was a ~440k-wide band in
which the sweep always fired and always failed, burning a measured 266,833 gas of
the swapper's money per swap.

Note the gacha gate compares `gasleft()` against `GACHA_GAS_MIN` and then subtracts
`GACHA_GAS_RESERVE`, whereas the perp gate compares against the **sum** of its two
constants. The two gates are not shaped the same way.

---

## 11. Re-entrancy and self-call flags

| flag | type | set by | effect |
|---|---|---|---|
| `_inSelfBuy` | `transient bool` (`:336`) | `legacyBuyStep` (`:1094`, cleared `:1109`) | both `before`- and `afterSwap` early-return (`:788`, `:1177`) so the hook's own buy pays no fee, accrues no volume and fires no side-effect |
| `_inRelaunchClose` | `transient bool` (`:341`) | the registry-driven relaunch force-close | same early return; the perp engine pays full fees at all other times |
| `_feeAsset` | `transient address` (`:698`) | `_takeEthFee` (`:1470`) | the asset the fee currently being routed was collected in; read by every routing helper |

`_feeAsset` is transient rather than plain storage so a stale value cannot survive
into a later transaction. The code is explicit about what that does *not* fix
(`:691-697`): transient storage persists for the whole transaction, so a nested swap
on a different-quote pool would still overwrite it mid-routing. Reaching that
requires the timelock-set `feeRouter` to re-enter.

---

## 12. Admin surface and trust tiers

| gate | who | notes |
|---|---|---|
| `onlyOwner` | the `Ownable` owner, set explicitly in the constructor (`:562`) | OpenZeppelin `transferOwnership` and `renounceOwnership` are inherited unmodified at this commit; renouncing would dead-end every owner setter permanently |
| `msg.sender != registry` | `registry` (`:256`) | one-shot at `setRegistry` (`:1901`); thereafter only via `proposeRegistryOverride` (`:1917`) → `executeRegistryOverride` (`:1937`) after `REGISTRY_SWAP_DELAY = 7 days` (`:263`), which is a `constant` so the owner cannot shorten their own notice |
| registry **or** owner | either | the per-brew wiring setters: `setCollection` (`:1969`), `setVault` (`:1997`), `setGuild` (`:2036`), `setSeeder` (`:2012`), `setPerpEngine` (`:2020`), `setQuest` (`:2003`), `setLegacyBuyback` (`:1846`), `setPolicies` (`:1870`), `setDeathChecker` (`:1860`), `setFeeRouter` (`:1882`), `setActiveProposer` (`:2056`), `setOpener` (`:2370`), `setTaxExempt` (`:2380`) |
| `legacyRegistry` | `legacyRegistry` (`:313`) | `sweepLegacyReserve` (`:1155`) |
| `address(this)` | the hook | `legacyBuyStep` (`:1084`), `nativeGachaStep` (`:2362`) |
| ungated | anyone | `fundLegacyBuffer` (`:1129`), `claimProposerFees` (`:2071`), `resolveTickets` (`:2287`), `receive()` (`:2472`), and every view |

**Trusted tier.** Four slots are reached with plain (re-entrant-capable) calls from
inside the swap path and must never point at anything the timelock does not
control: `quoteOracle` (`:703`, called at `:745`), `feeRouter` (`:229`, called at
`:1324`), `deathChecker` (`:214`), `surtaxPolicy` (`:221`). A compromised one of
these is a compromised hook. The code says so at `:732-740`.

**Bounded setters.**

| setter | bound | line |
|---|---|---:|
| `setDefaultTaxBps` | `<= MAX_TAX_BPS` (1,000) | 1648 |
| `setSnipeParams` | `maxBps <= MAX_SNIPE_BPS` (9,900); window unbounded | 1493 |
| `setFloorBps` | `<= BPS` (10,000) | 2030 |
| `setGuildBps` | `<= 1500` | 2049 |
| `setProposerBps` | `<= MAX_PROPOSER_BPS` (500) | 2064 |
| `setMaxOdds` | `<= ODDS_HARD_CAP_BPS` (9,500) | 2418 |
| `setWeights` | each `<= MAX_WEIGHT_BPS` (30,000) | 2424 |
| `setLegacyBuyback` | `bps <= BPS` | 1848 |

---

## Verification

- Documented against `git rev-parse --short HEAD` = **`20d6de2`**, reading each file
  from the committed tree (`git show 20d6de2:<path>`). At the time of writing the
  working tree had further uncommitted edits in `CauldronHook.sol`,
  `CauldronRegistry.sol`, `cauldron/CauldronGachaRouter.sol`,
  `cauldron/CauldronGovernor.sol`, `cauldron/PerpEngine.sol` and
  `cauldron/RedemptionExt.sol`. **Those are not reflected here**, and they shift line
  numbers. Re-check any citation against `20d6de2`, not against the working tree.

### Documentation debt — where a comment or prior doc disagrees with the code

1. **`CauldronHook.sol:115`** — the file header states the hook's permissions are
   "afterInitialize, afterSwap, afterSwapReturnDelta". The code also enables
   `beforeSwap` (`:586`) and `beforeSwapReturnDelta` (`:590`). Five bits, not three.
2. **`CauldronHook.sol:111-113`** — the header publishes a tiered tax table
   (Wizard 0 / King-Gnome 50 / Knight-Apprentice 100 / Peasant 200 / Non-holder 300
   bps). **No contract in this tree implements `getHolderTaxRate`**; it exists only
   as an interface declaration (`interfaces/INFTContract.sol:8`). With `nftContract`
   unset, every swapper pays `defaultTaxBps` (`:234`, 300 bps).
3. **`CauldronHook.sol:99`** — "Fully computed inside afterSwap(). No oracles."
   `_toUsd` (`:742`) makes a state-changing external oracle call from inside that
   same callback whenever `quoteOracle` is wired.
4. **`CauldronHook.sol:923-936`** — the comment describes a *hinted* liquidation
   (`liquidateInSwap` at the position named in `hookData`). The code calls the
   hint-free `sweepLiquidations` (`:949`).
5. **`CauldronHook.sol:205`** and **`cauldron/IDeathChecker.sol:23`** — both still
   say the 24h volume is "in currency0 terms". It is measured on the **quote** side,
   which may be `currency1` (`:812`), and is USD-at-1e18 once an oracle is wired.
6. **`CauldronHook.sol:239-252`** — `treasury` is described as a dead slot read by
   nothing; the constructor still writes it (`:566`).
7. **`audit/graph/hook.md` §J1** — states that `_defaultSurtaxBps` performs
   "the cluster's only direct pool-storage read: `poolManager.getSlot0(id)` … on the
   fee path of EVERY swap". **Stale.** The graph predates `69dc15d`; the tick read
   was removed and the hook now makes no direct pool-storage read at all. Verified by
   grep over `CauldronHook.sol`.
8. **`audit/graph/hook.md` §H item 12** — cites a comment claiming "seven pools" for
   `MAX_SIBLINGS`. That comment text is no longer present; the constant is 9
   (`:770`).
9. **`audit/graph/hook.md` §H items 13-14** — flagged `LegacyBuyLib`'s header as
   claiming an ETH-only settle path. **Resolved** by `f9c775f`; the current header
   (`cauldron/LegacyBuyLib.sol:52-72`) documents the branch correctly.

### Not verified here

- The claim that `block.number` reports the parent chain's block number on Arbitrum
  Nitro / Orbit is taken from `CauldronHook.sol:175-191` and
  `cauldron/SurtaxLib.sol:79-82`. It is not independently confirmed in this
  document.
- The gas figures quoted in §10 (388k per kill, 266,833 burned per swap, 543,602
  minimum swap gas) are the code's own measured numbers (`:158-167`), not
  re-measured here.
