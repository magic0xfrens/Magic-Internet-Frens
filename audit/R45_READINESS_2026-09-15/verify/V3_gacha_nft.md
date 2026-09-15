# V3 — gacha / NFT findings (verifier 3, round 45)

Tree: /tmp/r45-blind-h3/contracts/solidity. All runs `FOUNDRY_PROFILE=cauldron`.
PoC hygiene: `grep -n "return;\|vm.skip" test/attacks/R3*.t.sol` → **no hits** in any of the four files;
no top-level `test_*` contains an early return. All four PoCs re-ran and all assertion lines executed
(logs precede the asserts in every test and the suites are green).

---

## R3A — uncapped gacha re-anchor = unlimited free re-roll — **CONFIRMED, HIGH** (VERIFIED)

Code, quoted from `contracts/solidity/cauldron/GachaLib.sol:79-86`:

```solidity
while (processed < maxCount && bi < end) {
    Batch storage b = batches[bi];
    if (block.number <= b.commitBlock) break; // seed not known yet
    bytes32 bh = blockhash(b.commitBlock);
    if (bh == 0) {
        b.commitBlock = uint48(block.number);
        break; // FIFO: resume from here on the next call
    }
```

No cap, no bookkeeping: `grep -n reanchored cauldron/GachaLib.sol` → **no matches**. The two sibling
reveal paths do cap it, in comments that name exactly this attack:

- `contracts/solidity/cauldron/CauldronCollection.sol:253` `mapping(uint256 => bool) public reanchored;`
  set once at `:301-302`.
- `contracts/solidity/cauldron/MiFrensGenesis.sol:518` same map, set once at `:560-561`, above the comment
  “One re-anchor per token, ever … waiting costs the draw rather than buying another”
  (`MiFrensGenesis.sol:555-558`).

Outcome is fully player-computable before resolution: `GachaLib.sol:94`
`uint256 roll = uint256(keccak256(abi.encodePacked(bh, player, bi, r))) % 10_000;` — every input
(`bh = blockhash(commitBlock)`, player, batch index, sub-index) is public the block after the commit.
Nothing unknowable is mixed in at resolve time. The PoC reproduces the prediction off-chain and only
submits `resolveTickets` on a predicted win.

Run (VERIFIED): `forge test --match-path 'test/attacks/R3A_*.t.sol' -vv`
```
[PASS] test_R3A_LosingCrystalCanBeReRolledForever()
  odds bps 900 / re-anchors used 20 / tries 21 / minted 1
```
Asserts executed: `assertGt(reanchors, 1)`, `assertTrue(won)`, `assertEq(col.totalMinted(), 1)`.
via_ir stale-slot trap does **not** apply: the PoC reads `vm.getBlockNumber()` everywhere inside the
loop (`R3A_GachaReRollGrind.t.sol:53, 65`), never bare `block.number`, and the re-anchor count is read
back from contract storage (`hook.batches(0).commitBlock` strictly increasing), not from a cached block
value — so the 20 re-anchors are on-chain state transitions, not a cheatcode artefact.

**Falsifying one-line change (run, VERIFIED):** replace `vm.roll(vm.getBlockNumber() + 257)` with
`vm.roll(vm.getBlockNumber() + 1)` (i.e. lose the seed-expiry window but keep everything else) →
`[FAIL: more than one free re-roll was available: 0 <= 1]`, `re-anchors used 0 / minted 0` over 300 tries.
The grind therefore depends on the 256-block `blockhash` expiry and the uncapped re-stamp, exactly as
claimed. File restored to original afterwards.

**Reachability chain** (fresh deploy, no roles): `commitCrystals` is reached from the public router
(`CauldronGachaRouter.sol:328, 362, 398`); `resolveTickets` is permissionless — interface at
`CauldronGachaRouter.sol:16`, called unguarded at `:329, :363, :399`, and callable directly on the hook
(the PoC calls `hook.resolveTickets(1)` from an EOA-like caller with no role). The attacker needs no
privilege at any step.

**Counter-argument I tried (fails to refute, only rate-limits):** `resolveTickets` is permissionless and
FIFO, and an unresolved head batch blocks everyone behind it — R3D's log (`batches ahead 60`,
`head cb 361` pinned while others wait) proves third parties are strongly incentivised to call it. Any
third-party call inside the 256-block window resolves the attacker's losing batch and kills that
re-roll. **But this is a free option, not a gamble:** if someone resolves in the window the attacker
merely takes the loss he already had; if nobody does (≈51 minutes of no `play`/`playChurn`/`openCrystals`
/keeper call), he gets a fresh, fair, free draw. Downside is zero, so EV is strictly positive and the
expected number of draws per crystal is ≥ 1 with no bound other than patience. He cannot *prevent*
third-party resolution, which is why I did not raise this to CRITICAL; on a quiet chain or off-peak
hours the window is trivially available. Economics: the win branch is gated only by
`minted < max` (`GachaLib.sol:96`), so the drain is bounded by `maxSupply`, not by any per-generation or
per-player re-roll cap — a 9%-odds crystal becomes an eventual guaranteed mint at ~18k gas and
256 blocks per attempt (~11 attempts expected, ~9 h wall-clock, uncontested).

Severity: **HIGH** — supply-cap-bounded, permissionless, zero-cost-downside subversion of the core
randomness the gacha economy prices on; the same class the codebase already treats as must-fix twice.

---

## R3B — churn credits every leg — **DOWNGRADED to LOW (economic-calibration / design note)** (VERIFIED run)

The credit really is accrued on both legs of every loop — the hunter's `:485` / `:506` are the `_settle`
and `SwapParams` lines; the actual accrual lines are
`contracts/solidity/cauldron/CauldronGachaRouter.sol:487` `playWei += inE;` (buy leg) and
`:513` `playWei += outE;` (sell leg), returned at `:530` and fed to
`hook.commitCrystals(msg.sender, want, _playInCurveUnits(playWei))` at `:398`.

Run (VERIFIED, fork, first attempt, no 429):
```
[PASS] test_R3B_NetEthCostPerCrystal()
  eth in 1e18 / recovered by selling the churn output 0.543794e18 / NET 0.456205e18 / credit 14.086e18
[PASS] test_R3B_ChurnCreditAmplification()  credit/principal x10000 140862 ; crystal-equivalents 704
[PASS] test_R3B_PlayChurnRunsAndStrandsNothing()  router eth left 0 / router token left 0
```
The 30.9× is net of the sell-back: `_sell(r.tokensOut)` at `R3B_ChurnFlows.t.sol:97` and
`net = ethCost - back` at `:98`, so the round-trip realised cost (fees + impact) really is 0.4562 ETH for
14.086 ETH of credit. Caveat: the asserted claims are only `assertGt(r.credit, 0)` (`:88`) and
`assertGt(r.credit, net)` (`:104`) — **the 30.9× multiple itself is logged, not asserted**, and it is a
function of this fork pool's depth and `loops = 10`, so treat the exact number as measurement, not invariant.

Why downgraded: `playChurn` is a first-class, documented entry point (`CauldronGachaRouter.sol:370`
NatSpec, `:412` dispatch, `:462 _churn`) and volume-for-credit means a wash trader pays the LP/protocol
fee as the designed toll — 3.2% of notional here. Nothing is stranded (`router eth left 0`). This is a
parameter-calibration question (is `volumePerNFT` priced against gross or net flow?), not a broken
invariant, so it is not a standalone bug. Counter-argument that survives against the *hunter's* framing:
it is only a multiplier on R3A's fuel — it makes crystals ~30× cheaper per unit of net ETH, which raises
R3A's throughput but does not change R3A's mechanism or its supply bound. If R3A were refuted this would
be an INFO design note; with R3A confirmed it stays LOW and is worth a calibration decision before deploy.

---

## R3D — one expired batch cleared per transaction — **CONFIRMED, LOW** (VERIFIED)

Same `break` as R3A, `GachaLib.sol:85`: `break; // FIFO: resume from here on the next call` inside the
`if (bh == 0)` arm at `:83-86` — one re-stamp per call, then the loop exits, so a wall of expired batches
costs one transaction each.

Run: `[PASS] test_R3D_ExpiredQueueCostsOneCallPerBatch()` — `batches ahead 60`,
`resolve calls the victim waited for 62`, `victim pending after 0`. Asserts executed:
`assertEq(victimPending, 0, "liveness holds")` and `assertGt(calls, n)` (`R3D_AgedQueueStall.t.sol:74,76`).
The PoC re-reads `vm.getBlockNumber()` inside the loop (`:55, :59, :61`), so the roll is not stale.
Liveness holds, cost is linear in stale batches and is paid by whoever wants the queue drained —
LOW is the right severity; no escalation.

**One-line change that would falsify it:** turn the `break` at `GachaLib.sol:85` into `continue` (with
a cursor advance) — the victim would drain in one call and `assertGt(calls, n)` would fail. Not run
(source change, not PoC change); DERIVED.

---

## R3C — refutation PoC: does it actually assert? — **YES, it is a real refutation**

`test/attacks/R3C_SupplyConservation.t.sol:84-88`:
```solidity
assertGt(r.committed, 0, "crystals were committed");
assertEq(r.resolved, r.committed, "each crystal resolved exactly once");
assertEq(r.pendingLeft, 0, "no player left with a stuck crystal");
assertEq(r.outstandingLeft, 0, "queue fully drained");
assertLe(r.minted, CAP, "supply cap never exceeded");
```
Run: `[PASS] … committed 12 / resolved 12 / minted 11 / pending left 0`. Supply conservation and
exactly-once resolution are genuinely asserted (not logged-only), and `assertGt(r.committed, 0)` guards
against a vacuous zero-crystal pass. Accepted as a valid refutation of double-mint / cap-breach:
R3A mints *within* the cap, it does not break conservation.

---

## Tally
4 claims examined: R3A CONFIRMED (HIGH), R3B DOWNGRADED (MEDIUM → LOW design note), R3D CONFIRMED (LOW),
R3C accepted as a sound refutation PoC. Discards (refuted / not verified): **0 refuted, 0 not-verified,
1 downgraded**.
