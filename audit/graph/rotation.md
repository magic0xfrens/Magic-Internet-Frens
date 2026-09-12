# Rotation cluster — function graph

Generated from the decontaminated tree at `/tmp/blind-final/contracts/solidity`; **line numbers are identical to the repo**.

| File | Lines |
| --- | --- |
| `cauldron/QuoteRotator.sol` | 719 |
| `cauldron/QuoteOracle.sol` | 344 |
| `cauldron/RedemptionExt.sol` | 812 |
| `cauldron/CauldronVault.sol` | 126 |
| `cauldron/MockAggregator.sol` | 94 |
| `cauldron/MockQuoteToken.sol` | 28 |

84 nodes: 6 contracts plus the 6 interfaces declared inside them. `RedemptionExt` is a `delegatecall` facet of `CauldronRegistry` and inherits `CauldronBase`; its storage, custody and `address(this)` are the registry's, so every gate on a facet function is evaluated on the FACET side against the REGISTRY's slots. `CauldronRegistry.sol` and `cauldron/CauldronBase.sol` are read here for context only.

---

## A. Value inventory

Every storage field in the cluster that holds or counts value, its denomination, and every line that moves it.

### `QuoteRotator` (custody: its own native and ERC20 balances; there is no per-asset ledger)

| Field | Denomination | Increases | Decreases |
| --- | --- | --- | --- |
| `plan.totalIn` (QuoteRotator.sol:70) | raw units of `plan.from` | `setPlan` writing `totalIn` (QuoteRotator.sol:234) | never; cleared by `delete plan` (QuoteRotator.sol:250) |
| `plan.sliceIn` (QuoteRotator.sol:71) | raw units of `plan.from` | `setPlan` writing `sliceIn` (QuoteRotator.sol:235) | cleared (QuoteRotator.sol:250) |
| `plan.doneIn` (QuoteRotator.sol:72) | raw units of `plan.from` | `rotateStep` adding to `doneIn` (QuoteRotator.sol:305) | zeroed by `setPlan` zeroing `doneIn` (QuoteRotator.sol:236) and by `cancelPlan` deleting `plan` (QuoteRotator.sol:250) |
| `plan.gotOut` (QuoteRotator.sol:73) | raw units of `plan.to`, **gross of the keeper fee** | `rotateStep` adding to `gotOut` (QuoteRotator.sol:314) | zeroed at QuoteRotator.sol:237 and QuoteRotator.sol:250 |
| `plan.minRate` (QuoteRotator.sol:76) | raw `to` per 1e18 raw `from` | `setPlan` writing `minRate` (QuoteRotator.sol:238) | cleared (QuoteRotator.sol:250) |
| `keeperBps` (QuoteRotator.sol:89) | bps of slice output | `setKeeperBps` writing `keeperBps` (QuoteRotator.sol:255) | same setter, ceiling 100 (QuoteRotator.sol:254) |
| `rotationSlipBps` (QuoteRotator.sol:400) | bps off the oracle floor | `setRotationSlipBps` writing `rotationSlipBps` (QuoteRotator.sol:407) | same setter, ceiling 2000 (QuoteRotator.sol:406) |
| `arbKeeperBps` (QuoteRotator.sol:456) | bps of arb profit | `setArbParams` writing `arbKeeperBps` (QuoteRotator.sol:488) | same setter, ceiling 2000 (QuoteRotator.sol:486) |
| `minArbProfitUsd` (QuoteRotator.sol:461) | USD 1e18 | `setArbParams` writing `minArbProfitUsd` (QuoteRotator.sol:489) | same setter, unbounded |
| `maxArbNotionalUsd` (QuoteRotator.sol:474) | USD 1e18 | `setMaxArbNotionalUsd` writing `maxArbNotionalUsd` (QuoteRotator.sol:496) | same setter; 0 disables the bound (QuoteRotator.sol:598) |
| `arbUsdThisBlock` (QuoteRotator.sol:481) | USD 1e18 | `arbStep` storing `arbUsdThisBlock` (QuoteRotator.sol:602) | reset to 0 on a new block (QuoteRotator.sol:599) |

Native/ERC20 in: `receive` (QuoteRotator.sol:789) and `poolManager.take` (QuoteRotator.sol:696, QuoteRotator.sol:728).
Native/ERC20 out: `_send` (QuoteRotator.sol:745, QuoteRotator.sol:748) driven from `_send` (QuoteRotator.sol:317), `_send` (QuoteRotator.sol:613) and `_send` (QuoteRotator.sol:656); plus `_settle` to the pool manager (QuoteRotator.sol:734, QuoteRotator.sol:737).

### `QuoteOracle` (holds no value)

| Field | Denomination | Increases | Decreases |
| --- | --- | --- | --- |
| the `factor` member of `cache` (QuoteOracle.sol:287) | USD 1e18 per RAW unit | `factor` (QuoteOracle.sol:340), only when the refresh is non-zero | never — a failed refresh keeps the old value |
| `cache[q].at` (QuoteOracle.sol:286) | unix seconds | only on a CONFIRMED refresh, at `at` (QuoteOracle.sol:340) | never |
| `cache[q].triedAt` (QuoteOracle.sol:286) | unix seconds | every refresh ATTEMPT, at `triedAt` (QuoteOracle.sol:338) | never |
| `feeds[q].minUsd` / `.maxUsd` (QuoteOracle.sol:92, QuoteOracle.sol:93) | whole-token USD 1e18 | `setBounds` (QuoteOracle.sol:177, QuoteOracle.sol:178) | same setter; also silently zeroed by `setPegged` rewriting `feeds` (QuoteOracle.sol:158) |

### `CauldronVault`

| Field | Denomination | Increases | Decreases |
| --- | --- | --- | --- |
| native balance | wei | `receive` (CauldronVault.sol:72) | `call` (CauldronVault.sol:109), `registry` (CauldronVault.sol:121) |
| `redeemed` (CauldronVault.sol:40) | share count | `redeemed` (CauldronVault.sol:106) | never |
| `closed` (CauldronVault.sol:51) | flag | `closed` (CauldronVault.sol:118) | never — terminal |

### `RedemptionExt` (all of it the REGISTRY's storage, declared on `CauldronBase`)

| Field | Denomination | Increases | Decreases |
| --- | --- | --- | --- |
| `genesisReserveOutstanding` (CauldronBase.sol:426) | raw units of the generation token | `genesisReserveOutstanding` (RedemptionExt.sol:182) | `genesisReserveOutstanding` (RedemptionExt.sol:91), and only when it already covers the floor |
| `genesisPending` (RedemptionExt.sol:158) | raw units of the generation token | `genesisPending` (RedemptionExt.sol:158) | not in this cluster |
| `legProceeds` (RedemptionExt.sol:831) | raw units of that asset | `legProceeds` (RedemptionExt.sol:831) | zeroed in full by `legProceeds` (RedemptionExt.sol:889) |
| `legs` (RedemptionExt.sol:698) | set of positions | pushed at RedemptionExt.sol:698, id overwritten at RedemptionExt.sol:696 | swap-and-pop at RedemptionExt.sol:834 and RedemptionExt.sol:835 |
| `generationQuote[gen]` (RedemptionExt.sol:527) | address | flipped at RedemptionExt.sol:527 | also written on relaunch at `generationQuote` (CauldronRegistry.sol:1000) |

---

## B. Balance vs counter — where they can diverge

- **`plan.doneIn` is not backed by a balance.** `nextSliceSize` clamps the slice to what is actually held (QuoteRotator.sol:274), while `withdraw` can remove that balance at any time (QuoteRotator.sol:656) without touching the plan. A plan can therefore read as partially done with nothing converted, or sit at size 0 and revert `TooSoon` (QuoteRotator.sol:289) rather than announcing an empty treasury.
- **`plan.gotOut` overstates custody by `keeperBps`.** The received amount is booked whole (QuoteRotator.sol:314) and the keeper's cut leaves three lines later (QuoteRotator.sol:317).
- **`arbUsdThisBlock` has no balance behind it at all**; its reset is keyed on `block.number` (QuoteRotator.sol:599), so it measures a block, and it is written AFTER the swap has already settled (QuoteRotator.sol:602).
- **`QuoteRotator` keeps no per-plan segregation.** `receive` (QuoteRotator.sol:789) accepts anything, `balanceOf` (QuoteRotator.sol:779) is a raw balance read, and `_send` (QuoteRotator.sol:656) can move any asset to anyone the owner or registry names.
- **`cache[q].factor` is a price, never reconciled**; a failed refresh now advances only `triedAt` (QuoteOracle.sol:338) while `at` (QuoteOracle.sol:340) stays at the last confirmed price, so the retained factor is still served but its age is visible. The retry throttle at `factor` (QuoteOracle.sol:337) applies only once a non-zero factor exists.
- **`CauldronVault.redeemed` vs balance**: both fall together (CauldronVault.sol:106, CauldronVault.sol:109), but `outstanding` recomputes the numerator from the collection's own `totalMinted` (CauldronVault.sol:56), so any burn path outside `burnFromVault` (CauldronVault.sol:107) moves the floor without moving `redeemed`.
- **`genesisReserveOutstanding` vs the reserve position**: the debit is conditional (RedemptionExt.sol:91) and the delivery check tolerates 1e12 (RedemptionExt.sol:104), so the counter can sit slightly above or below the LP. On the credit side only the amount the library reports as actually added is booked (RedemptionExt.sol:182), and a zero add reverts (RedemptionExt.sol:181).
- **`legProceeds` is backed by the registry's balance** measured from what `removeAll` returned (RedemptionExt.sol:830), and the sweep zeroes the booking before transferring (RedemptionExt.sol:889).

---

## C. Authority map

| Gate | Held by | Guards | Can it rotate? | Can it renounce? | Dead-end risk |
| --- | --- | --- | --- | --- | --- |
| `QuoteRotator.onlyOwner` (QuoteRotator.sol:130) | `owner` (QuoteRotator.sol:83), the treasury | `transferOwnership` (QuoteRotator.sol:135), `setVenue` (QuoteRotator.sol:190), `onlyOwner` (QuoteRotator.sol:223), `cancelPlan` (QuoteRotator.sol:248), `setKeeperBps` (QuoteRotator.sol:253), `setRotationSlipBps` (QuoteRotator.sol:405), `setArbParams` (QuoteRotator.sol:485), `setMaxArbNotionalUsd` (QuoteRotator.sol:495) | yes, one-step (QuoteRotator.sol:135) | no dedicated function | yes — no zero check at QuoteRotator.sol:135; config freezes while registry-driven execution keeps working |
| `QuoteRotator.onlyRegistry` (QuoteRotator.sol:125) | immutable `registry` (QuoteRotator.sol:100) | `onlyRegistry` (QuoteRotator.sol:341) | no | no | permanent by construction |
| `QuoteRotator.withdraw` inline check (QuoteRotator.sol:654) | registry **or** owner | `withdraw` | follows the two above | no | no |
| `QuoteRotator.unlockCallback` inline check (QuoteRotator.sol:674) | immutable `poolManager` (QuoteRotator.sol:101) | `unlockCallback` | no | no | permanent |
| ungated | anyone | `rotateStep` (QuoteRotator.sol:284), `arbStep` (QuoteRotator.sol:533), `nextSliceSize` (QuoteRotator.sol:263), `isVenueAllowed` (QuoteRotator.sol:197), `receive` (QuoteRotator.sol:789) | — | — | — |
| `QuoteOracle.onlyOwner` (QuoteOracle.sol:114) | `owner` (QuoteOracle.sol:96), documented as the timelock | `transferOwnership` (QuoteOracle.sol:119), `onlyOwner` (QuoteOracle.sol:133), `setPegged` (QuoteOracle.sol:153), `setBounds` (QuoteOracle.sol:175), `setSequencer` (QuoteOracle.sol:182) | yes (QuoteOracle.sol:119) | no dedicated function | yes — zero is storable, freezing every feed |
| `MockAggregator.onlyOwner` (MockAggregator.sol:60) | `owner` (MockAggregator.sol:37) | `transferOwnership`, `peg`, `setStale`, `setDown` (MockAggregator.sol:65, MockAggregator.sol:68, MockAggregator.sol:76, MockAggregator.sol:82) | yes (MockAggregator.sol:65) | no | yes — zero is storable |
| `CauldronVault` registry check (CauldronVault.sol:117) | immutable `registry` (CauldronVault.sol:67) | `close` | no | no | permanent |
| `CauldronVault` owner check (CauldronVault.sol:97) | the NFT's holder | `redeem` | n/a | n/a | n/a |
| `RedemptionExt.onlyOwner` (Ownable, via `CauldronBase`) | the REGISTRY's owner slot | `setRotationWiring` (RedemptionExt.sol:260), `sweepLegProceeds` (RedemptionExt.sol:882) | `transferOwnership` is live | **no** — `renounceOwnership` reverts (CauldronBase.sol:464) | no |
| ungated facet entries | anyone | `rotateSlice` (RedemptionExt.sol:269), `rotateSliceFrom` (RedemptionExt.sol:280), `recoverLegs` (RedemptionExt.sol:732), `donateToReserve` (RedemptionExt.sol:136), `materializeLegacyReserve` (RedemptionExt.sol:147), the three views | — | — | — |

**How the forwarders reach the facet, and which side holds the gate.** Every facet entry is reached by `CauldronRegistry` copying the full calldata into a `delegatecall` at `delegatecall` (CauldronRegistry.sol:1462), reached from `_forwardToExt` (CauldronRegistry.sol:1457). The registry's own stubs carry **no** modifiers — `setRotationWiring` (CauldronRegistry.sol:274), `sweepLegProceeds` (CauldronRegistry.sol:300), `rotateSlice` (CauldronRegistry.sol:240), `rotateSliceFrom` (CauldronRegistry.sol:264), `redeemOgFren` (CauldronRegistry.sol:1389), `buyTreasuryOgFren` (CauldronRegistry.sol:1395), `donateToReserve` (CauldronRegistry.sol:1401), `materializeLegacyReserve` (CauldronRegistry.sol:1407) and the three views at `floorClaimableNow` (CauldronRegistry.sol:1424), `legCount` (CauldronRegistry.sol:1429) and `legAt` (CauldronRegistry.sol:1434). The only check on the registry side is that a facet is wired at `NotConfigured` (CauldronRegistry.sol:1459). `recoverLegs` now HAS a stub, at `recoverLegs` (CauldronRegistry.sol:290), and `claimByBurnUpTo` moved onto the facet behind its own stub at `claimByBurnUpTo` (CauldronRegistry.sol:1288); the teardown-only entry `recoverLegsAtTeardown` (RedemptionExt.sol:783) is deliberately unrouted and reached solely by the compiler-built selector at `RECOVER_LEGS` (CauldronRegistry.sol:1613). **One facet function has no forwarder at all** — `legProceedsOf` (RedemptionExt.sol:845), deliberately per the note at `legProceedsOf` (CauldronRegistry.sol:302) — and the registry has no catch-all fallback (CauldronRegistry.sol:1414), so it cannot run against the registry's storage. `completeRotation` was deleted outright, per the note at `completeRotation` (RedemptionExt.sol:608).

---

## D. External calls, the value they carry, and CEI ordering

| Call site | Callee | Value | Ordering |
| --- | --- | --- | --- |
| `totalMinted` (CauldronVault.sol:56) | collection | none | pure read |
| `ownerOf` (CauldronVault.sol:97) | collection | none | before effects |
| `burnFromVault` (CauldronVault.sol:107) | collection | none | AFTER `redeemed` is incremented (CauldronVault.sol:106) |
| `call` (CauldronVault.sol:109) | the redeemer | native out | last; guarded by `nonReentrant` |
| `call` (CauldronVault.sol:121) | the registry | native out, whole balance | AFTER `closed` is set (CauldronVault.sol:118) |
| `decimals` (QuoteOracle.sol:138), `decimals` (QuoteOracle.sol:155) | the quote token | none | before the struct write |
| `latestRoundData` (QuoteOracle.sol:231), `decimals` (QuoteOracle.sol:249) | the aggregator | none | inside try/catch; read-only |
| `latestRoundData` (QuoteOracle.sol:358) | sequencer feed | none | inside try/catch |
| `usdPerRawUnit` (QuoteOracle.sol:339) | itself, via `this.` | none | after `triedAt` is stamped (QuoteOracle.sol:338), before `factor` is written (QuoteOracle.sol:340) |
| `unlock` (QuoteRotator.sol:669) | pool manager | drives settle/take | AFTER `lastStepAt`/`doneIn` (QuoteRotator.sol:304, QuoteRotator.sol:305) |
| `swap` (QuoteRotator.sol:684) | pool manager | delta only | inside the lock |
| `_settle` (QuoteRotator.sol:695) then `take` (QuoteRotator.sol:696) | pool manager | native/ERC20 out then in | settle before take |
| `unlock` (QuoteRotator.sol:577) | pool manager | both arb legs | BEFORE the per-block counter is written (QuoteRotator.sol:602) — interaction precedes effect |
| `swap` (QuoteRotator.sol:710), `swap` (QuoteRotator.sol:720) | pool manager | delta only | inside one lock |
| `_settle` (QuoteRotator.sol:727) then `take` (QuoteRotator.sol:728) | pool manager | spends the cheap quote, receives the dear quote | settle before take |
| `settle` (QuoteRotator.sol:734) | pool manager | **native out** | — |
| `sync` (QuoteRotator.sol:736), `_safeTransfer` (QuoteRotator.sol:737), `settle` (QuoteRotator.sol:738) | pool manager / token | **ERC20 out** | v4 sync-transfer-settle |
| `call` (QuoteRotator.sol:745) | arbitrary recipient | **native out, all gas** | last in `rotateStep`; last in `arbStep`; only statement in `withdraw` |
| `call` (QuoteRotator.sol:764) | arbitrary token | **ERC20 out** | — |
| `staticcall` (QuoteRotator.sol:625) | the configured oracle, READ-ONLY (`_usdLive`; the cached reader is gone) | none | before the floor check (QuoteRotator.sol:393), before the unlock at `NotPriceable` (QuoteRotator.sol:574) and before the arb counter (QuoteRotator.sol:602) |
| `staticcall` (QuoteRotator.sol:785) | the registry | none | fails closed |
| `balanceOf` (QuoteRotator.sol:779) | arbitrary token | none | not wrapped — a reverting token blocks the plan |
| `allowance` (RedemptionExt.sol:303) | treasury governor | none | before anything moves |
| `removePartial` (RedemptionExt.sol:385) | `PoolOps` (delegatecall) | liquidity out of the pair, into the registry | first move |
| `sendAsset` (RedemptionExt.sol:397) | `PoolOps` (delegatecall) | **quote side out to the rotator** | before the swap |
| `swapOnce` (RedemptionExt.sol:398) | `QuoteRotator` | conversion | — |
| `withdraw` (RedemptionExt.sol:399) | `QuoteRotator` | **proceeds back in** | same transaction |
| `openOrAddPair` (RedemptionExt.sol:404) | `PoolOps` (delegatecall) | **both sides out into the new position** | — |
| `linkVolume` (RedemptionExt.sol:418) | the hook | none | refuses while the perp book is open |
| `consume` (RedemptionExt.sol:459) | treasury governor | none | **after every interaction** — the envelope is spent last |
| `migrationMandateSpent` (RedemptionExt.sol:526) | treasury governor | none | decides the write at RedemptionExt.sol:527 |
| `perpEngine` (RedemptionExt.sol:561), `syncGeneration` (RedemptionExt.sol:562) | hook, perp engine | none | best-effort, in try/catch |
| `ownerOf` (RedemptionExt.sol:84) / `custodyTransfer` (RedemptionExt.sol:92) / `claimFromReserve` (RedemptionExt.sol:95) | MiFrens, `PoolOps` | **generation token out to the redeemer** | effects at RedemptionExt.sol:91 and RedemptionExt.sol:92 precede the payout |
| `transferFrom` (RedemptionExt.sol:167) / `addToReserve` (RedemptionExt.sol:168) | token, `PoolOps` | **token in, then into the reserve** | counter credited after, at RedemptionExt.sol:182 |
| `materializeLegacy` (RedemptionExt.sol:151) | `PoolOps` | hook-held tokens into the reserve | counter after, at RedemptionExt.sol:158 |
| `getSlot0` (RedemptionExt.sol:638) | pool manager | none | view |
| `removeAll` (RedemptionExt.sol:824) | `PoolOps` | **each leg's liquidity back to the registry** | booking and pop after, at RedemptionExt.sol:831 and RedemptionExt.sol:835 |
| `sendAsset` (RedemptionExt.sol:890) | `PoolOps` | **booked asset out** | AFTER the booking is zeroed (RedemptionExt.sol:889) |

`rotateSliceFrom` (RedemptionExt.sol:280), `rotateSlice` (RedemptionExt.sol:269) and `recoverLegs` (RedemptionExt.sol:732) carry **no** `nonReentrant` modifier, and neither do the registry stubs that reach them; `QuoteRotator` has no reentrancy guard anywhere.

---

## E. Loops

Only two loops exist in the cluster; both are in `RedemptionExt` and both are bounded by `generationLegs[gen].length`.

| Loop | Bound | Who can grow the bound |
| --- | --- | --- |
| `for` in the `i < n` scan (RedemptionExt.sol:695) | the current leg count, read at RedemptionExt.sol:694 | only a push at RedemptionExt.sol:698, which happens once per DISTINCT destination quote; repeated slices into the same pair overwrite at RedemptionExt.sol:696 |
| `while` in the `while (i > 0)` walk (RedemptionExt.sol:821) | the leg count read at RedemptionExt.sol:820, descending | same push; each success removes an entry at RedemptionExt.sol:835 |

A destination must pass `allowedQuote` (RedemptionExt.sol:322) before a leg can be created, so the maximum leg count is the size of the owner-curated allowlist written at `setAllowedQuote` (CauldronRegistry.sol:308) — a permissionless caller can create legs, but only for assets the owner has already admitted. `recoverLegs` runs inside relaunch (CauldronRegistry.sol:1613); its per-leg `catch` (RedemptionExt.sol:837) keeps one bad leg from blocking the rest, and because the walk is descending while removal is swap-and-pop, an entry moved into the current slot is not revisited in that pass.

`QuoteRotator`, `QuoteOracle`, `CauldronVault` and both mocks contain no loops.

---

## F. Denomination and units

- **`QuoteOracle` is the only place decimals are normalised.** The feed's own decimals are read per call at `feedDec` (QuoteOracle.sol:248) and folded to a 1e18-per-WHOLE-token figure at `perWhole` (QuoteOracle.sol:256); the token's decimals are stored once at `quoteDecimals` (QuoteOracle.sol:69), taken either from the caller or from the token at `decimals` (QuoteOracle.sol:138) / `decimals` (QuoteOracle.sol:155); the final conversion to **USD 1e18 per RAW unit** happens at `factor` (QuoteOracle.sol:277), multiplying before dividing. The pegged shortcut does the same conversion with a literal dollar at `pegged` (QuoteOracle.sol:207).
- **Sanity bounds are in whole-token USD 1e18**, compared against `perWhole` (QuoteOracle.sol:267, QuoteOracle.sol:268) — not against the per-raw-unit factor.
- **`QuoteRotator.plan.minRate` is raw `to` per 1e18 raw `from`.** The floor is `size * minRate / WAD` (QuoteRotator.sol:310) where `size` is in raw `from` units — so for an 18-decimal source the comment's "per whole unit" (QuoteRotator.sol:74) holds, and for a 6-decimal source the same literal means per 1e18 raw units, i.e. per 1e12 whole tokens.
- **`_oracleFloor` is decimals-agnostic by routing through USD**: source to USD at `inUsd` (QuoteRotator.sol:439), destination priced per 1e18 raw units at `perUnitTo` (QuoteRotator.sol:441), and the division back at `fair` (QuoteRotator.sol:443) cancels the scale.
- **`_usdLive` multiplies the raw amount by the factor and divides by 1e18**, at `raw` (QuoteRotator.sol:630) — USD 1e18 out, any decimals in.
- **The arb keeper cut mixes units correctly**: `received * profitUsd * arbKeeperBps / (outUsd * BPS)` (QuoteRotator.sol:612) is raw-`out` units, because `received / outUsd` is units per USD.
- **`sliceBps` is a share of CURRENT liquidity**, not of the original position (RedemptionExt.sol:210), so successive slices compound rather than sum; the per-call ceiling is 2500 (RedemptionExt.sol:598) inside the library's own 5000 cap.
- **`recoverLegs` keeps one denomination per sum** by matching on the primary pool's own `currency0` at `matchQuote` (RedemptionExt.sol:818) rather than on the possibly-flipped `generationQuote` (RedemptionExt.sol:527); foreign assets go to `legProceeds` (RedemptionExt.sol:831) instead of into the returned figure.
- **`CauldronVault` is native-wei only** (CauldronVault.sol:80); the registry wires the hook's vault to zero on both collection paths (CauldronRegistry.sol:1189, CauldronRegistry.sol:1213), so its balance stays zero and `redeem` reports that explicitly at `UnifiedFloorActive` (CauldronVault.sol:102).
- `MockAggregator` fixes 8 decimals to match Chainlink (MockAggregator.sol:40); `MockQuoteToken` takes its decimals at construction (MockQuoteToken.sol:21).

---

## G. `unchecked` blocks and rounding direction

**There are no `unchecked` blocks in any of the six files.** The only occurrence of the word is prose at `unchecked` (QuoteRotator.sol:753). All arithmetic is Solidity 0.8 checked arithmetic, so every overflow and every underflow reverts; the places that could underflow are guarded explicitly instead: the saturating subtractions at `eligible` (CauldronVault.sol:57) and at `redeemed` (CauldronVault.sol:58), the conditional debit at `genesisReserveOutstanding` (RedemptionExt.sol:91), the future-timestamp refusals at `updatedAt` (QuoteOracle.sol:245) and `startedAt` (QuoteOracle.sol:365).

Every division truncates toward zero. Directions that matter:

| Division | Rounds | Effect |
| --- | --- | --- |
| `balance / n` (CauldronVault.sol:80, CauldronVault.sol:100) | down | the remainder stays in the vault, accruing to the survivors |
| `genesisReserveOutstanding / shares` (CauldronBase.sol:426) | down | floor understated by at most 1 wei per fren |
| `10 ** quoteDecimals` divisor (QuoteOracle.sol:207, QuoteOracle.sol:277) | down | price understated |
| `answer / 10 ** (feedDec - 18)` (QuoteOracle.sol:258) | down | only for feeds with more than 18 decimals |
| `size * minRate / WAD` (QuoteRotator.sol:310) | down | the required minimum is understated — favours the fill |
| `out * keeperBps / BPS` (QuoteRotator.sol:316) | down | keeper fee understated — favours the treasury |
| `inUsd * 1e18 / perUnitTo` and `fair * (BPS - slip) / BPS` (QuoteRotator.sol:443, QuoteRotator.sol:444) | down | the oracle floor is understated — favours the fill |
| `raw * f` divided by 1e18 (QuoteRotator.sol:630) | down | USD understated; on the arb path that understates BOTH legs |
| `received * profitUsd * arbKeeperBps / (outUsd * BPS)` (QuoteRotator.sol:612) | down | keeper cut understated |

Narrowing casts (not rounding, but silent on overflow only because the values are checked upstream): `uint64(block.timestamp)` and `uint128(size)` at `doneIn` (QuoteRotator.sol:305), `uint128(out)` at `gotOut` (QuoteRotator.sol:314), and the `uint256(uint128(...))` delta reads at `got` (QuoteRotator.sol:694), `spent` (QuoteRotator.sol:715), `got` (QuoteRotator.sol:716) and `received` (QuoteRotator.sol:725).

---

## H. Comment-vs-code observations

Recorded as pairs; no judgement attached.

1. `hook` (CauldronVault.sol:71) says fees flow in from the hook — `setVault` (CauldronRegistry.sol:1189) and `setVault` (CauldronRegistry.sol:1213) both wire the hook's vault to address(0).
2. `updatedAt` (MockAggregator.sol:27) says the feed returns `block.timestamp` — `ts` (MockAggregator.sol:91) returns the epoch value 1 whenever `stale` is set.
3. `triedAt` (QuoteOracle.sol:332) says the retry is throttled to once per TTL — the throttle at `factor` (QuoteOracle.sol:337) runs only when a non-zero factor already exists, so a quote that never priced pays a full feed read on every call. (The earlier defect — `at` restamped on a failed refresh — is fixed: it now moves only at `at` (QuoteOracle.sol:340).)
4. `cap` (QuoteRotator.sol:492) calls the bound a per-call notional cap — `spentThisBlock` (QuoteRotator.sol:600) accumulates across every call in a block.
5. `None` (QuoteRotator.sol:525) says no capital is needed because only the net delta settles — `_settle` (QuoteRotator.sol:727) pays the cheap pool's `currency0` in full from this contract's balance while `take` (QuoteRotator.sol:728) receives a different asset.
6. `Owner` (QuoteRotator.sol:646) says `withdraw` is owner-only — `registry` (QuoteRotator.sol:654) accepts the registry too, as the later note at `rotateSlice` (QuoteRotator.sol:650) admits.
7. `capital` (QuoteRotator.sol:701) repeats the no-capital claim for the arb callback — `_settle` (QuoteRotator.sol:727) shows only the TOKEN leg nets.
8. `CHECKED` (QuoteRotator.sol:752) says an unchecked transfer would report success while nothing moved — `ret` (QuoteRotator.sol:765) still accepts an empty return as success, but the codeless-address case is now refused ahead of it at `TransferFailed` (QuoteRotator.sol:762).
9. `registration` (RedemptionExt.sol:43) documents the hook's generation-volume registration — `ITreasuryGovernor` (RedemptionExt.sol:44) is the treasury envelope interface; the volume registration is `linkVolume` (RedemptionExt.sol:59).
10. `debit` (RedemptionExt.sol:88) says the reserve accounting is debited first — `genesisReserveOutstanding` (RedemptionExt.sol:91) debits only when the recorded reserve already covers the floor, and otherwise pays out without debiting.
11. `sliceBps` (RedemptionExt.sol:210) documents slice, floor and route parameters — the next declaration, `setRotationWiring` (RedemptionExt.sol:260), takes a rotator and a governor.
12. `DRAINED` (RedemptionExt.sol:252) describes a dust threshold for declaring the primary drained — `migrationMandateSpent` (RedemptionExt.sol:526) decides redenomination from the mandate flag alone, and `PRIMARY_DRAINED_DUST` (RedemptionExt.sol:258) is read nowhere.
13. `relaunch` (RedemptionExt.sol:463) puts the registry's other write of the generation quote at line 917 — the write is at `generationQuote` (CauldronRegistry.sol:1000).
14. `rebirth` (RedemptionExt.sol:706) says `recoverLegs` is safe to call directly afterwards — it now is, through the registry stub at `recoverLegs` (CauldronRegistry.sol:290), and it is gated to PAST generations at `CannotClaimCurrentGen` (RedemptionExt.sol:733); the teardown entry `recoverLegsAtTeardown` (RedemptionExt.sol:783) stays reachable only through `RECOVER_LEGS` (CauldronRegistry.sol:1613).

---

## The rotation state machine

### Machine 1 — the scheduled plan, inside `QuoteRotator`

State lives entirely in one struct, `plan` (QuoteRotator.sol:81).

| State | Test | Entered by | Gate |
| --- | --- | --- | --- |
| NONE | `plan.totalIn == 0` (QuoteRotator.sol:265, QuoteRotator.sol:286) | deployment default; `delete plan` at QuoteRotator.sol:250 | `onlyOwner` (QuoteRotator.sol:248) for the delete |
| ARMED | `totalIn != 0` and `lastStepAt == 0` (QuoteRotator.sol:270) | `setPlan` writes the whole struct at QuoteRotator.sol:231 | `onlyOwner` (QuoteRotator.sol:223) |
| RUNNING | `lastStepAt != 0`, `doneIn < totalIn` | `rotateStep` stamps `lastStepAt` (QuoteRotator.sol:304) and adds to `doneIn` (QuoteRotator.sol:305) | **ungated** (QuoteRotator.sol:284); the route must be curated (QuoteRotator.sol:299) |
| COOLING | `block.timestamp < lastStepAt + interval` (QuoteRotator.sol:270) | the same stamp | — |
| FINISHED | `doneIn >= totalIn` (QuoteRotator.sol:265) | accumulation at QuoteRotator.sol:305 | — |
| CANCELLED | back to NONE | `cancelPlan` deleting `plan` (QuoteRotator.sol:250) | `onlyOwner` (QuoteRotator.sol:248) |

`setPlan` is the only writer of `from`, `to`, `totalIn`, `sliceIn`, `minRate` and `interval`, and it can be called from ANY state — overwriting a live plan resets `doneIn` and `gotOut` to zero in the same literal (QuoteRotator.sol:236, QuoteRotator.sol:237). A step is possible only when all five of these hold: a plan exists (QuoteRotator.sol:286), the size is non-zero (QuoteRotator.sol:289), the destination is allowlisted (QuoteRotator.sol:290), the key trades the pair (QuoteRotator.sol:291) and the key is curated (QuoteRotator.sol:299).

Two side machines sit beside it:

- **Venue allowlist** — `allowedVenue` (QuoteRotator.sol:183), flipped either way by `allowedVenue` (QuoteRotator.sol:192) under `onlyOwner` (QuoteRotator.sol:190); read by all three spending paths (QuoteRotator.sol:299, QuoteRotator.sol:359, QuoteRotator.sol:553). Unset means nothing executes.
- **Arb throttle** — `arbBlock` (QuoteRotator.sol:480) and `arbUsdThisBlock` (QuoteRotator.sol:481). Transition: on a new `block.number` both reset (QuoteRotator.sol:599), then the running total accumulates (QuoteRotator.sol:600) and is stored (QuoteRotator.sol:602). Trigger: `arbStep`, ungated (QuoteRotator.sol:533). Gate: only active while `maxArbNotionalUsd != 0` (QuoteRotator.sol:598).

### Machine 2 — the live rotation, inside `RedemptionExt` on the registry's storage

| State variable | Declared | Written | Trigger | Gate |
| --- | --- | --- | --- | --- |
| `quoteRotator` | CauldronBase.sol:365 | RedemptionExt.sol:262 | `setRotationWiring` | `onlyOwner` on the facet (RedemptionExt.sol:260); the registry stub is ungated (CauldronRegistry.sol:274) |
| `treasuryGovernor` | CauldronBase.sol:371 | RedemptionExt.sol:263 | same call | same |
| `allowedQuote` | CauldronBase.sol:347 | `setAllowedQuote` (CauldronRegistry.sol:308) | owner | registry-side `onlyOwner` |
| `generationLegs[gen]` | CauldronBase.sol:507 | push RedemptionExt.sol:698, update RedemptionExt.sol:696, remove RedemptionExt.sol:834 and RedemptionExt.sol:835 | `_recordLeg` from a slice (RedemptionExt.sol:445); `recoverLegs` at teardown | ungated on both paths |
| `generationQuote[gen]` | CauldronBase.sol:358 | RedemptionExt.sol:527 | a primary-leg slice whose mandate is spent (RedemptionExt.sol:526) | ungated — the governor's flag is the whole gate |
| `legProceeds[asset]` | CauldronBase.sol:529 | credit RedemptionExt.sol:831, clear RedemptionExt.sol:889 | `recoverLegs`; `sweepLegProceeds` | ungated / `onlyOwner` (RedemptionExt.sol:882) |

Transitions, in the order one slice performs them: **UNWIRED** → `quoteRotator` (RedemptionExt.sol:262) → **WIRED**; **WIRED** + a live envelope (RedemptionExt.sol:317) → `rotateSliceFrom` removes (RedemptionExt.sol:385), swaps (RedemptionExt.sol:398), pulls back (RedemptionExt.sol:399), redeploys (RedemptionExt.sol:404), links volume (RedemptionExt.sol:418), records the leg (RedemptionExt.sol:445) and only then spends envelope (RedemptionExt.sol:459) → **SPLIT**; **SPLIT** + `migrationMandateSpent` on a primary slice (RedemptionExt.sol:526) → the quote flips (RedemptionExt.sol:527) and the perp engine is re-pointed best-effort (RedemptionExt.sol:562) → **REDENOMINATED**; at relaunch `RECOVER_LEGS` (CauldronRegistry.sol:1613) unwinds every leg → back to a single position. There is no pause, no abort and no pending state: the design note at `mind` (RedemptionExt.sol:208) says a guild that changes its mind simply stops calling.

Two flags outside this cluster gate the machine from the side: `linkVolume` refuses while the perp book is open, at `PerpsOpen` (CauldronHook.sol:1624), and the envelope's own liveness comes from `allowance` (TreasuryGovernor.sol:753).

### Machine 3 — `CauldronVault`

`closed` (CauldronVault.sol:51) is a one-way flag: false at deployment, set true by `closed` (CauldronVault.sol:118) under the registry check at `NotRegistry` (CauldronVault.sol:117), which the relaunch path reaches through `close` (PoolOps.sol:1013). Once set, `redeem` reverts at `Closed` (CauldronVault.sol:95) while `receive` (CauldronVault.sol:72) still accepts deposits. `redeemed` (CauldronVault.sol:40) only ever rises (CauldronVault.sol:106).

---

## The envelope lifecycle

Two different "envelopes" exist in this cluster; they are not the same object.

### The governance envelope (the one that authorises a live rotation)

- **Creation** — outside the cluster, in `TreasuryGovernor`; this cluster only ever reads it.
- **Who holds it** — the address in `treasuryGovernor` (CauldronBase.sol:371), written only at RedemptionExt.sol:263. A zero there stops every slice at `RotationNotWired` (RedemptionExt.sol:302).
- **Where its denomination is set** — by the vote; it is READ here as the first return of `allowance` (RedemptionExt.sol:303) and re-validated against the registry allowlist at `allowedQuote` (RedemptionExt.sol:322). The destination is never a caller parameter.
- **Liveness** — the SECOND return, the remaining bps, is the flag: absent, expired and spent envelopes all report zero and stop at `NoRotationApproved` (RedemptionExt.sol:317). Address zero is deliberately NOT the sentinel, because it is also a legitimate destination (native ether).
- **Funding / ceiling** — each call must fit inside the remainder (RedemptionExt.sol:318) and inside the per-call slice cap (RedemptionExt.sol:326, RedemptionExt.sol:598).
- **Spend** — `consume` (RedemptionExt.sol:459), booked only after the liquidity has actually moved, and told whether the slice came from the primary via the comparison on the same line.
- **Completion** — `migrationMandateSpent` (RedemptionExt.sol:526); true only on a primary-leg slice, and it is what flips `generationQuote` (RedemptionExt.sol:527) and re-points the perp engine (RedemptionExt.sol:562).
- **Abort** — none in this cluster; the caller stops calling (RedemptionExt.sol:208).

### The rotator's own envelope (the `Plan`)

- **Creation** — `setPlan` writing the whole `plan` (QuoteRotator.sol:231), owner-gated (QuoteRotator.sol:223); denomination set there as `from` and `to` (QuoteRotator.sol:232, QuoteRotator.sol:233) and read on every step at `from` (QuoteRotator.sol:273), `to` (QuoteRotator.sol:290) and `from` (QuoteRotator.sol:291).
- **Who holds it** — `QuoteRotator` itself; there is exactly one slot (QuoteRotator.sol:81), so one plan at a time.
- **Funding** — not part of the plan. Assets must simply BE in the rotator: native through `receive` (QuoteRotator.sol:789) or ERC20 by transfer, and `nextSliceSize` clamps to whatever is there at `held` (QuoteRotator.sol:274).
- **Spend** — `rotateStep` adding to `doneIn` (QuoteRotator.sol:305) advances `doneIn`, `rotateStep` adding to `gotOut` (QuoteRotator.sol:314) records `gotOut`, and the keeper takes its cut at QuoteRotator.sol:317.
- **Completion** — implicit: `doneIn >= totalIn` makes every further step return zero at QuoteRotator.sol:265. Nothing is emitted and nothing is cleared.
- **Abort** — `cancelPlan` deleting `plan` (QuoteRotator.sol:250), owner-gated, which deletes the struct and leaves the converted assets in place for `withdraw` (QuoteRotator.sol:653).

The two envelopes never meet: the live rotation path (`rotateSliceFrom` → `swapOnce`) does not read `plan` at all, and `rotateStep` does not consult the treasury governor.

---

## I. Function inventory


**IBurnableCollection (declared in CauldronVault.sol)** — `cauldron/CauldronVault.sol`

- `CauldronVault.sol:7` `function ownerOf(uint256 tokenId) external view returns (address)` — **anyone (declaration only; the implementation is whatever collection address the vault was constructed with)** — NONE
- `CauldronVault.sol:8` `function totalMinted() external view returns (uint256)` — **anyone (declaration only; the implementation is whatever collection address the vault was constructed with)** — NONE
- `CauldronVault.sol:9` `function burnFromVault(uint256 tokenId) external` — **anyone (declaration only; in practice the vault is the only caller and the collection must gate it to the vault)** — NONE

**CauldronVault** — `cauldron/CauldronVault.sol`

- `CauldronVault.sol:55` `function outstanding() public view returns (uint256)` — **anyone** — NONE
- `CauldronVault.sol:65` `constructor(address _collection, address _registry, uint256 _floorOffset)` — **deployer** — NONE
- `CauldronVault.sol:72` `receive() external payable` — **anyone** — `receive` receives native (line 72)
- `CauldronVault.sol:77` `function floorPerNFT() public view returns (uint256)` — **anyone** — NONE
- `CauldronVault.sol:94` `function redeem(uint256 tokenId) external nonReentrant returns (uint256 amount)` — **anyone (must own the NFT)** — `call` sends native to the redeemer (line 109)
- `CauldronVault.sol:116` `function close() external nonReentrant returns (uint256 swept)` — **registry (the immutable address fixed at construction)** — `registry` receives the whole native balance (line 121)

**MockAggregator** — `cauldron/MockAggregator.sol`

- `MockAggregator.sol:54` `constructor(string memory desc, int256 initialAnswer)` — **deployer** — NONE
- `MockAggregator.sol:60` `modifier onlyOwner()` — **internal (callers: transferOwnership, peg, setStale, setDown)** — NONE
- `MockAggregator.sol:65` `function transferOwnership(address to) external onlyOwner` — **owner** — NONE
- `MockAggregator.sol:68` `function peg(int256 answer) external onlyOwner` — **owner** — NONE
- `MockAggregator.sol:76` `function setStale(bool s) external onlyOwner` — **owner** — NONE
- `MockAggregator.sol:82` `function setDown(bool d) external onlyOwner` — **owner** — NONE
- `MockAggregator.sol:84` `function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)` — **anyone** — NONE

**MockQuoteToken** — `cauldron/MockQuoteToken.sol`

- `MockQuoteToken.sol:20` `constructor(string memory name_, string memory symbol_, uint8 dec_) ERC20(name_, symbol_)` — **deployer** — NONE
- `MockQuoteToken.sol:24` `function decimals() public view override returns (uint8)` — **anyone** — NONE
- `MockQuoteToken.sol:27` `function mint(address to, uint256 amount) external` — **anyone** — mints ERC20 balance via `_mint` to an arbitrary recipient (line 27)

**IAggregatorV3 (declared in QuoteOracle.sol)** — `cauldron/QuoteOracle.sol`

- `QuoteOracle.sol:5` `function decimals() external view returns (uint8)` — **anyone (declaration only; the implementation is the owner-chosen aggregator address)** — NONE
- `QuoteOracle.sol:6` `function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)` — **anyone (declaration only; the implementation is the owner-chosen aggregator or sequencer feed)** — NONE

**IERC20Decimals (declared in QuoteOracle.sol)** — `cauldron/QuoteOracle.sol`

- `QuoteOracle.sol:13` `function decimals() external view returns (uint8)` — **anyone (declaration only; the implementation is the quote token being configured)** — NONE

**QuoteOracle** — `cauldron/QuoteOracle.sol`

- `QuoteOracle.sol:110` `constructor(address _owner)` — **deployer** — NONE
- `QuoteOracle.sol:114` `modifier onlyOwner()` — **internal (callers: transferOwnership, setFeed, setPegged, setBounds, setSequencer)** — NONE
- `QuoteOracle.sol:119` `function transferOwnership(address to) external onlyOwner` — **owner (documented as the timelock)** — NONE
- `QuoteOracle.sol:131` `function setFeed(address quote, address aggregator, uint32 heartbeat, uint8 quoteDecimals) external onlyOwner` — **owner (documented as the timelock)** — NONE
- `QuoteOracle.sol:153` `function setPegged(address quote, uint8 dec) external onlyOwner` — **owner (documented as the timelock)** — NONE
- `QuoteOracle.sol:175` `function setBounds(address quote, uint128 minUsd, uint128 maxUsd) external onlyOwner` — **owner (documented as the timelock)** — NONE
- `QuoteOracle.sol:182` `function setSequencer(address feed, uint32 grace) external onlyOwner` — **owner (documented as the timelock)** — NONE
- `QuoteOracle.sol:202` `function usdPerRawUnit(address quote) external view returns (uint256 factor)` — **anyone** — NONE
- `QuoteOracle.sol:334` `function cachedUsdPerRawUnit(address quote) external returns (uint256)` — **anyone (permissionless, state-writing)** — none - no asset moves; the only effect is the cache write at `factor` (line 340)
- `QuoteOracle.sol:346` `function priceable(address quote) external view returns (bool)` — **anyone** — NONE
- `QuoteOracle.sol:350` `function _sequencerOk() internal view returns (bool)` — **internal (callers: usdPerRawUnit)** — NONE

**QuoteRotator** — `cauldron/QuoteRotator.sol`

- `QuoteRotator.sol:99` `constructor(address _registry, IPoolManager _poolManager)` — **deployer** — NONE
- `QuoteRotator.sol:125` `modifier onlyRegistry()` — **internal (callers: swapOnce)** — NONE
- `QuoteRotator.sol:130` `modifier onlyOwner()` — **internal (callers: transferOwnership, setVenue, setPlan, cancelPlan, setKeeperBps, setRotationSlipBps, setArbParams, setMaxArbNotionalUsd)** — NONE
- `QuoteRotator.sol:135` `function transferOwnership(address to) external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:190` `function setVenue(PoolKey calldata route, bool allowed) external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:197` `function isVenueAllowed(PoolKey calldata route) external view returns (bool)` — **anyone** — NONE
- `QuoteRotator.sol:216` `function setPlan( address from, address to, uint128 totalIn, uint128 sliceIn, uint256 minRate, uint32 interval ) external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:248` `function cancelPlan() external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:253` `function setKeeperBps(uint16 bps) external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:263` `function nextSliceSize() public view returns (uint256)` — **anyone** — NONE
- `QuoteRotator.sol:284` `function rotateStep(PoolKey calldata route) external returns (uint256 out)` — **anyone (permissionless keeper; the caller chooses only the venue, from the curated list)** — `_send` pays the keeper a share of the plan's `to` asset (line 317); the swap legs settle and take inside `_swap` (line 307)
- `QuoteRotator.sol:335` `function swapOnce( PoolKey calldata route, address from, address to, uint256 amountIn, uint256 minOut ) external onlyRegistry returns (uint256 out)` — **registry only** — `_swap` spends `amountIn` of the source quote and takes the destination quote inside the pool manager's unlock (line 392)
- `QuoteRotator.sol:405` `function setRotationSlipBps(uint16 bps) external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:425` `function _oracleFloor(address from, address to, uint256 amountIn) internal returns (uint256)` — **internal (single caller: swapOnce)** — none - a valuation only, no asset moves (DERIVED)
- `QuoteRotator.sol:485` `function setArbParams(address oracle, uint16 keeperBps, uint256 minProfitUsd) external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:495` `function setMaxArbNotionalUsd(uint256 maxNotionalUsd) external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:533` `function arbStep(PoolKey calldata cheap, PoolKey calldata dear, uint256 amountIn) external returns (uint256 profitUsd)` — **anyone (permissionless keeper)** — `_send` pays the keeper a cut of the received quote (line 613); the two swap legs settle and take inside the `unlock` (line 577)
- `QuoteRotator.sol:622` `function _usdLive(address quote, uint256 raw) internal view returns (uint256)` — **internal view (callers: _oracleFloor, arbStep)** — none - a staticcall valuation (DERIVED)
- `QuoteRotator.sol:653` `function withdraw(address asset, address to, uint256 amount) external` — **registry or owner (either satisfies the check; the gate is on this side)** — `_send` moves the named asset — native or ERC20 — to an arbitrary destination (line 656)
- `QuoteRotator.sol:664` `function _swap(PoolKey calldata route, address from, address to, uint256 size) internal returns (uint256 out)` — **internal (callers: rotateStep, swapOnce)** — the actual transfers happen in the callback this opens, at `unlock` (line 669)
- `QuoteRotator.sol:673` `function unlockCallback(bytes calldata data) external returns (bytes memory)` — **poolManager (the immutable address)** — pays the pool through `_settle` (line 695) and receives the bought asset through `take` (line 696)
- `QuoteRotator.sol:705` `function _arbCallback(bytes calldata data) internal returns (bytes memory)` — **internal (callers: unlockCallback)** — settles the spent quote out of this contract at `_settle` (line 727) and receives the sold quote at `take` (line 728)
- `QuoteRotator.sol:732` `function _settle(address cur, uint256 amount) internal` — **internal (callers: unlockCallback, _arbCallback)** — sends native to the pool manager at `settle` (line 734); ERC20 to the pool manager at `_safeTransfer` (line 737)
- `QuoteRotator.sol:742` `function _send(address cur, address to, uint256 amount) internal` — **internal (callers: rotateStep, arbStep, withdraw)** — sends native to an arbitrary recipient at `call` (line 745); ERC20 transfer at `_safeTransfer` (line 748)
- `QuoteRotator.sol:755` `function _safeTransfer(address token, address to, uint256 amount) internal` — **internal (callers: _settle, _send)** — `transfer` moves ERC20 balance out of this contract (line 764)
- `QuoteRotator.sol:768` `function _routeMatches(PoolKey calldata route, address from, address to) internal pure returns (bool)` — **internal (callers: rotateStep, swapOnce)** — NONE
- `QuoteRotator.sol:778` `function _balanceOf(address asset) internal view returns (uint256)` — **internal (callers: nextSliceSize)** — NONE
- `QuoteRotator.sol:782` `function _allowed(address quote) internal view returns (bool)` — **internal (callers: setPlan, rotateStep, swapOnce, arbStep)** — NONE
- `QuoteRotator.sol:789` `receive() external payable` — **anyone** — `receive` receives native with no accounting (line 789)

**ITreasuryGovernor (declared in RedemptionExt.sol)** — `cauldron/RedemptionExt.sol`

- `RedemptionExt.sol:45` `function allowance() external view returns (address quote, uint16 remainingBps)` — **anyone (declaration only; the implementation is the address stored in treasuryGovernor)** — NONE
- `RedemptionExt.sol:46` `function consume(uint16 bps, bool fromPrimary) external` — **anyone (declaration only; the implementation gates on its own caller)** — NONE
- `RedemptionExt.sol:49` `function migrationMandateSpent() external view returns (bool)` — **anyone (declaration only; the implementation is the address stored in treasuryGovernor)** — NONE

**IQuoteRotator (declared in RedemptionExt.sol)** — `cauldron/RedemptionExt.sol`

- `RedemptionExt.sol:53` `function swapOnce(PoolKey calldata route, address from, address to, uint256 amountIn, uint256 minOut) external returns (uint256)` — **anyone (declaration only; the implementation gates on its own caller)** — NONE
- `RedemptionExt.sol:55` `function withdraw(address asset, address to, uint256 amount) external` — **anyone (declaration only; the implementation gates on its own caller)** — NONE

**IHookVolume (declared in RedemptionExt.sol)** — `cauldron/RedemptionExt.sol`

- `RedemptionExt.sol:59` `function linkVolume(PoolId primary, PoolId secondary) external` — **anyone (declaration only; the implementation gates on its own caller)** — NONE

**RedemptionExt** — `cauldron/RedemptionExt.sol`

- `RedemptionExt.sol:78` `function redeemOgFren(uint256 mifrenTokenId) external nonReentrant returns (uint256 amount)` — **anyone holding a genesis MiFren (the gate is on the facet side, under the registry's delegatecall)** — `claimFromReserve` pays the redeemer in the generation's token out of the out-of-range reserve position (line 95)
- `RedemptionExt.sol:115` `function buyTreasuryOgFren(uint256 mifrenTokenId) external nonReentrant returns (uint256 paid)` — **anyone (the facet holds the checks; reached through the registry forwarder)** — `_pullGrow` collects twice the live floor in the generation's token from the buyer (line 124)
- `RedemptionExt.sol:136` `function donateToReserve(uint256 amount) external nonReentrant` — **anyone** — `_pullGrow` pulls the caller's generation tokens into the reserve (line 139)
- `RedemptionExt.sol:147` `function materializeLegacyReserve() external nonReentrant returns (uint256 added)` — **anyone (keeper or frontend)** — `materializeLegacy` moves the hook's held buyback tokens into the shared reserve position (line 151)
- `RedemptionExt.sol:165` `function _pullGrow(address from, uint256 amount) private returns (uint256 added)` — **internal (callers: buyTreasuryOgFren, donateToReserve)** — ERC20 `transferFrom` pulls the generation token from the payer into the registry (line 167)
- `RedemptionExt.sol:260` `function setRotationWiring(address rotator, address governor) external onlyOwner` — **owner (the registry's own owner slot; the gate is on the FACET side, the registry stub is ungated)** — NONE
- `RedemptionExt.sol:269` `function rotateSlice( uint16 sliceBps, uint256 minOut, PoolKey calldata route ) external returns (uint256 moved, uint256 positionId)` — **anyone (permissionless within the approved envelope)** — all value movement happens in the call it forwards to, at `rotateSliceFrom` (line 274)
- `RedemptionExt.sol:280` `function rotateSliceFrom( uint8 fromLeg, uint16 sliceBps, uint256 minOut, PoolKey calldata route ) public returns (uint256 moved, uint256 positionId)` — **anyone (public and ungated) - reached through the registry's forwarder, running on the registry's storage** — `removePartial` takes a slice out of the source pair (line 385), `sendAsset` hands the quote side to the rotator (line 397) and `openOrAddPair` redeploys it into the destination pair (line 404)
- `RedemptionExt.sol:634` `function floorClaimableNow() external view returns (bool claimable, uint256 perFren)` — **anyone** — NONE
- `RedemptionExt.sol:653` `function claimByBurnUpTo(uint256 fromGen, uint256 maxAmount) external returns (uint256 claimedAmount)` — **anyone while no claim gate is set; once set, only the claim gate or the perp engine** — `migrateUpTo` burns the caller's old-generation tokens and delivers live tokens out of the reserve band (line 669)
- `RedemptionExt.sol:677` `function legCount(uint256 gen) external view returns (uint256)` — **anyone** — NONE
- `RedemptionExt.sol:682` `function legAt(uint256 gen, uint256 i) external view returns (address quote, uint256 positionId, PoolKey memory key)` — **anyone** — NONE
- `RedemptionExt.sol:692` `function _recordLeg(uint256 gen, address quote, uint256 positionId, PoolKey memory key) private` — **internal (callers: rotateSliceFrom)** — NONE
- `RedemptionExt.sol:732` `function recoverLegs(uint256 gen) public returns (uint256 quoteOut, uint256 tokenOut)` — **anyone (public and ungated on the caller) - restricted to PAST generations** — the unwind and the booking both happen in the callees, at `_recoverLegs` (line 734) and `_bookLegProceeds` (line 735)
- `RedemptionExt.sol:759` `function _bookLegProceeds(uint256 gen, uint256 quoteOut, uint256 tokenOut) internal` — **internal (single caller: recoverLegs, the retry path)** — no transfer - it only marks balances this contract already holds as sweepable, at `legProceeds` (line 762)
- `RedemptionExt.sol:783` `function recoverLegsAtTeardown(uint256 gen) external returns (uint256, uint256)` — **anyone by ABI - in practice only the registry's internal delegatecall, because no registry stub forwards this selector** — the unwind happens in `_recoverLegs` (line 784)
- `RedemptionExt.sol:787` `function _recoverLegs(uint256 gen) private returns (uint256 quoteOut, uint256 tokenOut)` — **private (callers: recoverLegs, recoverLegsAtTeardown)** — `removeAll` unwinds each leg's position, delivering both sides into this contract (line 824)
- `RedemptionExt.sol:845` `function legProceedsOf(address asset) external view returns (uint256)` — **anyone** — NONE
- `RedemptionExt.sol:882` `function sweepLegProceeds(address asset, address to) external onlyOwner returns (uint256 amount)` — **owner (the registry's own owner slot; the gate is on the FACET side, the registry stub is ungated)** — `sendAsset` moves the whole booked balance of the asset to an owner-chosen destination (line 890)
