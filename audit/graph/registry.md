# Cluster `registry` — function graph

Re-extracted 2026-09-12 from the repository working tree; line numbers are those of that tree.

Source tree: `contracts/solidity`

| file | lines | nodes |
|---|---|---|
| `CauldronRegistry.sol` | 1797 | 68 |
| `CauldronToken.sol` | 62 | 3 |
| `cauldron/ICauldron.sol` | 56 | 8 |
| `cauldron/IPolicies.sol` | 75 | 4 |
| `cauldron/ILiquidatorMintable.sol` | 49 | 3 |
| `cauldron/IDeathChecker.sol` | 32 | 1 |

`CauldronRegistry` inherits `CauldronBase` (`cauldron/CauldronBase.sol`, cluster `pool`), which holds every storage
slot and the `_redeemBlocked` / `floorPerFren` views. `PoolOps` (cluster `pool`) is a linked library reached by
DELEGATECALL, and `RedemptionExt` (cluster `rotation`) is the delegatecall facet; both execute on this registry's
storage and custody.

---

## A. Value inventory

Every storage field that holds or counts value, its denomination, and every line that raises or lowers it.
Lines in `RedemptionExt.sol` are included because that code runs on these same slots.

| field (slot) | denomination | increased at | decreased / reset at |
|---|---|---|---|
| `genesisReserveOutstanding` (12) | units of the LIVE generation's ERC20 | set at `CauldronRegistry.sol:724` (ignition sizing); `+= genesisPending` at `CauldronRegistry.sol:1019`; `+= added` at `RedemptionExt.sol:182` (buy / donate / re-enchant) | `-= F` at `RedemptionExt.sol:91` on each OG recycle, guarded by a `>=` test on the same line |
| `genesisPending` (17) | units of the DYING generation's ERC20, carried as a number | `+= og` at `CauldronRegistry.sol:1507` (relaunch flush); `+= og` at `RedemptionExt.sol:158` (keeper materialize) | zeroed at `CauldronRegistry.sol:1020` immediately after the fold |
| `genesisSharePerFren` (28) | ERC20 units per fren, fixed at ignition | `CauldronRegistry.sol:723` | never |
| `genesisShares` (27) | count of frens (the divisor of the floor) | `CauldronRegistry.sol:634` | never; owner-settable only while `summoned == false` (`CauldronRegistry.sol:629`) |
| `airdropReserve` (34) | units of generation one's ERC20 | `CauldronRegistry.sol:645` | never zeroed; it is read and paid out once at `CauldronRegistry.sol:733` and the counter keeps its value afterwards |
| `primeBuyEth` (35) | native wei | `+= msg.value` at `CauldronRegistry.sol:661` | `= 0` at `CauldronRegistry.sol:668` (funder reclaim) and `= 0` at `CauldronRegistry.sol:752` (spent on the ignition buy) |
| `legProceeds` (53) | raw units of the booked foreign quote | `+= q` at `RedemptionExt.sol:831` | `= 0` at `RedemptionExt.sol:889` before the send at `RedemptionExt.sol:890` |
| `generationPositionId` (8) | a PositionManager token id — the handle to the ACTIVE LP | `CauldronRegistry.sol:1750` | never cleared, including after the position is fully removed at `CauldronRegistry.sol:1570` |
| `generationReservePositionId` (9) | a PositionManager token id — the handle to the migration/genesis reserve | `CauldronRegistry.sol:1751` | never cleared, including after removal at `CauldronRegistry.sol:1575` |
| `generationLegs` (52) | array of rotated LP handles per generation | pushed at `RedemptionExt.sol:698` | popped per leg at `RedemptionExt.sol:835`, only on a successful unwind |
| `quoteScale` (51) | wei of ether-equivalent per RAW unit of the quote, scaled 1e18 | `CauldronRegistry.sol:176` (native identity) and `CauldronRegistry.sol:323` | never zeroed; a de-listing at `CauldronRegistry.sol:321` leaves the stale scale behind |
| `emergencyReadyAt` (37) | unix timestamp (the arming, not value) | `CauldronRegistry.sol:421` | `CauldronRegistry.sol:409` (consumed) and `CauldronRegistry.sol:440` (guardian veto) |
| `enchantFeeMultBps` (29) / `royaltyBps` (21) / `genesisBonusBps` (26) | basis points | `CauldronRegistry.sol:464`, `CauldronRegistry.sol:604`, `CauldronRegistry.sol:633` | same lines (overwrite) |
| `nftMaxSupply` (20) / `nextSeedWindow` (46) / `minLifetime` (39) / `nextReserveCeilingOffset` (0) | NFT count / seconds / seconds / tick offset | `CauldronRegistry.sol:596`, `:352`, `:585`, `:199` | same lines (overwrite) |

Value that is held but never counted: the registry's raw ether balance (paid in at `CauldronRegistry.sol:572`,
swept wholesale at `CauldronRegistry.sol:484` and `CauldronRegistry.sol:566`) and its ERC20 balances of every
generation token.

## B. Balance vs counter

- `primeBuyEth` is a counter, and the refund at `CauldronRegistry.sol:669` pays the COUNTER out of the registry's
  pooled ether, which also holds hook reserve pulls, vault sweeps and auto-migrate fees. The two only agree while
  no other source has been consumed; `CauldronRegistry.sol:752` spends the counter through
  `PoolOps.primeBuy` without any balance check.
- `genesisReserveOutstanding` counts an entitlement; the tokens backing it sit in the out-of-range reserve LP
  addressed by `generationReservePositionId` (`CauldronRegistry.sol:1751`). The two are reconciled only at the
  point of payment, inside the library, which is why a short reserve must revert the whole redemption
  (`RedemptionExt.sol:91` debits first, the pull happens after). At a rebirth the counter is carried forward
  (`CauldronRegistry.sol:1019`) while the backing is re-created from `newReserve` (`CauldronRegistry.sol:1075`);
  when they cannot be made to agree the shortfall is emitted rather than enforced, at
  `CauldronRegistry.sol:1035` and `CauldronRegistry.sol:1060`.
- `airdropReserve` is never zeroed after the single payout at `CauldronRegistry.sol:733`, so the counter
  permanently over-states what remains reserved.
- `legProceeds` is backed by the registry's own balance of that asset; the sweep at `RedemptionExt.sol:884`
  trusts the counter and sends from the balance.
- `collectionLedger.totalEntitled()` (`CauldronRegistry.sol:1048`) is an external counter that sizes the new
  reserve; nothing checks it against anything this contract holds.

## C. Authority map

| gate | held by | rotatable | renounce / dead-end |
|---|---|---|---|
| `onlyOwner` (17 setters, e.g. `CauldronRegistry.sol:184`, `:308`, `:589`) | `Ownable._owner`, slot 0 | yes, via `transferOwnership` | `renounceOwnership` is overridden to revert at `CauldronBase.sol:464`, so ownership cannot be dropped |
| `onlyEmergency` (`CauldronRegistry.sol:364`) | `emergencyAdmin`, **immutable** (`CauldronRegistry.sol:171`) | no | cannot be rotated, renounced or replaced for the life of the deployment |
| `timelocked` (`CauldronRegistry.sol:373`) | nobody; it consumes an arming | n/a | requires a prior `armEmergency` even when `emergencyDelay == 0` (`CauldronRegistry.sol:407`) |
| guardian veto (`CauldronRegistry.sol:439`) | `guardian` | set by EITHER the emergency admin or the owner (`CauldronRegistry.sol:431`), not one-shot | defaults to the zero address, so no veto exists until it is wired |
| igniter (`CauldronRegistry.sol:695`) | `igniter`, owner-set (`CauldronRegistry.sol:415`) | yes | self-extinguishing: `summoned` (`CauldronRegistry.sol:696`) makes it a one-time right |
| prime funder (`CauldronRegistry.sol:660`, `:666`) | `primeFunder` | only while `summoned == false` (`CauldronRegistry.sol:650`) | frozen after ignition; a zero funder makes both entries unreachable |
| PoolManager callback (`CauldronRegistry.sol:1765`) | `poolManager` + the armed flag at `CauldronRegistry.sol:1766` | `poolManager` is written once, in the constructor (`CauldronRegistry.sol:167`) | no setter exists |
| facet `onlyOwner` (`RedemptionExt.sol:260`, `:882`) | this registry's own owner slot, through delegatecall | with ownership | same dead-end as above |
| rotation envelope (`RedemptionExt.sol:317`) | the MiFren treasury vote, read at `RedemptionExt.sol:303` | wiring replaceable at `RedemptionExt.sol:262` | execution is permissionless within the approved envelope |
| collection-NFT ownership (`PoolOps.sol:1404`) / treasury custody (`PoolOps.sol:1453`) | the token holder / this registry | n/a | enforced in the library, not here |
| `onlyRegistry` on the token (`CauldronToken.sol:50`) | the immutable `registry` (`CauldronToken.sol:45`) | no | burn authority is permanent and needs no allowance |

## D. External calls, with value and CEI ordering

| call site | callee | moves value | ordering |
|---|---|---|---|
| `CauldronRegistry.sol:329` | `hook.setSeeder` | no | after the storage write at `:328` |
| `CauldronRegistry.sol:342` | `ISeeder.rescue` | pulls the seeder's loose funds into this registry | after the timelock is consumed at `:409` |
| `CauldronRegistry.sol:360` | `floorPerFren` (base, internal) | no | pure read |
| `CauldronRegistry.sol:470` → `:472` → `:474` | `_removeLiquidity`, `IERC20.transfer`, `emergencyAdmin.call` | tokens then the whole ether amount | effects (`:409`) precede both sends; `nonReentrant` wraps it |
| `CauldronRegistry.sol:484`, `:487` | `emergencyAdmin.call`, arbitrary `IERC20` | whole native balance, whole token balance | the ERC20 branch calls a caller-named address twice (`balanceOf`, `transfer`) with no return check |
| `CauldronRegistry.sol:542`, `:543` | `IERC721.transferFrom` on the PositionManager | ownership of both live positions | before the loose-balance sends |
| `CauldronRegistry.sol:555` | `ISeeder.withdrawAll` | recovers the streamed book | before the sends at `:562` and `:566` |
| `CauldronRegistry.sol:566` | `to.call` where `to` is the admin-set successor | whole native balance | last, after every effect |
| `CauldronRegistry.sol:669` | `msg.sender.call` | the prime-buy counter | counter zeroed at `:668` first |
| `CauldronRegistry.sol:733` | `IERC20.transfer` | the airdrop reserve | before the pool is created |
| `CauldronRegistry.sol:756` | `PoolOps.primeBuy` | spends native on a market buy | flag armed at `:755`, cleared at `:757` |
| `CauldronRegistry.sol:797`, `:840`, `:1007`, `:1098`, `:1114`, `:1144`, `:1185`, `:1189`, `:1212`, `:1213`, `:1754` | `CauldronHook` | no | `:840` and `:1144` are gas-capped against `RELAUNCH_TAIL_RESERVE`; `:840` is try/catch, `:1144` is not |
| `CauldronRegistry.sol:805`, `:867`, `:995` | `ICauldronGovernor` | no | `markConsumed` is deliberately placed after the last revert, at `:994` |
| `CauldronRegistry.sol:822` | `_removeLiquidity` → `PoolOps.removeAll`, `ISeeder.withdrawAll`, facet `recoverLegs` | recovers both sides of up to four sources | the leg delegatecall's failure is swallowed at `:1614` |
| `CauldronRegistry.sol:829` | `CauldronToken.burn` | destroys the recovered dead-pool supply | after the recovery |
| `CauldronRegistry.sol:966` | `PoolOps.seedFunding` | pulls both hook reserves and closes the dying vault | placed AFTER token mining so the pull matches the surviving quote |
| `CauldronRegistry.sol:1044`, `:1048` | `PoolOps.crystallizeCollection`, `ICollectionLedger.totalEntitled` | no | before the reserve is sized |
| `CauldronRegistry.sol:1083` | `_seedGeneration` | pays the whole funded amount into the newborn pool | last value move of the rebirth |
| `CauldronRegistry.sol:1169`, `:1207` | `ICauldronFactory` | no | not wrapped; a broken factory reverts the rebirth |
| `CauldronRegistry.sol:1262`, `RedemptionExt.sol:669`, `CauldronRegistry.sol:1358` | `PoolOps.migrateOne` / `migrateUpTo` (now called from the facet) / `autoMigrateBatch` | burns old supply, releases live supply from the reserve | the burn and the release are one library call |
| `CauldronRegistry.sol:1311` | `IERC721.balanceOf` on `mifrens` | no | before the flag write at `:1314` |
| `CauldronRegistry.sol:1462` | `delegatecall` to `redemptionExt` | whatever the facet moves, from this registry's custody | forwards all gas; return and revert data bubbled verbatim |
| `CauldronRegistry.sol:1524`, `:1541` | `PoolOps.recycleCollection` / `buyCollection` | pays the floor out of the reserve / pulls 2x the floor in | ledger debit precedes the reserve pull, with a rollback check at `PoolOps.sol:1437` |
| `CauldronRegistry.sol:1613` | `delegatecall` to `RedemptionExt.recoverLegs` | unwinds every rotated leg | failure deliberately ignored at `:1614` |
| `CauldronRegistry.sol:1647`, `:1687`, `:1729`, `:1767` | `PoolOps` deploy / seed / buy | mints supply to this registry, seeds the pool, executes the in-callback buy | all delegatecalls, so custody stays here |

## E. Loops

`CauldronRegistry.sol` contains **no** `for` or `while` loop of its own. Every loop the registry can reach runs
in code delegatecalled onto its storage, plus one it calls out to:

| loop | bound | who can grow the bound |
|---|---|---|
| `PoolOps.sol:1302` (auto-migrate batch) | `holders.length`, supplied by the caller at `CauldronRegistry.sol:1359` | the keeper, per call; unbounded except by block gas |
| `RedemptionExt.sol:821` (recover legs, reached from `CauldronRegistry.sol:1613`) | `legs.length` for the generation | anyone who can execute an approved rotation, since each new quote pushes a leg at `RedemptionExt.sol:698` |
| `RedemptionExt.sol:695` (upsert a leg) | the same `legs.length` | same |
| `PoolOps.sol:701` (address mining, reached from `CauldronRegistry.sol:1647`) | the fixed `SALT_TRIES` constant | nobody; exhausting it downgrades the quote rather than reverting |
| `CauldronRegistry.sol:840` (`hook.resolveTickets`) | the literal `RELAUNCH_TICKETS` = 50 (`CauldronRegistry.sol:144`) | nobody; capped and try/catch'd |
| `CauldronRegistry.sol:1144` (`hook.forceClosePerps`) | the perp book, bounded inside the engine | traders opening positions; gas-capped but NOT try/catch'd |
| `CauldronHook.sol:1661` (sibling volume sum, reached from `CauldronRegistry.sol:797`) | the pool's sibling list | whoever wires volume siblings on the hook |

## F. Denomination and units

- The rebirth's funding figure is named `totalETH` (`CauldronRegistry.sol:956`) but is denominated in
  `specQuote`'s own raw units, as the comment at `CauldronRegistry.sol:955` states.
- The amount recovered from the dying LP is measured in the PRIMARY pair's `currency0`, passed explicitly at
  `CauldronRegistry.sol:969` rather than taken from `generationQuote[oldGen]`, because a completed rotation
  flips that mapping while the primary position stays in the launch pair
  (`RedemptionExt.sol:818` matches on the same primary currency for exactly this reason).
- A rotated leg whose asset differs from that primary currency is booked into `legProceeds`
  (`RedemptionExt.sol:831`) instead of being added to the sum, keeping one denomination per sum.
- `quoteScale` (`CauldronRegistry.sol:323`) is the only decimals conversion in the cluster: wei of
  ether-equivalent per RAW quote unit, scaled by 1e18, governance-set rather than oracle-derived. It defaults to
  1e18 when the caller passes zero, which is the identity for an 18-decimal asset and wrong by 1e12 for a
  6-decimal one unless the caller supplies the real value.
- Token amounts are 18-decimal throughout: `TOTAL_SUPPLY` is `777_000_000e18` (`CauldronBase.sol:156`) and
  `GEN1_ACTIVE_TOKENS` is four fifths of it (`CauldronBase.sol:160`).
- Basis points use a 10000 divisor at `CauldronRegistry.sol:360`, `:643`, `:722` and `:926`.
- `AUTO_MIGRATE_FEE` (`CauldronBase.sol:162`) and `primeBuyEth` are native wei; the collection floor and every
  redemption payout are in the LIVE generation's token, never in ether
  (`CauldronRegistry.sol:1523`, `:1543`).
- Tick units: `nextReserveCeilingOffset` is a tick offset bounded to 4000..138000 (`CauldronRegistry.sol:198`)
  and `TICK_SPACING` is 200 (`CauldronBase.sol:158`).

## G. `unchecked` blocks and rounding direction

- `CauldronRegistry.sol` contains **no** `unchecked` block, so every arithmetic operation in the cluster's own
  code is checked. The one raw-assembly region is the forwarder at `CauldronRegistry.sol:1460`, which performs no
  arithmetic beyond `calldatasize` / `returndatasize`.
- Integer divisions, all truncating toward zero (in the protocol's favour, leaving dust in the reserve):
  `enchantFee` at `CauldronRegistry.sol:360`; the genesis pool split at `CauldronRegistry.sol:722` and the
  per-fren share at `CauldronRegistry.sol:723`, whose product is then re-multiplied at
  `CauldronRegistry.sol:724` so the reserve is sized to the rounded-down share rather than the raw pool; the
  airdrop cap at `CauldronRegistry.sol:643`; `floorPerFren` at `CauldronBase.sol:426`.
- Subtractions that could underflow are explicitly clamped instead of wrapped: `newActive` at
  `CauldronRegistry.sol:1022`, `:1057` and `:1074`, `reserveTokens` at `CauldronRegistry.sol:732`, and the
  reserve debit at `RedemptionExt.sol:91`.

## H. Comment-vs-code observations

1. `summon` — comment at `CauldronRegistry.sol:708` says the generation token is deployed with plain CREATE;
   the code reached from `CauldronRegistry.sol:709` deploys with CREATE2 from a mined salt at `PoolOps.sol:707`,
   using plain CREATE only in the unmined fallback at `PoolOps.sol:718`.
2. `relaunch` — the same claim at `CauldronRegistry.sol:933`.
3. `_deployToken` — comment at `CauldronRegistry.sol:1627` says "plain CREATE, NOT CREATE2" because a
   predictable address could be squatted, while the note at `CauldronRegistry.sol:1641` calls the registry the
   CREATE2 deployer.
4. `relaunch` — comment at `CauldronRegistry.sol:777` says anyone can call once the pool is confirmed dead;
   `CauldronRegistry.sol:805` also requires a wired governor holding proposals and `CauldronRegistry.sol:801`
   also requires the grace period.
5. `relaunch` — comment at `CauldronRegistry.sol:815` says a revert in the force-close can never brick the
   rebirth; `CauldronRegistry.sol:1144` makes that call with no try/catch, and the note at
   `CauldronRegistry.sol:1125` states the opposite.
6. `claimByBurn` — the header at `CauldronRegistry.sol:44` names the migration entry `claimTokens(gen)`; the
   code exposes `claimByBurn` (`CauldronRegistry.sol:1243`) and the forwarder `claimByBurnUpTo` (`CauldronRegistry.sol:1288`), whose body is on the facet (`RedemptionExt.sol:653`).
7. `_forwardToExt` — comment at `CauldronRegistry.sol:1784` says the fallback delegatecalls any unknown selector
   to the facet; the contract declares only `receive` (`CauldronRegistry.sol:572`), which the note at
   `CauldronRegistry.sol:1416` also states.
8. `floorClaimableNow` / `legCount` — `RedemptionExt.sol:632` and `CauldronBase.sol:535` say these are reached
   "through the registry's fallback"; they are explicit stubs at `CauldronRegistry.sol:1424`, `:1429`, `:1434`.
9. `_flushLegacyAtRelaunch` — the NatSpec at `CauldronRegistry.sol:1485` documents a hook-only recorder; no such
   function is declared, and the next declaration is the private helper at `CauldronRegistry.sol:1500`.
10. `_seedGeneration` — comment at `CauldronRegistry.sol:1666` says BOTH genesis and relaunch use the
    green-candle seed; `CauldronRegistry.sol:1729` takes a different library entry whenever a seeder is set and
    `CauldronRegistry.sol:1728` is non-zero.
11. `unlockCallback` — comment at `CauldronRegistry.sol:1758` says the callback is accepted only while a
    RELAUNCH buy is armed; `CauldronRegistry.sol:1766` accepts it whenever the flag is set, and ignition sets it
    too (`CauldronRegistry.sol:755`, `:1727`).
12. `CauldronToken` constructor — `CauldronToken.sol:29` declares a fixed 777 million supply constant;
    `CauldronToken.sol:46` mints whatever the deployer passes and never compares the two.
13. `CauldronToken.burn` — `CauldronToken.sol:56` lists "unclaimed migration leftovers" as a use; the registry
    records that path as obsolete at `CauldronRegistry.sol:1364` and no such caller remains.
14. `IDeathChecker.isDead` — `IDeathChecker.sol:13` says the hook OWNER points the hook at a new checker;
    `CauldronHook.sol:1933` accepts the registry as well.

---

## Extra 1 — the generation lifecycle

**Phase variables.** `summoned` (slot 0, `CauldronBase.sol:179`), `currentGeneration` (1),
`currentToken` (2), `lastSummonAt` (38), `_seedBuyUnlocked` (slot 0, `CauldronBase.sol:182`),
`emergencyReadyAt` (37), `redemptionPaused` (30), `claimGate` (32), `successor` (31), and the per-generation
records `generationToken`/`generationQuote`/`generationPoolId`/`generationPoolKey`/`generationPositionId`/
`generationReservePositionId`/`reserveTickLower`/`reserveTickUpper`/`generationCollection`/`generationVault`/
`generationProposer`/`generationParent`/`generationLegs`.

| # | transition | trigger (who) | lines |
|---|---|---|---|
| 0 | deploy → wiring | deployer | constructor `CauldronRegistry.sol:158`; writes `poolManager` `:167`, `positionManager` `:168`, `hook` `:169`, `emergencyAdmin` `:171`, `emergencyDelay` `:172`, allows native quote `:175`, `:176` |
| 1 | wiring (`summoned == false`) | owner | `setRedemptionExt` `:182` (one-shot), `setFactory` `:593`, `setGovernor` `:583`, `setGenesisBonus` `:625`, `setAirdropReserve` `:640`, `setPrimeFunder` `:649`, `setIgniter` `:418`, `setCollectionLedger` `:1479`, `setSeeder` `:309`, `setSeedWindow` `:332`, `setReserveCeiling` `:195`, `setAllowedQuote` `:290` |
| 2 | wiring → generation 1 | owner OR igniter (`:695`), one-shot at `:696` | `summoned = true` `:699`, `currentGeneration = 1` `:700`, `lastSummonAt` `:701`, token `:710`/`:711`, genesis sizing `:723`/`:724`, airdrop `:733`, seed `:742`, prime buy `:750`-`:757`, collection `:761` |
| 3 | live generation | anyone | migration `:1243`, `:1288`, `:1346`; OG redemption `:1389`, `:1395`, `:1401`, `:1407`; collection floor `:1514`, `:1535`; rotation `:240`, `:264` |
| 4 | live → eligible for rebirth | state only: hook says dead `:797`, grace elapsed `:801`, governor holds proposals `:805` | — |
| 5 | rebirth | anyone (`relaunch` `:785`) | perp force-close `:819`; LP teardown `:822`; burn `:829`; ticket drain `:840`; `currentGeneration + 1` `:857`; `lastSummonAt` `:858`; winner `:867`; quote narrowed `:915`; token `:934`-`:936`; funding `:966`; solvency `:994`; `markConsumed` `:995`; `generationQuote` `:1000`; proposer + parent `:1005`/`:1006`; reserve sizing `:1019`-`:1075`; seed `:1083`; collection `:1090`-`:1093`; curve `:1098`; perp re-arm `:1103` |
| 5a | quote of the newborn | the winning proposal, narrowed three times and never allowed to revert | allowlist `:915`, mining fallback `:934`, funding narrowing `:966`, recorded `:1000` |
| 5b | seed-buy window | `_seedGeneration` | armed `:1727`, cleared `:1740`; ignition also arms it at `:755`/`:757`; the only consumer is `unlockCallback` `:1766` |
| 6 | emergency window | emergencyAdmin arms `:421`; guardian may cancel `:440` | consumed once per action at `:409` |
| 7 | terminal / handoff | emergencyAdmin, armed + timelocked | `emergencyWithdrawLP` `:469`, `emergencySweep` `:482`, `rescueSeeder` `:339`, `migrateToSuccessor` `:534` (pointer set at `:499`) |
| 8 | migration mode switch | emergencyAdmin | `setClaimGate` `:518` — restricting consumes a timelock at `:519`, restoring is instant |

Generation 1 is always native-quoted: nothing writes `generationQuote[1]`, and the mapping's zero default is
what the pool is built against (`CauldronRegistry.sol:712`-`:714`). `currentGeneration` advances at `:857`
BEFORE the new token exists, so a revert after that point rolls the whole rebirth back.

## Extra 2 — registry → facet forwarding (which side holds the gate)

Every forwarder's body is `_forwardToExt()` (`CauldronRegistry.sol:1457`), which rejects an unset target at
`:1459`, copies the full calldata at `:1461`, DELEGATECALLs at `:1462` and bubbles the result at `:1463`.
There is no fallback (`CauldronRegistry.sol:572`), so an un-stubbed facet function is unreachable.

| forwarder (registry) | facet function | gate side |
|---|---|---|
| `rotateSlice` `:240` | `RedemptionExt.rotateSlice` `:269` → `rotateSliceFrom` `:274` with `fromLeg = 0` | FACET — wiring `:311`, `:320`, envelope `:335`, slice bound `:336` |
| `rotateSliceFrom` `:264` | `RedemptionExt.rotateSliceFrom` `:280` | FACET — same four checks |
| `setRotationWiring` `:274` | `RedemptionExt.setRotationWiring` `:260` | FACET `onlyOwner`, resolved against THIS registry's owner slot |
| `claimByBurnUpTo` `:1288` | `RedemptionExt.claimByBurnUpTo` `:653` | FACET — earlier generations only `:657`, the vesting-gate/engine exemption `:658`, known source token `:661`, real balance `:664` |
| `recoverLegs` `:290` | `RedemptionExt.recoverLegs` `:732` | FACET — past generations only `:733`; otherwise permissionless |
| `sweepLegProceeds` `:300` | `RedemptionExt.sweepLegProceeds` `:882` | FACET `onlyOwner` |
| `redeemOgFren` `:1389` | `RedemptionExt.redeemOgFren` `:78` | FACET — breaker `:79`, ignition `:80`, OG id range `:83`, ownership `:84` |
| `buyTreasuryOgFren` `:1395` | `RedemptionExt.buyTreasuryOgFren` `:115` | FACET — ignition `:118`, id range `:119`, treasury custody `:121` |
| `donateToReserve` `:1401` | `RedemptionExt.donateToReserve` `:136` | FACET, but ungated: only ignition `:139` and a non-zero amount `:140` |
| `materializeLegacyReserve` `:1407` | `RedemptionExt.materializeLegacyReserve` `:147` | FACET, ungated: ignition `:150` only |
| `floorClaimableNow` `:1424` | `RedemptionExt.floorClaimableNow` `:634` | neither — ungated read (via `_forwardToExtView` `:1447`) |
| `legCount` `:1429` | `RedemptionExt.legCount` `:677` | neither — ungated read |
| `legAt` `:1434` | `RedemptionExt.legAt` `:682` | neither — ungated read; out-of-range reverts on the array access `RedemptionExt.sol:687` |
| `_removeLiquidity` `:1613` (internal, raw `delegatecall`) | `RedemptionExt.recoverLegsAtTeardown` `:783` | REGISTRY — only reachable from relaunch/emergency teardown; the selector is compiler-computed at `CauldronRegistry.sol:65` and a failure is swallowed at `:1614` |

`RedemptionExt.legProceedsOf` (`RedemptionExt.sol:845`) has no stub and therefore no path through the registry. `completeRotation` no longer exists on either side: the facet records it as deleted dead code at `RedemptionExt.sol:608`. `hasClaimed` has been removed from the registry as well.
The facet keeps its own `nonReentrant`, which runs against the registry's shared guard slot, which is why the
forwarders must not carry one (`CauldronRegistry.sol:1381`-`:1384`).

`PoolOps` is the other delegatecall target — a linked library, so it declares no storage of its own and inherits
the registry's layout by construction. Calls: `:705`, `:756`, `:966`, `:1044`, `:1262`, `:1358`,
`:1502`, `:1524`, `:1541`, `:1570`, `:1575`, `:1647`, `:1687`, `:1729`, `:1767`.

## Extra 3 — storage slots shared across the delegatecall facets

From `audit/graph/cache/CauldronRegistry.storageLayout.json` and
`audit/graph/cache/RedemptionExt.storageLayout.json`:

- Both layouts have **60 entries occupying slots 0..53**, and they are **identical for the entire length** —
  same order, same slot, same offset, same label, same type. There is no divergence point.
- The only textual difference is the AST-id suffix inside four type identifiers (e.g.
  `t_mapping(t_uint256,t_userDefinedValueType(PoolId)20317)` in the registry vs `…(PoolId)18176` in the facet,
  entry index 9, `generationPoolId`, slot 6). AST ids are per-compilation-unit identifiers, not layout, so the
  two agree slot-for-slot.
- This holds because both contracts derive from `CauldronBase` and neither adds a state variable
  (`CauldronBase.sol:75`-`:84`). The three former immutables are storage here on purpose
  (`CauldronBase.sol:302`-`:307`): an immutable resolves against the EXECUTING contract's code and would read as
  zero inside the facet.
- Shared prefix by slot: `0` `_owner` + `nextReserveCeilingOffset` + `summoned` + `_seedBuyUnlocked`;
  `1` `currentGeneration`; `2` `currentToken`; `3`-`11` the per-generation mappings;
  `12` `genesisReserveOutstanding`; `13`-`15` `claimed`/`generationCollection`/`generationVault`;
  `16`-`17` `collectionLedger`/`genesisPending`; `18`-`19` `factory`/`governor`; `20`-`29` the brew and genesis
  parameters; `30` `redemptionPaused` + `guardian`; `31`-`36` `successor`, `claimGate`, `airdropWallet`,
  `airdropReserve`, `primeBuyEth`, `primeFunder`; `37`-`39` `emergencyReadyAt`, `lastSummonAt`, `minLifetime`;
  `40` `autoMigrate` (the end of the documented baseline, `CauldronBase.sol:296`);
  `41`-`44` `poolManager`, `positionManager`, `hook`, `redemptionExt`; `45` `seeder` + `nextSeedWindow`;
  `46` `igniter`; `47`-`53` `allowedQuote`, `generationQuote`, `quoteRotator`, `treasuryGovernor`, `quoteScale`,
  `generationLegs`, `legProceeds`.
  (The cache reports `igniter` at slot 46 and `nextSeedWindow` packed at slot 45 offset 20, one slot lower than
  the comments at `CauldronBase.sol:317` and `:331` claim.)
- `CauldronRegistry`'s own additions are code-only and therefore layout-neutral: `RECOVER_LEGS`
  (`CauldronRegistry.sol:65`), `emergencyAdmin` (`:128`), `emergencyDelay` (`:130`), `RELAUNCH_TAIL_RESERVE`
  (`:141`), `RELAUNCH_TICKETS` (`:144`). The facet never reads them.

---

## I. Function inventory

**CauldronRegistry**

| line | signature | authority | value effect |
|---|---|---|---|
| 158 | `constructor( address _poolManager, address _positionManager, address _hook, address _emer...` | deployer | NONE |
| 184 | `function setRedemptionExt(address ext) external onlyOwner` | owner | NONE |
| 197 | `function setReserveCeiling(int24 offset) external onlyOwner` | owner | NONE |
| 240 | `function rotateSlice(uint16, uint256, PoolKey calldata) external returns (uint256, uint25...` | anyone at the registry; the facet holds the gate (RedemptionExt.rotateSliceFrom requires rotation wiring pl... | NONE in this stub; the value movement happens inside the delegatecalled facet, which runs on this registry'... |
| 264 | `function rotateSliceFrom(uint8, uint16, uint256, PoolKey calldata) external returns (uint...` | anyone at the registry; the facet holds the gate (RedemptionExt.rotateSliceFrom requires rotation wiring pl... | NONE in this stub; the value movement happens inside the delegatecalled facet, which runs on this registry'... |
| 274 | `function setRotationWiring(address, address) external` | owner (the gate is on the facet: RedemptionExt.setRotationWiring is onlyOwner and runs against this registr... | NONE |
| 290 | `function recoverLegs(uint256) external returns (uint256, uint256)` | anyone at the registry; the facet holds the only gate (RedemptionExt.recoverLegs refuses generation 0 and t... | NONE in this stub; the facet moves the recovered leg balances under delegatecall, so they land in this regi... |
| 300 | `function sweepLegProceeds(address, address) external returns (uint256)` | owner (the gate is on the facet: RedemptionExt.sweepLegProceeds is onlyOwner) | NONE in this stub; the facet sends the booked asset out of this registry's balance |
| 308 | `function setAllowedQuote(address quote, bool allowed, uint256 scale) external onlyOwner` | owner | NONE |
| 327 | `function setSeeder(address _seeder) external onlyOwner` | owner | NONE |
| 339 | `function rescueSeeder() external onlyEmergency timelocked nonReentrant` | emergencyAdmin | receives native and/or token back from the seeder through `rescue` (line 342) |
| 350 | `function setSeedWindow(uint64 window) external onlyOwner` | owner | NONE |
| 359 | `function enchantFee() external view returns (uint256)` | anyone | NONE |
| 363 | `modifier onlyEmergency()` | internal (callers: rescueSeeder, armEmergency, setRedemptionPaused, setEnchantFeeMult, emergencyWithdrawLP,... | NONE |
| 372 | `modifier timelocked()` | internal (callers: rescueSeeder, emergencyWithdrawLP, emergencySweep, migrateToSuccessor) | NONE |
| 406 | `function _consumeTimelock() private` | internal (callers: timelocked, setClaimGate) | NONE |
| 414 | `function setIgniter(address who) external onlyOwner` | owner | NONE |
| 420 | `function armEmergency() external onlyEmergency` | emergencyAdmin | NONE |
| 428 | `function setGuardian(address who) external` | emergencyAdmin or owner | NONE |
| 438 | `function vetoEmergency() external` | guardian | NONE |
| 453 | `function setRedemptionPaused(bool paused) external onlyEmergency` | emergencyAdmin | NONE |
| 462 | `function setEnchantFeeMult(uint256 bps) external onlyEmergency` | emergencyAdmin | NONE |
| 469 | `function emergencyWithdrawLP(uint256 gen) external onlyEmergency timelocked nonReentrant` | emergencyAdmin | ERC20 transfer of the generation token `tok` to the emergency admin (line 472); sends native to `emergencyA... |
| 482 | `function emergencySweep(address token) external onlyEmergency timelocked nonReentrant` | emergencyAdmin | sends the registry's whole native balance to `emergencyAdmin` (line 484); ERC20 transfer of the caller-name... |
| 499 | `function setSuccessor(address _successor) external onlyEmergency` | emergencyAdmin | NONE |
| 518 | `function setClaimGate(address gate) external onlyEmergency` | emergencyAdmin | NONE |
| 534 | `function migrateToSuccessor() external onlyEmergency timelocked nonReentrant` | emergencyAdmin | ERC721 ownership of the active position is moved to the successor at `transferFrom` (line 542) and the rese... |
| 572 | `receive() external payable` | anyone | receives native through `receive` (line 572) |
| 579 | `function setGovernor(address _governor) external onlyOwner` | owner | NONE |
| 584 | `function setMinLifetime(uint256 _seconds) external onlyEmergency` | emergencyAdmin | NONE |
| 589 | `function setFactory(address _factory) external onlyOwner` | owner | NONE |
| 594 | `function setNftMaxSupply(uint256 _max) external onlyOwner` | owner | NONE |
| 601 | `function setRoyalty(address _dividend, uint96 _bps) external onlyOwner` | owner | NONE |
| 609 | `function setGenesisMetadata(MetadataMode mode, string calldata baseURI, address renderer)...` | owner | NONE |
| 625 | `function setGenesisBonus(address _mifrens, uint256 _bonusBps, uint256 _shares) external o...` | owner | NONE |
| 640 | `function setAirdropReserve(address _wallet, uint256 _amount) external onlyOwner` | owner | NONE |
| 649 | `function setPrimeFunder(address who) external onlyOwner` | owner | NONE |
| 659 | `function fundPrimeBuy() external payable` | primeFunder | receives native, accumulated into `primeBuyEth` (line 661) |
| 665 | `function sweepPrimeBuy() external` | primeFunder | sends native equal to `amt` back to the funder (line 669) |
| 686 | `function summon() external payable nonReentrant returns (address token, PoolId poolId)` | owner or igniter | receives native as the entire genesis pairing, which `_seedGeneration` places into the pool (line 742); ERC... |
| 785 | `function relaunch() external nonReentrant returns (address token, PoolId poolId)` | anyone | receives the recovered quote and token of the dying generation through `_removeLiquidity` (line 822); burns... |
| 1112 | `function _perpHousekeep(bool sync) private` | internal (callers: relaunch) | NONE |
| 1153 | `function _deployCollection( uint256 gen, string memory name, string memory symbol, Metada...` | internal (callers: summon, relaunch) | NONE |
| 1202 | `function _continueMiFrens(uint256 gen) private` | internal (callers: relaunch) | NONE |
| 1243 | `function claimByBurn(uint256 fromGen, uint256 amount) external returns (uint256 claimedAm...` | anyone (holders of a previous generation's token); blocked for ordinary callers while a vesting gate is set | burns the caller's previous-generation balance and releases the same amount of the live token out of the re... |
| 1288 | `function claimByBurnUpTo(uint256, uint256) external returns (uint256)` | any holder of an earlier generation, unless a claim gate is set, in which case only the gate itself or the ... | NONE in this stub; the burn and the reserve withdrawal happen inside the delegatecalled facet, on this regi... |
| 1306 | `function enableAutoMigrate() external payable` | anyone (free for any MiFren holder, otherwise a fee is required) | receives native: the opt-in fee is required only when the caller holds no fren, checked at `AUTO_MIGRATE_FE... |
| 1334 | `function disableAutoMigrate() external` | anyone (for their own wallet only) | NONE |
| 1346 | `function autoMigrateBatch(uint256 fromGen, address[] calldata holders) external nonReentr...` | anyone (permissionless keeper) | burns each opted-in holder's whole previous-generation balance and releases the same amount of the live tok... |
| 1389 | `function redeemOgFren(uint256) external returns (uint256)` | anyone holding a genesis fren; the facet holds the gate (RedemptionExt checks OG ownership and the redempti... | NONE in this stub; the facet pays the live floor out of this registry's reserve position and takes custody ... |
| 1395 | `function buyTreasuryOgFren(uint256) external returns (uint256)` | anyone; the facet holds the gate (the fren must currently sit in this registry's treasury) | NONE in this stub; the facet pulls twice the live floor in the current token from the buyer and grows the r... |
| 1401 | `function donateToReserve(uint256) external` | anyone | NONE in this stub; the facet pulls the donated amount of the current token from the caller into the reserve |
| 1407 | `function materializeLegacyReserve() external returns (uint256)` | anyone (permissionless keeper) | NONE in this stub; the facet sweeps the hook's held buyback tokens into this registry's reserve position |
| 1424 | `function floorClaimableNow() external returns (bool, uint256)` | anyone | NONE |
| 1429 | `function legCount(uint256) external returns (uint256)` | anyone | NONE |
| 1434 | `function legAt(uint256, uint256) external returns (address, uint256, PoolKey memory)` | anyone | NONE |
| 1447 | `function _forwardToExtView() private` | internal (callers: floorClaimableNow, legCount, legAt) | NONE |
| 1457 | `function _forwardToExt() private` | internal (callers: rotateSlice, rotateSliceFrom, setRotationWiring, sweepLegProceeds, redeemOgFren, buyTrea... | NONE directly; the delegatecalled code executes with this registry's balances and position custody |
| 1479 | `function setCollectionLedger(address ledger) external onlyOwner` | owner | NONE |
| 1500 | `function _flushLegacyAtRelaunch(uint256 oldGen, address oldToken) private` | internal (callers: relaunch) | NONE at this level; the library sweeps the hook's un-materialized buyback tokens for the dying generation a... |
| 1514 | `function recycleCollectionNFT(uint256 gen, uint256 tokenId) external nonReentrant returns...` | anyone owning the collection NFT (ownership enforced in the library) | releases the collection's floor entitlement in the LIVE generation's token out of the shared reserve to the... |
| 1535 | `function buyCollectionNFT(uint256 gen, uint256 tokenId) external nonReentrant returns (ui...` | anyone (the NFT must currently sit in this registry's treasury) | pulls twice the NFT's floor in the live token from the buyer into the reserve and hands the NFT over, insid... |
| 1558 | `function _removeLiquidity(uint256 gen) private returns (uint256 ethRecovered, uint256 tok...` | internal (callers: relaunch, emergencyWithdrawLP) | recovers both sides of the active and reserve positions into this registry through `removeAll` (line 1570) ... |
| 1632 | `function _deployToken( string memory name, string memory symbol, uint256 gen, address wan...` | internal (callers: summon, relaunch) | NONE; the deployed token mints its entire fixed supply to this registry inside its own constructor |
| 1677 | `function _createPoolAndSeedWithBuy( address token, uint256 activeTokens, uint256 ethAmoun...` | internal (callers: _seedGeneration) | pays the whole funded amount and the active token tranche into the new pool, then buys the reserve back out... |
| 1709 | `function _seedGeneration( address token, uint256 activeTokens, uint256 ethAmount, uint256...` | internal (callers: summon, relaunch) | hands the active tranche plus the funding to either the streaming seeder or the atomic green-candle seed; o... |
| 1746 | `function _recordSeed(SeedResult memory r, uint256 gen) private returns (PoolId poolId)` | internal (callers: _seedGeneration, _createPoolAndSeedWithBuy) | NONE |
| 1764 | `function unlockCallback(bytes calldata data) external returns (bytes memory)` | poolManager, and only while the seed-buy window is armed | spends this registry's quote side and receives the bought token, inside `executeBuy` (line 1767) |

**CauldronToken**

| line | signature | authority | value effect |
|---|---|---|---|
| 36 | `constructor( string memory _name, string memory _symbol, uint256 _generation, address _re...` | deployer (the registry, acting through the delegatecalled PoolOps deploy) | NONE in native terms; the entire initial supply is minted to the registry at `_mint` (line 46) |
| 49 | `modifier onlyRegistry()` | internal (callers: burn) | NONE |
| 58 | `function burn(address from, uint256 amount) external onlyRegistry` | registry | destroys `amount` of the named holder's balance, reducing total supply (line 59) |

**ICollectionRenderer (declared in ICauldron.sol)**

| line | signature | authority | value effect |
|---|---|---|---|
| 12 | `function tokenURI(uint256 tokenId) external view returns (string memory)` | anyone (view on a proposer-supplied renderer contract) | NONE |

**LaunchLib (declared in ICauldron.sol)**

| line | signature | authority | value effect |
|---|---|---|---|
| 38 | `function displayName(string memory name) internal pure returns (string memory)` | internal (callers: summon, relaunch) | NONE |

**ICauldronGovernor (declared in ICauldron.sol)**

| line | signature | authority | value effect |
|---|---|---|---|
| 45 | `function winner() external view returns (uint256 proposalId, BrewSpec memory spec)` | anyone (view); the registry is its only in-tree caller | NONE |
| 46 | `function markConsumed(uint256 proposalId) external` | registry (the implementation restricts the caller) | NONE |
| 47 | `function hasProposals() external view returns (bool)` | anyone (view) | NONE |

**ICauldronCollection (declared in ICauldron.sol)**

| line | signature | authority | value effect |
|---|---|---|---|
| 52 | `function mint(address to) external returns (uint256 tokenId)` | the collection's wired minter (the volume hook) | NONE |
| 53 | `function totalMinted() external view returns (uint256)` | anyone (view) | NONE |
| 54 | `function maxSupply() external view returns (uint256)` | anyone (view) | NONE |

**IDeathChecker**

| line | signature | authority | value effect |
|---|---|---|---|
| 27 | `function isDead(PoolId id, uint256 volume24h, uint256 deathThreshold) external view retur...` | anyone (view on a pluggable module) | NONE |

**ILiquidatorMintable**

| line | signature | authority | value effect |
|---|---|---|---|
| 38 | `function mintLiquidatorWithStats(address to, LiqStats calldata s) external returns (uint2...` | the collection's wired liquidatorMinter (the perp engine) | NONE |
| 44 | `function mintLiquidator(address to) external returns (uint256 tokenId)` | the collection's wired liquidatorMinter (the perp engine) | NONE |
| 47 | `function liqStats(uint256 tokenId) external view returns (LiqStats memory)` | anyone (view) | NONE |

**ISurtaxPolicy (declared in IPolicies.sol)**

| line | signature | authority | value effect |
|---|---|---|---|
| 25 | `function surtaxBps(PoolId id, uint256 initBlock, uint256 maxBps, uint256 windowBlocks) ex...` | anyone (view on a pluggable module) | NONE |

**IOddsPolicy (declared in IPolicies.sol)**

| line | signature | authority | value effect |
|---|---|---|---|
| 37 | `function oddsBps(uint256 playWei, uint256 maxBps, uint256 fullVolumeWei) external view re...` | anyone (view on a pluggable module) | NONE |

**ICurvePolicy (declared in IPolicies.sol)**

| line | signature | authority | value effect |
|---|---|---|---|
| 49 | `function priceAt(uint256 k, uint256 base, uint256 step) external view returns (uint256 co...` | anyone (view on a pluggable module) | NONE |

**IFeeRouter (declared in IPolicies.sol)**

| line | signature | authority | value effect |
|---|---|---|---|
| 70 | `function route(uint256 feeAmount, address guild, address vault, uint256 guildBps, uint256...` | anyone (view on a pluggable module) | NONE; the module only returns amounts, and the hook performs every send itself |
