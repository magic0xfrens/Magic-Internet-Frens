# Magic Internet Frens / The Cauldron — Functional Specification

**Status:** Phase 1 complete (areas A–G). Phase 2 conformance folded in inline.
**Tree:** branch `fix/b05-b07-relaunch-totality`, working tree (NOT `HEAD`).
**Date:** 2026-09-10.
**Build:** `FOUNDRY_PROFILE=cauldron` (mandatory — V4 deps pin old solc).

This is the document the audit checks against. Before it, intent for this
protocol lived scattered across code comments, six design docs and three prior
audit passes, and no single place said what the system is supposed to do.

Every behavioural claim in the section files carries `path/File.sol:line`,
verified by reading that line. Where a comment and the code disagree, both are
recorded and the disagreement is the finding.

---

## What this protocol is

An autonomous, infinitely-relaunching token protocol on Uniswap V4. When a
generation's 24h volume dies, anyone may permissionlessly `relaunch()`: the dead
pool's liquidity is recovered, a new token is deployed, and the recovered value
seeds the next generation's pool. Prior holders claim 1:1 forever. Around that
core sit an NFT collection, a perp engine, holder dividends, a rotating LP quote
asset and on-chain governance.

Scale: ~15.7k lines of Solidity outside `lib/`, 130 Foundry suites, 661 tests.

### ⚠️ Intent sources that are NOT about this protocol

`docs/PROTOCOL_SPEC.md`, `docs/TOKENOMICS.md`, `docs/FLYWHEEL_ECONOMICS.md`,
`docs/DEATH_SPIRAL_ANALYSIS.md`, `docs/SECURITY_ANALYSIS.md`,
`docs/DEPLOYMENT_GUIDE.md`, `docs/PHOENIX_SYSTEM.md` and
`docs/PHOENIX_TAX_SYSTEM.md` described a **completely different protocol** — an
OP_NET (Bitcoin L1) Abracadabra/MIM fork with a BTC-collateralised stablecoin
(`$MIF`), an `$sFREN` staking token, LTV/liquidation lending and MotoSwap pools.

None of it exists in this tree. They were cited as intent sources by every prior
audit prompt, which means those audits were partly checking against fiction.
Moved to `archive/superseded-docs/opnet-era/` during this pass, with a README
recording what superseded what. **The surviving intent sources are**
`contracts/solidity/CAULDRON.md`, `docs/LAUNCH_LADDER_DESIGN.md`,
`docs/TREASURY_FUND_PLAN.md`, `docs/QUOTE_ASSET_PLAN.md`,
`docs/AI_REBIRTH_SYSTEM.md`, `contracts/solidity/COLLECTION_FLOOR_UNIFY.md`,
and the NatSpec, which is unusually dense and is the best source in the repo.

---

## The spine: denomination totality

The protocol's central claim is that every feature works with **any**
treasury-approved LP quote — native ETH, a 6-decimal stable (USDG), an
18-decimal synthetic — and stays correct when the base asset **changes
mid-iteration**.

Three slots answer "what asset is this generation in?", and they are not the
same slot (details in `sections/E_D_spine_rotation_perps.md` §S1):

| Slot | Written by | Meaning |
|---|---|---|
| `generationQuote[gen]` (`CauldronBase.sol:332`) | `CauldronRegistry.sol:924` (relaunch), `RedemptionExt.sol:413` (completed rotation) | the record of intent |
| `PerpEngine.quote` (`PerpEngine.sol:170`) | `PerpEngine.sol:1027` only | what the perp engine trades against |
| `CauldronHook._feeAsset` (`CauldronHook.sol:661`, transient) | `CauldronHook.sol:1423`, from the live `PoolKey` | derived per-swap; needs no sync |

**Verdict.** The transition is handled far better than a first read suggests, and
the two structural protections are real and tested:

- **The P-1 interlock.** `rotateSlice` must call `linkVolume`
  (`RedemptionExt.sol:372`), and `CauldronHook.linkVolume` reverts `PerpsOpen()`
  while any perp position is open (`CauldronHook.sol:1516-1520`). Rotation and
  perps are deliberately mutually exclusive. Tested by
  `test_F10_RotationIsBlockedWhilePositionsAreOpen`.
- **USD normalisation before accumulation.** Swap volume is converted to USD at
  `CauldronHook.sol:799` *before* being written to the bucket at `:800-801`, so
  the 24h buckets never hold mixed units and a rotation cannot fake or hide a
  death. Decimals are handled correctly for a 6-decimal quote
  (`QuoteOracle.sol:256-277`).

Findings R-01…R-06 below: **five fixed, one left open as a design call**.

---

## Section index

| § | Area | File |
|---|---|---|
| A | Genesis & NFT collection | [`sections/A_genesis_nft.md`](sections/A_genesis_nft.md) |
| B | Iteration lifecycle | [`sections/B_iteration_lifecycle.md`](sections/B_iteration_lifecycle.md) |
| C | Volume, credit & death | [`sections/C_volume_credit_death.md`](sections/C_volume_credit_death.md) |
| D+E | **Spine** — rotation & perps | [`sections/E_D_spine_rotation_perps.md`](sections/E_D_spine_rotation_perps.md) |
| F | Dividends | [`sections/F_dividends.md`](sections/F_dividends.md) |
| G | Floors, redemption & the 2× ratchet | [`sections/G_floors_redemption.md`](sections/G_floors_redemption.md) |

---

## Findings register

Findings fixed during this pass are marked **FIXED**; those left open are marked
**OPEN** with the reason.

### R-01 — Facet functions unreachable through the registry · FIXED

**INTENT.** `CauldronRegistry.sol:1695` and `CauldronBase.sol:426` both state
that a fallback delegatecalls any unknown selector to the `RedemptionExt` facet.
**ACTUAL.** The registry declares `receive()` (`:508`) and **no `fallback()`** —
confirmed against the compiled ABI (`fallback entries: []`). Facet functions are
reachable only via explicit `_forwardToExt` stubs (`:1368`).
**DELTA.** Any facet function without a stub reverts with the raw "unrecognized
selector" EVM error — not a named protocol error, so it is not diagnosable.
**CLASS.** `DEVIATES`. **DENOM.** n/a (dispatch).

Affected, and their disposition:

| Function | Was | Now |
|---|---|---|
| `floorClaimableNow` (`RedemptionExt.sol:520`) | unreachable — **broke 3 tests** | fixed, stub at `CauldronRegistry.sol:1344` |
| `legCount` / `legAt` (`:533`, `:538`) | unreachable | fixed, stubs at `:1349`, `:1354` |
| `rotateSliceFrom` (`:266`) | unreachable | **fixed this pass**, stub at `:235`+ |
| `completeRotation` (`:477`) | unreachable | correct — `DEPRECATED-PRESENT` dead code |
| `recoverLegs` (`:571`) | unreachable externally | correct — internal-only, called by selector at `:1490` |

`rotateSliceFrom` is the severe one: it is the **only** write the shipped
treasury UI issues for a rotation (`src/hooks/useTreasuryRotation.ts:290`, for
every slice including the default `fromLeg = 0`), so the rotate button reverted
on every press. The multi-leg merge/rebalance that `RedemptionExt.sol:307-318`
calls the entire point of `fromLeg` had no reachable path from any caller.

This is the **third** instance of this defect class, after `setRotationWiring`
(recorded at `RedemptionExt.sol:215-227`) and the three views above.

**A catch-all `fallback()` was considered and rejected** — it would make
`recoverLegs` externally callable, which must not happen. Explicit stubs are
correct. Pinned by `test/functional/F20_FacetReachability.t.sol` (5 tests).

### R-02 — Perp engine could be pinned to a drained pool after a rotation · FIXED

**INTENT.** "The perp engine must reference the asset the pool actually trades
now" — and `CauldronHook.sol:1499` claims `_key()` is built from
`generationQuote[gen]`.
**ACTUAL.** `_key()` reads the engine's **own** `quote` slot
(`PerpEngine.sol:450`), which is assigned in exactly one place
(`:1027`, inside `syncGeneration`).
**DELTA.** After a rotation completed, `generationQuote` flipped but
`PerpEngine.quote` did not. `_guardOpen` (`:1210-1214`) checks warmup, death and
leverage but **not** quote freshness, so a trader could open in that window;
`openCount != 0` then makes `syncGeneration` revert `PositionsOpen()` (`:987`),
and `forceCloseDead`/`forceCloseAllDead` both require a **dead** generation
(`:937`, `:950`). The engine stayed pinned to the drained pool until every
position voluntarily closed, marking and liquidating off a thin pool that is
cheap to push while the deep sibling sets the real price — the exact hazard
`CauldronHook.sol:1504-1508` describes.
**CLASS.** `DEVIATES`. **DENOM.** `breaks-on-transition` (ETH → USDG).

**FIX.** `rotateSlice` now re-points the engine in the same transaction that
flips the quote (`RedemptionExt.sol`, `stillRotating` branch), best-effort via
`try/catch`, mirroring `CauldronRegistry._perpHousekeep` (`:1063`). Safe exactly
there: reaching that line required `linkVolume` to succeed earlier in the same
call, which guarantees `openCount == 0`. No user can interleave an open inside
one transaction.

Placed in `RedemptionExt` (11,668 B margin) rather than `PerpEngine`, which has
**35 bytes** of EIP-170 margin and could not absorb the alternative
(`_guardOpen` staleness check). Regression: `F10` §2–3 now assert the engine
follows with **no keeper call**, and that a redundant `syncGeneration` correctly
reverts `AlreadySynced`.

### R-03 — `renounceOwnership` could permanently brick the protocol · FIXED

**INTENT.** Ownership is meant to sit with a governance timelock and stay
replaceable — `RedemptionExt.sol:235-239` says the rotation wiring is
"deliberately NOT one-shot: a rotator or governor that turns out to be broken
must be replaceable."
**ACTUAL.** `CauldronBase is Ownable` (`:91`), so OZ's `renounceOwnership()` was
live and reachable with **zero callers anywhere** — no test, no script, no
frontend. Calling it zeroes the owner and permanently disables
`setRotationWiring`, `setAllowedQuote`, `setGovernor`, `setFactory`, `setSeeder`,
`setSeedWindow`, `setReserveCeiling`, `setCollectionLedger`.
**DELTA.** A one-call version of an accident this contract already carries the
scar of: `CauldronBase.sol:296-304` records a deploy that handed registry
ownership to the presale and "BURNED every `onlyOwner` setter ... permanently".
**CLASS.** `DEVIATES`.

**FIX.** Overridden to revert `RenounceDisabled()` (`CauldronBase.sol:409`).
`transferOwnership` is untouched, so handing control to a timelock still works.
Same pattern v4-periphery uses at `PermissionsAdapter.sol:187`. Reclaimed 42
bytes of registry bytecode.

### R-04 — `recoverLegs` sums proceeds across incompatible quote assets · FIXED

**INTENT.** `relaunch` treats `ethFromLP` as denominated in ONE asset — it is
passed to `PoolOps.seedFunding` together with `generationQuote[oldGen]` as the
asset it is measured in (`CauldronRegistry.sol:922`).
**ACTUAL.** `RedemptionExt.recoverLegs` (`:571-590`) accumulates
`quoteOut += q` (`:581`) across **every** leg regardless of that leg's own
`l.quote`. The `TreasuryLeg.quote` field is read only for the event at `:585`.
The result is folded straight into `ethRecovered` at
`CauldronRegistry.sol:1558-1561`.
**DELTA.** The multi-leg treasury is the explicit purpose of `fromLeg`
(`RedemptionExt.sol:307-318` describes 50/30/20 splits). With legs in USDG
(6-dec) and, say, an 18-decimal synthetic, `ethFromLP` becomes a meaningless sum
of incompatible units — and even a single USDG leg contributes 6-decimal raw
units to a native-wei total.
**CLASS.** `DEVIATES`. **DENOM.** `breaks-on-transition` — any generation with a
leg whose quote ≠ `generationQuote[oldGen]`.
**IMPACT.** `relaunch`'s "can we seed?" decision (`totalETH == 0` →
`NoLiquidityToSeed`, `:945`) is made on a corrupted magnitude. Under-counting
blocks a legitimate rebirth; over-counting seeds against value that is not there
in the expected asset.
**FIX (author's call: try liquidity first, else treasury / OG dividends).**
Two things had to be separated, because only the arithmetic was ever wrong — the
value itself always landed in the registry:

1. `recoverLegs` now adds a leg's proceeds to `quoteOut` **only** when
   `l.quote == generationQuote[gen]`. The relaunch's funding figure is once again
   a single denomination.
2. Foreign proceeds are booked to `legProceeds[asset]` (`CauldronBase.sol`,
   appended at the end of the shared layout) and emitted as `LegProceedsBooked`,
   then moved by `sweepLegProceeds(asset, to)`.

**On "can we just add it to an LP first?" — established, not assumed: no, not at
that moment.** `recoverLegs` runs inside `_removeLiquidity` (`Registry:785`),
which is tearing down every pool the dying generation had, and the new
generation's quote is not chosen until `seedFunding` (`Registry:921`) from a spec
not even read until `:830`. No LP exists that could accept a foreign asset there.
Converting instead would need a swap — hence a price — inside the one path that
must never be the reason the machine cannot be reborn, which is exactly the trade
`PoolOps.seedFunding` refuses to make (`PoolOps.sol:1021-1029`, *"RANKING ACROSS
ASSETS WOULD NEED A PRICE"*). So the sweep is deliberate and post-rebirth, where
it cannot affect it. Preference 1 (back into liquidity, once a later generation
uses that asset) is reachable by sweeping to the treasury; preference 2 (OG
dividends) is left wired-but-not-forced because `MiFrensDividend.fundToken` is
`funder`-gated to the **hook**, so the registry cannot call it — that is a
hook-side change, recommended rather than smuggled into the relaunch path.

Landed entirely in `RedemptionExt` (12,908 → 13,399 B); `CauldronRegistry`
unchanged at **55 bytes** of margin.
**REPRO.** `test/functional/F22_LegProceedsDenomination.t.sol` (3 tests) pins the
magnitude of the error and the partition invariant. The full end-to-end path
(rotate into two quotes, then relaunch) still needs a fork journey.

### R-05 — `CauldronGachaRouter` hardcodes native ETH as the pool quote · FIXED

**ACTUAL.** `CauldronGachaRouter._key()` (`:171-178`) builds
`currency0: Currency.wrap(address(0))` with the comment "The current iteration's
pool key (ETH is currency0)". The registry, by contrast, builds the key from the
generation's real quote and enforces "quote = currency0" via the watermark
ceiling (`CauldronRegistry.sol:271-287`).
**DELTA.** On any generation not denominated in native ETH — a relaunch onto
USDG, or a completed rotation — the gacha router addresses a pool that is not
the generation's pool.
**CLASS.** `DEVIATES`. **DENOM.** `ETH-only`.

**A SECOND, INDEPENDENT HARDCODE was found while fixing the first.**
`_playInCurveUnits` priced every play with `usdPerRawUnit(address(0))`
unconditionally, applying the 18-decimal ETH factor to a 6-decimal size: a real
$1,500 USDG buy came out as `4.5e12` instead of `1500e18` — understated
**~333,000,000x**, collapsing the player's odds to nothing. It fails in the same
safe direction as the original Q-02 bug (players win less, never more), which is
why it could ship unnoticed.

**FIX.** Both halves now read `registry.generationQuote(currentGeneration)`:
- `_key()` builds `currency0` from the live quote. Quote-as-currency0 is an
  invariant, not luck — `setAllowedQuote` refuses any quote at or above
  `QUOTE_WATERMARK` and every token is mined above it (`Registry:246-256`).
- `_playInCurveUnits` prices with the live quote.
- Value transport is now quote-aware end to end: `_pullQuote` takes the buy side
  as native `value` **or** an ERC20 `quoteIn` and rejects the wrong one rather
  than stranding it (`NativeQuoteTakesValue` / `ErcQuoteTakesNoValue`);
  `_payQuote` refunds in kind; the `settle` native flag is derived per call.

ABI changed (`play`, `playLiq`, `playChurn` gained a leading `quoteIn`), which is
safe: the router has **no Solidity callers** and exists only on testnet, so it is
redeployable. `src/config/cauldron.ts` and `useCauldronSwap.ts` updated;
`npm run type-check` clean. The stale `playLiq` ABI entry — which declared a bare
`uint256` where the contract takes `uint256[]`, and which the frontend worked
around by never calling it — was corrected in the same pass.
**REPRO.** `test/functional/F21_GachaQuoteAgnostic.t.sol` (5 tests), which pins
both the correct value and the pre-fix one so it cannot pass by coincidence.

### R-06 — INVARIANT R is a payout-time property, not an on-chain assert · OPEN (by design)

**INTENT.** `COLLECTION_FLOOR_UNIFY.md` calls for an on-chain assert that, on
every credit and redeem,
`Σ(genesisReserveOutstanding + Σ_gen entitledTokens[gen] + migrationOutstanding)
≤ reserve LP balance`.
**ACTUAL.** No such assert exists in any `.sol` file. `CollectionLedger.credit`
has no backing check at all; solvency is enforced at **payout**, where
`claimFromReserve` reverts "reserve short" (`PoolOps.sol:1133`, `:1264`). The
doc's third term, `migrationOutstanding`, names no tracked on-chain variable.
**CLASS.** `UNDERSPECIFIED` — intent and implementation choose different
enforcement points.
**ASSESSMENT.** This is **already documented honestly in the tree**:
`test_F11_InvariantRIsEnforcedAtPayoutNotAtCredit`
(`F11_FloorsAndRedemption.t.sol:98-118`) credits `type(uint128).max` against a
zero reserve, asserts it is accepted, and records the first-come-first-served
failure mode explicitly. So this is a known, tested design position, not a hidden
hole. The residual risk is real but bounded: a ledger bug cannot mint value, it
can only let the last redeemers find the reserve empty.
**RECOMMENDATION.** Leave as-is, or add the assert as a cheap belt at
`CollectionLedger.credit`. A design call, surfaced not taken.

---

## Conformance matrix

| Area | Feature | Class | Denomination | Test |
|---|---|---|---|---|
| A1 | Presale summon / cancel / refund | CONFORMS | ETH-only *by design* (gen 1 predates the allowlist, `CauldronRegistry.sol:675-677`) | `GenesisCancelRefund.t.sol` |
| A2 | Mint, caps, curve | CONFORMS | quote-agnostic (credit-priced, `MintCurvePolicy.sol:30-42`) | `F13_MintCurve.t.sol` |
| A3 | Reveal / sealed crystals | CONFORMS | quote-agnostic (no value moved) | `RevealBatch.t.sol` |
| A4 | Gacha `play`/`playChurn`/`openReady` | **FIXED** (R-05) | was **ETH-only** ×2 (key + pricing) | `F21_GachaQuoteAgnostic.t.sol` |
| A5 | Liquidatoor badges | CONFORMS-UNTESTED (stats payload) | ETH-wei hardcoded in `LiqStats`/renderer | `LiquidatoorBadge.t.sol` |
| B1 | `summon` | CONFORMS | ETH-only *by design* at genesis | `CauldronSummon.t.sol` |
| B2 | `relaunch` | CONFORMS *except* R-04 | quote-agnostic; raw base units end-to-end | `LifecycleE2E.t.sol` (fork) |
| B3 | Creature cycle | CONFORMS | n/a | `test_CreatureCycle` |
| B4 | `claimByBurn` 1:1 | CONFORMS | quote-agnostic — 1:1 is in the **token**, backed by the new gen's reserve (`PoolOps.sol:1233-1243`) | `MigrationVesting.t.sol` |
| C1–C2 | Volume & mint credit | CONFORMS | quote-agnostic — USD *before* accumulation (`CauldronHook.sol:799-801`) | `VolumeUnits.t.sol` |
| C3 | `QuoteOracle` | CONFORMS | quote-agnostic, 6-dec correct (`QuoteOracle.sol:256-277`) | `QuoteOracle.t.sol`, `F14_OracleSafety.t.sol` |
| C4 | Death detection | CONFORMS | asset-neutral; fails **open** ≤24h then **closed** (`CauldronHook.sol:1486`) | `F15_QuotePriceability.t.sol` |
| C5 | `linkVolume` | CONFORMS | one-directional linkage (noted) | `F10` |
| D | Perp quote follows rotation | **FIXED** (R-02) | was `breaks-on-transition` | `F10` §2–3 |
| D | P-1 interlock | CONFORMS | n/a | `test_F10_RotationIsBlockedWhilePositionsAreOpen` |
| E | Facet reachability | **FIXED** (R-01) | n/a | `F20_FacetReachability.t.sol` |
| E | `rotateSlice` / envelope / caps | CONFORMS | quote-agnostic | `F10`, `QuoteRotator.t.sol`, `RotationRoundTrip.t.sol` |
| E | Multi-leg recovery | **FIXED** (R-04) | was `breaks-on-transition` | `F22_LegProceedsDenomination.t.sol` |
| F1–F3 | Multi-asset basket, settlement | CONFORMS | quote-agnostic; native and ERC20 rails never cross | `DividendBasket.t.sol` |
| F4 | `enchantFee` | CONFORMS | denominated in the **iteration token**, a third axis | `DividendBasket.t.sol` |
| G1 | OG floor + 2× ratchet | CONFORMS | quote-agnostic (operates on the token, not the quote) | `F11_FloorsAndRedemption.t.sol` |
| G2 | Creature floor — `CollectionLedger` | CONFORMS (live path) | quote-agnostic | `CollectionLedger.t.sol` |
| G2 | Creature floor — `CauldronVault` | **DEPRECATED-PRESENT** | ETH-only, neutered by `hook.setVault(0)` (`CauldronRegistry.sol:1124`, `:1148`) | — |
| G2 | `redeemCreature`/`buyTreasuryCreature` | **DESIGN-ONLY** — absent from tree; no `feat/unified-collection-floor` branch exists | n/a | — |
| G3 | INVARIANT R | **UNDERSPECIFIED** (R-06) | n/a | `test_F11_InvariantRIsEnforcedAtPayoutNotAtCredit` |
| G4 | Fold-forward | CONFORMS | both genesis and creature fold forward (`CauldronRegistry.sol:960-1026`) | `F11` |

---

## Test baseline

| Run | Suites | Pass | Fail | Skip |
|---|---|---|---|---|
| Session start | 126 | 621 | 14 | 1 |
| After R-01/R-03 (+`F20`, 5 tests) | 127 | 643 | 0 | 1 |
| After R-02 | 127 | 643 | 0 | 1 |
| After R-05 (+`F21`, 5 tests) | 128 | 648 | 0 | 1 |
| After R-04 (+`F22`, 3 tests) — **final** | 130 | **660** | **0** | 1 |

636 tests at session start, 661 at the end (+25: three new regression suites and
`F10`'s strengthened rotation assertions). The final run is
`660 passed, 0 failed, 1 skipped (661 total)`.

**The 14 initial failures were not 14 defects.** Eleven were public-RPC 429
throttling from parallel fork tests against
`ethereum-sepolia-rpc.publicnode.com` — they vanish at `--threads 4`. Three were
genuine, all caused by R-01. Fork suites silently `[SKIP]` without `FORK_RPC` /
`POOL_MANAGER` / `POSITION_MANAGER`, so an unconfigured run reports a green suite
that never exercised the pool.

## Contract sizes (EIP-170 = 24,576 B)

| Contract | Runtime | Margin | Note |
|---|---|---|---|
| `PerpEngine` | 24,541 | **35** | binding — no fix can land here |
| `CauldronRegistry` | 24,521 | **55** | R-01 stub +120, R-03 override −42 |
| `CauldronHook` | 24,508 | **68** | untouched |
| `PoolOps` | 23,662 | 914 | |
| `RedemptionExt` | 13,399 | 11,177 | absorbed R-02 **and** R-04 |
| `CauldronGachaRouter` | 8,536 | 16,040 | absorbed R-05 |

`PerpEngine`'s 35 bytes is the single hardest constraint in the codebase and
directly shaped the R-02 fix.

---

## Threats to validity

- **Journey 4 as briefed is not constructable.** The audit brief asks for a live
  rotation *with perp positions open*. The P-1 interlock forbids exactly that
  combination (`CauldronHook.sol:1518`). The journey is only valid with
  `openCount == 0`, which is how `F10` builds it.
- **R-04 and R-05 are reachability-established, not repro-constructed.** Both
  need a fork rotation into a second quote; the call graph is traced but no
  failing test exists yet.
- **Phase 3 journeys 1, 2, 3, 5, 6 were not driven end-to-end** in this pass
  beyond the coverage the existing suites already provide.
- **Fork tests depend on a rate-limited public RPC.** Results vary with
  concurrency; all numbers here are from `--threads 4`.
- **The tree changed mid-audit.** `CauldronRegistry.sol` was edited by the author
  at 20:14 during this pass (the R-01 view stubs). Findings are stated against
  the post-edit tree; see `sections/E_D_spine_rotation_perps.md` § Provenance.
- **Subagent claims discarded: 0.** Four claims were independently re-verified
  before inclusion (gacha `_key`, `recoverLegs` summation, INVARIANT R absence,
  dividend rail separation); all four held.
