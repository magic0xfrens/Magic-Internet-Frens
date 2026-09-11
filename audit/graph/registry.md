# Cluster `registry` — function graph

Generated from the decontaminated tree; line numbers identical to the repo.

Source tree: `/tmp/blind-final/contracts/solidity`

| file | lines | nodes |
|---|---|---|
| `CauldronRegistry.sol` | 1786 | 68 |
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
| `genesisReserveOutstanding` (12) | units of the LIVE generation's ERC20 | set at `CauldronRegistry.sol:706` (ignition sizing); `+= genesisPending` at `CauldronRegistry.sol:1001`; `+= added` at `RedemptionExt.sol:182` (buy / donate / re-enchant) | `-= F` at `RedemptionExt.sol:91` on each OG recycle, guarded by a `>=` test on the same line |
| `genesisPending` (17) | units of the DYING generation's ERC20, carried as a number | `+= og` at `CauldronRegistry.sol:1501` (relaunch flush); `+= og` at `RedemptionExt.sol:158` (keeper materialize) | zeroed at `CauldronRegistry.sol:1002` immediately after the fold |
| `genesisSharePerFren` (28) | ERC20 units per fren, fixed at ignition | `CauldronRegistry.sol:705` | never |
| `genesisShares` (27) | count of frens (the divisor of the floor) | `CauldronRegistry.sol:616` | never; owner-settable only while `summoned == false` (`CauldronRegistry.sol:611`) |
| `airdropReserve` (34) | units of generation one's ERC20 | `CauldronRegistry.sol:627` | never zeroed; it is read and paid out once at `CauldronRegistry.sol:715` and the counter keeps its value afterwards |
| `primeBuyEth` (35) | native wei | `+= msg.value` at `CauldronRegistry.sol:643` | `= 0` at `CauldronRegistry.sol:650` (funder reclaim) and `= 0` at `CauldronRegistry.sol:734` (spent on the ignition buy) |
| `legProceeds` (53) | raw units of the booked foreign quote | `+= q` at `RedemptionExt.sol:743` | `= 0` at `RedemptionExt.sol:801` before the send at `RedemptionExt.sol:802` |
| `generationPositionId` (8) | a PositionManager token id — the handle to the ACTIVE LP | `CauldronRegistry.sol:1744` | never cleared, including after the position is fully removed at `CauldronRegistry.sol:1564` |
| `generationReservePositionId` (9) | a PositionManager token id — the handle to the migration/genesis reserve | `CauldronRegistry.sol:1745` | never cleared, including after removal at `CauldronRegistry.sol:1569` |
| `generationLegs` (52) | array of rotated LP handles per generation | pushed at `RedemptionExt.sol:682` | popped per leg at `RedemptionExt.sol:747`, only on a successful unwind |
| `quoteScale` (51) | wei of ether-equivalent per RAW unit of the quote, scaled 1e18 | `CauldronRegistry.sol:174` (native identity) and `CauldronRegistry.sol:305` | never zeroed; a de-listing at `CauldronRegistry.sol:303` leaves the stale scale behind |
| `emergencyReadyAt` (37) | unix timestamp (the arming, not value) | `CauldronRegistry.sol:403` | `CauldronRegistry.sol:391` (consumed) and `CauldronRegistry.sol:422` (guardian veto) |
| `enchantFeeMultBps` (29) / `royaltyBps` (21) / `genesisBonusBps` (26) | basis points | `CauldronRegistry.sol:446`, `CauldronRegistry.sol:586`, `CauldronRegistry.sol:615` | same lines (overwrite) |
| `nftMaxSupply` (20) / `nextSeedWindow` (46) / `minLifetime` (39) / `nextReserveCeilingOffset` (0) | NFT count / seconds / seconds / tick offset | `CauldronRegistry.sol:578`, `:334`, `:567`, `:197` | same lines (overwrite) |

Value that is held but never counted: the registry's raw ether balance (paid in at `CauldronRegistry.sol:554`,
swept wholesale at `CauldronRegistry.sol:466` and `CauldronRegistry.sol:548`) and its ERC20 balances of every
generation token.

## B. Balance vs counter

- `primeBuyEth` is a counter, and the refund at `CauldronRegistry.sol:651` pays the COUNTER out of the registry's
  pooled ether, which also holds hook reserve pulls, vault sweeps and auto-migrate fees. The two only agree while
  no other source has been consumed; `CauldronRegistry.sol:734` spends the counter through
  `PoolOps.primeBuy` without any balance check.
- `genesisReserveOutstanding` counts an entitlement; the tokens backing it sit in the out-of-range reserve LP
  addressed by `generationReservePositionId` (`CauldronRegistry.sol:1745`). The two are reconciled only at the
  point of payment, inside the library, which is why a short reserve must revert the whole redemption
  (`RedemptionExt.sol:91` debits first, the pull happens after). At a rebirth the counter is carried forward
  (`CauldronRegistry.sol:1001`) while the backing is re-created from `newReserve` (`CauldronRegistry.sol:1057`);
  when they cannot be made to agree the shortfall is emitted rather than enforced, at
  `CauldronRegistry.sol:1017` and `CauldronRegistry.sol:1042`.
- `airdropReserve` is never zeroed after the single payout at `CauldronRegistry.sol:715`, so the counter
  permanently over-states what remains reserved.
- `legProceeds` is backed by the registry's own balance of that asset; the sweep at `RedemptionExt.sol:796`
  trusts the counter and sends from the balance.
- `collectionLedger.totalEntitled()` (`CauldronRegistry.sol:1030`) is an external counter that sizes the new
  reserve; nothing checks it against anything this contract holds.

## C. Authority map

| gate | held by | rotatable | renounce / dead-end |
|---|---|---|---|
| `onlyOwner` (17 setters, e.g. `CauldronRegistry.sol:182`, `:290`, `:571`) | `Ownable._owner`, slot 0 | yes, via `transferOwnership` | `renounceOwnership` is overridden to revert at `CauldronBase.sol:417`, so ownership cannot be dropped |
| `onlyEmergency` (`CauldronRegistry.sol:346`) | `emergencyAdmin`, **immutable** (`CauldronRegistry.sol:169`) | no | cannot be rotated, renounced or replaced for the life of the deployment |
| `timelocked` (`CauldronRegistry.sol:355`) | nobody; it consumes an arming | n/a | requires a prior `armEmergency` even when `emergencyDelay == 0` (`CauldronRegistry.sol:389`) |
| guardian veto (`CauldronRegistry.sol:421`) | `guardian` | set by EITHER the emergency admin or the owner (`CauldronRegistry.sol:413`), not one-shot | defaults to the zero address, so no veto exists until it is wired |
| igniter (`CauldronRegistry.sol:677`) | `igniter`, owner-set (`CauldronRegistry.sol:397`) | yes | self-extinguishing: `summoned` (`CauldronRegistry.sol:678`) makes it a one-time right |
| prime funder (`CauldronRegistry.sol:642`, `:648`) | `primeFunder` | only while `summoned == false` (`CauldronRegistry.sol:632`) | frozen after ignition; a zero funder makes both entries unreachable |
| PoolManager callback (`CauldronRegistry.sol:1759`) | `poolManager` + the armed flag at `CauldronRegistry.sol:1760` | `poolManager` is written once, in the constructor (`CauldronRegistry.sol:165`) | no setter exists |
| facet `onlyOwner` (`RedemptionExt.sol:260`, `:794`) | this registry's own owner slot, through delegatecall | with ownership | same dead-end as above |
| rotation envelope (`RedemptionExt.sol:317`) | the MiFren treasury vote, read at `RedemptionExt.sol:303` | wiring replaceable at `RedemptionExt.sol:262` | execution is permissionless within the approved envelope |
| collection-NFT ownership (`PoolOps.sol:1380`) / treasury custody (`PoolOps.sol:1429`) | the token holder / this registry | n/a | enforced in the library, not here |
| `onlyRegistry` on the token (`CauldronToken.sol:50`) | the immutable `registry` (`CauldronToken.sol:45`) | no | burn authority is permanent and needs no allowance |

## D. External calls, with value and CEI ordering

| call site | callee | moves value | ordering |
|---|---|---|---|
| `CauldronRegistry.sol:311` | `hook.setSeeder` | no | after the storage write at `:310` |
| `CauldronRegistry.sol:324` | `ISeeder.rescue` | pulls the seeder's loose funds into this registry | after the timelock is consumed at `:391` |
| `CauldronRegistry.sol:342` | `floorPerFren` (base, internal) | no | pure read |
| `CauldronRegistry.sol:452` → `:454` → `:456` | `_removeLiquidity`, `IERC20.transfer`, `emergencyAdmin.call` | tokens then the whole ether amount | effects (`:391`) precede both sends; `nonReentrant` wraps it |
| `CauldronRegistry.sol:466`, `:469` | `emergencyAdmin.call`, arbitrary `IERC20` | whole native balance, whole token balance | the ERC20 branch calls a caller-named address twice (`balanceOf`, `transfer`) with no return check |
| `CauldronRegistry.sol:524`, `:525` | `IERC721.transferFrom` on the PositionManager | ownership of both live positions | before the loose-balance sends |
| `CauldronRegistry.sol:537` | `ISeeder.withdrawAll` | recovers the streamed book | before the sends at `:544` and `:548` |
| `CauldronRegistry.sol:548` | `to.call` where `to` is the admin-set successor | whole native balance | last, after every effect |
| `CauldronRegistry.sol:651` | `msg.sender.call` | the prime-buy counter | counter zeroed at `:650` first |
| `CauldronRegistry.sol:715` | `IERC20.transfer` | the airdrop reserve | before the pool is created |
| `CauldronRegistry.sol:738` | `PoolOps.primeBuy` | spends native on a market buy | flag armed at `:737`, cleared at `:739` |
| `CauldronRegistry.sol:779`, `:822`, `:989`, `:1080`, `:1096`, `:1126`, `:1167`, `:1171`, `:1194`, `:1195`, `:1748` | `CauldronHook` | no | `:822` and `:1126` are gas-capped against `RELAUNCH_TAIL_RESERVE`; `:822` is try/catch, `:1126` is not |
| `CauldronRegistry.sol:787`, `:849`, `:977` | `ICauldronGovernor` | no | `markConsumed` is deliberately placed after the last revert, at `:976` |
| `CauldronRegistry.sol:804` | `_removeLiquidity` → `PoolOps.removeAll`, `ISeeder.withdrawAll`, facet `recoverLegs` | recovers both sides of up to four sources | the leg delegatecall's failure is swallowed at `:1608` |
| `CauldronRegistry.sol:811` | `CauldronToken.burn` | destroys the recovered dead-pool supply | after the recovery |
| `CauldronRegistry.sol:948` | `PoolOps.seedFunding` | pulls both hook reserves and closes the dying vault | placed AFTER token mining so the pull matches the surviving quote |
| `CauldronRegistry.sol:1026`, `:1030` | `PoolOps.crystallizeCollection`, `ICollectionLedger.totalEntitled` | no | before the reserve is sized |
| `CauldronRegistry.sol:1065` | `_seedGeneration` | pays the whole funded amount into the newborn pool | last value move of the rebirth |
| `CauldronRegistry.sol:1151`, `:1189` | `ICauldronFactory` | no | not wrapped; a broken factory reverts the rebirth |
| `CauldronRegistry.sol:1244`, `:1279`, `:1352` | `PoolOps.migrateOne` / `migrateUpTo` / `autoMigrateBatch` | burns old supply, releases live supply from the reserve | the burn and the release are one library call |
| `CauldronRegistry.sol:1305` | `IERC721.balanceOf` on `mifrens` | no | before the flag write at `:1308` |
| `CauldronRegistry.sol:1456` | `delegatecall` to `redemptionExt` | whatever the facet moves, from this registry's custody | forwards all gas; return and revert data bubbled verbatim |
| `CauldronRegistry.sol:1518`, `:1535` | `PoolOps.recycleCollection` / `buyCollection` | pays the floor out of the reserve / pulls 2x the floor in | ledger debit precedes the reserve pull, with a rollback check at `PoolOps.sol:1413` |
| `CauldronRegistry.sol:1607` | `delegatecall` to `RedemptionExt.recoverLegs` | unwinds every rotated leg | failure deliberately ignored at `:1608` |
| `CauldronRegistry.sol:1641`, `:1681`, `:1723`, `:1761` | `PoolOps` deploy / seed / buy | mints supply to this registry, seeds the pool, executes the in-callback buy | all delegatecalls, so custody stays here |

## E. Loops

`CauldronRegistry.sol` contains **no** `for` or `while` loop of its own. Every loop the registry can reach runs
in code delegatecalled onto its storage, plus one it calls out to:

| loop | bound | who can grow the bound |
|---|---|---|
| `PoolOps.sol:1278` (auto-migrate batch) | `holders.length`, supplied by the caller at `CauldronRegistry.sol:1353` | the keeper, per call; unbounded except by block gas |
| `RedemptionExt.sol:733` (recover legs, reached from `CauldronRegistry.sol:1607`) | `legs.length` for the generation | anyone who can execute an approved rotation, since each new quote pushes a leg at `RedemptionExt.sol:682` |
| `RedemptionExt.sol:679` (upsert a leg) | the same `legs.length` | same |
| `PoolOps.sol:701` (address mining, reached from `CauldronRegistry.sol:1641`) | the fixed `SALT_TRIES` constant | nobody; exhausting it downgrades the quote rather than reverting |
| `CauldronRegistry.sol:822` (`hook.resolveTickets`) | the literal `RELAUNCH_TICKETS` = 50 (`CauldronRegistry.sol:142`) | nobody; capped and try/catch'd |
| `CauldronRegistry.sol:1126` (`hook.forceClosePerps`) | the perp book, bounded inside the engine | traders opening positions; gas-capped but NOT try/catch'd |
| `CauldronHook.sol:1602` (sibling volume sum, reached from `CauldronRegistry.sol:779`) | the pool's sibling list | whoever wires volume siblings on the hook |

## F. Denomination and units

- The rebirth's funding figure is named `totalETH` (`CauldronRegistry.sol:938`) but is denominated in
  `specQuote`'s own raw units, as the comment at `CauldronRegistry.sol:937` states.
- The amount recovered from the dying LP is measured in the PRIMARY pair's `currency0`, passed explicitly at
  `CauldronRegistry.sol:951` rather than taken from `generationQuote[oldGen]`, because a completed rotation
  flips that mapping while the primary position stays in the launch pair
  (`RedemptionExt.sol:730` matches on the same primary currency for exactly this reason).
- A rotated leg whose asset differs from that primary currency is booked into `legProceeds`
  (`RedemptionExt.sol:743`) instead of being added to the sum, keeping one denomination per sum.
- `quoteScale` (`CauldronRegistry.sol:305`) is the only decimals conversion in the cluster: wei of
  ether-equivalent per RAW quote unit, scaled by 1e18, governance-set rather than oracle-derived. It defaults to
  1e18 when the caller passes zero, which is the identity for an 18-decimal asset and wrong by 1e12 for a
  6-decimal one unless the caller supplies the real value.
- Token amounts are 18-decimal throughout: `TOTAL_SUPPLY` is `777_000_000e18` (`CauldronBase.sol:156`) and
  `GEN1_ACTIVE_TOKENS` is four fifths of it (`CauldronBase.sol:160`).
- Basis points use a 10000 divisor at `CauldronRegistry.sol:342`, `:625`, `:704` and `:908`.
- `AUTO_MIGRATE_FEE` (`CauldronBase.sol:162`) and `primeBuyEth` are native wei; the collection floor and every
  redemption payout are in the LIVE generation's token, never in ether
  (`CauldronRegistry.sol:1517`, `:1537`).
- Tick units: `nextReserveCeilingOffset` is a tick offset bounded to 4000..138000 (`CauldronRegistry.sol:196`)
  and `TICK_SPACING` is 200 (`CauldronBase.sol:158`).

## G. `unchecked` blocks and rounding direction

- `CauldronRegistry.sol` contains **no** `unchecked` block, so every arithmetic operation in the cluster's own
  code is checked. The one raw-assembly region is the forwarder at `CauldronRegistry.sol:1454`, which performs no
  arithmetic beyond `calldatasize` / `returndatasize`.
- Integer divisions, all truncating toward zero (in the protocol's favour, leaving dust in the reserve):
  `enchantFee` at `CauldronRegistry.sol:342`; the genesis pool split at `CauldronRegistry.sol:704` and the
  per-fren share at `CauldronRegistry.sol:705`, whose product is then re-multiplied at
  `CauldronRegistry.sol:706` so the reserve is sized to the rounded-down share rather than the raw pool; the
  airdrop cap at `CauldronRegistry.sol:625`; `floorPerFren` at `CauldronBase.sol:379`.
- Subtractions that could underflow are explicitly clamped instead of wrapped: `newActive` at
  `CauldronRegistry.sol:1004`, `:1039` and `:1056`, `reserveTokens` at `CauldronRegistry.sol:714`, and the
  reserve debit at `RedemptionExt.sol:91`.

## H. Comment-vs-code observations

1. `summon` — comment at `CauldronRegistry.sol:690` says the generation token is deployed with plain CREATE;
   the code reached from `CauldronRegistry.sol:691` deploys with CREATE2 from a mined salt at `PoolOps.sol:707`,
   using plain CREATE only in the unmined fallback at `PoolOps.sol:718`.
2. `relaunch` — the same claim at `CauldronRegistry.sol:915`.
3. `_deployToken` — comment at `CauldronRegistry.sol:1621` says "plain CREATE, NOT CREATE2" because a
   predictable address could be squatted, while the note at `CauldronRegistry.sol:1635` calls the registry the
   CREATE2 deployer.
4. `relaunch` — comment at `CauldronRegistry.sol:759` says anyone can call once the pool is confirmed dead;
   `CauldronRegistry.sol:787` also requires a wired governor holding proposals and `CauldronRegistry.sol:783`
   also requires the grace period.
5. `relaunch` — comment at `CauldronRegistry.sol:797` says a revert in the force-close can never brick the
   rebirth; `CauldronRegistry.sol:1126` makes that call with no try/catch, and the note at
   `CauldronRegistry.sol:1107` states the opposite.
6. `claimByBurn` — the header at `CauldronRegistry.sol:44` names the migration entry `claimTokens(gen)`; the
   code exposes `claimByBurn` (`CauldronRegistry.sol:1225`) and `claimByBurnUpTo` (`CauldronRegistry.sol:1263`).
7. `_forwardToExt` — comment at `CauldronRegistry.sol:1773` says the fallback delegatecalls any unknown selector
   to the facet; the contract declares only `receive` (`CauldronRegistry.sol:554`), which the note at
   `CauldronRegistry.sol:1410` also states.
8. `floorClaimableNow` / `legCount` — `RedemptionExt.sol:646` and `CauldronBase.sol:488` say these are reached
   "through the registry's fallback"; they are explicit stubs at `CauldronRegistry.sol:1418`, `:1423`, `:1428`.
9. `_flushLegacyAtRelaunch` — the NatSpec at `CauldronRegistry.sol:1479` documents a hook-only recorder; no such
   function is declared, and the next declaration is the private helper at `CauldronRegistry.sol:1494`.
10. `_seedGeneration` — comment at `CauldronRegistry.sol:1660` says BOTH genesis and relaunch use the
    green-candle seed; `CauldronRegistry.sol:1723` takes a different library entry whenever a seeder is set and
    `CauldronRegistry.sol:1722` is non-zero.
11. `unlockCallback` — comment at `CauldronRegistry.sol:1752` says the callback is accepted only while a
    RELAUNCH buy is armed; `CauldronRegistry.sol:1760` accepts it whenever the flag is set, and ignition sets it
    too (`CauldronRegistry.sol:737`, `:1721`).
12. `CauldronToken` constructor — `CauldronToken.sol:29` declares a fixed 777 million supply constant;
    `CauldronToken.sol:46` mints whatever the deployer passes and never compares the two.
13. `CauldronToken.burn` — `CauldronToken.sol:56` lists "unclaimed migration leftovers" as a use; the registry
    records that path as obsolete at `CauldronRegistry.sol:1358` and no such caller remains.
14. `IDeathChecker.isDead` — `IDeathChecker.sol:13` says the hook OWNER points the hook at a new checker;
    `CauldronHook.sol:1850` accepts the registry as well.

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
| 0 | deploy → wiring | deployer | constructor `CauldronRegistry.sol:156`; writes `poolManager` `:165`, `positionManager` `:166`, `hook` `:167`, `emergencyAdmin` `:169`, `emergencyDelay` `:170`, allows native quote `:173`, `:174` |
| 1 | wiring (`summoned == false`) | owner | `setRedemptionExt` `:182` (one-shot), `setFactory` `:571`, `setGovernor` `:561`, `setGenesisBonus` `:607`, `setAirdropReserve` `:622`, `setPrimeFunder` `:631`, `setIgniter` `:396`, `setCollectionLedger` `:1473`, `setSeeder` `:309`, `setSeedWindow` `:332`, `setReserveCeiling` `:195`, `setAllowedQuote` `:290` |
| 2 | wiring → generation 1 | owner OR igniter (`:677`), one-shot at `:678` | `summoned = true` `:681`, `currentGeneration = 1` `:682`, `lastSummonAt` `:683`, token `:692`/`:693`, genesis sizing `:705`/`:706`, airdrop `:715`, seed `:724`, prime buy `:732`-`:739`, collection `:743` |
| 3 | live generation | anyone | migration `:1225`, `:1263`, `:1340`; OG redemption `:1383`, `:1389`, `:1395`, `:1401`; collection floor `:1508`, `:1529`; rotation `:238`, `:262` |
| 4 | live → eligible for rebirth | state only: hook says dead `:779`, grace elapsed `:783`, governor holds proposals `:787` | — |
| 5 | rebirth | anyone (`relaunch` `:767`) | perp force-close `:801`; LP teardown `:804`; burn `:811`; ticket drain `:822`; `currentGeneration + 1` `:839`; `lastSummonAt` `:840`; winner `:849`; quote narrowed `:897`; token `:916`-`:918`; funding `:948`; solvency `:976`; `markConsumed` `:977`; `generationQuote` `:982`; proposer + parent `:987`/`:988`; reserve sizing `:1001`-`:1057`; seed `:1065`; collection `:1072`-`:1075`; curve `:1080`; perp re-arm `:1085` |
| 5a | quote of the newborn | the winning proposal, narrowed three times and never allowed to revert | allowlist `:897`, mining fallback `:916`, funding narrowing `:948`, recorded `:982` |
| 5b | seed-buy window | `_seedGeneration` | armed `:1721`, cleared `:1734`; ignition also arms it at `:737`/`:739`; the only consumer is `unlockCallback` `:1760` |
| 6 | emergency window | emergencyAdmin arms `:403`; guardian may cancel `:422` | consumed once per action at `:391` |
| 7 | terminal / handoff | emergencyAdmin, armed + timelocked | `emergencyWithdrawLP` `:451`, `emergencySweep` `:464`, `rescueSeeder` `:321`, `migrateToSuccessor` `:516` (pointer set at `:481`) |
| 8 | migration mode switch | emergencyAdmin | `setClaimGate` `:500` — restricting consumes a timelock at `:501`, restoring is instant |

Generation 1 is always native-quoted: nothing writes `generationQuote[1]`, and the mapping's zero default is
what the pool is built against (`CauldronRegistry.sol:694`-`:696`). `currentGeneration` advances at `:839`
BEFORE the new token exists, so a revert after that point rolls the whole rebirth back.

## Extra 2 — registry → facet forwarding (which side holds the gate)

Every forwarder's body is `_forwardToExt()` (`CauldronRegistry.sol:1451`), which rejects an unset target at
`:1453`, copies the full calldata at `:1455`, DELEGATECALLs at `:1456` and bubbles the result at `:1457`.
There is no fallback (`CauldronRegistry.sol:554`), so an un-stubbed facet function is unreachable.

| forwarder (registry) | facet function | gate side |
|---|---|---|
| `rotateSlice` `:238` | `RedemptionExt.rotateSlice` `:269` → `rotateSliceFrom` `:274` with `fromLeg = 0` | FACET — wiring `:293`, `:302`, envelope `:317`, slice bound `:318` |
| `rotateSliceFrom` `:262` | `RedemptionExt.rotateSliceFrom` `:280` | FACET — same four checks |
| `setRotationWiring` `:272` | `RedemptionExt.setRotationWiring` `:260` | FACET `onlyOwner`, resolved against THIS registry's owner slot |
| `sweepLegProceeds` `:282` | `RedemptionExt.sweepLegProceeds` `:794` | FACET `onlyOwner` |
| `redeemOgFren` `:1383` | `RedemptionExt.redeemOgFren` `:78` | FACET — breaker `:79`, ignition `:80`, OG id range `:83`, ownership `:84` |
| `buyTreasuryOgFren` `:1389` | `RedemptionExt.buyTreasuryOgFren` `:115` | FACET — ignition `:116`, id range `:117`, treasury custody `:119` |
| `donateToReserve` `:1395` | `RedemptionExt.donateToReserve` `:136` | FACET, but ungated: only ignition `:137` and a non-zero amount `:138` |
| `materializeLegacyReserve` `:1401` | `RedemptionExt.materializeLegacyReserve` `:147` | FACET, ungated: ignition `:148` only |
| `floorClaimableNow` `:1418` | `RedemptionExt.floorClaimableNow` `:648` | neither — ungated read (via `_forwardToExtView` `:1441`) |
| `legCount` `:1423` | `RedemptionExt.legCount` `:661` | neither — ungated read |
| `legAt` `:1428` | `RedemptionExt.legAt` `:666` | neither — ungated read; out-of-range reverts on the array access `RedemptionExt.sol:671` |
| `_removeLiquidity` `:1607` (internal, raw `delegatecall`) | `RedemptionExt.recoverLegs` `:699` | REGISTRY — only reachable from relaunch/emergency teardown; the selector is compiler-computed at `CauldronRegistry.sol:63` and a failure is swallowed at `:1608` |

`RedemptionExt.legProceedsOf` (`RedemptionExt.sol:757`) has no stub and therefore no path through the registry.
The facet keeps its own `nonReentrant`, which runs against the registry's shared guard slot, which is why the
forwarders must not carry one (`CauldronRegistry.sol:1375`-`:1378`).

`PoolOps` is the other delegatecall target — a linked library, so it declares no storage of its own and inherits
the registry's layout by construction. Calls: `:687`, `:738`, `:948`, `:1026`, `:1244`, `:1279`, `:1352`,
`:1496`, `:1518`, `:1535`, `:1564`, `:1569`, `:1641`, `:1681`, `:1723`, `:1761`.

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
  (`CauldronBase.sol:284`-`:289`): an immutable resolves against the EXECUTING contract's code and would read as
  zero inside the facet.
- Shared prefix by slot: `0` `_owner` + `nextReserveCeilingOffset` + `summoned` + `_seedBuyUnlocked`;
  `1` `currentGeneration`; `2` `currentToken`; `3`-`11` the per-generation mappings;
  `12` `genesisReserveOutstanding`; `13`-`15` `claimed`/`generationCollection`/`generationVault`;
  `16`-`17` `collectionLedger`/`genesisPending`; `18`-`19` `factory`/`governor`; `20`-`29` the brew and genesis
  parameters; `30` `redemptionPaused` + `guardian`; `31`-`36` `successor`, `claimGate`, `airdropWallet`,
  `airdropReserve`, `primeBuyEth`, `primeFunder`; `37`-`39` `emergencyReadyAt`, `lastSummonAt`, `minLifetime`;
  `40` `autoMigrate` (the end of the documented baseline, `CauldronBase.sol:278`);
  `41`-`44` `poolManager`, `positionManager`, `hook`, `redemptionExt`; `45` `seeder` + `nextSeedWindow`;
  `46` `igniter`; `47`-`53` `allowedQuote`, `generationQuote`, `quoteRotator`, `treasuryGovernor`, `quoteScale`,
  `generationLegs`, `legProceeds`.
  (The cache reports `igniter` at slot 46 and `nextSeedWindow` packed at slot 45 offset 20, one slot lower than
  the comments at `CauldronBase.sol:299` and `:313` claim.)
- `CauldronRegistry`'s own additions are code-only and therefore layout-neutral: `RECOVER_LEGS`
  (`CauldronRegistry.sol:63`), `emergencyAdmin` (`:126`), `emergencyDelay` (`:128`), `RELAUNCH_TAIL_RESERVE`
  (`:139`), `RELAUNCH_TICKETS` (`:142`). The facet never reads them.

---

## I. Function inventory

**CauldronRegistry**

| line | signature | authority | value effect |
|---|---|---|---|
| 156 | `constructor( address _poolManager, address _positionManager, address _hook, address _emer...` | deployer | NONE |
| 182 | `function setRedemptionExt(address ext) external onlyOwner` | owner | NONE |
| 195 | `function setReserveCeiling(int24 offset) external onlyOwner` | owner | NONE |
| 238 | `function rotateSlice(uint16, uint256, PoolKey calldata) external returns (uint256, uint256)` | anyone at the registry; the facet holds the gate (RedemptionExt.rotateSliceFrom requires rotation wiring pl... | NONE in this stub |
| 262 | `function rotateSliceFrom(uint8, uint16, uint256, PoolKey calldata) external returns (uint...` | anyone at the registry; the facet holds the gate (RedemptionExt.rotateSliceFrom requires rotation wiring pl... | NONE in this stub |
| 272 | `function setRotationWiring(address, address) external` | owner (the gate is on the facet: RedemptionExt.setRotationWiring is onlyOwner and runs against this registr... | NONE |
| 282 | `function sweepLegProceeds(address, address) external returns (uint256)` | owner (the gate is on the facet: RedemptionExt.sweepLegProceeds is onlyOwner) | NONE in this stub |
| 290 | `function setAllowedQuote(address quote, bool allowed, uint256 scale) external onlyOwner` | owner | NONE |
| 309 | `function setSeeder(address _seeder) external onlyOwner` | owner | NONE |
| 321 | `function rescueSeeder() external onlyEmergency timelocked nonReentrant` | emergencyAdmin | receives native and/or token back from the seeder through `rescue` (line 324) |
| 332 | `function setSeedWindow(uint64 window) external onlyOwner` | owner | NONE |
| 341 | `function enchantFee() external view returns (uint256)` | anyone | NONE |
| 345 | `modifier onlyEmergency()` | internal (callers: rescueSeeder, armEmergency, setRedemptionPaused, setEnchantFeeMult, emergencyWithdrawLP,... | NONE |
| 354 | `modifier timelocked()` | internal (callers: rescueSeeder, emergencyWithdrawLP, emergencySweep, migrateToSuccessor) | NONE |
| 388 | `function _consumeTimelock() private` | internal (callers: timelocked, setClaimGate) | NONE |
| 396 | `function setIgniter(address who) external onlyOwner` | owner | NONE |
| 402 | `function armEmergency() external onlyEmergency` | emergencyAdmin | NONE |
| 410 | `function setGuardian(address who) external` | emergencyAdmin or owner | NONE |
| 420 | `function vetoEmergency() external` | guardian | NONE |
| 435 | `function setRedemptionPaused(bool paused) external onlyEmergency` | emergencyAdmin | NONE |
| 444 | `function setEnchantFeeMult(uint256 bps) external onlyEmergency` | emergencyAdmin | NONE |
| 451 | `function emergencyWithdrawLP(uint256 gen) external onlyEmergency timelocked nonReentrant` | emergencyAdmin | ERC20 transfer of the generation token `tok` to the emergency admin (line 454) |
| 464 | `function emergencySweep(address token) external onlyEmergency timelocked nonReentrant` | emergencyAdmin | sends the registry's whole native balance to `emergencyAdmin` (line 466) |
| 481 | `function setSuccessor(address _successor) external onlyEmergency` | emergencyAdmin | NONE |
| 500 | `function setClaimGate(address gate) external onlyEmergency` | emergencyAdmin | NONE |
| 516 | `function migrateToSuccessor() external onlyEmergency timelocked nonReentrant` | emergencyAdmin | ERC721 ownership transfer of the two live positions out of `positionManager` (line 524) |
| 554 | `receive() external payable` | anyone | receives native through `receive` (line 554) |
| 561 | `function setGovernor(address _governor) external onlyOwner` | owner | NONE |
| 566 | `function setMinLifetime(uint256 _seconds) external onlyEmergency` | emergencyAdmin | NONE |
| 571 | `function setFactory(address _factory) external onlyOwner` | owner | NONE |
| 576 | `function setNftMaxSupply(uint256 _max) external onlyOwner` | owner | NONE |
| 583 | `function setRoyalty(address _dividend, uint96 _bps) external onlyOwner` | owner | NONE |
| 591 | `function setGenesisMetadata(MetadataMode mode, string calldata baseURI, address renderer)...` | owner | NONE |
| 607 | `function setGenesisBonus(address _mifrens, uint256 _bonusBps, uint256 _shares) external o...` | owner | NONE |
| 622 | `function setAirdropReserve(address _wallet, uint256 _amount) external onlyOwner` | owner | NONE |
| 631 | `function setPrimeFunder(address who) external onlyOwner` | owner | NONE |
| 641 | `function fundPrimeBuy() external payable` | primeFunder | receives native, accumulated into `primeBuyEth` (line 643) |
| 647 | `function sweepPrimeBuy() external` | primeFunder | sends native equal to `amt` back to the funder (line 651) |
| 668 | `function summon() external payable nonReentrant returns (address token, PoolId poolId)` | owner or igniter | receives native as the entire genesis pairing, which `_seedGeneration` places into the pool (line... |
| 767 | `function relaunch() external nonReentrant returns (address token, PoolId poolId)` | anyone | receives the recovered quote and token of the dying generation through `_removeLiquidity` (line 804) |
| 1094 | `function _perpHousekeep(bool sync) private` | internal (callers: relaunch) | NONE |
| 1135 | `function _deployCollection( uint256 gen, string memory name, string memory symbol, Metada...` | internal (callers: summon, relaunch) | NONE |
| 1184 | `function _continueMiFrens(uint256 gen) private` | internal (callers: relaunch) | NONE |
| 1225 | `function claimByBurn(uint256 fromGen, uint256 amount) external returns (uint256 claimedAm...` | anyone (holders of a previous generation's token); blocked for ordinary callers while a vesting gate is set | burns the caller's previous-generation balance and releases the same amount of the live token out... |
| 1263 | `function claimByBurnUpTo(uint256 fromGen, uint256 maxAmount) external returns (uint256 cl...` | anyone (holders of a previous generation's token); blocked for ordinary callers while a vesting gate is set | burns up to the caller's balance of the previous generation and releases the same amount of the l... |
| 1300 | `function enableAutoMigrate() external payable` | anyone (free for any MiFren holder, otherwise a fee is required) | receives native: the opt-in fee is required only when the caller holds no fren, checked at `AUTO_... |
| 1328 | `function disableAutoMigrate() external` | anyone (for their own wallet only) | NONE |
| 1340 | `function autoMigrateBatch(uint256 fromGen, address[] calldata holders) external nonReentrant` | anyone (permissionless keeper) | burns each opted-in holder's whole previous-generation balance and releases the same amount of th... |
| 1383 | `function redeemOgFren(uint256) external returns (uint256)` | anyone holding a genesis fren; the facet holds the gate (RedemptionExt checks OG ownership and the redempti... | NONE in this stub |
| 1389 | `function buyTreasuryOgFren(uint256) external returns (uint256)` | anyone; the facet holds the gate (the fren must currently sit in this registry's treasury) | NONE in this stub |
| 1395 | `function donateToReserve(uint256) external` | anyone | NONE in this stub |
| 1401 | `function materializeLegacyReserve() external returns (uint256)` | anyone (permissionless keeper) | NONE in this stub |
| 1418 | `function floorClaimableNow() external returns (bool, uint256)` | anyone | NONE |
| 1423 | `function legCount(uint256) external returns (uint256)` | anyone | NONE |
| 1428 | `function legAt(uint256, uint256) external returns (address, uint256, PoolKey memory)` | anyone | NONE |
| 1441 | `function _forwardToExtView() private` | internal (callers: floorClaimableNow, legCount, legAt) | NONE |
| 1451 | `function _forwardToExt() private` | internal (callers: rotateSlice, rotateSliceFrom, setRotationWiring, sweepLegProceeds, redeemOgFren, buyTrea... | NONE directly |
| 1473 | `function setCollectionLedger(address ledger) external onlyOwner` | owner | NONE |
| 1494 | `function _flushLegacyAtRelaunch(uint256 oldGen, address oldToken) private` | internal (callers: relaunch) | NONE at this level |
| 1508 | `function recycleCollectionNFT(uint256 gen, uint256 tokenId) external nonReentrant returns...` | anyone owning the collection NFT (ownership enforced in the library) | releases the collection's floor entitlement in the LIVE generation's token out of the shared rese... |
| 1529 | `function buyCollectionNFT(uint256 gen, uint256 tokenId) external nonReentrant returns (ui...` | anyone (the NFT must currently sit in this registry's treasury) | pulls twice the NFT's floor in the live token from the buyer into the reserve and hands the NFT o... |
| 1552 | `function _removeLiquidity(uint256 gen) private returns (uint256 ethRecovered, uint256 tok...` | internal (callers: relaunch, emergencyWithdrawLP) | recovers both sides of the active and reserve positions into this registry through `removeAll` (l... |
| 1626 | `function _deployToken( string memory name, string memory symbol, uint256 gen, address wan...` | internal (callers: summon, relaunch) | NONE |
| 1671 | `function _createPoolAndSeedWithBuy( address token, uint256 activeTokens, uint256 ethAmoun...` | internal (callers: _seedGeneration) | pays the whole funded amount and the active token tranche into the new pool, then buys the reserv... |
| 1703 | `function _seedGeneration( address token, uint256 activeTokens, uint256 ethAmount, uint256...` | internal (callers: summon, relaunch) | hands the active tranche plus the funding to either the streaming seeder or the atomic green-cand... |
| 1740 | `function _recordSeed(SeedResult memory r, uint256 gen) private returns (PoolId poolId)` | internal (callers: _seedGeneration, _createPoolAndSeedWithBuy) | NONE |
| 1758 | `function unlockCallback(bytes calldata data) external returns (bytes memory)` | poolManager, and only while the seed-buy window is armed | spends this registry's quote side and receives the bought token, inside `executeBuy` (line 1761) |
| 1768 | `function hasClaimed(uint256 generation_, address holder) external view returns (bool)` | anyone | NONE |

**CauldronToken**

| line | signature | authority | value effect |
|---|---|---|---|
| 36 | `constructor( string memory _name, string memory _symbol, uint256 _generation, address _re...` | deployer (the registry, acting through the delegatecalled PoolOps deploy) | NONE in native terms |
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
| 49 | `function priceAt(uint256 k, uint256 base, uint256 step) external view returns (uint256 cost)` | anyone (view on a pluggable module) | NONE |

**IFeeRouter (declared in IPolicies.sol)**

| line | signature | authority | value effect |
|---|---|---|---|
| 70 | `function route(uint256 feeAmount, address guild, address vault, uint256 guildBps, uint256...` | anyone (view on a pluggable module) | NONE |
