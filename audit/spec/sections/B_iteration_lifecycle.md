# AREA B — Iteration lifecycle

Files read in full: `contracts/solidity/CauldronRegistry.sol` (1736 lines), `contracts/solidity/cauldron/CauldronBase.sol` (461 lines), `contracts/solidity/cauldron/MigrationVesting.sol` (307 lines), `contracts/solidity/CauldronToken.sol` (61 lines), `contracts/solidity/cauldron/CauldronFactory.sol` (105 lines). `cauldron/PoolOps.sol` grepped + targeted reads (creature table, `deployTokenAbove`, `seedFunding`, `removeAll`, `migrateOne`/`migrateUpTo`/`autoMigrateBatch`, `materializeLegacy`, rotation helpers). `cauldron/RedemptionExt.sol` read for `rotateSliceFrom`/`recoverLegs`/`generationQuote` write.

---

## B1 — `CauldronRegistry.summon`

**Purpose (INTENT).** One-time genesis: deploy generation 1, create its V4 pool, seed liquidity, deploy the genesis NFT collection. NatSpec CauldronRegistry.sol:640-648: "the ONLY function that requires external ETH."

**Entrypoint.** `function summon() external payable nonReentrant returns (address token, PoolId poolId)` — CauldronRegistry.sol:649-653.
**Authority (ACTUAL).** CauldronRegistry.sol:658: `if (msg.sender != owner() && msg.sender != igniter) revert NotAdmin();` — owner OR the delegated `igniter` role (CauldronBase.sol:305, set via `setIgniter`, CauldronRegistry.sol:377-379).

**Preconditions.** `!summoned` (CauldronRegistry.sol:659) else `AlreadySummoned`; `msg.value != 0` (CauldronRegistry.sol:660) else `InsufficientETH`.

**Behavior (step-by-step).**
1. `summoned = true; currentGeneration = 1; lastSummonAt = block.timestamp` (CauldronRegistry.sol:662-664).
2. Name/symbol via `PoolOps.creatureFor(1)` = ("Gnomeland","GNOME") (PoolOps.sol:155), branded via `LaunchLib.displayName` (CauldronRegistry.sol:668-669).
3. `_deployToken` → `PoolOps.deployTokenAbove(name, symbol, 1, TOTAL_SUPPLY, address(0))`, plain `CREATE` (CauldronRegistry.sol:672, 1576-1592; PoolOps.sol:677-714). Mints the full 777M fixed supply to the registry in the `CauldronToken` constructor (CauldronToken.sol:46). `generationToken[1] = token`; `generationQuote[1]` left at its zero default = native ETH (CauldronRegistry.sol:673-677).
4. Genesis bonus sizing (opt-in): `genesisSharePerFren = pool/genesisShares`, `genesisReserveOutstanding = genesisSharePerFren * genesisShares` (CauldronRegistry.sol:684-689).
5. OG airdrop reserve carved off-LP: `reserveTokens -= airdropReserve`, `IERC20(token).transfer(airdropWallet, airdropReserve)` (CauldronRegistry.sol:691-697) — moves value OUTSIDE the LP, unlike everything else in the function.
6. `_seedGeneration(token, activeTokens=GEN1_ACTIVE_TOKENS(80%), msg.value, reserveTokens, 1)` (CauldronRegistry.sol:692-705) → pool created, two positions minted (see B5/PoolOps below); records `generationPoolId/PoolKey/PositionId/ReservePositionId/reserveTick*[1]` and pushes the live key to the hook (CauldronRegistry.sol:1690-1699).
7. Optional prime buy from `primeBuyEth` (owner pre-funded) — a real first-block market buy routed to `airdropWallet`/`primeFunder` (CauldronRegistry.sol:713-721).
8. `_deployCollection(1, ...)` deploys the genesis NFT collection + wires the hook as minter (CauldronRegistry.sol:724, 1088-1126).
9. `emit CauldronSummoned(1, token, poolId, name, symbol)` (CauldronRegistry.sol:726).

**Postconditions/invariants.** `summoned=true`; `currentGeneration=1`; gen-1 pool live and seeded; registry holds no un-deployed ETH except any leftover `primeBuyEth` remainder path.

**Edge cases.** Mining can fail to place the token above `QUOTE_WATERMARK` for a non-native quote, but gen-1 always requests `address(0)`, so `deployTokenAbove`'s no-mining-needed branch always succeeds (PoolOps.sol:684-687, 671-672).

**Events.** `CauldronSummoned` (CauldronRegistry.sol:68-74), `GenesisBonusReserved` (:103), `CollectionDeployed` (:1125).

**DENOMINATION: ETH-only** — `summon()` hard-passes `address(0)` as quote (CauldronRegistry.sol:672 `_deployToken(name, symbol, 1, address(0))`); there is no path to launch generation 1 against any other asset.

---

## B2 — Permissionless `relaunch()`

**Purpose (INTENT).** "Kill the current token, deploy a new generation, create its V4 pool, and seed liquidity. Everything in one transaction... Fully autonomous... Permissionless... Mints nothing extra" (CauldronRegistry.sol:733-747).

**Entrypoint.** `function relaunch() external nonReentrant returns (address token, PoolId poolId)` (CauldronRegistry.sol:748-752).
**Authority (ACTUAL).** None — `external`, no modifier beyond `nonReentrant`. Callable by anyone once the gates below pass.

**Preconditions (death check).**
1. `summoned` (CauldronRegistry.sol:753) else `NotSummoned`.
2. `hook.isDead(oldPoolId)` (CauldronRegistry.sol:760) else `TokenStillAlive` — on-chain volume check, no oracle (per comment).
3. `block.timestamp >= lastSummonAt + minLifetime` (CauldronRegistry.sol:764) else `TooYoung` (grace period).
4. `address(governor) != 0 && governor.hasProposals()` (CauldronRegistry.sol:768) else `NoProposal`.

**Behavior — full sequence, denomination noted at each value-moving step.**
1. `emit CauldronDied(oldGen, oldToken, block.number)` (CauldronRegistry.sol:773). Token is NOT frozen — remains transferable (comment :770-772).
2. `_perpHousekeep(false)` — force-closes all open perp positions while the OLD pool is still alive, via `hook.forceClosePerps` under a gas cap `gasleft()-RELAUNCH_TAIL_RESERVE`, try/catch, never bricks (CauldronRegistry.sol:782, 1063-1082, constant at :136-139).
3. **Liquidity teardown**: `(ethFromLP, tokensFromLP) = _removeLiquidity(oldGen)` (CauldronRegistry.sol:785; body at :1502-1564). Despite the variable's legacy name, this is in the DYING generation's *own quote's* raw units, not necessarily ETH (see Denomination Spine below). Recovers, in order: (a) active position via `PoolOps.removeAll` (CauldronRegistry.sol:1513-1515; PoolOps.sol:1101-1124, measured on `key.currency0` balance delta, not `address(this).balance`); (b) reserve position, same call (CauldronRegistry.sol:1517-1522); (c) progressive-seeder mini-positions via `ISeeder.withdrawAll` if seeding (CauldronRegistry.sol:1530-1535); (d) rotated treasury legs via delegatecall to `RedemptionExt.recoverLegs(gen)` (CauldronRegistry.sol:1549-1563; RedemptionExt.sol:571-590) — best-effort per leg, failing legs stay recorded for retry.
4. `emit LiquidityRecovered(oldGen, ethFromLP)` (CauldronRegistry.sol:786).
5. Recovered dead-pool tokens burned: `CauldronToken(oldToken).burn(address(this), tokensFromLP)` (CauldronRegistry.sol:791-793) — via `onlyRegistry` `burn()` (CauldronToken.sol:58-60).
6. Matured perp tickets resolved, gas-capped + try/catch (CauldronRegistry.sol:802-804, `RELAUNCH_TICKETS=50`).
7. `newGen = oldGen + 1; currentGeneration = newGen; lastSummonAt = block.timestamp` (CauldronRegistry.sol:819-821).
8. `(winId, spec) = governor.winner()` (CauldronRegistry.sol:830). `spec.quote` re-checked against the live allowlist: `if (specQuote != address(0) && !allowedQuote[specQuote]) specQuote = address(0)` — degrades to native rather than reverting (CauldronRegistry.sol:877-878). `spec.nftSupply` clamped, never reverted (CauldronRegistry.sol:888-890).
9. **New token deploy**: `(token, specQuote) = _deployToken(name, symbol, newGen, specQuote)` → `PoolOps.deployTokenAbove` (CauldronRegistry.sol:897, 1576-1592; PoolOps.sol:677-714) — plain `CREATE` (not CREATE2, "audit A-01": a predictable CREATE2 address could be squatted to brick relaunch, PoolOps.sol comment ~656-664). Mining tries `SALT_TRIES` salts above `max(quote, QUOTE_WATERMARK)`; if none lands above, silently falls back to `address(0)` (native) instead of reverting (PoolOps.sol:696-713).
10. **Funding decision**: `(specQuote, totalETH, vaultSwept) = PoolOps.seedFunding(hook, specQuote, generationQuote[oldGen], ethFromLP, generationVault[oldGen])` (CauldronRegistry.sol:921-923; PoolOps.sol:985-1052). Preference order, none of which reverts: (1) the proposal's `wantQuote` IF `recovered==0 OR oldQuote==wantQuote` — i.e. only funded from value already in that denomination, pulling `hook.releaseRelaunchAsset(wantQuote)` (PoolOps.sol:1037-1040, :1059-1061); (2) native — `recovered` counts only if `oldQuote==address(0)`, plus `vaultSwept` plus `hook.releaseRelaunchETH()` (PoolOps.sol:1043-1046, :1066-1068); (3) last resort, the dying generation's own quote (PoolOps.sol:1048-1050). **Rule: never strand `recovered`** — no swap is ever performed (explicit design note, PoolOps.sol:1016-1029: "putting an oracle in the one function that must never be the reason the machine cannot be reborn is a bad trade").
11. `if (totalETH == 0) revert NoLiquidityToSeed()` (CauldronRegistry.sol:945) — this is the ONLY revert point after `winId` is read and BEFORE `markConsumed`; everything else in the sequence is designed not to revert (comment CauldronRegistry.sol:925-944 documents this was moved here specifically so a revert stays recoverable).
12. `governor.markConsumed(winId)` (CauldronRegistry.sol:946).
13. **`generationQuote[newGen] = specQuote`** (CauldronRegistry.sol:951) — generation-keyed write #1 for this mapping (see B5).
14. `generationProposer[newGen] = spec.proposer; generationParent[newGen] = oldGen; hook.setActiveProposer(spec.proposer)` (CauldronRegistry.sol:956-958).
15. Active/reserve sizing: `genesisReserveOutstanding += genesisPending; genesisPending = 0` (CauldronRegistry.sol:970-971); `newActive = tokensFromLP > unclaimedGenesis ? tokensFromLP - unclaimedGenesis : tokensFromLP` with a `newActive==0` fallback to `GEN1_ACTIVE_TOKENS` + `ReserveShortfall` event (CauldronRegistry.sol:973-988).
16. Legacy-collection flush (if `collectionLedger` wired): `_flushLegacyAtRelaunch` (burns dying tokens into a ledger credit, CauldronRegistry.sol:1447-1455; PoolOps.sol:1310-1328), then `PoolOps.crystallizeCollection` (CauldronRegistry.sol:995-998; PoolOps.sol:1335-1350), then `newActive` is reduced by `collectionLedger.totalEntitled()`, clamped to zero with a `ReserveShortfall` emit rather than underflow (CauldronRegistry.sol:999-1014).
17. `if (newActive > TOTAL_SUPPLY) newActive = TOTAL_SUPPLY` clamp against fee-inflated recovery (CauldronRegistry.sol:1016-1025). `newReserve = TOTAL_SUPPLY - newActive` (CauldronRegistry.sol:1026).
18. **Pool init + seeding**: `poolId = _seedGeneration(token, newActive, totalETH, newReserve, newGen)` (CauldronRegistry.sol:1034) — atomic green-candle (`_createPoolAndSeedWithBuy` → `PoolOps.createAndSeedWithBuy`) by default, or progressive (`PoolOps.createAndSeedProgressive`, degrades to atomic for any non-native quote, PoolOps.sol:272-306) if `seeder != 0 && nextSeedWindow > 0` (CauldronRegistry.sol:1653-1685). `_recordSeed` writes `generationPoolId/PoolKey/PositionId/ReservePositionId/reserveTickLower/Upper[newGen]` and `hook.setLiveKey` (CauldronRegistry.sol:1690-1699).
19. NFT collection: iteration 2 continues MiFrens (`_continueMiFrens`), else fresh `_deployCollection` (CauldronRegistry.sol:1041-1045).
20. `hook.setNftCurveFrom(volPerNFT)` (CauldronRegistry.sol:1049).
21. `_perpHousekeep(true)` re-arms the perp engine on the new token via `IPerpSync(eng).syncGeneration()`, try/catch (CauldronRegistry.sol:1054, 1064-1066).
22. `emit CauldronReborn(newGen, token, poolId, name, symbol)` (CauldronRegistry.sol:1056).

**Generation-keyed storage writes made by `relaunch()`** (see B5 table for the full inventory): `generationQuote[newGen]` (:951), `generationProposer[newGen]` (:956), `generationParent[newGen]` (:957), `generationToken[newGen]` (:899), `generationPoolId/PoolKey/PositionId/ReservePositionId/reserveTickLower/Upper[newGen]` (via `_recordSeed`, :1690-1698), `generationCollection[newGen]`/`generationVault[newGen]` (via `_deployCollection`/`_continueMiFrens`, :1118-1119/:1143-1144).

**Postconditions/invariants.** `currentGeneration = oldGen+1`; `currentToken` points at the new token; old token remains transferable and its reserve/claim path stays live via `claimByBurn`; `TOTAL_SUPPLY` conserved per generation (new token minted fresh at the same fixed 777M, CauldronToken.sol:46).

**Edge cases documented in-code.** OOG child call draining gas via the 63/64 rule → mitigated with `RELAUNCH_TAIL_RESERVE` (CauldronRegistry.sol:127-136). A revert AFTER `markConsumed` would permanently re-elect the same proposal — extensively documented as the class of bug the whole ordering (mine → fund → check solvency → consume) is designed to avoid (CauldronRegistry.sol:925-944, 1016-1024, PoolOps.sol:775-788, :1031-1034).

**Events.** `CauldronDied`, `LiquidityRecovered`, `ReserveShortfall`(×2 possible sites), `CollectionDeployed`, `CauldronReborn` (CauldronRegistry.sol:76-99, 148, 1125, 82-88).

**DENOMINATION: quote-agnostic (by design), with one breaks-on-transition gap** — see the Denomination Spine section; `PoolOps.deployTokenAbove`/`seedFunding`/`removeAll`/`_greenCandle` are all written to move raw base units of whatever `quote` is live, with no decimals lookup anywhere in the call path (grep confirmed: no `decimals()` call in `PoolOps.sol`, `CauldronRegistry.sol`, `CauldronBase.sol`, `RedemptionExt.sol`, `MigrationVesting.sol`, `CauldronToken.sol`, `CauldronFactory.sol`). Evidence: PoolOps.sol:438-442 explicit comment "64 base units is dust in any decimals (64 wei; 0.000064 USDG)".

---

## B3 — The creature cycle MIT→SPIRIT→WRAITH→BEAST→ASTRAL→STORM→repeat

**Where it lives (ACTUAL).** `PoolOps.creatureFor(uint256 gen)`, PoolOps.sol:153-161:
```
uint256 idx = (gen - 1) % 6;
if (idx == 0) return ("Gnomeland", "GNOME");
if (idx == 1) return ("Ethereal Spirit", "SPIRIT");
if (idx == 2) return ("Shadow Wraith", "WRAITH");
if (idx == 3) return ("Infernal Beast", "BEAST");
if (idx == 4) return ("Astral Entity", "ASTRAL");
return ("Storm Elemental", "STORM");
```
**DELTA (naming).** The header comment in CauldronRegistry.sol:48-52 documents "Gen 1: Magic Internet Token (MIT)"; the ACTUAL code returns `("Gnomeland", "GNOME")` for `idx==0` (gen 1) — INTENT (header comment/docstring) names it MIT, ACTUAL code names it GNOME. This is a comment/code mismatch, not a functional bug (flagged, not fixed per rules).

**Reachability (ACTUAL).** `creatureFor` is called ONLY from `summon()` (CauldronRegistry.sol:668, gen 1 unconditionally). Relaunches (gen 2+) do NOT call `creatureFor` — the name/symbol come from `spec.name`/`spec.symbol`, i.e. the winning governance proposal (CauldronRegistry.sol:879-880), confirmed by the code comment at CauldronRegistry.sol:1728-1730: "Relaunches (gen 2+) name from the BrewSpec." So **the 6-creature cycle is NOT auto-applied by the protocol after gen 1** — it exists only as an available naming convention proposers may (or may not) choose to reuse; nothing in code enforces the cycle beyond generation 1.

**DENOMINATION:** N/A — naming only, moves no value.

---

## B4 — Cross-generation claims

### `claimByBurn(fromGen, amount)` — CauldronRegistry.sol:1178-1202
**Authority.** Permissionless caller, gated only by `claimGate` (CauldronRegistry.sol:1187-1189): if a non-zero `claimGate` is set, only `claimGate` or `hook.perpEngine()` may call — else `VestingEnforced`.
**Preconditions.** `fromGen != 0 && fromGen < currentGeneration` (CauldronRegistry.sol:1182) else `CannotClaimCurrentGen`; `generationToken[fromGen] != 0` (:1191) else `UnknownGeneration`; caller balance `>= amount` (:1192) else `NoBalance`.
**Behavior — where "1:1 forever" is ENFORCED.** `PoolOps.migrateOne` (PoolOps.sol:1233-1243): (a) `ICauldronBurn(prevToken).burn(from, amount)` — destroys `amount` of the OLD generation's token; (b) `claimFromReserve(pm, r.positionId, r.key, r.tickLower, r.tickUpper, amount, from)` (PoolOps.sol:1132-1161) pulls exactly `amount` of the CURRENT generation's token out of `generationReservePositionId[currentGeneration]`, an out-of-range single-sided Uniswap v4 position — no price move, no mint; (c) `if (got + CLAIM_DUST < amount) revert("reserve short")` (PoolOps.sol:1242) — the strict 1:1 guarantee: a short reserve reverts the WHOLE call (burn included), so a holder is never given less than they burned. `CLAIM_DUST = 1e12` tolerates Uniswap liquidity-unit rounding (PoolOps.sol:1214).
**What backs the 1:1.** The out-of-range reserve LP position for the CURRENT generation (`generationReservePositionId[currentGeneration]`), which was funded at that generation's seeding with `newReserve = TOTAL_SUPPLY - newActive` tokens of the CURRENT token (CauldronRegistry.sol:1026, 1034) — i.e. it is backed by pre-minted current-generation tokens set aside at birth, not by any escrowed value from the OLD generation.
**Events.** `HolderClaimed(fromGen, msg.sender, claimedAmount)` (CauldronRegistry.sol:1201).

### `claimByBurnUpTo(fromGen, maxAmount)` — CauldronRegistry.sol:1216-1237
Same gating/preconditions. Sizes to reserve capacity first via `PoolOps.migrateUpTo` (PoolOps.sol:1222-1231: `cap = tokenOutForLiquidity(...)`, `amt = min(maxAmount, cap)`), then calls `migrateOne` with the clamped `amt` — so it can NEVER revert on a short reserve, unlike `claimByBurn`. Documented purpose: the perp engine's own inventory sync must not revert mid-`syncGeneration` (CauldronRegistry.sol:1208-1215).

### `MigrationVesting` — `startVest`/`vestBatch`/`claim`
- `startVest(fromGen, amount)` (MigrationVesting.sol:135-145, `nonReentrant`, permissionless): pulls the caller's dead-gen tokens via `_pullAndVest` → `registry.claimByBurn(fromGen, amount)` (MigrationVesting.sol:184) — so the escrow itself is the caller of the registry's strict 1:1 path, and the same `reserve short` revert propagates if the reserve can't cover it.
- `vestBatch(fromGen, holders[])` (MigrationVesting.sol:153-164, permissionless keeper path): per-holder `transferFrom` + `_pullAndVest`; skips (does not revert) a holder with zero pullable balance/allowance (:161), but a holder WITH balance whose `claimByBurn` reverts (reserve short) still reverts the WHOLE batch — no per-holder try/catch around `_pullAndVest`.
- `claim()`/`claimFor(holder)` (MigrationVesting.sol:206-216): releases `_vestedOf(grant) - grant.released` per grant, linear over `grant.window` from `grant.start` (MigrationVesting.sol:244-250); `window==0` (instant tier, via `IStakerOracle.isInstant`, default false if unset — MigrationVesting.sol:252-258) is fully vested at deposit.
- **Enforcement of "vesting is mandatory."** `claimByBurn`/`claimByBurnUpTo`/`autoMigrateBatch` all check `claimGate` and revert `VestingEnforced` for anyone except `claimGate` itself and `hook.perpEngine()` (CauldronRegistry.sol:1187-1189, 1221-1223, 1301). Setting `claimGate` to the deployed `MigrationVesting` address (via `setClaimGate`, CauldronRegistry.sol:481-485, `onlyEmergency` + timelocked when restricting) is what forces ordinary holders through the escrow.

**DENOMINATION for B4: breaks-on-transition** — see Denomination Spine below; a claim always pays in the CURRENT generation's token (never cross-quote converted), but `MigrationVesting`'s `Grant.token` is pinned to "the live token at deposit" (MigrationVesting.sol:87-89) specifically because a LATER relaunch can make that grant's token itself a dead generation — the escrow pays back exactly what it received, never re-migrating an unclaimed grant forward again.

---

## B5 — Generation-keyed storage table (`CauldronBase.sol`)

| Mapping | Slot (comment) | Line | Writers | Readers |
|---|---|---|---|---|
| `generationToken[gen] → address` | — | CauldronBase.sol:179 | `summon` (:674), `relaunch` (:899) | `_removeLiquidity` (:1507), `claimByBurn`/`claimByBurnUpTo` (:1190,1224), `autoMigrateBatch` (:1303), `emergencyWithdrawLP` (:434), `migrateToSuccessor` (:522), `_flushLegacyAtRelaunch` (via param), `RedemptionExt.rotateSliceFrom` (:305), views |
| `generationProposer[gen] → address` | — | CauldronBase.sol:181 | `relaunch` (:956) | `hook.setActiveProposer` (consumed, not stored per-gen elsewhere directly by registry) |
| `generationParent[gen] → uint256` | — | CauldronBase.sol:184 | `relaunch` (:957) | none found in these files (documented "V1 linear chain; V2 branch graph seam", :957 comment) |
| `generationPoolId[gen] → PoolId` | — | CauldronBase.sol:186 | `_recordSeed` (:1692, called from both `summon`→`_seedGeneration` and `relaunch`→`_seedGeneration`) | `relaunch` (`oldPoolId`, :757), `RedemptionExt.rotateSliceFrom`/`completeRotation` (`linkVolume` arg), `floorClaimableNow` (RedemptionExt.sol:524) |
| `generationPoolKey[gen] → PoolKey` | — | CauldronBase.sol:188 | `_recordSeed` (:1693) | `_removeLiquidity` (:1506), `claimByBurn`/`claimByBurnUpTo`/`autoMigrateBatch`/`recycleCollectionNFT`/`buyCollectionNFT` (ReserveRef construction), `RedemptionExt.rotateSliceFrom` (:325) |
| `generationPositionId[gen] → uint256` | — | CauldronBase.sol:190 | `_recordSeed` (:1694) | `_removeLiquidity` (:1513), `migrateToSuccessor` (:503), `RedemptionExt.rotateSliceFrom` (:324) |
| `generationReservePositionId[gen] → uint256` | — | CauldronBase.sol:193 | `_recordSeed` (:1695) | `_removeLiquidity` (:1517), `migrateToSuccessor` (:504), all `claimByBurn`-family calls (ReserveRef), `recycleCollectionNFT`/`buyCollectionNFT` |
| `reserveTickLower[gen] → int24` | — | CauldronBase.sol:195 | `_recordSeed` (:1696) | ReserveRef construction (claim family), `RedemptionExt.floorClaimableNow` (:525) |
| `reserveTickUpper[gen] → int24` | — | CauldronBase.sol:196 | `_recordSeed` (:1697) | same as above |
| `claimed[gen][holder] → bool` | — | CauldronBase.sol:201 | none found in the files read (only a reader, `hasClaimed`, CauldronRegistry.sol:1718-1720) — **DELTA: dead/unwritten mapping**, see Open deltas |
| `generationCollection[gen] → address` | — | CauldronBase.sol:203 | `_deployCollection` (:1118), `_continueMiFrens` (:1143) | `_flushLegacyAtRelaunch`/`crystallizeCollection` (relaunch), `recycleCollectionNFT`/`buyCollectionNFT` |
| `generationVault[gen] → address` | — | CauldronBase.sol:205 | `_deployCollection` (:1119), `_continueMiFrens` (:1144) | `relaunch` (`generationVault[oldGen]` into `seedFunding`, :922; `crystallizeCollection`, :996) |
| `generationQuote[gen] → address` | slot 49 | CauldronBase.sol:332 | `relaunch` (:951); `RedemptionExt.rotateSliceFrom` on rotation completion (:413) | `relaunch` (`generationQuote[oldGen]` into `seedFunding` and `_flushLegacyAtRelaunch`'s siblings, :922, 1635, 1678); `RedemptionExt.rotateSliceFrom` (`fromLeg==0` branch, :323) |
| `generationLegs[gen] → TreasuryLeg[]` | appended, "declared last" | CauldronBase.sol:452 | `RedemptionExt._recordLeg` (:548-556, upsert-by-quote) | `RedemptionExt.legCount`/`legAt` (:533-545), `RedemptionExt.recoverLegs` (:571-590, pops as it recovers), `rotateSliceFrom` `fromLeg>0` branch (:327) |

Note: `TOTAL_SUPPLY`, `POOL_FEE`, `TICK_SPACING`, `GEN1_ACTIVE_TOKENS` are `constant`s (CauldronBase.sol:148-152), not generation-keyed storage — listed here only to confirm they were checked and excluded.

---

## DENOMINATION SPINE

**On `relaunch`, what asset is recovered LP value in?** `ethFromLP` (CauldronRegistry.sol:785, `_removeLiquidity` body :1502-1564) is denominated in `key.currency0` of the DYING generation's pool — i.e. `generationQuote[oldGen]`'s raw base units, NOT necessarily ETH. `PoolOps.removeAll` explicitly measures via `_balance(quote)` delta (`quote = Currency.unwrap(key.currency0)`, PoolOps.sol:1108-1109, 1122), not `address(this).balance` — the code comment at PoolOps.sol:1086-1099 documents this was fixed from a prior bug where a non-native generation reported zero recovered quote.

**Does the code handle a non-ETH ERC20 with non-18 decimals?** Yes, structurally — every amount from `removeAll`/`_greenCandle`/`seedFunding`/`migrateOne` is a raw base-unit `uint256` with no `decimals()` lookup anywhere in scope (grep-confirmed empty across `PoolOps.sol`, `CauldronRegistry.sol`, `CauldronBase.sol`, `RedemptionExt.sol`, `MigrationVesting.sol`, `CauldronToken.sol`, `CauldronFactory.sol`). The exact-output buy settlement buffer is explicitly sized "64 base units is dust in any decimals" (PoolOps.sol:438-442) — i.e. the design deliberately avoids needing decimals awareness by staying in each asset's own base units end to end.

**Do gen-N holders claiming AFTER a relaunch onto a different quote still get 1:1, and in WHICH asset?** Yes — `claimByBurn`/`claimByBurnUpTo` always burn `fromGen`'s token and pay out of `generationReservePositionId[currentGeneration]`, i.e. the CURRENT (live) generation's token, regardless of what quote the OLD generation's pool traded against (CauldronRegistry.sol:1196-1200, 1231-1235). The claim ratio (1:1 token-for-token) is invariant to quote changes because the reserve holds current-gen TOKEN, not the quote asset.

**Any relaunch path assuming `address(0)` (native) or 18 decimals?** One confirmed gap: `RedemptionExt.recoverLegs` (RedemptionExt.sol:571-590) sums `quoteOut` across ALL of a generation's rotated legs (`quoteOut += q` at line 581) regardless of each leg's OWN `quote` asset (`TreasuryLeg.quote`, CauldronBase.sol:441-443) — if a generation rotated into two different quote assets (e.g. both USDG and DAI legs exist, `generationLegs[gen].length > 1` with differing `.quote`), the returned `quoteOut` mixes base units of different assets into one `uint256`. That value flows straight into `CauldronRegistry._removeLiquidity`'s `ethRecovered` (CauldronRegistry.sol:1556-1561, added via `abi.decode(ret, (uint256,uint256))`) and from there into `relaunch`'s `ethFromLP` → `seedFunding`'s `recovered` param, which is priced as if it were entirely `generationQuote[oldGen]` (`oldQuote` param, CauldronRegistry.sol:922). **DENOMINATION: breaks-on-transition** for the specific case of a generation with 2+ rotated legs into 2+ *different* quote assets — flagged as a delta, not fixed (rule 3).

**MigrationVesting: what asset does a vest pay out in, and what if its generation used a different quote than the current one?** A `Grant.token` is pinned at deposit to `registry.generationToken(registry.currentGeneration())` — the LIVE token AT THAT MOMENT (MigrationVesting.sol:180-197), independent of that generation's quote asset (the grant pays in TOKEN units, never quote units, matching `claimByBurn`'s own token-for-token model). If a LATER relaunch happens mid-vest, the grant's `token` becomes a dead-generation token but the escrow still holds and pays out exactly that dead token (comment MigrationVesting.sol:59-61: "a relaunch mid-vest ... never mixes balances") — the holder receives an OLD-generation token, not the new live one, and must separately `claimByBurn` again if they want to migrate forward. This is INTENDED behavior per the comment (not itself a quote/decimals defect).

**Per-feature denomination tags (summary):**
- B1 `summon`: **ETH-only** (CauldronRegistry.sol:672 hardcodes `address(0)`).
- B2 `relaunch`: **quote-agnostic**, except **breaks-on-transition** for multi-quote rotated legs at recovery (RedemptionExt.sol:581, see above).
- B3 creature cycle: N/A (no value moved).
- B4 claims (`claimByBurn`/`claimByBurnUpTo`/`MigrationVesting`): **quote-agnostic** — always token-for-token, never priced in the quote asset.
- B5 storage: N/A (data only); `generationQuote[gen]` is the SPINE record itself.

---

## Open deltas

1. **INTENT vs ACTUAL naming mismatch (B3).** CauldronRegistry.sol:48-52 documents gen 1 as "Magic Internet Token (MIT)"; `PoolOps.creatureFor` (PoolOps.sol:155) returns `("Gnomeland","GNOME")` for gen 1. Comment/code disagreement, not a functional bug.
2. **`claimed[gen][holder]` mapping appears unwritten (B5).** Declared CauldronBase.sol:201, only read via `hasClaimed` (CauldronRegistry.sol:1718-1720); no `claimed[...] = true` write found in `CauldronRegistry.sol`, `CauldronBase.sol`, `RedemptionExt.sol`, or `PoolOps.sol` grep of writers in this pass. Flagged as possibly dead/vestigial storage — not confirmed against files outside this task's scope (e.g. it may be written elsewhere not read in this pass); reported as found, not fixed.
3. **Multi-quote leg recovery sums across denominations (Denomination Spine).** `RedemptionExt.recoverLegs` (RedemptionExt.sol:571-590) has no per-quote grouping; `quoteOut` can mix base units of distinct ERC20s when a generation holds legs in more than one non-primary quote. Flagged, not fixed, per task rules.
