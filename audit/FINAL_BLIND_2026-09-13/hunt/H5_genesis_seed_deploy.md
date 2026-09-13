# H5 — Genesis / seed / deploy

Scope: `cauldron/MiFrensGenesis.sol`, `CauldronSeeder.sol`, `SeedLib.sol`, `ReserveLib.sol`,
`MigrationVesting.sol`, `LaunchSniper.sol`, `CauldronVault.sol`, `deploy/*.s.sol`.
Worked from a decontaminated copy at `/tmp/blind-final-h5/contracts/solidity` (line numbers 1:1).

## 1. Model from code

**Ignition.** `MiFrensGenesis.mint(qty)` (:262) takes exact `PRICE*qty`, caps on
`balanceOf(sender)+qty <= MAX_PER_WALLET`, records `paid[]`. `cancelPresale()` (:289) is
deployer-only, irreversible, opens `refund()` (:300, CEI, pays `paid[]`).
`igniteCauldron()` (:609) gates on `registry != 0`, `!finalized`, `!cancelled`,
`minted >= GENESIS_SUPPLY`, and `finalizer` if set; forwards the whole balance to
`registry.summon{value: bal}()`. `setFinalizer` (:423) is deployer-only, so a stuck
finalizer is recoverable. `LaunchSniper.launch` (:70) is `onlyOwner`, does
ignite → `gachaRouter.play(0,0,minOut,0,openMax)` (5-arg selector matches
`CauldronGachaRouter.sol:234`) → forwards token; `renounceOwnership` reverts (:120).

**Summon.** `CauldronRegistry.summon()` (:722) is `owner() || igniter`; one-shot;
deploys the token, sizes the genesis bonus + airdrop reserve, then `_seedGeneration`
(:1757). That dispatches PROGRESSIVE (`seeder != 0 && nextSeedWindow > 0`) to
`PoolOps.createAndSeedProgressive` (:312), else the atomic green candle.

**Seeder.** `startSeed` (:238) onlyRegistry, pulls ledger-A tokens via `transferFrom`,
takes ledger-A ETH as `msg.value`, places base + floor. `poke()` (:302) and
`pokeInSwap()` (:432, hook-only) advance the schedule; `fundPrime(to)` (:338) is
deployer/registry-owner; `withdrawAll`/`rescue` (:806/:838) are onlyRegistry.
`_syncRef` (:459) rate-limits the price reference to `MAX_TICK_DEV = 1000` ticks/block.

**Vault.** `receive()` (:118) counts only registry/minter deposits into
`accountedDeposits`; `close()` (:184) is registry-only and reports `min(bal, accounted)`
while sweeping everything. Both collection paths wire `hook.setVault(0)`
(`CauldronRegistry.sol:1237`, `:1261`), so `redeem` (:155) reverts `UnifiedFloorActive`.

**Deploy.** `DeployLaunchpad.s.sol` wires hook→registry, `setOpener/setTaxExempt` for
registry, gacha, seeder; `registry.setIgniter(presale)` (:569) then
`transferOwnership(timelock)` (:570). `DeployLaunchSniper.s.sol` asserts
`hook.isOpener(gacha)` before granting the sniper its exemption (:44).

## 2. Findings

```
id: K5b   severity: Critical   confidence: VERIFIED
subsystem: seed / PoolOps handoff
file:line: cauldron/PoolOps.sol:168, 395-396, 405, 409-410
    168:    uint256 internal constant SEED_BASE_WAD = 1e18;
    395:        uint256 baseTok = (activeTokens * SEED_BASE_WAD) / 1e18;
    396:        uint256 baseEth = (ethAmount * SEED_BASE_WAD) / 1e18;
    405:        if (activeTokens <= baseTok || ethAmount <= baseEth) return r;
    409:        IERC20(token).approve(sp.seeder, activeTokens - baseTok);
    410:        ISeeder(sp.seeder).startSeed{value: ethAmount - baseEth}(SeederConfig({
title: The entire progressive launch seeder is unreachable dead code, and any ETH sent
       to it through the documented `fundPrime` path is permanently locked.
precondition: None beyond the shipped configuration. `SEED_BASE_WAD == 1e18` makes both
       comparisons at :405 equalities, so the early return ALWAYS fires and :410 — the
       ONLY call site of `startSeed` in the tree (grep: `startSeed` appears in
       PoolOps.sol:410, ISeeder.sol:30, CauldronSeeder.sol:238 and tests only) — is
       never executed. `startSeed` is `onlyRegistry`, so nothing else can arm a campaign.
sequence:
  1. deployer: registry.setSeeder(seeder); registry.setSeedWindow(3600)  [reads as armed]
  2. anyone/igniter: registry.summon{value: 1 ether}()  -> succeeds, pool seeded ATOMICALLY
  3. observe: seeder.seeding() == false, seeder.gen() == 0, seeder.token() == address(0),
     seeder.ethTotal() == 0  (no campaign, no ladder, no anti-snipe stream)
  4. deployer: seeder.fundPrime{value: 1 ether}(treasury)   [documented funding step]
  5. anyone: seeder.poke()  -> primePending() == 0 (guarded on `!seeding`, :365), no-op
  6. emergencyAdmin: registry.armEmergency(); registry.rescueSeeder()  -> REVERTS.
     `CauldronSeeder.rescue` (:839) runs `IERC20(token).balanceOf(address(this))` with
     `token == address(0)` (never assigned, because startSeed never ran); the high-level
     call to an empty account reverts. `withdrawAll` is the only other exit and the
     registry calls it exclusively behind `if (ISeeder(_seeder).seeding())`, which is
     false forever.
attacker_cost: 0 (this is a self-inflicted configuration defect, not an attack)
damage: (a) every launch, forever, silently loses the advertised streamed anti-snipe
     ladder, the two-sided spot-straddling base, the in-swap auto-stream and the
     treasury prime buy — the whole CauldronSeeder contract, its hook exemptions and
     `setSeedWindow` are inert; (b) 100% of any ETH placed via `fundPrime`, or sent to
     the seeder's open `receive()` (:229), is permanently locked with no owner,
     emergency or timelock path out. Measured in the PoC: 1.0 ETH trapped.
poc: contracts/solidity/test/attacks/K5b_ProgressiveSeederUnreachable.t.sol   needs_fork: yes
```

Corroboration (independent, unchanged by me): the feature's own coverage is red.
`forge test --match-path test/ProgressiveSeed.t.sol` with the fork env exported:

```
[FAIL: seeder armed]                          test_Summon_Stream_Teardown_Relaunch_OnFork
[FAIL: floor at t0: 0 != 100000000000000000]  test_InSwap_AutoStreams_OnFork
[FAIL: no in-swap streaming ...: 0 != 1e17]   test_InSwap_ToggleOff_PermissionlessStillWorks_OnFork
[FAIL: streamed past the floor: 0 <= 1e17]    test_PartialStream_Death_FullRecovery_OnFork
[FAIL: fully streamed]                        test_Base_GivesSpotDepth_FromSummon_OnFork
[PASS]                                        test_WindowZero_IsAtomicGreenCandle_OnFork
5 failed, 1 passed
```
Every one of those tests opens with `vm.skip(!active)` and `active` is false unless
`FORK_RPC` is exported, so CI is green while the feature is dead. This is finding-grade
on its own: the only regression net over the seeder is disarmed by default.

```
id: K5c   severity: Medium   confidence: DERIVED
subsystem: seeder break-glass
file:line: cauldron/CauldronSeeder.sol:838-845
    838:    function rescue(address to) external onlyRegistry lock {
    839:        uint256 bal = IERC20(token).balanceOf(address(this));
    840:        if (bal > 0) IERC20(token).transfer(to, bal);
    841:        uint256 e = address(this).balance;
    842:        if (e > 0) { (bool ok,) = to.call{value: e}(""); require(ok, "eth"); }
title: The registry's only escape hatch for the seeder reverts whenever no campaign has
       ever run, because `token` is still address(0).
precondition: `startSeed` never executed for this seeder instance. Under K5b that is
       ALWAYS true; independently of K5b it is true for the whole window between
       deploying the seeder and the first progressive summon — exactly the window in
       which `fundPrime` is documented to be used ("funding before ignition is the
       normal path", :335).
sequence: 1. deployer funds/dusts the seeder; 2. emergencyAdmin arms + calls
       `registry.rescueSeeder()` (CauldronRegistry.sol:343); 3. revert, no data.
attacker_cost: 1 wei of ETH to the open `receive()` is enough to create the stuck balance
damage: ETH locked until a campaign is started AND torn down; under K5b, forever.
       Fix shape: read the balance defensively (`if (token != address(0))`).
poc: same file as K5b (assertion `registry.rescueSeeder() reverts -> ETH permanently locked`)
needs_fork: yes
```

```
id: K5d   severity: Medium   confidence: DERIVED
subsystem: seeder prime buy (BLOCKED TODAY BY K5b — becomes live the moment K5b is fixed)
file:line: cauldron/CauldronSeeder.sol:193, 302, 383-425
    193:    int24 internal constant MAX_TICK_DEV = 1000; // ~10.5% of price
    199:    uint256 internal constant PRIME_SLIP_BPS = 1000; // 10%
    386:        int24 lim = _refTick - MAX_TICK_DEV;
    421:        minOut = (minOut * (10_000 - PRIME_SLIP_BPS)) / 10_000;
title: `poke()` is permissionless and executes the treasury's market order, so a stranger
       picks the block and (within one MAX_TICK_DEV per block) the price it fills at.
precondition: a live progressive campaign with `primeBudget > primeSpent`, past the
       30-block anti-sniper window (`CauldronHook.sol:510 snipeWindowBlocks = 30`), after
       which a sandwicher pays only the 3% base fee each leg.
sequence: 1. attacker swaps ETH->token to push the tick DOWN by <= 1000 (so `_syncRef`
       at :472-475 ADOPTS the manipulated tick wholesale and returns in-band);
       2. attacker calls `seeder.poke()`; `_primeStep` limits at `_refTick - 1000` and
       accepts anything above `0.9 x` the value at that limit; 3. attacker unwinds.
attacker_cost: gas + 2x 3% pool/base fee on the manipulation notional
damage: worst-case fill = 1.0001^-2000 x 0.9 ~= 0.819 of fair, i.e. up to ~18% of each
       prime tranche, repeatable once per block for the whole launch window. The
       symmetric griefing case is that `require(got >= minOut, "prime slippage")` (:422)
       trips inside `poke`'s try/catch (:325), so the tranche is silently refused every
       time an attacker is watching.
poc: not written — the code path is unreachable on the current tree (K5b). See Leads.
needs_fork: yes
```

```
id: K5e   severity: Low   confidence: DERIVED
subsystem: genesis presale
file:line: cauldron/MiFrensGenesis.sol:268
    268:        if (balanceOf(msg.sender) + quantity > MAX_PER_WALLET) revert PerWalletCap();
title: The per-wallet cap measures current holdings, not lifetime mints, so one buyer
       loops mint -> transfer out -> mint to take the whole genesis tranche.
precondition: none; ERC721 transfers are open pre-ignition.
sequence: repeat { mint(MAX_PER_WALLET); transferFrom each id to a burner }
attacker_cost: gas only (they pay full PRICE for every NFT — no value extraction)
damage: distribution grief; a single entity can own the OG tranche and therefore the
       genesis dividend and the ERC721Votes weight the governor reads.
poc: not written (mechanism is a one-liner and unambiguous)   needs_fork: no
```

```
id: K5f   severity: Low   confidence: DERIVED
subsystem: genesis presale liveness
file:line: cauldron/MiFrensGenesis.sol:289-296, 621
    289:    function cancelPresale() external {
    291:        if (finalized) revert PresaleOver();
    ...
    621:        if (cancelled) revert AlreadyCancelled();
title: `cancelPresale` has no sell-out precondition and is irreversible, so the deployer
       EOA can permanently veto ignition of an already sold-out round.
precondition: deployer key (a plain EOA in `DeployLaunchpad.s.sol`; no timelock, and
       `MiFrensGenesis` has no renounce for `deployer`).
sequence: 1. round sells out; 2. deployer calls `cancelPresale()`; 3. `igniteCauldron`
       reverts forever; the collection can never launch.
attacker_cost: one transaction     damage: minters are made whole via `refund()`, so this
       is a liveness veto, not a theft. Deliberate design (the :615-624 comment argues
       the gate); logged as a residual key risk, not a defect.
poc: none   needs_fork: no
```

## 3. Refutations (attacked hard, held)

- **Vault donation inflating a dead collection's entitlement.** Attacked
  `CauldronVault.receive()` (:118) / `close()` (:184). The `accountedDeposits`
  high-water-mark plus the `min(bal, accounted)` clamp means a stranger's donation (or a
  `selfdestruct`/coinbase push) raises `floorPerNFT` but contributes zero to the `swept`
  figure `PoolOps.crystallizeCollection` (:1477) uses as the entitlement numerator. The
  surplus is emitted as `UnaccountedSweep` and still reaches the registry. Held.
- **Ignite-after-cancel.** `igniteCauldron` gates on `cancelled` (:621) before touching
  the balance, so the "cancelled AND sold out" state forwards nothing. Held.
- **LaunchSniper selector drift.** `IGachaPlay.play` (LaunchSniper.sol:22-28) is the
  5-arg quote-first form; `CauldronGachaRouter.sol:234` matches exactly. Held.
- **Liquidatoor badges diluting the vault.** `_mintLiquidator` (:376) uses
  `LIQUIDATOR_ID_BASE + ++liquidatorMinted` and never touches `minted`, and the
  constructor forbids `maxSupply >= LIQUIDATOR_ID_BASE` (:241), so `totalMinted()` — and
  therefore `outstanding()` — cannot be inflated by badges. Held.
- **MigrationVesting grant flooding.** `vestBatch` (:191) skips a holder at
  `MAX_BATCH_GRANTS = 32` (`continue`, not revert) and `_pullAndVest` (:213) hard-caps at
  `MAX_GRANTS = 64`, so a duster can neither exhaust the holder's own headroom nor make
  `_release` (:264) unrunnable, nor kill the keeper batch. Held.
- **Registry ownership vs ignition wiring order.** `DeployLaunchpad.s.sol:569-570` calls
  `setIgniter(presale)` BEFORE `transferOwnership(timelock)`, and `summon` (:731) accepts
  `owner() || igniter`, so the handoff does not strand ignition. Held.

## 4. Leads (HYPOTHESIS — exact next step)

1. **K5d prime-buy sandwich.** Next step: set `SEED_BASE_WAD` below 1e18 (or call
   `startSeed` directly from a registry-impersonating `vm.prank`) to make a campaign
   reachable, then run the sandwich harness: buy to push the tick ~900 down, `poke()`,
   unwind; compare `IERC20(token).balanceOf(primeTo)` against an unmolested poke. My
   first attempt at exactly this is what surfaced K5b (the treasury received 0 in BOTH
   arms because no campaign existed).
2. **`_advance` advances the schedule even when nothing was placed.**
   `CauldronSeeder.sol:495` sets `placedWad = target` unconditionally, while
   `_placeStep` (:558-590) sizes a band to zero liquidity whenever `_reserveRange`
   declines (returns `(0,0)` at :779) or the resolved band is on the wrong side of live
   spot. Each such poke burns a slice of the ladder that is never redeployed. Next step:
   drive `ranges.length` to `MAX_RANGES = 64` with the base as the only non-evictable
   entry and confirm the `(0,0)` branch is reachable, then measure the stranded fraction.
3. **`_reserveRange` eviction as a depth drain.** At the cap (:781-796) the band furthest
   from spot has its liquidity removed into the seeder's loose balance and its slot
   reassigned. A trader who repeatedly walks spot can convert placed book depth into idle
   seeder balance across a launch. Next step: 64-range fixture, alternate large swaps and
   pokes, and chart `pm.getLiquidity(poolId)` against `address(seeder).balance`.
4. **Seeder ETH provenance on fork.** In my first harness `address(seeder).balance` read
   0.17 ETH immediately after a summon in which no call to the seeder appears in the
   `-vvvv` trace. Most likely a pre-existing balance at the CREATE address on the Sepolia
   fork, but it is unexplained. Next step: log `address(seeder).balance` immediately
   after `new CauldronSeeder(...)` in `setUp`.

## Method notes
- All PoC assertions are top-level; the only `return;` in `K5b*.t.sol` is the fork guard
  inside `setUp`, and the test function itself opens with
  `require(active, "FORK_RPC/POOL_MANAGER/POSITION_MANAGER must be exported")` so a
  missing fork fails loudly rather than passing vacuously. Verified with `-vv`: the log
  lines interleaved with the assertions all printed.
- K5b uses no `vm.warp`, so the viaIR `block.timestamp`-sinking hazard does not apply.
- One `520` from the public Sepolia RPC during the run; re-ran and it passed.
