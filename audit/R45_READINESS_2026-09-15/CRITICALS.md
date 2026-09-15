# CRITICALS — appended the moment one lands (read mid-run)

## C-1 (P2.5, round-scoped) — deployed r44 gachaRouter has no `playChurn` selector
- Source: ARTIFACT_PARITY.md §A/§B. On-chain runtime at 0x4658…2FdA lacks selector 0xdf70b5a4; the current source has it. The live app's churn/spin path reverts with empty data. Not a source bug: a stale artifact was broadcast on r43 and r44.
- Round-45 consequence: the deploy pipeline (scripts/deploy-*.sh, deploy-round.mjs) has NO clean build / `--force` before broadcast and NO post-deploy `verify-selectors.mjs` run, so r45 can ship the same way. `verify-selectors.mjs` guards 5 of ~17 manifest keys and ~10% of the ~80 functions the app calls.
- Status: to fixer (off-chain pipeline group) at P4; verification of the full picture by the P2.5 verifier in progress.

## C-2 (P1 hunter 2, PENDING P2 verification) — R2B: token-side exit queue latches forever, bricks `PerpEngine.setVault`
- Claim: `PerpVault.claimPendingToken` (contracts/solidity/cauldron/PerpVault.sol:566,569) still reverts `ZeroAmount()` where the ETH twin (:390,403) banks the write-down; both reverts roll back the haircut (:565), so once token backing < `pendingTok` the queue can never shrink; `hasStakers()` (:205) latches true; `PerpEngine.setVault` (PerpEngine.sol:2620) is bricked for the engine's life. `depositToken` (:507) also lacks the ETH side's `QueueInsolvent` guard (:274): the next token staker's principal pays the stale queue in full (measured 100e18 of 100e18).
- Reachability claimed via `_writeOffTok` (PerpEngine.sol:2225) or a relaunch migration shortfall (`syncGeneration` :1310). PoC: /tmp/r45-blind-h2/contracts/solidity/test/attacks/R2B_TokenQueueLatch.t.sol (4/4 pass, assertions observed under -vv).
- Status: Verifier 2 running (reachability from public entrypoints is the open question).

## C-3 / C-4 / C-5 (P1 hunter 1, re-run by the orchestrator, PENDING P2 verification)
The pre-emptive liquidation sweep — the feature whose whole purpose is to stop PLV stakers underwriting
traders — can be skipped or misfired three ways. All three reproduce in /tmp/r45-blind-h1, each with a
POSITIVE CONTROL that passes, so none is a test artifact. Orchestrator re-ran them directly:

- **C-3 (R1C) — the caller picks the gas, and the whole liquidation engine is optional.**
  `CauldronHook.sol:161` LIQ_GAS_RESERVE=180_000, `:172` LIQ_GAS_MIN=400_000, `:791-799` `_liqSweep`
  runs only `if (g > reserve + LIQ_GAS_MIN)`. Pre-trade needs ~980k gas, post-trade ~580k, but the bare
  swap costs ~104k. A swapper who caps tx gas executes a FULL-SIZE trade with BOTH sweeps skipped.
  Measured at a 500,000 gas cap: victim survives, insolvent, **bad-debt gap 0.30798 ETH**.
  Control `test_R1C_positive_uncapped_gas_preempts` PASSES (survivedPos false).
- **C-4 (R1B) — a 12-slot window over a 64-slot book.** `PerpEngine.sol:419` SWEEP_SCAN=12, `:186`
  MAX_LIQ_PER_SWAP=8, `:198` MAX_OPEN_POSITIONS=64, `:1126` the scan loop. minCollateral 0.003 ETH
  (`:182`) lets anyone pad the book; 40 padding positions push a chosen victim outside BOTH the pre- and
  post-trade windows of the same swap. Measured **bad-debt gap 0.31526 ETH**; control (short book) PASSES.
- **C-5 (R1A) — free kill inside the projection slack.** `PerpSwapLib.projectedSqrtPriceX96` inflates the
  pending input by SLACK_BPS=1500 and rounds UP; `PerpEngine._liqTest` then uses that projected price as a
  ZERO-BUFFER trigger. Measured: victim value at the REALIZED post-trade price 0.96281 ETH against a
  0.931 ETH threshold — solvent — yet force-closed by that trade. Minimum kill size 22.25 ETH-equivalent.
  NOTE for reconciliation: a prior pass refuted a similar-sounding claim (slack is on the INPUT, small bps
  vs a large buffer). This PoC is NEW EVIDENCE — an actual liquidation of a position solvent at the
  realized price — so it must be judged on the numbers, not dropped by the old argument.

PoCs: /tmp/r45-blind-h1/contracts/solidity/test/attacks/R1{A,B,C}_*.t.sol (2 controls pass, 3 attacks fail
as designed). Severity pending Verifier 1; on the schema's definition (permissionless loss of funds borne
by stakers) C-3 and C-4 are Critical candidates.

## C-6 (NEIGHBOURHOOD RE-HUNT — FIX-INDUCED BY THIS RUN, CONFIRMED by the orchestrator)
**`PerpVault.settlePendingEth(address)` is permissionless and NOT idempotent: repeated calls confiscate a queued LP's claim and hand it to the other claimants.**

This bug did not exist this morning. It was introduced by THIS RUN's own fix for R2C (commit 8bcfe78),
which added permissionless settle entrypoints so a queue could be un-stuck by anyone. The re-hunt phase
exists precisely because the last two remediations each shipped their own bugs; it just earned its slot.

Mechanism, `contracts/solidity/cauldron/PerpVault.sol:383-394` (`_bankEthWriteDown`), reached from `:415`:
```solidity
owed = pendingEthOf[user];
uint256 capped = _haircut(owed, engine.totalEth(), pendingEth);   // owed * backing / claims
if (capped < owed) { pendingEth -= (owed - capped); pendingEthOf[user] = capped; owed = capped; }
```
Each call re-divides the caller-chosen user's ALREADY-REDUCED claim by a `pendingEth` denominator that
still carries every other claimant's FULL nominal, and `backing < claims` stays true, so the same victim
can be ground down again and again. Nothing tracks that a write-down was already taken.

Measured by the orchestrator, re-running the re-hunt's PoC (2 tests, both FAIL as designed, no
`return;`/`vm.skip`, assertions observed under -vv), backing 10 ETH, two equal 10 ETH queued claims:
- **Spam form:** 80 calls aimed at one LP → victim's pending 0.1235 ETH, attacker's 10 ETH; victim paid
  **0.12195 ETH**, attacker paid **9.87805 ETH**. Cost: gas only. No role. No capital at risk.
- **Weak form (the positive control, which also fails):** ONE settle each, in order, pays **4.2857** vs
  **5.7143 ETH** where both should get 5. So this is not merely a spam bug — the accounting is
  ORDER-DEPENDENT for honest callers too.
- `settlePendingToken` / `_bankTokWriteDown` (`:612`, `:626`) is the identical shape (DERIVED).

PoC: /tmp/r45-rehunt/contracts/solidity/test/attacks/NB_SettleSpamHaircut.t.sol
Status: routed to fixer-vault. **Round 45 must not deploy until this is closed** — it is a permissionless
loss of a user's funds, strictly worse than the deposit denial-of-service (R2C) the fix was closing.

Required invariant for the remedy: after ANY sequence of settle/claim calls in ANY order and any number
of repetitions, each queued claimant receives their pro-rata share of backing. The remedy must NOT
reintroduce R2C (a queued holdout must still not be able to hold the deposit gate shut) and must NOT
reintroduce R2B (a stale queue must still not take a new staker's principal).

### C-6 CLOSED — verified by the orchestrator
Fix commit `beedf49` (fixer-vault). The exit queue is now UNITS x a single INDEX: a shortfall is
recognised ONCE, globally, by scaling `ethQueueIndex`/`tokQueueIndex`, and `settlePending*` touch no
per-user state — so there is nothing to repeat and no order to depend on.

Orchestrator re-ran `test/attacks/NB_SettleSpamHaircut.t.sol` in the REAL tree, 4 tests, all PASS,
assertions observed under -vv:
- 80-call spam: victim **5.000 ETH**, attacker **5.000 ETH** (was 0.12195 / 9.87805)
- positive control, one settle each: **5.000 / 5.000** (was 4.2857 / 5.7143)
- idempotence: 1 settle and 50 settles give a byte-identical index (5e26) and entitlement (5e18)
- order-independence: A-then-B and B-then-A both give 5e18 / 5e18
`R2B_TokenQueueLatch` and `R2C_DepositLatch` re-run green in the same batch, so neither earlier finding
regressed. PerpVault 9,858 -> 11,280 B (13,296 free); nothing over EIP-170.

Follow-on caught by the orchestrator while verifying: the restructure changed `QueueWrittenDown` to
`(bool indexed tokenSide, uint256 writtenOff, uint256 newIndex)` while `src/config/perp.ts` still declared
the per-user shape whose first topic was an `address`. Latent (nothing consumes the event yet) but it is
the artifact-drift class this review exists to catch. Corrected in `229d98b`; tsc and build clean.
