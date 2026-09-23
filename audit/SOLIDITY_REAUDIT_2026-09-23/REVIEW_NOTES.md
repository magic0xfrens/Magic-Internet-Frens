# Review evidence and open questions

This is an intermediate worksheet, not a final findings ledger. Baseline identity
is in BASELINE.json. No new vulnerability is confirmed by the checks below.

## Requote storage interface

Fresh compiler layout for PerpEngine agrees with the slots its `_bookSlots`
assembly supplies to PerpSwapLib. The six full-width pots are uint256 at byte
offset zero; all slots fit the 16-bit encoding. Address offsets are zero here.

| Value | Storage slot | Encoded bit start |
|---|---:|---:|
| plv | 65 | 0 |
| longOiEth | 81 | 16 |
| insuranceEth | 17 | 32 |
| tokYieldEth | 67 | 48 |
| tokYieldCumulative | 68 | 64 |
| quoteUnit | 86 | 80 |
| quote | 16 | 96 |
| markSource | 85 | 120 |
| quoteOracle | 87 | 144 |

The separate reference word encodes positions=71, openIds=78, observations=28,
ring=60 at bit starts 0/16/32/48. Library reconstruction uses those starts.
Evidence: COMPILER_GRAPH.json contractSurfaces / PerpEngine / storageLayout;
PerpEngine._bookSlots and requoteBook; PerpSwapLib._slot/_ldAddr/_stAddr and
requoteBookAt. This establishes layout agreement for this extraction, not
end-to-end authorization or accounting safety.

## Rotation call path inspected

RedemptionExt.rotateSliceFrom updates generationQuote and the hook live key,
then calls the engine's requoteBook without catching its failure. Engine delegates
to the library, which gates on registry msg.sender before checking whether the
quote changed. Owed payouts prevent carrying the book. Physical pots convert at
realized rate; long debts convert at the oracle rate, rounded upward. Vault hooks
are engine-only and their failures propagate. QuoteRotator checks the live-engine
identity, curated venue and nonzero oracle floor; engine withdrawals can only go
to the engine itself. These observations are not a closed review: callback
ordering, stale marks, re-entry, token behavior and funding still need analysis.

Funding dimensional check: `_pokeFunding` accrues a dimensionless 1e18-scaled
index. `_fundingDelta` applies the index difference to collateral times leverage,
bounded by a fraction of collateral. Requote preserves entryFunding while
rescaling collateral, so an unchanged entry index is not itself a missing
quote-unit conversion. Economic conservation with different long/short realized
rates still requires tests; comments claiming solvency are not evidence.

## Test quality and limitations

- The initial local lane executed 108 tests; F12/F12b executed another 10.
- F12b uses the real engine, vault and quote oracle, but a stand-in venue and
  pool manager. Its passing round trip does not prove open-position execution.
- Existing F14/F14c use YBase's fork bring-up. Their setUp explicitly requires
  an active fixture. Do not count them as executed merely because other YBase
  tests can return early without FORK_RPC.
- The added RotationTotalityLocal harness replaces `_boot` only, deploying
  actual PoolManager, PositionManager and Permit2 artifacts. It inherits F14's
  ledger round trip and F14c's open-book carry/close assertions. Original source
  snapshot files remain intact; this is an additive test input, duplicated in
  the root tree for retention.
- F14c permits a 25% difference from its no-rotation payout control. A passing
  test is evidence of its stated bound, not exact payout preservation or proof
  that the bound is economically acceptable under every market condition.
- Gas fits, all quote decimals, repeated-rounding edge cases, full maximum book
  size, adversarial callback/token behavior and new-generation retries are not
  established by these tests.

## Remediation constraints

No production fix has been made in this fresh pass. Registry runtime has only
8 bytes of build-reported EIP-170 headroom; engine has 408. Any remediation needs
fresh size validation. Low/Informational findings remain documentation-only per
the user's instruction. No push or deployment is authorized for this pass.

## Lead R23-L1: cascade completion condition (unconfirmed)

PerpEngine._doSweep's cascade pass exits clean when `!condemnedRemains`, even
when `killedAny` is true. A settlement late in the pass can change the price
after an earlier survivor was checked. In addition, `_condemnedByThisTrade`
reads the stored projection, whereas that projection is refreshed only after
the predicate selects a position for liquidation in this loop. The comments
describe a clean no-kill pass, which is stronger than this exit condition.

Do not assign severity or apply a fix yet. Establish whether a reachable mixed
book can return SWEEP_OK while a freshly projected survivor is unsafe, accounting
for the first sweep, the settlement band, the backlog exception and the hook's
post-trade sweep. Existing large-book tests pass and do not alone resolve this
lead. A local stateful regression should vary position ordering and exposure,
verify actual position creation and distinguish safe refusal from successful
unsafe execution. No user loss has been reproduced for this lead.
