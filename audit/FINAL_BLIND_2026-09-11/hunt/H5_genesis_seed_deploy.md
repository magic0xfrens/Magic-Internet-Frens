# H5 — Genesis / seed / deploy (blind hunt, 2026-09-11)

Tree: `/tmp/blind-final-h5/contracts/solidity`. PoCs: `test/attacks/X5*.t.sol`.
All four tests pass with `-vv`; no bare `return;` in any `test_*` body (checked with
`grep -n "return;" test/attacks/X5*.t.sol` → no hits).

---

## 1. Model from code

**Genesis (`cauldron/MiFrensGenesis.sol`).** `mint(quantity)` (262) takes exact
`PRICE*quantity`, records `paid[msg.sender] += msg.value` (270) and mints ids
`1..GENESIS_SUPPLY`. Three flags govern the money: `finalized` (140), `cancelled`
(146), `paid` (147). `setRegistry` (249) is deployer-only and one-shot;
`setFinalizer` (423) and `cancelPresale` (289) are deployer-only. `refund()` (300)
requires `cancelled` and pays `paid[msg.sender]` CEI-correctly.
`igniteCauldron()` (575) requires registry set, `!finalized`, `minted >=
GENESIS_SUPPLY`, and `msg.sender == finalizer` when a finalizer is set — then
forwards `address(this).balance` into `registry.summon{value: bal}()` (585).
**It does not read `cancelled`.**

**Seed.** `CauldronRegistry._seedGeneration` (1703) arms `_seedBuyUnlocked`, and
takes the progressive branch when `seeder != 0 && nextSeedWindow > 0` (1722) →
`PoolOps.createAndSeedProgressive` (252, delegatecall ⇒ `address(this)` = registry).
The token is CREATE2-mined above `QUOTE_WATERMARK` in `deployTokenAbove` (682),
salt `keccak256(abi.encode(gen,i))` (702), deployer = registry; failure to mine
degrades to plain CREATE + native quote (718) rather than reverting. PoolKey is
`(quote, token, POOL_FEE, TICK_SPACING, hook)` (268-274). A non-native quote
degrades to the atomic seed and returns (296-310). Native: 15 % green-candle base,
then `IERC20.approve(seeder,…)` (343) + `ISeeder.startSeed{value:}` (344).
`CauldronSeeder.startSeed` (175) is `onlyRegistry`, asserts `msg.value ==
cfg.ethTotal` (179), pulls the token side (215) and places the floor slice.
`poke()` (231) is permissionless; band ticks are anchored to the live tick (368).
`withdrawAll` (565) / `rescue` (597) are `onlyRegistry`.

**Relaunch funding.** `PoolOps.seedFunding` (1000) closes the dying vault (1013),
then returns `(quoteUsed, amount, vaultSwept)` from one of three branches
(1054/1060/1064). `vaultSwept` is always **native wei**; `amount` is in
`quoteUsed`'s units. The registry consumes both at 948 and feeds them to
`PoolOps.crystallizeCollection` (1026-1028 → 1350).

**Deploy.** `DeployLaunchSniper.s.sol` wires `hook.setTaxExempt(sniper)` (37) then
`presale.setFinalizer(sniper)` (40). `DeployLaunchpad.s.sol` instead sets
`FINALIZER` to the deployer (524) and gives ignition its own role (`setIgniter`, 537).

---

## 2. Findings

```
id: X5a   severity: Critical   confidence: VERIFIED
subsystem: cauldron/MiFrensGenesis.sol:575-586
  function igniteCauldron() external nonReentrant returns (address token) {
      if (address(registry) == address(0)) revert RegistryNotSet();
      if (finalized) revert AlreadyFinalized();
      if (minted < GENESIS_SUPPLY) revert NotSoldOut();
      if (finalizer != address(0) && msg.sender != finalizer) revert NotAuthorized();
      finalized = true;
      uint256 bal = address(this).balance;
      (token, ) = registry.summon{value: bal}();
  (compare cancelPresale:289-294 `if (finalized) revert PresaleOver(); ... cancelled = true;`
   and refund:300-307 `if (!cancelled) revert NotCancelled(); ... msg.sender.call{value: amount}`)
title: A stranger ignites a CANCELLED sold-out presale and forwards the entire
       refund pot into the LP, permanently destroying every outstanding refund.
precondition: presale sold out AND the deployer pulled the documented safety valve
       `cancelPresale()`. `cancelPresale` has no sell-out precondition and
       `igniteCauldron` has no `cancelled` check, so the two states coexist.
       Permissionless when `finalizer == 0` (the contract's documented default,
       MiFrensGenesis.sol:422 "Zero = anyone"); otherwise the finalizer alone.
sequence:
  1. buyers mint the genesis tranche (1111 x PRICE lands in `paid`)
  2. deployer: cancelPresale()            — refunds open, minting stops
  3. anyone: igniteCauldron()             — passes every gate; `finalized = true`
     and `registry.summon{value: address(this).balance}()` empties the pot
  4. any un-refunded buyer: refund() now reverts RefundFailed forever; `paid`
     still shows the debt.
attacker_cost: 47,326 gas, 0 ETH (measured in the PoC)
damage: every un-refunded `paid[]` balance permanently unrecoverable. In the PoC
       1.11 ETH of 2.22 ETH; at mainnet config (1111 x 0.0222) up to ~24.7 ETH.
       Step 3 can be placed in the same block as step 2 with higher priority, so
       in practice NO buyer refunds. Permanent.
poc: test/attacks/X5a_GenesisCancelledIgnite.t.sol   needs_fork: no
```

Positive control in the same file (`test_Positive_CancelledPresaleRefundsInFull`)
shows the valve works when nobody ignites, so the attack is what breaks it.

```
id: X5b   severity: High   confidence: VERIFIED
subsystem: cauldron/LaunchSniper.sol:17 + :76 vs cauldron/CauldronGachaRouter.sol:233
  LaunchSniper.sol:17   function play(uint256 gnomeIn, uint256 minGnomeOut, uint256 minEthOut, uint256 openMax)
  LaunchSniper.sol:76   IGachaPlay(gachaRouter).play{value: msg.value}(0, minGnomeOut, 0, openMax);
  GachaRouter.sol:233   function play(uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax)
  GachaRouter.sol:552   receive() external payable {}        // and NO fallback()
title: LaunchSniper.launch() calls a four-argument `play` that does not exist on
       the router, so the whole atomic ignite+buy path reverts unconditionally —
       and when the sniper is the presale's finalizer, ignition is unreachable.
precondition: none beyond running the shipped script. `deploy/DeployLaunchSniper.s.sol:40`
       sets `presale.setFinalizer(address(sniper))`, and MiFrensGenesis.sol:581
       then rejects every other caller.
sequence:
  1. DeployLaunchSniper: setTaxExempt(sniper), setFinalizer(sniper)
  2. presale sells out
  3. owner: sniper.launch{value: fundingETH}(presale, registry, router, wallet, …)
     - :70 igniteCauldron() succeeds (state written)
     - :76 selector 0x1ca5b161 hits the router; the router implements 0x7fe7c4b6
       and has no fallback → dispatcher falls through → revert with empty
       returndata → the ENTIRE tx, including the ignition, reverts.
attacker_cost: n/a (self-inflicted); recovery needs `setFinalizer(0)` by the deployer
damage: the launch cannot be performed as deployed. Recovering it means opening
       ignition to everyone, which is exactly the front-run the contract exists to
       prevent (LaunchSniper.sol:32-36). Argument ORDER is wrong too: the call
       passes `minGnomeOut` where the 5-arg router reads `tokenIn`, so a mechanical
       arity fix alone would sell tokens the sniper does not hold.
poc: test/attacks/X5b_SniperSelectorDead.t.sol   needs_fork: no
```
The PoC deploys the **real** `CauldronGachaRouter` and shows the raw 4-arg call
fails with zero returndata, then runs the **real** `LaunchSniper.launch` against a
byte-faithful 5-arg router (reverts) and against a hypothetical 4-arg router
(succeeds) — the contrast isolates the selector as the cause.

```
id: X5c   severity: High   confidence: DERIVED (arithmetic VERIFIED, reachability read-only)
subsystem: cauldron/PoolOps.sol:1356 / :1013 / :1054 / :1064, cauldron/CauldronVault.sol:119,
           CauldronRegistry.sol:948 + :1026-1028
  CauldronVault.sol:119      swept = address(this).balance;                    // NATIVE wei
  PoolOps.sol:1013           try IVaultCloseOps(oldVault).close() returns (uint256 s) { vaultSwept = s; }
  PoolOps.sol:1054           if (p > 0) return (wantQuote, p, vaultSwept);     // p is in wantQuote units
  PoolOps.sol:1064           return (oldQuote, recovered + _pullAsset(hookAddr, oldQuote), vaultSwept);
  Registry.sol:948           (specQuote, totalETH, vaultSwept) = PoolOps.seedFunding(
  Registry.sol:1026-1028     PoolOps.crystallizeCollection(..., oldGen, vaultSwept, newActive, totalETH);
  PoolOps.sol:1356           entitled = FullMath.mulDiv(swept, activeBase, totalETH);
title: On a rebirth into a non-native quote, the dying collection's entitlement is
       computed as native-wei / quote-raw-units, so a dust donation to the dying
       vault's open `receive()` crystallizes the entire newborn active supply into
       the dead collection's ledger.
precondition: (a) the winning proposal's quote is a non-native allowlisted ERC20 —
       branches 1 and 3 of `seedFunding` both return a non-native `quoteUsed` while
       still returning a native `vaultSwept`; (b) the dying vault holds any ether.
       `CauldronVault.receive()` (72) is open and `PoolOps.sol:1008-1012` explicitly
       acknowledges "anyone may donate to its receive()". Under the shipped
       unified-floor config the vault's balance is otherwise 0, so the donation is
       the whole of the numerator.
sequence:
  1. relaunch is armed with a 6-decimal quote; the guild's funding is, say,
     20,000 USDC → `totalETH == 20_000e6 == 2e10` (raw units, not wei)
  2. attacker sends 2e10 wei (0.00000002 ETH) to `generationVault[oldGen]`
  3. anyone calls relaunch(): seedFunding closes the vault → `vaultSwept = 2e10`
  4. crystallizeCollection: entitled = mulDiv(2e10, 8e26, 2e10) = 8e26 = 100 % of
     the newborn active tranche
  5. Registry.sol:1039-1045: `legacy >= newActive` → ReserveShortfall, newActive
     collapses to the GEN1_ACTIVE_TOKENS floor; the dead collection's NFTs can now
     recycle against the live reserve for the whole entitlement.
attacker_cost: ~20 gwei of ETH + one transfer's gas (scales with the quote's
       decimals; an 18-dp quote costs the ETH/quote price ratio instead)
damage: the newborn launches on the emergency active floor instead of its sized
       tranche, and an entitlement worth up to the entire active supply is minted
       into the dead collection's ledger, drawable from the live migration reserve
       that backs every holder's 1:1 claim. Not self-limiting: unlike the native
       branch (:1060) the donation is NOT added to `totalETH`, so numerator and
       denominator do not move together.
poc: test/attacks/X5c_VaultSweptDenomination.t.sol   needs_fork: no
```
The PoC calls the real `PoolOps.crystallizeCollection` (delegatecall) with a
native control (1 ETH of 100 ETH → 1 % of supply, correct) and the non-native case
(2e10 wei against 2e10 raw USDC → 100 % of supply). The *arithmetic* is VERIFIED;
the end-to-end relaunch that supplies those two arguments is read, not run.

```
id: X5d   severity: Low   confidence: VERIFIED
subsystem: deployments/sepolia.json, deployments/sepolia-launch.json, deployments/sepolia-final.json
title: The three deployment manifests disagree with each other and cannot all be current.
precondition: none — inspection.
sequence: `MiFrensPresale` is 0x046E6D… (sepolia.json), 0x66ab05… (sepolia-launch.json)
  and 0xb1d4cb… (sepolia-final.json); `CauldronHook` / `CauldronRegistry` /
  `CauldronGovernor` / `CauldronFactory` differ across all three the same way.
  `sepolia-final.json` carries no `network`/`chainId`, omits `CauldronGachaRouter`
  and `MiFrensDividend`, and its `gen1.token` (0x8A6077…) is a different address
  from `sepolia-launch.json`'s `gen1_live.token` (0x0588CA…). The price also
  differs (1e16 vs 5e14 wei) with no epoch marker on the newest file.
attacker_cost: n/a    damage: operational — a script or frontend reading the wrong
  file wires a live protocol to dead addresses.
poc: none (inspection)   needs_fork: no
```

---

## 3. Refutations — attacked hard, held

1. **Squatting the next generation's PoolKey.** The token address *is* publicly
   predictable — `deployTokenAbove` uses CREATE2 with `salt = keccak256(abi.encode(gen,i))`
   (PoolOps.sol:702) over an initcode built from public `(name, symbol, gen,
   registry, totalSupply)` — despite the header comment at PoolOps.sol:596 claiming
   "PLAIN CREATE, NOT CREATE2". So the full PoolKey `(quote, predictedToken,
   POOL_FEE, TICK_SPACING, hook)` is computable before the relaunch tx exists, and
   a pre-`initialize` would make `PoolOps.sol:298/467` revert and roll back
   `governor.markConsumed`. **It is blocked one layer down:**
   `CauldronHook.getHookPermissions` sets `afterInitialize: true` (579-580) and
   `_afterInitialize` (621) opens with `require(sender == registry)` (630). Every
   pool whose key names this hook must pass that callback, so no third party can
   open it. The CREATE2 address itself is likewise unreachable: the deployer baked
   into it is the registry (delegatecalled library), and Solidity's library
   call-protection blocks a direct call to `deployTokenAbove`. Attacked via: the
   predictability chain, `SALT_TRIES` exhaustion (failure probability (15/16)^1024),
   and the `quote > QUOTE_WATERMARK` branch. No PoC written — the defence is a
   single unconditional `require` I could not route around. Confidence DERIVED.

2. **`rescueSeeder` leaving stale ledger-C counters that spend ledger-A ETH.**
   `CauldronSeeder.rescue` (597-602) really does write no state — `primeBudget`,
   `primeSpent`, `primeTo`, `seeding`, `ranges` all survive a full native drain —
   and `startSeed`'s per-campaign reset (201-213) does **not** clear the ledger-C
   trio. But `rescue` deliberately leaves `seeding = true` (see its own note at
   579-595), and `startSeed` reverts `AlreadySeeding` (176), so the next campaign
   cannot begin until `withdrawAll` (565) runs `_teardown`, which zeroes
   `primeBudget`/`primeSpent` (449-450). The cross-ledger spend is unreachable.
   Residual (Low, not filed as a finding): prime ETH funded *before* a relaunch is
   swept by that same teardown and reported to the registry as recovered ledger A.

3. **Flooding a `MigrationVesting` holder with grants to brick `_release`.**
   `_release` (221) loops every grant with no paging, so a long enough list would
   lock a holder out permanently. `vestBatch` (153) does let a stranger book grants
   for any address with an open allowance — but the amount is pinned to
   `min(balance, allowance)` (162) and `amt == 0` now `continue`s (163), so a repeat
   of the same holder in one array yields exactly one grant. Growing the list needs
   the attacker to *gift* the victim real dead-gen tokens each round, and
   `_pullAndVest` reverts `ZeroAmount` (188) when `claimByBurn`'s measured delta is
   zero, which is what dust produces. Economically self-defeating at the sizes that
   work. Downgraded to a lead (below) rather than a finding — I did not establish
   the minimum profitable dust.

---

## 4. Leads (HYPOTHESIS — exact next step)

- **L1 — sandwiching the permissionless `poke()`.** `poke()` (CauldronSeeder.sol:231)
  is ungated; `_placeStep` anchors both bands to the instantaneous tick
  (`poolManager.getSlot0` at :368, bands at :376-378) and `_primeStep` swaps with
  `sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1` (:292) — no slippage bound at
  all. An attacker can buy to push the tick down, `poke()` so the seeder parks its
  ETH bid band just above the manipulated tick, then dump into it. Next step: fork
  PoC on the real hook — measure whether the decaying launch surtax (CauldronHook,
  `poolInitBlock` anchor at CauldronHook.sol:650) still exceeds the extractable spread once the
  window is a day old, for a single `ethStep`.
- **L2 — `_reserveRange` fallback burning the range budget.** `MAX_RANGES = 64`
  (:115) and the comment at :111 says placement *reverts* at the cap while the code
  at :544/:551 silently reuses a tracked same-side band. Next step: drive 64+ pokes
  at moving ticks on a fork and assert whether the streamed liquidity still lands
  adjacent to spot or piles into a stale band.
- **L3 — minimum profitable grant flood.** Binary-search the smallest `amount` for
  which `PoolOps.migrateOne` returns non-zero against a realistic reserve position;
  if it is ≤ 1e9 raw units, refutation 3 becomes a Medium liveness finding.
- **L4 — `taperWeightWad` (SeedLib.sol:140) has no production caller.** Dead code
  in a shipped library; confirm with a repo-wide selector/caller sweep and decide
  whether the band sizing was *meant* to taper.
