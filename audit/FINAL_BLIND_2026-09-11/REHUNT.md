# REHUNT — blind attack on the neighbourhood of `1e98bb4..HEAD`

Date: 2026-09-12. Scope: `contracts/solidity`. 21 contracts + their tests.
Profile `cauldron`. PoCs at `test/attacks/X8*`, all run with `-vv`.

> **The tree moved while I worked.** At session start `HEAD` was `3ee07ac`; my first
> command saw `6459b85`; by the time I finished, `HEAD` was `9a1254d` with a large
> UNCOMMITTED working-tree diff across `CauldronHook`, `PerpEngine`, `QuoteOracle`,
> `QuoteRotator`, `RedemptionExt`, `SurtaxLib`, `TreasuryGovernor`, `MigrationVesting`,
> `FeeRouteLib`, `PerpSwapLib`. Line numbers below are as of the **working tree at the
> time of the final PoC run**, and every PoC was re-run against that tree and still
> passes. Two of my candidate findings turned out to be already in flight in that
> uncommitted diff (see refutations R8, R9) — I do not claim them.

---

## 1. What I attacked, and how I chose it from the diff

`git diff --stat 1e98bb4..HEAD` put the mass in eight places. I picked targets by the
method's own shapes rather than by file size:

| cluster | lines | shape I went after |
|---|---|---|
| `CauldronHook` (194) + new `SurtaxLib` (106) | | **rule 4 — code MOVED** behind a linked library; **rule 6 — denomination**: `legacyBuffer` gained an asset tag |
| `TreasuryGovernor` (172) + `CauldronGovernor` (91) | | **rule 5 — a new bounded window**: both grew an 8-slot `_bench` and both replaced their fallback scan with it; **rule 3 — siblings**, two governors, one shape |
| `RedemptionExt` (153) + `CauldronRegistry` (63) | | **rule 4** — `claimByBurnUpTo` moved behind a delegatecall stub, `recoverLegs` split into a gated public entry + an ungated teardown entry reached only by a raw selector |
| `PerpEngine` (109) + `PerpVault` (39) | | **rule 2 — new state** (`ringArmedAt`, `payoutOwedTotal`); **rule 3 — a guard widened from one counter to five**; **rule 1** — `claimPendingEth` changed revert → return |
| `QuoteRotator` (65) | | **rule 1 — failure mode changed**: `_oracleFloor == 0` went from "no floor" to a hard `NotPriceable` revert on a permissionless path |

The widened guard at `PerpEngine.syncGeneration` is where I spent most of the budget,
because it is the textbook version of rule 3: a guard that used to name **one** counter
now names **five**, and nobody appears to have asked, for each of the four new ones,
*who is able to drive it to zero.* Three of the five can be. Two cannot.

---

## 2. Findings

### X8-01 — the insurance buffer the deploy script arms is the one counter nobody can clear, and `syncGeneration` refuses a quote rotation while it is non-zero

- **id**: X8-01
- **severity**: **Critical** (permanent brick of a core promise — live quote rotation —
  at zero cost, reached by the shipped default configuration with no attacker at all)
- **confidence**: VERIFIED (PoC runs, asserts on the `VaultStaked()` selector, and a
  control proves the harness is not the blocker)
- **file:line**:

  `cauldron/PerpEngine.sol:1157` — the widened guard:
  ```solidity
  if ((plv | tokYieldEth | insuranceEth | payoutOwedTotal) != 0) revert VaultStaked();
  ```

  `cauldron/PerpEngine.sol:1679` — the funder is **permissionless**:
  ```solidity
  function fundInsurance(uint256 amount) external payable {
      _pullQuote(msg.sender, amount);
      insuranceEth += amount;
  }
  ```

  `cauldron/PerpEngine.sol:1919-1923` — the only writer that lowers it, floored:
  ```solidity
  function skimInsurance(uint256 amount, address to) external onlyOwner {
      if (to == address(0)) revert BadParam();
      uint256 riskMin = ((longOiEth + _quoteEth(shortOiToken)) * maintenanceBps) / BPS;
      uint256 protect = insuranceFloor > riskMin ? insuranceFloor : riskMin;
      if (insuranceEth < protect + amount) revert BadParam();
  ```

  `deploy/DeployPerp.s.sol:94-97` — the floor is armed at deploy, by default:
  ```solidity
  engine.setVaultLimits(
      vm.envOr("MAX_UTIL_BPS", uint256(8_000)),
      vm.envOr("INSURANCE_FLOOR_WEI", uint256(0.05 ether))
  );
  ```

  `cauldron/PerpEngine.sol:842` and `:880` — and the buffer must be **above** that floor
  or the engine will not trade at all:
  ```solidity
  if (insuranceFloor > 0 && insuranceEth < insuranceFloor) revert InsurancePaused();
  ```

  `cauldron/PerpEngine.sol:1382` — what "did not adopt" costs:
  ```solidity
  if (quote != registry.generationQuote(registry.currentGeneration())) return true;   // _isDead()
  ```

- **precondition**: the engine is deployed by `deploy/DeployPerp.s.sol` (so
  `insuranceFloor == 0.05 ether`), the buffer holds at least the floor (which it must,
  or every `open` reverts `InsurancePaused`), and the treasury completes a quote
  rotation so `registry.generationQuote(gen) != engine.quote()`.

- **sequence**:
  1. `setVaultLimits(8_000, 0.05 ether)` — the deploy script, verbatim.
  2. `fundInsurance{value: 0.05 ether}(0.05 ether)` — required for opens to be live.
     No permission needed; anyone may do it, including a stranger.
  3. A completed treasury rotation flips `generationQuote[gen]` (the divergence this
     guard was written for; `RedemptionExt.sol:487`).
  4. `syncGeneration()` — permissionless, the documented way the engine follows a
     rotation — reverts **`VaultStaked()`**.
  5. The owner tries to clear the blocker. `skimInsurance(0.05 ether, …)` reverts
     `BadParam` (`insuranceEth < protect + amount`). So does `skimInsurance(1, …)`:
     **not one wei is skimmable while the floor is armed.**
  6. `syncGeneration()` again — `VaultStaked()`. Forever.

  The two requirements are **mutually exclusive by construction**: `insuranceEth >=
  insuranceFloor` is the condition for the engine to accept an open, and
  `insuranceEth == 0` is the condition for it to adopt a rotated quote. A healthy
  engine can never follow a rotation, and an engine that can follow one is paused.

- **attacker_cost**: **zero — no attacker is required.** The shipped deploy default
  reaches it. If a deployment sets `INSURANCE_FLOOR_WEI=0`, the same lock is still
  available to a stranger for **1 wei** of `fundInsurance` (PoC test 2 measures this:
  the sync fails, the owner skims the wei, the sync then succeeds — so with the floor
  at zero it is a grief the owner can undo, and with the floor armed it is permanent).

- **damage**: `_isDead()` returns true for as long as `quote` disagrees with the
  generation's quote, so from the moment the rotation completes the engine
  **force-closes its book and refuses every open, permanently, for the remaining life
  of the generation**. LP principal is not stolen (`quote` stays put, so `plv` keeps
  paying in the asset it was staked in) — this is a liveness brick, not a theft. The
  only recovery is a relaunch, i.e. the death of the generation, because a relaunch
  clamps the quote to native and takes the `newQuote == quote` path. This is the exact
  F-10/F-11 state the guard exists to prevent, reached through the one door the fix did
  not check.

- **poc path**: `contracts/solidity/test/attacks/X8a_InsuranceFloorFreezesRotation.t.sol`
  - `test_TheDeployedInsuranceFloorPermanentlyBlocksQuoteAdoption` — PASS, asserts
    `syncSel == PerpEngine.VaultStaked.selector`, `skimAll == false`, `skimOne == false`,
    `insuranceEth` unchanged, `quote()` never adopted.
  - `test_ControlEmptyBufferRotatesAndOneStrangerWeiStopsIt` — PASS, control: the
    identical rotation on an identical engine with an empty buffer **succeeds** and
    `quote() == usdg`, and one stranger wei turns it back into `VaultStaked()`.
  - `-vv` assertions confirmed executed: **yes** (3 tests, 0 failed; the control's
    positive assertion `adopted == address(usdg)` is what rules out a fixture artefact).

**Note on the sibling.** `payoutOwedTotal` in the same `|` is the *other* counter no
third party can be forced to clear. I derived that independently before finding that
the **uncommitted** working tree already fixes it with a timelock-only `retirePayout`
(tagged "red-team X3i", PerpEngine.sol around :1495). I do not claim it. What matters
here is that the same audit pass fixed one of the two unclearable counters and left the
other — and the one it left is the one the deploy script *arms on purpose*, and the one
the engine *needs non-zero to function*.

---

### X8-02 — the relocated surtax jitter is block-shoppable (already accepted in-file; the stale claim is not)

- **id**: X8-02
- **severity**: **Low** (hygiene — the behaviour is documented and accepted; what is
  wrong is a contradictory comment that is still in the file)
- **confidence**: VERIFIED
- **file:line**: `cauldron/SurtaxLib.sol:120-124`
  ```solidity
  uint256 rnd = uint256(
      keccak256(
          abi.encodePacked(blockhash(block.number - 1), PoolId.unwrap(id), block.number, block.prevrandao)
      )
  ) % (maxBps + 1);
  ```
  `cauldron/SurtaxLib.sol:69-88` already states the true property ("an earlier version
  of this comment claimed a sniper 'can't pick a guaranteed-cheap block', and that was
  never true … Accepted deliberately"). But **`SurtaxLib.sol:100-101` still says the
  opposite** in the same function: "the previous blockhash (known to everyone during
  block N, **but not to a sniper choosing which block to submit into**)".
- **precondition**: Arbitrum/Orbit, where `block.prevrandao` is the constant 1 (the
  file says so at :102-104).
- **sequence**: every operand of the seed is fixed before block N is built —
  `blockhash(N-1)` seals with block N-1, `poolId` is static, `N` is the next number,
  `prevrandao` is 1. An observer at the chain head computes the exact surtax for the
  next block and submits only into cheap ones.
- **attacker_cost**: one block of latency per skipped draw.
- **damage**: measured over 64 candidate blocks at `maxBps = 1000`, `window = 200`:
  cheapest **690 bps**, dearest **1000 bps**, and the cheapest is *exactly* the
  published deterministic decay at that block (690) — the jitter contributes nothing to
  a shopper. 0/64 predictions missed.
- **poc path**: `contracts/solidity/test/attacks/X8b_SurtaxJitterBlockShoppable.t.sol`
  - `test_TheSurtaxForTheNextBlockIsKnownBeforeSubmittingIntoIt` — PASS.
  - `-vv` assertions confirmed executed: **yes** (`mismatches == 0`, `lo < hi`,
    `lo < 0.9*hi`, `lo >= decayedAtLo`; logged 690 / 1000 / 690).
  - Actionable part: delete or correct `SurtaxLib.sol:100-101`. A file that documents
    both "X is true" and "X was never true" in one function will mislead the next
    reviewer in whichever direction they read first.

---

## 3. Refutations — surfaces I attacked hard that held

**R1 — the 8-slot `_bench` cannot be filled with dust to erase a live mandate.**
My best theory was that the bench would treat a proposal *still taking votes* as weight
0 (the shape that would let 8 junk filings with one MiFren evict the guild's mandate
mid-vote, reintroducing B-10 through the new window). It does not.
`TreasuryGovernor._dead` (`cauldron/TreasuryGovernor.sol:728-731`) tests only
`executed || cancelled || past EXECUTION_WINDOW`, with an explicit note that "a proposal
still taking votes is not executable YET but is very much alive"; `_benchRecord`
(`:527-543`) therefore scores an open proposal at its full `forVotes`. Same in
`CauldronGovernor._benchRecord` (`cauldron/CauldronGovernor.sol:~428`): `q.exists &&
!q.consumed`, with no `votingEndsAt` test, so an open mandate holds full weight.
Displacing an incumbent strictly requires out-voting the weakest live mandate. I traced
the eviction order by hand for empty / dust-filled / full benches; dust never displaces
a voted mandate. **Held.**

**R2 — vote weight cannot be replayed to manufacture high-vote junk.** The follow-up
attack on R1 was to cycle one MiFren through N addresses to inflate junk bench entries
past a real mandate. Both governors weigh by
`mifrens.getPastVotes(msg.sender, p.snapshot)` (`TreasuryGovernor.sol:463`,
`CauldronGovernor.sol:398`) and gate with `hasVoted[id][msg.sender]`
(`:461`, `:392`), so a transfer after the snapshot yields zero. Bench capture reduces
to ordinary governance capture. **Held.**

**R3 — `consume`'s new primary/secondary split does not starve the migration and does
not overflow.** I walked the arithmetic for a full-position envelope: a stranger
spending 10,000 bps out of a secondary leg drives `movedBps` to the cap but leaves
`movedPrimaryBps` at 0, so `allowance()` (`TreasuryGovernor.sol:745-767`) still reports
the entire migration budget and the deactivation test
(`cap >= BPS_ONE ? movedPrimaryBps >= cap : movedBps >= cap`) keeps the envelope live.
`movedBps` peaks at `2 * cap == 20_000`, comfortably inside `uint16`. No starvation, no
wrap. **Held.**

**R4 — the two gates added to `execute` cannot be used to burn a cooldown cheaply.**
I looked for a junk proposal that consumes `lastEnvelopeAt` and thereby kills the
guild's alternative. `execute` still requires `_passed` (`:868-881`), i.e. quorum
against `getPastTotalSupply(p.snapshot)` **and** `forVotes > againstVotes`, so burning
the cooldown costs a real majority. **Held.**

**R5 — `swapOnce`'s new `NotPriceable` cannot brick a rebirth, and `_usdLive` is not
dead on arrival.** I grepped every caller of `swapOnce` across `contracts/solidity`
excluding tests: the only one is `cauldron/RedemptionExt.sol:398` inside
`rotateSliceFrom`. The teardown/relaunch path does not touch it, so the new hard revert
cannot propagate into `relaunch()` (the B-05 shape). And `_usdLive`'s `staticcall`
target really is a view — `QuoteOracle.sol:202: function usdPerRawUnit(address quote)
external view returns (uint256 factor)` — so the uncached floor is live rather than
permanently 0. **Held.**

**R6 — `MigrationVesting`'s two caps are not bypassable from the permissionless side.**
`startVest` is `msg.sender`-keyed (`cauldron/MigrationVesting.sol:167,173`), so the only
third-party route into `_pullAndVest` is `vestBatch`, which skips at
`MAX_BATCH_GRANTS == 32` (`:198`). A spammer therefore cannot consume the 32 slots
`MAX_GRANTS == 64` reserves for the holder's own migration, and `_release` (`:262-283`)
walks at most 64 entries and prunes drained ones. **Held.**

**R7 — the two relocated bodies keep their contract with callers.**
`CauldronRegistry._forwardToExt` (`:1457-1468`) rejects a zero facet and bubbles both
returndata and revert data verbatim, so the moved `claimByBurnUpTo` and the new gated
`recoverLegs` stub cannot silently no-op the way the pre-fix facet-direct calls did. The
teardown selector really is distinct (`RECOVER_LEGS =
bytes4(keccak256("recoverLegsAtTeardown(uint256)"))`) and really has no forwarder, so
the ungated entry is unreachable externally. **Held.**

**R8 — `payoutOwedTotal` (already in flight, not claimed).** I derived the same lock
through the `payoutOwed` door: `_payOut` forwards only 30k gas, credits on failure, and
`claimPayout` is `msg.sender`-keyed, so one wei owed to a permanently-reverting contract
pinned `payoutOwedTotal` non-zero forever. The **uncommitted** working tree already adds
`retirePayout(address) external onlyOwner` for exactly this, tagged "red-team X3i".
Refuted as a new finding; noted because it makes X8-01 the surviving half of a pair.

**R9 — surtax block-shopping is already accepted in-file.** See X8-02. I reproduced it
with numbers before reading the tail of the file (my first `git diff` read was truncated
at 420 lines and cut off `SurtaxLib.sol:69-88`). The behaviour is documented and
deliberately accepted; only the contradictory sentence remains actionable.

---

## 4. Leads, with the exact next step

**L1 — the codeless-recipient check landed in two files and skipped a third.** This pass
added `if (to.code.length == 0) return false;` to `FeeRouteLib` (two sites) and
`if (token.code.length == 0) revert TransferFailed();` to `QuoteRotator._safeTransfer`.
`PerpEngine`'s own transfer helpers did not get it: `_pullQuote`
(`cauldron/PerpEngine.sol:196-209`) accepts `ret.length == 0` as success, so a `quote`
with **no code** reports a successful `transferFrom` and the caller credits `plv`,
`insuranceEth` or a trader's collateral against nothing that moved.
*Next step*: `grep -n "code.length" cauldron/PerpEngine.sol` (expect no hit inside
`_pullQuote`/`_safeTransfer`/`PerpSwapLib.tryTransfer`), then PoC with a registry whose
`generationQuote` is an undeployed address and `fundInsurance`/`open` against it.

**L2 — `legacyThreshold` is a bare scalar and `legacyBuffer` is now explicitly
per-asset.** `CauldronHook._maybeLegacyBuyback` flushes the buffer to the reserve only
when `legacyBufferAsset != Currency.unwrap(live.currency0)` — a **matching**-asset
buffer below `legacyThreshold` is neither spent nor released, and
`releaseRelaunchAsset` does not see `legacyBuffer`. On a 6-decimal quote an ETH-sized
threshold is ~1e12× too large, so the buyback never fires and the whole `legacyBps`
carve accumulates with no exit at any privilege level.
*Next step*: read `setLegacyBuyback` for whether the threshold is re-settable per
generation, and grep the relaunch path for any sweep of `legacyBuffer`.

**L3 — `vaultSwept` native wei on a non-native rebirth.** `PoolOps.sol:1077,1088,1090`
now return `0` for the third value from branches 1 and 3, on the (correct) grounds that
wei must not be divided by 6-decimal units. The comment says "the wei just lands in the
registry".
*Next step*: grep `CauldronRegistry` + `RedemptionExt` for a native `sweep`/`withdraw`
that can reach that balance. If there is none, every non-native rebirth strands the
dying vault's whole ETH sweep permanently.

**L4 — `PerpVault.claimPendingEth`'s total write-down now persists.**
`if (owed == 0) { emit ClaimEth(msg.sender, 0); return 0; }` banks a zero where it used
to roll back. A staker who claims at a moment when `engine.totalEth() == 0` permanently
forfeits the queued exit even if the engine is re-funded in the next block.
*Next step*: establish whether `plv + longOiEth` can legitimately reach 0 with queued
exits standing (`_absorbPlvLoss` then `fundPlv`), then PoC the forfeit-and-refill.

**L5 — `NotPriceable` may make "rotate home to ether" unreachable.**
`QuoteRotator.sol:389` (`if (floor == 0 && quoteOracle != address(0)) revert
NotPriceable();`) refuses whenever either side is unpriceable, and
`usdPerRawUnit(address(0))` returns 0 when no native feed is configured
(`test/F15_QuotePriceability.t.sol:90` asserts exactly that).
*Next step*: check `deploy/DeployRotationStack.s.sol` for a feed registered against
`address(0)`; if none, no deployment with an oracle can ever rotate to or from ether.

**L6 — an 8-slot bench is entered only on a vote, and `CauldronGovernor` stockpiles
mandates indefinitely.** A 9th simultaneously-live mandate that loses the bench race is
invisible to `_recomputeLeader` forever unless someone casts another vote on it after a
slot frees. The `TreasuryGovernor` comment argues 9 is unreachable there (6-day
lifetimes); that argument does not transfer to `CauldronGovernor`, whose own comment
says a brew mandate "is STOCKPILED against the next death, which may be months away".
*Next step*: PoC 9 settled unconsumed mandates, consume 8 across 8 relaunches, and check
whether the 9th is still reachable by `winner()` / `hasProposals()`.
