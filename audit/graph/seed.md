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

**Arming (registry owner).** `setSeeder` (CauldronRegistry.sol:327) stores the seeder and mirrors it onto the hook at `hook.setSeeder` (CauldronRegistry.sol:329); `setSeedWindow` (CauldronRegistry.sol:350) sets the stream length, bounded to 60 s … 7 days at (CauldronRegistry.sol:351). The progressive path fires only when both are set — `seeder != address(0) && nextSeedWindow > 0` (CauldronRegistry.sol:1728).

**Who funds.** Nobody funds the seeder directly. `_seedGeneration` (CauldronRegistry.sol:1709) delegatecalls `PoolOps.createAndSeedProgressive` (PoolOps.sol:252), so `address(this)` inside PoolOps *is* the registry: the registry holds ledger A and the seeder's `onlyRegistry` (CauldronSeeder.sol:145) resolves to it (PoolOps.sol:333-334).

**PoolKey and orientation.** Built at (PoolOps.sol:268-274): `currency0 = quote` (address(0) = native ETH), `currency1 = token`, `fee = poolFee`, `tickSpacing`, `hooks = hook`. The registry passes `TICK_SPACING` and `POOL_FEE` (CauldronRegistry.sol:1732), declared as 200 and 0 at (CauldronBase.sol:158) and (CauldronBase.sol:157). The token is deployed to sort above the quote (PoolOps.sol:265). Orientation is spelled out at (SeedLib.sol:21-27): price = tokens per ETH, so **ask (token) bands sit BELOW spot** and **bid (ETH) bands sit ABOVE spot**.

**Non-native quote.** `if (quote != address(0))` (PoolOps.sol:296) degrades the whole generation to the atomic seed and returns at (PoolOps.sol:310) — the seeder is never called, because `startSeed` asserts `msg.value == cfg.ethTotal` (CauldronSeeder.sol:179) and has no ERC20 path for the quote.

**Native path.** `baseTok`/`baseEth` are carved at 15 % (`SEED_BASE_WAD`, PoolOps.sol:145) at (PoolOps.sol:335-336); `_greenCandle` (PoolOps.sol:338) places that base and buys the reserve out of it in the ignition tx. Then `IERC20(token).approve(sp.seeder, activeTokens - baseTok)` (PoolOps.sol:343) and `ISeeder(sp.seeder).startSeed{value: ethAmount - baseEth}` (PoolOps.sol:344) with `baseWad: 0` (PoolOps.sol:348), `seedFloorWad = 0.1e18` (PoolOps.sol:137), `minStepWad = 0.02e18` (PoolOps.sol:138), `bandWidth = 2000` ticks (PoolOps.sol:139).

**Seeder intake.** `startSeed` (CauldronSeeder.sol:175) validates (176-181), writes the whole campaign (183-194), performs a full per-campaign reset (201-213), then **pulls** the token side with `transferFrom(registry, address(this), cfg.tokenTotal)` (CauldronSeeder.sol:215) — the ETH side arrived as `msg.value`. One self-`unlock` at (CauldronSeeder.sol:222) places the floor slice, and `placedWad = cfg.seedFloorWad` (CauldronSeeder.sol:223).

**How liquidity is minted.** Core, not periphery: `poolManager.modifyLiquidity` (CauldronSeeder.sol:401) for the ask band and (CauldronSeeder.sol:407) for the bid band, sized by `getLiquidityForAmount1` (CauldronSeeder.sol:389) and `getLiquidityForAmount0` (CauldronSeeder.sol:394). The optional two-sided full-range base uses `getLiquidityForAmounts` (CauldronSeeder.sol:468) and `modifyLiquidity` (CauldronSeeder.sol:477). Settlement of the net delta is `_settle` (CauldronSeeder.sol:488): token out via `IERC20(token).transfer(address(poolManager), …)` (CauldronSeeder.sol:492) + `settle()` (493); native out via `settle{value:}` (499).

**Salt and position owner.** Every mint uses salt `bytes32(0)` — (CauldronSeeder.sol:402), (CauldronSeeder.sol:408), (CauldronSeeder.sol:426), (CauldronSeeder.sol:478) — so repeat placements into the same tick pair MERGE. The positions are owned by the **seeder itself**, as confirmed by the teardown lookup `getPositionInfo(pid, address(this), r.lo, r.hi, bytes32(0))` (CauldronSeeder.sol:423). `activePositionId` stays 0 for a progressive generation (PoolOps.sol:244-245, CauldronRegistry.sol:1566).

**Streaming.** Keeperless in-swap: the hook's `_maybePoke` (CauldronHook.sol:1083) fires a gas-bounded, result-ignored `call` (CauldronHook.sol:1088) into `pokeInSwap` (CauldronSeeder.sol:307), which is gated on `_key.hooks` (CauldronSeeder.sol:308). Fallback: permissionless `poke` (CauldronSeeder.sol:231), which opens its own unlock (234). The amount is a pure function of elapsed time — `SeedLib.deployedTargetWad` (SeedLib.sol:58) — read at (CauldronSeeder.sol:318) and again at (CauldronSeeder.sol:328).

**Prime buy (ledger C).** `fundPrime` (CauldronSeeder.sol:251) takes external ETH and names `primeTo` (254). Each `poke` spends one tranche via `ACT_PRIME` (CauldronSeeder.sol:241) → `_primeStep` (CauldronSeeder.sol:286): `poolManager.swap` (287), `settle{value: owed}` (298), and `take(_key.currency1, primeTo, got)` (299) — the bought token goes straight to `primeTo`, never into this contract.

**Teardown.** `withdrawAll(to)` (CauldronSeeder.sol:565) is `onlyRegistry`; the registry calls it at (CauldronRegistry.sol:555) on a successor handoff and at (CauldronRegistry.sol:1588) at relaunch, both behind `ISeeder(_seeder).seeding()` (CauldronRegistry.sol:554 / 1581). `_teardown` (CauldronSeeder.sol:417) removes every tracked range (421-429), settles (430), forwards the token balance (435) and the entire native balance (437), records both (438-439) and zeroes ledger C (449-450). `rescue(to)` (CauldronSeeder.sol:597) is the loose-funds-only hatch, reachable from `rescueSeeder` (CauldronRegistry.sol:339).

---

## Cluster extra 2 — the vesting schedules

**Every schedule variable.**

| variable | line | meaning |
|---|---|---|
| `vestWindow` | MigrationVesting.sol:81 | live linear window copied into each NEW grant |
| `MIN_WINDOW` = 1 hours | MigrationVesting.sol:86 | lower bound on `vestWindow` |
| `MAX_WINDOW` = 14 days | MigrationVesting.sol:87 | upper bound on `vestWindow` |
| `Grant.token` | MigrationVesting.sol:124 | the token this grant pays in, pinned at deposit |
| `Grant.total` | MigrationVesting.sol:125 | escrowed amount |
| `Grant.released` | MigrationVesting.sol:126 | already withdrawn |
| `Grant.start` | MigrationVesting.sol:127 | deposit timestamp = vest origin |
| `Grant.window` | MigrationVesting.sol:128 | this grant's duration; 0 = instant |
| `stakerOracle` | MigrationVesting.sol:84 | decides who gets `window = 0` |

Snapshotting: the window is copied at `uint64 w = _isInstant(holder) ? 0 : vestWindow;` (MigrationVesting.sol:233) and the token at (MigrationVesting.sol:235), so retuning at (MigrationVesting.sol:354) or swapping the oracle at (MigrationVesting.sol:360) never repriced an existing grant.

**Claim math** — `_vestedOf` (MigrationVesting.sol:301): `window == 0 → total` (246); `elapsed = now - start` (247); `elapsed >= window → total` (248); otherwise `total * elapsed / window` (249), truncating (rounds toward the escrow). `_release` (MigrationVesting.sol:264) pays `vested - released` (226), raises `released` to `vested` (228) **before** the transfer (230), and prunes a drained grant by swap-pop (235-237).

**Who can create a grant.** `startVest` (MigrationVesting.sol:168) — anyone, for themselves only, since the holder is fixed to `msg.sender` at (MigrationVesting.sol:174). `vestBatch` (MigrationVesting.sol:191) — anyone, for ANY address in the array; the only consent is that address's ERC20 allowance, read at (MigrationVesting.sol:198). Both funnel into `_pullAndVest` (MigrationVesting.sol:208), the sole writer of `_grants` (191).

**Who can revoke a grant.** Nobody. There is no revoke, claw-back, pause or sweep function in the contract; the owner's only powers are `setVestWindow` (MigrationVesting.sol:352) and `setStakerOracle` (MigrationVesting.sol:359), both of which affect FUTURE grants only. DERIVED: an escrowed balance can leave the contract only through `_release`'s CHECKED transfer (MigrationVesting.sol:286), which always pays the grant's own beneficiary.

**Who can claim.** `claim` (MigrationVesting.sol:249) pays `msg.sender`; `claimFor` (MigrationVesting.sol:256) is permissionless but pays the named `holder` (214) — a keeper can never redirect. Both revert with `NothingToClaim` (208 / 215) when nothing is due; the auto-release inside `startVest` (144) does not.

**Enforcement.** The escrow is only the exclusive route if the registry's `claimGate` points at it — `msg.sender != claimGate && msg.sender != hook.perpEngine()` (CauldronRegistry.sol:1252). The escrow never verifies that it is the configured gate.

---

## Cluster extra 3 — the sniper / launch flow

**Who can call.** `launch` (LaunchSniper.sol:69) is `onlyOwner` (LaunchSniper.sol:76); the owner is set once at `Ownable(_owner)` (LaunchSniper.sol:58) and is transferable but NO LONGER renounceable — `renounceOwnership` reverts (LaunchSniper.sol:121). Additionally the presale must name this contract as its finalizer, or a bot can ignite first: `if (finalizer != address(0) && msg.sender != finalizer) revert NotAuthorized();` (MiFrensGenesis.sol:591).

**What it does.** (1) precondition `soldOut()` (LaunchSniper.sol:78); (2) `igniteCauldron()` (LaunchSniper.sol:81) → the presale forwards its whole balance to `registry.summon{value: bal}()` (MiFrensGenesis.sol:595), which summons gen 1 and seeds the pool; (3) read the fresh token at `currentToken()` (LaunchSniper.sol:82); (4) **buy** with the entire `msg.value` through the router's real five-argument entry, `IGachaPlay(gachaRouter).play{value: msg.value}(0, 0, minGnomeOut, 0, openMax)` (LaunchSniper.sol:92); (5) forward the result.

**Where the proceeds go.** The bought token is measured from this contract's own balance at `balanceOf(address(this))` (LaunchSniper.sol:95) — not from the router's return — and sent to the caller-supplied `airdropWallet` (LaunchSniper.sol:96). Anything left behind (a router ETH refund, a stray token) is recoverable only by the owner through `sweep` (LaunchSniper.sol:102), which sends to `owner()` (88 / 91). `receive()` (LaunchSniper.sol:124) accepts ether with no bookkeeping.

**Fee exemption.** The doc requires `setTaxExempt(launchSniper, true)` (LaunchSniper.sol:45); the hook's rule is `taxExempt[_taxedPlayer(sender, hookData)] && isOpener[sender]` (CauldronHook.sol:2467), so the ROUTER must be an opener and the SNIPER must be tax-exempt.

**Selector mismatch — FIXED.** `IGachaPlay.play` now declares five `uint256` arguments (LaunchSniper.sol:22) and is called with five (LaunchSniper.sol:92), matching `CauldronGachaRouter.play` (CauldronGachaRouter.sol:234). The router still declares `receive()` (CauldronGachaRouter.sol:594) and no `fallback`, so a future drift would again revert unconditionally; the mirroring is enforced only by the note at `play` (LaunchSniper.sol:16) (DERIVED).

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
| `_grants[h][i].total` (MigrationVesting.sol:125) | units of `.token` | `push` at (191) | only by pruning the whole grant at (237) |
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
* **Teardown returns are measured, not accounted.** `_lastEthOut`/`_lastTokenOut` come from `address(this).balance` (436) and `balanceOf` (434), and the registry adds them to `ethRecovered` at (CauldronRegistry.sol:1589) — so any unspent prime budget (ledger C) is reported to the registry as recovered ledger A.
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
| `setSeeder` (registry side) | registry owner | CauldronRegistry.sol:327 | yes | yes | — |
| `setSeeder` (hook side) | registry **or** hook owner | CauldronHook.sol:2084-2002 | yes | yes | clearing it only disables the in-swap nudge; `poke` (231) survives |
| `rescueSeeder` | emergency admin + timelock | CauldronRegistry.sol:339 | per the registry | per the registry | — |
| `onlyOwner` (vesting) | Ownable owner | MigrationVesting.sol:352, 303 | yes | yes — which freezes both knobs | oracle can be set to any address including zero (304) |
| `claimGate` (registry side) | registry | CauldronRegistry.sol:1252 | yes | — | if it points elsewhere, `_pullAndVest` (184) always reverts |
| `onlyOwner` (sniper) | Ownable owner | LaunchSniper.sol:76, 102 | yes | **no** — `renounceOwnership` reverts (LaunchSniper.sol:121) | `sweep`'s destination follows the owner (104) |
| presale finalizer | `finalizer` | MiFrensGenesis.sol:591 | per the presale | — | if unset, anyone may ignite |

Ungated (no authority check at all): `receive` (166), `poke` (231), `primePending` (265), the three views (607-609), `startVest` (135), `vestBatch` (153), `claim` (206), `claimFor` (213), the four vesting views (265, 273, 281, 286), `receive` (LaunchSniper.sol:124).

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
| 70 | `presale.igniteCauldron()` | drives `summon{value:}` inside the presale (MiFrensGenesis.sol:595) | before the token read |
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
| batch migration | MigrationVesting.sol:192 | `holders.length`, entirely caller-supplied | the caller; there is no cap and no gas reserve |
| release over a holder's grants | MigrationVesting.sol:266 | that holder's open-grant count | one entry per deposit at 191 — and `vestBatch` (162) lets a THIRD party push grants onto any address that has an allowance |
| claimable sum | MigrationVesting.sol:323 | same per-holder count | same |
| locked sum | MigrationVesting.sol:323 | same per-holder count | same |

`_release` is the only mutating loop that shrinks: swap-pop at 236-237, with the index advanced only in the else branch at 239.

---

## F. Denomination and units

* **WAD fractions** (1e18 = 100 %): `placedWad` (94), `seedFloorWad` (91), `minStepWad` (95), `baseWad` (96), and `SeedLib.WAD` (SeedLib.sol:37). Bounds are enforced at `cfg.seedFloorWad > 1e18` (177), `cfg.baseWad > 0.5e18` (181) and `seedFloorWad > WAD` (SeedLib.sol:63).
* **wei**: `ethTotal` (92), `primeBudget` (137), `primeSpent` (138), `PRIME_MIN_WEI = 0.001 ether` (141). No scaling, no oracle, no decimals conversion anywhere in the cluster.
* **raw token units**: `tokenTotal` (93). The `1e18` divisors at (370), (372), (466) are WAD-fraction denominators, not decimal normalisers — the contract makes **no** 18-decimals assumption about the brew token.
* **Hard currency-orientation assumption**: currency0 = native, currency1 = the ERC20 brew token, stated at (486-487) and hard-coded — the token leg always goes through `IERC20(token)` (492) and the native leg always through `settle{value:}` (499). The only thing keeping a non-native quote away from this code is the degrade at (PoolOps.sol:296).
* **Ticks**: `_spacing` (97) and `_bandWidth` (98) are tick counts; `SeedLib` treats the last argument as a tick offset (SeedLib.sol:80, SeedLib.sol:111) and floors every width at one spacing (SeedLib.sol:131).
* **Seconds**: `startTs` (89), `window` (90), `Grant.start` (MigrationVesting.sol:127), `Grant.window` (95), `vestWindow` (78), bounded 1 h … 14 days (83-84).
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
| MigrationVesting.sol:305 | `total * elapsed / window` | **down** — rounding favours the escrow until the window closes, when 248 returns the exact total |

---

## H. Comment-vs-code observations (12)

1. `CauldronSeeder` ctor (159): comment at `unused` (CauldronSeeder.sol:82) says `positionManager` is unused now that placement is core-level; code at `positionManager` (CauldronSeeder.sol:162) still stores it and no other line in the file reads it.
2. `startSeed` (175): comment at `msg` (PoolOps.sol:279) cites the value assert at seeder line 133 and the token pull at seeder line 169; code puts the assert at (CauldronSeeder.sol:179) and the pull at (CauldronSeeder.sol:215).
3. `fundPrime` (251): comment at `Callable` (CauldronSeeder.sol:245) says fundPrime is callable by the registry's owner; code at (CauldronSeeder.sol:252) also accepts the immutable deployer.
4. `fundPrime` (251): comment at `custodies` (CauldronSeeder.sol:48) says this contract only ever custodies ledger A; code at (CauldronSeeder.sol:255) accumulates external ether the file's own note at (CauldronSeeder.sol:441) calls ledger C, into the same native balance.
5. `_teardown` (417): comment at `Nothing` (CauldronSeeder.sol:57) says teardown leaves nothing stranded; code at (CauldronSeeder.sol:422) only unwinds ranges still in the tracked array, and (CauldronSeeder.sol:210) clears that array at the start of every campaign.
6. `_reserveRange` (536): comment at `reverts` (CauldronSeeder.sol:111) says placement reverts once the range cap is hit; code at (CauldronSeeder.sol:544) instead returns a tracked same-side fallback at (CauldronSeeder.sol:551), and the later note at (CauldronSeeder.sol:509) documents that reversal.
7. `rescue` (597): comment at `ledger` (CauldronSeeder.sol:580) says rescue only ever touches ledger A; code at (CauldronSeeder.sol:600) forwards the entire native balance, which the ledger-C note at (CauldronSeeder.sol:137) says also holds the prime budget, and the counters are zeroed only at (CauldronSeeder.sol:449).
8. `IGachaPlay.play` (22): the four-argument declaration is gone; the interface and the call site now both carry five arguments (LaunchSniper.sol:92) and match the router (CauldronGachaRouter.sol:234), and the note recording the old defect sits at `play` (LaunchSniper.sol:16).
9. `startVest` (168): comment at `escrowed` (MigrationVesting.sol:167) says the return equals `amount` 1:1; code at `escrowed` (MigrationVesting.sol:230) lowers it to the measured balance delta whenever the delta is smaller.
10. `vestBatch` (153): comment at `skipped` (MigrationVesting.sol:183) says a holder with no balance or allowance is skipped and the batch never reverts; code at (MigrationVesting.sol:231) reverts the whole loop from inside `_pullAndVest` (MigrationVesting.sol:208) when the measured delta is zero, and (MigrationVesting.sol:221) reverts it when the pull returns false.
11. `SeedLib.askBand` (84): comment at `launchTick` (SeedLib.sol:78) documents the parameter as the pool tick right after `initialize`; code at (CauldronSeeder.sol:376) passes the CURRENT tick just read at (CauldronSeeder.sol:368).
12. `SeedLib.askBand` (84): comment at `ceilingOffset` (SeedLib.sol:80) documents the last parameter as the price ceiling in ticks below launch; code at (CauldronSeeder.sol:376) passes the per-band width held in `_bandWidth` (CauldronSeeder.sol:98).

---

## I. Function inventory


### `cauldron/CauldronSeeder.sol`

| line | signature | authority | value effect |
|---|---|---|---|
| 23 | `owner() external view returns (address)` | anyone (declaration only; the implementing getter is the registry's Ownable owner) | NONE |
| 144 | `modifier lock()` | internal (callers: startSeed, poke, pokeInSwap, withdrawAll, rescue) | NONE |
| 145 | `modifier onlyRegistry()` | internal (callers: startSeed, withdrawAll, rescue) | NONE |
| 159 | `constructor(address _registry, address _positionManager, address _poolManager)` | deployer | NONE |
| 166 | `receive() external payable` | anyone | receives native — `receive` is payable (line 166) |
| 175 | `startSeed(SeederConfig calldata cfg) external payable onlyRegistry lock` | registry | receives native — `startSeed` is payable (line 175) and rejects any value that differs from the declared `ethTotal` (line 179); ERC20 pull of the brew token ... |
| 231 | `poke() external lock` | anyone | sends native indirectly — the `ACT_PRIME` unlock (line 241) re-enters `_primeStep` (line 286), which pays the PoolManager at `settle` (line 298) out of this ... |
| 251 | `fundPrime(address to) external payable` | deployer or the registry's owner | receives native — `fundPrime` is payable (line 251) and the whole amount is added to `primeBudget` (line 255) |
| 265 | `primePending() public view returns (uint256)` | anyone | NONE |
| 286 | `_primeStep(uint256 ethIn) private` | internal (callers: unlockCallback) | sends native to the PoolManager at `settle` (line 298); the bought token is delivered straight to `primeTo` at `take` (line 299) |
| 307 | `pokeInSwap() external lock` | hook (the address stored in _key.hooks at summon) | NONE at this frame; the mint's native and token legs are paid by `_settle` (line 412) |
| 316 | `_pendingStep() private view returns (uint256)` | internal (callers: poke, pokeInSwap) | NONE |
| 327 | `_advance(uint256 step) private` | internal (callers: poke, pokeInSwap) | NONE |
| 341 | `unlockCallback(bytes calldata data) external returns (bytes memory)` | poolManager | NONE at this frame; the three branches move value through `_placeStep` (line 346), `_primeStep` (line 349) and `_teardown` (line 352) |
| 363 | `_placeStep(uint256 stepWad) private` | internal (callers: unlockCallback, pokeInSwap) | NONE directly — both mints are paid or collected by `_settle` (line 412) |
| 417 | `_teardown(address to) private` | internal (callers: unlockCallback) | ERC20 transfer of the brew token to `to` at `transfer` (line 435); sends native to `to` at `call` (line 437); pool proceeds are pulled in first by `_settle` ... |
| 462 | `_placeBase() private` | internal (callers: _placeStep) | NONE directly — the two-sided mint is paid by `_settle` (line 480) |
| 488 | `_settle(BalanceDelta d) private` | internal (callers: _placeStep, _teardown, _placeBase) | ERC20 transfer of the brew token to the PoolManager at `transfer` (line 492); sends native to the PoolManager at `settle` (line 499); pulls the two currencie... |
| 536 | `_reserveRange(int24 lo, int24 hi, bool isAsk) private returns (int24, int24)` | internal (callers: _placeStep) | NONE |
| 565 | `withdrawAll(address to) external onlyRegistry lock returns (uint256 ethOut, uint256 tokenOut)` | registry | NONE in this frame; the `ACT_WITHDRAW` unlock (line 566) re-enters `unlockCallback` (line 341) and `_teardown` (line 417) forwards both balances to the calle... |
| 597 | `rescue(address to) external onlyRegistry lock` | registry | ERC20 transfer of the brew token to `to` at `transfer` (line 599); sends native to `to` at `call` (line 601) |
| 607 | `deployedWad() external view returns (uint256)` | anyone | NONE |
| 608 | `rangeCount() external view returns (uint256)` | anyone | NONE |
| 609 | `isComplete() external view returns (bool)` | anyone | NONE |

### `cauldron/ISeeder.sol`

| line | signature | authority | value effect |
|---|---|---|---|
| 30 | `startSeed(SeederConfig calldata cfg) external payable` | registry (the gate lives on the implementation, CauldronSeeder.startSeed) | receives native — `startSeed` is declared payable (line 30) |
| 31 | `poke() external` | anyone (the implementation CauldronSeeder.poke has no authority check) | NONE |
| 32 | `withdrawAll(address to) external returns (uint256 ethOut, uint256 tokenOut)` | registry (the gate lives on the implementation, CauldronSeeder.withdrawAll) | NONE at the declaration; the implementation forwards the recovered native and token balances at `withdrawAll` (line 32) |
| 35 | `rescue(address to) external` | registry (the gate lives on the implementation, CauldronSeeder.rescue) | NONE at the declaration; the implementation forwards the loose token and native balances at `rescue` (line 35) |
| 36 | `isComplete() external view returns (bool)` | anyone (view) | NONE |
| 37 | `seeding() external view returns (bool)` | anyone (view) | NONE |

### `cauldron/LaunchSniper.sol`

| line | signature | authority | value effect |
|---|---|---|---|
| 8 | `igniteCauldron() external returns (address token)` | the presale's finalizer, if one is set; otherwise anyone once the presale is sold out | NONE at the declaration; the implementation forwards the presale's whole native balance to the registry at `summon` (MiFrensGenesis.sol:595) |
| 9 | `soldOut() external view returns (bool)` | anyone (declaration only; a view on the presale) | NONE |
| 13 | `currentToken() external view returns (address)` | anyone (declaration only; the registry's public live-token pointer) | NONE |
| 22 | `play( uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax ) external payable returns (uint256)` | declaration only (interface) | the declared entry is `payable` (line 28), so the caller's ether funds the buy |
| 58 | `constructor(address _owner) Ownable(_owner)` | deployer | NONE |
| 69 | `launch( address presale, address registry, address gachaRouter, address airdropWallet, uint256 minGnomeOut, uint256 openMax ) external payable onlyOwner returns (address token, uint256 gnomeBought)` | owner | forwards the ENTIRE message value into the router's buy at `play` (line 92) and pushes whatever token balance results to the airdrop wallet at `transfer` (li... |
| 102 | `sweep(address tokenAddr) external onlyOwner` | owner | sends native to the owner at `call` (line 104); ERC20 transfer of the named token to the owner at `transfer` (line 107) |
| 120 | `renounceOwnership() public pure override` | anyone by ABI - it always reverts | none - it reverts (DERIVED) |
| 124 | `receive() external payable` | anyone | receives native — `receive` is payable (line 124) |

### `cauldron/MigrationVesting.sol`

| line | signature | authority | value effect |
|---|---|---|---|
| 14 | `currentGeneration() external view returns (uint256)` | anyone (declaration only; the registry's public generation counter) | NONE |
| 15 | `generationToken(uint256 gen) external view returns (address)` | anyone (declaration only; the registry's generation-to-token map) | NONE |
| 16 | `claimByBurn(uint256 fromGen, uint256 amount) external returns (uint256 claimedAmount)` | the registry's claimGate (this escrow) or the perp engine | ERC20 transfer of the live-generation token from the registry's reserve to this escrow, driven by the call at `claimByBurn` (line 227) |
| 24 | `isInstant(address who) external view returns (bool)` | anyone (declaration only; the implementation is whatever address the owner set) | NONE |
| 147 | `constructor( address _registry, address _owner, uint64 _vestWindow, address _stakerOracle ) Ownable(_owner)` | deployer | NONE |
| 168 | `startVest(uint256 fromGen, uint256 amount) external nonReentrant returns (uint256 escrowed)` | anyone (a holder migrating their own balance) | NONE at this frame; `_pullAndVest` (line 174) pulls the dead-gen token in and `_release` (line 177) pays the live token out |
| 191 | `vestBatch(uint256 fromGen, address[] calldata holders) external nonReentrant` | anyone (permissionless keeper batch) | each holder's dead-gen balance is pulled and escrowed inside `_pullAndVest` (line 201) |
| 208 | `_pullAndVest(address holder, uint256 fromGen, uint256 amount) private returns (uint256 escrowed)` | private (callers: startVest, vestBatch) | pulls the holder's dead tokens into this escrow at `transferFrom` (line 221) and receives the live token from the registry's burn-and-claim at `claimByBurn` ... |
| 249 | `claim() external nonReentrant` | anyone (pays only the caller) | ERC20 transfer of each grant's pinned token to the caller, performed by `_release` (line 250) |
| 256 | `claimFor(address holder) external nonReentrant` | anyone (keeper; funds go to the named holder) | ERC20 transfer of each grant's pinned token to the named holder, performed by `_release` (line 257) |
| 264 | `_release(address holder) private returns (uint256 totalMoved)` | private (callers: startVest, claim, claimFor) | pays each grant's vested-minus-released amount to the beneficiary at `transfer` (line 286) |
| 301 | `_vestedOf(Grant storage grt) private view returns (uint256)` | internal (callers: _release, claimable, locked) | NONE |
| 308 | `_isInstant(address who) private view returns (bool)` | internal (callers: _pullAndVest) | NONE |
| 321 | `claimable(address holder) external view returns (uint256 total)` | anyone | NONE |
| 329 | `locked(address holder) external view returns (uint256 total)` | anyone | NONE |
| 337 | `grantCount(address holder) external view returns (uint256)` | anyone | NONE |
| 342 | `grantAt(address holder, uint256 i) external view returns (Grant memory)` | anyone | NONE |
| 352 | `setVestWindow(uint64 _window) external onlyOwner` | owner | NONE |
| 359 | `setStakerOracle(address _oracle) external onlyOwner` | owner | NONE |
| 372 | `renounceOwnership() public pure override` | anyone by ABI - it always reverts | none - it reverts (DERIVED) |

### `cauldron/SeedLib.sol`

| line | signature | authority | value effect |
|---|---|---|---|
| 40 | `_alignDown(int24 tick, int24 spacing) internal pure returns (int24)` | internal (callers: askBand, bidBand, _bandWidth) | NONE |
| 45 | `_alignUp(int24 tick, int24 spacing) internal pure returns (int24)` | internal (callers: askBand) | NONE |
| 58 | `deployedTargetWad(uint64 startTs, uint64 window, uint256 nowTs, uint256 seedFloorWad) internal pure returns (uint256 wad)` | internal (callers: CauldronSeeder._pendingStep, CauldronSeeder._advance) | NONE |
| 84 | `askBand(uint256 i, uint256 n, int24 launchTick, int24 spacing, int24 ceilingOffset) internal pure returns (int24 lower, int24 upper)` | internal (callers: CauldronSeeder._placeStep) | NONE |
| 111 | `bidBand(uint256 j, uint256 m, int24 launchTick, int24 spacing, int24 floorOffset) internal pure returns (int24 lower, int24 upper)` | internal (callers: CauldronSeeder._placeStep) | NONE |
| 128 | `_bandWidth(int24 offset, uint256 n, int24 spacing) internal pure returns (int24 w)` | internal (callers: askBand, bidBand) | NONE |
| 140 | `taperWeightWad(uint256 i, uint256 n) internal pure returns (uint256 wad)` | internal (no production caller) | NONE |
