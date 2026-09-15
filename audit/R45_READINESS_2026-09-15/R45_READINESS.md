# Round-45 deploy readiness — final report

Cauldron / Magic Internet Frens. 2026-09-15. Branch `redteam/2026-09-13`, base `e4ea3dc`, pre-review
snapshot `40ccfb2`, 25 commits landed. `main` untouched at `0d2c39c`. **Nothing pushed.**

The question this run answers: *would I deploy the current working tree to Sepolia today, and is there
anything hidden left in what CHANGED since round 44 — in the contracts, in the artifacts that will actually
be deployed, and in the off-chain layer that has to survive the chain misbehaving?*

---

## 1. Verdict

**Yes, deploy round 45 — and you could not have deployed the tree as it stood this morning.** Twelve
findings of Medium or higher were confirmed by execution and closed, including a permissionless theft that
**this review's own first fix created** and that only the neighbourhood re-hunt caught.

The single most important result is not any one bug. It is that **the deployed round-44 gacha router still
has no `playChurn` selector**, so the live spin path has been dead for two rounds, and until today nothing
in the pipeline could have told you. A clean build was not forced before broadcast, the selector checker
existed but was wired to nothing, and it covered 5 of 17 manifest keys. All four holes are closed and the
check now aborts the deploy.

Is anything hidden left? Three things, named rather than buried. **(a)** The read layer still assumes ETH
in places the contracts do not — that is the coherence pattern in §12, largely fixed today but the class is
wide. **(b)** The liquidation promise is complete for the common case but not when more than 8 positions
sink in one trade, nor after a quote rotation, where `_guardOpen` has no stale-quote check. **(c)** The
frontend RPC and indexer provider variables could not be read from the repository and must be checked in
the hosting dashboards before you ship.

---

## 2. Value & authority map (merged from the five hunters' models from code)

**The pool and the hook.** `CauldronHook._beforeSwap` is v4-`PoolManager`-only, gated by
`trackedPools[id]` adoption (`CauldronHook.sol:1244`); adoption itself is `require(sender == registry)`
(`:636`), and every `poolManager.initialize` in the tree sits inside `PoolOps`, a DELEGATECALL library, so
squatting is closed. Inside one swap the hook does fee, volume, death detection, gacha credit, legacy
buyback and liquidation — all sharing one gas budget, which is why gas floors are a security property here
and not an optimisation.

**Perp value.** In: trader collateral, vault funding (`fundFromVault`, onlyVault), permissionless
`fundInsurance`, hook-gated fee credit. Out: settlement proceeds, `liqPenaltyBps = 690` of collateral split
with `keeperBps = 145` to `tx.origin`, `skimInsurance` (onlyOwner, capped). Counters:
`totalEth() = plv + longOiEth`, `freeEth() = plv`, mirrored on the token side. **The waterfall** on a
shortfall is insurance first, then PLV — and a short buy-back may spend `backing + insuranceEth + plv`, so
the whole ETH LP base backstops one short. That is the exposure pre-emptive liquidation exists to prevent.

**Authority.** `relaunch()` is permissionless (gated only on `summoned`, `isDead`, lifetime, and a live
proposal). `resolveTickets` is permissionless. `rotateSliceFrom` is permissionless but bounded by the
treasury allowance, a venue allowlist and an oracle floor. `PerpVault` deposit/withdraw/claim are all
permissionless; `hasStakers()` gates `PerpEngine.setVault`, and `hasQuoteStake()` gates `syncGeneration`.
The owner holds mark-source arming, `skimInsurance` and `setOracle`. **The dangerous shape throughout is
not privilege — it is permissionless entrypoints whose accounting is order-dependent.** Two of this run's
worst findings were exactly that.

**Denomination.** A generation's quote can rotate between ETH (18), USDG (6) and xNVDA (18) while live.
Every stored amount's *meaning* can shift under it. This is the protocol's signature feature and the source
of most of its coherence debt.

---

## 3. Findings

Severity is the independent verifier's, not the hunter's, wherever they differed — verifiers downgraded
four and discarded one.

| id | sev | conf | what an attacker could do | location | fix |
|---|---|---|---|---|---|
| **NB** | **Critical** | VERIFIED | Repeatedly "settle" one queued LP and move almost his whole exit claim to the other claimants, for gas. 80 calls: victim 0.12195 ETH, attacker 9.87805 ETH of a 10 ETH backing. **Introduced by this run's own `8bcfe78`.** | `PerpVault._bankEthWriteDown` | `beedf49` — queue is units × one index; shortfall recognised once, globally |
| **C-1** | **Critical (round)** | VERIFIED | Nothing; the round ships broken. Deployed r44 router lacks selector `0xdf70b5a4`, so every spin reverts with empty data | `scripts/`, pipeline | `d9975af`, `763a84b` |
| R1C | High | VERIFIED | Cap your own gas and trade at full size with the liquidation sweep silently skipped; 0.30798 ETH of realized bad debt onto PLV. Attacker cost **negative** | `CauldronHook._liqSweep:791-799` | `b8b7ab9` — reverts `LiqGasStarved()` when the book is non-empty |
| R2B | High | VERIFIED | A stale token queue takes the next staker's entire principal (100e18 of 100e18); the token twin of a latch fixed on the ETH side only | `PerpVault:566,569,507` | `8bcfe78` |
| R2C | High | VERIFIED | One queued holdout shuts ETH deposits to everyone, indefinitely | `PerpVault:274,381,405` | `8bcfe78` + `beedf49` |
| R3A | High | VERIFIED | Peek at a losing crystal, never resolve it, re-roll the mint free forever (20 measured re-anchors) | `GachaLib:79-86` | `d21cfbe` — one re-anchor, ever |
| R5A | High | VERIFIED | Every crystal spin reverts on an ERC20-quoted generation | `CrystalCauldronGame.tsx:206` | `cf188a6` |
| R5B | High | VERIFIED | Type "1" on a 6-decimal quote and stake your entire balance, after an infinite approval | `StakePanel.tsx:84` | `d53c26c` |
| A-1/A-2 | High | DERIVED | Every perp open reverts on an ERC20 generation; the revert arrives as a hex blob | `usePerpEngine.ts:223-243` | `2132dd2` |
| A-3 | High | DERIVED | A USDG staker sees their balance 1e12 too small — units fixed on the write path only | `indexer/src/api/index.ts:1348,1376` | `5e7deb1` |
| B-1 | High | DERIVED | An honest crystal forfeits its draw through inactivity, undisclosed. **Consequence of this run's `d21cfbe`** | `GachaLib:135,150,182` | `dc35fa0` — keeper resolves; copy warns |
| B-2 | High | VERIFIED | Displayed gacha odds stop matching the chain the moment `setOracle` is called | `CrystalCauldronGame.tsx:162,202` | `9bcf5be` |
| B-3 | High | DERIVED | The rebirth panel reports a funded relaunch as unfunded under a rotated quote | `indexer/src/api/index.ts:373-385` | `5e7deb1` |
| R1B | Medium | VERIFIED | Pad the book with dust so a victim falls outside both sweep windows; 0.31526 ETH bad debt | `PerpEngine:419,1126` | `bfff978` — scan the whole book, bounded by gas |
| R4A | Medium | VERIFIED | A rebirth empties a seed reserve it then declines to use; up to 673.94 USDG stranded with **no recovery path** | `PoolOps:1173-1174` | `c6aefd0` — peek before pull |
| R2A | Medium | VERIFIED | Queue-jump seniority: a racing LP exits whole while a passive one absorbs the loss | `PerpVault:236,371` | accepted by design, reasoned in ledger |
| R1A | Low | VERIFIED | Liquidate a position solvent at the realized price (early, not wrong) | `PerpEngine:1552-1561` | accepted with rationale; kept as a characterization test |
| R5C/R5E | Medium | VERIFIED | A routine reorg crash-loops the indexer; a container booting into divergence reports healthy forever | `ponder.config.ts:107-121`, `api/index.ts:1260` | `52e9c3c`, `a2c2e0b` |
| R5F/R5G/R5H | Low | VERIFIED | Stack-trace leak on a bad param; silent keeper failures; infinite sell approval | various | `a2c2e0b`, `7863119`, `85a7a80` |

---

## 4. Leads — believed real, not demonstrated

1. **Stale quote after rotation, in the sweep.** `_guardOpen` has no stale-quote check, so after a rotation
   the liquidation sweep prices off the drained pool. *Next step:* rotate a live generation with an open
   book and assert the mark the sweep uses. **The most valuable open lead in this report.**
2. **More than 8 sinkable positions in one trade** exceeds `MAX_LIQ_PER_SWAP`; the remainder survives to the
   post-trade sweep at the depressed price. *Next step:* build a 9-victim book and measure the residual.
3. **Cross-pool projection contamination** via tracked siblings (hunter 1's L1).
4. **`MIN_TWAP = 1 second`** with no liquidation-side ring warmup (hunter 2).
5. **Dust-leg envelope burn** and **treasury exit to an owner-only sweep at rebirth** (hunter 4's L1/L2).

---

## 5. Proven safe (attacked hard, held)

Thirty-two documented refutations, each with the PoC that failed. Highlights: **relaunch liveness** held
from every reachable state including mid-rotation, non-ETH quote, squatted next-generation pool and hostile
recipient, with the full gen1→gen2→gen3 lifecycle green on fork; **PoolKey squatting** closed at the
adoption gate; **supply conservation and exactly-once gacha resolution** asserted and held; **the sibling
cap** binds atomically and one-way; **ABI parity** — 199 function/event entries across 25 exports compared
recursively including tuple component counts and `indexed` flags, zero mismatches; **off-chain** — bundle
secrets, `x-forwarded-for` rate-limit bypass, LLM prompt injection and OAuth redirect all held.

---

## 6. Coverage gaps

- `CHURN1_LiveRevert.t.sol:27` returns early without the fork env, so it **passes vacuously** — the exact
  vacuity pattern the brief forbids, in a kept test.
- The five `S08` tests carry `vm.skip(!active)`, so they are meaningful only on a live fork.
- `S06_PerpVaultSolvency` likewise skips rather than fails without a fork.
- The indexer registers **no `PerpVault` contract at all**, so `QueueWrittenDown` has no consumer and there
  is no feed of queued holders.
- Coherence agent B did not reach `MiFrensGenesis`, `CauldronCollection`, `RedemptionExt`,
  `CauldronSeeder`, `QuoteRotator`, `CauldronBase`, the presale hooks, or the indexer event handlers.

---

## 7. Artifact parity — will round 45 ship the source we reviewed?

**As the pipeline stood this morning: no, not reliably. As it stands now: yes, and it will refuse to ship
otherwise.** 17 contracts compared chain-versus-source. The router is STALE-AT-DEPLOY — `0xdf70b5a4` absent
on chain, present in source. The hook, engine and vault show EXPECTED-DRIFT (source moved after r44; the
r44 engine's mark-source slot reads `1e18`, which independently proves the deployed engine is not this
source). `perpVault` is missing four read-only getters that nothing calls. Four rows NOT VERIFIED:
`quoteRotator` parity, timelock bytecode (dirty submodule), the r44 mark-source value, and inline ABIs in
`src/hooks`/`src/components`.

Four mechanisms by which a stale artifact could ship, all now guarded: no clean build (`763a84b` forces
one), selector check wired to nothing (`d9975af` runs it from `apply-deployment.mjs`, `auto-deploy.sh` and
CI, aborting on a miss), 5-of-17 key coverage (now 11 keys / 43 signatures), and a broken vendored import
that only a stale cache hid.

---

## 8. Off-chain liveness

Full runbook in `OFFCHAIN_LIVENESS.md`. The short version: `/freshness`, not `/health`; find the provider
whose block `N+1` parent-hashes to `N`; pin `PONDER_RPC_URL` to that one provider; **a schema bump alone
does not help**, because the bad data arrives live from the RPC. The round-robin default that caused the
25-minute outage is replaced with a single pinned provider and ordered failover.

---

## 9. Decontamination

66 files, 490 tag substitutions, comments only. Verified: residual finding-shaped grep clean (45 hits, all
inside test-assertion string literals), line counts **identical** between trees, and `forge build --sizes`
**byte-identical** for every contract in both. 139 answer-key PoCs quarantined.

**What leaked, honestly:** hunters were blind to prior *conclusions*, not to the fact that this code has
been reviewed — comments and identifiers like `reanchored` survive comment-stripping. **Evidence it still
worked:** the quarantine hid the prior PoCs for both the gacha grind and the vault queue latch, and both
were independently rediscovered *at a higher severity* by hunters who never saw them.

---

## 10. Reconciliation

Full detail in `RECONCILIATION.md`, including a correction I made to my own earlier classification.

- **Fix-induced:** NB (by this run, hours old) and R1C/R1A (by the 2026-09-11 remediation).
- **Rediscovery of a "fixed" item ⇒ the fix is broken:** R2C — `Jb` closed the revert path but not the
  latch, and the prior comment claiming a "permissionless" release was **false as written**. R2B — the last
  run wrote the token twin down verbatim, deferred it, and its stated reason for deferring was backwards.
  R3A — `K4b` was downgraded on an argument this run's PoC defeats.
- **Correction:** I first classified R1C as new. It was not. The 2026-09-11 run found the mechanism, wrote
  the PoC, considered this exact remedy and **rejected it** as "a worse liveness property than the one it
  buys". What is new is the verifier's proof that the loss is **realized, not deferred**, which is what
  defeats that reasoning. **The owner was asked directly and confirmed: protect the stakers, keep the fix.**
- **Missed by us:** the 2026-09-09/11 finding sets were not re-derived (the run was deliberately narrowed to
  the delta and the deploy seam); `Jc` and `SIB1-D` not rediscovered; `S06` remains open and pre-existing.
- Verifier discards: 1 (R2D, not reproducible without a fork harness). Downgrades: 4.

---

## 11. Fixes, suite and size

25 commits. No size refactor was needed: no contract crossed EIP-170 at any point.

| | suites | passed | skipped | failed |
|---|---|---|---|---|
| P0 | 244 | 969 | 1 | 2 |
| Final | 254 | **985** | **1** | 3 |

Skip count did **not** grow. Of the three failures: `S06` is the known pre-existing baseline, **bit-identical
across three independent source changes**; `CHURN1` is the expected live-incident PoC that will pass once
r45 deploys a correct router; `T02` was an RPC timeout that passed cleanly on re-run.

Bytes: CauldronHook 23,140 → 23,258 (1,318 free); PerpEngine 24,247 → 24,215 (361 free, *smaller*);
PerpVault 9,858 → 11,280; PoolOps 24,006 → 24,173 (403 free); GachaLib 1,466 → 1,652; CauldronRegistry
unchanged at 24,492 (**84 free — the tightest contract in the repo**).

---

## 12. Coherence

Full table in `FUNCTIONAL_COHERENCE.md`. No Criticals; neither agent found a UI path that loses funds.

**The finding is a pattern, not a list: the contracts were built for quote rotation and the read layer was
not.** Every coherence High except two was the same defect wearing different clothes — a value parsed or
formatted at 18 decimals, or a `value`-bearing call, on a protocol whose thesis is that a generation's quote
can rotate to a 6-decimal asset. *The incentive that breaks first:* nobody rotates, because the first
generation to move to USDG finds the perp panel dead, balances 10^12 too small and the relaunch panel lying
about funding. All of those are now fixed; the class is wide enough to deserve a dedicated pass.

Two disclosure gaps remain open and deliberate: the UI never tells a trader that **a stranger's swap can
close their position**, and a user blocked by `QueueInsolvent` has no in-app remedy (the app cannot choose
the `address` argument, so a keeper verb was judged the honest answer over a button that cannot work).

---

## 13. Blind spots

Named, not hidden. No coherence agent executed anything — A-1, A-3, A-4, B-1 and B-3 are DERIVED from
reading. The Arc deployment was not reviewed. `main` at `0d2c39c` was never examined; this reviews the
red-team branch. Hosting configuration (`VITE_SEPOLIA_RPC_URL` on Vercel, `PONDER_RPC_URL` on Railway) is
**not verifiable from the repository** and must be checked by hand. The `collection` and `seeder` manifest
addresses are carried forward by `apply-deployment.mjs` when broadcast names no CREATE, making them the
least verifiable entries. A peer session was idle in this repo at start; judged not active, flagged here.

---

## Would I deploy this to Sepolia as round 45 today?

**Yes — with one non-negotiable step: run `node scripts/verify-selectors.mjs` against the new manifest after
the deploy and confirm it exits clean.** That is now automatic in the pipeline, and it is the one check that
would have caught the bug that has been live for two rounds. Before you ship, also confirm the two hosting
RPC variables are populated, because neither can be verified from this repository.

**Before mainnet**, four things would have to be true that are not true today. The five fork-gated test
files must lose their skip guards, or a CI fork job must make them unskippable, because a third of this
suite currently proves nothing without a fork. The rotation-to-6-decimal path needs a dedicated pass across
the whole read layer, since today's coherence fixes closed the instances we found, not the class. The
stale-quote lead in the liquidation sweep needs executing, not reasoning about. And `S06` — open across at
least three reviews — needs closing or an explicit written acceptance, because a known-failing solvency PoC
is not something to carry into mainnet quietly.
