# V2 — lifecycle & governance verification (P2)

Blind verifier, decontaminated copy at `/tmp/blind-final-v2/contracts/solidity`. All 8 PoC tests
pass; all three findings survived mutation testing (a one-line change flipped each headline
assertion, proving the assertion lines execute and the claimed mechanism is load-bearing). No
`return;`, no `vm.skip` in any top-level `test_*`; every PoC reads time via
`vm.getBlockTimestamp()` and asserts the warp landed.

(Transcribed verbatim by the orchestrator from the verifier's return message; the verifier
declined to write this file itself.)

## T2a | HIGH → CONFIRMED (HIGH) — VERIFIED

`TreasuryGovernor.sol:775` `uint16 spent = e.maxTotalBps >= BPS_ONE ? e.movedPrimaryBps : e.movedBps;`
deliberately leaves partial envelopes on the shared counter, and `:855` deactivates on it.

The DERIVED registry chain is now VERIFIED: `CauldronRegistry.sol:270-274` is an ungated
`external` stub that `_forwardToExt()` delegatecalls into `RedemptionExt.sol:280` (`public`, no
gate, caller-chosen `fromLeg`), which books `ITreasuryGovernor(gov).consume(sliceBps, fromLeg == 0)`
at `RedemptionExt.sol:514` — `false` for any leg the caller names, and `msg.sender` at the
governor is the registry, so `:828` passes.

Counter-argument (2) partially holds and is recorded: `toQuote` comes from `allowance()`
(`RedemptionExt.sol:303`), the quote is owner-allowlisted (`:322`), and the swap is
venue-allowlisted + oracle-floored, so **no value is stolen** — the slice lands in the guild's
own voted asset. Counter-argument (3): damage is the 7-day `COOLDOWN` lockout plus loss of
control over which leg rotates, and it is repeatable at gas cost every envelope
(`test_K2a_lockoutLastsFullCooldown` asserts the cooldown clears, i.e. grief-repeatable not
one-shot), so partial mandates can never execute against the primary.

Precondition: a secondary leg in a different quote must already exist (`_recordLeg` upserts by
quote, `RedemptionExt.sol:774/780`), so a generation's first migration is safe.

Mutation: `gov.consume(bps, true)` flips the control test to `0 != 10000` — the `false` flag is
exactly the discriminator.

## T2b | HIGH → CONFIRMED (HIGH) — VERIFIED

`winner()` (`TreasuryGovernor.sol:696-712`) is *only* the `_leadId` hint plus an 8-slot bench
walk — the "walking BACKWARDS" scan the comment at `:713-728` describes **is not in the code**.
`_benchRecord` (`:525-541`) ranks on raw `forVotes` and excludes only `_dead` entries, so a
still-OPEN proposal counts at full weight.

**Priced attack cost:** gas for 8 `propose` + 8 `vote` calls, plus holding voting power strictly
greater than the mandate's FOR total (301 vs 300 in the PoC; floor is quorum = 10% of supply).
`PROPOSAL_THRESHOLD = 5` MiFrens (`:503`), **no deposit, no fee, no stake, no per-proposal
cooldown**, and the same wallet's votes are reused on all eight filings.

Counter-argument (2) fails: the `_leadId` hint is handed to the heavier open proposal and then
rejected by `_executable` for being open. Counter-argument (3) fails: `execute` gates on
`if (id != winner()) revert DidNotPass;` (`TreasuryGovernor.sol:566`) — there is no by-id bypass,
and the mandate cannot be re-benched because `vote` is closed after `votingEndsAt`, so not even
the guardian can rescue it. Counter-argument (4): the attacker's envelope **does install**
(`allowance()` returns XNVDA), but only for an owner-allowlisted quote (`:594`) — a real
constraint, not a full refutation.

Residual mitigation that could not knock the finding down: an attacker holding that much power
could also win honestly; the incremental harm is that this lands *after* the window, so the
guild cannot counter-mobilize.

Mutation: making only the 8th filing light (`i==7?1:ATTACK_POWER`) yields `winner()==good` — the
8th eviction is precisely load-bearing.

## T2c | HIGH → CONFIRMED (HIGH) — VERIFIED

Same root cause, second governor: `CauldronGovernor._benchRecord` (`:689-706`) admits open
proposals at full weight while `_recomputeLeader` (`:812-826`) skips them
(`if (block.timestamp <= p.votingEndsAt) continue;`), so `hasProposals()` (`:731-733`) goes false
with a settled mandate on file and `CauldronRegistry.sol:841`
(`if (address(governor) == address(0) || !governor.hasProposals()) revert NoProposal();`) blocks
rebirth.

Counter-argument on the cached slots fails: `vote` (`:665-681`) demotes the guild's brew from
`_leaderId` into `_runnerId` on the first junk filing and overwrites `_runnerId` on the second, so
both caches are lost.

**Priced attack cost:** gas only for 8 `propose` + 8 `vote` calls — `CauldronGovernor.propose`
has no threshold, deposit or cooldown — plus one wallet holding strictly more checkpointed MiFren
power than the guild brew's vote total.

Bounded vs indefinite: it is **not** a one-period delay. `vote` reverts `VotingClosed` past
`votingEndsAt` (`:652`), so the evicted brew can never be re-benched; once the junk settles it
*is* the winner and the machine is reborn as the attacker's brew (`winnerLater == firstJunk`).
That is a permanent hijack of the rebirth, but it is gated on out-voting the guild, so it stays
HIGH rather than Critical (it is not a brick "at any cost").

Mutation: attacker power 299 < 300 leaves `hasProposals()` true.

## Spot-checks of the hunter's refutations

**Rotator venue + floor on `swapOnce` — AGREE, refutation holds.** VERIFIED by reading
`QuoteRotator.sol:359` `if (!allowedVenue[PoolIdLibrary.toId(route)]) revert NoRoute();`,
`:390` `if (floor == 0 && quoteOracle != address(0)) revert NotPriceable();`, and
`:393` `if (out < (minOut > floor ? minOut : floor)) revert SlippageTooHigh();` — the venue is
keyed by PoolId (not just the pair), the floor is computed before the swap, an unpriceable pair
fails closed when an oracle is wired, and a caller-supplied `minOut` can only tighten.
`arbStep`/`rotateStep` enforce the same at `:295`.

**`_recoverLegs` loop bound — AGREE, refutation holds.** VERIFIED: the loops at
`RedemptionExt.sol:759` and `:768` run over `generationLegs[gen].length`, and `_recordLeg` upserts
by quote (`:774 if (legs[i].quote == quote)`) and only `legs.push` for a genuinely new quote
(`:780`), while every destination must pass `if (!allowedQuote[toQuote]) revert NotConfigured();`
(`:322`). Leg count is therefore bounded by the owner-controlled allowlist size, not by anything a
permissionless caller can grow.

## Discards

0 findings refuted, 0 downgraded, 0 not-verified — all 3 survived, both spot-checks agreed.

PoCs (restored, unmutated, green): `/tmp/blind-final-v2/contracts/solidity/test/attacks/K2a_PartialEnvelopeStarve.t.sol`,
`K2b_MandateErasedAfterVoteCloses.t.sol`, `K2c_RelaunchStalledByOpenBrews.t.sol`.
