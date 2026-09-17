# Robinhood mainnet (4663) — readiness verdict

Branch `redteam/2026-09-13`, 22 commits on top of `a3bcd29`. Nothing pushed.
`main` frozen at `0d2c39c`.

## 1. Verdict

**DO NOT DEPLOY TOMORROW.** Not because the protocol is unsound — the contract
work is in materially better shape than it was 24 hours ago — but because the
things still open are precisely the ones that are **irreversible, unreviewed, or
untested at launch time**:

- One deploy parameter (`MAX_PER_WALLET`) is **immutable** and currently equals
  the entire genesis supply. Get it wrong tomorrow and it cannot be fixed.
- **There is no mainnet deploy script.** The documented path is a bare
  `forge script` with no clean build; the stale-`out/` failure that bit rounds 43
  and 44 is unguarded exactly where it now matters.
- **The fix batch from this review has not been re-hunted.** Four consecutive
  remediations in this protocol have each shipped their own bug, and this run's
  round-1 re-hunt caught a High introduced by this run's own first fix. Seven
  Solidity commits — including the Critical — are adversarially unreviewed.
- A **new routability regression** (LIQ04) is failing in the suite, caused by our
  own gas-floor fix, against a standing constraint that the pool must stay
  routable.

A launch that slips by a few days and closes these is a good launch. A launch
tomorrow is a bet that four independent unknowns all land favourably.

## 2. Suite

| | P0 baseline | final |
|---|---|---|
| suites | 254 | **264** |
| passed | 986 | **1030** |
| skipped | 1 | **1** |
| failed | 2 | **4** |

Skipped did not grow. +44 tests are this run's regression coverage.

**The 4 failures:**
1. `test_S06_POC_RealEngine_QueueingBeforeBadDebtShedsAllOfItOnLpB` — pre-existing,
   open 3+ reviews. Numbers **bit-identical at six measurements**
   (`344218925886143795 <= 459182015833333191`), so it is static, not drifting.
   E2's mainnet verdict: **should not be open on a real-money deploy.**
2. `test_CHURN1_playWorksButChurnReverts` — pre-existing; asserts against a live
   router lacking `playChurn`. Passes once a good router ships.
3. `test_LIQ04_PreSweepDoesNotStarveTheUsersSwap` — **NEW, ours.** `3000000 >
   1600000`: the pre-sweep multiplies the gas a plain buy needs by **more than
   4×**, violating an explicit routability bound. From T1a (`0f71309`).
4. `test_S08_E_PoC_ABiggerBookRaisesTheBarForEverySweep` — **NEW, ours.** Encodes
   the pre-T1a behaviour; the fix makes the swap revert rather than fill.

3 and 4 were reported unmodified by the fixer rather than edited to pass.

## 3. Blocking before any mainnet deploy

**B1 — `MAX_PER_WALLET` (irreversible).** VERIFIED by live `cast call`:
`MAX_PER_WALLET() = GENESIS_SUPPLY() = 1111`, `immutable`
(`MiFrensGenesis.sol:119`, set at `:243`), **no setter**. It is a constructor
argument. Pass a real per-wallet cap at the 4663 deploy or one wallet can take
the entire genesis supply — and, until B3 lands, 1,111 votes with it.

**B2 — no mainnet deploy path.** `auto-deploy.sh:65` hard-refuses any chain ≠
11155111. No `clean`/`--force` before broadcast. `auto-deploy.sh:81`'s EIP-170
guard reads `$4` (initcode size) not `$5` (runtime margin) — **it can never
fire**. `verify-selectors.mjs` defaults its RPC to Sepolia and nothing on a 4663
path sets `RPC_URL`, so the selector gate would go red on all 11 keys. Four
manifest values have **no producer** (`indexerUrl`, `genesisSupply`,
`deathThresholdEth`, `legacy*`), and the template ships `deathThresholdEth: 0`
against a runbook saying `1e18`. `vault`'s `redeem` is **structurally ungated** —
the same shape as the `playChurn` defect that shipped twice.

**B3 — governance fix is uncommitted and unverified.** Owner ruled badges must
not vote. `MiFrensGenesis.sol` is dirty, `V2B_GenesisOnlyQuorum.t.sol` untracked.
**The quorum-denominator trap was never checked**: if badges stop carrying votes
but still count toward the supply quorum is measured against, every badge minted
raises the bar while adding no weight, and badges are unbounded — governance
would slowly become unreachable. Do not ship this fix unverified.

**B4 — re-hunt round 2 never ran.** Killed by the rate limit mid-PoC. Named
targets that remain **unanswered**: whether `_settle`'s in-place settlement swap
re-enters the hook's sweep recursively; whether book-padding with dust positions
can make an honest trader's swap revert (a griefing vector at ~0.003 ETH/position
against the new revert-on-incomplete-sweep behaviour); `GachaLib` hashed-slot
collisions; `stalled()` boundaries.

**B5 — LIQ04 routability.** See suite failure 3. Aggregators quoting a pool that
can demand 3M gas may decline to route it.

**B6 — read layer.** No alerting anywhere (zero sentry/pager/webhook in repo);
`/freshness` is polled only by a browser; Railway stops restarting after 10
attempts. **No archive RPC exists for 4663** — indexer recovery is not executable
without buying one.

## 4. Non-blocking but open

- **B-4 decimals** — `legacyThreshold = 0.02 ether` compared against quote-raw
  `legacyBuffer` (`CauldronHook.sol:336` vs `:1115,:1124`). On a 6-dec quote the
  floor buyback **silently never fires** while the UI advertises it. DERIVED.
- Activity-feed `quoteWei` round-trip, 1e12 off on a 6-dec quote. Display only.
- **E1A split band** — preserved at `e1a-splitband-followup.patch`. Restores
  same-swap closure; needs ~987 B freed first.
- **`usePoll`** — the primitive still ignores its closure's inputs; 13 call sites
  inherit the RH1A shape. ~4-line fix, zero call-site changes.
- T3C supply capture (no per-actor throttle), R1A, R2A re-raised as Mediums.

## 5. What the review actually closed

**22 commits.** One Critical (E1A), one deploy-blocking Critical (T5A), one
read-layer Critical (reorg tolerance off by 322×), plus 6 Highs and 8 Mediums.
Full register in `FINDINGS.md`; chain facts in `CHAIN_PROFILE.md`.

The single most valuable structural result: **the 18-decimal class is not
closed.** Three independent agents each found surviving instances, and the last
found three more while fixing. Treat every quote-denominated value as guilty.

## 6. What I would still lose sleep over

1. **The unreviewed fix batch.** Seven Solidity commits, no adversarial pass.
   History says the next bug is in there. One re-hunt round closes it.
2. **`MAX_PER_WALLET` at deploy.** One immutable constructor argument between a
   fair launch and one wallet owning the collection and the electorate.
3. **The read layer on day one.** A reorg deeper than the new tolerance, or a
   Ponder crash, with no alerting and no archive to recover from — nobody finds
   out until a user says the site is wrong.
