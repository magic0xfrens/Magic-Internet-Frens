# H3 — Gacha & the NFT economy (round-45 blind readiness)

Tree: `/tmp/r45-blind-h3/contracts/solidity` (line numbers identical to the real tree).
All PoCs: `test/attacks/R3*.t.sol`. Suite result: **5 tests, 5 passed, 0 skipped** (2 of them fork-gated and *observed executing* against `FORK_RPC`; they assert `r.ran` so they FAIL, not skip, without a fork).

---

## 1. MODEL FROM CODE

**Credit.** `CauldronHook._afterSwap` accrues `nftCredit[creditEpoch][player] += absVolume * (isBuy ? buyWeightBps : sellWeightBps)/BPS` (CauldronHook.sol:912-918); weights default `15_000`/`5_000` (:430-431). Attribution is hookData's first word, else `tx.origin` (:898-901).

**Commit.** `commitCrystals(player,maxCount,playWei)` — gate `if (!isOpener[msg.sender]) revert NotOpener()` (:2371). Body `_commitCrystals` (:2385-2432): reserves `room = max - minted - outstandingOf[col]` (:2394-2398), prices each crystal at `nftPriceAt(startPos+n)` (`volumePerNFT=0.02 ether`, `nftPriceStep=0.00002 ether`, :382-383), debits credit, pushes one `GachaLib.Batch{player,collection,commitBlock,oddsBps,count,resolved}` (:2425). `oddsForPlay` = `playWei*maxOddsBps/oddsFullVolumeWei`, capped 9000 (:2306-2320). Also reached self-only from `nativeGachaStep` inside `afterSwap`, gas-gated `gg > 700_000` (:980-983).

**Resolve.** `resolveTickets(maxCount)` is **permissionless** (`public nonReentrant`, :2445) and delegates to the linked library `GachaLib.resolveTickets(batches, missStreak, pendingOf, outstandingOf, opened, gacha, pityThreshold, maxCount)` (:2464-2466).

**Router** `cauldron/CauldronGachaRouter.sol`: `play`/`playLiq`/`playChurn` (payable, `nonReentrant`), `openReady`, `unlockCallback` (`msg.sender == poolManager`, :410), owner-only `setOracle`/`rescueETH`/`rescueToken`, `renounceOwnership` disabled (:605). Quote = `registry.generationQuote(currentGeneration())` = `currency0` (:206-222). `_pullQuote` (:271-280) makes native and ERC20 mutually exclusive. `playChurn` → `_churn` (:461-528) runs ≤10 buys + 9 sells at the extreme tick, sums `playWei` from **both** legs, sweeps `tokBal` to the player and returns `ethBal` as the refund.

**Downstream.** Wins call `ICauldronCollection.mint` → `CauldronCollection.mint` (`msg.sender != minter` revert, :207-215) which mints UNREVEALED; rarity rolls in `_reveal` from `blockhash(mintBlockOf)`. `CollectionLedger` is `onlyRegistry` throughout (:83-86) and gives every minted NFT a floor claim `entitledTokens[gen]/outstanding` (:98-103).

---

## 2. FINDINGS

### R3A — the gacha win/lose roll is an UNLIMITED free re-roll

```
id: R3A   severity: High   confidence: VERIFIED
subsystem: gacha resolution
file:line: contracts/solidity/cauldron/GachaLib.sol:80-84
```
```solidity
            if (block.number <= b.commitBlock) break; // seed not known yet
            bytes32 bh = blockhash(b.commitBlock);
            if (bh == 0) {
                b.commitBlock = uint48(block.number);
                break; // FIFO: resume from here on the next call
            }
```

**title:** A player who does not like his crystal's (public, pre-computable) outcome simply declines to resolve it for 256 blocks; the next `resolveTickets` call re-stamps the batch to a fresh block and hands him a brand-new draw, with no cap — turning any odds into 100%.

**Why it is a bug and not the design:** the two sibling reveal paths cap exactly this at ONE re-anchor per token, for exactly this reason, in their own comments:
- `contracts/solidity/cauldron/CauldronCollection.sol:253` — `mapping(uint256 => bool) public reanchored;` … "an uncapped re-anchor is an unlimited free re-roll, because the holder can read the pending tier off-chain the moment block `mintBlockOf` is mined and is under no obligation to commit it."
- `contracts/solidity/cauldron/MiFrensGenesis.sol:559-563` — `if (bh == 0) { if (!reanchored[tokenId]) { reanchored[tokenId] = true; mintBlockOf[tokenId] = uint48(block.number); … } }`, with "Unlimited: measured at 400 re-rolls to a deterministic Ultra."

`GachaLib` has **no** `reanchored` equivalent (`grep -n reanchored cauldron/GachaLib.sol` → empty), and it governs the strictly more valuable draw: mint-or-nothing, not rarity. The hook's own docstring at CauldronHook.sol:2438 ("so it can't be foreseen, grinded, or re-rolled by reverting") is true only of *reverting*; withholding is not covered.

**precondition:** one 256-block window (~51 min at 12 s; ~8.5 min on a 2 s L2) in which nobody calls `resolveTickets` past the attacker's batch. Fully reachable: resolution is only driven by other players' router calls (`CauldronGachaRouter.sol:329, :363, :399`) and by the best-effort in-swap step, so any quiet hour is a re-roll. Each failed roll costs the attacker nothing but the wait; the crystal is never consumed.

**sequence:**
1. attacker (any address with credit) → `router.openReady(1)` or `play(...)`, one crystal, batch index `bi`.
2. at `commitBlock+1` attacker computes `uint256(keccak256(abi.encodePacked(blockhash(commitBlock), player, bi, 0))) % 10_000` off-chain — the exact expression at GachaLib.sol:93.
3. win → call `resolveTickets(1)` and take the NFT. lose → do nothing.
4. after 257 blocks → `resolveTickets(1)`: `bh == 0`, batch re-stamped, `processed == 0`, crystal intact. Go to 2.

**attacker_cost:** ~18 k gas per re-roll (measured: 579,948 gas for 21 rounds incl. setup), plus ~51 min of latency per re-roll. No principal at risk; the crystal is never spent on a loss.
**damage:** every crystal becomes a guaranteed NFT. With the churn amplifier measured in R3B (0.456 ETH net → 14.086 ETH of credit → ~551 crystals at default `volumePerNFT`), one grinder converts **0.456 ETH into the entire remaining NFT supply** of a generation, each NFT carrying a floor claim on the shared reserve (`CollectionLedger.floorPerNFT`, CollectionLedger.sol:98-103) and denying every honest player. The odds curve, the pity counter and `oddsFullVolumeWei` all stop meaning anything.

**poc:** `test/attacks/R3A_GachaReRollGrind.t.sol` **needs_fork: no**
Observed under `-vv`: `odds bps 900 / re-anchors used 20 / tries 21 / minted 1` — a 9 % ticket ground to a win through **20 uncapped re-rolls**; the invariant "at most one re-anchor" (`assertGt(reanchors, 1)`) is the failing-side assertion and it fires.

---

### R3B — churn buys 30.9× its own net cost in crystal credit

```
id: R3B   severity: Medium   confidence: VERIFIED
subsystem: CauldronGachaRouter.playChurn / hook credit accrual
file:line: contracts/solidity/cauldron/CauldronGachaRouter.sol:485, :506
```
```solidity
                playWei += inE;          // buy leg
...
                playWei += outE;         // sell leg
```
and CauldronHook.sol:912 `uint256 weighted = (absVolume * (isBuy ? buyWeightBps : sellWeightBps)) / BPS;`

**title:** `playChurn` credits the player on **all 19 legs** of a round trip, so the crystal credit a principal buys is ~31× the ETH it actually costs — a crystal prices at 0.00083 ETH against a `volumePerNFT` of 0.02 ETH.

**precondition:** none. Live generation past the 30-block anti-snipe window (`snipeWindowBlocks = 30`, CauldronHook.sol:514).

**sequence:** 1. attacker → `router.playChurn{value: 1 ether}(0, 10, 0, 0)`. 2. attacker → sell the creature tokens the churn left him.

**attacker_cost (measured on fork):** `eth in 1e18`, `eth recovered by selling the churn output 543,794,342,926,747,257`, **net 0.4562 ETH**.
**damage:** `credit bought 14,086,272,397,770,014,634` (14.086 ETH-equivalent) = 30.9× the net cost; ≈551 crystals after integrating the rising curve (`0.02 + k*0.00002`). This is documented as a feature ("volume amplifier", :375-377), so it is Medium on its own — but it is the fuel that makes R3A's guaranteed win a supply-wide drain, and it means `volumePerNFT` calibrated against a one-shot buy is ~31× too cheap for a churner.

**poc:** `test/attacks/R3B_ChurnFlows.t.sol` (`test_R3B_NetEthCostPerCrystal`, `test_R3B_ChurnCreditAmplification`) **needs_fork: yes** (assertions observed under `-vv`).

---

### R3D — an expired queue costs one transaction per batch, not one batch per transaction

```
id: R3D   severity: Low   confidence: VERIFIED
subsystem: gacha resolution
file:line: contracts/solidity/cauldron/GachaLib.sol:82-84 (the same `break`)
```

**title:** After any 256-block quiet window, each `resolveTickets` call can clear at most ONE batch (it re-stamps the next expired head and breaks), so N stale batches ahead of you impose N sequential blocks of head-of-line latency regardless of `maxCount`.

**precondition:** N batches queued and a 256-block window with no resolution. `maxCount = 30` buys you nothing.

**attacker_cost:** one `openReady(1)` transaction per batch (~700 batches per ETH of churned credit, per R3B).
**damage:** ~1 block of delay per batch, self-healing; cost ≈ damage, hence Low. **Liveness holds** — asserted: `assertEq(victimPending, 0, "the queue does eventually drain")` passes.

**poc:** `test/attacks/R3D_AgedQueueStall.t.sol` **needs_fork: no**
Observed: `batches ahead 60 / resolve calls the victim waited for 62 / victim pending after 0`, with per-call logs showing `processed 1` each call.

---

## 3. REFUTATIONS (attacked hard, held)

**Supply conservation and one-resolution-per-crystal — HELD.** `test/attacks/R3C_SupplyConservation.t.sol` (no fork, passes): 8 concurrent players, a cap-12 collection, all commits before any resolution. Result `committed 12 / resolved 12 / minted 11 / pending left 0`, and `outstandingTickets() == 0`. `_commitCrystals`'s `room = max > minted + reserved ? max - minted - reserved : 0` (CauldronHook.sol:2394-2398) makes over-reservation unreachable, and `b.resolved` is written **before** the mint (GachaLib.sol:105-107) so a crystal cannot roll twice. I could not commit a 13th crystal at any price, nor mint past the cap, nor leave a crystal stuck.

**`playChurn` value conservation — HELD.** `test_R3B_PlayChurnRunsAndStrandsNothing` (fork): after a 10-loop churn `router eth left 0`, `router token left 0`, `tokens kept 6,892,259,624,117,292,427,337,452`. The X4b `ethBal -= inE` / `tokBal -= inG` debits (:496, :509) do return partial fills; `_pullQuote` (:271-280) rejects the native/ERC20 mix-up; `_payQuote` (:552-560) reverts rather than silently losing a refund.

**Mint-revert wedging the queue — HELD (by reading + the R3C drain).** `try ICauldronCollection(col).mint(player) … catch` (GachaLib.sol:116-121) records a failed mint as a loss and does not charge the pity streak; the crystal and cursor are already advanced. `pendingOf`/`outstandingOf`/`outstandingCrystals` have no reset anywhere in the hook (`grep -n pendingOf CauldronHook.sol` → only :420, :2420, :2465), so no underflow-brick from an epoch bump.

**Calling `GachaLib` directly — HELD (harmless).** It is a linked library; a direct `CALL` executes against the *library's own* storage with attacker-chosen slot numbers and can only dirty the library contract, which nothing reads. No contract in the tree delegatecalls it but `CauldronHook` (`grep -n GachaLib` → CauldronHook.sol:28, 408, 413, 2464 only), and its `Batch`/`State` structs are the hook's *only* declarations of those types (CauldronHook.sol:408-413), so there is no layout divergence to attack.

---

## 4. LEADS (HYPOTHESIS)

- **L1 — free-ish NFTs vs the redemption floor.** `CollectionLedger.floorPerNFT = entitledTokens/outstanding` (CollectionLedger.sol:98-103). R3A+R3B price an NFT at ~0.00083 ETH of net cost. If `floorPerNFT` ever exceeds that, minting-to-redeem is a direct reserve drain. *Next step:* fork-boot with a funded reserve, run `registry`'s redemption path against a grinder-minted NFT and compare payout to net mint cost.
- **L2 — `tx.origin` credit on untagged swaps** (CauldronHook.sol:898-901) with `creditUntaggedSwaps` on: a contract that swaps on behalf of many users credits the bundler/relayer. *Next step:* drive a 4337-shaped swap and assert who `creditOf` grew for.
- **L3 — oracle in `_playInCurveUnits`** (CauldronGachaRouter.sol:136-145): a `usdPerRawUnit` that returns a large non-zero value inflates `playWei` and therefore odds, and it is `try`/`catch`-soft. *Next step:* wire a hostile oracle via `setOracle` (owner-gated) and measure the odds delta — role-gated, so Low unless the oracle itself is rotatable.
- **L4 — test-harness hazard (methodology, worth reporting upward).** Under `via_ir`, `block.number` read in a test loop is cached across `vm.roll`: my first R3D run rolled **backwards** (logged `blk 2` while the hook saw `304`) and produced a false brick. Existing suites use `vm.roll(block.number + 1)` (e.g. `test/final/F02_L2Semantics.t.sol:194, :219, :229`). *Next step:* audit those for loop-cached `block.number`; single-shot uses are fine, loops are not. All R3 PoCs use `vm.getBlockNumber()`.

---

### PoC hygiene
`grep -n "return;\|vm.skip" test/attacks/R3*.t.sol` → **empty**. The only early return is `if (!active) return r;` inside R3B's internal helper, which sets `r.ran = false`; the top-level tests assert `assertTrue(r.ran, "FORK_RPC required")`, so an unforked run fails loudly instead of passing vacuously.
Run: `FOUNDRY_PROFILE=cauldron forge test --match-path 'test/attacks/R3*.t.sol' -vv --skip 'lib/v4-periphery/lib/permit2/script/**'` → `5 passed; 0 failed; 0 skipped`.
