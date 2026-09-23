# PerpVault review — full source traversal, final verification pending

Read through deposit's quote-selection path (source through line 345). Earlier
tests and comments are leads, not fresh full-scope validation. No production edit.

DERIVED: constructor fixes engine/registry and initializes both queue indices.
hasStakers checks shares and queue units on both sides; hasQuoteStake checks only
quote-side shares/queue. assetsEth/assetsTok subtract queue claims with saturation.
deposit calls queue synchronization before pricing and rejects remaining queue
insolvency. Review the complete synchronization and rotation algebra before
claiming dilution resistance or denomination safety.

HYPOTHESIS to resolve: hasStakers does not include tokRewardOwed, while token
rewards have a separately claimable ledger. Determine whether withdrawing the
last token shares always pays/clears that ledger, or whether replacing the vault
can strand earned but unclaimed yield. Inspect withdrawToken, claimTokYield,
engine.setVault and onlyVault payment gates together. No finding yet; orphan
engine yield is explicitly distinct from earned user yield.

Stale narrative: header claims queued exits stop bearing bad-debt risk, while
later comments describe pro-rata queue loss recognition. Use executable queue
math, not either comment, to establish actual loss allocation.

## Continuation: earned-yield guard mechanism reproduced

Read token deposit/settlement/withdrawal/claim paths (620–860), plus
PerpEngine.onlyVault, withdrawTokYieldTo and setVault. withdrawToken banks
rewards into tokRewardOwed and resets share debt without paying those rewards.
hasStakers counts shares and queue units only. Test R23VaultRewardStake fails
exactly the replacement-guard assertion after confirming positive earned debt
and zero token shares/queue units; see badge-legacy-and-earned-yield logs.
The engine fixture is mocked: production fee accrual, replacement, failed old
vault claim and recovery control remain required. This is a mechanism-level
result, not a proven permanent loss or completed PerpVault traversal.

## Full traversal checkpoint

Read source lines 1–959 including all interface declarations, state, constructor,
public getters and executable bodies. Source reading is complete, not sign-off.

| Paths | Authority/assets/order and remaining property gaps |
|---|---|
| constructor; hasStakers; hasQuoteStake | Immutable engine/registry; replacement guard omits earned reward debt. Quote-adoption intentionally excludes token shares. Wiring and lifecycle interactions require validation. |
| assetsEth/assetsTok; ethPosition/tokenPosition | Saturating residual backing, virtual offset and floor rounding. Views use stored queue indices, so unsynchronized-loss preview parity is a gap. |
| deposit/depositEth; _engineQuote; _pull/_approve | Permissionless native/ERC20 deposits, native value equality, pre-funding share pricing, guarded engine transfer. Compatibility fallback is native; malformed return and token balance-delta assumptions need dependency review. |
| withdrawEth; _markEth | Sync losses before valuation; burn/queue before payment; post-payment baseline. Test callback rollback and earned-yield/loss interleaving. |
| _haircut; pendingEth/Of; _queueEth/_dropEthUnits; _syncEthQueue; settlePendingEth; claimPendingEth | Fixed units/global index, epoch invalidation, floor rounding, permissionless write-down without payment. Partial-payment rounding after quote conversion and net-gain/net-loss observation require boundary tests. |
| beforeBookRequote/afterBookRequote; _toYieldUnit | Engine-only guarded callbacks; quote queue index scales and clamps to one; internal reward scale floors without nonzero guard. Trace engine reachable ratios before classifying zero-scale risk. |
| _syncTokYield/_settleTok/_resetTokDebt | Cumulative-plus-pot write-off detector and lazy epoch accounting; per-user owed survives principal exit. Repeated-writeoff and rounding behavior require fresh suite execution. |
| depositToken/withdrawToken/claimTokYield | Guarded funding/principal exits/independent reward claim; share changes bank old rewards. Token deposit checks insolvent queue without synchronizing; withdrawal also does not synchronize token queue. Reconcile with production inventory-loss reachability. |
| pendingTok/Of; _queueTok/_dropTokUnits/_syncTokQueue; settlePendingToken/claimPendingToken | Token queue globally haircuts only beyond backing; arbitrary users may settle loss; payment follows state debit. Verify epoch, zero backing and partial-payment properties. |
| pendingTokYield | Recomputes lazy reward accrual and write-off preview; compare to actual claims across rotation, reward scale and zero-share windows. |

Production-engine reproduction `perp-replacement-earned-yield` PASSES its
mechanism assertions: fee credit through authorized hook role, normal stake and
full principal withdrawal, positive reward, replacement accepted, old claim
reverts NotVault with unchanged balances/pot/entitlement, restoring old vault
permits exact payout. Registry/pool remain stubs; no forced target storage.
This refutes unconditional permanent loss but proves claim outage. Test a funded
replacement (which may prevent restoration) and track attributed debt without
reintroducing the orphan-yield replacement lockout.

## FS-perpvault-01 candidate verification

Exact aggregate of settled current-epoch reward units is appended privately.
_settleTok adds the same earned increment to individual and aggregate debt;
claims subtract pre-clear debt; recognized write-off clears aggregate before
rebasing any user. Quote conversion leaves internal units unchanged. When no
shares/queues exist, the view ignores old settled debt only if engine counters
show an unrecognized write-off. No loop or external mutation was added.
All external payment failures roll back aggregate and individual debits.

perp-earned-yield-fix: 32 passes, 0 failures/skips; seven are inherited repeats
(four engine-writeoff tests, three K3b tests), so 25 distinct tests. Separate
perp-reward-scale-and-mark-boundaries adds two vault tests, asserting scaled
payout and deliberate user clearing of positive debt rounded to zero. These
conversion tests use a modeled engine callback sequence, not actual swaps.

Surface check passes with exactly one appended private uint256 slot and no
ABI/selector change. Runtime 12,608 (headroom 11,968), init 13,009.
Consumer inspection: selectors in src/config/perp.ts unchanged; usePerpVault
submits the same claim. StakePanel hides claim for zero displayed reward, so the
new dust-clearing operation needs an explicit consumer/operator path before
final verification. No frontend edit or compatibility completion claimed.

Stateful sequence continuation: R23VaultRewardSequence passes 256 seeds, each
64 actions across four users (accrual, deposit, principal withdrawal, claim,
write-off). Every step checks credited = paid + forfeited + engine pot, aggregate
settled debt equals sum of current-epoch user debts, total claimable <= backing,
and any positive claim keeps replacement blocked. Private slot read is pinned
by compiler layout; no storage writes. Engine is modeled, and actual quote
conversion/consumer flow remain distinct gaps.
