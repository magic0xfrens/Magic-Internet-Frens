# H2 — Lifecycle & governance (QuoteRotator, QuoteOracle, RedemptionExt, TreasuryGovernor, CauldronGovernor)

Branch `redteam/2026-09-11`. All work done in a decontaminated copy at
`/tmp/blind-final-h2/contracts/solidity`; PoCs copied verbatim into the real tree and re-run there.

## 1. Model from code

**TreasuryGovernor** (`cauldron/TreasuryGovernor.sol`). `propose(quote,maxTotalBps)` — gate: 5 MiFrens
(`PROPOSAL_THRESHOLD`), allowlisted quote, priceable (native + unset-oracle exempt, :932-936), no live
envelope, cooldown elapsed. `vote(id,bool)` — power snapshotted at `block.number-1`. `execute(id)` —
permissionless, requires `_passed` + `id == winner()` + inside `EXECUTION_WINDOW` + re-checks
allowlist/priceability. `cancel`/`setGuardian`/`setQuoteOracle` — guardian only. `winner()` = O(1) hint
(`_leadId`) validated by `_executable`, falling back to an 8-slot `_bench` keyed on FOR-votes.
`allowance()`/`consume(bps,fromPrimary)`/`migrationMandateSpent()` — registry-only writes; a migration
mandate (`maxTotalBps >= 10_000`) meters on `movedPrimaryBps`, a partial one on the shared `movedBps`.

**RedemptionExt** (delegatecall facet). Reached through `CauldronRegistry` forwarders at :246, :270,
:280, :296, :306 and `_forwardToExt` (:1505). `rotateSliceFrom(fromLeg,sliceBps,minOut,route)` is
**permissionless**: reads the envelope, removes a slice from the named leg (`PoolOps.removePartial`),
sends the quote side to `QuoteRotator.swapOnce`, pulls it back, unwinds the destination leg in full and
re-mints one position, `linkVolume`s it, `_recordLeg`s it, then `consume(sliceBps, fromLeg == 0)` (:514)
and — only if `fromLeg == 0 && migrationMandateSpent()` — flips `generationQuote[gen]` and best-effort
`syncGeneration`. `recoverLegs` (past gens only) / `recoverLegsAtTeardown` (no stub, teardown only) /
`sweepLegProceeds` (onlyOwner). Redemption: `redeemOgFren`, `buyTreasuryOgFren`, `donateToReserve`,
`materializeLegacyReserve`, `claimByBurnUpTo` — all denominated in the generation TOKEN, not the quote.

**QuoteRotator**. `swapOnce`/`withdraw` gated `onlyRegistry`; venue allowlist by `PoolId`; floor =
`_oracleFloor` from the **uncached** oracle, `floor == 0 && quoteOracle != 0` reverts `NotPriceable`;
fill must clear `max(minOut, floor)`. `arbStep` permissionless, both venues curated, both legs priced
live, per-block notional cap. Config `onlyOwner`.

**QuoteOracle**. `usdPerRawUnit` view fails to 0 on pegged/absent/sequencer/revert/stale/out-of-band;
`cachedUsdPerRawUnit` retains the last good factor but only advances `at` on a real refresh.

**Cross-subsystem**: `CauldronRegistry.relaunch` :841 `governor.hasProposals()` else `NoProposal()`,
:903 `governor.winner()`; rotation completion calls `PerpEngine.syncGeneration`.

---

## 2. Findings

```
id: T2b   severity: High   confidence: VERIFIED
subsystem: TreasuryGovernor
file:line: cauldron/TreasuryGovernor.sol:525-541 (_benchRecord) and :707-712 (winner fallback)

    function _benchRecord(uint256 id, uint256 votes) private {
        ...
            if (b != 0) {
                Proposal storage q = proposals[b];
                if (!_dead(q)) v = q.forVotes;
            }
            if (v < weakVotes) { weakVotes = v; weakSlot = i; }
        }
        if (votes > weakVotes) _bench[weakSlot] = id;

    // winner():
        for (uint256 i; i < BENCH_SLOTS; ++i) {
            uint256 id = _bench[i];
            if (id == 0) continue;
            Proposal storage p = proposals[id];
            if (!_executable(p)) continue;

title: Eight proposals whose voting is still OPEN evict a PASSED treasury mandate from the bench and
       from the hint, so winner() returns 0, execute() reverts DidNotPass, the mandate goes stale, and
       the attacker's own envelope installs three days later.
precondition: A treasury proposal has passed and is inside its 3-day EXECUTION_WINDOW; `propose` is
       open (no live envelope, cooldown elapsed — the same window the mandate was voted in). Attacker
       holds strictly more voting power than the mandate's FOR-count (>= quorum, i.e. >10% of supply).
       Fully reachable: this is the ordinary post-vote state of the governor.
sequence:
  1. GUILD (300 votes of 1000 supply) proposes id=1, votes FOR, waits out VOTING_PERIOD.
     winner() == 1, passing(1) == true. (positive test)
  2. ATTACKER (301 votes) calls propose() 8 times and vote(id,true) 8 times — the SAME 301 votes are
     reused, because `hasVoted` is per-proposal. No AGAINST vote is ever cast.
     `_benchRecord` fills the 7 empty slots and the 8th filing evicts id=1 (300 < 301).
     `vote` case (3) hands `_leadId` to an attacker proposal whose voting is still open.
  3. winner() -> hint not `_executable` (open) -> bench scan -> all 8 open -> returns 0.
     execute(1) reverts DidNotPass, although passing(1) is still true and againstVotes == 0.
  4. After the attacker's window closes, execute(their id) installs an XNVDA envelope; the guild's
     USDG mandate is stale forever.
attacker_cost: 16 transactions, ~1.2M gas total (<0.01 ETH on L1 at 8 gwei, cents on an L2), plus
       HOLDING (not spending) 301 MiFrens. Repeatable at every cycle.
damage: The guild's voted treasury mandate is destroyed after the vote closed, when no counter-vote is
       possible (`vote` reverts VotingClosed). The treasury is then rotated into the attacker's chosen
       allowlisted asset, up to MAX_ENVELOPE_BPS (~95% conversion of the position). Governance is
       additionally locked out for ENVELOPE_LIFETIME (30 d) or COOLDOWN (7 d) after each install.
poc: contracts/solidity/test/attacks/K2b_MandateErasedAfterVoteCloses.t.sol   needs_fork: no
     3/3 pass. `test_K2b_positive_passedMandateExecutes` is the liveness positive
     (mandate -> winner -> envelope installed); `test_K2b_openProposalsEvictAPassedMandate` breaks it.
root cause: bench weight is `forVotes` for anything not `_dead`, but eligibility to WIN additionally
       requires the vote to have CLOSED. A proposal that is heavy enough to evict is not eligible to
       replace what it evicted.
```

```
id: T2c   severity: High   confidence: VERIFIED
subsystem: CauldronGovernor (brew mandates -> relaunch)
file:line: cauldron/CauldronGovernor.sol:689-706 (_benchRecord) and :812-826 (_recomputeLeader)

    // _benchRecord:
            if (b != 0) {
                Proposal storage q = _proposals[b];
                if (q.exists && !q.consumed) v = q.votes;
            }
    // _recomputeLeader:
            if (!p.exists || p.consumed) continue;
            if (block.timestamp <= p.votingEndsAt) continue; // still open for votes

  consumed by: CauldronRegistry.sol:841
    if (address(governor) == address(0) || !governor.hasProposals()) revert NoProposal();

title: Eight still-OPEN brew proposals push a settled, voted brew mandate off the bench, making
       hasProposals() false — relaunch() reverts NoProposal() for the whole voting period, and the
       attacker's brew is what the machine is then reborn as.
precondition: A settled, unconsumed brew proposal exists (the normal state before a rebirth). Attacker
       holds strictly more votes than it. CauldronGovernor has NO quorum, so the bar is whatever the
       leading honest brew actually drew — often small. `propose` costs one MiFren and has no cooldown.
sequence:
  1. GUILD (300 votes) proposes, votes, waits out VOTING_PERIOD. hasProposals() == true,
     winner() == the guild's brew. (positive test)
  2. ATTACKER (301 votes) files 8 brew proposals and votes each. `_benchRecord` evicts the guild's
     entry on the 8th; `vote` moves `_leaderId` onto an open attacker proposal, so
     `_bestUnconsumed`'s cached fast path also rejects it (`block.timestamp <= votingEndsAt`).
  3. hasProposals() == false and winner() reverts NoProposals. Any relaunch() in this window reverts
     NoProposal() — the eternal machine cannot be reborn, with a fully voted mandate on file.
  4. After the attacker's window closes their brew wins: name, symbol, renderer, quote, nftSupply and
     volumePerNFT are all attacker-chosen.
attacker_cost: 16 transactions, ~2.1M gas (brew proposals store strings), plus holding 301 MiFrens.
damage: relaunch — the protocol's stated "runs forever, relaunches permissionlessly" promise — is
       unavailable for a full VOTING_PERIOD (3 days mainnet default), and the attacker can fire it the
       moment a generation is about to be declared dead. Then the rebirth's entire identity and quote
       asset are the attacker's. The guild cannot answer: its own proposal's vote is CLOSED
       (`vote` reverts VotingClosed), so defending requires a brand new 3-day proposal, which can be
       evicted the same way.
poc: contracts/solidity/test/attacks/K2c_RelaunchStalledByOpenBrews.t.sol   needs_fork: no
     2/2 pass. Positive: `test_K2c_positive_settledMandateIsAvailable`. Attack:
     `test_K2c_openBrewsStallRelaunch`.
note: same root cause as T2b, in the sibling governor. Both benches admit weight from proposals that
       are not yet eligible to win; both readers then skip exactly those entries.
```

```
id: T2a   severity: High   confidence: VERIFIED (governor accounting) / DERIVED (registry call chain)
subsystem: TreasuryGovernor <-> RedemptionExt rotation envelope
file:line: cauldron/TreasuryGovernor.sol:775-778

        //  Partial envelopes are unchanged: below a whole position there is no
        //  migration to protect and one shared budget is the honest accounting.
        uint16 spent = e.maxTotalBps >= BPS_ONE ? e.movedPrimaryBps : e.movedBps;
        if (spent >= e.maxTotalBps) return (address(0), 0);

  and cauldron/TreasuryGovernor.sol:855
        if (cap >= BPS_ONE ? e.movedPrimaryBps >= cap : e.movedBps >= cap) e.active = false;

  reached from cauldron/RedemptionExt.sol:514
        ITreasuryGovernor(gov).consume(sliceBps, fromLeg == 0);

title: A stranger spends an entire PARTIAL treasury envelope with one permissionless slice out of a
       SECONDARY leg, so the primary rotation the guild voted for never happens and COOLDOWN locks
       governance out for 7 days.
precondition: The envelope's `maxTotalBps < 10_000` (any partial mandate — e.g. "move at most 25%"),
       and a secondary leg exists in a quote different from the envelope's destination. That leg is
       exactly what a previous completed rotation leaves behind (`_recordLeg`, RedemptionExt.sol:765),
       so every generation after its first migration is exposed. This is the same reachability the
       code already documents for the migration case (TreasuryGovernor.sol:844-852) and explicitly
       declines to fix for partial mandates.
sequence:
  1. Guild passes and installs an envelope: quote = XNVDA, maxTotalBps = 2500. allowance() == 2500.
  2. ATTACKER calls registry.rotateSliceFrom(fromLeg = 1, sliceBps = 2500, minOut, route).
     MAX_SLICE_BPS is exactly 2500 (RedemptionExt.sol:655), so ONE call suffices.
     `consume(2500, false)` books movedBps = 2500 == cap.
  3. allowance() -> (0,0); envelope.active -> false; migrationMandateSpent() -> false.
     Any honest `rotateSliceFrom(0, ...)` now reverts NoRotationApproved.
  4. `propose` reverts CooldownActive for COOLDOWN (7 days mainnet). Attacker repeats each cycle.
attacker_cost: one rotateSliceFrom (~600k gas, single-digit dollars), once per ~10 days.
damage: no direct theft — the slice is a real, oracle-floored rebalance between two legs — but the
       voted mandate is nullified 100% of the time, indefinitely, for gas. Each cycle costs the guild
       3 days of voting plus 7 days of cooldown. Value moved out of the guild's intended source pool:
       0; value denied: the whole voted budget (up to 25% of the primary position per envelope).
poc: contracts/solidity/test/attacks/K2a_PartialEnvelopeStarve.t.sol   needs_fork: no
     3/3 pass. `test_K2a_control_migrationEnvelopeSurvivesSecondaryDrain` is the positive control that
     shows the migration path IS protected (4x2500 bps of secondary spend leaves the budget at 10_000
     and the envelope live) — the asymmetry is the finding.
     `test_K2a_partialEnvelopeNulledBySingleSecondarySlice` is the attack;
     `test_K2a_lockoutLastsFullCooldown` prices the lockout.
caveat: the governor-side accounting is executed and asserted. The registry-side call chain
       (`rotateSliceFrom` -> `consume(bps,false)`) is read and quoted, not executed on a fork, hence
       DERIVED for that link.
```

---

## 3. Refutations — surfaces attacked hard that held

- **Caller-supplied `minOut`/venue on the rotation path.** `QuoteRotator.swapOnce` (:335-395) now
  enforces `allowedVenue[PoolIdLibrary.toId(route)]` (:359) AND an uncached oracle floor
  (`_oracleFloor`, :425-444) with `if (floor == 0 && quoteOracle != address(0)) revert NotPriceable();`
  (:392) and `if (out < (minOut > floor ? minOut : floor)) revert SlippageTooHigh();` (:394). A caller
  passing `minOut = 0` through a self-deployed pool is refused twice over. `arbStep` (:534-611) applies
  the same curation to BOTH keys and prices both legs with `_usdLive` before unlocking. I could find no
  path that reaches `poolManager.swap` with an attacker-chosen price reference.
- **Bench displacement of a treasury mandate at LOWER cost than an AGAINST vote.** A live veto needs
  `power >= forVotes`; bench eviction needs `power > forVotes`. Eviction is not cheaper, so during the
  voting window it adds nothing. The finding (T2b) is specifically that it works AFTER the window,
  where the AGAINST path is closed. I tried and failed to build a sub-quorum version.
- **`consume` uint16 overflow.** For `cap = 30_000`, secondary spend is bounded by `cap - movedBps` and
  primary by `cap - movedPrimaryBps`, so `movedBps <= 60_000 < type(uint16).max`. No `unchecked` blocks
  exist in any of the five files (grepped).
- **`_recoverLegs` unbounded loop.** `generationLegs` is upserted BY QUOTE (`_recordLeg`, :765-782), so
  its length is bounded by the owner-controlled `allowedQuote` set, not by anything a stranger grows.
- **Double-booking of leg proceeds.** `_recoverLegs` books only non-matching legs into `legProceeds`
  and returns matching ones; `_bookLegProceeds` runs only on the public retry, and the teardown entry
  does not book. Legs are popped as recovered, so a retry after a teardown recovers nothing.
- **`redeemOgFren` reserve underflow.** `F = genesisReserveOutstanding / genesisShares`, so
  `genesisReserveOutstanding >= F` always holds and the guarded subtraction at :90 is never skipped.
- **`renounceOwnership` dead-end on CauldronGovernor** — blocked at :315 with
  `OwnershipCannotBeRenounced()`.

## 4. Leads (HYPOTHESIS — exact next step given)

- **L1. Rotation back to native ETH is not exempt from `NotPriceable`.** `TreasuryGovernor
  ._requirePriceable` (:929) explicitly exempts `address(0)` so the guild can always vote its way home,
  but `QuoteRotator.swapOnce` :392 has no such exemption: `_oracleFloor(from, address(0), amountIn)`
  returns 0 whenever the ETH/USD feed is stale, out of band, or the sequencer is in its grace window,
  and every slice of a "come home to ETH" envelope then reverts. `deploy/DeployLaunchpad.s.sol:678-680`
  does configure a native feed, so this is an outage-window stall, not a permanent brick — but the
  envelope keeps expiring (`ENVELOPE_LIFETIME`) while the feed is down.
  *Next step*: fork test — install a native-destination envelope, `vm.mockCall` the ETH feed to a stale
  `updatedAt`, assert `rotateSliceFrom` reverts `NotPriceable` and the envelope expires unspent.
- **L2. Symmetric to L1: a leg whose feed is later removed cannot be rotated OUT of.** `_oracleFloor`
  requires BOTH legs priceable, so `setFeed(x, address(0), ...)` on a quote that already holds a leg
  makes that leg permanently un-rotatable (only `recoverLegs` at teardown exits it).
  *Next step*: confirm no owner path re-enables rotation without re-listing the feed.
- **L3. `TreasuryGovernor.cancel` accepts a nonexistent id** (:616-621) and writes
  `proposals[id].cancelled = true`, pre-poisoning an id the counter has not reached. Guardian-only, so
  Low at most. *Next step*: check whether a pre-cancelled id can later be `propose`d into and be
  silently unexecutable — `propose` writes the full struct with `cancelled: false`, so probably not.
- **L4. `QuoteRotator.arbStep` claims "Capital: none needed"** (:524-527) but the callback must settle
  `spent` of `inQuote` from this contract's own balance. If the rotator holds no inventory the path may
  be unreachable in practice. *Next step*: read `_arbCallback` (:~700) and check whether the two legs
  net inside one unlock or actually require a pre-funded balance.
- **L5. `TreasuryGovernor._settled` (:889) is dead code** — no caller. Hygiene only.

## 5. How to reproduce

```
cd contracts/solidity
export FOUNDRY_PROFILE=cauldron FOUNDRY_DISABLE_NIGHTLY_WARNING=1
forge test --match-path 'test/attacks/K2*' -vv     # 8 tests, 8 pass, no fork needed
```
**viaIR clock gotcha, hit and neutralised.** Under this profile's viaIR build a `block.timestamp` or
`block.number` read is sunk past a `vm.warp` / `vm.roll` issued in the same frame, so naive time travel
silently does nothing. I hit this twice (K2b's second warp landed 3 days short; K2c's `vm.roll` reissued
the same block and the vote reverted `SnapshotNotReady`). All three PoCs now read the clock ONLY via
`vm.getBlockTimestamp()` / `vm.getBlockNumber()`, and each time-dependent test carries an explicit
assertion that the warp took effect (`assertGt(t, goodEnd, ...)`, `assertTrue(warpTookEffect, ...)`,
`assertEq(vm.getBlockTimestamp(), ts, "warp took effect")`). `grep -n "block.timestamp\|block.number"
test/attacks/K2*.t.sol` now returns only comment lines. Re-verified 8/8 pass after the change.

`grep -n "return;" test/attacks/K2*.t.sol` returns nothing: no top-level test contains an early
return or `vm.skip`, all conditional logic lives in `_executeSucceeds` / `_proposeReverts` /
`_winnerId` helpers that return booleans/ids into locals, and every top-level test ends in assertions
on those locals. No existing test was modified.
