# Cauldron — The generation lifecycle

What this document covers: how a generation is born, how it lives, how it is
declared dead, and exactly what happens to value at each step.

Every claim carries a `file:line` read at the commit in the Verification footer.

---

## 1. The state machine

```
  [UNWIRED]
      |  owner wires governor, factory, royalty, genesis bonus, metadata,
      |  redemption facet   (CauldronRegistry.sol:579,589,601,625,609,184)
      v
  [PRESALE]                            MiFrensGenesis.mint()
      |                                (MiFrensGenesis.sol:262)
      |
      +--- deployer cancels ---> [CANCELLED] --> refund() forever
      |    (MiFrensGenesis.sol:289)              (MiFrensGenesis.sol:300)
      |
      |  minted == GENESIS_SUPPLY
      v
  [ARMED]                              soldOut() == true
      |                                (MiFrensGenesis.sol:604)
      |  igniteCauldron()  ->  registry.summon{value: balance}()
      |  (MiFrensGenesis.sol:575,595)     (CauldronRegistry.sol:686)
      v
  [LIVE gen N] ------------------------------------------------+
      |  swaps: hook takes a fee, records volume,              |
      |         accrues relaunchETH, forges NFT credit         |
      |  (CauldronHook.sol:1555, :286)                         |
      |                                                        |
      |  holders of gens < N may claimByBurn 1:1 at any time   |
      |  (CauldronRegistry.sol:1243)                           |
      |                                                        |
      |  24h volume < deathThreshold  AND                      |
      |  now >= lastSummonAt + minLifetime  AND                |
      |  governor.hasProposals()                               |
      v                                                        |
  [DEAD gen N]                                                 |
      |  anyone calls relaunch()  (CauldronRegistry.sol:785)   |
      |                                                        |
      |  ONE TRANSACTION:                                      |
      |   force-close perps -> recover LP -> burn recovered    |
      |   -> resolve tickets -> deploy token N+1 -> decide     |
      |   funding -> markConsumed -> seed pool N+1 -> deploy   |
      |   collection -> re-arm perps                           |
      v                                                        |
  [LIVE gen N+1] ---------------------------------------------+

  Break-glass, orthogonal to the above:
  [ANY] --armEmergency--> [ARMED EMERGENCY] --guardian veto--> [ANY]
                                |  (CauldronRegistry.sol:420, :438)
                                |  after emergencyDelay
                                v
                      emergencyWithdrawLP / emergencySweep /
                      migrateToSuccessor / setClaimGate / rescueSeeder
                      (CauldronRegistry.sol:469,482,534,518,339)
```

---

## 2. Every transition, its trigger and its gate

| # | From → To | Function | Who may call | Gates (each reverts) |
|---|---|---|---|---|
| 1 | Presale → Cancelled | `cancelPresale()` `MiFrensGenesis.sol:289` | deployer only `:290` | not finalized `:291`; not already cancelled `:292` |
| 2 | Cancelled → (refunds) | `refund()` `MiFrensGenesis.sol:300` | anyone, for their own `paid` | `cancelled` `:301`; `paid > 0` `:303` |
| 3 | Presale → Armed | `mint(quantity)` `MiFrensGenesis.sol:262` | anyone | not finalized `:263`; not cancelled `:264`; `quantity > 0` `:265`; `minted+q <= GENESIS_SUPPLY` `:266`; exact `PRICE*q` `:267`; per-wallet cap `:268` |
| 4 | Armed → Live gen 1 | `igniteCauldron()` `MiFrensGenesis.sol:575` | anyone, unless `finalizer` set `:591` | registry wired `:576`; not finalized `:577`; **not cancelled** `:587`; sold out `:588` |
| 5 | (same) | `summon()` `CauldronRegistry.sol:686` | `owner()` **or** `igniter` `:695` | not already summoned `:696`; `msg.value != 0` `:697` |
| 6 | Live → Dead (observation) | `hook.isDead(poolId)` `CauldronHook.sol:1628` | view | pool is tracked `:1629`; summed 24h volume of the primary **and its linked siblings** `< deathThreshold` `:1634-1647` |
| 7 | Dead → Live gen N+1 | `relaunch()` `CauldronRegistry.sol:785` | **anyone** | summoned `:790`; `hook.isDead` `:797`; `now >= lastSummonAt + minLifetime` `:801`; governor wired and `hasProposals()` `:805`; funding `> 0` `:994`; perp book cleared (propagates from `forceClosePerps`) `:1142-1145` |
| 8 | Live → migrated holder | `claimByBurn(fromGen, amount)` `CauldronRegistry.sol:1243` | any holder | `0 < fromGen < currentGeneration` `:1247`; no `claimGate`, or caller is the gate or the perp engine `:1252`; token known `:1256`; balance covers `amount` `:1257`; reserve can cover it `PoolOps.sol:1283` |
| 9 | Live → migrated batch | `autoMigrateBatch(fromGen, holders)` `CauldronRegistry.sol:1346` | **anyone** | `0 < fromGen < currentGeneration` `:1350`; `claimGate == 0` `:1354`; token known `:1356`. Per holder it *skips* rather than reverts: not opted in, zero balance, or reserve short (`PoolOps.sol:1300-1314`) |
| 10 | Any → armed emergency | `armEmergency()` `CauldronRegistry.sol:420` | emergency admin `:363-366` | none; sets `emergencyReadyAt = now + emergencyDelay` `:421` |
| 11 | Armed emergency → cancelled | `vetoEmergency()` `CauldronRegistry.sol:438` | guardian only `:439` | none |
| 12 | Armed emergency → executed | `emergencyWithdrawLP` `:469`, `emergencySweep` `:482`, `migrateToSuccessor` `:534`, `rescueSeeder` `:339` | emergency admin | must be armed, and the delay elapsed `:407-409` |

### Two properties of the timelock worth stating plainly

**Arming is always mandatory**, even when `emergencyDelay == 0`
(`CauldronRegistry.sol:407`). This is load-bearing: the redemption exit guarantee
is keyed on `emergencyReadyAt` being non-zero
(`cauldron/CauldronBase.sol:415-417`). Redemption is blocked only when
`redemptionPaused && emergencyReadyAt == 0` — so the instant any custody action is
armed, the exit is forced back open and holders can leave at floor before anything
moves.

**`setClaimGate` is asymmetrically timelocked.** Setting a non-zero gate (which
closes instant migration for every ordinary holder) consumes the timelock;
clearing it back to zero does not (`CauldronRegistry.sol:518-522`).

---

## 3. Phase by phase — what happens to your money

### Phase A — Presale

- **Where the ETH is:** in `MiFrensGenesis`. `mint()` requires exact payment
  (`MiFrensGenesis.sol:267`) and records it per address in `paid`
  (`:270`).
- **The only two exits:** `refund()` after a cancel (`:300`), or
  `igniteCauldron()`, which forwards `address(this).balance` into
  `registry.summon{value: bal}()` (`:594-595`). There is no owner withdraw
  function in the contract.
- **What you get:** an OG MiFren, ids `1..GENESIS_SUPPLY`, revealed at mint
  (`:278`). It is `ERC721Votes` and auto-delegates to its holder on first receipt
  (`:669-671`), so it carries governance weight with no separate delegate
  transaction.
- **A cancelled sale cannot be ignited.** `igniteCauldron` reverts on `cancelled`
  (`:587`), so the refund pot can never be spent into liquidity.

### Phase B — Ignition (`summon`)

The presale's whole balance becomes generation 1's liquidity. In order
(`CauldronRegistry.sol:699-763`):

1. `summoned = true`, `currentGeneration = 1`, `lastSummonAt = now` (`:699-701`).
2. Name/symbol come from the hard-coded creature table — generation 1 is
   `("Gnomeland","GNOME")` (`PoolOps.sol:153-161`) — branded
   `"<name> by Magic Internet Frens"` (`cauldron/ICauldron.sol:35-40`).
3. The token is deployed; its constructor mints all 777M to the registry
   (`CauldronToken.sol:46`). `generationQuote[1]` is left at zero = native ETH,
   deliberately (`CauldronRegistry.sol:712-714`).
4. **Genesis bonus** (opt-in): a share of supply, capped at 3000 bps
   (`:630`), is set aside as `genesisReserveOutstanding` — a number, not a
   transfer (`:721-726`). It lives inside the reserve position and backs the OG
   redemption floor.
5. **OG airdrop reserve** (opt-in): capped at 2000 bps of total supply (`:643`),
   this is the one tranche that leaves the LP — it is transferred outright to
   `airdropWallet` (`:731-734`).
6. `activeTokens = GEN1_ACTIVE_TOKENS` = 80% of supply
   (`cauldron/CauldronBase.sol:160`); the rest, minus the airdrop, is the reserve
   (`:729-734`).
7. The pool is created and seeded (see `03-GENESIS-AND-SEEDING.md`).
8. **Prime buy** (opt-in): owner-supplied personal ETH, spent on a real
   first-block market buy whose output goes to the airdrop wallet
   (`:750-758`). It is spent *after* the seed, so it hits the intended price.
9. The genesis NFT collection is deployed and the hook is pointed at it
   (`:761`).

**Your money at the end of Phase B:** the presale ETH is inside the active V4
position. 80% of token supply is tradeable depth; the remaining ~20% (less the
airdrop) sits out of range in the reserve position, claimable only by burning.

### Phase C — Live

- **Every swap pays a fee**, taken by the hook via `afterSwap` return deltas
  (`CauldronHook.sol:113-116`). The default flat rate is 300 bps when no tiered
  NFT contract is wired (`:234`), hard-capped at `MAX_TAX_BPS = 1000` (10%)
  (`:153`).
- **The fee is split.** Guild share defaults to 1500 bps of the fee
  (`CauldronHook.sol:477`, setter capped at 1500 `:2095-2098`); the proposer slice
  defaults to 50 bps with a hard ceiling of 500 (`:491-492`); the floor share is
  `floorBps`, defaulting to 10000 (`:458`). The remainder accrues as
  `relaunchETH` (`:286`) — this is what funds the next generation.
- **Volume is recorded** in 24 hourly buckets. `getVolume24h` returns 0 outright
  if the pool has not been touched for more than a day
  (`CauldronHook.sol:1555-1563`).
- **A generation's volume is the sum across its pools**, not one pool's, so a
  treasury split across two quotes is not declared dead because trading moved to
  the sibling. Up to `MAX_SIBLINGS = 9` linked pools (`CauldronHook.sol:770`,
  `:1634-1638`).
- **NFTs are forged from volume**, at `volumePerNFT` credit each; the winning
  proposal's `volumePerNFT` is applied to the live curve at relaunch
  (`CauldronRegistry.sol:1098`; `CauldronHook.sol:2141-2147`).
- **You can migrate at any time**, including while the generation is alive — the
  only requirement is that `fromGen < currentGeneration`
  (`CauldronRegistry.sol:1247`).
- **The floor vault holds nothing.** Both collection-deployment paths call
  `hook.setVault(address(0))` (`CauldronRegistry.sol:1189`, `:1213`), so the fee
  floor-share becomes token buy pressure instead of ETH in the vault.
  `CauldronVault.redeem` therefore reverts `UnifiedFloorActive()`
  (`cauldron/CauldronVault.sol:102`), and the contract's own NatSpec says so
  (`:85-93`). The vault is still load-bearing: `crystallizeCollection` reads its
  `outstanding()` to size the collection's entitlement at death. The live floor
  is instead `CauldronRegistry.recycleCollectionNFT` (`:1514`), paid in the live
  token out of the shared reserve.

### Phase D — Death

Death is an observation, not a transaction. `isDead` is a view
(`CauldronHook.sol:1628`). Nothing changes state when a pool dies; the pool keeps
trading normally. Death only unlocks `relaunch()`.

The rule is pluggable: if `deathChecker` is set, `isDead` delegates to it, and
falls back to the built-in `vol < deathThreshold` if that module reverts
(`CauldronHook.sol:1639-1646`). The module is set by the registry or the hook
owner (`CauldronHook.sol:1907-1911`).

`deathThreshold` and the oracle that denominates it are set together in one call,
because the threshold is meaningless without knowing its units
(`CauldronHook.sol:1795-1807`).

### Phase E — Relaunch

The sequence, with what moves at each step
(`CauldronRegistry.sol:785-1106`):

| Step | What happens | Where the value goes | Cite |
|---|---|---|---|
| 1 | Gates checked | nothing moves | `:790-805` |
| 2 | `CauldronDied` emitted; the old token is **not** frozen | nothing | `:810` |
| 3 | Every open perp force-closed **while the old pool is still alive** | settlement swaps against the dying pool | `:819`, `:1142-1145` |
| 4 | `_removeLiquidity(oldGen)`: active position, reserve position, progressive-seeder bands, and rotated legs | quote + tokens land at the registry | `:822`, `:1558-1620` |
| 5 | Recovered dead-generation tokens burned | supply destroyed | `:828-830` |
| 6 | Up to `RELAUNCH_TICKETS = 50` matured NFT tickets resolved, gas-capped and `try/catch`'d | pending winners mint while the floor is still funded | `:144`, `:839-841` |
| 7 | `currentGeneration = oldGen + 1`, grace clock restarts | nothing | `:856-858` |
| 8 | `governor.winner()` read; its quote re-checked against the live allowlist and its NFT supply clamped | nothing | `:867`, `:915`, `:925-927` |
| 9 | New token deployed (plain CREATE, mined above `QUOTE_WATERMARK`) | 777M minted to the registry | `:934`; `PoolOps.sol:682-719` |
| 10 | `PoolOps.seedFunding` decides the newborn's quote and pulls the funding | the dying floor vault is closed and swept; the hook's native and/or per-asset reserve is released to the registry | `:966-972`; `PoolOps.sol:1000-1093` |
| 11 | **`if (totalETH == 0) revert NoLiquidityToSeed()`** — the last safe revert | nothing | `:994` |
| 12 | **`governor.markConsumed(winId)`** — past this line a revert is fatal | nothing | `:995` |
| 13 | `generationQuote[newGen]`, proposer, parent recorded; hook's proposer slice repointed | nothing | `:1000-1007` |
| 14 | Reserve sized: `genesisPending` folded into the OG floor; active band = recovered tokens minus unclaimed genesis minus legacy entitlement, each clamped | nothing moves yet | `:1019-1075` |
| 15 | Pool created and seeded — green candle by default, progressive if armed | funding becomes the active position; the reserve is bought out and re-parked out of range | `:1083`; `PoolOps.sol:448-488` |
| 16 | NFT collection: iteration 2 **continues** MiFrens; all others deploy fresh | a new collection + vault (+ royalty router) | `:1090-1094` |
| 17 | `hook.setNftCurveFrom(volPerNFT)` | nothing | `:1098` |
| 18 | Perp engine re-armed on the new token; its inventory migrates 1:1 | engine inventory migrates out of the reserve | `:1103`, `:1112-1115` |

**What happens to your money across a relaunch, as a holder:**

- Your **old tokens are untouched.** They are not burned, not frozen, not
  confiscated. Their pool is drained, so they become illiquid, but transfer still
  works (`CauldronToken.sol:18-21`).
- Your **claim is preserved as a 1:1 right** on the new generation's reserve
  position. Nothing is minted for it; the reserve is pre-sized from
  `TOTAL_SUPPLY - newActive` (`CauldronRegistry.sol:1075`).
- If you opted into auto-migration, a keeper may migrate you at a moment you did
  not choose. That is exactly what the opt-in authorises
  (`:1302-1316`), and it is revocable for free at any time (`:1334-1337`).
- Your **OG genesis floor rises** across the rebirth: `genesisPending` (the OG
  share of iteration-2 live buybacks) is folded into
  `genesisReserveOutstanding` *before* the reserve is sized, so the new reserve
  covers the grown entitlement (`:1019-1021`).
- If the reserve cannot cover migration plus the OG floor plus the legacy
  entitlement, you get a `ReserveShortfall` event and first-come-first-served
  claims (`:1035`, `:1060`). This is observable, not silent, and it is not
  repaired automatically — it is repaired by a future generation with a larger
  recovery.

### Phase F — Migration to the successor (the V2 exit)

This is not a generation transition; it is a controller handoff.

1. `setSuccessor(addr)` — emergency admin, no timelock, pointer only
   (`CauldronRegistry.sol:499`).
2. `armEmergency()`, wait `emergencyDelay` (`:420`). During this window the
   redemption exit is forced open (`CauldronBase.sol:415-417`) and the guardian
   may veto (`:438`).
3. `migrateToSuccessor()` (`:534`). It **transfers ownership of the position
   NFTs**, it does not withdraw liquidity — the Uniswap positions and therefore
   the price are untouched (`:539-543`). A live progressive seeder is unwound
   first so the streamed book is not stranded behind the outgoing controller
   (`:553-556`). Loose token and ETH balances follow (`:559-568`).

Treasury-held frens, the MiFrens custody pointer and the hook's registry pointer
are re-homed separately. The hook's controller swap is itself a two-step,
7-day-delayed action (`CauldronHook.sol:263`, `:1964`, `:1984`).

---

## 4. State variables that define a generation

All live on `CauldronBase` and are shared with the `RedemptionExt` facet.

| Variable | Meaning | Cite |
|---|---|---|
| `summoned` | Genesis has fired; one-shot | `CauldronBase.sol:179` |
| `currentGeneration` / `currentToken` | The live generation number and its token | `:183-184` |
| `generationToken[g]` | g's ERC-20 | `:187` |
| `generationProposer[g]` | Who authored the winning brew | `:189` |
| `generationParent[g]` | The generation g descended from (V2 branch seam; linear in V1) | `:192` |
| `generationPoolId[g]` / `generationPoolKey[g]` | g's primary pool | `:194`, `:196` |
| `generationPositionId[g]` | g's **active** position NFT; **0 for a progressive generation** | `:198` |
| `generationReservePositionId[g]` + `reserveTickLower/Upper[g]` | g's out-of-range reserve band | `:201-204` |
| `generationCollection[g]` / `generationVault[g]` | g's NFT collection and floor vault | `:211`, `:213` |
| `generationQuote[g]` | What g is priced in; `address(0)` = native ETH | `:340` |
| `generationLegs[g]` | Every pool g holds liquidity in **beyond** the primary | `:460` |
| `genesisReserveOutstanding` | The OG redemption floor pot, carried forward every generation | `:206` |
| `lastSummonAt` / `minLifetime` | Grace clock; default 1 hour | `:274`, `:276` |

---

## 5. Known limitations of this lifecycle

- **`hasClaimed()` always returns false.** The `claimed[gen][holder]` mapping
  (`CauldronBase.sol:209`) has exactly one reader,
  `CauldronRegistry.hasClaimed` (`:1774-1776`), and **no writer anywhere in the
  non-test tree**. It is a dead storage slot retained for layout stability; the
  view built on it is meaningless. Migration is tracked by burning the real old
  balance, not by a flag (`:1344-1345`).
- **A progressive generation has no single active position.**
  `generationPositionId[g] == 0`; the active book is N core positions owned by the
  seeder, recoverable only through `ISeeder.withdrawAll`, which is
  `onlyRegistry` (`CauldronRegistry.sol:1566-1591`;
  `cauldron/CauldronSeeder.sol:565`).
- **Recovery from rotated legs is best-effort.** A leg that cannot be unwound is
  skipped so it does not block the rebirth, and stays recorded for a later
  `recoverLegs(gen)` retry (`CauldronRegistry.sol:1593-1619`, `:290`).
- **`vaultSwept` only counts toward a native rebirth.** It is native wei;
  `PoolOps.seedFunding` reports it only out of the native branch, because the
  other two branches are denominated in something else
  (`PoolOps.sol:1075-1093`). On a non-native rebirth the swept ether lands at the
  registry and does not enter the newborn's book.

---

## Verification

- **Commit documented against:** `880220a`. The tree was under active edit
  throughout this pass — `CauldronHook.sol`, `CauldronBase.sol`,
  `TreasuryGovernor.sol`, `CauldronGovernor.sol`, `LaunchSniper.sol` and
  `CauldronRegistry.sol` all shifted while these documents were written, some by
  90+ lines. Every `file:line` above was mechanically re-mapped and then
  spot-verified against the tree at this commit. `CauldronBase.sol`,
  `TreasuryGovernor.sol`, `LaunchSniper.sol`, `PerpEngine.sol` and `PerpVault.sol`
  still carried uncommitted working-tree edits at the end of the pass, so a later
  commit may shift them again.

- **Disagreements between a prior doc/comment and the code, relevant here:**
  - `CauldronRegistry.sol:1778-1782` claims an unknown-selector fallback exists.
    It does not (`:572` declares only `receive()`); the note at `:1411-1420` is
    correct.
  - `cauldron/PoolOps.sol:247-251` says the progressive entry is "pending a ~450B
    reclaim" and that the registry "will call this ... once its EIP-170 wiring
    lands". The registry calls it today at `CauldronRegistry.sol:1729`.
  - `audit/spec/sections/B_iteration_lifecycle.md` was written against a
    1,736-line `CauldronRegistry.sol`; the file is 1,791 lines at this commit, so
    every line number in that section is shifted. Its *behavioural* claims that I
    re-checked all held.
  - `audit/graph/README.md` states it was generated at commit `39d04e1`. ~30 fix
    commits have landed since; its line numbers are not current.
- **Unverified:** whether the tree compiles at this commit (a `forge build`
  attempted during this pass produced no size output); the exact fee-split
  arithmetic inside `FeeRouteLib` (out of scope); perp force-close internals (out
  of scope).
