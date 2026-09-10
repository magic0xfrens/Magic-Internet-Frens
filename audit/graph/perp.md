# PerpEngine cluster — mechanical extraction

Scope: `cauldron/PerpEngine.sol` (1703 lines), `cauldron/PerpVault.sol` (366),
`cauldron/PerpMarkSource.sol` (188), `cauldron/PerpSwapLib.sol` (142),
`cauldron/PerpStakerOracle.sol` (32), read in full from
`/tmp/blind-tree/contracts/solidity/cauldron/`. All line numbers below were
verified by reading/grepping that exact line. This document extracts what the
code does; it does not assess whether that behavior is safe or correct.

---

## A. Solvency accounting — per-accumulator +/- inventory

### PerpEngine.sol

**`plv`** (PerpEngine.sol:280, `uint256`, quote-units — native wei if
`quote==address(0)`, else raw units of the ERC20 `quote`)
| Δ | Line | Code |
|---|---|---|
| + | 1065 | `plv += repay;` (`_settle`, long close: repay = min(proceeds, principal)) |
| + | 1105 | `plv += pay;` (`_settle`, funding: crowded long side pays in) |
| + | 1259 | `plv += toVault;` (`_routeFee`, long-side fee share) |
| + | 1319 | `plv += cover;` (`_replenishPlv`, insurance covers long bad debt) |
| + | 1450 | `plv += amount;` (`fundPlv`, owner donation) |
| + | 1504 | `plv += amount;` (`creditPerpFeeAsset`, hook-routed non-native fee) |
| + | 1517 | `plv += amount;` (`_creditPerp(true)`) |
| + | 1533 | `plv += amount;` (`fundFromVault`, vault deposit) |
| − | 767 | `plv -= borrow;` (`openLong`, lent to the position) |
| − | 1112 | `plv -= rest;` (`_settle`, funding: underweight side draws out, capped at plv) |
| − | 1330 | `plv = plv > rest ? plv - rest : 0;` (`_absorbPlvLoss`, **saturating**, not a plain `-=`) |
| − | 1541 | `plv -= amount;` (`withdrawPlvTo`, vault withdrawal) |

Read-only gates (not mutations): 755, 1111, 1540, 1641 (setVault drain guard).
**`receive() external payable {}` (line 1702) accepts ETH but does NOT touch
`plv` or any accumulator** — a bare transfer widens the gap between
`address(this).balance` and the sum of tracked accumulators (only relevant
when `quote == address(0)`).

**`plvToken`** (281, `uint256`, token-units of `syncedToken`)
| Δ | Line | Code |
|---|---|---|
| + | 1078 | `plvToken += p.size;` (`_settle`, short close: inventory returned in full) |
| + | 1458 | `plvToken += amount;` (`fundPlvToken`, owner) |
| + | 1552 | `plvToken += amount;` (`fundTokenFromVault`, vault) |
| − | 803 | `plvToken -= tokenToSell;` (`openShort`, lent to the position) |
| − | 1558 | `plvToken -= amount;` (`withdrawPlvTokenTo`, vault withdrawal) |
| SET | 993 | `plvToken = newInv;` (`syncGeneration` — full overwrite to the engine's real balance, not a delta) |

**`longOiEth`** (325, quote-units) — + 767 (`openLong`); − 1061 `longOiEth -=
p.principal;` (`_settle` long close); SET 995 `longOiEth = 0;`
(`syncGeneration`).

**`shortOiToken`** (326, token-units) — + 803 (`openShort`); − 1073
`shortOiToken -= p.size;` (`_settle` short close); SET 994 `shortOiToken =
0;` (`syncGeneration`).

**`insuranceEth`** (210, quote-units)
| Δ | Line | Code |
|---|---|---|
| + | 1264 | `insuranceEth += toIns;` (`_routeFee`) |
| + | 1464 | `insuranceEth += amount;` (`fundInsurance`, UNGATED) |
| − | 1109 | `insuranceEth -= fromIns;` (`_settle`, funding credit draw) |
| − | 1319 | `insuranceEth -= cover;` (`_replenishPlv`) |
| − | 1328 | `insuranceEth -= fromIns;` (`_absorbPlvLoss`) |
| − | 1678 | `insuranceEth -= amount;` (`skimInsurance`, owner) |

**`tokYieldEth`** (287, quote-units, segregated pot) — + 1261 (`_routeFee`
short-side), + 1519 (`_creditPerp(false)`); − 1547 `tokYieldEth -= amount;`
(`withdrawTokYieldTo`).

**`tokYieldCumulative`** (290, quote-units, **monotonic — grep found zero
decrements**) — + 1262, + 1520. Only ever read (by `PerpVault._syncTokYield`)
or incremented.

**`fundingIndex`** (293, `int256`, WAD(1e18)-scaled signed rate index, *not*
itself a value) — single mutation site: 701 `fundingIndex += step;`
(`_pokeFunding`, `step` can be negative). Snapshotted (not mutated) into
`Position.entryFunding` at 1225.

**`payoutOwed[address]`** (317, quote-units, IOU liability) — + 1303
`payoutOwed[to] += amount;` (`_payOut`, on push failure only, inside an
`unchecked` block); SET-to-zero 1311 `payoutOwed[msg.sender] = 0;`
(`claimPayout`, before the outbound push — CEI order).

**`badgesOwed[address]`** (312, NFT-mint count, not value) — + 1413
`badgesOwed[to] += 1;` (`_awardBadge`, unchecked); SET 1429
`badgesOwed[msg.sender] = owed - n;` (`claimLiquidatorBadges`).

**`openCount`** (308, position count, not value) — + 1223 `openCount++;`
(`_book`); − 1056 `openCount--;` (`_settle`). Gates at 959, 978, 1016, 1221.

### PerpVault.sol

**`ethShares`** (70, virtual-share units, `OFFSET=1e6`) — + 157 (`deposit`);
− 207 (`withdrawEth`). Per-user `ethShareOf[user]` (71) mirrors this: + 158,
SET 206 `ethShareOf[msg.sender] = bal - shares;`.

**`pendingEth`** (72, **asset**-units, i.e. ETH/quote, not shares) — + 209
(`withdrawEth`, queued remainder); − 224 (`claimPendingEth`). Per-user
`pendingEthOf[user]` (73): + 210, SET 223 `= owed - paid;`.

**`tokShares`** (76, virtual-share units) — + 274 (`depositToken`); − 309
(`withdrawToken`). Per-user `tokShareOf[user]` (77): + 275, SET 308 `= bal -
shares;`.

**`pendingTok`** (78, token-units) — + 312 (`withdrawToken`, queued
remainder); − 327 (`claimPendingToken`). Per-user `pendingTokOf[user]` (79):
+ 313, SET 326 `= owed - paid;`.

**`accEthPerTokShare`** (86, WAD(1e18)-scaled ETH-per-token-share, **grep
found zero decrements**) — single mutation site: 248 `accEthPerTokShare +=
FullMath.mulDiv(delta, ACC, tokShares);` (`_syncTokYield`, only when
`tokShares>0`).

**`lastTokYieldCum`** (87, quote-units watermark, **only ever advances**) —
246 `lastTokYieldCum = cum;` (`_syncTokYield`) — the code comment at
234-241 states this SET happens even at zero `tokShares`, specifically so the
watermark cannot be replayed against a later depositor.

**`tokRewardDebt[user]`** (88, quote-units — see Section D for a
comment/code mismatch on its documented scale) — SET (full overwrite) at 261
`_resetTokDebt`.

**`tokRewardOwed[user]`** (89, quote-units, claimable) — + 256
`_settleTok` (only if `acc > tokRewardDebt[user]`); SET-to-zero 290
(`claimTokYield`).

*(Both sides' engine accumulators above are the only place ETH/token
"backing" is tracked in this cluster; PerpVault's shares are a second-layer
accounting on top of `engine.totalEth()`/`engine.totalTokenAssets()`, not an
independent pool of funds.)*

---

## B. Liquidation — full path

**Entry points** (three ways `_settle` can be reached in liquidation mode):
1. `liquidate(uint256 id) external nonReentrant notNested` — PerpEngine.sol:823-837. Direct, UNGATED caller.
2. `sweepLiquidations(address liquidator) external` (848-851, hookAddr-only) → `_doSweep(liquidator, true)` (873-907) → `_tryLiquidate` (912-926) → `_settle`. Hook calls this from `_afterSwap` on every pool swap (confirmed: `CauldronHook.sol:711` is `_afterSwap`'s definition; call site at `CauldronHook.sol:878-884`: `perpEngine.call{gas:...}(abi.encodeWithSelector(IPerpEngineLiq.sweepLiquidations.selector, tx.origin))`).
3. `selfSweep(address liquidator) external` (857-860, self-call only) ← `_sweepAfterOpen` (863-868, best-effort try/catch) ← end of `openLong` (773) / `openShort` (810).

**Health formula** — `_underwaterVal`, PerpEngine.sol:1041-1051, quoted verbatim:
```solidity
function _underwaterVal(Position memory p, uint256 val) internal view returns (bool) {
    if (p.isLong) {
        // token worth less than debt + maintenance buffer
        return val < p.principal + (p.principal * maintenanceBps) / BPS;
    } else {
        // buying the owed token back costs more than the ETH backing − buffer
        uint256 backing = uint256(p.collateral) + p.principal;
        uint256 buffer = (backing * maintenanceBps) / BPS;
        return val + buffer > backing;
    }
}
```
**One-line summary**: LONG is liquidatable when `_quoteMark(size) <
principal * (1 + maintenanceBps/BPS)`; SHORT is liquidatable when
`_quoteMark(size) + (collateral+principal)*maintenanceBps/BPS >
collateral+principal`.

**Inputs and their origin**:
- `val` = `_quoteMark(p.size)` (682), computed **once** per liquidation check by the caller (`liquidate`:828, `_tryLiquidate`:917) and reused for both the health test and the per-block cap notional.
- `_quoteMark(size)` = `_quoteAt(size, markSqrtPriceX96())` (676-678, 682) — see Section C for `markSqrtPriceX96()`'s sourcing.
- `p.principal`, `p.collateral` — set once at open time (`_book`, 1217-1228) and never mutated afterward except by being deleted at settle.
- `maintenanceBps` — owner-tunable storage (default 1_500 = 15%), bounded `<= 5000` by `setRisk` (1588-1589).

**Per-block liquidation cap** (`liquidate`:830-835 and `_tryLiquidate`:919-924, identical logic):
```solidity
if (block.timestamp != liqBlock) { liqBlock = block.timestamp; liqEthThisBlock = 0; }
uint256 cap = (activeEthDepth() * maxLiqBps) / BPS;
if (cap > 0 && liqEthThisBlock + notional > cap) revert LiqCapped();   // liquidate(): revert; _tryLiquidate(): silent `return`
liqEthThisBlock += notional;
```

**Who may call**: `liquidate` — UNGATED (`if (p.trader == address(0)) revert
NotOpen();` line 825; no `msg.sender` restriction). `sweepLiquidations` —
`if (msg.sender != hookAddr) revert OnlyHook();` (849). `selfSweep` — `if
(msg.sender != address(this)) revert OnlyHook();` (858).

**What the liquidator receives, and the paying line** — `_settle`
MODE_LIQUIDATION branch, PerpEngine.sol:1116-1132:
```solidity
uint256 penalty = (uint256(p.collateral) * liqPenaltyBps) / BPS;
if (penalty > residual) penalty = residual;
uint256 toKeeper = (penalty * keeperBps) / BPS;
residual -= penalty;
_routeFee(penalty - toKeeper, p.isLong);
if (toKeeper > 0) _payOut(keeper, toKeeper);              // <- PerpEngine.sol:1122, the pay line
emit Liquidated(id, keeper, penalty);
_awardBadge(id, keeper, _killStats(p, toKeeper));          // also mints/credits a Liquidatoor NFT
```
`keeper` = `msg.sender` (direct `liquidate`) or the `liquidator` param
threaded from `sweepLiquidations`/`selfSweep` (ultimately `tx.origin` on the
hook path, per the call site quoted above). `keeperBps` default 145 (owner
bound `<=BPS`, `setFees`:1564). `_payOut` (1286-1304) is a 30_000-gas-capped
push that **never reverts** — on failure it credits `payoutOwed[keeper]`
instead (claimable via `claimPayout`).

Non-liquidation force-closes (`forceCloseDead`/`forceCloseAllDead`,
MODE_DEATH, gated only by `_isDead()==true`, UNGATED caller) pay a **reward**
instead of a penalty: `_settle` lines 1133-1137, `reward = (residual *
keeperBps) / BPS`, no `liqPenaltyBps` involved.

---

## C. Mark price — every source

1. **`_sqrtP()`** (PerpEngine.sol:456): `(s,,,) = poolManager.getSlot0(_key().toId());` — raw pool `slot0`, i.e. **SPOT**. No staleness/bounds check at this call site.
2. **`_currentTick()`** (501-519): tries `markSource.staticcall(weightedTick())`; requires `returndatasize()==0x20` (513, a *format* check only) before trusting the answer; casts the raw `int256` return to `int24` via truncation (516, `int24(v)` — no range check against tick bounds beforehand); on any failure (no code, revert, wrong-size return, or `markSource==address(0)`) falls back to `poolManager.getSlot0(_key().toId())` (518) — **SPOT fallback**, itself unchecked.
3. **`twapTick()`** (601-645): integrates the on-chain observation ring. Checks present: `if (nowTs <= MIN_TWAP) return (0,false);` (603); ring-reach fallback `unchecked { if (nowTs - oldest.ts < MIN_TWAP) return (0,false); }` (623, `MIN_TWAP`=1s, line 248); `if (span == 0) return (0,false);` (642).
4. **`markSqrtPriceX96()`** (648-651): `ok ? TickMath.getSqrtPriceAtTick(t) : _sqrtP();` — TWAP if available, **else raw spot** with no additional check.
5. **`activeEthDepth()`** (653-661): spot-only (`_sqrtP()` + `poolManager.getLiquidity`) — not itself "the mark" but a price-shaped read feeding every notional/OI/liquidation-cap comparison in the file.
6. **`PerpMarkSource.weightedTick()`** (PerpMarkSource.sol:158-187): live liquidity-weighted average, `Σ(tickᵢ×Lᵢ)/Σ(Lᵢ)`, over `primary` + up to `MAX_POOLS`(4) siblings, every pool read live via `getSlot0`/`getLiquidity` (no caching). Falls back to `primary`'s own tick when `pools.length==0` (165) or when `totalL==0` (185, "nothing in range anywhere").

**Consumption**: `_quoteMark(size)` (682, uses `markSqrtPriceX96()` — the
manipulation-resistant path) feeds the liquidation formula (`_underwaterVal`
via `liquidate`:828, `_tryLiquidate`:917, `isLiquidatable`:1028,
`positionHealth`:1697), the funding-imbalance sizing in `_pokeFunding`
(`shortEth = _quoteMark(shortOiToken)`, line 694), and the badge stats
(`_killStats`:1368). `_quoteEth(size)` (680, uses raw `_sqrtP()` — spot) has
exactly **one** call site by grep: `skimInsurance`'s `riskMin` (1675). **Note
(comment-vs-code, rule 4)**: the doc-comment on line 679 says `_quoteEth` is
"used for funding sizing," but `_pokeFunding` (line 694) actually calls
`_quoteMark`, not `_quoteEth` — the comment does not match current callers.
`_ethToToken(eth)` (1240-1243, spot-only) sizes `openShort`'s
`tokenToSell` (794) and the short-side OI cap (801).

**Read inside a swap callback?** Yes, on the auto-sweep path, but indirectly.
`sweepLiquidations` is invoked by `CauldronHook._afterSwap` (confirmed:
function at `CauldronHook.sol:711`, call site `CauldronHook.sol:878-884`) →
`_doSweep(liquidator, true)` → unconditionally calls `_pokeFunding()` (line
885 — the in-code comment there says this poke was deliberately moved
*before* the empty-book early-return so the mark can never go stale during a
quiet book) → `_writeObs()` → `_currentTick()`. So every pool swap routed
through the hook samples the oracle synchronously inside the hook's own
`afterSwap`. The pool-settlement callback itself (`unlockCallback` /
`_swapBody`) does **not** call `_currentTick`/`_writeObs` directly — the
oracle write happens in the calling entrypoints (open/close/liquidate/
poke/`_doSweep`), not inside swap settlement.

**Checks explicitly ABSENT** (as requested):
- No staleness/bounds check on `_sqrtP()` itself anywhere it's used directly (`activeEthDepth`, `_ethToToken`, `_quoteEth`, and the `markSqrtPriceX96()` cold-start fallback all consume raw spot).
- No value-range check on an external `markSource`'s returned tick before the `int24(v)` truncating cast (516) — only the return-data *length* is checked.
- `liquidate()`/`_tryLiquidate()` never call `_guardOpen` — the `warmup` gate (1201, `block.timestamp < registry.lastSummonAt() + warmup`) blocks **new opens only**; it does not gate liquidations, and there is no separate cold-start guard at the liquidation call sites if `twapTick()` returns `ok=false`.
- `PerpMarkSource.weightedTick()` has no staleness check (always-live reads) and no minimum-liquidity floor beyond a per-pool `l==0` skip (176) — any nonzero liquidity is weighted in, however thin.
- `PerpMarkSource.setPrimary`/`addPool` (both `onlyOwner`) accept any `PoolKey` with no check that the pool exists or has ever held liquidity.

---

## D. Units

| Field(s) | Unit | Established by |
|---|---|---|
| `plv`, `insuranceEth`, `tokYieldEth`, `tokYieldCumulative`, `longOiEth`, `payoutOwed[·]` | quote-units (native wei or raw ERC20 units of `quote`) | `_pullQuote`/`_pushQuote` transport (181-208); doc comment 160-170/332-352 |
| `plvToken`, `shortOiToken` | token-units of `syncedToken` | `fundPlvToken`/`fundTokenFromVault` direct `transferFrom` (1457, 1551); `_ethToToken` sizing (794) |
| `Position.collateral` (`uint128`) | quote-units, "ETH stake net of open fee" | comment line 299; narrowed via `uint128(collateral)` at `_book`:1224, **no explicit range check before the cast** |
| `Position.size` (`uint256`) | token-units | comment line 300 |
| `Position.principal` (`uint256`) | quote-units | comment line 301 |
| `Position.leverage` (`uint8`) | plain integer multiplier (1-10), **not** bps | bounded via `setRisk`'s `_ceiling<=10` (1588) and `_guardOpen`'s `leverage>maxLeverage()` (1203) |
| `fundingIndex`, `Position.entryFunding` (`int256`) | WAD, scaled 1e18 — a dimensionless rate index, not a value | comment line 292; `* 1e18` in `_pokeFunding` (699), `/ 1e18` in `_fundingDelta` (716) |
| `openFeeBps`, `ogDiscountBps`, `liqPenaltyBps`, `divShareBps`, `keeperBps`, `maintenanceBps`, `maxNotionalBps`, `maxOiBps`, `vaultYieldBps`, `insuranceBps`, `maxUtilBps`, `maxLiqBps`, `maxFundingBps`, `fundingRateBpsPerDay` | basis points, parts of `BPS`=10_000 (line 96) | — |
| `minCollateral` (131) | quote-units, default `0.003 ether` | a fixed raw-unit literal applied identically regardless of what `quote` actually is or its decimals — the same raw number means a very different real value on an 18-decimal vs. a fewer-decimal ERC20 quote |
| `tierDepthWei` (232) | quote-units | compared directly against `activeEthDepth()` |
| `twapWindow`, `warmup`, `OBS_INTERVAL`, `MIN_TWAP` | seconds | time constants, not value-denominated |
| `activeEthDepth()` return | code treats it as quote-units throughout (compared to `tierDepthWei`, multiplied by bps against OI) | derived from pool liquidity `L` + Q96 sqrtPrice via two `FullMath.mulDiv` (659-660); the closed-form itself was not independently re-derived here |
| PerpVault `ethShares`, `tokShares` (+ `ethShareOf`/`tokShareOf`) | virtual-share units, `OFFSET`=1e6 (PerpVault.sol:64) | `FullMath.mulDiv(amount, shares+OFFSET, assets+1)` (155, 272) |
| PerpVault `pendingEth`, `pendingEthOf`, `pendingTok`, `pendingTokOf` | **asset** units (ETH/quote, token) — not shares | used directly against `assetsEth()`/`assetsTok()` (117, 122) |
| PerpVault `accEthPerTokShare` (86) | WAD(1e18)-scaled ETH-per-token-share | `ACC`=1e18 (85); `+= FullMath.mulDiv(delta, ACC, tokShares)` (248) |
| PerpVault `tokRewardDebt`, `tokRewardOwed` (88-89) | plain quote-units (ETH), despite the comment | **comment-vs-code (rule 4)**: line 88 labels `tokRewardDebt` "1e18-scaled baseline," but line 261 computes `FullMath.mulDiv(shares, accEthPerTokShare, ACC)` — the `ACC` division is already applied, so the stored value is plain quote-units, matching `tokRewardOwed` (paid out 1:1 at PerpVault.sol:291) |

---

## E. Rounding

`FullMath.mulDiv` (imported from `lib/v4-core/src/libraries/FullMath.sol:14`,
read to confirm) floors: the non-overflow branch is literally `result :=
div(prod0, denominator)` (line 35, EVM `DIV`), and the 512-bit branch
reconstructs the same exact floored quotient. Grep confirmed **no** call in
this cluster ever uses `mulDivRoundingUp`. Plain Solidity `/` truncates
toward zero (relevant where signed `int256` operands appear, e.g. funding).

| # | Location | Expression | Mechanism | Direction |
|---|---|---|---|---|
|1| PerpEngine.sol:659-660 | `activeEthDepth()` two `mulDiv` calls | floor | depth estimate floored (no direct value transfer) |
|2| PerpEngine.sol:677 | `_quoteAt` two `mulDiv` calls | floor | mark value understated: marginally *easier* to trip the LONG liq test, marginally *harder* to trip the SHORT liq test |
|3| PerpEngine.sol:700 | `_pokeFunding` step, plain signed `/` | truncate-toward-zero | funding transfer magnitude under-charged this tick (both sides marginally) |
|4| PerpEngine.sol:716 | `_fundingDelta` raw, plain signed `/` | truncate-toward-zero | same as #3, per position |
|5| PerpEngine.sol:717 | `_fundingDelta` cap, `/BPS` inside cast | floor | cap marginally tighter |
|6| PerpEngine.sol:1044 | `_underwaterVal` long buffer | floor | favors TRADER (delays liquidation eligibility by ε) |
|7| PerpEngine.sol:1048 | `_underwaterVal` short buffer | floor | favors TRADER (same direction) |
|8| PerpEngine.sol:1117 | `_settle` penalty | floor | favors TRADER (smaller penalty, larger residual) |
|9| PerpEngine.sol:1119 | `_settle` toKeeper | floor | favors FEE ROUTE over KEEPER |
|10| PerpEngine.sol:1135 | `_settle` MODE_DEATH reward | floor | favors TRADER over keeper |
|11| PerpEngine.sol:1209 | `_takeFee` fee | floor | favors TRADER (opener) |
|12| PerpEngine.sol:1210 | `_takeFee` OG discount | floor | favors TRADER further |
|13| PerpEngine.sol:1215 | `_checkNotional` cap | floor | stricter cap (protocol-conservative) |
|14| PerpEngine.sol:760,765,798,801,833,922 | OI/util/liq `(X*bps)/BPS` caps | floor | all stricter (protocol-conservative), same as #13 |
|15| PerpEngine.sol:1251-1252 | `_routeFee` toVault, toIns | floor | remainder to div/treasury split marginally larger |
|16| PerpEngine.sol:1268 | `_routeFee` toDiv (toTre = remainder) | floor | favors TREASURY over dividend pot |
|17| PerpEngine.sol:1242 | `_ethToToken` two `mulDiv` calls | floor | `openShort` sizing (794): short trader owes marginally less token than exact notional; OI cap (801): marginally looser (different sites, different readings — not collapsed) |
|18| PerpEngine.sol:1367-1368 | `_killStats` entry, mark | floor (plain `/`, both unsigned) | informational badge stats only, not economically enforced |
|19| PerpEngine.sol:1675 | `skimInsurance` riskMin | floor | favors OWNER (can skim marginally more) |
|20| PerpMarkSource.sol:186 | `weightedTick` `acc / totalL`, plain signed `/` | truncate-toward-zero | oracle averaging, no value transfer |
|21| PerpVault.sol:155 | `deposit` shares | floor | favors EXISTING shareholders |
|22| PerpVault.sol:198 | `withdrawEth` owed | floor | favors REMAINING shareholders |
|23| PerpVault.sol:248 | `_syncTokYield` accumulator | floor | dust stays unattributed in `tokYieldEth` |
|24| PerpVault.sol:255 | `_settleTok` acc | floor | favors other stakers / undistributed remainder over this user |
|25| PerpVault.sol:261 | `_resetTokDebt` baseline | floor | baseline set low; partially offsets #24 for the same user later — net effect over a full cycle not derived here |
|26| PerpVault.sol:272 | `depositToken` shares | floor | same direction as #21 |
|27| PerpVault.sol:303 | `withdrawToken` owed | floor | same direction as #22 |
|28-31| PerpVault.sol:338,346,358,361 | view mirrors of #22/#27/#23/#24 | floor | informational, no state change |

### `unchecked` blocks — every one, cluster-wide

Grep-confirmed: **zero** `unchecked` blocks in PerpVault.sol,
PerpMarkSource.sol, PerpSwapLib.sol, or PerpStakerOracle.sol. All 11 sites
are in PerpEngine.sol:

| Line(s) | Function | Contents |
|---|---|---|
| 566-579 | `_writeObs()` | whole body: `dt = nowTs-lastObsTs`, ring-append timing — deliberate mod-2^32 timestamp-wrap safety (see comment 550-563) |
| 605 | `twapTick()` | `target = nowTs - twapWindow` |
| 623 | `twapTick()` | `nowTs - oldest.ts < MIN_TWAP` check |
| 638-641 | `twapTick()` | `cumNow`, `span` computation |
| 669 | `maxLeverage()` | `++i` loop counter |
| 962 | `forceCloseAllDead()` | `iters++` loop counter |
| 1303 | `_payOut()` | `payoutOwed[to] += amount` |
| 1394 | `_awardBadge()` | `fwd = gasleft() - 120_000` (guarded: reached only when `gasleft() > 300_000`) |
| 1405 | `_awardBadge()` | second `fwd = gasleft() - 120_000` (guarded: `gasleft() > 200_000`) |
| 1413 | `_awardBadge()` | `badgesOwed[to] += 1` |
| 1432 | `claimLiquidatorBadges()` | `++i` loop counter |

Adjacent but *not* `unchecked`: PerpEngine.sol:1330, `_absorbPlvLoss`'s `plv
= plv > rest ? plv - rest : 0` — underflow avoided via an explicit ternary
guard rather than an `unchecked` block. Noted here for completeness since
it's risk-adjacent arithmetic in the same neighborhood as the loss-absorption
`unchecked` sites.

### Other mechanical observations (comment-vs-code / pattern asymmetries)

- **`fundPlvToken`** (PerpEngine.sol:1456-1459) and **`fundTokenFromVault`**
  (1550-1553) both pull the generation token via the bare high-level call
  `IERC20(registry.currentToken()).transferFrom(msg.sender, address(this),
  amount);` with the returned `bool` **discarded** — no capture, no
  `require`. This differs from every other value-pull in the file:
  `_pullQuote`'s ERC20 branch (190-193) and `_safeTransfer` (1434-1436) both
  do `(bool ok, bytes memory ret) = token.call(...); if (!(ok &&
  (ret.length==0 || abi.decode(ret,(bool))))) revert BadParam();`. The
  matching *outbound* token path, `withdrawPlvTokenTo` (1556-1561), *does*
  use the checked `_safeTransfer`.
- **`PerpVault._approve`** (186-189) checks only the low-level call's
  success (`if (!ok) revert ZeroAmount();`) — it does not decode/require the
  returned `bool`, unlike `PerpVault._pull` (179-184) on the same file,
  which does.
- **`receive()`** (PerpEngine.sol:1702) is a bare `{}` — confirmed no
  accounting write of any kind.

---

## Function inventory

100 records total: 70 in `PerpEngine.sol` (47 external/public including
constructor and `receive()`, 23 internal/private that move value or mutate
storage), 19 in `PerpVault.sol` (14 + 5), 6 in `PerpMarkSource.sol` (all
external/public + constructor), 3 in `PerpSwapLib.sol` (library, all
external/private), 2 in `PerpStakerOracle.sol` (external + constructor).
Internal/private functions that are pure/view with no storage write and no
value movement (e.g. `_key`, `_sqrtP`, `_currentTick`, `_quoteAt`,
`_quoteEth`, `_quoteMark`, `_ethToToken`, `_guardOpen`, `_isDead`,
`_checkNotional`, `_underwater`, `_underwaterVal`, `_fundingDelta`,
`_killStats`, `_engineQuote`) are **excluded from this table per the brief's
own scoping rule** ("every internal function that moves value or mutates
storage") but are fully discussed above in Sections B-D since they are
central to the mark-price and liquidation logic. Full per-function detail —
reads, writes, edges with TRUSTED/CONFIGURABLE/ATTACKER-INFLUENCED tags, and
reachability — is in `/tmp/graph/perp.json`; this table is a condensed index
into it.

### PerpEngine.sol

| Line | Signature | Vis/Mut | Modifiers | Authority | Value movement |
|---|---|---|---|---|---|
|391|`constructor(...)`|public/nonpayable|Ownable(_owner)|deploy-time only|none|
|433|`totalEth()`|public/view|—|UNGATED|none|
|435|`freeEth()`|external/view|—|UNGATED|none|
|437|`totalTokenAssets()`|public/view|—|UNGATED|none|
|439|`freeToken()`|external/view|—|UNGATED|none|
|525|`poke()`|external/nonpayable|—|UNGATED|none|
|601|`twapTick()`|public/view|—|UNGATED|none|
|648|`markSqrtPriceX96()`|public/view|—|UNGATED|none|
|653|`activeEthDepth()`|public/view|—|UNGATED|none|
|663|`maxLeverage()`|public/view|—|UNGATED|none|
|723|`fundingDelta(id)`|external/view|—|UNGATED|none|
|744|`openLong(leverage,minTokenOut,liqHint,amount)`|public/payable|nonReentrant,notNested|UNGATED (state-gated via `_guardOpen`)|pulls quote in, real pool swap|
|781|`openShort(leverage,minEthOut,liqHint,amount)`|public/payable|nonReentrant,notNested|UNGATED (state-gated)|pulls quote in, real pool swap|
|816|`close(id,minOut)`|external/nonpayable|nonReentrant,notNested|caller must be `p.trader`|pool swap + trader payout|
|823|`liquidate(id)`|external/nonpayable|nonReentrant,notNested|UNGATED (must be underwater + under cap)|pool swap + keeper/trader payout|
|848|`sweepLiquidations(liquidator)`|external/nonpayable|—|hookAddr only|indirect, per hit|
|857|`selfSweep(liquidator)`|external/nonpayable|—|self-call only|indirect, per hit|
|934|`forceCloseDead(id)`|external/nonpayable|nonReentrant,notNested|UNGATED (token must be dead)|pool swap + keeper reward + trader residual|
|949|`forceCloseAllDead()`|external/nonpayable|nonReentrant,notNested|UNGATED (token must be dead)|up to 96x the above|
|975|`syncGeneration()`|external/nonpayable|nonReentrant,notNested|UNGATED (state-gated, `openCount==0`)|none direct; triggers registry burn-claim|
|1025|`isLiquidatable(id)`|external/view|—|UNGATED|none|
|1165|`unlockCallback(raw)`|external/nonpayable|—|poolManager only|pool swap settlement|
|1308|`claimPayout()`|external/nonpayable|nonReentrant|self-scoped|pushes caller's own owed quote|
|1421|`claimLiquidatorBadges(n)`|external/nonpayable|nonReentrant|self-scoped|NFT mints only, no value|
|1448|`fundPlv(amount)`|external/payable|onlyOwner,notNested|owner only|pulls quote in|
|1456|`fundPlvToken(amount)`|external/nonpayable|onlyOwner,notNested|owner only|pulls token in (unchecked return, see above)|
|1462|`fundInsurance(amount)`|external/payable|—|UNGATED|pulls quote in|
|1472|`creditPerpFee()`|external/payable|—|hookAddr only (in `_creditPerp`)|accepts msg.value into plv|
|1477|`creditPerpFeeToken()`|external/payable|—|hookAddr only|accepts msg.value into tokYieldEth|
|1498|`creditPerpFeeAsset(asset,amount)`|external/nonpayable|—|hookAddr only|pulls quote in|
|1531|`fundFromVault(amount)`|external/payable|onlyVault|vault only|pulls quote in|
|1539|`withdrawPlvTo(amount,to)`|external/nonpayable|onlyVault,notNested,nonReentrant|vault only|pushes quote to `to`|
|1545|`withdrawTokYieldTo(amount,to)`|external/nonpayable|onlyVault,notNested,nonReentrant|vault only|pushes quote to `to` from tokYieldEth|
|1550|`fundTokenFromVault(amount)`|external/nonpayable|onlyVault|vault only|pulls token in (unchecked return)|
|1556|`withdrawPlvTokenTo(amount,to)`|external/nonpayable|onlyVault,notNested,nonReentrant|vault only|pushes token to `to` (checked)|
|1563|`setFees(...)`|external/nonpayable|onlyOwner|owner only|none|
|1567|`setRisk(...)`|external/nonpayable|onlyOwner|owner only|none|
|1604|`setTiers(depths,levs)`|external/nonpayable|onlyOwner|owner only|none|
|1618|`setRouting(dividend,treasury,nftBeneficiary,markSource)`|external/nonpayable|onlyOwner|owner only, no zero-check|none|
|1628|`setGuards(twapWindow,maxLiqBps,maxFundingBps)`|external/nonpayable|onlyOwner|owner only|none|
|1640|`setVault(vault)`|external/nonpayable|onlyOwner|owner only, drain-guarded|none|
|1646|`setVaultSplit(yieldBps,insBps)`|external/nonpayable|onlyOwner|owner only|none|
|1652|`setVaultLimits(maxUtilBps,insuranceFloor)`|external/nonpayable|onlyOwner|owner only|none|
|1657|`setMinCollateral(min)`|external/nonpayable|onlyOwner|owner only|none|
|1673|`skimInsurance(amount,to)`|external/nonpayable|onlyOwner|owner only, risk-floor guarded|pushes quote to `to`|
|1691|`positionHealth(id)`|external/view|—|UNGATED|none|
|1702|`receive()`|external/payable|—|UNGATED|accepts ETH, no accounting write|
|181|`_pullQuote(from,amount)` (internal)|internal/nonpayable|—|internal helper|pulls quote from `from`|
|200|`_pushQuote(to,amount)` (internal)|internal/nonpayable|—|internal helper|pushes quote to `to`|
|564|`_writeObs()` (internal)|internal/nonpayable|—|internal helper|none (oracle state only)|
|685|`_pokeFunding()` (internal)|internal/nonpayable|—|internal helper|none|
|863|`_sweepAfterOpen(liquidator)` (internal)|internal/nonpayable|—|internal helper|indirect via selfSweep|
|873|`_doSweep(liquidator,inLocked)` (internal)|internal/nonpayable|—|internal helper|indirect via _tryLiquidate|
|912|`_tryLiquidate(id,liquidator)` (internal)|internal/nonpayable|—|internal helper|indirect via _settle|
|1053|`_settle(id,p,minOut,mode,keeper)` (internal)|internal/nonpayable|—|internal helper|pool swap + payouts|
|1149|`_run(r)` (internal)|internal/nonpayable|—|internal helper|dispatches pool swap|
|1156|`_swapExactIn(buy,amount)` (internal)|internal/nonpayable|—|internal helper|pool swap|
|1161|`_buyExactOut(tokenOut)` (internal)|internal/nonpayable|—|internal helper|pool swap|
|1173|`_swapBody(r)` (internal)|internal/nonpayable|—|internal helper|delegatecall to PerpSwapLib|
|1208|`_takeFee(sent,longSide)` (internal)|internal/nonpayable|—|internal helper|routes fee|
|1217|`_book(...)` (internal)|internal/nonpayable|—|caps at MAX_OPEN_POSITIONS|none direct|
|1230|`_removeOpen(id)` (internal)|internal/nonpayable|—|internal helper|none|
|1245|`_routeFee(amount,longSide)` (internal)|internal/nonpayable|—|internal helper|pushes to dividend/treasury|
|1274|`_sendEth(to,amount)` (internal)|internal/nonpayable|—|internal helper|wraps _pushQuote|
|1286|`_payOut(to,amount)` (internal)|internal/nonpayable|—|internal helper|push, credit-on-fail|
|1317|`_replenishPlv(shortfall)` (internal)|internal/nonpayable|—|internal helper|internal transfer insurance→plv|
|1326|`_absorbPlvLoss(loss)` (internal)|internal/nonpayable|—|internal helper|internal transfer insurance/plv down|
|1383|`_awardBadge(id,to,st)` (internal)|internal/nonpayable|—|internal helper|NFT mint, gas-gated|
|1434|`_safeTransfer(token,to,amount)` (private)|private/nonpayable|—|internal helper|checked ERC20 transfer|
|1508|`_creditPerp(ethSide)` (private)|private/payable|—|hookAddr only|credits plv or tokYieldEth|

### PerpVault.sol

| Line | Signature | Vis/Mut | Modifiers | Authority | Value movement |
|---|---|---|---|---|---|
|108|`constructor(_engine,_registry)`|public/nonpayable|—|deploy-time only|none|
|115|`assetsEth()`|public/view|—|UNGATED|none|
|120|`assetsTok()`|public/view|—|UNGATED|none|
|140|`deposit(amount)`|public/payable|nonReentrant|UNGATED|pulls in, forwards to engine|
|165|`depositEth()`|external/payable|—|UNGATED|wraps deposit|
|179|`_pull(token,from,amount)` (private)|private/nonpayable|—|internal helper|checked transferFrom|
|186|`_approve(token,spender,amount)` (private)|private/nonpayable|—|internal helper|call-success-only checked approve|
|193|`withdrawEth(shares)`|external/nonpayable|nonReentrant|self-scoped|engine.withdrawPlvTo|
|217|`claimPendingEth()`|external/nonpayable|nonReentrant|self-scoped|engine.withdrawPlvTo|
|242|`_syncTokYield()` (internal)|internal/nonpayable|—|internal helper|none|
|252|`_settleTok(user)` (internal)|internal/nonpayable|—|internal helper|none|
|260|`_resetTokDebt(user)` (internal)|internal/nonpayable|—|internal helper|none|
|268|`depositToken(amount)`|external/nonpayable|nonReentrant|UNGATED|pulls in, forwards to engine|
|286|`claimTokYield()`|external/nonpayable|nonReentrant|self-scoped|engine.withdrawTokYieldTo|
|297|`withdrawToken(shares)`|external/nonpayable|nonReentrant|self-scoped|engine.withdrawPlvTokenTo|
|320|`claimPendingToken()`|external/nonpayable|nonReentrant|self-scoped|engine.withdrawPlvTokenTo|
|336|`ethPosition(user)`|external/view|—|UNGATED|none|
|344|`tokenPosition(user)`|external/view|—|UNGATED|none|
|353|`pendingTokYield(user)`|external/view|—|UNGATED|none|

### PerpMarkSource.sol

| Line | Signature | Vis/Mut | Modifiers | Authority | Value movement |
|---|---|---|---|---|---|
|93|`constructor(_poolManager,_owner)`|public/nonpayable|Ownable(_owner)|deploy-time only|none|
|100|`setPrimary(key)`|external/nonpayable|onlyOwner|owner only, no existence check|none|
|111|`addPool(key)`|external/nonpayable|onlyOwner|owner only, pair-matched, capped at 4|none|
|132|`removePool(key)`|external/nonpayable|onlyOwner|owner only|none|
|146|`poolCount()`|external/view|—|UNGATED|none|
|158|`weightedTick()`|external/view|—|UNGATED|none|

### PerpSwapLib.sol (linked library)

| Line | Signature | Vis/Mut | Modifiers | Authority | Value movement |
|---|---|---|---|---|---|
|52|`swapLeg(poolManager,key,r,quoteIsCurrency0,hookData)`|external/nonpayable|—|**no caller check** (see JSON observation on linked-library exposure)|executes pool swap, settle/take|
|101|`_settle(poolManager,c,amount)` (private)|private/nonpayable|—|internal-to-library|pays poolManager, checked ERC20 branch|
|128|`migrateInventory(registry,oldToken,fromGen)`|external/nonpayable|—|**no caller check**|best-effort registry burn-claim|

### PerpStakerOracle.sol

| Line | Signature | Vis/Mut | Modifiers | Authority | Value movement |
|---|---|---|---|---|---|
|24|`constructor(_perpVault)`|public/nonpayable|—|deploy-time only|none|
|29|`isInstant(who)`|external/view|—|UNGATED|none|

---

## Things I could not determine from this cluster alone

- Whether `_currentTick()`'s truncating `int24(v)` cast on an external
  mark-source's return (PerpEngine.sol:516) can actually receive a value
  outside plausible tick range in practice depends on `PerpMarkSource`'s
  behavior (bounded, since it derives ticks from `poolManager.getSlot0`) —
  but `markSource` is a `CONFIGURABLE` address; nothing in this cluster
  proves only `PerpMarkSource`-shaped contracts can ever be wired there.
- `IPerpHook(hookAddr).collection()` and `IPerpHook(hookAddr).isDead(...)`
  (both used repeatedly) are defined on `CauldronHook.sol`, outside my
  assigned cluster — I read only the two call-site confirmations needed for
  reachability (the `_afterSwap` function and its `sweepLiquidations` call)
  and did not extract `CauldronHook.sol` itself.
- Whether `FullMath.mulDiv`'s 512-bit branch (denominator ≥ 2^256 case,
  lines 40-107 of the library) preserves the same floor semantics under
  every input was confirmed by reading the non-overflow branch and the
  overall function contract, not by re-deriving the assembly line by line.