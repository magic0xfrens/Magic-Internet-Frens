# V2 / E2A — "the governance electorate is farmable at gas cost"

Verdict: **CONFIRMED-mechanism / corrected-cost. Severity DOWNGRADED High -> Medium.**

PoC: `contracts/solidity/test/attacks/V2A_VoteFarm.t.sol` (copy in `poc/v2/`). PASSES on the Sepolia fork, real `MiFrensGenesis` wired (not the mock in `YBase.sol`). Only `return;` is the `if (!active) return;` fork guard in `setUp()`; the `test_*` body has none and no `vm.skip`.

## The documented property, quoted (VERIFIED)
`cauldron/MiFrensGenesis.sol:175-178`:
```
    // governance vote, exactly like a volume-minted MiFren (badges are earned by
    // real, capital-at-risk liquidations, not cheaply farmable). It is never
```
The code contradicts it: capital IS at risk, but the risk is recoverable and the marginal cost per vote is ~0.0018 ETH.

## Links, each executed (VERIFIED unless noted)
1. `PerpEngine.liquidate(uint256)` at `cauldron/PerpEngine.sol:1042` — `external`, no caller gate, `keeper = msg.sender` (`_settle(id, p, 0, MODE_LIQUIDATION, msg.sender)` at :1050).
2. No self-counterparty guard anywhere on that path — confirmed by the PoC's `vm.prank(atk, atk); perp.liquidate(i)` loop.
3. Badge mints on EVERY kill: `_awardBadge(id, keeper, _killStats(p, toKeeper))` at `PerpEngine.sol:1767`, unconditional inside `if (mode == MODE_LIQUIDATION)`; `_mintLiquidator` at `MiFrensGenesis.sol:380` is uncapped (`LIQUIDATOR_ID_BASE + (++liquidatorMinted)`).
4. **Delegation is automatic** — `MiFrensGenesis.sol:703-704` `if (to != address(0) && delegates(to) == address(0)) { _delegate(to, to); }`. PoC asserts `getVotes(atk) == balanceOf(atk)` and it held (64 == 64). No extra step.
5. Quorum 10% (`TreasuryGovernor.sol:329 QUORUM_BPS = 1000`), proposal threshold 5 votes (`:331 PROPOSAL_THRESHOLD = 5`), `propose` is otherwise permissionless (`:415-420`, only `getVotes >= 5` + `allowedQuote`). 5 badges is trivial.

## What actually mints the badges (the hunter had the mechanism wrong)
`liquidate()` was NOT the productive path in the PoC — every position was already dead before the explicit call (`kills attempted 0`). The badges came from the hook's in-swap sweep, which credits **tx.origin**: `sweepLiquidations(address liquidator, ...)` at `PerpEngine.sol:1069`, reached from `_sweepAfterOpen` (`:1099-1105`). A long opened while spot is far above the TWAP is born insolvent — `_liqTest` values it at `_quoteMark(p.size)` (`:1555`) — so the *next* open's own sweep kills it and mints the badge to the opener. The attacker never calls `liquidate` at all.

## Measured economics (VERIFIED, 200 ETH seed pool, `minCollateral = 0.003 ether` at `PerpEngine.sol:182`, `maxLeverageCeiling = 3` at `:170`)
| n positions | total net ETH cost | per badge |
|---|---|---|
| 8  | 4.7423 ETH | 0.5928 ETH |
| 64 | 4.8422 ETH | 0.0757 ETH |

**Marginal cost per extra badge = (4.8422 - 4.7423)/56 = 0.001784 ETH (~$6 at $3.5k ETH).** The 4.74 ETH is the one-off pump/dump round trip (80 ETH in, 75.27 ETH back) that creates the spot-vs-TWAP gap; it is amortised over unbounded badges.

`MAX_OPEN_POSITIONS = 64` (`PerpEngine.sol:198`) does **not** bound farming: `openCount` was 0 throughout because each open's sweep clears the prior ones, so the cap is never approached.

**Corrected cost of a majority (DERIVED from the measured marginal cost).** Farmed badges inflate the quorum denominator too (`getPastTotalSupply`, `TreasuryGovernor.sol:7-16`), so against honest supply H the attacker needs X > H badges: cost ≈ 4.74 + 0.0018·X ETH.
- H = 1,111 (genesis only, launch regime): ~6.8 ETH (~$24k).
- H = 10,000: ~22.7 ETH (~$79k).
The hunter's "< 1 ETH" is wrong by one to two orders of magnitude; the claim "at roughly gas cost" is false — the pump/dump round trip and the forfeited collateral are real. But it is not "capital-at-risk" in the sense the comment asserts either.

## Counter-arguments that did NOT kill it
- Snapshot is `block.number - 1` (`TreasuryGovernor.sol:452`): adds latency, not cost — badges are held, farming is done days before proposing.
- Explicit delegation: refuted, auto-delegate at `MiFrensGenesis.sol:703`.
- Insolvency must be real: true, and it costs the collateral — but only 0.0018 ETH net per kill after the residual/penalty split (`liqPenaltyBps = 690`, `keeperBps = 145`, `PerpEngine.sol:155,168`), not the full 0.006 ETH staked.

## What bounds the damage (why Medium, not High)
A captured mandate cannot steal arbitrarily: destination is owner-allowlisted (`allowedQuote`, a vote cannot widen it), `MAX_ROTATION_BPS` caps a call at 50% of the live position, and venue/`minOut` are constrained (`TreasuryGovernor.sol:303-308`). Ceiling is a forced, oracle-floored rotation into an already-allowlisted quote plus slippage, not theft. HYPOTHESIS: repeated forced rotations are still a meaningful griefing/value-leak vector.

## Second-order finding (VERIFIED, separate from E2A)
Each farmed kill is a genuine insolvency, so the deficit lands on the PLV — the attacker converts community vault capital into votes. That, not the vote count, may be the larger harm.

## Constraints on any fix (NOT a prescription)
Whatever is done must not break the keeperless design: the badge is the incentive that makes `sweepLiquidations` self-funding. A blanket `keeper != p.trader` guard would silently stop paying the honest swapper whose trade happens to kill their own other position, and tx.origin crediting means the natural guard is not obvious. The economics fix (badge only above a size/age threshold, or votes decoupled from badges) is the fixer's call.

## Test-coverage gap (VERIFIED)
`test/attacks/YBase.sol:356 YMockMiFrens` has no `mintLiquidator`/`mintLiquidatorWithStats`, so every badge in that harness silently falls through to `badgesOwed`. No shared-harness test exercises the real badge mint.

## Caveats
Sepolia fork, 200 ETH seed / 60 ETH PLV. Absolute costs scale with pool depth; the marginal per-badge number does not. `PerpEngine.sol` is held by a fixer in the real tree — a change to `_sweepAfterOpen` or `_liqTest` would invalidate the measured numbers.
