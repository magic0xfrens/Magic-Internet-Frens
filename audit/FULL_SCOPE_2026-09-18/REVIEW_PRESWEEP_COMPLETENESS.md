# Pre-trade liquidation completeness

Current status (2026-09-21): **OPEN**. The implementation described below is
historical, not the current checkout's remedy. HEAD `83ef97b` has a 30-kill
ceiling, a mutable rotating traversal and check-only survivor validation.
Session 70027 reports 7 pass / 1 fail; mixed-book rotated-cursor execution
reverts. The 64-position test now passes by atomic refusal and the badge test
permits inline minting, so neither proves the earlier acceptance property.
See `CURRENT_TREE_REGRESSION_RECHECK.md`. Historical results below remain useful
for comparison, not current-source or deployed attestations.

## PERP-04 — eight-kill exit incorrectly reports a complete pre-trade scan

Severity: **Medium** on demonstrated evidence: deterministic protection bypass
and outstanding spot insolvency. Realized loss and profitable extraction are not
established by the current test.

`PerpEngine._doSweep` initializes `complete = true` but stops at
`kills == MAX_LIQ_PER_SWAP` (8), even with unscanned positions. Only its explicit
gas-reserve branch changes that flag. `CauldronHook._liqSweep` rejects an explicit
incomplete pre-sweep, but accepts this incorrectly successful result.

## Executed pre-patch reproduction

Command (from `contracts/solidity`):

```sh
FOUNDRY_PROFILE=cauldron forge test --offline --threads 1 \
  --match-contract PreSweepLargeBookLocalTest -vv
```

Result: **1 passed / 1 failed / 0 skipped**. Four-position control passes.
The failing case opens 24 shorts from distinct accounts, each with 0.01 ETH gross
collateral and 2x leverage, against a 60 ETH initial pool and 40 ETH perp vault.
Every intended position remains open and healthy immediately before a 45 ETH buy.
The successful buy leaves 16 positions open, all spot-insolvent, with aggregate
spot-valued shortfall **450763942319741449 wei**. Immediate measured PLV decrease
is zero. That shortfall is not an executed loss or attacker profit.

The fixture uses production hook, engine, registry, V4 PoolManager,
PositionManager and Permit2. It inherits the local adapter's explicit 10,000 ETH
ambient manager-inventory assumption; this is not a fork or deployment attestation.
No production storage is overwritten. The trigger is an ordinary funded trade;
the regression does not quantify round-trip proceeds or claim profitable griefing.

## Remediation and boundaries

Only nonzero-`spec` pre-trade sweeps may exceed the eight-kill cap. They must cover
the already bounded (maximum 64) book; insufficient scan gas returns false so the
parent swap rolls back. Post-swap and post-open sweeps retain the eight-kill cap.
Simply reporting false at the eighth kill would block trades needing more than
eight kills regardless of supplied gas, since each failed attempt rolls back.

Independent source review agrees with the mode split. Added regressions cover 24
and 64 positions and a gas ladder: every successful swap must leave a safe book;
failed swaps must roll back price, positions, payer balance, keeper payout and PLV.
First post-patch result: **4/4 large-book tests pass**, including 24 and 64 healthy
positions before the trigger. Both books clear completely with no measured PLV
decrease. In the 24-position ladder, 1M/3M/5M/8M caps reject and roll back;
12M/16M succeed and clear the book. This does not prove a 64-position trade fits
a production transaction gas limit: the unrestricted test includes book setup,
and separate swap-only measurement is being added.

The combined run returned **16 passed / 3 failed / 0 skipped** across six suites.
All three failures were the pre-existing rebook-accounting assertions: the
collateral-preserving body was absent from the source compiled for this run.
Its primary source keccak was
`0x5816d69b7395b57a5f793a43901787c7b719899c5755ef1de811f76a74b4566a`.
An overlapping external edit subsequently restored that body and changed nearby
settlement comments. Do not attribute that restoration to this turn's root edits;
it must be independently retested against the new source hash.

The replacement focused run passed **29/29**, 0 failed, 0 skipped: four-position
control; 24/64-position books; exact-output buy; rotated cursor; gas ladder;
cascade projection/loss; partial-close minimum; and 257 rebook fuzz cases. A
separate claim-later badge regression passed **1/1**, confirming 24 claimable
credits, no inline pre-trade mints, a successful bounded claim, and the approved
absence of stats on claimed badges. The 64-position check used the full
16,777,216 gas ceiling as an optimistic inner-call budget; real transaction
intrinsic/router overhead still requires a production gas estimate.

Full fork execution, fresh artifact size checks, graph refresh, and full-suite
acceptance remain open.

## Additional traversal leads (source-derived, not yet production reproduction)

The production remedy snapshots pre-trade membership and revalidates survivors
at the final projected price. If a later settlement makes an earlier survivor
unsafe, it retries that id with a progress check and a bound of the original
book length; otherwise it fails closed on gas. The mixed-cursor regression now
passes with zero spot-insolvent survivors. This does not prove all arbitrary
future storage mutations safe; new mutations require regression coverage.

The app's old hardcoded 8M limit is insufficient in the executed 24-position case.
A local consumer patch estimates the exact router request and adds 20% headroom
with an 8M floor, surfacing RPC/chain/simulation failures rather than forcing a
transaction. Four helper tests pass; full hook interaction and inclusion-state
races remain limitations. Consumer type checking is being finalized; concurrent
manifest edits separately break deployment-config typing. Do not restore the
silent on-chain bypass for compatibility.
