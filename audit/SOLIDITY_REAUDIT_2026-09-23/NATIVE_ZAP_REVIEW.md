# NativeQuoteZap review — intermediate

Full first-party source read: constructor, zap and unlockCallback; immutable
poolManager getter is a separate generated surface. No production edit.

## Function and asset path

- constructor: immutable manager assignment, no owner/upgrades; invalid manager
  deployment remains a configuration gap, not permissionless replacement.
- zap: public payable; nonzero value and floor; native currency0; calls manager
  unlock with the caller as payer, checks output floor, transfers only output
  to caller, then emits Zapped. No state counters or persistent approvals.
- unlockCallback: only immutable manager; decodes the call, swaps exact input,
  pays actual native debt and takes output ERC20. Excess input is refunded to
  payer before callback returns. Refund failure reverts all effects. The manager
  remains unlocked during this refund, unlike the later output token transfer.

There are no loops, configurable roles or delegatecalls. Asset units are native
wei and raw currency1 units. Casts rely on expected signed V4 deltas. Floor is
caller-supplied, not an on-chain oracle guarantee. Arbitrary user-selected pool
keys/hooks are allowed, so this review does not infer venue curation from zap.

## Executed properties

The four NativeQuoteZapLocal tests in oracle-fix-neighbors execute production V4
and fee-bearing ranges: multi-tick partial refund, budget fuzzing, impossible
floor rollback, and unauthorized callback/zero-floor rejection. Their assertions
check received quote, manager/payer balance changes and no zap residuals.

New R23_ZapRefundCallbacks.t.sol, logs/zap-refund-callbacks.*: 2 passed, 0 failed,
0 skipped, exit 0. Same production-manager fixture, fresh synthetic recipients:

1. Partial-fill refund invokes recipient code; nested zap is refused with the
   manager's AlreadyUnlocked selector; original swap still delivers all output.
   Manager input plus recipient refund equals the original one-ether budget.
2. Rejecting refund produces EthReturnFailed; pool price, payer and manager
   balances revert, with no output/residual credited to recipient or zap.

This establishes the refund callback paths, not all hostile-hook/token behavior.
No new vulnerability demonstrated. Candidate selected total is 214 passing tests
across disjoint batches, not complete repository coverage.

## Consumer links inspected

- deploy/DeployLaunchpad.s.sol:1020 constructs with configured manager.
- scripts/apply-deployment.mjs extracts NativeQuoteZap into nativeZap; currently
  owner-modified and not certified by this traversal.
- scripts/verify-selectors.mjs:72 expects the zap tuple/uint256 signature.
- src/hooks/useCauldronSwap.ts:16 defines the same payable tuple ABI; :207 onwards
  signs a native/quote, fee=3000, spacing=60, hook=zero venue and nonzero expected
  output with a haircut. Buy path measures quote balance before/after receipt.
- src/config/cauldron.ts reads address from the active round manifest, which has
  owner-side modifications. This is a local source link, not deployed parity.

## Explicit gaps and limits

Output transfer accepts an empty/true token return, without measuring recipient
balance. Fee-on-transfer/rebasing/dishonest token behavior and post-unlock token
callback re-entry need separate treatment; the existing tests use ordinary ERC20.
Forced native or donated token balances cannot be claimed through a sweep; the
contract's zero-balance promise is only tested absent such donations. No actual
deployed-address, venue-liquidity or oracle-derived frontend floor parity has
been established. Client receipt/replacement behavior and hard-coded venue
matching remain part of later consumer validation.
