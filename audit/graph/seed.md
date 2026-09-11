# Cluster `seed` — function graph

Generated from the decontaminated tree; line numbers identical to the repo.

Source tree: `/tmp/blind-final/contracts/solidity`

| file | lines | nodes |
|---|---|---|
| `cauldron/CauldronSeeder.sol` | 610 | 24 (incl. `IRegistryOwner`) |
| `cauldron/SeedLib.sol` | 146 | 7 |
| `cauldron/ISeeder.sol` | 38 | 6 |
| `cauldron/MigrationVesting.sol` | 307 | 19 (incl. `IVestingRegistry`, `IStakerOracle`) |
| `cauldron/LaunchSniper.sol` | 96 | 8 (incl. `IMiFrensGenesisFinalize`, `IRegistryCurrent`, `IGachaPlay`) |

64 nodes, 0 validator failures. No `unchecked` block and no inline assembly appears in any of the five files.

---

## Cluster extra 1 — the seeding flow, end to end

**Arming (registry owner).** `setSeeder` (CauldronRegistry.sol:309) stores the seeder and mirrors it onto the hook at `hook.setSeeder` (CauldronRegistry.sol:311); `setSeedWindow` (CauldronRegistry.sol:332) sets the stream length, bounded to 60 s … 7 days at (CauldronRegistry.sol:333). The progressive path fires only when both are set — `seeder != address(0) && nextSeedWindow > 0` (CauldronRegistry.sol:1722).

**Who funds.** Nobody funds the seeder directly. `_seedGeneration` (CauldronRegistry.sol:1703) delegatecalls `PoolOps.createAndSeedProgressive` (PoolOps.sol:252), so `address(this)` inside PoolOps *is* the registry: the registry holds ledger A and the seeder's `onlyRegistry` (CauldronSeeder.sol:145) resolves to it (PoolOps.sol:333-334).

**PoolKey and orientation.** Built at (PoolOps.sol:268-274): `currency0 = quote` (address(0) = native ETH), `currency1 = token`, `fee = poolFee`, `tickSpacing`, `hooks = hook`. The registry passes `TICK_SPACING` and `POOL_FEE` (CauldronRegistry.sol:1726), declared as 200 and 0 at (CauldronBase.sol:158) and (CauldronBase.sol:157). The token is deployed to sort above the quote (PoolOps.sol:265). Orientation is spelled out at (SeedLib.sol:21-27): price = tokens per ETH, so **ask (token) bands sit BELOW spot** and **bid (ETH) bands sit ABOVE spot**.

**Non-native quote.** `if (quote != address(0))` (PoolOps.sol:296) degrades the whole generation to the atomic seed and returns at (PoolOps.sol:310) — the seeder is never called, because `startSeed` asserts `msg.value == cfg.ethTotal` (CauldronSeeder.sol:179) and has no ERC20 path for the quote.

**Native path.** `baseTok`/`baseEth` are carved at 15 % (`SEED_BASE_WAD`, PoolOps.sol:145) at (PoolOps.sol:335-336); `_greenCandle` (PoolOps.sol:338) places that base and buys the reserve out of it in the ignition tx. Then `IERC20(token).approve(sp.seeder, activeTokens - baseTok)` (PoolOps.sol:343) and `ISeeder(sp.seeder).startSeed{value: ethAmount - baseEth}` (PoolOps.sol:344) with `baseWad: 0` (PoolOps.sol:348), `seedFloorWad = 0.1e18` (PoolOps.sol:137), `minStepWad = 0.02e18` (PoolOps.sol:138), `bandWidth = 2000` ticks (PoolOps.sol:139).

**Seeder intake.** `startSeed` (CauldronSeeder.sol:175) validates (176-181), writes the whole campaign (183-194), performs a full per-campaign reset (201-213), then **pulls** the token side with `transferFrom(registry, address(this), cfg.tokenTotal)` (CauldronSeeder.sol:215) — the ETH side arrived as `msg.value`. One self-`unlock` at (CauldronSeeder.sol:222) places the floor slice, and `placedWad = cfg.seedFloorWad` (CauldronSeeder.sol:223).

**How liquidity is minted.** Core, not periphery: `poolManager.modifyLiquidity` (CauldronSeeder.sol:401) for the ask band and (CauldronSeeder.sol:407) for the bid band, sized by `getLiquidityForAmount1` (CauldronSeeder.sol:389) and `getLiquidityForAmount0` (CauldronSeeder.sol:394). The optional two-sided full-range base uses `getLiquidityForAmounts` (CauldronSeeder.sol:468) and `modifyLiquidity` (CauldronSeeder.sol:477). Settlement of the net delta is `_settle` (CauldronSeeder.sol:488): token out via `IERC20(token).transfer(address(poolManager), …)` (CauldronSeeder.sol:492) + `settle()` (493); native out via `settle{value:}` (499).

**Salt and position owner.** Every mint uses salt `bytes32(0)` — (CauldronSeeder.sol:402), (CauldronSeeder.sol:408), (CauldronSeeder.sol:426), (CauldronSeeder.sol:478) — so repeat placements into the same tick pair MERGE. The positions are owned by the **seeder itself**, as confirmed by the teardown lookup `getPositionInfo(pid, address(this), r.lo, r.hi, bytes32(0))` (CauldronSeeder.sol:423). `activePositionId` stays 0 for a progressive generation (PoolOps.sol:244-245, CauldronRegistry.sol:1560).

**Streaming.** Keeperless in-swap: the hook's `_maybePoke` (CauldronHook.sol:1047) fires a gas-bounded, result-ignored `call` (CauldronHook.sol:1052) into `pokeInSwap` (CauldronSeeder.sol:307), which is gated on `_key.hooks` (CauldronSeeder.sol:308). Fallback: permissionless `poke` (CauldronSeeder.sol:231), which opens its own unlock (234). The amount is a pure function of elapsed time — `SeedLib.deployedTargetWad` (SeedLib.sol:58) — read at (CauldronSeeder.sol:318) and again at (CauldronSeeder.sol:328).

**Prime buy (ledger C).** `fundPrime` (CauldronSeeder.sol:251) takes external ETH and names `primeTo` (254). Each `poke` spends one tranche via `ACT_PRIME` (CauldronSeeder.sol:241) → `_primeStep` (CauldronSeeder.sol:286): `poolManager.swap` (287), `settle{value: owed}` (298), and `take(_key.currency1, primeTo, got)` (299) — the bought token goes straight to `primeTo`, never into this contract.

**Teardown.** `withdrawAll(to)` (CauldronSeeder.sol:565) is `onlyRegistry`; the registry calls it at (CauldronRegistry.sol:537) on a successor handoff and at (CauldronRegistry.sol:1582) at relaunch, both behind `ISeeder(_seeder).seeding()` (CauldronRegistry.sol:536 / 1581). `_teardown` (CauldronSeeder.sol:417) removes every tracked range (421-429), settles (430), forwards the token balance (435) and the entire native balance (437), records both (438-439) and zeroes ledger C (449-450). `rescue(to)` (CauldronSeeder.sol:597) is the loose-funds-only hatch, reachable from `rescueSeeder` (CauldronRegistry.sol:321).

---

## Cluster extra 2 — the vesting schedules

**Every schedule variable.**

| variable | line | meaning |
|---|---|---|
| `vestWindow` | MigrationVesting.sol:78 | live linear window copied into each NEW grant |
| `MIN_WINDOW` = 1 hours | MigrationVesting.sol:83 | lower bound on `vestWindow` |
| `MAX_WINDOW` = 14 days | MigrationVesting.sol:84 | upper bound on `vestWindow` |
| `Grant.token` | MigrationVesting.sol:91 | the token this grant pays in, pinned at deposit |
| `Grant.total` | MigrationVesting.sol:92 | escrowed amount |
| `Grant.released` | MigrationVesting.sol:93 | already withdrawn |
| `Grant.start` | MigrationVesting.sol:94 | deposit timestamp = vest origin |
| `Grant.window` | MigrationVesting.sol:95 | this grant's duration; 0 = instant |
| `stakerOracle` | MigrationVesting.sol:81 | decides who gets `window = 0` |

Snapshotting: the window is copied at `uint64 w = _isInstant(holder) ? 0 : vestWindow;` (MigrationVesting.sol:190) and the token at (MigrationVesting.sol:192), so retuning at (MigrationVesting.sol:298) or swapping the oracle at (MigrationVesting.sol:304) never repriced an existing grant.

**Claim math** — `_vestedOf` (MigrationVesting.sol:245): `window == 0 → total` (246); `elapsed = now - start` (247); `elapsed >= window → total` (248); otherwise `total * elapsed / window` (249), truncating (rounds toward the escrow). `_release` (MigrationVesting.sol:221) pays `vested - released` (226), raises `released` to `vested` (228) **before** the transfer (230), and prunes a drained grant by swap-pop (235-237).

**Who can create a grant.** `startVest` (MigrationVesting.sol:135) — anyone, for themselves only, since the holder is fixed to `msg.sender` at (MigrationVesting.sol:141). `vestBatch` (MigrationVesting.sol:153) — anyone, for ANY address in the array; the only consent is that address's ERC20 allowance, read at (MigrationVesting.sol:159). Both funnel into `_pullAndVest` (MigrationVesting.sol:169), the sole writer of `_grants` (191).

**Who can revoke a grant.** Nobody. There is no revoke, claw-back, pause or sweep function in the contract; the owner's only powers are `setVestWindow` (MigrationVesting.sol:296) and `setStakerOracle` (MigrationVesting.sol:303), both of which affect FUTURE grants only. DERIVED: an escrowed balance can leave the contract only through `_release`'s transfer (MigrationVesting.sol:230), which always pays the grant's own beneficiary.

**Who can claim.** `claim` (MigrationVesting.sol:206) pays `msg.sender`; `claimFor` (MigrationVesting.sol:213) is permissionless but pays the named `holder` (214) — a keeper can never redirect. Both revert with `NothingToClaim` (208 / 215) when nothing is due; the auto-release inside `startVest` (144) does not.

**Enforcement.** The escrow is only the exclusive route if the registry's `claimGate` points at it — `msg.sender != claimGate && msg.sender != hook.perpEngine()` (CauldronRegistry.sol:1234). The escrow never verifies that it is the configured gate.

---

## Cluster extra 3 — the sniper / launch flow

**Who can call.** `launch` (LaunchSniper.sol:58) is `onlyOwner` (LaunchSniper.sol:65); the owner is set once at `Ownable(_owner)` (LaunchSniper.sol:47) and is transferable/renounceable. Additionally the presale must name this contract as its finalizer, or a bot can ignite first: `if (finalizer != address(0) && msg.sender != finalizer) revert NotAuthorized();` (MiFrensGenesis.sol:581).

**What it does.** (1) precondition `soldOut()` (LaunchSniper.sol:67); (2) `igniteCauldron()` (LaunchSniper.sol:70) → the presale forwards its whole balance to `registry.summon{value: bal}()` (MiFrensGenesis.sol:585), which summons gen 1 and seeds the pool; (3) read the fresh token at `currentToken()` (LaunchSniper.sol:71); (4) **buy** with the entire `msg.value` through `IGachaPlay(gachaRouter).play{value: msg.value}(0, minGnomeOut, 0, openMax)` (LaunchSniper.sol:76); (5) forward the result.

**Where the proceeds go.** The bought token is measured from this contract's own balance at `balanceOf(address(this))` (LaunchSniper.sol:79) — not from the router's return — and sent to the caller-supplied `airdropWallet` (LaunchSniper.sol:80). Anything left behind (a router ETH refund, a stray token) is recoverable only by the owner through `sweep` (LaunchSniper.sol:86), which sends to `owner()` (88 / 91). `receive()` (LaunchSniper.sol:95) accepts ether with no bookkeeping.

**Fee exemption.** The doc requires `setTaxExempt(launchSniper, true)` (LaunchSniper.sol:35); the hook's rule is `taxExempt[_taxedPlayer(sender, hookData)] && isOpener[sender]` (CauldronHook.sol:2384), so the ROUTER must be an opener and the SNIPER must be tax-exempt.

**Selector mismatch (recorded as an observation).** `IGachaPlay.play` is declared with four `uint256` arguments (LaunchSniper.sol:17) and called with four (LaunchSniper.sol:76); the only `play` in the repo is `CauldronGachaRouter.play` with five (CauldronGachaRouter.sol:233). The router declares `receive()` (CauldronGachaRouter.sol:552) but no `fallback`.

---

## A. Value inventory

### CauldronSeeder — storage that holds or counts value

| field | denom | increases | decreases |
|---|---|---|---|
| `ethTotal` (CauldronSeeder.sol:92) | wei (ledger-A ETH budget) | assigned at (189) | overwritten only by the next campaign's (189) |
| `tokenTotal` (CauldronSeeder.sol:93) | raw brew-token units | assigned at (190) | overwritten only at (190) |
| `placedWad` (CauldronSeeder.sol:94) | WAD fraction of the STREAM budget | set to the floor at (223), snapped to the schedule at (330) | reset by the next campaign at (223) |
| `seedFloorWad` (CauldronSeeder.sol:91) | WAD | (188) | — |
| `minStepWad` (CauldronSeeder.sol:95) | WAD | (191) | — |
| `baseWad` (CauldronSeeder.sol:96) | WAD | (192) | — |
| `primeBudget` (CauldronSeeder.sol:137) | wei (ledger C) | `+= msg.value` at (255) | `= 0` at (449) |
| `primeSpent` (CauldronSeeder.sol:138) | wei | `+= owed` at (300) | `= 0` at (450) |
| `primeTo` (CauldronSeeder.sol:139) | recipient address | (254) | never cleared — deliberate, per the note at (447) |
| `ranges` (CauldronSeeder.sol:106) | position inventory | `push` at (476) and (553) | `delete` at (210) and (570) |
| `_lastAsk` / `_lastBid` (109 / 110) | per-side fallback band | (540), (554) | `delete` at (212), (213) |
| `_lastEthOut` (CauldronSeeder.sol:576) | wei | (438) | `= 0` at (203) |
| `_lastTokenOut` (CauldronSeeder.sol:577) | token units | (439) | `= 0` at (204) |

Native balance (not storage): **in** `msg.value` (179), `receive()` (166), `take(currency0)` (501); **out** `settle{value:}` (298), `settle{value:}` (499), `to.call{value: ebal}` (437), `to.call{value: e}` (601).
Token balance: **in** `transferFrom` (215), `take(currency1)` (495); **out** `transfer` to the PoolManager (492), `transfer` to `to` (435), `transfer` to `to` (599).

### MigrationVesting

| field | denom | increases | decreases |
|---|---|---|---|
| `_grants[h][i].total` (MigrationVesting.sol:92) | units of `.token` | `push` at (191) | only by pruning the whole grant at (237) |
| `_grants[h][i].released` (93) | units of `.token` | `= vested` at (228) | pruned at (237) |
| `vestWindow` (78) | seconds | (122), (298) | (122), (298) |

Token balance: **in** `claimByBurn` (184); **out** `transfer(holder, due)` (230). No native value anywhere in this contract.

### LaunchSniper
No value-bearing storage. Native: **in** `msg.value` (66), `receive()` (95); **out** `play{value:}` (76), `owner().call{value:}` (88). Token: **in** the router's delivery, measured at (79); **out** `transfer` (80) and `transfer` (91).

---

## B. Balance vs counter

* **`primePending` is balance-backed.** The computed want is clamped to the live balance at (CauldronSeeder.sol:273-274), so an under-funded contract asks for less rather than reverting in `settle{value:}` (298).
* **Ledger-C counters can outlive the balance.** `primeBudget`/`primeSpent` are zeroed only in `_teardown` (449-450). `rescue` (597) sweeps the whole native balance at (600-601) and clears nothing, so after a rescue the counters read non-zero against an empty balance. Only the clamp at (273) stops that from producing an unpayable swap.
* **`placedWad` is a schedule counter, not a deployment measure.** `_advance` sets it to the time-based target at (330) regardless of what actually minted. A band the cap declined returns `(0,0)` at (550), yields zero liquidity at (388)/(393), and mints nothing — yet `placedWad` still advances at (330). Same divergence when `_reserveRange` falls back onto an already-tracked band at (551): the step is placed into an old range rather than a fresh one adjacent to spot.
* **Teardown returns are measured, not accounted.** `_lastEthOut`/`_lastTokenOut` come from `address(this).balance` (436) and `balanceOf` (434), and the registry adds them to `ethRecovered` at (CauldronRegistry.sol:1583) — so any unspent prime budget (ledger C) is reported to the registry as recovered ledger A.
* **Positions are re-read before removal.** `_teardown` reads live liquidity at `getPositionInfo` (423) and skips zero at (424), so a stale `ranges` entry costs gas but cannot corrupt the delta.
* **Grants are delta-backed.** `_pullAndVest` brackets `claimByBurn` with `balanceOf` at (183) and (186) and clamps `escrowed` down at (187), so a grant can never exceed what actually landed. There is no aggregate solvency check: `_release` transfers at (230) without comparing the sum of open grants to `balanceOf`.

---

## C. Authority map

| gate | holder | where | rotate? | renounce? | dead-end? |
|---|---|---|---|---|---|
| `onlyRegistry` | the registry | CauldronSeeder.sol:145, used at 175 / 565 / 597 | no — `registry` is immutable (71, written 160) | no | yes, if the registry is replaced without redeploying the seeder |
| prime-budget gate | `deployer` **or** `registry.owner()` | CauldronSeeder.sol:252 | `deployer` no (immutable, 161); the owner side rotates with registry ownership | the registry owner can renounce | yes for the owner side, per the note at 74-76; `deployer` remains |
| `OnlyHook` | `_key.hooks` | CauldronSeeder.sol:308 | yes — rewritten every campaign at 183 | n/a | yes — zero before the first campaign |
| `OnlyPoolManager` | `poolManager` | CauldronSeeder.sol:342 | no (immutable, 163) | no | no |
| `lock` (reentrancy, not authority) | — | CauldronSeeder.sol:144 | — | — | held across the nested `unlock` (222) |
| `setSeeder` (registry side) | registry owner | CauldronRegistry.sol:309 | yes | yes | — |
| `setSeeder` (hook side) | registry **or** hook owner | CauldronHook.sol:2001-2002 | yes | yes | clearing it only disables the in-swap nudge; `poke` (231) survives |
| `rescueSeeder` | emergency admin + timelock | CauldronRegistry.sol:321 | per the registry | per the registry | — |
| `onlyOwner` (vesting) | Ownable owner | MigrationVesting.sol:296, 303 | yes | yes — which freezes both knobs | oracle can be set to any address including zero (304) |
| `claimGate` (registry side) | registry | CauldronRegistry.sol:1234 | yes | — | if it points elsewhere, `_pullAndVest` (184) always reverts |
| `onlyOwner` (sniper) | Ownable owner | LaunchSniper.sol:65, 86 | yes | yes | `sweep`'s destination follows the owner (88) |
| presale finalizer | `finalizer` | MiFrensGenesis.sol:581 | per the presale | — | if unset, anyone may ignite |

Ungated (no authority check at all): `receive` (166), `poke` (231), `primePending` (265), the three views (607-609), `startVest` (135), `vestBatch` (153), `claim` (206), `claimFor` (213), the four vesting views (265, 273, 281, 286), `receive` (LaunchSniper.sol:95).

---

## D. External calls with value, and CEI ordering

**CauldronSeeder**

| line | call | value | ordering |
|---|---|---|---|
| 215 | `IERC20(cfg.token).transferFrom(registry, this, tokenTotal)` | token in | after all 183-213 writes; return value checked by `require` |
| 222 | `poolManager.unlock(ACT_PLACE, seedFloorWad)` | — | before the `placedWad` write at 223 |
| 234 / 241 | `poolManager.unlock(ACT_PLACE …)` / `(ACT_PRIME …)` | — | two separate sessions in one tx |
| 252 | `IRegistryOwner(registry).owner()` | — | authority read, before any write |
| 287 | `poolManager.swap` | — | price limit pinned to `MIN_SQRT_PRICE + 1` (292), i.e. no slippage bound |
| 298 | `poolManager.settle{value: owed}` | **native out** | **before** the `primeSpent += owed` effect at 300 |
| 299 | `poolManager.take(currency1, primeTo, got)` | token out to a third party | before the effect at 300 |
| 331 / 368 / 463 | `poolManager.getSlot0` | — | reads |
| 389 / 390 / 394 / 468 / 469 | `LiquidityAmounts` / `TickMath` | — | pure library |
| 401 / 407 / 425 / 477 | `poolManager.modifyLiquidity` | — | `_basePlaced = true` (365) is set BEFORE `_placeBase()` (366): effect-then-interaction |
| 423 | `poolManager.getPositionInfo` | — | read inside the teardown loop |
| 434 / 435 | `IERC20(token).balanceOf` / `.transfer(to, tbal)` | token out | return value NOT checked |
| 437 | `to.call{value: ebal}("")` | **native out, all gas** | **all** effects (438, 439, 449, 450) come AFTER it; re-entry is blocked by `lock` (144) held from `withdrawAll` (565) |
| 491-501 | `sync` / `transfer` / `settle` / `take` / `settle{value:}` / `take` | native + token both ways | 492's boolean return NOT checked, unlike the checked pull at 215 |
| 566 | `poolManager.unlock(ACT_WITHDRAW, to)` | — | before the `ranges`/`seeding`/`complete` writes at 570-572 |
| 598 / 599 / 601 | `balanceOf` / `transfer` / `to.call{value: e}` | token + **native out** | no state writes at all in this function |

**MigrationVesting**

| line | call | value | ordering |
|---|---|---|---|
| 156 / 173 / 181 | `registry.generationToken` | — | read; re-read per loop iteration at 156 |
| 158 / 159 | `balanceOf` / `allowance` on an arbitrary token | — | read |
| 178 | `IERC20(dead).transferFrom(holder, this, amount)` | token in | boolean checked at 178 |
| 180 | `registry.currentGeneration` | — | read |
| 183 / 186 | `IERC20(live).balanceOf(this)` | — | brackets the migration to measure the real delta |
| 184 | `registry.claimByBurn` | token in | the grant is pushed at 191, i.e. AFTER every interaction — CEI-correct |
| 256 | `stakerOracle.isInstant` | — | `try/catch`, failure ⇒ not instant (257) |
| 230 | `IERC20(grt.token).transfer(holder, due)` | token out | `released` is raised at 228 **before** the transfer — CEI-correct; boolean NOT checked; prune (235-237) happens after |

**LaunchSniper**

| line | call | value | ordering |
|---|---|---|---|
| 67 | `presale.soldOut()` | — | precondition |
| 70 | `presale.igniteCauldron()` | drives `summon{value:}` inside the presale (MiFrensGenesis.sol:585) | before the token read |
| 71 | `registry.currentToken()` | — | must run after 70 |
| 76 | `gachaRouter.play{value: msg.value}` | **native out, whole balance of the call** | before the balance read |
| 79 / 80 | `balanceOf(this)` / `transfer(airdropWallet, …)` | token out | measured from balance, so pre-existing tokens are swept with it |
| 88 | `owner().call{value: address(this).balance}` | **native out, all gas** | `require(ok)` at 89 |
| 91 | `transfer(owner(), balanceOf(this))` | token out | boolean NOT checked |

---

## E. Loops

| loop | line | bound | who can grow the bound |
|---|---|---|---|
| teardown over tracked ranges | CauldronSeeder.sol:421 | `ranges.length`, read at 418, hard-capped by `MAX_RANGES = 64` (115) at the check at 544 | anyone: each poke that finds a new aligned band pushes at 553; `_placeBase` pushes one more at 476 |
| range lookup / reservation scan | CauldronSeeder.sol:538 | same `ranges.length`; run TWICE per placement (383, 384) | same as above — up to 2 × 64 comparisons per poke |
| batch migration | MigrationVesting.sol:154 | `holders.length`, entirely caller-supplied | the caller; there is no cap and no gas reserve |
| release over a holder's grants | MigrationVesting.sol:223 | that holder's open-grant count | one entry per deposit at 191 — and `vestBatch` (162) lets a THIRD party push grants onto any address that has an allowance |
| claimable sum | MigrationVesting.sol:267 | same per-holder count | same |
| locked sum | MigrationVesting.sol:275 | same per-holder count | same |

`_release` is the only mutating loop that shrinks: swap-pop at 236-237, with the index advanced only in the else branch at 239.

---

## F. Denomination and units

* **WAD fractions** (1e18 = 100 %): `placedWad` (94), `seedFloorWad` (91), `minStepWad` (95), `baseWad` (96), and `SeedLib.WAD` (SeedLib.sol:37). Bounds are enforced at `cfg.seedFloorWad > 1e18` (177), `cfg.baseWad > 0.5e18` (181) and `seedFloorWad > WAD` (SeedLib.sol:63).
* **wei**: `ethTotal` (92), `primeBudget` (137), `primeSpent` (138), `PRIME_MIN_WEI = 0.001 ether` (141). No scaling, no oracle, no decimals conversion anywhere in the cluster.
* **raw token units**: `tokenTotal` (93). The `1e18` divisors at (370), (372), (466) are WAD-fraction denominators, not decimal normalisers — the contract makes **no** 18-decimals assumption about the brew token.
* **Hard currency-orientation assumption**: currency0 = native, currency1 = the ERC20 brew token, stated at (486-487) and hard-coded — the token leg always goes through `IERC20(token)` (492) and the native leg always through `settle{value:}` (499). The only thing keeping a non-native quote away from this code is the degrade at (PoolOps.sol:296).
* **Ticks**: `_spacing` (97) and `_bandWidth` (98) are tick counts; `SeedLib` treats the last argument as a tick offset (SeedLib.sol:80, SeedLib.sol:111) and floors every width at one spacing (SeedLib.sol:131).
* **Seconds**: `startTs` (89), `window` (90), `Grant.start` (MigrationVesting.sol:94), `Grant.window` (95), `vestWindow` (78), bounded 1 h … 14 days (83-84).
* **MigrationVesting is decimal-agnostic**: it moves a measured delta 1:1 (186-187) and never multiplies by anything but `elapsed/window` (249).

---

## G. `unchecked` blocks and rounding direction

**There is no `unchecked` block and no inline assembly in any of the five files** (verified by grep over all of them). Every arithmetic site is checked by the 0.8 compiler. Rounding:

| site | operation | direction |
|---|---|---|
| SeedLib.sol:68 | `seedFloor + (WAD - seedFloor) * elapsed / window` | **down** — the schedule under-deploys, never over-deploys |
| SeedLib.sol:130 | `_alignDown(offset / n, spacing)` | **down**, then floored at one `spacing` (131) |
| SeedLib.sol:144 | `2 * (n - i) * WAD / denom` | **down** — the taper weights lose dust |
| SeedLib.sol:42 / 47 | `_alignDown` / `_alignUp` | correct Solidity's toward-zero division to floor / ceil |
| CauldronSeeder.sol:370 / 371 | `total - (total * baseWad) / 1e18` | the subtrahend rounds down, so the STREAM share rounds **up** |
| CauldronSeeder.sol:372 / 373 | `(stream * stepWad) / 1e18` | **down** |
| CauldronSeeder.sol:466 / 467 | `(total * baseWad) / 1e18` | **down** |
| CauldronSeeder.sol:267 | `(primeBudget * placedWad) / 1e18` | **down**; the residue is recovered because the final tranche waives the dust floor at 272 |
| CauldronSeeder.sol:464 / 465 | `(MIN_TICK / spacing) * spacing` | toward zero on both ends, so the full range is strictly inside the legal range |
| MigrationVesting.sol:249 | `total * elapsed / window` | **down** — rounding favours the escrow until the window closes, when 248 returns the exact total |

---

## H. Comment-vs-code observations (12)

1. `CauldronSeeder` ctor (159): comment at `unused` (CauldronSeeder.sol:82) says `positionManager` is unused now that placement is core-level; code at `positionManager` (CauldronSeeder.sol:162) still stores it and no other line in the file reads it.
2. `startSeed` (175): comment at `msg` (PoolOps.sol:279) cites the value assert at seeder line 133 and the token pull at seeder line 169; code puts the assert at (CauldronSeeder.sol:179) and the pull at (CauldronSeeder.sol:215).
3. `fundPrime` (251): comment at `Callable` (CauldronSeeder.sol:245) says fundPrime is callable by the registry's owner; code at (CauldronSeeder.sol:252) also accepts the immutable deployer.
4. `fundPrime` (251): comment at `custodies` (CauldronSeeder.sol:48) says this contract only ever custodies ledger A; code at (CauldronSeeder.sol:255) accumulates external ether the file's own note at (CauldronSeeder.sol:441) calls ledger C, into the same native balance.
5. `_teardown` (417): comment at `Nothing` (CauldronSeeder.sol:57) says teardown leaves nothing stranded; code at (CauldronSeeder.sol:422) only unwinds ranges still in the tracked array, and (CauldronSeeder.sol:210) clears that array at the start of every campaign.
6. `_reserveRange` (536): comment at `reverts` (CauldronSeeder.sol:111) says placement reverts once the range cap is hit; code at (CauldronSeeder.sol:544) instead returns a tracked same-side fallback at (CauldronSeeder.sol:551), and the later note at (CauldronSeeder.sol:509) documents that reversal.
7. `rescue` (597): comment at `ledger` (CauldronSeeder.sol:580) says rescue only ever touches ledger A; code at (CauldronSeeder.sol:600) forwards the entire native balance, which the ledger-C note at (CauldronSeeder.sol:137) says also holds the prime budget, and the counters are zeroed only at (CauldronSeeder.sol:449).
8. `IGachaPlay.play` (17): comment at `router` (LaunchSniper.sol:74) says the router tags the swap with this contract as the player; code declares a four-argument `play` (LaunchSniper.sol:17) while the router's entry point (CauldronGachaRouter.sol:233) takes five arguments, so the two selectors differ.
9. `startVest` (135): comment at `escrowed` (MigrationVesting.sol:134) says the return equals `amount` 1:1; code at (MigrationVesting.sol:187) lowers it to the measured balance delta whenever the delta is smaller.
10. `vestBatch` (153): comment at `skipped` (MigrationVesting.sol:150) says a holder with no balance or allowance is skipped and the batch never reverts; code at (MigrationVesting.sol:188) reverts the whole loop from inside `_pullAndVest` (MigrationVesting.sol:169) when the measured delta is zero, and (MigrationVesting.sol:178) reverts it when the pull returns false.
11. `SeedLib.askBand` (84): comment at `launchTick` (SeedLib.sol:78) documents the parameter as the pool tick right after `initialize`; code at (CauldronSeeder.sol:376) passes the CURRENT tick just read at (CauldronSeeder.sol:368).
12. `SeedLib.askBand` (84): comment at `ceilingOffset` (SeedLib.sol:80) documents the last parameter as the price ceiling in ticks below launch; code at (CauldronSeeder.sol:376) passes the per-band width held in `_bandWidth` (CauldronSeeder.sol:98).

---

## I. Function inventory

### `cauldron/CauldronSeeder.sol`

| line | signature | authority | value effect |
|---|---|---|---|
| 23 | `IRegistryOwner.owner() external view` | anyone (declaration) | none |
| 144 | `modifier lock()` | internal (startSeed, poke, pokeInSwap, withdrawAll, rescue) | none |
| 145 | `modifier onlyRegistry()` | internal (startSeed, withdrawAll, rescue) | none |
| 159 | `constructor(address,address,address)` | deployer | none |
| 166 | `receive() external payable` | anyone | receives native |
| 175 | `startSeed(SeederConfig) external payable` | registry | receives native; pulls the token side (215) |
| 231 | `poke() external` | anyone | spends native on the prime tranche via 241 → 298 |
| 251 | `fundPrime(address) external payable` | deployer or registry owner | receives native into `primeBudget` (255) |
| 265 | `primePending() public view` | anyone | none |
| 286 | `_primeStep(uint256) private` | internal (unlockCallback) | native out (298); token out to `primeTo` (299) |
| 307 | `pokeInSwap() external` | hook (`_key.hooks`) | none at this frame; settles via 412 |
| 316 | `_pendingStep() private view` | internal (poke, pokeInSwap) | none |
| 327 | `_advance(uint256) private` | internal (poke, pokeInSwap) | none |
| 341 | `unlockCallback(bytes) external` | poolManager | none at this frame |
| 363 | `_placeStep(uint256) private` | internal (unlockCallback, pokeInSwap) | none directly; 412 settles |
| 417 | `_teardown(address) private` | internal (unlockCallback) | token out (435); **native out** (437) |
| 462 | `_placeBase() private` | internal (_placeStep) | none directly; 480 settles |
| 488 | `_settle(BalanceDelta) private` | internal (_placeStep, _teardown, _placeBase) | token out (492); **native out** (499); both in (495, 501) |
| 536 | `_reserveRange(int24,int24,bool) private` | internal (_placeStep) | none |
| 565 | `withdrawAll(address) external` | registry | none at this frame; 566 drives the sweep |
| 597 | `rescue(address) external` | registry | token out (599); **native out** (601) |
| 607 | `deployedWad() external view` | anyone | none |
| 608 | `rangeCount() external view` | anyone | none |
| 609 | `isComplete() external view` | anyone | none |

### `cauldron/ISeeder.sol`

| line | signature | authority | value effect |
|---|---|---|---|
| 30 | `startSeed(SeederConfig) external payable` | registry (gate on the implementation, 175) | declared payable |
| 31 | `poke() external` | anyone | none |
| 32 | `withdrawAll(address) external` | registry (gate at 565) | implementation forwards both balances |
| 35 | `rescue(address) external` | registry (gate at 597) | implementation forwards both balances |
| 36 | `isComplete() external view` | anyone | none |
| 37 | `seeding() external view` | anyone | none |

### `cauldron/SeedLib.sol`

| line | signature | authority | value effect |
|---|---|---|---|
| 40 | `_alignDown(int24,int24) internal pure` | internal (askBand, bidBand, _bandWidth) | none |
| 45 | `_alignUp(int24,int24) internal pure` | internal (askBand) | none |
| 58 | `deployedTargetWad(uint64,uint64,uint256,uint256) internal pure` | internal (CauldronSeeder._pendingStep, _advance) | none |
| 84 | `askBand(uint256,uint256,int24,int24,int24) internal pure` | internal (CauldronSeeder._placeStep) | none |
| 111 | `bidBand(uint256,uint256,int24,int24,int24) internal pure` | internal (CauldronSeeder._placeStep) | none |
| 128 | `_bandWidth(int24,uint256,int24) internal pure` | internal (askBand, bidBand) | none |
| 140 | `taperWeightWad(uint256,uint256) internal pure` | internal — **no production caller** | none |

### `cauldron/MigrationVesting.sol`

| line | signature | authority | value effect |
|---|---|---|---|
| 14 | `IVestingRegistry.currentGeneration() external view` | anyone (declaration) | none |
| 15 | `IVestingRegistry.generationToken(uint256) external view` | anyone (declaration) | none |
| 16 | `IVestingRegistry.claimByBurn(uint256,uint256) external` | registry's `claimGate` or the perp engine | live token in to the escrow |
| 24 | `IStakerOracle.isInstant(address) external view` | anyone (declaration) | none |
| 114 | `constructor(address,address,uint64,address)` | deployer | none |
| 135 | `startVest(uint256,uint256) external` | anyone (self only) | dead token in (178); live token possibly out (144 → 230) |
| 153 | `vestBatch(uint256,address[]) external` | anyone (keeper) | dead token in per holder (178) |
| 169 | `_pullAndVest(address,uint256,uint256) private` | internal (startVest, vestBatch) | dead token in (178); live token in (184) |
| 206 | `claim() external` | anyone (pays caller) | token out (230) |
| 213 | `claimFor(address) external` | anyone (pays the named holder) | token out (230) |
| 221 | `_release(address) private` | internal (startVest, claim, claimFor) | token out (230) |
| 245 | `_vestedOf(Grant) private view` | internal (_release, claimable, locked) | none |
| 252 | `_isInstant(address) private view` | internal (_pullAndVest) | none |
| 265 | `claimable(address) external view` | anyone | none |
| 273 | `locked(address) external view` | anyone | none |
| 281 | `grantCount(address) external view` | anyone | none |
| 286 | `grantAt(address,uint256) external view` | anyone | none |
| 296 | `setVestWindow(uint64) external` | owner | none |
| 303 | `setStakerOracle(address) external` | owner | none |

### `cauldron/LaunchSniper.sol`

| line | signature | authority | value effect |
|---|---|---|---|
| 8 | `IMiFrensGenesisFinalize.igniteCauldron() external` | presale finalizer (MiFrensGenesis.sol:581) | drives `summon{value:}` inside the presale |
| 9 | `IMiFrensGenesisFinalize.soldOut() external view` | anyone (declaration) | none |
| 13 | `IRegistryCurrent.currentToken() external view` | anyone (declaration) | none |
| 17 | `IGachaPlay.play(uint256,uint256,uint256,uint256) external payable` | anyone (declaration) | whole message value forwarded at 76 |
| 47 | `constructor(address)` | deployer | none |
| 58 | `launch(address,address,address,address,uint256,uint256) external payable` | owner | receives native (58); forwards all of it (76); token out (80) |
| 86 | `sweep(address) external` | owner | **native out** (88) or token out (91) |
| 95 | `receive() external payable` | anyone | receives native |
