# NEIGHBOURHOOD RE-HUNT — blind pass, 2026-09-13

## 1. What I attacked, and the shape

| File / function | Shape hunted |
|---|---|
| `PerpVault._syncTokYield`, `_settleTok`, `pendingTokYield` | the new write-off **epoch**: spurious detection, double-claim across the boundary, over-forfeit of post-write-off yield |
| `PerpVault.deposit` (`QueueInsolvent`) / `claimPendingEth` | whether the documented permissionless release actually releases |
| `PerpSwapLib.bandLimit/_band/closeLimit`, `PerpEngine._settle` band, `_writeOffTok`, `_buyUpTo` | direction of the band per side, already-past-the-band, tighter-of-two, remainder rebooking |
| `PerpEngine.syncGeneration` (`markSource = address(0)` moved out of the quote branch) | what a relaunch now leaves un-armed, and who can re-arm |
| `PerpMarkSource.weightedTick` revert-when-unarmed | swap-path callers of a now-reverting view |
| `CauldronHook._recordVolume` / `getVolume24h` (absolute hours) | hour-0 boundary, >24h gaps, lazy-clear write-vs-read symmetry |
| `CauldronHook.linkVolume` cap-after-dedup, `getHolderTaxRate` clamp | ratchet, re-link |
| `CauldronGovernor._benchRecord`, `TreasuryGovernor._benchRecord/allowance/consume` | eviction ordering, ties, envelope deactivation counter |
| `RoyaltyRouter.sweep` (permissionless), `CauldronSeeder.refundPrime` (new), `withdrawAll`/`rescue` token-leg guard | wrong destination, wrong time, list growth via `adopt` |
| `CauldronGachaRouter.playChurn` new `minTokenOut` arg | caller-side ABI mismatch |

## 2. Findings

```
id: Ja   severity: High   confidence: VERIFIED
subsystem: PerpVault write-off epoch
file:line: contracts/solidity/cauldron/PerpVault.sol:421-453
  uint256 cut = pulled + lost;       // the cum level the write-off ate up to
  if (lost != 0 && cut > last && cut < cum) {
      accEthPerTokShare += FullMath.mulDiv(cut - last, ACC, sh);
      epochAcc = accEthPerTokShare;  // the forfeit line
      accEthPerTokShare += FullMath.mulDiv(cum - cut, ACC, sh);
  } else {
      accEthPerTokShare += FullMath.mulDiv(cum - last, ACC, sh);
      if (lost != 0) epochAcc = accEthPerTokShare;
  }
title: Short-side yield credited AFTER a rotation write-off is swept below the
       forfeit line and permanently stranded in the engine's pot.
precondition: A quote rotation zeroes `tokYieldEth` (PerpEngine.sol:1359 region)
  while the vault was UP TO DATE (`lastTokYieldCum == tokYieldCumulative`), which is
  the normal state — any deposit/withdraw/claim syncs it. Then any short-side fee
  lands before the next vault interaction.
mechanism: `lost = cum - (pot + pulled)` implies `cut = pulled + lost = cum - pot`.
  With the vault synced at rotation time, `pot` is exactly the NEW post-rotation
  accrual, so `cut == last` EXACTLY — `cut > last` is false, the split fold can
  never be taken, and the else branch folds the whole new delta into
  `accEthPerTokShare` and only THEN stamps `epochAcc` at that level. Every entitlement
  "at or below epochAcc" is forfeited, so the new, fully-backed yield is forfeited
  with the written-off yield. `pendingTokYield` (:569-609) reproduces the same branch,
  so the UI agrees with the loss instead of exposing it.
sequence: 1) staker depositToken; 2) engine credits 10 ETH tok-yield; 3) any vault
  call syncs (last = cum = 10); 4) rotation write-off zeroes the pot; 5) engine
  credits 5 ETH of NEW yield; 6) staker claimTokYield → `_syncTokYield` sets
  epochAcc above the 5 ETH, `_settleTok` zeroes owed, `paid == 0` → revert ZeroAmount.
attacker_cost: none required — this fires on the honest path. A griefer can force it
  by routing one swap's short-side fee in the window after a rotation (gas only).
damage: the entire post-rotation, pre-sync token-side yield is forfeited from every
  staker and stranded in `tokYieldEth` with no path out (measured 5 ETH in the PoC;
  in production it is whatever short-side fees accrue in that window).
poc: contracts/solidity/test/attacks/Ja_VaultEpochOverForfeit.t.sol   needs_fork: no
observed: pot backing 5000000000000000000; pendingTokYield 0; claimTokYield reverts.
```

```
id: Jb   severity: Medium   confidence: VERIFIED
subsystem: PerpVault deposit guard
file:line: contracts/solidity/cauldron/PerpVault.sol:274
  if (pendingEth > engine.totalEth()) revert QueueInsolvent();
  ...and its stated release, contracts/solidity/cauldron/PerpVault.sol:380-393
  uint256 capped = _haircut(owed, engine.totalEth(), pendingEth);
  if (capped < owed) { pendingEth -= (owed - capped); pendingEthOf[msg.sender] = capped; owed = capped; }
  ...
  if (paid == 0) revert ZeroAmount();
title: In the exact state the new guard fires in, the release path it names reverts
       and rolls its own write-down back, so the ETH side can neither be
       recapitalised nor drained until a trader voluntarily closes.
precondition: `pendingEth > engine.totalEth()` (a bad-debt settlement after exits
  queued) AND `engine.freeEth() == 0` (PLV fully deployed in open positions). Both are
  ordinary stressed states and co-occur naturally — the queue only outruns backing
  after a loss, and a loss is what leaves the book fully utilised.
mechanism: The guard's own comment claims `claimPendingEth` "banks the haircut
  permissionlessly ... which drains pendingEth and reopens the side". It banks a zero
  only on the `owed == 0` branch (:390, the patched one). When `freeEth == 0` the
  later `paid == 0` revert at :393 unwinds the `pendingEth -= (owed - capped)` written
  two lines earlier, so the recognised write-down never persists and the guard stays
  latched.
sequence: 1) lp deposit 10 ETH; 2) traders open, freeEth → 0; 3) lp withdrawEth →
  10 ETH queued; 4) 1 ETH of bad debt, totalEth = 9; 5) newLp deposit → QueueInsolvent;
  6) lp claimPendingEth → ZeroAmount, pendingEth still 10.
attacker_cost: zero (no attacker needed); a vandal wanting to hold the state can queue
  from a contract with a reverting `receive()`, whose claim can never be haircut at all
  — that variant makes the latch permanent and is HYPOTHESIS, see Leads.
damage: deposits shut precisely when the vault needs capital; queued LPs cannot bank
  their haircut. Bounded by a trader closing a position (which they may never do).
poc: contracts/solidity/test/attacks/Jb_QueueInsolventDepositLock.t.sol   needs_fork: no
observed: pendingEth 10e18, totalEth 9e18, freeEth 0, both calls revert.
```

```
id: Jc   severity: High   confidence: DERIVED
subsystem: PerpEngine mark pointer / volume-link interlock
file:line: contracts/solidity/cauldron/PerpEngine.sol:1454
  quote = newQuote;
  //  The mark pointer never survives a sync — see the note in the branch above.
  markSource = address(0);
  ...and contracts/solidity/cauldron/PerpEngine.sol:874
  return openCount != 0 && markSource == address(0);
  ...consumed at contracts/solidity/CauldronHook.sol:1635
  if (perpEngine != address(0) && IPerpOpenCount(perpEngine).blocksVolumeLink()) {
title: Moving the mark-source drop OUT of the `newQuote != quote` branch makes every
       GENERATION change disarm it, which re-arms the dust-position treasury-rotation
       hostage at each relaunch until the owner manually re-runs `setRouting`.
precondition: One relaunch. `syncGeneration` is invoked from
  `CauldronRegistry.sol:1163` (`try IPerpSync(eng).syncGeneration() {} catch {}`) on
  every generation change, so this is the normal path, not an edge case.
mechanism: `markSource` is written in exactly two places — `setRouting`
  (`PerpEngine.sol:2495-2511`, `onlyOwner`) and this unconditional clear. No relaunch
  path re-arms it; the only arming site in the tree is
  `deploy/DeployPerp.s.sol:228 engine.setRouting(dividend, treasury, treasury, markSource, quoteOracle)`.
  Once cleared, `blocksVolumeLink()` is true whenever a single position is open, and
  the hook refuses every `linkVolume` — i.e. every rotation slice's destination link.
  Secondarily, the new T3d death band falls back to the single-pool TWAP the mark
  source existed to replace.
sequence: 1) relaunch → syncGeneration clears markSource; 2) anyone opens one dust
  position (the engine's own comment measures the minimum at 0.000744 ETH);
  3) every treasury rotation slice reverts at CauldronHook.sol:1635 for as long as
  that position stays open.
attacker_cost: ~0.0007 ETH of collateral plus gas, and it is refundable on close.
damage: treasury rotation is held hostage for the generation; each denied envelope
  costs the guild a fresh vote plus the cooldown. Recoverable only by the owner
  (timelock+multisig) re-calling `setRouting` after every relaunch — an off-chain
  step the permissionless-relaunch promise does not have.
poc: none written (needs the full fork launch harness; the two mechanical facts —
  the unconditional clear and the owner-only re-arm — are both quoted above).
needs_fork: yes
```

```
id: Jd   severity: Low   confidence: DERIVED
subsystem: TreasuryGovernor envelope lifecycle
file:line: contracts/solidity/cauldron/TreasuryGovernor.sol:817 and :913
  uint16 spent = e.movedPrimaryBps;
  ...
  if (e.movedPrimaryBps >= cap) e.active = false;
title: Deactivation now keys on the PRIMARY counter for every envelope, so a mandate
       whose slices all come from secondary legs never deactivates and keeps
       `propose` locked out until expiry.
precondition: An envelope spent entirely through `rotateSliceFrom(fromLeg != 0)`.
  `consume` still bounds those on `movedBps` (:895-897), so the budget is exhausted
  (`bps > cap - e.movedBps` reverts) while `movedPrimaryBps` is still 0.
mechanism: This is the R-05 lock-out the `e.movedBps >= cap` half used to cover for
  partial envelopes; the T2a change removed that half unconditionally.
attacker_cost: gas for the secondary slices (permissionless per the same comment).
damage: `propose` (:322) refuses new treasury proposals for the rest of the envelope's
  expiry window (30-day mainnet default) with a budget that can no longer be spent.
poc: none   needs_fork: no
```

## 3. Refutations — changed shapes I attacked that held

- **`CauldronHook._recordVolume` / `getVolume24h` absolute-hour rewrite** (`CauldronHook.sol:1554-1600`). Worked the algebra end to end: `steps = now/3600 - lastTs/3600`, `lastBucket = (lastTs/3600) % 24`, so `(lastBucket + steps) % 24 == _getCurrentBucket()` always — the write-side clear of offsets `1..steps` is exactly the expired set and includes the current bucket. On the read side `base = lastBucket + 1 + gap` with `24 - gap` iterations covers offsets `gap+1 .. 24`, i.e. every bucket written inside the window and nothing else; offset 24 ≡ `lastBucket` (correctly included), offset `gap` ≡ the current bucket (correctly excluded, since it holds day-old data no write has cleared). Hour-0/`% 24` wrap, first-ever write (`lastTs == 0` → `gap` enormous → `return 0` / full clear), and same-hour repeats all behave. No unsigned underflow is reachable (`lastTs <= block.timestamp`). Held.
- **The death band's direction and tighter-of-two logic** (`PerpSwapLib.sol:406-451`, `PerpEngine.sol:1602`). `bandLimit(mark, sp, !p.isLong, quote < syncedToken)`: a long SELLS → `buy = false` → ceiling `mark * 1.054093`; with quote as currency0, selling token raises `sqrtPrice`, so a ceiling is the correct binding side, and `_quoteAt`'s `(Q96/sp)²` makes 1/√0.9 the right factor. A short BUYS → floor `mark * 0.953463`, and `closeLimit` takes `max(band, spendLimit)` which is the tighter of two FLOORS. Already-past-the-band returns `sp±1` (fill ~nothing) rather than reverting, so v4 does not reject the limit and the terminal write-off still clears the book. The `quoteIsCurrency0 == false` case returns 0 (no band), preserving the pre-band behaviour rather than putting a limit on the wrong side. Held.
- **`PerpMarkSource.weightedTick` now reverting when unarmed** (`PerpMarkSource.sol:174`). Its only in-tree consumer is `PerpEngine._currentTick` (`:696-714`), which uses a raw assembly `staticcall` and `and(ok, eq(returndatasize(), 0x20))`, so a revert is absorbed and falls through to `poolManager.getSlot0`. No swap path takes a revert from it. Held.
- **`RoyaltyRouter.sweep` as an unbounded-list / redirect vector** (`RoyaltyRouter.sol:120-150`). Destinations are both immutable; `sweep` takes no destination. The `try IAdoptable(to).adopt(asset)` cannot grow the dividend's basket: `MiFrensDividend.adopt` (`:323-330`) requires `msg.sender == funder || treasury` for an unknown asset and the router is neither, so the call reverts into the catch and only already-known assets are credited. Held.
- **`CauldronGovernor` / `TreasuryGovernor` bench eviction ordering** (`:687-730` / `:531-575`). The lexicographic comparator `weakProtected != prot ? !prot : v < weakVotes` initialises with `weakProtected = true, weakVotes = max`, so an empty or dead slot (unprotected, v = 0) is always chosen first and a protected slot is only displaced when all eight are protected AND `votes > weakVotes` strictly. I could not construct a junk eviction of a settled mandate without out-voting it eight times, which is the legitimate mechanism. Held.
- **`CauldronGachaRouter.playChurn` signature change** (`:379`). Grepped every caller: only `src/config/cauldron.ts:455` (ABI) and `src/hooks/useCauldronSwap.ts:308`, both updated in the same change; no on-chain caller exists. Held.

## 4. Leads (HYPOTHESIS — exact next step)

1. **Jb permanent variant.** A queued exiter that is a contract with a reverting
   `receive()` can never be haircut: `_haircut` writes down at
   `PerpVault.sol:381`, then `engine.withdrawPlvTo` → `_sendEth` reverts and unwinds
   it. If that address's nominal alone exceeds `engine.totalEth()`, the
   `QueueInsolvent` guard is latched forever with no privileged override.
   Next step: extend `Jb` with a `RevertingLp` contract, queue from it, and assert
   `pendingEth` never falls below its nominal across any sequence of other claims.
2. **`CauldronSeeder.refundPrime` door that never shuts** (`CauldronSeeder.sol:379`).
   The gate is `if (seeding || gen != 0) revert`, and `gen` is written only by
   `startSeed`, which `PoolOps.sol:402-405` never calls while `SEED_BASE_WAD == 1e18`.
   On the shipped configuration the door is therefore open for the machine's whole
   life, letting the deployer EOA sweep `address(this).balance` at any time.
   Next step: enumerate every path that can leave ETH on the seeder in that
   configuration (registry `withdrawAll`/`_teardown` returns, stray `receive()`), and
   price what is sweepable.
3. **`_writeOffTok(id, unsold, true)` off the death path** (`PerpEngine.sol:1624`). It
   runs for MODE_NORMAL and MODE_LIQUIDATION too, where `band == 0`; the only way
   `unsold > 0` there is v4 hitting the tick extreme on an exact-in sell. Next step:
   fork-test a long close into a near-empty pool and check whether `plvToken += unsold`
   silently confiscates a trader's token instead of reverting Slippage.
4. **`MAX_SIBLINGS` one-way ratchet**, self-declared OPEN at `CauldronHook.sol:1666-1673`
   with no `unlinkVolume`. Next step: count distinct rotation destinations reachable in
   one generation and price ten of them.
