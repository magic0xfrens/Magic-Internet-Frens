# FINAL BLIND REVIEW — 2026-09-11

Pre-mainnet adversarial review of the Cauldron protocol, run blind against a
decontaminated tree. Orchestrator + 6 scoped attack teams. Every claim below
carries a file:line I read, and every CRITICAL was independently re-run by the
orchestrator before it was accepted.

---

## 1. Verdict

**Do not deploy today. The code is materially safer than it was this morning —
four Criticals are closed — but a set of demonstrated Highs is still open.**

Four Criticals were found and fixed. Three of them were *permanent-brick* bugs:
each one ended the protocol's core promise (runs forever, relaunches
permissionlessly) for the price of gas. One of them — a dead quorum call — meant
treasury governance had **never worked on any deployment**.

What stands between this and "yes":

1. **Eight Highs demonstrated but unfixed** (oracle cache, vault exit seniority,
   `plvToken` wipe, surtax grind, envelope hijack, mandate erasure, scan flood,
   vesting grant flood). Each has a passing PoC.
2. **Two of those are value-extraction, not griefing** — the stale-oracle
   sandwich measured 16.4% ROI on 10 ETH, and the forged-tranche floor pays
   12.11× short.
3. **No fork-level re-verification of the four fixes together.** They were
   verified individually and against the full suite; they have not run against a
   live multi-generation lifecycle.

Answering the question actually asked — *is anything hidden still there*: **yes,
and it was hidden in exactly the place the method predicted.** Two of the four
Criticals live in code a prior remediation had just touched, and one of them
(C-3) is a direct fix-induced regression of remediation R-04 from the same day.
The freshly-patched code was the richest hunting ground, not the safest.

---

## 2. The value & authority map

Built from the code before reading any prior document.

**Native value sinks** (11 contracts with `receive()`): `CauldronRegistry:538`,
`CauldronHook:2392`, `CauldronSeeder:166`, `LaunchSniper:95`,
`CauldronGachaRouter:551`, `PerpEngine:1813`, `CauldronVault:72`,
`QuoteRotator:718`, `RoyaltyRouter:32`, `MiFrensDividend:235`.

**Native egress — who can move ETH out:** 29 `call{value:}` sites. The
privileged ones are `CauldronRegistry:440/450/532` (emergencyAdmin),
`CauldronHook:1633/1882` (registry), `CauldronHook:2013` (proposer, pull-only),
`CauldronSeeder:437/601`, `PerpEngine:216/1392`, `MiFrensDividend:523/538`.

**Access modifiers — the whole set (15):** `CauldronToken.onlyRegistry`,
`CauldronRegistry.{onlyEmergency,timelocked}`, `QuoteOracle.onlyOwner`,
`CauldronSeeder.{lock,onlyRegistry}`, `PerpEngine.{notNested,onlyVault}`,
`CauldronGachaRouter.nonReentrant`, `MiFrensGenesis.onlyDeployerOrRegistry`,
`QuoteRotator.{onlyRegistry,onlyOwner}`, `CollectionLedger.onlyRegistry`.
`CauldronHook` defines **no** modifier of its own — it uses OZ `onlyOwner` plus
inline `if (msg.sender != …) revert`, which is why several signatures read as
unguarded and are not. The single genuinely unguarded state-mutating function in
the hook is `fundLegacyBuffer()` (`CauldronHook.sol:1086`), and that is a
donation.

**Delegatecall surface — verified clean.** `CauldronRegistry` ↔ `RedemptionExt`:
60 storage slots each, 60 shared, **zero mismatches** (`forge inspect
storage-layout`, diffed slot-by-slot). All six delegatecall libraries
(`FeeRouteLib`, `LegacyBuyLib`, `PoolOps`, `SeedLib`, `ReserveLib`,
`PerpSwapLib`) declare **zero** storage slots — collision is structurally
impossible, not merely currently-absent. `_forwardToExt()`
(`CauldronRegistry.sol:1419`) is a correct full-calldata delegatecall with
returndata and revert bubbling, no stubbed returns.

**Facet reachability.** ABI-diffing the facet against the dispatcher found 4
facet functions with no stub. Two are unrouted by design; two
(`sweepLegProceeds`, `legProceedsOf`) were genuinely dead — see M-1.

---

## 3. Findings

### CRITICAL — all four FIXED and regression-tested

#### C-1 · A 33,077-gas pool-key squat bricks `relaunch()` permanently · VERIFIED

`PoolOps.deployTokenAbove` (`PoolOps.sol:677`) mines a CREATE2 salt
`keccak256(abi.encode(gen, i))` over an initcode hash of only public inputs, so
the next generation's token address — and its whole `PoolKey` — is computable
before the token exists. `PoolOps._greenCandle` then called `initialize` **bare**:

```solidity
// PoolOps.sol:462
poolManager.initialize(r.key, sqrtPriceX96);
```

while its sibling 400 lines later (`PoolOps.sol:863`, the rotation path) wraps
the same call in `try/catch`. An attacker initializes that key first; every
future `relaunch()` reverts `PoolAlreadyInitialized()` (`0x7983c051`) forever.
Retried at +30 days: identical revert. The squat is **invisible** —
`_afterInitialize` declined to track a foreign pool, so `trackedPools` reads
false and no protocol view shows anything wrong.

Cost 33,077 gas, no capital, atomic, repeatable against every future generation.
Damage: total, permanent, all holders stranded.

**Fix.** `CauldronHook._afterInitialize` now **reverts** for a non-registry
sender (`CauldronHook.sol:620`) instead of silently not-tracking. The key names
the hook, so every `initialize` must pass that callback — which makes the key
unsquattable. Declining-to-track looked conservative and was the opposite.
Paid for under EIP-170 by demoting two unused public constants to `internal`.
PoC → regression: `test/attacks/T01_PoolKeySquatRegression.t.sol`.

#### C-2 · A gas-starved `relaunch()` strands the entire perp book, permanently · VERIFIED

`relaunch()` is permissionless and **the caller chooses the gas limit**. The
force-close was gas-capped and double-swallowed (`CauldronRegistry.sol:1108-1111`
and `CauldronHook.forceClosePerps`). Three facts combined into a permanent freeze:

1. The close is **all-or-nothing** — an OOG mid-loop reverts every settle it had
   done. Measured: at a 12M cap **64/64 positions survive**; at 14M, none do.
2. The documented recovery is unreachable. `_isDead()` (`PerpEngine.sol:1306`)
   builds its key from `registry.currentToken()` — a **live** read — so an
   instant after relaunch the newborn pool is current and alive:
   `forceCloseAllDead`/`forceCloseDead` revert `NotDead()` forever, and
   `syncGeneration` needs `openCount == 0` so it reverts `PositionsOpen()`.
3. It cannot be repaired even with the gate forced open: `_settle` **always**
   swaps (`PerpEngine.sol:1144`, `:1157`) against a pool the relaunch has already
   drained. Engine held 257,096,092 gen-1 tokens and **0** gen-2.

0.224 ETH fills the 64-slot book — and an *honest* relaunch sent with a 12M limit
triggers it by accident. 64 traders' collateral and the LP's lent ETH locked.

**Fix.** The survivor check moved to where the engine is in scope
(`CauldronHook.forceClosePerps` → `if (IPerpForceClose(eng).openCount() != 0)
revert PerpsOpen();`) and the registry **stopped swallowing it**
(`CauldronRegistry.sol`, `try/catch` removed). Reverting is safe *and*
recoverable: the whole tx rolls back, `markConsumed` with it, the proposal stays
live, and the next caller sends more gas. It cannot wedge the machine because the
work is bounded — `MAX_OPEN_POSITIONS = 64`, `FORCE_CLOSE_MAX = 96` guarantees
one call drains it, and a full close measures ~7.5M gas, well inside a block.
**The overflow the gas cap was written to prevent cannot occur; the freeze it
produced could, and did.**

Verified after the fix:

```
cap 12000000 → relaunch ok: false | gen: 1 | openCount: 64   (reverts, retryable)
cap 14000000 → relaunch ok: true  | gen: 2 | openCount:  0   (normal path intact)
```

PoC: `test/attacks/T03_RelaunchSurvivorBrick.t.sol`.

#### C-3 · A stranger burns a whole migration mandate on a dust leg · VERIFIED · **FIX-INDUCED**

`TreasuryGovernor.consume` books `e.movedBps += bps` with **no notion of value**
(`TreasuryGovernor.sol:678-680`), while `RedemptionExt.rotateSliceFrom` lets a
**permissionless** caller choose which leg those bps come out of
(`RedemptionExt.sol:286` — *"Not onlyOwner… a caller chooses only the timing"*;
it does not — it chooses the denominator). `migrationMandateSpent()` then reports
the migration complete and `generationQuote[gen]` flips.

```
bps of envelope consumed : 10000
primary liquidity BEFORE : 111387380039212700526908
primary liquidity AFTER  : 111387380039212700526908   ← bit-identical
generationQuote[1]       : 0x1d14…F211                 ← flipped anyway
and rotateSliceFrom(0,…) now reverts: the ETH treasury is frozen
```

It also re-points `PerpEngine.quote` onto a dust pool in the same transaction —
the thin-pool mark hazard the hook's own comments warn about, now permissionless.

**This is a regression of remediation R-04 from the same day.** R-04 correctly
identified that exhaustion ≠ completion and replaced `allowance() == address(0)`
with `movedBps >= maxTotalBps` — swapping one *accounting* test for another. The
multi-leg rotation made the accounting unit wrong.

**Fix.** Made the unit honest rather than adding a third accounting test: a new
`Envelope.movedPrimaryBps` counts only what left the generation's **own**
position, `consume(uint16,bool fromPrimary)` records it, and
`migrationMandateSpent()` tests that. Secondary legs stay rotatable under the
same envelope (rebalancing, authorised) but cannot declare a migration done.
PoC: `test/attacks/T02_EnvelopeBurnedOnADustLeg.t.sol` (attack no longer lands).

#### C-4 · Treasury governance was dead on arrival — the quorum calls a function that does not exist · VERIFIED

`TreasuryGovernor._passed` computed quorum as `mifrens.totalSupply() * QUORUM_BPS
/ 10_000`. The contract production actually wires is `MiFrensGenesis`
(`DeployLaunchpad.s.sol:461` — `IVotes721(address(presale))`), which is
`ERC721Votes` but deliberately **not** `ERC721Enumerable`, and declares no
fallback. Confirmed from the compiled ABI: `totalSupply present: False`,
`has fallback: False`.

`propose` and `vote` work (they use `getVotes`/`getPastVotes`). The defect is
invisible until `forVotes > againstVotes`, because `_passed` short-circuits on
ties. The moment a proposal earns real support, every quorum read reverts
`unrecognized function selector 0x18160ddd` — killing `execute`, the leader scan
and `passing`. **No envelope could ever be approved, so `rotateSlice` could never
be authorised.** Permanent and not owner-fixable: `mifrens` is immutable.

It shipped because the governor's suite binds a mock that *does* implement
`totalSupply()`. No test ever pointed the governor at the real vote source.

**Fix.** `IVotes721.getPastTotalSupply(uint256)` — what `Votes` actually
maintains. Strictly better than a mint counter: it follows burns
(`burnFromVault` exists), and it is read **at the proposal's snapshot**, the same
timepoint `vote` weighs ballots against, so quorum cannot be moved under a vote
in progress. All 12 vote mocks across the suite updated to match production.
New regression test wires the **real** pair:
`test/attacks/T08_GovernorQuorumWiring.t.sol`.

*Note the ordering dependency: C-4 is why C-3 was not yet live in production.
Fixing C-4 exposes C-3, which is why both had to ship together.*

---

### HIGH — fixed

#### H-1 · The OG tranche can drain the forged tranche's floor, permanently · VERIFIED

On the iteration-#2 continuation `generationCollection[gen]` **is** the MiFrens
collection, OGs included (`CauldronRegistry.sol:1158`), but the ledger pot it
pays from was credited with the **forged share only**
(`PoolOps.sol:1292-1296`), and the matching vault is deliberately given
`floorOffset = genesisShares` for exactly this reason — the code says so at
`CauldronRegistry.sol:1154`: *"the OGs have their own dividend + redemption floor
and must not dilute or draw this one"*.

`CauldronVault.redeem` enforces it (`CauldronVault.sol:96`: `if (tokenId <=
floorOffset) revert NotOwner();`). `PoolOps.recycleCollection` had **no
equivalent**. Each OG recycle also incremented the ledger's shared `retired`,
permanently destroying a unit of forged capacity — and the only decrementer,
`buyback`, reverts once the floor hits zero. Measured: **91% of the forged
tranche's pot permanently stranded.**

**Fix.** The guard now lives in `PoolOps.recycleCollection`, which has the
EIP-170 room and sits beside the accounting it protects. It asks the collection
for its own offset rather than taking a parameter, so it self-configures: only
the MiFrens continuation answers `GENESIS_SUPPLY()`, a plain brew returns no data
and the check is correctly inert.

---

### MEDIUM — fixed

#### M-1 · Booked foreign leg proceeds had no reachable way out · VERIFIED

`RedemptionExt.recoverLegs` books proceeds of a leg whose quote doesn't match the
generation's (`RedemptionExt.sol:707`). The facet shipped exactly one way to move
that balance — `sweepLegProceeds` (`:758`) — and one way to read it,
`legProceedsOf` (`:721`). **Neither had a dispatcher stub**, and the registry has
no fallback. Found by ABI-diffing the facet against the dispatcher, not by
reading the existing reachability test — which enumerates only three selectors
and classifies each, missing both of these. Fourth instance of the defect class
`F20_FacetReachability` documents.

**Fix.** `sweepLegProceeds` stubbed. `legProceedsOf` **knowingly left unrouted**
and pinned as such: the registry has ~15 bytes of EIP-170 headroom and only one
stub fits; the value-moving half wins, because a read-only gap is recoverable
(events + direct slot read on a facet whose storage *is* the registry's) and a
stuck asset is not. PoC: `test/attacks/T07_LegProceedsUnreachable.t.sol`.

#### M-2 · Fix-induced by C-1: `openOrAddPair`'s blanket catch · VERIFIED

My own C-1 fix created this, and a subagent caught it. `PoolOps.openOrAddPair`
wraps `initialize` in a `catch` meaning *"the pair already exists, read the live
price"*. After C-1 it also caught *"the hook refused you"*, leaving `live == 0`,
keeping the contributed price, and handing a non-existent pool to `_seedActive` —
failing far downstream as `PoolNotInitialized`, naming neither cause nor line.

**Fix.** `PoolOps.sol` — `if (live == 0) revert PoolInitRefused();`. A zero slot0
means the pool genuinely is not there, so a refusal surfaces as itself.

---

### HIGH — demonstrated, **NOT fixed**

Each has a passing PoC in `test/attacks/`. I verified the mechanism in source for
all of them; I did not re-run every PoC myself (noted per item).

| # | Finding | Location | Impact | Confidence |
|---|---|---|---|---|
| O-1 | **Oracle cache stamps the *attempt*, not the *success*** — `c.at` is written unconditionally, `c.factor` only on success, so a failing feed re-arms the TTL and the cache never expires. It is the *entire* price floor on a permissionless rotation slice. | `QuoteOracle.sol:305-312` | Measured **+1.639 ETH on 10 ETH (16.4% ROI)**; treasury slice filled 32.98% below market. Control with a live feed rejects the same attack. | VERIFIED by agent; source confirmed by me |
| O-2 | **Queued vault exits are 100% senior to live shares** — `_haircut` compares the queue against `engine.totalEth()`, the *whole* vault including live-share equity, so it only writes down once the queue exceeds every asset. The comment claims this exact scenario is fixed; the remediation moved 84%/0% to **100%/0%**. | `PerpVault.sol:285-295` | Queueing is free and strictly dominant → a bank run with a protocol-enforced starting gun. | VERIFIED by agent; source confirmed |
| O-3 | **`plvToken` is *assigned*, not adjusted, at sync** — whatever failed to migrate is silently written to zero while the engine still holds the old tokens. | `PerpEngine.sol:1049-1051` | `plvToken` 200M → **0**; engine still holds 200M old tokens with no reachable path. Recovery is owner grace (`fundPlvToken`), not a protocol path. | VERIFIED by agent; source confirmed |
| O-4 | **Anti-snipe surtax is grindable to its deterministic floor** — the "unknowable" entropy is the live pool tick, read **pre-swap**, which the taxed transaction sets. | `CauldronHook.sol:1402-1408` | 5575 vs 9551 bps, attacker's choice; **0.3976 ETH** on a 1 ETH buy. Also griefs: +2975 bps forced onto a victim. | VERIFIED by agent |
| O-5 | **Envelope hijack** — `execute` enforces neither one-envelope-at-a-time nor the cooldown that `propose` enforces, so executing winner-then-runner-up clobbers the guild's choice and zeroes `movedBps`. | `TreasuryGovernor.sol:466-498` | Loser's destination installed; slice budget silently doubles. | VERIFIED by agent |
| O-6 | **64 spam proposals permanently erase any voted mandate beyond the top two** — the cache is two deep and `_recomputeLeader`'s window only moves forward; re-entry needs a vote, and voting is closed. | `CauldronGovernor.sol:350-365, 399-430, 478-489` | `hasProposals()` false → `relaunch` reverts `NoProposal`. Repeatable every generation. | VERIFIED by agent |
| O-7 | **Treasury scan flood** — one FOR-vote every ≤5 days pins the O(1) hint on a corpse, re-exposing the unbounded scan inside `execute`. | `TreasuryGovernor.sol:430-455, 545-590` | ~3,600–7,000 junk filings (cold-gas estimate) block every envelope. | VERIFIED by agent; cold-gas arithmetic DERIVED |
| O-8 | **`MigrationVesting` grant flood** — `vestBatch` is permissionless and `_release` is unpaginated. | `MigrationVesting.sol:153-164, 221-242` | 1,077 planted grants (~160M gas) permanently freeze a targeted holder's escrow. | VERIFIED by agent |
| O-9 | **Live collection floor divides a forged-only pot by an OG-inclusive count** — same root as H-1 but unconditional, no attacker needed. | `PoolOps.sol:1382` | **12.11× under-payment** to forged holders recycling while alive. | VERIFIED by agent |
| O-10 | **Post-flip the primary leg is unrotatable and ~31.6% is stranded** — `generationQuote` flips but `generationPoolKey`/`generationPositionId` do not, so `fromLeg == 0` measures in one asset and settles in another. Compounding slices mean a 10,000-bps mandate converges on ~68% moved. | `RedemptionExt.sol:337-345, 469`; `PoolOps.sol:919` | 31.6% of the treasury unrotatable for the generation's life. **Partially mitigated by the C-3 fix** (a dust leg can no longer trigger the flip) but the compounding tail is untouched. | VERIFIED by agent |

### MEDIUM / LOW — open

- **`setTaxExempt` alone is inert** (`CauldronHook.sol:2348`): exemption requires
  `isOpener[sender]` too, and two deploy scripts set only the former
  (`DeployLaunchpad.s.sol:504`, `DeployLaunchSniper.s.sol:37`). The snipe wallet
  believes it pays 0 and pays **99%**. Fails closed for the protocol,
  money-losing for the operator. VERIFIED.
- **`minCollateral` is an absolute 18-decimal constant** (`PerpEngine.sol:144`)
  compared against collateral in whatever `quote` is. After rotation to a
  6-decimal stable, `3e15` raw = 3,000,000,000 USDG — $50k of collateral reverts
  `DustPosition()`. Fails safe. VERIFIED.
- **`quoteScale` is write-only dead storage** (`CauldronBase.sol:360`, written
  `CauldronRegistry.sol:174`/`:289`, **no reader anywhere**). The documented
  governance lever against cross-decimal volume collapse is inert; the real
  mitigation is `CauldronHook._toUsd`, which returns raw when no oracle is wired.
  DERIVED.
- **Legacy buyback is a market order with no `minOut`** (`LegacyBuyLib.sol:56-63`)
  fired inside the attacker's swap, and `fundLegacyBuffer()` is permissionless so
  the trigger timing is attacker-chosen. Unprofitable at the shipped
  `legacyThreshold = 0.02 ether`, but that threshold is a **security parameter**
  and nothing documents it as one. DERIVED.
- **`sweepLegacyReserve` takes a caller-chosen `token`** while the counter it
  debits accrues in the iteration token (`CauldronHook.sol:1102-1109`).
  Trusted-caller only, but an accrual-asset ≠ payout-asset gap with no invariant.
  VERIFIED.
- **`TreasuryGovernor`'s guardian is unremovable and self-perpetuating**
  (`:503-513`), holds more than "stop" (`setQuoteOracle` → a reverting oracle is
  a second, quieter permanent veto), and the constructor zero-checks none of
  `_mifrens`/`_registry`/`_guardian`. DERIVED.
- **`renounceOwnership` is live on `CauldronGovernor` and `MigrationVesting`**
  (the registry blocks it at `CauldronBase.sol:409`; neither of these inherits
  that). Renouncing `CauldronGovernor` before `setRegistry` leaves `relaunch`
  unable to ever consume a winner. Narrow window, terminal outcome. DERIVED.
- **Gacha reveal is grindable** (`MiFrensGenesis.sol:532-537`): the expired-seed
  re-anchor gives unlimited free re-rolls because declining a revealed outcome
  costs nothing. 44 re-rolls reached the 1% tier; `revealBatch` amortises it to
  50 draws per tx. `rarityOf` has no economic consumer — collectible-fairness
  break, not a fund drain. VERIFIED.
- **TEST-SUITE INTEGRITY:** relative `vm.warp` is common-subexpression-eliminated
  under `via_ir` — **nine existing test functions do not advance time as
  written**, including `test_FullLifecycle_ToRound3_OnFork`, which claims to
  cross three generation lifetimes and crosses one. VERIFIED. Not fixed; listed
  in §6.

---

## 4. Leads — believed real, not demonstrated

1. **`_sequencerOk()` as a *scheduled* attack window.** `QuoteOracle.sol:320-341`
   returns false for the whole grace period after a sequencer restart — a
   publicly announced, recurring window in which O-1's frozen floor is guaranteed
   active. *Next step:* parameterise `T02_StaleFloorSandwich` with
   `setSequencer(feed, grace)` and measure extraction across a realistic 30-min
   grace with a real L2 restart price gap.
2. **`arbStep` under the same frozen cache.** `QuoteRotator.sol:496-560` gates on
   `minArbProfitUsd`/`maxArbNotionalUsd`, both judged through the same cache.
   *Next step:* call `arbStep(cheap, dear, amountIn)` post-freeze, measure
   treasury PnL vs the keeper's 10%.
3. **Hook volume collapse without a wired oracle (M `quoteScale`).** *Next step:*
   boot with `quoteOracle` unset, rotate to the 6-decimal quote, drive equal
   *dollar* volume through both legs, read `isDead()`. If the generation reads
   dead, this becomes a permissionless-relaunch HIGH.
4. **`PerpMarkSource.primary` does not follow a rotation** and `addPool` reverts
   `WrongPair` for the new pair, so the mark cannot even be re-aimed. Measured
   **112,805,296× overstatement**. **Currently latent** — `markSource` is absent
   from `indexer/deployments/round.json`, and `_currentTick` falls back to
   `getSlot0(_key())` when unset, which does follow the rotation. A landmine for
   whoever wires it; the deploy script tells them to.
5. **`_castSpell` violates CEI** (`MiFrensDividend.sol:396-397`) — external call
   before `activeShares += 1`, no `nonReentrant`. Unreachable today; re-test if
   the enchant fee is ever denominated in a rotated third-party quote.
6. **`_leadVotes` as a permanent poisoning primitive.** O-7 assumes the corpse's
   vote count beats later honest proposals. *Next step:* rent ~10% of MiFrens for
   one block, vote an unbeatable high-water mark, never execute. Needs a real
   `ERC721Votes` MiFrens.

---

## 5. Proven safe — attacked hard, held

- **Delegatecall storage layout.** Not merely correct today — *structurally*
  impossible to break. 60/60 slots identical; all six libraries declare zero
  storage; `sstore`/`sload`/`.slot`/`assembly` grep on `FeeRouteLib` and
  `LegacyBuyLib`: **zero hits**.
- **In-swap gas-cap underflow.** All four gas-capped sites have MIN > RESERVE
  (`750k>350k`, `500k>200k`, `300k>220k`, and the liq site is written correctly
  as `g > RESERVE + MIN`). The 63/64 rule only bites above 22.4M gas — past any
  block limit.
- **No attacker-growable loop in the swap hot path.** `_recordVolume` clamps to
  `HOURS_PER_DAY`, the sibling loop to `MAX_SIBLINGS = 9`, `_commitCrystals` to
  `MAX_MINTS_PER_CALL = 30`. `linkVolume` *looks* permissionless and is
  registry-only (`CauldronHook.sol:1552`).
- **hookData spoofing.** `_taxedPlayer` refuses hookData unless
  `isOpener[sender]`; both consumers route through it.
- **The gacha commit/reveal is NOT grindable** (unlike the surtax): seeded from
  `blockhash(b.commitBlock)` with a hard future-block guard, FIFO resolution, and
  wins minted to `b.player` not the caller. This is the shape O-4 needs.
- **Unchecked `transferFrom` at `PerpEngine.sol:1559`/`:1653` — REFUTED.** Both
  real, both unexploitable: `onlyOwner` and `onlyVault` respectively, the vault
  caller already `_pull`s with a checked return, and the token is always
  `CauldronToken`, a plain OZ ERC20 with no fee-on-transfer and no false-return.
  Definitively closed. (Still worth `_safeTransferFrom` for defence in depth.)
- **The truncating casts at `PerpEngine.sol:1478-1481` — REFUTED.** They live in
  `_killStats`, whose only consumer is the badge's metadata. A clamp misreports a
  collectible; it moves no value.
- **`creditPerpFeeToken` being `payable` is correct, not odd** — it credits the
  token stakers' *ETH* reward pot. All three entrypoints are hook-gated.
- **Bounty-before-solvency.** `_tryLiquidate` checks `_underwaterVal` before any
  payout; `liquidate(1)` returned `Healthy()` even with the engine bricked.
- **First-depositor share inflation.** `OFFSET = 1e6` virtual shares; an attacker
  must donate ~1e6× the victim's deposit.
- **Rotation back to ether works** — `address(0)` overloading refuted:
  `allowedQuote[address(0)] = true` in the constructor, `_requirePriceable`
  exempts native, and `allowance` uses `remainingBps` not the address as the
  liveness flag.
- **Caller-supplied rotation venue — already closed** at `QuoteRotator.sol:355`
  (`allowedVenue` keyed by `PoolId`), and `_routeMatches` checks **both**
  directions. The predecessor session's "94% of the slice extracted" claim was
  **retracted as not reproducible**.
- **Dividend basket.** Per-asset accumulators, no cross-asset denomination;
  `_tryPush` banks failed legs so **one hostile ERC20 cannot grief other
  holders**; the transfer-gas reservation (260k forwarded of 320k) exceeds the
  measured 202k worst case. No value accrues in a token and pays in native wei.
- **Mint integrity.** No `_safeMint` anywhere — so no `onERC721Received` surface
  on mint/claim at all. Exact payment, strict supply check, disjoint badge id
  namespace, no double refund.
- **`claimProposerFees` accrual asset == payout asset** — `_routeEthFee:1249`
  skips the proposer carve entirely for a non-native fee asset, falling through
  to the correct per-asset bucket. Independently re-derived.

**PoCs that failed (recorded as results):** a single dust perp position bricking
the engine (refuted — the floor is a full 64-position book); the "force-close gas
exceeds a block" premise (refuted — 7.46M for 64, well inside 30M; the damage was
the `NotDead()` gate, not the gas); `_beforeSwap` fee-bypass across all eight
quadrants (no untaxed quadrant in either orientation).

---

## 6. Coverage gaps

- **Nine test functions silently do not advance time** (see §3). A test asserting
  three generation lifetimes exercises one. Mechanical fix: capture `t0` once and
  warp absolutely.
- **Production wiring is untested for the governor.** C-4 existed because every
  governor test binds a mock. `T08_GovernorQuorumWiring.t.sol` now closes this
  for the quorum specifically; the pattern deserves a sweep.
- **15 invariant functions early-return on `if (!active)`** with no `vm.skip`, so
  without fork env they report green having asserted nothing. With fork env they
  do run (verified: 7/7, 80 calls, 9 reverts).
- **`LedgerInvariants` codifies the H-1 brick as correct** (`:126-131`) — its
  handler uses one `ghostMinted` for both live and frozen bases, so it cannot
  model the continuation's dual-base situation.
- **No test drives a non-native (ERC20-quoted) perp book.** `YBase._boot` only
  stands up a native-quote generation, so `creditPerpFeeAsset` and the ERC20
  payout path were read, never executed.
- **Hostile quote tokens** (fee-on-transfer, rebasing, blocklist, no-return-bool)
  were reasoned about and never PoC'd. Structurally they fail closed
  (`QuoteRotator._swap` takes `out` from `BalanceDelta`, not a balance diff).
- **`PerpStakerOracle` / `PerpMarkSource`** have no live instance in the harness.

---

## 7. Decontamination report

**Built** `/tmp/blind-final` + six cloned working trees. Excluded `lib/`, `out/`,
`cache/`, `broadcast/`, `audit/`. **Quarantined** `test/attacks/` and
`test/audit/` (the answer-key suites) and all four in-tree `.md` files. **Kept**
legitimate coverage (`test/*.t.sol`, `final/`, `functional/`, `invariants/`).

**Stripped** finding-ID anchors from comments with a Solidity-aware scrubber that
never touches code or string literals: 111 files on the first pass, plus a second
pass for refs straddling a comment line-break (`(audit\n/// C-01b)`). Verified:
`grep -rnE '[A-Z]{1,2}-[0-9]{1,2}'` over non-test, non-lib sources returns
**nothing**.

**Byte-identical build confirmed.** All 31 protocol contracts compile to
identical runtime *and* initcode sizes in the blind tree vs. the real tree —
diff empty. Comments and removed test files changed no bytecode.

**Residual leak — what I could not remove:**
- Prose shape still signals prior review: *"The old line was never doing that
  work"*, *"Two things went wrong downstream"*, *"Measured, pre-fix"*. Several
  comments narrate a fix without naming an ID.
- Variable and constant names encode considered threats: `everMoved`,
  `_inRelaunchClose`, `RELAUNCH_TAIL_RESERVE`, `QUOTE_WATERMARK`,
  `migrationMandateSpent`.
- Four bare `audit`/`Gas audit` mentions survived in `CauldronHook.sol`
  (`:317, :652, :2345, :2384`) with the IDs removed but the word intact.
- One `require` string in a deploy script retains a literal tag
  (`DeployLaunchpad.s.sol:184`) — it is in a string literal, so stripping it
  would have changed bytecode.
- The quarantined `YBase.sol` had to be restored (scrubbed) because legitimate
  functional suites import it.

I claim blinding of *finding identifiers*, not of *the fact that this code has
been reviewed before*. The latter is not removable without rewriting the source.

---

## 8. Reconciliation

Read only after the findings above were written and sealed.

**New / still-open — the point of the pass.**
- **C-1 (pool-key squat)** — not in any prior document. `DEEP_AUDIT_2026-09-08`
  touches CREATE2 squatting only to declare it a **blind spot**: *"`A01_Create2Squat`
  passes… but I did not independently re-derive that the mined hook address's
  permission bits match."* Nobody connected the predictable token address to the
  bare `initialize` in the relaunch path.
- **C-2 (perp survivor strand)** — no prior mention of `forceClosePerps`,
  survivors, or the `_isDead()` live-read. New.
- **C-4 (governance DOA)** — no prior document contains the string `totalSupply`.
  New, and the most consequential: treasury rotation has never worked.
- **H-1 / O-9 (tranche base mismatch)** — new.
- **M-1 (`sweepLegProceeds` unreachable)** — `legProceeds` appears in
  `REMEDIATION_2026-09-11.md` only as *"the delegatecall facet cannot corrupt
  registry state"*. Its reachability was never checked.

**Fix-induced — bugs a remediation introduced.**
- **C-3 is a direct regression of R-04**, dated the same day. R-04 correctly
  diagnosed "exhaustion ≠ completion" and replaced an `address(0)` test with a
  `movedBps` test — one accounting test for another. It did not ask what the bps
  were a share *of*, and `rotateSliceFrom`'s multi-leg selection made that the
  hole. The prior report even states the compounding caveat honestly ("a small
  tail can remain") without noticing the leg-selection problem beside it.
- **M-2 is a regression of my own C-1 fix**, caught by a subagent, fixed.

This is the third consecutive pass in which remediation introduced findings —
`REMEDIATION_2026-09-11` itself logs two NEW Criticals found while fixing (R-08,
R-09). The pattern is now the strongest signal in this codebase.

**Re-confirmed safe — prior-fixed areas I attacked independently and could not break.**
- **R-01** (attacker venue + attacker `minOut`): `allowedVenue` keyed by `PoolId`
  and `_routeMatches` checking both directions both hold. The successor claim of
  a 94% extraction was retracted under re-test.
- **R-03** (`address(0)` overloading): rotation back to ether proposes, votes and
  executes cleanly.
- **R-05** (spent envelope locking governance): `active` is cleared on
  exhaustion; held.
- **R-06** (governance spam wedging `winner()`): the *bounded* scan holds — but
  O-7 shows the O(1) hint that makes the bound cheap can be pinned on a corpse,
  and O-6 shows the two-deep cache erases mandates beyond the runner-up. The fix
  held; the surface next to it did not.
- **L-3 / PerpVault queue**: the prior pass fixed 84%/0%. It is now 100%/0% (O-2).
  Fixed, then re-broken in the same area.

**Missed by me.**
- **R-02** (a completed rotation bricking `relaunch`) — I did not rediscover it.
  Genuinely fixed: the `oldQuote` path reads the primary pool, and my C-3 work
  traversed that code without finding a way through.
- **R-07** (a comment instructing operators to strand the engine) — a
  documentation fix; my method (execute features, don't read prose) was
  structurally blind to it.
- **R-09** (one wei of dust bricking vault replacement) — did not look there.
- The **gas/deploy-cost** review (`IndependentReview-Gas-DeployCost.md`) — out of
  the scope I set.

---

## 9. Blind spots — what I could not reach or run

- **The off-chain stack was never reviewed.** The `api/`, `indexer/` and `src/`
  agent died to a session limit on its first call and was not relaunched.
  So: **no route table, no OAuth review, no LLM-route rate-limit or
  cost-amplification analysis, no `dist/` secret scan, no "can a lying indexer
  induce a harmful signature" trace.** The prompt weighted these heavily and
  they are entirely absent. This is the largest gap in the report.
- **Frontend** `npm run dev` / type-check / build were never run.
- **The four fixes have not been run together against a live multi-generation
  lifecycle** on a fork — only individually and against the full suite.
- **`indexer/deployments/round.json` was read for parameters** (it is how I
  established `markSource` is unwired) but the live deployment was not otherwise
  examined.
- **Cold-gas numbers for O-7 are arithmetic, not measured** (the flood and the
  measurement shared a transaction, so 602 gas/proposal is a warm-storage floor).
- **Agent discard count: 0.** Every subagent finding I report here I
  independently located in source; the three Criticals I re-ran myself. One
  agent claim (the 94% venue extraction) was retracted by its own successor
  under re-test, and one (`PerpMarkSource`, O-4/lead 4) I **downgraded** from the
  agent's HIGH to latent after confirming `markSource` is unwired in production —
  that correction is mine, not theirs.

---

## Final line

**Would I deploy this to mainnet today? No.**

Four Criticals down — including one that meant treasury governance had never
functioned — is real progress, and the permanent-brick class is now closed at
every point I could find it. But ten Highs remain demonstrated and unfixed, two
of them extracting real value rather than merely griefing, and the entire
off-chain surface is unreviewed. Fix the Highs, review the API and indexer, then
re-run this pass against the fixes — because in this codebase the fix has been
the bug three passes running.
