# Perp and rotation graph refresh

Date: 2026-09-18  
Scope: `audit/graph/perp.{json,md}` and `audit/graph/rotation.{json,md}` only  
Evidence status: **DERIVED** static analysis unless a validator result is explicitly marked **VERIFIED**.

## Outcome

The two annotated graphs are now bijective with the immutable current-tree skeletons.

| cluster | old nodes | current nodes | added | changed bodies | obsolete removed | validator |
|---|---:|---:|---:|---:|---:|---|
| perp | 163 | 216 | 61 | 61 | 8 | **VERIFIED 216/216, 0 failures** |
| rotation | 87 | 93 | 6 | 4 | 0 | **VERIFIED 93/93, 0 failures** |

The changed/added bodies were reread from the current source. Because insertions also invalidated
many cross-function line citations on nominally unchanged nodes, all current nodes were regenerated
against current source locations rather than retaining stale September 12 citations.

Current direct annotation totals:

| cluster | files | public/external nodes | reads | writes | resolved edges | explicit caller gates | untrusted edges |
|---|---:|---:|---:|---:|---:|---:|---:|
| perp | 5 | 121 | 223 | 141 | 600 | 28 | 16 |
| rotation | 7 | 64 | 125 | 46 | 184 | 27 | 9 |

`reads`/`writes` are direct body references. Effects hidden in modifiers and transitive callees are
recorded on those nodes, not duplicated onto every caller.

## Files covered

Perp:

- `cauldron/PerpEngine.sol`: 135 nodes
- `cauldron/PerpMarkSource.sol`: 7 nodes
- `cauldron/PerpStakerOracle.sol`: 4 nodes
- `cauldron/PerpSwapLib.sol`: 22 nodes
- `cauldron/PerpVault.sol`: 48 nodes

Rotation:

- `cauldron/CauldronVault.sol`: 11 nodes
- `cauldron/MockAggregator.sol`: 7 nodes
- `cauldron/MockQuoteToken.sol`: 3 nodes
- `cauldron/NativeQuoteZap.sol`: 3 nodes
- `cauldron/QuoteOracle.sol`: 14 nodes
- `cauldron/QuoteRotator.sol`: 29 nodes
- `cauldron/RedemptionExt.sol`: 26 nodes

## Risk-weighted cross-check

- **DERIVED — vault floor accounting:** `CauldronVault.receive` counts only registry/minter-originated
  funding in `accountedDeposits` while still accepting donations
  (`CauldronVault.sol:117-122`). `close` transfers the complete live balance but returns only the
  accounted amount, clamped to balance (`CauldronVault.sol:184-195`). This separates custody from
  the entitlement numerator; the live `collection.minter()` lookup remains a configuration trust
  boundary (`CauldronVault.sol:130-135`).
- **DERIVED — native quote zap:** the callback is pool-manager gated
  (`NativeQuoteZap.sol:123-125`), the entry requires nonzero value/floor and native `currency0`
  (`NativeQuoteZap.sol:101-105`), and the output transfer checks both reverting and boolean-return
  ERC20 shapes (`NativeQuoteZap.sol:116-120`). The caller deliberately controls the remaining pool
  key, including hooks; safety depends on the helper remaining stateless and allowance-free.
- **HYPOTHESIS — zap multi-tick liveness:** the code documents a case where V4 rounding may return
  `owed > amountIn`, but still attempts `settle{value: owed}` before its saturating refund
  (`NativeQuoteZap.sol:143-170`). If the documented condition is reachable, the helper reverts for
  that trade. A fee-bearing, multi-tick executable test must prove or reject this; it is not a
  confirmed loss finding.
- **DERIVED — queued perp exits:** ETH and token queues use global units/indexes and epoch invalidation
  to apply write-downs without caller-sized iteration (`PerpVault.sol:410-474` and
  `PerpVault.sol:683-726`). Permissionless settlement pays nobody and only crystallizes the current
  haircut (`PerpVault.sol:493-497`, `PerpVault.sol:730-734`). Claim paths update queue effects before
  engine payout calls.
- **DERIVED — token-yield rotation write-off:** `_syncTokYield` splits accrual at a clamped write-off
  boundary, advances the cumulative watermark, and bumps the epoch once
  (`PerpVault.sol:547-595`). This is dense accounting and remains a priority invariant/fuzz target;
  graph validation establishes references and edges, not conservation.
- **DERIVED — rotation leg custody:** destination-leg replacement resolves the prior position before
  recording the new one, and recovery books foreign-denomination proceeds separately. A failed
  `removeAll` is caught and the leg remains for retry (`RedemptionExt.sol:924-958`). This preserves
  teardown liveness but can leave a permanently failing venue position pending; operational
  recovery behavior needs fork coverage.

## Validation evidence

Commands run from the repository root:

```text
python3 audit/graph/validate.py contracts/solidity audit/graph perp
python3 audit/graph/validate.py contracts/solidity audit/graph rotation
```

Results:

```text
COVERAGE perp: 216/216 nodes, 0 failures
COVERAGE rotation: 93/93 nodes, 0 failures
```

No Solidity or tests were edited, and no full test suite was run for this bounded graph task.

## Residual gaps

1. The legacy graph schema validates authority, direct storage reads/writes, value movement, edges,
   reachability, and observations. It has no machine fields for the full-scope prompt's math units,
   rounding, loop bounds, events/errors, lifecycle exits, test assertions, or frontend/indexer/
   deployer consumers. Those overlays remain required before the global Phase 1 gate can close.
2. Compiler-generated public state getters have selectors but no declaration nodes by skeleton
   design. The validator reports them as informational unmatched method identifiers; the global
   selector inventory must retain them.
3. Edge trust labels are a source-derived first pass. Admin-configurable addresses and live
   collection/registry dependencies need reconciliation with the authority and deployment maps.
4. Validator success proves graph shape, current citations, storage-layout membership, edge symbol
   resolution, and selector presence. It does not prove the economic claims, transitive asset
   conservation, or liveness. Those need invariant, stateful-fuzz, and fork execution.
5. The zap rounding/liveness hypothesis and retryability of permanently failing rotation legs are
   the two focused executable follow-ups surfaced by this refresh.
