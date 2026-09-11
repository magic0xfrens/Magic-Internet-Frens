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
| `plan.totalIn` (QuoteRotator.sol:66) | raw units of `plan.from` | `setPlan` writing `totalIn` (QuoteRotator.sol:230) | never; cleared by `delete plan` (QuoteRotator.sol:246) |
| `plan.sliceIn` (QuoteRotator.sol:67) | raw units of `plan.from` | `setPlan` writing `sliceIn` (QuoteRotator.sol:231) | cleared (QuoteRotator.sol:246) |
| `plan.doneIn` (QuoteRotator.sol:68) | raw units of `plan.from` | `rotateStep` adding to `doneIn` (QuoteRotator.sol:301) | zeroed by `setPlan` zeroing `doneIn` (QuoteRotator.sol:232) and by `cancelPlan` deleting `plan` (QuoteRotator.sol:246) |
| `plan.gotOut` (QuoteRotator.sol:69) | raw units of `plan.to`, **gross of the keeper fee** | `rotateStep` adding to `gotOut` (QuoteRotator.sol:310) | zeroed at QuoteRotator.sol:233 and QuoteRotator.sol:246 |
| `plan.minRate` (QuoteRotator.sol:72) | raw `to` per 1e18 raw `from` | `setPlan` writing `minRate` (QuoteRotator.sol:234) | cleared (QuoteRotator.sol:246) |
| `keeperBps` (QuoteRotator.sol:85) | bps of slice output | `setKeeperBps` writing `keeperBps` (QuoteRotator.sol:251) | same setter, ceiling 100 (QuoteRotator.sol:250) |
| `rotationSlipBps` (QuoteRotator.sol:373) | bps off the oracle floor | `setRotationSlipBps` writing `rotationSlipBps` (QuoteRotator.sol:380) | same setter, ceiling 2000 (QuoteRotator.sol:379) |
| `arbKeeperBps` (QuoteRotator.sol:419) | bps of arb profit | `setArbParams` writing `arbKeeperBps` (QuoteRotator.sol:451) | same setter, ceiling 2000 (QuoteRotator.sol:449) |
| `minArbProfitUsd` (QuoteRotator.sol:424) | USD 1e18 | `setArbParams` writing `minArbProfitUsd` (QuoteRotator.sol:452) | same setter, unbounded |
| `maxArbNotionalUsd` (QuoteRotator.sol:437) | USD 1e18 | `setMaxArbNotionalUsd` writing `maxArbNotionalUsd` (QuoteRotator.sol:459) | same setter; 0 disables the bound (QuoteRotator.sol:544) |
| `arbUsdThisBlock` (QuoteRotator.sol:444) | USD 1e18 | `arbStep` storing `arbUsdThisBlock` (QuoteRotator.sol:548) | reset to 0 on a new block (QuoteRotator.sol:545) |

Native/ERC20 in: `receive` (QuoteRotator.sol:718) and `poolManager.take` (QuoteRotator.sol:632, QuoteRotator.sol:664).
Native/ERC20 out: `_send` (QuoteRotator.sol:681, QuoteRotator.sol:684) driven from `_send` (QuoteRotator.sol:313), `_send` (QuoteRotator.sol:559) and `_send` (QuoteRotator.sol:592); plus `_settle` to the pool manager (QuoteRotator.sol:670, QuoteRotator.sol:673).

### `QuoteOracle` (holds no value)

| Field | Denomination | Increases | Decreases |
| --- | --- | --- | --- |
| the `factor` member of `cache` (QuoteOracle.sol:281) | USD 1e18 per RAW unit | `fresh` (QuoteOracle.sol:310), only when the refresh is non-zero | never — a failed refresh keeps the old value |
| `cache[q].at` (QuoteOracle.sol:280) | unix seconds | every call (QuoteOracle.sol:309), success or not | never |
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
| `genesisReserveOutstanding` (CauldronBase.sol:379) | raw units of the generation token | `genesisReserveOutstanding` (RedemptionExt.sol:182) | `genesisReserveOutstanding` (RedemptionExt.sol:91), and only when it already covers the floor |
| `genesisPending` (RedemptionExt.sol:158) | raw units of the generation token | `genesisPending` (RedemptionExt.sol:158) | not in this cluster |
| `legProceeds` (RedemptionExt.sol:743) | raw units of that asset | `legProceeds` (RedemptionExt.sol:743) | zeroed in full by `legProceeds` (RedemptionExt.sol:801) |
| `legs` (RedemptionExt.sol:682) | set of positions | pushed at RedemptionExt.sol:682, id overwritten at RedemptionExt.sol:680 | swap-and-pop at RedemptionExt.sol:746 and RedemptionExt.sol:747 |
| `generationQuote[gen]` (RedemptionExt.sol:505) | address | flipped at RedemptionExt.sol:505 | also written on relaunch at `generationQuote` (CauldronRegistry.sol:982) |

---

## B. Balance vs counter — where they can diverge

- **`plan.doneIn` is not backed by a balance.** `nextSliceSize` clamps the slice to what is actually held (QuoteRotator.sol:270), while `withdraw` can remove that balance at any time (QuoteRotator.sol:592) without touching the plan. A plan can therefore read as partially done with nothing converted, or sit at size 0 and revert `TooSoon` (QuoteRotator.sol:285) rather than announcing an empty treasury.
- **`plan.gotOut` overstates custody by `keeperBps`.** The received amount is booked whole (QuoteRotator.sol:310) and the keeper's cut leaves three lines later (QuoteRotator.sol:313).
- **`arbUsdThisBlock` has no balance behind it at all**; its reset is keyed on `block.number` (QuoteRotator.sol:545), so it measures a block, and it is written AFTER the swap has already settled (QuoteRotator.sol:548).
- **`QuoteRotator` keeps no per-plan segregation.** `receive` (QuoteRotator.sol:718) accepts anything, `balanceOf` (QuoteRotator.sol:708) is a raw balance read, and `_send` (QuoteRotator.sol:592) can move any asset to anyone the owner or registry names.
- **`cache[q].factor` is a price, never reconciled**; a refresh that fails still advances `cache[q].at` (QuoteOracle.sol:309), so the staleness window restarts with no good answer.
- **`CauldronVault.redeemed` vs balance**: both fall together (CauldronVault.sol:106, CauldronVault.sol:109), but `outstanding` recomputes the numerator from the collection's own `totalMinted` (CauldronVault.sol:56), so any burn path outside `burnFromVault` (CauldronVault.sol:107) moves the floor without moving `redeemed`.
- **`genesisReserveOutstanding` vs the reserve position**: the debit is conditional (RedemptionExt.sol:91) and the delivery check tolerates 1e12 (RedemptionExt.sol:104), so the counter can sit slightly above or below the LP. On the credit side only the amount the library reports as actually added is booked (RedemptionExt.sol:182), and a zero add reverts (RedemptionExt.sol:181).
- **`legProceeds` is backed by the registry's balance** measured from what `removeAll` returned (RedemptionExt.sol:742), and the sweep zeroes the booking before transferring (RedemptionExt.sol:801).

---

## C. Authority map

| Gate | Held by | Guards | Can it rotate? | Can it renounce? | Dead-end risk |
| --- | --- | --- | --- | --- | --- |
| `QuoteRotator.onlyOwner` (QuoteRotator.sol:126) | `owner` (QuoteRotator.sol:79), the treasury | `transferOwnership` (QuoteRotator.sol:131), `setVenue` (QuoteRotator.sol:186), `onlyOwner` (QuoteRotator.sol:219), `cancelPlan` (QuoteRotator.sol:244), `setKeeperBps` (QuoteRotator.sol:249), `setRotationSlipBps` (QuoteRotator.sol:378), `setArbParams` (QuoteRotator.sol:448), `setMaxArbNotionalUsd` (QuoteRotator.sol:458) | yes, one-step (QuoteRotator.sol:131) | no dedicated function | yes — no zero check at QuoteRotator.sol:131; config freezes while registry-driven execution keeps working |
| `QuoteRotator.onlyRegistry` (QuoteRotator.sol:121) | immutable `registry` (QuoteRotator.sol:96) | `onlyRegistry` (QuoteRotator.sol:337) | no | no | permanent by construction |
| `QuoteRotator.withdraw` inline check (QuoteRotator.sol:590) | registry **or** owner | `withdraw` | follows the two above | no | no |
| `QuoteRotator.unlockCallback` inline check (QuoteRotator.sol:610) | immutable `poolManager` (QuoteRotator.sol:97) | `unlockCallback` | no | no | permanent |
| ungated | anyone | `rotateStep` (QuoteRotator.sol:280), `arbStep` (QuoteRotator.sol:496), `nextSliceSize` (QuoteRotator.sol:259), `isVenueAllowed` (QuoteRotator.sol:193), `receive` (QuoteRotator.sol:718) | — | — | — |
| `QuoteOracle.onlyOwner` (QuoteOracle.sol:114) | `owner` (QuoteOracle.sol:96), documented as the timelock | `transferOwnership` (QuoteOracle.sol:119), `onlyOwner` (QuoteOracle.sol:133), `setPegged` (QuoteOracle.sol:153), `setBounds` (QuoteOracle.sol:175), `setSequencer` (QuoteOracle.sol:182) | yes (QuoteOracle.sol:119) | no dedicated function | yes — zero is storable, freezing every feed |
| `MockAggregator.onlyOwner` (MockAggregator.sol:60) | `owner` (MockAggregator.sol:37) | `transferOwnership`, `peg`, `setStale`, `setDown` (MockAggregator.sol:65, MockAggregator.sol:68, MockAggregator.sol:76, MockAggregator.sol:82) | yes (MockAggregator.sol:65) | no | yes — zero is storable |
| `CauldronVault` registry check (CauldronVault.sol:117) | immutable `registry` (CauldronVault.sol:67) | `close` | no | no | permanent |
| `CauldronVault` owner check (CauldronVault.sol:97) | the NFT's holder | `redeem` | n/a | n/a | n/a |
| `RedemptionExt.onlyOwner` (Ownable, via `CauldronBase`) | the REGISTRY's owner slot | `setRotationWiring` (RedemptionExt.sol:260), `onlyOwner` (RedemptionExt.sol:607), `sweepLegProceeds` (RedemptionExt.sol:794) | `transferOwnership` is live | **no** — `renounceOwnership` reverts (CauldronBase.sol:417) | no |
| ungated facet entries | anyone | `rotateSlice` (RedemptionExt.sol:269), `rotateSliceFrom` (RedemptionExt.sol:280), `recoverLegs` (RedemptionExt.sol:699), `donateToReserve` (RedemptionExt.sol:136), `materializeLegacyReserve` (RedemptionExt.sol:147), the three views | — | — | — |

**How the forwarders reach the facet, and which side holds the gate.** Every facet entry is reached by `CauldronRegistry` copying the full calldata into a `delegatecall` at `delegatecall` (CauldronRegistry.sol:1456), reached from `_forwardToExt` (CauldronRegistry.sol:1451). The registry's own stubs carry **no** modifiers — `setRotationWiring` (CauldronRegistry.sol:272), `sweepLegProceeds` (CauldronRegistry.sol:282), `rotateSlice` (CauldronRegistry.sol:238), `rotateSliceFrom` (CauldronRegistry.sol:262), `redeemOgFren` (CauldronRegistry.sol:1383), `buyTreasuryOgFren` (CauldronRegistry.sol:1389), `donateToReserve` (CauldronRegistry.sol:1395), `materializeLegacyReserve` (CauldronRegistry.sol:1401) and the three views at `floorClaimableNow` (CauldronRegistry.sol:1418), `legCount` (CauldronRegistry.sol:1423) and `legAt` (CauldronRegistry.sol:1428). The only check on the registry side is that a facet is wired at `NotConfigured` (CauldronRegistry.sol:1453). `recoverLegs` has no stub and is reached only by the compiler-built selector at `RECOVER_LEGS` (CauldronRegistry.sol:1607). **Two facet functions have no forwarder at all** — `completeRotation` (RedemptionExt.sol:605) and `legProceedsOf` (RedemptionExt.sol:757), the latter deliberately per the note at `legProceedsOf` (CauldronRegistry.sol:284) — and the registry has no catch-all fallback (CauldronRegistry.sol:1408), so neither can run against the registry's storage.

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
| `latestRoundData` (QuoteOracle.sol:328) | sequencer feed | none | inside try/catch |
| `usdPerRawUnit` (QuoteOracle.sol:308) | itself, via `this.` | none | before `cache` is written (QuoteOracle.sol:309) |
| `unlock` (QuoteRotator.sol:605) | pool manager | drives settle/take | AFTER `lastStepAt`/`doneIn` (QuoteRotator.sol:300, QuoteRotator.sol:301) |
| `swap` (QuoteRotator.sol:620) | pool manager | delta only | inside the lock |
| `_settle` (QuoteRotator.sol:631) then `take` (QuoteRotator.sol:632) | pool manager | native/ERC20 out then in | settle before take |
| `unlock` (QuoteRotator.sol:526) | pool manager | both arb legs | BEFORE the per-block counter is written (QuoteRotator.sol:548) — interaction precedes effect |
| `swap` (QuoteRotator.sol:646), `swap` (QuoteRotator.sol:656) | pool manager | delta only | inside one lock |
| `_settle` (QuoteRotator.sol:663) then `take` (QuoteRotator.sol:664) | pool manager | spends the cheap quote, receives the dear quote | settle before take |
| `settle` (QuoteRotator.sol:670) | pool manager | **native out** | — |
| `sync` (QuoteRotator.sol:672), `_safeTransfer` (QuoteRotator.sol:673), `settle` (QuoteRotator.sol:674) | pool manager / token | **ERC20 out** | v4 sync-transfer-settle |
| `call` (QuoteRotator.sol:681) | arbitrary recipient | **native out, all gas** | last in `rotateStep`; last in `arbStep`; only statement in `withdraw` |
| `call` (QuoteRotator.sol:693) | arbitrary token | **ERC20 out** | — |
| `call` (QuoteRotator.sol:567) | the configured oracle, state-changing | none | before the floor check (QuoteRotator.sol:366) and before the arb counter (QuoteRotator.sol:548) |
| `staticcall` (QuoteRotator.sol:714) | the registry | none | fails closed |
| `balanceOf` (QuoteRotator.sol:708) | arbitrary token | none | not wrapped — a reverting token blocks the plan |
| `allowance` (RedemptionExt.sol:303) | treasury governor | none | before anything moves |
| `removePartial` (RedemptionExt.sol:363) | `PoolOps` (delegatecall) | liquidity out of the pair, into the registry | first move |
| `sendAsset` (RedemptionExt.sol:375) | `PoolOps` (delegatecall) | **quote side out to the rotator** | before the swap |
| `swapOnce` (RedemptionExt.sol:376) | `QuoteRotator` | conversion | — |
| `withdraw` (RedemptionExt.sol:377) | `QuoteRotator` | **proceeds back in** | same transaction |
| `openOrAddPair` (RedemptionExt.sol:382) | `PoolOps` (delegatecall) | **both sides out into the new position** | — |
| `linkVolume` (RedemptionExt.sol:396) | the hook | none | refuses while the perp book is open |
| `consume` (RedemptionExt.sol:437) | treasury governor | none | **after every interaction** — the envelope is spent last |
| `migrationMandateSpent` (RedemptionExt.sol:504) | treasury governor | none | decides the write at RedemptionExt.sol:505 |
| `perpEngine` (RedemptionExt.sol:539), `syncGeneration` (RedemptionExt.sol:540) | hook, perp engine | none | best-effort, in try/catch |
| `ownerOf` (RedemptionExt.sol:84) / `custodyTransfer` (RedemptionExt.sol:92) / `claimFromReserve` (RedemptionExt.sol:95) | MiFrens, `PoolOps` | **generation token out to the redeemer** | effects at RedemptionExt.sol:91 and RedemptionExt.sol:92 precede the payout |
| `transferFrom` (RedemptionExt.sol:167) / `addToReserve` (RedemptionExt.sol:168) | token, `PoolOps` | **token in, then into the reserve** | counter credited after, at RedemptionExt.sol:182 |
| `materializeLegacy` (RedemptionExt.sol:151) | `PoolOps` | hook-held tokens into the reserve | counter after, at RedemptionExt.sol:158 |
| `getSlot0` (RedemptionExt.sol:652) | pool manager | none | view |
| `removeAll` (RedemptionExt.sol:736) | `PoolOps` | **each leg's liquidity back to the registry** | booking and pop after, at RedemptionExt.sol:743 and RedemptionExt.sol:747 |
| `sendAsset` (RedemptionExt.sol:802) | `PoolOps` | **booked asset out** | AFTER the booking is zeroed (RedemptionExt.sol:801) |

`rotateSliceFrom` (RedemptionExt.sol:280), `rotateSlice` (RedemptionExt.sol:269) and `recoverLegs` (RedemptionExt.sol:699) carry **no** `nonReentrant` modifier, and neither do the registry stubs that reach them; `QuoteRotator` has no reentrancy guard anywhere.

---

## E. Loops

Only two loops exist in the cluster; both are in `RedemptionExt` and both are bounded by `generationLegs[gen].length`.

| Loop | Bound | Who can grow the bound |
| --- | --- | --- |
| `for` in the `i < n` scan (RedemptionExt.sol:679) | the current leg count, read at RedemptionExt.sol:678 | only a push at RedemptionExt.sol:682, which happens once per DISTINCT destination quote; repeated slices into the same pair overwrite at RedemptionExt.sol:680 |
| `while` in the `while (i > 0)` walk (RedemptionExt.sol:733) | the leg count read at RedemptionExt.sol:732, descending | same push; each success removes an entry at RedemptionExt.sol:747 |

A destination must pass `allowedQuote` (RedemptionExt.sol:322) before a leg can be created, so the maximum leg count is the size of the owner-curated allowlist written at `setAllowedQuote` (CauldronRegistry.sol:290) — a permissionless caller can create legs, but only for assets the owner has already admitted. `recoverLegs` runs inside relaunch (CauldronRegistry.sol:1607); its per-leg `catch` (RedemptionExt.sol:749) keeps one bad leg from blocking the rest, and because the walk is descending while removal is swap-and-pop, an entry moved into the current slot is not revisited in that pass.

`QuoteRotator`, `QuoteOracle`, `CauldronVault` and both mocks contain no loops.

---

## F. Denomination and units

- **`QuoteOracle` is the only place decimals are normalised.** The feed's own decimals are read per call at `feedDec` (QuoteOracle.sol:248) and folded to a 1e18-per-WHOLE-token figure at `perWhole` (QuoteOracle.sol:256); the token's decimals are stored once at `quoteDecimals` (QuoteOracle.sol:69), taken either from the caller or from the token at `decimals` (QuoteOracle.sol:138) / `decimals` (QuoteOracle.sol:155); the final conversion to **USD 1e18 per RAW unit** happens at `factor` (QuoteOracle.sol:277), multiplying before dividing. The pegged shortcut does the same conversion with a literal dollar at `pegged` (QuoteOracle.sol:207).
- **Sanity bounds are in whole-token USD 1e18**, compared against `perWhole` (QuoteOracle.sol:267, QuoteOracle.sol:268) — not against the per-raw-unit factor.
- **`QuoteRotator.plan.minRate` is raw `to` per 1e18 raw `from`.** The floor is `size * minRate / WAD` (QuoteRotator.sol:306) where `size` is in raw `from` units — so for an 18-decimal source the comment's "per whole unit" (QuoteRotator.sol:70) holds, and for a 6-decimal source the same literal means per 1e18 raw units, i.e. per 1e12 whole tokens.
- **`_oracleFloor` is decimals-agnostic by routing through USD**: source to USD at `inUsd` (QuoteRotator.sol:402), destination priced per 1e18 raw units at `perUnitTo` (QuoteRotator.sol:404), and the division back at `fair` (QuoteRotator.sol:406) cancels the scale.
- **`_usd` multiplies the raw amount by the factor and divides by 1e18**, at `raw` (QuoteRotator.sol:572) — USD 1e18 out, any decimals in.
- **The arb keeper cut mixes units correctly**: `received * profitUsd * arbKeeperBps / (outUsd * BPS)` (QuoteRotator.sol:558) is raw-`out` units, because `received / outUsd` is units per USD.
- **`sliceBps` is a share of CURRENT liquidity**, not of the original position (RedemptionExt.sol:210), so successive slices compound rather than sum; the per-call ceiling is 2500 (RedemptionExt.sol:576) inside the library's own 5000 cap.
- **`recoverLegs` keeps one denomination per sum** by matching on the primary pool's own `currency0` at `matchQuote` (RedemptionExt.sol:730) rather than on the possibly-flipped `generationQuote` (RedemptionExt.sol:505); foreign assets go to `legProceeds` (RedemptionExt.sol:743) instead of into the returned figure.
- **`CauldronVault` is native-wei only** (CauldronVault.sol:80); the registry wires the hook's vault to zero on both collection paths (CauldronRegistry.sol:1171, CauldronRegistry.sol:1195), so its balance stays zero and `redeem` reports that explicitly at `UnifiedFloorActive` (CauldronVault.sol:102).
- `MockAggregator` fixes 8 decimals to match Chainlink (MockAggregator.sol:40); `MockQuoteToken` takes its decimals at construction (MockQuoteToken.sol:21).

---

## G. `unchecked` blocks and rounding direction

**There are no `unchecked` blocks in any of the six files.** The only occurrence of the word is prose at `unchecked` (QuoteRotator.sol:689). All arithmetic is Solidity 0.8 checked arithmetic, so every overflow and every underflow reverts; the places that could underflow are guarded explicitly instead: the saturating subtractions at `eligible` (CauldronVault.sol:57) and at `redeemed` (CauldronVault.sol:58), the conditional debit at `genesisReserveOutstanding` (RedemptionExt.sol:91), the future-timestamp refusals at `updatedAt` (QuoteOracle.sol:245) and `startedAt` (QuoteOracle.sol:335).

Every division truncates toward zero. Directions that matter:

| Division | Rounds | Effect |
| --- | --- | --- |
| `balance / n` (CauldronVault.sol:80, CauldronVault.sol:100) | down | the remainder stays in the vault, accruing to the survivors |
| `genesisReserveOutstanding / shares` (CauldronBase.sol:379) | down | floor understated by at most 1 wei per fren |
| `10 ** quoteDecimals` divisor (QuoteOracle.sol:207, QuoteOracle.sol:277) | down | price understated |
| `answer / 10 ** (feedDec - 18)` (QuoteOracle.sol:258) | down | only for feeds with more than 18 decimals |
| `size * minRate / WAD` (QuoteRotator.sol:306) | down | the required minimum is understated — favours the fill |
| `out * keeperBps / BPS` (QuoteRotator.sol:312) | down | keeper fee understated — favours the treasury |
| `inUsd * 1e18 / perUnitTo` and `fair * (BPS - slip) / BPS` (QuoteRotator.sol:406, QuoteRotator.sol:407) | down | the oracle floor is understated — favours the fill |
| `raw * f` divided by 1e18 (QuoteRotator.sol:572) | down | USD understated; on the arb path that understates BOTH legs |
| `received * profitUsd * arbKeeperBps / (outUsd * BPS)` (QuoteRotator.sol:558) | down | keeper cut understated |

Narrowing casts (not rounding, but silent on overflow only because the values are checked upstream): `uint64(block.timestamp)` and `uint128(size)` at `doneIn` (QuoteRotator.sol:301), `uint128(out)` at `gotOut` (QuoteRotator.sol:310), and the `uint256(uint128(...))` delta reads at `got` (QuoteRotator.sol:630), `spent` (QuoteRotator.sol:651), `got` (QuoteRotator.sol:652) and `received` (QuoteRotator.sol:661).

---

## H. Comment-vs-code observations

Recorded as pairs; no judgement attached.

1. `hook` (CauldronVault.sol:71) says fees flow in from the hook — `setVault` (CauldronRegistry.sol:1171) and `setVault` (CauldronRegistry.sol:1195) both wire the hook's vault to address(0).
2. `updatedAt` (MockAggregator.sol:27) says the feed returns `block.timestamp` — `ts` (MockAggregator.sol:91) returns the epoch value 1 whenever `stale` is set.
3. `cached` (QuoteOracle.sol:283) describes the constant as how long a cached price stays good — `c` (QuoteOracle.sol:309) restamps the timestamp even when the refresh came back unusable, so the early-return at `factor` (QuoteOracle.sol:307) serves the old value for another full window.
4. `cap` (QuoteRotator.sol:455) calls the bound a per-call notional cap — `spentThisBlock` (QuoteRotator.sol:546) accumulates across every call in a block.
5. `None` (QuoteRotator.sol:488) says no capital is needed because only the net delta settles — `_settle` (QuoteRotator.sol:663) pays the cheap pool's `currency0` in full from this contract's balance while `take` (QuoteRotator.sol:664) receives a different asset.
6. `Owner` (QuoteRotator.sol:582) says `withdraw` is owner-only — `registry` (QuoteRotator.sol:590) accepts the registry too, as the later note at `rotateSlice` (QuoteRotator.sol:586) admits.
7. `capital` (QuoteRotator.sol:637) repeats the no-capital claim for the arb callback — `_settle` (QuoteRotator.sol:663) shows only the TOKEN leg nets.
8. `CHECKED` (QuoteRotator.sol:688) says an unchecked transfer would report success while nothing moved — `ret` (QuoteRotator.sol:694) accepts an empty return as success, which is also what a call to a codeless address produces; there is no code-length check.
9. `registration` (RedemptionExt.sol:43) documents the hook's generation-volume registration — `ITreasuryGovernor` (RedemptionExt.sol:44) is the treasury envelope interface; the volume registration is `linkVolume` (RedemptionExt.sol:59).
10. `debit` (RedemptionExt.sol:88) says the reserve accounting is debited first — `genesisReserveOutstanding` (RedemptionExt.sol:91) debits only when the recorded reserve already covers the floor, and otherwise pays out without debiting.
11. `sliceBps` (RedemptionExt.sol:210) documents slice, floor and route parameters — the next declaration, `setRotationWiring` (RedemptionExt.sol:260), takes a rotator and a governor.
12. `DRAINED` (RedemptionExt.sol:252) describes a dust threshold for declaring the primary drained — `migrationMandateSpent` (RedemptionExt.sol:504) decides redenomination from the mandate flag alone, and `PRIMARY_DRAINED_DUST` (RedemptionExt.sol:258) is read nowhere.
13. `relaunch` (RedemptionExt.sol:441) puts the registry's other write of the generation quote at line 917 — the write is at `generationQuote` (CauldronRegistry.sol:982).
14. `rebirth` (RedemptionExt.sol:690) says `recoverLegs` is safe to call directly afterwards — no registry stub exists for that selector; it is reached only through `RECOVER_LEGS` (CauldronRegistry.sol:1607), so a direct call lands on the facet's own empty storage.

---

## The rotation state machine

### Machine 1 — the scheduled plan, inside `QuoteRotator`

State lives entirely in one struct, `plan` (QuoteRotator.sol:77).

| State | Test | Entered by | Gate |
| --- | --- | --- | --- |
| NONE | `plan.totalIn == 0` (QuoteRotator.sol:261, QuoteRotator.sol:282) | deployment default; `delete plan` at QuoteRotator.sol:246 | `onlyOwner` (QuoteRotator.sol:244) for the delete |
| ARMED | `totalIn != 0` and `lastStepAt == 0` (QuoteRotator.sol:266) | `setPlan` writes the whole struct at QuoteRotator.sol:227 | `onlyOwner` (QuoteRotator.sol:219) |
| RUNNING | `lastStepAt != 0`, `doneIn < totalIn` | `rotateStep` stamps `lastStepAt` (QuoteRotator.sol:300) and adds to `doneIn` (QuoteRotator.sol:301) | **ungated** (QuoteRotator.sol:280); the route must be curated (QuoteRotator.sol:295) |
| COOLING | `block.timestamp < lastStepAt + interval` (QuoteRotator.sol:266) | the same stamp | — |
| FINISHED | `doneIn >= totalIn` (QuoteRotator.sol:261) | accumulation at QuoteRotator.sol:301 | — |
| CANCELLED | back to NONE | `cancelPlan` deleting `plan` (QuoteRotator.sol:246) | `onlyOwner` (QuoteRotator.sol:244) |

`setPlan` is the only writer of `from`, `to`, `totalIn`, `sliceIn`, `minRate` and `interval`, and it can be called from ANY state — overwriting a live plan resets `doneIn` and `gotOut` to zero in the same literal (QuoteRotator.sol:232, QuoteRotator.sol:233). A step is possible only when all five of these hold: a plan exists (QuoteRotator.sol:282), the size is non-zero (QuoteRotator.sol:285), the destination is allowlisted (QuoteRotator.sol:286), the key trades the pair (QuoteRotator.sol:287) and the key is curated (QuoteRotator.sol:295).

Two side machines sit beside it:

- **Venue allowlist** — `allowedVenue` (QuoteRotator.sol:179), flipped either way by `allowedVenue` (QuoteRotator.sol:188) under `onlyOwner` (QuoteRotator.sol:186); read by all three spending paths (QuoteRotator.sol:295, QuoteRotator.sol:355, QuoteRotator.sol:516). Unset means nothing executes.
- **Arb throttle** — `arbBlock` (QuoteRotator.sol:443) and `arbUsdThisBlock` (QuoteRotator.sol:444). Transition: on a new `block.number` both reset (QuoteRotator.sol:545), then the running total accumulates (QuoteRotator.sol:546) and is stored (QuoteRotator.sol:548). Trigger: `arbStep`, ungated (QuoteRotator.sol:496). Gate: only active while `maxArbNotionalUsd != 0` (QuoteRotator.sol:544).

### Machine 2 — the live rotation, inside `RedemptionExt` on the registry's storage

| State variable | Declared | Written | Trigger | Gate |
| --- | --- | --- | --- | --- |
| `quoteRotator` | CauldronBase.sol:347 | RedemptionExt.sol:262 | `setRotationWiring` | `onlyOwner` on the facet (RedemptionExt.sol:260); the registry stub is ungated (CauldronRegistry.sol:272) |
| `treasuryGovernor` | CauldronBase.sol:353 | RedemptionExt.sol:263 | same call | same |
| `allowedQuote` | CauldronBase.sol:329 | `setAllowedQuote` (CauldronRegistry.sol:290) | owner | registry-side `onlyOwner` |
| `generationLegs[gen]` | CauldronBase.sol:460 | push RedemptionExt.sol:682, update RedemptionExt.sol:680, remove RedemptionExt.sol:746 and RedemptionExt.sol:747 | `_recordLeg` from a slice (RedemptionExt.sol:423); `recoverLegs` at teardown | ungated on both paths |
| `generationQuote[gen]` | CauldronBase.sol:340 | RedemptionExt.sol:505 | a primary-leg slice whose mandate is spent (RedemptionExt.sol:504) | ungated — the governor's flag is the whole gate |
| `legProceeds[asset]` | CauldronBase.sol:482 | credit RedemptionExt.sol:743, clear RedemptionExt.sol:801 | `recoverLegs`; `sweepLegProceeds` | ungated / `onlyOwner` (RedemptionExt.sol:794) |

Transitions, in the order one slice performs them: **UNWIRED** → `quoteRotator` (RedemptionExt.sol:262) → **WIRED**; **WIRED** + a live envelope (RedemptionExt.sol:317) → `rotateSliceFrom` removes (RedemptionExt.sol:363), swaps (RedemptionExt.sol:376), pulls back (RedemptionExt.sol:377), redeploys (RedemptionExt.sol:382), links volume (RedemptionExt.sol:396), records the leg (RedemptionExt.sol:423) and only then spends envelope (RedemptionExt.sol:437) → **SPLIT**; **SPLIT** + `migrationMandateSpent` on a primary slice (RedemptionExt.sol:504) → the quote flips (RedemptionExt.sol:505) and the perp engine is re-pointed best-effort (RedemptionExt.sol:540) → **REDENOMINATED**; at relaunch `RECOVER_LEGS` (CauldronRegistry.sol:1607) unwinds every leg → back to a single position. There is no pause, no abort and no pending state: the design note at `mind` (RedemptionExt.sol:208) says a guild that changes its mind simply stops calling.

Two flags outside this cluster gate the machine from the side: `linkVolume` refuses while the perp book is open, at `PerpsOpen` (CauldronHook.sol:1565), and the envelope's own liveness comes from `allowance` (TreasuryGovernor.sol:643).

### Machine 3 — `CauldronVault`

`closed` (CauldronVault.sol:51) is a one-way flag: false at deployment, set true by `closed` (CauldronVault.sol:118) under the registry check at `NotRegistry` (CauldronVault.sol:117), which the relaunch path reaches through `close` (PoolOps.sol:1013). Once set, `redeem` reverts at `Closed` (CauldronVault.sol:95) while `receive` (CauldronVault.sol:72) still accepts deposits. `redeemed` (CauldronVault.sol:40) only ever rises (CauldronVault.sol:106).

---

## The envelope lifecycle

Two different "envelopes" exist in this cluster; they are not the same object.

### The governance envelope (the one that authorises a live rotation)

- **Creation** — outside the cluster, in `TreasuryGovernor`; this cluster only ever reads it.
- **Who holds it** — the address in `treasuryGovernor` (CauldronBase.sol:353), written only at RedemptionExt.sol:263. A zero there stops every slice at `RotationNotWired` (RedemptionExt.sol:302).
- **Where its denomination is set** — by the vote; it is READ here as the first return of `allowance` (RedemptionExt.sol:303) and re-validated against the registry allowlist at `allowedQuote` (RedemptionExt.sol:322). The destination is never a caller parameter.
- **Liveness** — the SECOND return, the remaining bps, is the flag: absent, expired and spent envelopes all report zero and stop at `NoRotationApproved` (RedemptionExt.sol:317). Address zero is deliberately NOT the sentinel, because it is also a legitimate destination (native ether).
- **Funding / ceiling** — each call must fit inside the remainder (RedemptionExt.sol:318) and inside the per-call slice cap (RedemptionExt.sol:326, RedemptionExt.sol:576).
- **Spend** — `consume` (RedemptionExt.sol:437), booked only after the liquidity has actually moved, and told whether the slice came from the primary via the comparison on the same line.
- **Completion** — `migrationMandateSpent` (RedemptionExt.sol:504); true only on a primary-leg slice, and it is what flips `generationQuote` (RedemptionExt.sol:505) and re-points the perp engine (RedemptionExt.sol:540).
- **Abort** — none in this cluster; the caller stops calling (RedemptionExt.sol:208).

### The rotator's own envelope (the `Plan`)

- **Creation** — `setPlan` writing the whole `plan` (QuoteRotator.sol:227), owner-gated (QuoteRotator.sol:219); denomination set there as `from` and `to` (QuoteRotator.sol:228, QuoteRotator.sol:229) and read on every step at `from` (QuoteRotator.sol:269), `to` (QuoteRotator.sol:286) and `from` (QuoteRotator.sol:287).
- **Who holds it** — `QuoteRotator` itself; there is exactly one slot (QuoteRotator.sol:77), so one plan at a time.
- **Funding** — not part of the plan. Assets must simply BE in the rotator: native through `receive` (QuoteRotator.sol:718) or ERC20 by transfer, and `nextSliceSize` clamps to whatever is there at `held` (QuoteRotator.sol:270).
- **Spend** — `rotateStep` adding to `doneIn` (QuoteRotator.sol:301) advances `doneIn`, `rotateStep` adding to `gotOut` (QuoteRotator.sol:310) records `gotOut`, and the keeper takes its cut at QuoteRotator.sol:313.
- **Completion** — implicit: `doneIn >= totalIn` makes every further step return zero at QuoteRotator.sol:261. Nothing is emitted and nothing is cleared.
- **Abort** — `cancelPlan` deleting `plan` (QuoteRotator.sol:246), owner-gated, which deletes the struct and leaves the converted assets in place for `withdraw` (QuoteRotator.sol:589).

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
- `QuoteOracle.sol:305` `function cachedUsdPerRawUnit(address quote) external returns (uint256)` — **anyone** — NONE
- `QuoteOracle.sol:316` `function priceable(address quote) external view returns (bool)` — **anyone** — NONE
- `QuoteOracle.sol:320` `function _sequencerOk() internal view returns (bool)` — **internal (callers: usdPerRawUnit)** — NONE

**QuoteRotator** — `cauldron/QuoteRotator.sol`

- `QuoteRotator.sol:95` `constructor(address _registry, IPoolManager _poolManager)` — **deployer** — NONE
- `QuoteRotator.sol:121` `modifier onlyRegistry()` — **internal (callers: swapOnce)** — NONE
- `QuoteRotator.sol:126` `modifier onlyOwner()` — **internal (callers: transferOwnership, setVenue, setPlan, cancelPlan, setKeeperBps, setRotationSlipBps, setArbParams, setMaxArbNotionalUsd)** — NONE
- `QuoteRotator.sol:131` `function transferOwnership(address to) external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:186` `function setVenue(PoolKey calldata route, bool allowed) external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:193` `function isVenueAllowed(PoolKey calldata route) external view returns (bool)` — **anyone** — NONE
- `QuoteRotator.sol:212` `function setPlan( address from, address to, uint128 totalIn, uint128 sliceIn, uint256 minRate, uint32 interval ) external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:244` `function cancelPlan() external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:249` `function setKeeperBps(uint16 bps) external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:259` `function nextSliceSize() public view returns (uint256)` — **anyone** — NONE
- `QuoteRotator.sol:280` `function rotateStep(PoolKey calldata route) external returns (uint256 out)` — **anyone (permissionless keeper; the caller chooses only the venue, from the curated list)** — `_send` pays the keeper a share of the plan's `to` asset (line 313); the swap legs settle and take inside `_swap` (line 303)
- `QuoteRotator.sol:331` `function swapOnce( PoolKey calldata route, address from, address to, uint256 amountIn, uint256 minOut ) external onlyRegistry returns (uint256 out)` — **registry (the immutable address; the gate is on THIS side, not the registry's)** — the swap legs settle and take inside `_swap` (line 356); proceeds stay in this contract until `withdraw` (line 589) moves them
- `QuoteRotator.sol:378` `function setRotationSlipBps(uint16 bps) external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:398` `function _oracleFloor(address from, address to, uint256 amountIn) internal returns (uint256)` — **internal (callers: swapOnce)** — NONE
- `QuoteRotator.sol:448` `function setArbParams(address oracle, uint16 keeperBps, uint256 minProfitUsd) external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:458` `function setMaxArbNotionalUsd(uint256 maxNotionalUsd) external onlyOwner` — **owner (the treasury)** — NONE
- `QuoteRotator.sol:496` `function arbStep(PoolKey calldata cheap, PoolKey calldata dear, uint256 amountIn) external returns (uint256 profitUsd)` — **anyone (permissionless keeper)** — `_send` pays the keeper a cut of the received quote (line 559); the two swap legs settle and take inside the unlock at `unlock` (line 526)
- `QuoteRotator.sol:564` `function _usd(address quote, uint256 raw) internal returns (uint256)` — **internal (callers: _oracleFloor, arbStep)** — NONE
- `QuoteRotator.sol:589` `function withdraw(address asset, address to, uint256 amount) external` — **registry or owner (either satisfies the check; the gate is on this side)** — `_send` moves the named asset — native or ERC20 — to an arbitrary destination (line 592)
- `QuoteRotator.sol:600` `function _swap(PoolKey calldata route, address from, address to, uint256 size) internal returns (uint256 out)` — **internal (callers: rotateStep, swapOnce)** — the actual transfers happen in the callback this opens, at `unlock` (line 605)
- `QuoteRotator.sol:609` `function unlockCallback(bytes calldata data) external returns (bytes memory)` — **poolManager (the immutable address)** — pays the pool through `_settle` (line 631) and receives the bought asset through `take` (line 632)
- `QuoteRotator.sol:641` `function _arbCallback(bytes calldata data) internal returns (bytes memory)` — **internal (callers: unlockCallback)** — settles the spent quote out of this contract at `_settle` (line 663) and receives the sold quote at `take` (line 664)
- `QuoteRotator.sol:668` `function _settle(address cur, uint256 amount) internal` — **internal (callers: unlockCallback, _arbCallback)** — sends native to the pool manager at `settle` (line 670); ERC20 to the pool manager at `_safeTransfer` (line 673)
- `QuoteRotator.sol:678` `function _send(address cur, address to, uint256 amount) internal` — **internal (callers: rotateStep, arbStep, withdraw)** — sends native to an arbitrary recipient at `call` (line 681); ERC20 transfer at `_safeTransfer` (line 684)
- `QuoteRotator.sol:691` `function _safeTransfer(address token, address to, uint256 amount) internal` — **internal (callers: _settle, _send)** — ERC20 transfer of the named token to the recipient at `transfer` (line 693)
- `QuoteRotator.sol:697` `function _routeMatches(PoolKey calldata route, address from, address to) internal pure returns (bool)` — **internal (callers: rotateStep, swapOnce)** — NONE
- `QuoteRotator.sol:707` `function _balanceOf(address asset) internal view returns (uint256)` — **internal (callers: nextSliceSize)** — NONE
- `QuoteRotator.sol:711` `function _allowed(address quote) internal view returns (bool)` — **internal (callers: setPlan, rotateStep, swapOnce, arbStep)** — NONE
- `QuoteRotator.sol:718` `receive() external payable` — **anyone** — `receive` receives native with no accounting (line 718)

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
- `RedemptionExt.sol:280` `function rotateSliceFrom( uint8 fromLeg, uint16 sliceBps, uint256 minOut, PoolKey calldata route ) public returns (uint256 moved, uint256 positionId)` — **anyone (permissionless; the destination and the ceiling come from the governance envelope, not from the caller)** — `sendAsset` pushes the removed quote side to the rotator (line 375); `withdraw` pulls the converted asset back (line 377); `openOrAddPair` deploys both sides into the destination pair (line 382)
- `RedemptionExt.sol:605` `function completeRotation(address quote, uint256 quoteAmount, uint256 tokenAmount) external onlyOwner returns (uint256 positionId)` — **owner (the gate is on the facet side) — but see reachability: no registry forwarder exists** — `openOrAddPair` deploys the named quote amount and token amount out of the registry's custody into the pair (line 614)
- `RedemptionExt.sol:648` `function floorClaimableNow() external view returns (bool claimable, uint256 perFren)` — **anyone** — NONE
- `RedemptionExt.sol:661` `function legCount(uint256 gen) external view returns (uint256)` — **anyone** — NONE
- `RedemptionExt.sol:666` `function legAt(uint256 gen, uint256 i) external view returns (address quote, uint256 positionId, PoolKey memory key)` — **anyone** — NONE
- `RedemptionExt.sol:676` `function _recordLeg(uint256 gen, address quote, uint256 positionId, PoolKey memory key) private` — **internal (callers: rotateSliceFrom)** — NONE
- `RedemptionExt.sol:699` `function recoverLegs(uint256 gen) public returns (uint256 quoteOut, uint256 tokenOut)` — **anyone (public and ungated) — reached in practice only through the registry's relaunch delegatecall** — `removeAll` unwinds each leg's position, delivering both sides into the registry (line 736)
- `RedemptionExt.sol:757` `function legProceedsOf(address asset) external view returns (uint256)` — **anyone** — NONE
- `RedemptionExt.sol:794` `function sweepLegProceeds(address asset, address to) external onlyOwner returns (uint256 amount)` — **owner (the registry's own owner slot; the gate is on the FACET side, the registry stub is ungated)** — `sendAsset` moves the whole booked balance of the asset to an owner-chosen destination (line 802)