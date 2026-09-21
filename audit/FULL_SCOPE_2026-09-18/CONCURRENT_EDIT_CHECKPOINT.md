# Concurrent-edit checkpoint — 2026-09-18

This is an incomplete-audit handoff, not release approval.

## Why fresh-source certification is blocked

The continuation began at `71443f2bac9275b54536046ead962b4a65f557c2`.
At 12:02:58 UTC, read-only inspection found HEAD at
`f1023234f5221b5db4562f51d3d40a1712546fc7` without any commit/push command from
this audit turn. `PerpEngine.sol` and `indexer/deployments/round.json` changed
repeatedly during builds. Preserve those external edits and commits.

The latest engine has the collateral-preserving `_rebook` body from external
commit `712c2b1`. However, **both local PERP-03 and PERP-04 remedies disappeared**:

- partial short settlement no longer checks `_ownerFloor(ownerSlippage, 0, minOut)`;
- `_doSweep` again stops at `kills < MAX_LIQ_PER_SWAP` in both modes.

Earlier passing tests cannot certify this changed source. The owner was asked
to pause the overlapping editing session or establish file ownership. Repeated
automatic rebuilding against a moving target wastes credits and cannot close
the audit's source-hash gates.

## Work executed in this continuation

- PERP-04 before remedy: 24 healthy shorts, then a funded buy, leaves 16 open
  spot-insolvent positions; shortfall 0.450763942319741449 ETH; immediate PLV loss
  zero. Four-position control passes. No profitable extraction claimed.
- Cap remedy plus restored rebook, at source keccak
  `0x7da00c031aecd4d11fe9a293835d46236788d3a1e72a2e6a2d417005ae84738a`:
  27 focused Solidity tests pass, including partial-close/funding fuzzing,
  24/64-position books, exact-output and atomic gas rollback. The source-matching
  versioned artifacts measured 23,382 bytes (1,194 headroom); bare alias stale.
- Read-only actual Sepolia fork: projection suite 5/5; expanded liquidation,
  D04 funding/penalty, relaunch/whale and padded-book suites 12/12. Fresh protocol
  contracts on forked managers, not deployed-protocol attestation. Latest fork
  selected by original harness, not pinned to a block in these runs.
- App gas fix retained locally: exact-request estimate, 20% buffer, 8M floor,
  pinned account/chain and error propagation. Root `npm test`: 33/33 pass
  (19 Node + 2 API + 7 indexer + 5 gas-helper).
- Frontend type-check fails at deployment-config/perp consumers after external
  manifest changes. No remaining error was reported in the new gas helper/hook.

## Unclosed acceptance problems

The full 64-position sweep consumed 21,338,728 gas excluding setup; the same
trade failed with a 16,777,216 call gas budget. Ethereum's transaction cap is
16,777,216 under [EIP-7825](https://eips.ethereum.org/EIPS/eip-7825), included in
[Fusaka, activated on Sepolia in October 2025](https://eips.ethereum.org/EIPS/eip-7607).
Thus raising the wallet gas limit cannot make this measured full-book transaction
executable there. This is an acceptance blocker for the cap remedy, not proof
of a permanent pool freeze or a claim about every supported chain.

Cursor wrapping and partial rebooking may also invalidate one-pass traversal;
source-derived counterexamples and the next test are in
`REVIEW_PRESWEEP_COMPLETENESS.md` / `PreSweepLargeBookLocal.t.sol`. The new mixed-book
probe is not yet counted as evidence. Do not restore the cap remedy and call the
entire sweep safe without closing these tests and gas/liveness constraints.

## Exact remedies that must be reconciled on a stable tree

PERP-03, inside the non-death partial-short branch before rebooking:

```solidity
_ownerFloor(ownerSlippage, 0, minOut);
```

PERP-04 tested cap change (necessary but not sufficient for final acceptance):

```solidity
while (scanned < len && (spec != 0 || kills < MAX_LIQ_PER_SWAP)) {
```

No final report, all-clear, audit-fix push or deployment is claimed. Low and
Informational findings remain unfixed as requested.
