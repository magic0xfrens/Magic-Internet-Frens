# AREA C — Volume accounting, mint credit, death detection

Files read in full: `contracts/solidity/cauldron/QuoteOracle.sol` (344 lines), `contracts/solidity/cauldron/IDeathChecker.sol` (31 lines).
Files read in the relevant regions (volume / death / oracle / credit): `contracts/solidity/CauldronHook.sol` lines 1-270, 340-420, 490-520, 610-970, 1440-1800, 1990-2270 (of 2364 total; rest skimmed for cross-references).
Also read: `contracts/solidity/cauldron/RedemptionExt.sol` lines 1-70, 240-530; `contracts/solidity/CauldronRegistry.sol` lines 735-960; `contracts/solidity/cauldron/PerpEngine.sol` (grep + lines 440-520, 975-1030, 1180-1220).
`contracts/solidity/cauldron/PoolOps.sol` was grepped for volume/death/linkVolume — no matches beyond one unrelated comment (`PoolOps.sol:364`, "visible volume" in a migration-buy comment). No volume/death logic lives in PoolOps.

---

## C1 — Volume accrual from swaps

**Purpose.** Track a rolling 24-hour trading-volume figure per pool, denominated so every pool (any quote asset) counts on the same scale, feeding death detection and mint credit.

**Entrypoints (+ actual authority).** No external entrypoint; volume is recorded internally from `_afterSwap` (`CauldronHook.sol:742`), called by the V4 `PoolManager` via the `BaseHook.afterSwap` callback for every swap on a tracked pool. No caller-supplied authority — gated only by `trackedPools[id]` (`CauldronHook.sol:755,772`), set true for any pool the registry's `afterInitialize` call adopts (`CauldronHook.sol:610-616`).

**Preconditions.**
- `trackedPools[id] == true` (`CauldronHook.sol:755`).
- Not the hook's own self-buy/relaunch-close swap (`_inSelfBuy || _inRelaunchClose` early-return, `CauldronHook.sol:751`).

**Behavior (step-by-step, units + denomination).**
1. Determine which side of the pool is quote: `q0 = quoteIsCurrency0[id]` (recorded once at adoption, `CauldronHook.sol:635,758`).
2. Read the swap's quote-side delta: `quoteAmt = q0 ? delta.amount0() : delta.amount1()` (`CauldronHook.sol:775`), absolute-valued to `absVolume` (raw quote-token units, `CauldronHook.sol:776-778`).
3. Convert to USD **before** any accumulation: `absVolume = _toUsd(quoteAsset, absVolume)` (`CauldronHook.sol:799`). `_toUsd` (`CauldronHook.sol:705-714`):
   - If `quoteOracle == address(0)`: returns `raw` unchanged — i.e., volume stays in raw quote-token units (`CauldronHook.sol:706-707`).
   - Else: low-level `call` (not `staticcall`, so it can write the oracle's cache — see C3) to `IQuoteOracle.cachedUsdPerRawUnit(quote)`; on call failure or short return, returns `0`; else `f == 0 ? 0 : (raw * f) / 1e18` (`CauldronHook.sol:708-713`). `f` is USD-per-raw-unit at 1e18 scale (see C3), so the result is USD at 1e18 scale.
4. `0` is the sentinel for "cannot judge," not "zero volume" (comment `CauldronHook.sol:675-685`, "audit V-1"). Gate: only if `absVolume > 0` does the hook call `_recordVolume(id, absVolume)` and bump `cumulativeVolume` (`CauldronHook.sol:800-803`). On `0`, nothing is written — no bucket, no `_lastUpdateTs` touch (deliberate: the existing 24h window becomes the outage grace period, `CauldronHook.sol:792-798`).
5. `_recordVolume` (`CauldronHook.sol:1455-1483`) — the bucketing scheme: 24 hourly buckets per pool, `mapping(PoolId => uint128[24]) private _volumeBuckets` (`CauldronHook.sol:255`). Bucket index = `_getCurrentBucket() = (block.timestamp / SECONDS_PER_HOUR) % HOURS_PER_DAY` (`CauldronHook.sol:1561-1562`), i.e. **wall-clock seconds**, `HOURS_PER_DAY = 24`, `SECONDS_PER_HOUR = 1 hours` (`CauldronHook.sol:177-179`). This replaced a block-count window (`BLOCKS_PER_HOUR=300`/`BLOCKS_PER_DAY=7200`) that was wrong on L2s where `block.number` reports the parent chain's block (documented at `CauldronHook.sol:160-181`, "audit Z-05").
   - If `block.timestamp > lastTs + SECONDS_PER_DAY` (a full day of inactivity): all 24 buckets are zeroed (`CauldronHook.sol:1460-1463`).
   - Else if the current bucket differs from the last-written bucket: every bucket strictly between them (mod 24, capped at 24 steps) is zeroed (`CauldronHook.sol:1464-1472`) — this is how the sliding window evicts stale hours.
   - The current bucket then gets a **saturating add**: `bucketTotal > type(uint128).max ? type(uint128).max : uint128(bucketTotal)` (`CauldronHook.sol:1475-1478`) — cannot revert the swap.
   - `_lastBucketIndex[id]` and `_lastUpdateTs[id]` are updated (`CauldronHook.sol:1479-1480`).
6. Emits `VolumeRecorded(PoolId indexed poolId, uint256 amount, uint256 bucket)` (`CauldronHook.sol:504,1482`).

**Postconditions & invariants.**
- `getVolume24h(id)` (`CauldronHook.sol:1485-1493`) sums all 24 buckets **unless** `block.timestamp > _lastUpdateTs[id] + SECONDS_PER_DAY`, in which case it returns `0` outright (a hard cliff for total inactivity, independent of per-bucket eviction).
- Buckets pack two `uint128` per storage slot (`CauldronHook.sol:248-255`, "audit G-10"), so the 24-bucket sum costs 12 SLOADs.

**Edge cases.**
- A monster swap saturates a bucket at `type(uint128).max` rather than reverting/wrapping (`CauldronHook.sol:1475-1478`).
- An oracle outage (returns 0) freezes the window's clock (`_lastUpdateTs` untouched) rather than writing zero volume — see C3/(d).
- `deathChecker` and `isDead` treat a bucket-based `getVolume24h` as the ground truth regardless of `_toUsd`'s presence — see C4.

**Events.** `VolumeRecorded(PoolId indexed poolId, uint256 amount, uint256 bucket)` — `CauldronHook.sol:504`.

**DENOMINATION: breaks-on-transition (comment-level) / quote-agnostic (arithmetic-level)** — the state variable doc still says `"Volume below this in 24h (in currency0 terms) = dead"` (`CauldronHook.sol:187`), and `IDeathChecker.isDead`'s NatSpec says `"the hook's current 24h volume for the pool (currency0 terms)"` (`IDeathChecker.sol:23`). ACTUAL: volume is measured on the **quote** side (`CauldronHook.sol:773-775`, "Volume is measured in QUOTE terms... may be currency1"), and is USD-1e18-scaled once an oracle is wired, or raw quote-token units otherwise. **DELTA**: both NatSpec comments are stale relative to the code (flagged, not fixed).

---

## C2 — Mint credit from NFTs

**Purpose.** Convert accrued swap volume into spendable "crystal credit," which buys lottery tickets ("crystals") on a rising-price curve; a won ticket mints an NFT in the live collection.

**Entrypoints (+ actual authority).**
- `commitCrystals(address player, uint256 maxCount, uint256 playWei)` (`CauldronHook.sol:2116-2131`) — external, gated `isOpener[msg.sender]` (`CauldronHook.sol:2121`, reverts `NotOpener`); callable only by a registry/owner-set opener (typically the gacha router).
- `nativeGachaStep` (self-call only, fired from `_afterSwap` at `CauldronHook.sol:926-932`, gas-bounded) — for swaps with no router `hookData`.
- Both funnel into internal `_commitCrystals(address player, uint256 maxCount, uint256 playWei)` (`CauldronHook.sol:2136-2185`).

**Preconditions.** `collection != address(0)` (else returns 0, no revert — `CauldronHook.sol:2141`). Credit accrual itself (writing `nftCredit`) requires, from `_afterSwap`: `collection != address(0) && absVolume > 0 && key.currency1 == _liveKey.currency1` (`CauldronHook.sol:820-822`) — i.e. only swaps on the **live** generation's pool credit, guarding against farming a retired-but-still-tracked pool (`CauldronHook.sol:813-819`, "audit Z-09").

**Behavior (step-by-step, units + denomination).**
- **What earns credit**: a swap's USD-converted (or raw, if no oracle) volume, weighted by direction: `weighted = (absVolume * (isBuy ? buyWeightBps : sellWeightBps)) / BPS` (`CauldronHook.sol:852`), with `buyWeightBps = 15_000` (1.5x) and `sellWeightBps = 5_000` (0.5x) by default (`CauldronHook.sol:402-403`), capped at `MAX_WEIGHT_BPS = 30_000` (`CauldronHook.sol:404`). `isBuy = params.zeroForOne == q0` (`CauldronHook.sol:851`).
- Attribution: a trusted router tags the buyer via `hookData` (`abi.decode(hookData, (address))` when `hookData.length >= 32`, `CauldronHook.sol:837-839`); otherwise, if `creditUntaggedSwaps` (default `true`, `CauldronHook.sol:409`) it falls back to `tx.origin` (`CauldronHook.sol:840`). The registry's own relaunch buy is excluded (`player == registry` → `address(0)`, `CauldronHook.sol:845`).
- Credit is written with saturating adds to three places, per epoch: `nftCredit[creditEpoch][player]` (`CauldronHook.sol:349,856-858`), `lifetimeVolumeOf[player]` (`CauldronHook.sol:396,859-861`), and global `totalLifetimeVolume` (`CauldronHook.sol:397,862-864`). `creditEpoch` increments on every `setCollection` call (`CauldronHook.sol:1886`), resetting the credit namespace for a new brew.
- **What it is redeemable for**: crystals on a rising-difficulty curve, `nftPriceAt(k) = volumePerNFT + k * nftPriceStep` (default `0.02 ether` base, `0.00002 ether` step — `CauldronHook.sol:356-357,2019`), indexed from `mintBaseline` (the collection's `totalMinted` at wiring time, `CauldronHook.sol:359-365`), optionally overridden by a pluggable `curvePolicy` (`CauldronHook.sol:2011-2020`). `_commitCrystals` spends credit greedily up the curve (`CauldronHook.sol:2151-2162`), enqueues a `Batch` (`CauldronHook.sol:2176-2183`) with a win probability `oddsForPlay(playWei)` (`CauldronHook.sol:2060-2071`, linear up to `maxOddsBps` at `oddsFullVolumeWei`). Resolution (`resolveTickets`/`_resolveTickets`, `CauldronHook.sol:2196-2229`) later mints via the collection on a win, seeded by the commit block's hash.
- **Units note**: `playWei` must arrive in whatever units `oddsFullVolumeWei` is denominated in (raw ETH-wei by default, or USD-1e18 once an oracle is wired) — the router/opener is responsible for that conversion on the router path; the native in-swap path feeds `weighted` (already USD-converted volume) directly (`CauldronHook.sol:2122-2129`).

**Postconditions & invariants.** `_commitCrystals` never mints more crystals than remaining collection room (`room = max - minted - reserved`, `CauldronHook.sol:2144-2149`), never reverts (returns `0` when sold out, `CauldronHook.sol:2141,2148,2163`).

**Edge cases.** `wiring an oracle re-denominates `nftCredit`'s unit to USD` — `setDeathThreshold` forces the caller to simultaneously restate `volumePerNFT`/`nftPriceStep`/`oddsFullVolumeWei` in the new unit (`CauldronHook.sol:1682-1697`, "audit U-1"); the contract cannot itself detect a stale mismatch since both sides are just 1e18 integers (`CauldronHook.sol:1670-1672`).

**Events.** `CreditAccrued(address indexed player, uint256 amount)` (`CauldronHook.sol:505,866`); `CrystalsCommitted(address indexed player, uint256 count, uint256 oddsBps)` (`CauldronHook.sol:513,2184`).

**DENOMINATION: breaks-on-transition — evidence `CauldronHook.sol:1650-1672`** ("Wiring an oracle re-denominates EVERY volume-derived figure... Left in ether terms against USD-scaled credit, a $3,000 ETH inflates every trader's mint credit ~3000x"). The contract forces a coupled restatement rather than detecting/preventing the mismatch automatically.

---

## C3 — USD denomination (`QuoteOracle`)

**Purpose.** Turn a raw quote-asset volume figure into USD-at-1e18, so pools in different quote assets/decimals are comparable (`QuoteOracle.sol:16-29`).

**Entrypoints (+ actual authority).**
- `setFeed(address quote, address aggregator, uint32 heartbeat, uint8 quoteDecimals)` — `onlyOwner` (`QuoteOracle.sol:131-143`).
- `setPegged(address quote, uint8 dec)` — `onlyOwner`, prices at exactly $1, no aggregator consulted (`QuoteOracle.sol:153-160`).
- `setBounds(address quote, uint128 minUsd, uint128 maxUsd)` — `onlyOwner` (`QuoteOracle.sol:175-180`).
- `setSequencer(address feed, uint32 grace)` — `onlyOwner` (`QuoteOracle.sol:182-186`).
- `usdPerRawUnit(address quote) external view returns (uint256 factor)` — public read, no auth (`QuoteOracle.sol:202-278`).
- `cachedUsdPerRawUnit(address quote) external returns (uint256)` — public, non-view (writes cache) (`QuoteOracle.sol:305-312`); this is the entrypoint `CauldronHook._toUsd` calls (`CauldronHook.sol:708-710`).
- `priceable(address quote) external view returns (bool)` (`QuoteOracle.sol:316-318`).
- `owner` is set in the constructor (`QuoteOracle.sol:110-112`) and is described in comments as "the timelock" (`QuoteOracle.sol:123`) — not independently verified in this section (out of scope: no timelock contract read).

**Preconditions/Behavior — full pricing path.**
1. **Pegged** (`Feed.pegged == true`): `return 1e18 * 1e18 / (10 ** f.quoteDecimals)` (`QuoteOracle.sol:207`) — $1 per whole token converted to per-raw-unit at the token's own decimals; no aggregator call, cannot revert/go stale/be manipulated (`QuoteOracle.sol:70-88,204-207`).
2. **No feed configured** (`aggregator == address(0)`): `return 0` (`QuoteOracle.sol:208`).
3. **Sequencer down / not yet past grace**: `if (!_sequencerOk()) return 0` (`QuoteOracle.sol:209`). `_sequencerOk` (`QuoteOracle.sol:320-342`): unset sequencer feed ⇒ `true` (L1, not applicable, `QuoteOracle.sol:322`); else reads `latestRoundData()`, `up != 0` ⇒ `false` (down, `QuoteOracle.sol:332`); `startedAt` in the future or zero ⇒ `false` (`QuoteOracle.sol:335`); else `block.timestamp - startedAt > gracePeriod` (default `3600`, `QuoteOracle.sol:104,338`); any revert from the feed ⇒ `false` (`QuoteOracle.sol:339-341`).
4. **Feed read**: `try f.aggregator.latestRoundData()`; **on revert, `return 0`** (`QuoteOracle.sol:231-238`) — this is a `try/catch` at the `usdPerRawUnit` level, so a reverting aggregator does NOT propagate up to `_toUsd`'s `call`; `_toUsd` only sees ordinary call failure if `cachedUsdPerRawUnit` itself reverts, which it does not for this case (it returns 0 cleanly). (Historical note in the code, `QuoteOracle.sol:211-228`, describes a PRIOR bug where a revert bypassed the cache; current code catches it here.)
5. `answer <= 0` ⇒ `return 0` (`QuoteOracle.sol:239`).
6. Staleness: `updatedAt == 0 || updatedAt > block.timestamp` ⇒ `return 0` (future timestamp guard, `QuoteOracle.sol:242-245`); `block.timestamp - updatedAt > f.heartbeat` ⇒ `return 0` (`QuoteOracle.sol:246`).
7. Feed decimals read via `try/catch`; revert ⇒ `return 0` (`QuoteOracle.sol:249-253`).
8. **Decimal normalization to 1e18** (`QuoteOracle.sol:256-258`):
   ```
   perWhole = feedDec <= 18
       ? uint256(answer) * (10 ** (18 - feedDec))
       : uint256(answer) / (10 ** (feedDec - 18));
   ```
9. **Band guard**: `minUsd != 0 && perWhole < minUsd` ⇒ `0`; `maxUsd != 0 && perWhole > maxUsd` ⇒ `0` (`QuoteOracle.sol:267-268`). Bounds are whole-USD at 1e18 (`QuoteOracle.sol:89-93`).
10. **Convert to per-raw-unit**: `factor = (perWhole * 1e18) / (10 ** f.quoteDecimals)` (`QuoteOracle.sol:277`) — 1e18 is applied **before** dividing by decimals, per an explicit comment describing a prior bug where dividing first floored to zero (`QuoteOracle.sol:270-276`).

**6-decimal example (arithmetic check).** Chainlink USDC/USD feed, `feedDec = 8`, answer `= 1_00000000` ($1.00): `perWhole = 1_00000000 * 10**(18-8) = 1e18` (i.e., $1 at 1e18 scale). `quoteDecimals = 6`: `factor = 1e18 * 1e18 / 1e6 = 1e30`. Then in `_toUsd`: for `raw = 1_000000` (1 USDC, 6 decimals): `usdVolume = raw * factor / 1e18 = 1e6 * 1e30 / 1e18 = 1e18` = $1 at 1e18 scale. **Decimals handled correctly** (`QuoteOracle.sol:256-277`, `CauldronHook.sol:713`).

**Caching.** `cachedUsdPerRawUnit` (`QuoteOracle.sol:305-312`): TTL `15 minutes` (`QuoteOracle.sol:284`); if within TTL and `c.factor != 0`, return cached; else refresh via `this.usdPerRawUnit(quote)` (external self-call — so an internal revert inside `usdPerRawUnit` would propagate through `this.` and revert `cachedUsdPerRawUnit` too, but the code above shows every failure mode inside `usdPerRawUnit` returns `0` rather than reverting, so this call effectively never reverts under a misbehaving feed — only under a codeless/self-destructed aggregator per the comment at `QuoteOracle.sol:211-227`, which is itself now caught by the `try/catch` at step 4). On refresh: `c.at` is updated unconditionally; `c.factor` is updated **only if `fresh > 0`** (`QuoteOracle.sol:309-310`) — a refresh that comes back unusable **keeps the last good factor** rather than collapsing to 0 (`QuoteOracle.sol:301-303`).

**Behavior when unset/reverting.** No feed ⇒ `0` (`QuoteOracle.sol:208`), which `CauldronHook._toUsd` treats as "cannot judge" (`CauldronHook.sol:711-713`, `raw*0` branch short-circuited to `0`) — see C1 step 4 and (d) below.

**Events.** `FeedSet(address indexed quote, address aggregator, uint32 heartbeat, uint8 quoteDecimals)` (`QuoteOracle.sol:106,142,159`); `SequencerSet(address feed, uint32 gracePeriod)` (`QuoteOracle.sol:107,185`); `BoundsSet(address indexed quote, uint128 minUsd, uint128 maxUsd)` (`QuoteOracle.sol:108,179`).

**DENOMINATION: quote-agnostic — evidence `QuoteOracle.sol:16-29,256-277`** (explicit design goal, decimals handled generically for any `quoteDecimals`).

---

## C4 — Death detection

**Purpose.** Declare a generation's token "dead" (unlocking permissionless `relaunch()`) when its 24h volume falls under a threshold.

**Entrypoints (+ actual authority).** `isDead(PoolId id) external view returns (bool)` (`CauldronHook.sol:1539-1559`) — unauthenticated view, called by `CauldronRegistry.relaunch()` as `hook.isDead(oldPoolId)` where `oldPoolId = generationPoolId[oldGen]` (`CauldronRegistry.sol:757,760`), and by `PerpEngine._isDead()` as `IPerpHook(hookAddr).isDead(_key().toId())` (`PerpEngine.sol:1216`, `_key()` at `PerpEngine.sol:449-455`, built from the engine's own `quote` + `registry.currentToken()` — **not** the same id source as the registry's relaunch check; see "Death neutrality (b)" below).

**Preconditions.** None to call; returns `false` immediately if `!trackedPools[id]` (`CauldronHook.sol:1540`).

**Behavior — the exact comparison and its units.**
1. `vol = getVolume24h(id)` (own pool's 24h sum, C1 units: USD-1e18 if oracle wired, else raw quote units) — `CauldronHook.sol:1545`.
2. `vol += getVolume24h(sib)` for every `sib` in `_volumeSiblings[id]` (`CauldronHook.sol:1546-1547`) — see C5.
3. If a `deathChecker` module is set, delegate: `try checker.isDead(id, vol, deathThreshold) returns (bool dead) { return dead } catch { return vol < deathThreshold }` (`CauldronHook.sol:1548-1556`) — a reverting/misbehaving module falls back to the built-in rule rather than bricking the check.
4. Built-in rule (no module, or module unset): `return vol < deathThreshold` (`CauldronHook.sol:1558`), `deathThreshold` a plain `uint256` (`CauldronHook.sol:188`), owner-set via `setDeathThreshold` (`CauldronHook.sol:1682-1697`).

**24h decay window — exact mechanism.** Not a decay curve: it is the 24-hourly-bucket ring buffer of C1, summed by `getVolume24h` (`CauldronHook.sol:1485-1493`), with a hard cliff to `0` if `block.timestamp > _lastUpdateTs[id] + SECONDS_PER_DAY` (`CauldronHook.sol:1486`). There is no separate "grace period" state — the 24h window itself doubles as the outage grace period, because an oracle-unpriceable swap does not advance `_lastUpdateTs` (`CauldronHook.sol:796-798`).

**Postconditions & invariants.** `isDead` never reverts on a misbehaving `deathChecker` (try/catch fallback, `CauldronHook.sol:1552-1556`).

**Edge cases.**
- A brand-new pool reads `vol = 0 < deathThreshold` ⇒ `true` (dead) immediately; the registry gates this separately with a `minLifetime` grace period unrelated to the hook (`CauldronRegistry.sol:762-764`, "grace period: a brand-new pool reads dead at 0 volume").
- `PerpEngine._isDead()` computes its own `_key().toId()` (`PerpEngine.sol:449-455`) from `quote` (adopted via `syncGeneration`, `PerpEngine.sol:975-1027`) rather than reading `generationPoolId[gen]`; after a full quote rotation this can differ from the primary id `linkVolume` was called against (see C5 and "Death neutrality (b)").

**Events.** None emitted by `isDead` itself. `DeathCheckerSet(address)` on module change (`CauldronHook.sol:1772`, declaration not shown in the read range but referenced at the emit site).

**DENOMINATION: quote-agnostic (by construction, once linked) — evidence `CauldronHook.sol:1541-1547`**, contingent on C1's USD conversion and C5's linkage being correct together (see critical question below).

---

## C5 — `linkVolume`

**Purpose.** Register a secondary pool's volume as counting toward the same generation as a primary pool, so a generation whose liquidity is split across two quote assets (via a treasury rotation) is not misjudged dead just because the primary pool's own volume dropped.

**Entrypoints (+ actual authority).** `linkVolume(PoolId primary, PoolId secondary) external` (`CauldronHook.sol:1516-1534`) — gated `if (msg.sender != registry) revert OnlyRegistry()` (`CauldronHook.sol:1517`). Called from two sites in `RedemptionExt.sol` (delegatecalled into the registry, so `msg.sender` at the hook is the registry contract):
- `rotateSliceFrom` (`RedemptionExt.sol:266-418`, the real, **permissionless-within-governance-approval** slice-rotation API — not `onlyOwner`; see the note at `RedemptionExt.sol:281-286`), which calls `IHookVolume(address(hook)).linkVolume(generationPoolId[gen], poolId)` after opening/topping-up the destination pair (`RedemptionExt.sol:372`).
- `completeRotation(address quote, uint256 quoteAmount, uint256 tokenAmount)` (`RedemptionExt.sol:477-503`), gated `onlyOwner` (`RedemptionExt.sol:479`), same call pattern (`RedemptionExt.sol:500`).
Both always pass `primary = generationPoolId[gen]` — the **original, fixed** primary pool id recorded at relaunch/seed time, never the currently-live quote's pool id.

**Preconditions.**
- `msg.sender == registry` (`CauldronHook.sol:1517`).
- No perps open: `perpEngine != address(0) && IPerpOpenCount(perpEngine).openCount() > 0` ⇒ revert `PerpsOpen` (`CauldronHook.sol:1518-1520`, "audit P-1" — perps mark against the primary only, so a second pool joining while positions are open would let the mark diverge from where the price is actually made, `CauldronHook.sol:1498-1515`).
- `sib.length < MAX_SIBLINGS` (`9`, `CauldronHook.sol:733,1521-1527`), else revert `OnlyRegistry` (reused error selector, not semantically "not registry" — a `BadParam`-shaped condition reusing the auth error to save bytecode).

**Behavior.**
- Idempotent: if `secondary` is already in `_volumeSiblings[primary]`, the call is a silent no-op (`CauldronHook.sol:1528-1531`).
- Else `sib.push(secondary)` and `emit VolumeLinked(primary, secondary)` (`CauldronHook.sol:1532-1533,1536`).
- The link is **one-directional**: `_volumeSiblings[primary]` grows; nothing is ever written to `_volumeSiblings[secondary]`. `isDead(secondary)` (queried directly, e.g. by `PerpEngine._key().toId()` post-rotation) would NOT see `primary` or other siblings — only `isDead(primary)` aggregates the whole set (`CauldronHook.sol:1546-1547`).

**Which pools count toward one generation:** exactly `{primary} ∪ _volumeSiblings[primary]`, where `primary` is fixed at `generationPoolId[gen]` for that generation's whole life (written once, `CauldronRegistry.sol:1692`, region read; not reassigned by rotation).

**Who may link:** the registry only (`CauldronHook.sol:1517`), reached from `rotateSliceFrom` (permissionless within an approved governance envelope) and `completeRotation` (registry-`onlyOwner`).

**Postconditions & invariants.** Bounded to `MAX_SIBLINGS = 9` so `isDead`'s loop (`CauldronHook.sol:1547`) cannot be griefed into an unbounded gas cost that would make a generation permanently un-relaunchable (`CauldronHook.sol:1522-1527`).

**Edge cases.** Re-linking the same pair is a no-op, not a revert (`CauldronHook.sol:1530`) — safe against a rotation calling `linkVolume` on every slice for the same destination pair (`rotateSliceFrom` does call it once per slice, `RedemptionExt.sol:372`, each subsequent call for the same `poolId` is absorbed by the idempotency check).

**Events.** `VolumeLinked(PoolId indexed primary, PoolId indexed secondary)` — `CauldronHook.sol:1536`.

**DENOMINATION: quote-agnostic for the registry's own death check; breaks-on-transition for `PerpEngine`'s — evidence `CauldronRegistry.sol:757,760` vs. `PerpEngine.sol:449-455,1216`** (registry always queries `isDead` by the fixed `generationPoolId[gen]`, which is always the `linkVolume` primary and therefore always aggregates correctly; `PerpEngine` queries `isDead` by a freshly-derived key from its own `quote` variable, which after `syncGeneration` adopts a rotated quote — `PerpEngine.sol:975-1027` — points at a pool id that was registered only as a *secondary*, so its own sibling list is empty).

---

## Open deltas

1. **Stale/misleading NatSpec on volume units.** `CauldronHook.sol:187` ("in currency0 terms") and `IDeathChecker.sol:23` ("currency0 terms") both say currency0; the actual measurement is quote-side (may be currency1) and, once an oracle is wired, USD-1e18 rather than any token's native terms. Not fixed here per instructions — flagged only.
2. **`PerpEngine._isDead()` vs. registry `relaunch()`'s `isDead()` can read different aggregates after a full quote rotation.** The registry always calls `isDead(generationPoolId[gen])` (the fixed, `linkVolume`-primary id, `CauldronRegistry.sol:757,760`) and therefore always sums every linked sibling. `PerpEngine._isDead()` calls `isDead(_key().toId())` where `_key()` derives from the engine's own `quote` (`PerpEngine.sol:449-455`), which `syncGeneration` re-points to the rotated-into quote once a rotation fully completes (`PerpEngine.sol:975-1027`, `RedemptionExt.sol:411-415`). Because `linkVolume`'s linkage is one-directional and keyed only under the original primary (`CauldronHook.sol:1521,1528-1533`), `isDead(newQuotePoolId)` after a full rotation has an empty sibling list and reads only that pool's own 24h volume — it does not include whatever residual volume the drained old primary still records. This is an architectural asymmetry between the two `isDead` call sites, not verified here to be exploitable (the old primary is expected to be near-fully drained by the time `generationQuote` flips), and is reported as a delta rather than judged.
3. **`OnlyRegistry` reused as the sibling-cap revert** (`CauldronHook.sol:1527`) — the revert selector fired when `MAX_SIBLINGS` is hit is `OnlyRegistry`, which is semantically about caller authority, not about the cap. Cosmetic/diagnostic-clarity delta only.
4. **`completeRotation`'s `onlyOwner`** (`RedemptionExt.sol:479`) was not traced to confirm which "owner" (timelock vs. EOA) in this pass — out of scope (no `Ownable`/timelock wiring file was read). Not verified either way; not claimed.

---

## Death neutrality answers

**(a) Converted to USD before accumulating, or raw-then-later?** **Before.** `CauldronHook.sol:799`: `absVolume = _toUsd(Currency.unwrap(q0 ? key.currency0 : key.currency1), absVolume);` runs immediately after the raw delta is read (`CauldronHook.sol:775-778`) and strictly before `_recordVolume(id, absVolume)` is called (`CauldronHook.sol:800-801`). The bucket array (`_volumeBuckets`) only ever holds already-converted figures — raw quote units when no oracle is wired, USD-1e18 when one is (`CauldronHook.sol:705-714`). There is no later, separate conversion step; `getVolume24h` (`CauldronHook.sol:1485-1493`) sums whatever was written.

**(b) Partial rotation, two pools trading at once — does `linkVolume` make both count? Is either double-counted?** Both count, and no double-count, **as queried through the fixed primary**. `isDead(primary)` sums `getVolume24h(primary) + Σ getVolume24h(sibling)` for `sibling ∈ _volumeSiblings[primary]` (`CauldronHook.sol:1545-1547`); `rotateSliceFrom` calls `linkVolume(generationPoolId[gen], newPoolId)` after every slice (`RedemptionExt.sol:372`), so the new pool is a registered sibling the moment it opens, and stays one whether the rotation is partial or complete (`generationQuote` itself is only flipped at full completion, `RedemptionExt.sol:389-415`, but the sibling link is independent of that flip and happens per-slice). Each pool's bucket is written only by swaps that actually occur on that pool's own `afterSwap` callback (`CauldronHook.sol:742,772`), so there is no mechanism by which one swap's volume lands in two pools' buckets — no double-counting. The asymmetry described in Delta 2 above is a **different-query-id** problem (whether a given caller asks by the linked primary or by a fresh secondary id), not a double-count or a fake-death in the primary-keyed path the registry actually uses to gate `relaunch()`.

**(c) 6-decimal quote — decimals handled correctly?** Yes. Worked example above (C3): `feedDec=8` answer `1e8` ($1.00) → `perWhole = 1e18` (`QuoteOracle.sol:256-258`); `quoteDecimals=6` → `factor = perWhole * 1e18 / 1e6 = 1e30` (`QuoteOracle.sol:277`); for `raw = 1_000000` (1 whole 6-decimal token): `_toUsd` computes `raw * factor / 1e18 = 1e6 * 1e30 / 1e18 = 1e18` = exactly $1 at 1e18 scale (`CauldronHook.sol:713`). The code explicitly documents and avoids the floor-to-zero bug of dividing by decimals before applying the 1e18 scale (`QuoteOracle.sol:270-276`).

**(d) No feed for the new quote — fail open (never dead) or fail closed (instantly dead)?** **Neither absolutely — fails OPEN for up to the 24h window, then fails CLOSED.** `usdPerRawUnit` returns `0` when no aggregator is configured (`QuoteOracle.sol:208`); `cachedUsdPerRawUnit` then returns the cache's last-good factor if one exists within TTL, or `0` if none ever existed (`QuoteOracle.sol:305-312`). `_toUsd` treats a `0` factor as "cannot judge" and returns `0` (`CauldronHook.sol:712-713`), and `_afterSwap`'s `if (absVolume > 0)` gate (`CauldronHook.sol:800`) means **no bucket write happens and `_lastUpdateTs[id]` is not advanced** (`CauldronHook.sol:796-798`, explicitly deliberate). Consequently: existing volume within the current 24h window continues to be summed and read as alive (`getVolume24h`, `CauldronHook.sol:1486-1492`) — this is the "fails toward ALIVE" grace period described in the `QuoteOracle` header (`QuoteOracle.sol:40-44`). But once `block.timestamp > _lastUpdateTs[id] + SECONDS_PER_DAY` — i.e., 24h with zero successfully-priced swaps — `getVolume24h` hard-cliffs to `0` (`CauldronHook.sol:1486`), and `isDead` then reads `0 < deathThreshold` ⇒ `true` (dead), even though real trading may be occurring in raw terms; the pool is judged dead purely because it cannot be *priced*. So: **fails open for the first ≤24h of a missing/broken feed, then fails closed** once that window lapses with no successful price.
