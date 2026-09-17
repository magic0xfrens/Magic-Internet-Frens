# E2 — Patient Whale & Re-pricer of Accepted Risk

Working tree: `/tmp/rh-blind-h4`. Fork: Sepolia v4. All code cites verified by reading in this tree.
Method note: my primary deliverable is verdicts. Where a verdict is DERIVED (read + reasoned, not
executed) it says so; I did not manufacture PoCs I could not stand behind under the budget.

---

## (1) Re-pricing table — every standing accepted risk

| id | original argument | mainnet re-argument (borrowed capital, real TVL) | verdict | numbers |
|---|---|---|---|---|
| **R1A** free-kill in projection slack | "early not wrong; victim already underwater; bounty ~1 mETH ≪ 0.5–1 ETH round-trip fees" | Bounty is `toKeeper = penalty·keeperBps = collateral·690bps·145bps ≈ **0.1% of collateral** (`PerpEngine.sol:1752-1757`), scaling **linearly with victim size**. `liquidate(id)` (`:1042`) is permissionless, keeper=`msg.sender`, gas-only cost; FCFS means the race is latency not fees, so a co-located searcher wins uncontested. The victim eats the **6.9%** penalty (`liqPenaltyBps=690`, `:155`) on a position solvent at the true mark but underwater at the projected mark. | **RE-RAISE → Medium** | 100-ETH-collateral victim: searcher nets ~0.1 ETH for gas; victim loses ~6.9 ETH. Value transfer, not drain; bounded by book size & how deep the projection slack flips solvency. DERIVED. |
| **R2A** queue-jump seniority | "LP-vs-LP, no value leaves, documented" | `_syncEthQueue` haircuts **only when queue > total backing** (`PerpVault.sol:460-466`); any smaller partial loss → queued exits eat **0%**, staying stakers eat **100%**, contradicting the code's own pro-rata comment (`:394-400`). "No value leaves the system" is the exact defence this run voids. At mainnet PLV (tens–hundreds ETH) the misallocation between LP cohorts is unbounded in absolute terms. | **RE-RAISE → Medium** | H2's `M2a_QueueSeniorityDodge.t.sol` already shows lpA 0% / lpB 100% of a 3-ETH loss vs 1.5/1.5 pro-rata. Still DERIVED (bad-debt trigger simulated); real-long-loss path is `PerpEngine.sol:1681-1687`. |
| **S06** bad-debt shedding | "no value leaves" | Same class as R2A; test still fails bit-identically across 5 measurements (`344218925886143795 <= 459182015833333191`), open across 3+ reviews. Not in this decontaminated tree (only referenced by `test/functional/F10_QuoteRotationTotality.t.sol`), verdict per coordinator's numbers. On a real-money deploy this **should NOT still be open**: it is a solvency/fairness invariant that misallocates ~0.115 ETH per the measured case and scales with PLV. | **RE-RAISE → Medium (open)** | measured gap 0.459−0.344 = **0.115 ETH** on a small pool; scales linearly with staked ETH. |
| **R1B** sweep-window starvation | "padding cost ~0.40 ETH of recoverable collateral" | The direct `liquidate(id)` (`:1042`) path is always available and unbounded per call, so padding only delays the *in-swap* sweep (`MAX_LIQ_PER_SWAP=8`, `:186`), never removes liquidatability. Damage is latency, not lost funds; the padding collateral is recoverable. | **ACCEPT-STILL-HOLDS** | attacker locks ~0.40 ETH recoverable; no permanent loss. |
| **SIB1-D** `linkVolume` O(n²) | 487k gas at 9th sibling | `linkVolume` is **registry-gated** (`CauldronHook.sol:1707 OnlyRegistry`), not permissionless; bounded by `MAX_SIBLINGS` (~10). Not an external attack vector. The real residual is the **one-way ratchet** (no `unlinkVolume`, `:1765-1771`): the 10th distinct rotation destination bricks further rotation — but that is governance's own choice, not a stranger's. | **ACCEPT-STILL-HOLDS** (note the ratchet as a liveness lead) | O(n²) ≤ ~45 iters, one-time per rotation, gated. |
| **MIN_SEED_UNITS** decimal-blind | "magnitude, not safety" | `= 777_000_000e18 >> 60 ≈ 6.739e8` raw units (`PoolOps.sol:225`). For a 6-dec quote ≈ 673.9 tokens; for an **18-dec quote it is 6.7e-10 tokens — a no-op floor**. It is a magnitude sanity check, not a safety invariant, and seeding is not a permissionless attacker primitive. | **ACCEPT-STILL-HOLDS** (Low hygiene: no-op on 18-dec quotes) | — |
| **R3B** churn credit | "intended economics" | Per Hunter 3 (do not redo): real multiplier **14.69×** (10.1× a plain buy), churn *worse* per ETH of fee burned (36.7 vs 48.5 credit/ETH), and `lifetimeVolumeOf`/`totalLifetimeVolume` (`CauldronHook.sol:956-961`) **read by nothing on-chain**. | **ACCEPT-STILL-HOLDS** (corrected verdict recorded) | credited volume is not a claim on any pot. |

---

## (2) New findings

```
id: E2A   severity: High   confidence: DERIVED
subsystem: governance electorate / perp liquidation badges
file:line:
  PerpEngine.sol:1042  function liquidate(uint256 id) external nonReentrant notNested { ... _settle(id, p, 0, MODE_LIQUIDATION, msg.sender); }  // keeper = msg.sender, NO self-counterparty guard
  PerpEngine.sol:1767  _awardBadge(id, keeper, _killStats(p, toKeeper));            // 1 badge per kill to the keeper
  PerpEngine.sol:2340-2355 _awardBadge -> PerpSwapLib.tryMintBadge(IPerpHook(hookAddr).collection(), to, st)
  MiFrensGenesis.sol:48  contract MiFrensGenesis is ERC721, ERC721Votes ...
  MiFrensGenesis.sol:176 "this collection is ERC721Votes, so a badge carries ONE governance vote ... not cheaply farmable"
  MiFrensGenesis.sol:703-704 if (delegates(to) == address(0)) _delegate(to, to);   // auto self-delegate on receipt
  TreasuryGovernor.sol:328 QUORUM_BPS = 1000 (10%);  :930 need = getPastTotalSupply(snapshot)*QUORUM_BPS/1e4
title: Governance voting power is farmable at ~gas cost by self-liquidation: an attacker opens their
  own dust perp positions and liquidates them (permissionless liquidate, keeper=self), minting one
  uncapped ERC721Votes badge = one vote per kill, defeating the "capital-at-risk, not cheaply
  farmable" defence and letting a stranger force OR block the de-risking switch / any treasury rotation.
precondition: iteration-2 MiFrens continuation where hook.collection() is the ERC721Votes MiFrens
  (the badge target). No per-actor cap anywhere; no guard that keeper != trader.
sequence (repeat per vote):
  1. attacker: perp.open{minCollateral=0.003 ETH}(...) at max leverage
  2. attacker: nudge the pool mark so _liqTest trips (or wait one funding block)
  3. attacker: perp.liquidate(id)  -> badge (1 vote) minted to attacker; pays 6.9% penalty of dust
  4. after >= quorum votes accrued and one block, propose+vote the de-risking mandate.
capital: ~gas + 6.9% of minCollateral per badge; FLASHLOANABLE n/a (votes must predate snapshot, held).
attacker_cost: penalty per badge = 0.003 ETH * 690bps = 2.07e-4 ETH. Quorum at ~1,200 vote supply =
  120 votes ~ 0.025 ETH + gas; a working MAJORITY (~1,300 badges) ~ 0.27 ETH + gas.
damage: capture of the entire treasury-rotation / de-risking electorate for < 1 ETH; can force the
  book into a chosen quote up to maxTotalBps, or veto every de-risk at a market top. Permanent per gen.
poc: NOT WRITTEN (YBase wires a mock, YMockMiFrens, not the ERC721Votes collection). Next step:
  deploy real MiFrensGenesis, setLiquidatorMinter(perp), wire as hook.collection(), farm N badges via
  open/liquidate loop, assert mifrens.getPastVotes(attacker, block-1) >= 10% getPastTotalSupply for
  < 1 ETH.  needs_fork: no
```

**T3C escalation (links to E2A):** capturing 100% of a volume-minted MiFrens supply is *also* capturing
100% of the ERC721Votes electorate for that collection — the supply raid and the governance takeover are
the same NFTs.

---

## (3) T3C redemption verdict — the number that decides Critical vs High

**Answer: redemption does NOT return more than the ~1,118 ETH acquisition cost at launch TVL → T3C
stays HIGH (fairness + governance capture), not a Critical redemption drain. DERIVED, and I did NOT
run the redemption loop — this is a reasoned bound, not a costed PoC.**

Reasoning from code:
- `CollectionLedger.redeem` pays `entitledTokens[gen]/outstanding` in the **live token**, debiting the
  pot so other holders' floor is unchanged (`CollectionLedger.sol:161-169`). Owning 100% of NFTs =
  redeeming the **entire `entitledTokens` pot**, then it must be **sold into the same pool**, craterng
  price as the sole large seller.
- `entitledTokens` is fed only by the **legacy-buyback slice** of fees (`PoolOps.doLegacyNote` /
  `credit`, `PoolOps.sol:1475-1477`), which is carved AFTER `guildBps=15%` goes to the genesis dividend
  (`CauldronHook.sol:1457`) and shares the remainder with the relaunch reserve. The attacker's measured
  **net** cost (547 ETH / 1,632) already nets out the token sellback. The floor pot in ETH-equivalent is
  therefore a *fraction of the fees*, which are themselves a fraction of gross spend → redemption ≪ cost.

**What supply capture buys beyond redemption:** (a) the full ERC721Votes electorate → E2A; (b) a
**perpetual monopoly on all future floor credits** funded by *other* traders' organic volume (the sole
holder collects 100% of `credit` inflows forever until death) — a slow dividend, small at single-digit-ETH
launch TVL, larger the more organic volume the generation attracts.

**Exact next step to close the number (hand-off ready):** run `PoolOps.sol:1610`
`ILedgerOps(ledger).redeem(gen, mintedNow)` 3,333× against the post-raid ledger, sum payouts, sell the
resulting tokens through the pool, and compare realised ETH to `netCostWei`. If realised > cost → Critical.

---

## (4) Refutations

- **Vote borrowing by flashloan is REFUTED by the snapshot.** `TreasuryGovernor` votes at
  `snapshot = block.number - 1` (`:455`) via `getPastVotes` — a sealed past block. NFTs flash-borrowed
  and returned in one tx carry zero past votes. (Renting real NFTs *over time* works but requires owning
  them across the snapshot; the cheap path is E2A, not borrowing.)
- **Sandwiching the liquidation sweep — REFUTED by chain property.** `eth_maxPriorityFeePerGas=0`, one
  Robinhood sequencer, Nitro FCFS: ordering is not purchasable. The searcher race for the R1A bounty is
  latency, not fees; it produces no gas war and cannot reorder the sweep.
- **`linkVolume` spam — REFUTED.** Registry-gated (`CauldronHook.sol:1707`), not permissionless.

## (5) Leads (HYPOTHESIS — next step each)

- **R2A → VERIFIED:** open a real losing long against the live engine (`PerpEngine.sol:1681-1687`,
  `plv += repay<principal`, `longOiEth -= principal`) with a vault exit queued, then claim — upgrades
  M2a from simulated-trigger to real. ~1 fork PoC.
- **SIB1-D ratchet liveness:** no `unlinkVolume` (`:1765`); the 10th distinct rotation destination bricks
  further rotation for the generation. Governance-reachable, not stranger-reachable — confirm whether a
  realistic multi-rotation life can hit 10 distinct quotes.
- **R1A depth-of-slack:** cost the projection slack to confirm it flips a truly-solvent (true-mark)
  position; if so, E2A + R1A compound (farm badges from your own pre-emptive kills at a profit).
