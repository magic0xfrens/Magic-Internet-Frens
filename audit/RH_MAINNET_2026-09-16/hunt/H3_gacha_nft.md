# H3 — Gacha & the NFT economy (blind red-team, 2026-09-16)

Working tree: `/tmp/rh-blind-h3` (decontaminated copy of `contracts/solidity`).
PoCs: `test/attacks/M3A_ChurnEconomics.t.sol`, `test/attacks/M3B_ExpiredCrystalForfeit.t.sol`,
copied to `audit/RH_MAINNET_2026-09-16/poc/h3/`. All runs on the Sepolia v4 fork.

---

## 1. Model from code

**Entrypoints / gates**

| entrypoint | file:line | gate |
|---|---|---|
| `CauldronGachaRouter.play` | `cauldron/CauldronGachaRouter.sol:229` | permissionless, `nonReentrant`, payable |
| `.playLiq` | `:250` | permissionless |
| `.playChurn` | `:379` | permissionless; `loops ∈ [1,10]` (`MAX_LOOPS`) |
| `.openReady` | `:347` | permissionless; spends only the caller's own credit |
| `.unlockCallback` | `:409` | `msg.sender == poolManager` |
| `.setOracle/.rescueETH/.rescueToken` | `:99/:579/:592` | `onlyOwner` (`renounceOwnership` disabled, `:605`) |
| `CauldronHook.commitCrystals` | `CauldronHook.sol:2402` | `isOpener[msg.sender]` |
| `CauldronHook.resolveTickets` | `CauldronHook.sol:2482` | **permissionless, no reward** |
| `CauldronHook.nativeGachaStep` | `CauldronHook.sol:2508` | `msg.sender == address(this)` |
| `CauldronHook.setCollection` | `CauldronHook.sol:2164` | `onlyRegistry` |
| `GachaLib.resolveTickets` | `cauldron/GachaLib.sol:104` | `external` lib, DELEGATECALLed from the hook only |
| `CollectionLedger.credit/redeem/buyback/crystallize` | `cauldron/CollectionLedger.sol:146/161/174/186` | `onlyRegistry` |
| `MiFrensGenesis.mint/refund/reveal/revealBatch` | `cauldron/MiFrensGenesis.sol:262/300/487/507` | exact price / cancelled / `ownerOf == msg.sender` |

**Asset flows.** Quote (native or ERC20) → router `_pullQuote` (`:271`) → `poolManager.swap` legs →
hook skims base + anti-snipe surtax in `afterSwap` → floor vault / genesis dividend / relaunch
reserve. Creature tokens and unspent quote return to the player (`_payQuote`, `:552`). No ETH ever
leaves the router except a refund or `rescue*`.

**Credit**: `afterSwap` accrues `nftCredit[creditEpoch][player] += absVolume * (buy?15000:5000)/10000`
(`CauldronHook.sol:949-955`). Credit is the only currency that buys crystals; it is burned in
`_commitCrystals` (`:2455`) at `nftPriceAt(startPos+n)`.

**Supply-conservation invariant (derived).** For a collection `col`:
`col.totalMinted() + Σ_players pendingOf ⊇ outstandingOf[col]`, and
`outstandingOf[col] = Σ over unresolved batches of (count - resolved)`. `_commitCrystals` reserves
`room = maxSupply - minted - outstandingOf[col]` (`:2429-2435`) so resolution can never exceed
`maxSupply`. `GachaLib.resolveTickets` decrements `pendingOf`, `st.outstandingCrystals`,
`outstandingOf[col]` exactly once per crystal (`GachaLib.sol:148-150`) before the mint, and the mint
is `try/catch` — so a reverting mint burns the reservation without minting. **The invariant is
one-directional: crystals can be destroyed without a mint, never the reverse.** That is where the
finding lives.

**Cross-subsystem.** Volume feeds `cumulativeVolume` (`:899`, death detection) and
`lifetimeVolumeOf`/`totalLifetimeVolume` (`:956-961`). `setCollection` bumps `creditEpoch`
(`:2172`), stranding old credit. `CollectionLedger` floors are quoted per outstanding NFT.

---

## 1b. `playChurn` REACHABILITY — the thing that had never run on any chain

**VERIFIED REACHABLE.** `playChurn` executes end-to-end from a realistic state (live generation,
native quote, past the anti-snipe window) in all three PoCs below. It is *not* a dead feature.
`hookData = abi.encode(c.player)` (32 bytes, `CauldronGachaRouter.sol:462`) satisfies the hook's
`hookData.length >= 32` tag test (`CauldronHook.sol:934`), so the player — not the router — is
credited; confirmed by `lifetimeVolumeOf(attacker)` rising in M3A and M3C. The 19-leg shape is real:
`loops = 10` performs 10 buys and 9 sells (`CauldronGachaRouter.sol:474-521`, sell gated on
`i + 1 < loops`).

---

## 2. Findings

```
id: T3C   severity: High   confidence: VERIFIED
subsystem: gacha supply capture (playChurn + commitCrystals)
file:line: CauldronGachaRouter.sol:379  function playChurn(uint256 quoteIn, uint256 loops, uint256 minTokenOut, uint256 openMax)
           CauldronHook.sol:2402        function commitCrystals(address player, uint256 maxCount, uint256 playWei)
           CauldronHook.sol:2443        while (n < maxCount && n < MAX_MINTS_PER_CALL) {
title: One address with borrowed capital captures the entire NFT collection at ~30 NFTs per
       ~100 ms block, before any other participant can react — there is no per-wallet cap, no
       per-block cap and no cooldown anywhere in the commit path.
precondition: a live generation past the ~30-block anti-snipe window. That is the normal state
       of every generation for its entire life.
sequence (one round = one tx = one ~100 ms block, repeated):
  1. attacker: router.playChurn{value: 20 ether}(0, 10, 0, 30)
       -> 19 legs credit ~14.7x the input in volume -> credit buys 30 crystals at 9,000 bps
  2. attacker: hook.resolveTickets(2000) in the next block  -> ~27 of 30 mint (90% + pity)
  3. repeat.
capital: 20 ETH PER ROUND, returned within the same transaction net of fees. FLASHLOANABLE yes —
       the v4 PoolManager holds 21,218 ETH borrowable fee-free inside one `unlock()`. "Nobody
       can afford it" is not available as a defence, and is not even needed: the per-round
       float is 20 ETH.
attacker_cost: MEASURED 547.4 ETH net for 1,632 NFTs = 0.3354 ETH/NFT, on a 50-ETH-seeded pool.
       Extrapolating the same rate to the full 3,333 supply: ~123 rounds, ~1,118 ETH net,
       ~12.3 seconds of wall-clock time. Most of that "cost" is swap fee + slippage, which the
       hook routes to the floor vault / genesis dividend / relaunch reserve — i.e. it is
       recycled into the very floor the attacker now owns 100% of.
damage: total capture of the generation's NFT supply and therefore of its entire
       `CollectionLedger` floor claim (`cauldron/CollectionLedger.sol:161` pays
       `entitledTokens/outstanding` per NFT, and the attacker is every holder). The
       "mint by volume, anyone can play" fair-launch promise is defeated outright.
       No other participant gets a single NFT.
poc: audit/RH_MAINNET_2026-09-16/poc/h3/M3C_WholeSupplyCost.t.sol   needs_fork: yes
```

Measured (`-vv`, assertions executed, test PASSES):

```
maxSupply      3333
minted         1632      <- 49% of the collection
rounds         60        <- MY loop cap, not the protocol's; it never resisted
grossEthOut    1200.000 ETH   (20 ETH per round, per-tx float only)
sellBackEth     652.553 ETH   (creature tokens dumped back)
NET COST        547.447 ETH
cost per NFT      0.3354 ETH
attacker vol   17,634 ETH-equivalent of volume credited to ONE address
cumVol delta   17,298 ETH
```

The assertion `assertEq(r.rounds, 60, "raid ended early - protocol resisted")` is the load-bearing
one: the raid was stopped by the test's own bound, not by any protocol limit. Confirmed by grep —
`cooldown`, `lastPlay`, `perWallet`, `perBlock`, `MAX_PER`, `dailyCap`, `mintCap` return **zero
hits** across `CauldronHook.sol`, `cauldron/CauldronGachaRouter.sol` and
`cauldron/CauldronCollection.sol`. The only throttle is `MAX_MINTS_PER_CALL = 30`
(`CauldronGachaRouter.sol:69`), which bounds a *call*, not an *actor*, and blocks are ~100 ms.

**What the credited volume unlocks (the mainnet question, answered):** I grepped every reader.
`lifetimeVolumeOf` and `totalLifetimeVolume` (`CauldronHook.sol:430-431`) are **written at
`:956-961` and read by nothing on-chain** — no fee share, no dividend, no governance weight, no
floor. They are indexer/UI figures only. So the credited volume buys exactly two things:
(a) `nftCredit` → crystals → NFTs, which is T3C above; and (b) `cumulativeVolume`
(`CauldronHook.sol:899`), which the death oracle reads — see lead L-2. **The good news is that the
volume number itself is not a claim on any pot.** The damage is the supply capture, not a volume
dividend.

```
id: T3B   severity: High   confidence: VERIFIED
subsystem: gacha resolution
file:line: cauldron/GachaLib.sol:124-135
    if (bh == 0) {
        if (!_reanchored(bi)) {
            _markReanchored(bi);
            b.commitBlock = uint48(block.number);
            break; // FIFO: resume from here on the next call
        }
        //  SECOND EXPIRY: the honest re-draw was offered and declined.
        expired = true;
    }
  and cauldron/GachaLib.sol:147
    bool win = (forced || (!expired && roll < odds)) && minted < max;
title: A paid crystal that nobody resolves inside two 256-block windows is destroyed —
       a 9,000 bps (90%) draw becomes a guaranteed loss — and on a ~100 ms chain each
       window is only ~25.6 seconds.
precondition: `resolveTickets` (CauldronHook.sol:2482) is permissionless and pays NO keeper
       reward; its only organic callers are other players' `play`/`playChurn`/`openReady`
       (CauldronGachaRouter.sol:326, 368, 393) and the in-swap native path. Any period of
       ~51 s with no gacha activity forfeits every pending crystal at the FIFO head.
       Reachable with zero attacker involvement; the default during quiet hours.
sequence:
  1. victim: router.playChurn{value: 5 ether}(0, 10, 0, 5)  -> 5 crystals at oddsBps 9000,
     batch pushed with commitBlock = now; the in-call resolveTickets no-ops because
     `block.number <= b.commitBlock` (GachaLib.sol:110).
  2. 300 blocks pass (~30 s at 100 ms) with no resolve call.
  3. anyone: hook.resolveTickets(30)  -> processed = 0 (re-anchor + break).
  4. another 300 blocks pass.
  5. anyone: hook.resolveTickets(30)  -> processed = 5, won = 0. pendingOf = 0.
capital: none. The victim's own 5 ETH of churn (already spent on fees) is the loss.
       No borrowed capital needed; no attacker needed at all.
attacker_cost: 0 (passive). To FORCE it on a busy chain an attacker must keep >128k crystals
       ahead of the victim in the FIFO for 512 blocks (256 blk x 30M gas / ~60k gas per mint) —
       each crystal costs real swap fees, so forcing it is expensive; the passive path is free.
damage: the full expected value of every forfeited draw. Measured: 5 crystals x 9,000 bps
       = 4.5 expected NFTs destroyed per victim play. At a 1,000-NFT collection with a
       0.05 ETH floor that is ~0.22 ETH per affected play, unbounded in aggregate.
       The fees that bought the draw were already routed to the floor vault — value left
       the player with no matching value returned.
poc: audit/RH_MAINNET_2026-09-16/poc/h3/M3B_ExpiredCrystalForfeit.t.sol   needs_fork: yes
```

Measured output (`-vv`, both assertion blocks executed):

```
CTL  opened      5      <- positive control: resolved at commit+1
CTL  processed   5
CTL  minted      5      <- 5 NFTs actually minted
ATK  opened      5
ATK  oddsBps     9000
ATK  proc#1      0      <- window 1: re-anchor only
ATK  proc#2      5
ATK  won#2       0      <- every 90% draw lost
ATK  pendingEnd  0      <- crystals consumed
```

The positive control (crystal resolved promptly ⇒ it really mints) and the attack are in the
same test, so the failure is not a harness artefact.

Note on the sibling path: `MiFrensGenesis._reveal` (`cauldron/MiFrensGenesis.sol:559-570`) has the
same one-re-anchor shape but is `ownerOf`-gated, so the holder controls the timing. There the cap
does not remove the free re-roll, it caps it at **best-of-2** — the holder peeks at
`blockhash(mintBlockOf[id])` at `mb+1`, reveals only a good tier, otherwise waits out the window
(25.6 s at 100 ms blocks) and draws again. The contract's own comment at `:546` prices best-of-2 at
`P(≥Rare) 21% → ~37.6%`. Logged as a Low below rather than a High because it is documented as
accepted behaviour, but the published rarity table is wrong by that margin on this chain.

```
id: T3A   severity: Low (economics, not a bug)   confidence: VERIFIED
subsystem: playChurn volume amplification
file:line: cauldron/CauldronGachaRouter.sol:474-522 (the 10-buy / 9-sell loop),
           CauldronHook.sol:949  uint256 weighted = (absVolume * (isBuy ? buyWeightBps : sellWeightBps)) / BPS;
title: MEASURED churn multiplier is 14.69x input (10.1x a plain buy) — NOT the 30.9x the
       brief quoted. I could not reproduce 30.9x at any pool depth I tested; treat the
       30.9x/0.4562 ETH/19-leg figure in the brief as unverified.
capital: 1 ETH used; FLASHLOANABLE yes (PoolManager holds 21,218 ETH).
poc: audit/RH_MAINNET_2026-09-16/poc/h3/M3A_ChurnEconomics.t.sol   needs_fork: yes
```

Measured on a 50-ETH-seeded pool, past the anti-snipe window:

```
CHURN 1 ETH / 10 loops:  volume credit 14.694 ETH (14.69x), cumulativeVolume +14.41 ETH,
                         tokens kept 6.892e24
PLAIN 1 ETH:             volume credit  1.455 ETH ( 1.455x), cumulativeVolume  +0.97 ETH,
                         tokens kept 1.157e25
```

Churn ends holding **40.4 % fewer creature tokens** than the plain buy for the same 1 ETH — that
difference (~0.40 ETH of value) is the fee it burned across 19 legs. Credit per ETH of fee burned:
churn ≈ 36.7, plain ≈ 48.5. **Churn is worse per unit of real cost, so it is not an extraction
path on the credit axis.** Two caveats I could not close in budget:
- the multiplier is pool-depth dependent (thin pool ⇒ more slippage ⇒ lower multiplier); a
  mainnet-depth pool will land closer to the theoretical 19.5x;
- `cumulativeVolume` rose 14.41 ETH for ~0.40 ETH of real cost — a **36x-efficient way to fake the
  volume figure the death oracle reads** (`CauldronHook.sol:899`). Handed to the death-detection
  hunter as lead L-2; I did not own that surface.

`playChurn` **executes successfully end-to-end on the fork** (M3A and M3B both call it): it is not
a dead feature. `hookData = abi.encode(c.player)` (32 bytes, `:462`) is accepted by the hook's
`hookData.length >= 32` tag test (`CauldronHook.sol:934`) and credits the player, not the router —
verified by `lifetimeVolumeOf(attacker)` rising.

---

## 3. Refutations (attacked hard, held)

- **Supply conservation across `_commitCrystals`/`resolveTickets`.** `room = maxSupply - minted -
  outstandingOf[col]` (`CauldronHook.sol:2429-2435`) reserves against *both* minted and pending, and
  the resolve loop re-reads `minted`/`max` per batch and re-checks `minted < max` per roll
  (`GachaLib.sol:147`). I could not construct a mint past the cap. M3A/M3B both end with
  `totalMinted()` ≤ opened. VERIFIED by execution, not reading.
- **Double resolution of one ticket.** `b.resolved = uint16(r)` is written *before* the mint
  (`GachaLib.sol:161`) and the cursor is monotonic (`:191`); the only external call is
  `ICauldronCollection.mint`, which is plain `_mint` with no `onERC721Received`
  (`cauldron/CauldronCollection.sol:207-210`), and both callers are `nonReentrant`. No re-entry
  surface found. DERIVED.
- **`CollectionLedger.redeem` double-claim / floor dilution.** `payout = entitledTokens/n;
  entitledTokens -= payout; retired += 1` (`:167-170`) leaves the per-NFT floor *exactly* invariant
  ( (E - E/n)/(n-1) = E/n ) with the rounding dust staying in the pot. Held. DERIVED.
- **`_curvePos` underflow** (`CauldronHook.sol:2319`, `minted + outstandingOf - mintBaseline`):
  `mintBaseline` is a snapshot of the same collection's `totalMinted()` taken in `setCollection`
  (`:2169`) and `totalMinted` is monotonic, so `minted ≥ mintBaseline` always. Held. DERIVED.
- **Fee-based sandwich of `playChurn`'s 19 unlimited-tick legs.** Per chain fact (a) ordering is not
  purchasable on the target chain, so the classic sandwich is refuted there; `minTokenOut` at
  `:524` is the remaining defence and it is checked on the kept balance. Not raised.

---

## 4. Leads (HYPOTHESIS — exact next step each)

- **L-1 (Medium?): forced forfeiture by FIFO flooding.** T3B is passive. Next step: measure the real
  gas cost of 128,000 pending crystals (256 blocks x 30M gas / ~60k per mint) and whether an
  attacker with flashloaned capital can buy that much credit for less than the aggregate floor value
  of the crystals they destroy. If yes, T3B becomes Critical (permissionless destruction of other
  players' paid draws).
- **L-2 (for the death-detection hunter): `cumulativeVolume` inflation.** `playChurn` moves the death
  oracle 36x more per ETH of real cost than a plain buy. Next step: run `_recordVolume` /
  `deathChecker` against a churn-only volume stream and see whether a dead brew can be kept alive,
  or a live one starved, inside the 24 h window.
- **L-3 (Low): `MAX_PER_WALLET` on `MiFrensGenesis.mint` (`:268`) tests `balanceOf(msg.sender)`,** so
  transferring out between mints lifts the cap. Next step: decide whether the cap is meant to be
  sybil-resistant at all; if not, drop it.
- **L-5 (feeds T3C): is the supply raid net-PROFITABLE, not merely cheap?** T3C proves capture at
  0.3354 ETH/NFT and total-floor ownership; I did not close the loop on whether redeeming that
  floor returns more than 1,118 ETH. Next step: run `PoolOps.sol:1610`
  (`ILedgerOps(ledger).redeem(gen, mintedNow)`) 3,333 times against the post-raid ledger and
  compare the payout to `netCostWei`. If payout > cost, T3C is Critical, not High.
- **L-4: reorg (chain fact (d), ~9,650 blocks ≈ 16 min).** Both the gacha seed
  (`blockhash(b.commitBlock)`) and the genesis reveal seed are rewritten by a reorg far deeper than
  the 256-block horizon. Next step: confirm the indexer/frontend does not key any irreversible
  off-chain action on a `TicketWon`/`Revealed` event younger than the finality lag.
