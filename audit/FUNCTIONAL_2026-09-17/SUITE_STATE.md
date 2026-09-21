# Suite state — measured at `cdb319d`, clean worktree

**This is the first number in this review taken against committed code only.**
Every earlier figure (35, 36, 38, 89, 92) was measured in a shared worktree
carrying uncommitted edits from up to four sessions, and at least three
"findings" were artefacts of that. Method matters more than the number:

```
git worktree add /tmp/final-verify HEAD
cd /tmp/final-verify/contracts/solidity
ln -sfn <repo>/contracts/solidity/lib lib      # avoid a second dependency tree
FOUNDRY_PROFILE=cauldron \
FORK_RPC=<keyed archive endpoint> \
forge test --threads 2 --skip 'lib/v4-periphery/lib/permit2/script/**'
```

```
297 suites · 1147 passed · 14 failed · 1 skipped (1162 total) · 827s
infrastructure failures: 0
```

Two things that silently corrupt this measurement if you skip them:
- **Use a keyed archive RPC.** `ethereum-sepolia-rpc.publicnode.com` cannot carry
  297 suites; it fails with `could not instantiate forked environment`, which
  reads exactly like a code failure. One run produced 110 such lines and a
  "92 failures" scare.
- **Do NOT add `--skip 'test/audit_full_scope/**'`.** That workaround was adopted
  from a real compile error, was fixed upstream, and then silently excluded
  **14 files / 83 tests** from every number both sessions reported for days.

## The 14, fully classified — no unexplained failures

### Active work in flight (7) — the kill-cap → gas-bound change
Owned by session `magic-internet-frens-2c`, in progress. These assert the
*target* behaviour of raising `MAX_LIQ_PER_SWAP` and conditioning refusal on
genuine gas exhaustion rather than a kill count.

| test | why it fails today |
|---|---|
| `test_largeBookGasLadderEitherRejectsAtomicallyOrLeavesSafeBook` | asserts `successes > 0` across a 1M→16M ladder; under a **count** bound every rung refuses, so it fails by construction and would fail at 100M |
| `test_maximumBookCannotBypassPreSweepViaKillCap` | same root |
| `test_twentyFourPositionsCannotBypassPreSweepViaKillCap` | same root |
| `test_twentyFourPositionExactOutputBuy` | same root |
| `test_mixedBookRotatedCursorMustNotSkipDangerousPrefix` | same root |
| `test_preTradeBadgesDeferWithoutDroppingKeeperCredits` | badge defers to `badgesOwed` under a wider kill loop |
| `test_maximumBookTradeMustFitSepoliaTransactionGasCap` | **the test is wrong.** 64 dust shorts + a 45 ETH buy ≈ 28M of work against EIP-7825's 16,777,216 cap. Impossible at *any* kill cap, including none. Being fixed as a test. |

Note these tests measure the same defect `98a97ec` fixed, from the opposite
side: one found **56** stranded positions where mine found 2. Same bug, worse
measurement, independently discovered.

### Rotation, owned by `2c` (4)
`test_R2D_roundTripMisclassifiesThePositionHoldingTheTreasury` ·
`test_T02_POC_DustLegBurnsTheWholeMigrationMandate` ·
`test_INVARIANT_S02_04_APoolIsNeverItsOwnVolumeSibling` ·
`test_regression_routeC_rotationWorksAgainOnceTheBookDrains`

`SlippageTooHigh()` ×4 is the oracle-rate trap: every rotation venue seeds
**40 ETH : 400,000 USDG (1 ETH = 10,000 USDG)**. A mock priced at $3,000 makes a
USDG→ETH floor demand 3.3× what the pool can give — a pricing bug that surfaces
as a slippage bug, silently.

### Known baseline, pre-existing (3)
- `test_S06_POC_RealEngine_...ShedsAllOfItOnLpB` — open across 3+ reviews,
  numbers **bit-identical at an eighth measurement**
  (`344218925886143795 <= 459182015833333191`). Genuinely static, not drifting.
  E2's mainnet verdict: should not be open on a real-money deploy. **Owner call.**
- `test_CHURN1_playWorksButChurnReverts` — asserts against a live router lacking
  `playChurn`; passes once a good router ships.
- `test_S08_E_PoC_ABiggerBookRaisesTheBarForEverySweep` — encodes pre-`0f71309`
  behaviour; stale-by-success, needs retiring or inverting.

## Guard tests — must never regress

| guard | asserts |
|---|---|
| `E1B_LiqDrainScale` | `drain wei: 0`, attacker net **−0.0591 / −0.1773 ETH** (E1A Critical) |
| `XL1_LiqTwapAndDepthCap` | 6/6 incl. `NestedSweepIsANoOp` |
| `D04_RebookErasesFundingAndPenalty` | funding, penalty, keeper cut survive a partial close |
| `H1B_SweepCapCertifiesUnscanned` | crash swap reverts with **0 stranded** |
| `H1C_PreExistingBacklogWedge` | backlog drains **18 → 0, zero keeper calls** |
| `test_ownerPartialCloseMustRespectNonzeroMinimum` | a partial close honours the signed `minOut` |

## Method lessons worth more than the number

1. **`git worktree add` at the commit you mean to characterise.** Three separate
   findings this week — a rotation Critical, a round-trip inversion, and a
   `QUOTE_ORACLE` escape hatch — were confident conclusions drawn from a dirty
   tree. All three were retracted.
2. **Two independent readings agreeing is not execution.** The inversion had two
   sessions agreeing on the code and both wrong about reachability: neither
   checked whether the path reaches the branch with that argument.
3. **Transcript recovery works for destroyed uncommitted work.** Parsing
   `~/.claude/projects/<repo>/*.jsonl` for `tool_use` entries where `name` is
   `Edit`/`Write`/`MultiEdit` yields the exact `old_string`/`new_string`. Used
   once in anger here, recovering a 4-line hunk byte-for-byte. Stale `out/`
   artifacts are corroborating forensics: a size delta proves lost lines were
   functional before you know what they said.
4. **A workaround outlives the condition that justified it.** The
   `audit_full_scope` skip was correct when adopted and wrong within a day, and
   nobody re-tested the assumption.
