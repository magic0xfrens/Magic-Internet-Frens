# Cluster `pool` — CauldronBase + PoolOps

Files (source tree `contracts/solidity`, repository working tree, re-extracted 2026-09-12):

| file | lines | unit kind |
|---|---|---|
| `cauldron/CauldronBase.sol` | 539 | `abstract contract CauldronBase` + 6 shared interface declarations |
| `cauldron/PoolOps.sol` | 1463 | `library PoolOps` (external, linked, delegatecalled) + 11 interface declarations + 4 structs |

Line numbers are those of the working tree. 71 nodes, all filled; validator reports `COVERAGE pool: 71/71 nodes, 0 failures`.

Two facts frame everything below:

* `CauldronBase` holds **all** the storage and **none** of the logic. It is inherited by `CauldronRegistry` (CauldronRegistry.sol:57) and by the delegatecall facet `RedemptionExt` (RedemptionExt.sol:62); neither adds state.
* `PoolOps` holds **all** the logic and **none** of the storage (`forge inspect PoolOps storageLayout` → empty). Every one of its functions runs by DELEGATECALL from the registry, so `address(this)` is the registry: the registry owns the position NFTs, holds the tokens and the ether, and is the `msg.sender` every counterparty gate keys on (`delegatecall` PoolOps.sol:116).

---

## A. Value inventory

All value-bearing storage is declared in `CauldronBase.sol`; the mutations live in the registry and the facet (PoolOps never writes storage).

| field | denomination | increases | decreases |
|---|---|---|---|
| `genesisReserveOutstanding` (CauldronBase.sol:206) | LIVE generation token units (paid out of the reserve LP) | set at summon `genesisReserveOutstanding` (CauldronRegistry.sol:724); `+= genesisPending` at relaunch (CauldronRegistry.sol:1019); `+= added` on every floor ratchet (RedemptionExt.sol:182) | `-= F` on an OG redemption, guarded by `>=` (RedemptionExt.sol:91) |
| `genesisPending` (CauldronBase.sol:237) | LIVE generation token units | `+= og` on the live legacy path (RedemptionExt.sol:158) and on the relaunch flush (CauldronRegistry.sol:1507) | zeroed once folded forward (CauldronRegistry.sol:1020) |
| `airdropReserve` (CauldronBase.sol:282) | gen-1 token units | owner-set pre-ignition (CauldronRegistry.sol:645) | subtracted from the reserve tranche and transferred out at summon (CauldronRegistry.sol:732, CauldronRegistry.sol:733) |
| `primeBuyEth` (CauldronBase.sol:285) | native wei | `+= msg.value` from the prime funder (CauldronRegistry.sol:661) | reclaim to zero (CauldronRegistry.sol:668); spent into the market buy at summon (CauldronRegistry.sol:752, then `PoolOps.primeBuy` at CauldronRegistry.sol:756) |
| `legProceeds[asset]` (CauldronBase.sol:529) | RAW units of that foreign quote | `+= q` for a recovered leg whose quote is not the primary's (RedemptionExt.sol:831) | zeroed by the owner sweep (RedemptionExt.sol:889) which then pays out through `PoolOps.sendAsset` (RedemptionExt.sol:890) |
| `genesisShares` (CauldronBase.sol:262) / `genesisSharePerFren` (CauldronBase.sol:264) | fren count / token units per fren | owner-set at CauldronRegistry.sol:634; per-fren share fixed at summon (CauldronRegistry.sol:723) | never decreased |
| `generationPositionId` (CauldronBase.sol:198), `generationReservePositionId` (CauldronBase.sol:201), `generationPoolKey` (CauldronBase.sol:196), `generationLegs` (CauldronBase.sol:507) | the LP itself — the real treasury | written by `_recordSeed` (CauldronRegistry.sol:1746); legs appended by the rotation (RedemptionExt.sol:373 reads them back) | positions emptied and burned by `PoolOps.removeAll` (PoolOps.sol:1140) |

Inside PoolOps the value that moves is never a counter, it is a measured balance: `quoteRecovered`/`tokensRecovered` (PoolOps.sol:934, PoolOps.sol:1161), `taken` (PoolOps.sol:1199), `added` (PoolOps.sol:1238), `bought` (PoolOps.sol:478), `got` (PoolOps.sol:521).

## B. Balance vs counter

* **Reserve claims clamp, they do not fail.** `claimFromReserve` caps the withdrawal at the position's live liquidity (PoolOps.sol:1184) and reports what actually arrived (PoolOps.sol:1199). Every caller that owes a full payout re-checks the delta itself: `CLAIM_DUST` (PoolOps.sol:1281) for migration, `CLAIM_DUST` (PoolOps.sol:1437) for the collection recycle, and `1e12` (RedemptionExt.sol:104) for the OG redemption. The tolerance exists because liquidity sizing rounds down (PoolOps.sol:1180).
* **The genesis counter is debited before the pull.** `genesisReserveOutstanding -= F` (RedemptionExt.sol:91) happens before `claimFromReserve` (RedemptionExt.sol:95); the short-claim revert at RedemptionExt.sol:104 is what keeps the counter and the LP in step, and the `>=` guard means a counter smaller than the floor silently debits nothing while the LP still pays.
* **Deposits credit what the position absorbed, not what was offered.** `addToReserve` returns a measured delta (PoolOps.sol:1238); `buyCollection` credits the ledger with `added` rather than `paid` (PoolOps.sol:1459) and `materializeLegacy` credits `credited` (PoolOps.sol:1360). On the relaunch branch there is no position to absorb anything, so the same figure is carried as a pure ledger number after burning the dead token (PoolOps.sol:1364).
* **`seedFunding` sums balances, not counters** — except that the hook's two releases are counter-driven on the hook side (`releaseRelaunchETH` PoolOps.sol:1106, `releaseRelaunchAsset` PoolOps.sol:1099) and both are try/catch'd, so a hook counter that has outrun its balance returns zero here instead of reverting.
* **`legProceeds` is a counter over the registry's own balance.** The sweep sends the counter (RedemptionExt.sol:889) and the transfer itself is the only check that the balance is there (`require` PoolOps.sol:1118).

## C. Authority map

| gate | held by | where | rotatable? |
|---|---|---|---|
| `onlyOwner` | registry owner (intended: governance timelock) | `renounceOwnership` (CauldronBase.sol:464) reverts `RenounceDisabled` (CauldronBase.sol:465) | transferable, **not** renounceable — the dead-end door is closed |
| owner **or** `igniter` | ignition role (CauldronBase.sol:331) | `NotAdmin` (CauldronRegistry.sol:695) — one-shot summon | igniter is a separate slot so ownership can stay with the timelock |
| state-gated, no role | anyone | relaunch: `TokenStillAlive` (CauldronRegistry.sol:797), `TooYoung` (CauldronRegistry.sol:802), `NoProposal` (CauldronRegistry.sol:805) | n/a |
| PoolManager + armed window | the v4 PoolManager | `NotPoolManager` (CauldronRegistry.sol:1765) plus `_seedBuyUnlocked` (CauldronRegistry.sol:1766), armed only around a seed (CauldronRegistry.sol:1727 / CauldronRegistry.sol:1740) | flag is transient per seed |
| circuit breaker | `redemptionPaused` (CauldronBase.sol:270), forced open while an emergency is armed | `_redeemBlocked` (CauldronBase.sol:433), used at RedemptionExt.sol:79 and CauldronRegistry.sol:1517 | yes, owner/guardian side |
| vesting gate | `claimGate` (CauldronBase.sol:278) | `VestingEnforced` (CauldronRegistry.sol:1253, CauldronRegistry.sol:1354, RedemptionExt.sol:659) | zero = feature off |
| guild mandate | `treasuryGovernor` (CauldronBase.sol:371) via `NoRotationApproved` (RedemptionExt.sol:317) | the only gate on `removePartial`/`openOrAddPair`/`sendAsset` in normal operation | wiring is owner-set, replaceable |
| counterparty gates facing this cluster | hook, vault, token, ledger, collection | `releaseRelaunchETH` (CauldronHook.sol:1711), `releaseRelaunchAsset` (CauldronHook.sol:1739), `sweepLegacyReserve` (CauldronHook.sol:1194), `close` (CauldronVault.sol:117), `burn` (CauldronToken.sol:58), `onlyRegistry` (CollectionLedger.sol:117), `custodyTransfer` (CauldronCollection.sol:395) / `custodyTransfer` (MiFrensGenesis.sol:414) | all satisfied because PoolOps is delegatecalled — they see the registry |

**The library's own surface is ungated.** `PoolOps` is a deployed contract with 22 external/public entry points (its `methodIdentifiers` list); calling any of them directly executes in the caller's own context, where no generation state, tokens or positions exist. Four of them are `public`, so they are reachable both internally and at the library address: `claimFromReserve` (PoolOps.sol:1171), `addToReserve` (PoolOps.sol:1211), `migrateOne` (PoolOps.sol:1272), `doLegacyNote` (PoolOps.sol:1322). One external entry point has no in-protocol caller at all: `createAndSeed` (PoolOps.sol:197).

## D. External calls with value, and CEI ordering

| function | calls, in order | value | ordering |
|---|---|---|---|
| `_approve` (PoolOps.sol:176) | `approve` (PoolOps.sol:177) → `approve` (PoolOps.sol:178) | none | ERC20 allowance then Permit2 allowance, 300 s expiry |
| `createAndSeed` (PoolOps.sol:197) | `initialize` (PoolOps.sol:222) → `_seedActive` (PoolOps.sol:225) → `_seedReserve` (PoolOps.sol:231) | quote paid inside the mints | no state to protect (library) |
| `createAndSeedProgressive` (PoolOps.sol:252) | non-native: `initialize` (PoolOps.sol:298) → `_seedReserve` (PoolOps.sol:303) → `_seedActive` (PoolOps.sol:307); native: `_greenCandle` (PoolOps.sol:338) → `approve` (PoolOps.sol:343) → `startSeed` (PoolOps.sol:344) | **sends native** to the seeder (PoolOps.sol:344) and approves it the streamed tokens (PoolOps.sol:343) | the seeder pulls the token side itself; the approval is the single funding path |
| `createAndSeedWithBuy` (PoolOps.sol:375) | `_greenCandle` (PoolOps.sol:399) | via the candle | — |
| `_greenCandle` (PoolOps.sol:448) | `initialize` (PoolOps.sol:467) → `_seedActive` (PoolOps.sol:471) → `unlock` (PoolOps.sol:477) → `getSlot0` (PoolOps.sol:482) → `_seedReserve` (PoolOps.sol:486) | the unlock re-enters the registry and spends its quote | the buy is made **after** the LP exists, and the reserve band is placed **after** the buy settles |
| `executeBuy` (PoolOps.sol:498) | `swap` (PoolOps.sol:509) → native `settle` (PoolOps.sol:539) **or** `sync` (PoolOps.sol:541) + checked `transfer` (PoolOps.sol:564) + `settle` (PoolOps.sol:566) → `take` (PoolOps.sol:568) | **sends native or ERC20** to the PoolManager, receives the token | swap → settle → take, the v4 order; the ERC20 return value is required (PoolOps.sol:565) |
| `primeBuy` (PoolOps.sol:581) | `unlock` (PoolOps.sol:585) | spends exactly `ethIn`, token straight to the recipient | — |
| `deployTokenAbove` (PoolOps.sol:682) | `CauldronToken` creation (PoolOps.sol:707 or PoolOps.sol:718) | the new token mints its whole supply to the registry | mined address asserted (PoolOps.sol:710) before use |
| `_seedActive` (PoolOps.sol:722) | `_approve` (PoolOps.sol:732) → `nextTokenId` (PoolOps.sol:756) → `modifyLiquidities` (PoolOps.sol:761) **or** `_approve` (PoolOps.sol:763) + `modifyLiquidities` (PoolOps.sol:764) | **native forwarded** only when the quote is `address(0)` | id is predicted before the mint, never re-read |
| `_seedReserve` (PoolOps.sol:770) | `liquidityForTokenOut` (PoolOps.sol:779) → `_approve` (PoolOps.sol:794) → `nextTokenId` (PoolOps.sol:808) → `modifyLiquidities` (PoolOps.sol:809) | token pulled by the PositionManager | zero-liquidity early return (PoolOps.sol:793) before any call |
| `openOrAddPair` (PoolOps.sol:834) | `initialize` (PoolOps.sol:877) in try → `getSlot0` (PoolOps.sol:880) in catch → `_seedActive` (PoolOps.sol:885) | both legs paid in the mint | live price read **before** sizing |
| `removePartial` (PoolOps.sol:905) | `getPositionLiquidity` (PoolOps.sol:914) → `_balance`/`balanceOf` (PoolOps.sol:920, PoolOps.sol:921) → `modifyLiquidities` (PoolOps.sol:932) → deltas (PoolOps.sol:934, PoolOps.sol:935) | TAKE_PAIR delivers to the registry | measure-before/after around the single interaction |
| `seedFunding` (PoolOps.sol:1000) | `close` (PoolOps.sol:1013) in try → `_pullAsset` (PoolOps.sol:1077) → `_pullEth` (PoolOps.sol:1083) → `_pullAsset` (PoolOps.sol:1088) | receives native from the vault and the hook, ERC20 from the hook | every external call is best-effort; nothing here can revert the rebirth |
| `sendAsset` (PoolOps.sol:1109) | `to.call{value}` (PoolOps.sol:1112) **or** `asset.call(transfer)` (PoolOps.sol:1116) | **sends native or ERC20 to an arbitrary address** | both outcomes required (PoolOps.sol:1113, PoolOps.sol:1117) |
| `removeAll` (PoolOps.sol:1140) | `getPositionLiquidity` (PoolOps.sol:1144) → balances (PoolOps.sol:1148, PoolOps.sol:1149) → `modifyLiquidities` (PoolOps.sol:1159) → deltas (PoolOps.sol:1161, PoolOps.sol:1162) | both currencies to the registry, NFT burned (PoolOps.sol:1152) | — |
| `claimFromReserve` (PoolOps.sol:1171) | `liquidityForTokenOut` (PoolOps.sol:1180) → `getPositionLiquidity` (PoolOps.sol:1183) → `balanceOf` (PoolOps.sol:1187) → `modifyLiquidities` (PoolOps.sol:1197) → `balanceOf` (PoolOps.sol:1199) | token delivered straight to `recipient` (PoolOps.sol:1195) | recipient-measured delta |
| `addToReserve` (PoolOps.sol:1211) | `liquidityForTokenOut` (PoolOps.sol:1220) → `_approve` (PoolOps.sol:1224) → `balanceOf` (PoolOps.sol:1225) → `modifyLiquidities` (PoolOps.sol:1235) → `balanceOf` (PoolOps.sol:1238) | token pulled from the registry | — |
| `migrateUpTo` (PoolOps.sol:1261) | `getPositionLiquidity` (PoolOps.sol:1265) → `migrateOne` (PoolOps.sol:1269) | see below | capacity read before the burn |
| `migrateOne` (PoolOps.sol:1272) | `burn` (PoolOps.sol:1275) → `claimFromReserve` (PoolOps.sol:1276) | burns old token, delivers new | **burn first**, then claim; shortfall reverts both (PoolOps.sol:1281) |
| `autoMigrateBatch` (PoolOps.sol:1298) | per holder: `autoMigrate` (PoolOps.sol:1304) → `balanceOf` (PoolOps.sol:1305) → `getPositionLiquidity` (PoolOps.sol:1309) → `migrateOne` (PoolOps.sol:1312) | as `migrateOne` | capacity re-read every iteration |
| `doLegacyNote` (PoolOps.sol:1322) | `totalMinted` (PoolOps.sol:1327) → `credit` (PoolOps.sol:1335) or `credit` (PoolOps.sol:1337) | none | accounting only |
| `materializeLegacy` (PoolOps.sol:1349) | `legacyRegistry` (PoolOps.sol:1356) → `sweepLegacyReserve` (PoolOps.sol:1357) → `addToReserve` (PoolOps.sol:1360) **or** `burn` (PoolOps.sol:1364) → `doLegacyNote` (PoolOps.sol:1366) | ERC20 swept in from the hook | the credit is issued only after the tokens are backed |
| `crystallizeCollection` (PoolOps.sol:1374) | `crystallized` (PoolOps.sol:1379) → `outstanding` (PoolOps.sol:1387) → `crystallize` (PoolOps.sol:1388) | none | idempotence checked first |
| `recycleCollection` (PoolOps.sol:1395) | `ownerOf` (PoolOps.sol:1404) → `GENESIS_SUPPLY` staticcall (PoolOps.sol:1425) → `totalMinted` (PoolOps.sol:1431) → `redeem` (PoolOps.sol:1432) → `custodyTransfer` (PoolOps.sol:1433) → `claimFromReserve` (PoolOps.sol:1434) | NFT in, tokens out | **checks-effects-interactions**: ledger debited and NFT moved before the reserve is drawn; shortfall reverts everything (PoolOps.sol:1437) |
| `buyCollection` (PoolOps.sol:1443) | `ownerOf` (PoolOps.sol:1453) → `totalMinted` (PoolOps.sol:1454) → `floorPerNFT` (PoolOps.sol:1455) → `transferFrom` (PoolOps.sol:1457) → `addToReserve` (PoolOps.sol:1458) → `buyback` (PoolOps.sol:1459) → `custodyTransfer` (PoolOps.sol:1460) | payment pulled in, NFT out | payment first, NFT last |

**Trust of the callee address (DERIVED).** `PoolOps` is a linked library, so every address it
calls arrives as a call argument. The v4 singletons stay TRUSTED: `PERMIT2` (PoolOps.sol:178) is a
constant and the registry hands its own immutable manager to `poolManager` (PoolOps.sol:222) and
`pm` (PoolOps.sol:1197). The **token** addresses are not, and are now labelled UNTRUSTED to match
their siblings `IERC20` (PoolOps.sol:177), `IERC20` (PoolOps.sol:921) and `IERC20`
(PoolOps.sol:1122): `token` (PoolOps.sol:343), `Currency` (PoolOps.sol:1187), `Currency`
(PoolOps.sol:1199), `token` (PoolOps.sol:1225), `token` (PoolOps.sol:1238), `prevToken`
(PoolOps.sol:1275), `prevToken` (PoolOps.sol:1305), `token` (PoolOps.sol:1364) and `token`
(PoolOps.sol:1457) are each whatever the caller supplies, and `token` (PoolOps.sol:1225) is read
straight out of the caller's own key at `token` (PoolOps.sol:1223).

DERIVED: the two `CauldronToken` creations, `new` (PoolOps.sol:707) and `new` (PoolOps.sol:718),
are listed in the table above but carry no graph edge — a constructor has no function name for an
edge to name at the call site.

## E. Loops

| loop | bound | who can grow it |
|---|---|---|
| Babylonian sqrt `while (z < y)` (PoolOps.sol:188) | converges in O(log) steps on a 256-bit value | nobody — arithmetic only |
| salt search `for (uint256 i; i < SALT_TRIES; ++i)` (PoolOps.sol:701) | `SALT_TRIES` = 1024 (PoolOps.sol:620), one keccak per try, exits on the first hit | the quote's address decides the expected hit rate; exhaustion returns unmined (PoolOps.sol:718) rather than reverting |
| keeper batch `for (uint256 i = 0; i < holders.length; i++)` (PoolOps.sol:1302) | **unbounded** — the caller supplies the array | the caller; each iteration costs an external `autoMigrate` (PoolOps.sol:1304), a `balanceOf` (PoolOps.sol:1305), a `getPositionLiquidity` (PoolOps.sol:1309) and, when it proceeds, a full burn + reserve withdrawal in `migrateOne` (PoolOps.sol:1312) |

No loop in this cluster iterates a protocol-grown list; the leg loop lives on the facet (`recoverLegs`, RedemptionExt.sol:788).

## F. Denomination and units

* **The quote side is polymorphic.** `address(0)` means native ether, anything else is an ERC20 of unknown decimals. The only branch points are `_balance` (PoolOps.sol:1122), the mint funding split at `quote` (PoolOps.sol:759), the settle split at `q` (PoolOps.sol:537), and the payout split at `asset` (PoolOps.sol:1111). Everything else works in raw units.
* **Price is computed from RAW amounts**: `_sqrtPrice` (PoolOps.sol:182) divides token raw units by quote raw units, so the sqrt price already encodes the decimals difference; the orientation (quote = currency0) is guaranteed by mining the token above `QUOTE_WATERMARK` (PoolOps.sol:647) and asserted again at `require` (PoolOps.sol:846).
* **Fixed-point constants**: `SEED_FLOOR_WAD` (PoolOps.sol:137), `SEED_MINSTEP_WAD` (PoolOps.sol:138) and `SEED_BASE_WAD` (PoolOps.sol:145) are 1e18-scaled fractions applied to raw amounts (PoolOps.sol:335, PoolOps.sol:336); `bps` is 1e4-scaled (PoolOps.sol:917); `MAX_ROTATION_BPS` = 5000 (PoolOps.sol:941).
* **Decimals-agnostic dust**: `BUY_SETTLE_BUFFER` = 64 RAW units (PoolOps.sol:625), subtracted unconditionally at `ethActive` (PoolOps.sol:463); `CLAIM_DUST` = 1e12 (PoolOps.sol:1253) is in the generation TOKEN's 18-decimal units, which is the only asset it is ever compared against (PoolOps.sol:1281, PoolOps.sol:1437).
* **`seedFunding` returns a pair, not a number** — `(quoteUsed, amount, vaultSwept)` with the amount in the returned asset's own units (PoolOps.sol:1077, PoolOps.sol:1083, PoolOps.sol:1088), and it deliberately performs no conversion: the preference order never mixes two denominations into one sum.
* **`crystallizeCollection` converts across assets**: `mulDiv(swept, activeBase, totalETH)` (PoolOps.sol:1380) where `swept` is NATIVE ether from the dying vault (`close` CauldronVault.sol:116) and `totalETH` is denominated in the NEWBORN's quote as chosen by `seedFunding` (PoolOps.sol:1000). The two are the same unit only when the newborn launches native.
* **`quoteScale` (CauldronBase.sol:415)** — the governance-set wei-per-raw-unit scalar — is declared in this cluster and read nowhere in it (DERIVED: no occurrence in PoolOps.sol, and only the declaration in CauldronBase.sol).

## G. `unchecked` blocks and rounding

There is **no `unchecked` block** in either file (DERIVED: grep for `unchecked` over both files returns nothing). All arithmetic is checked; the rounding that matters is therefore explicit:

| site | direction | consequence |
|---|---|---|
| `liquidityForTokenOut` (PoolOps.sol:779, PoolOps.sol:1180, PoolOps.sol:1220) | DOWN | dust maps to zero liquidity → `_seedReserve` returns 0 (PoolOps.sol:793), `addToReserve` returns 0 (PoolOps.sol:1221), claims land a few wei short (the reason `CLAIM_DUST` exists, PoolOps.sol:1253) |
| `mulDiv` for `ethActive` (PoolOps.sol:462) | DOWN, then a fixed 64-unit subtraction (PoolOps.sol:463) | makes the exact-output settlement buffer unconditional instead of dependent on a remainder |
| `mulDiv` for the entitlement (PoolOps.sol:1380) | DOWN | entitled tokens never exceed the swept-value share |
| base tranche split (PoolOps.sol:335, PoolOps.sol:336) | DOWN on both legs | keeps `baseEth/baseTok` at the ledger-A ratio; remainders stay in the streamed tranche |
| rotation share `liquidity * bps / 10_000` (PoolOps.sol:917) | DOWN | a zero share returns (0,0) (PoolOps.sol:918) |
| OG/forged split (PoolOps.sol:1331, PoolOps.sol:1332) | `ogShare` DOWN, remainder to the forged share | no wei is created or lost |
| creature index `(gen - 1) % 6` (PoolOps.sol:154) | n/a | `gen == 0` would underflow-revert (checked arithmetic) |

## H. Comment-vs-code observations

1. `everMoved` (CauldronBase.sol:41) is documented as the gate for the paid re-enchant; the only code that reads the flag is `everMoved` (MiFrensDividend.sol:449) through its own declaration (MiFrensDividend.sol:12). The declaration in this cluster has no caller.
2. `relaunch` (CauldronBase.sol:52) is documented as MUST-see-zero on `openCount` before returning; `relaunch` (CauldronRegistry.sol:785) never reads it — its only perp step is a try/catch `syncGeneration` (CauldronRegistry.sol:1115) whose failure is swallowed, and the zero-open check lives in the hook (`openCount` CauldronHook.sol:1874).
3. `createAndSeed` (CauldronRegistry.sol:1668) is described as still exposed "for reference / external callers"; it has no caller in the repo, while both live seed paths go through `_createPoolAndSeedWithBuy` (CauldronRegistry.sol:1738) and `createAndSeedProgressive` (CauldronRegistry.sol:1729).
4. `activePositionId` (PoolOps.sol:244) is documented as "left 0 — there is no single active position"; it is set on both branches, at `_seedActive` (PoolOps.sol:307) and inside the candle at `activePositionId` (PoolOps.sol:470).
5. `registry` (PoolOps.sol:248) says the registry "will call this ... once its EIP-170 wiring lands"; the registry already calls it at `createAndSeedProgressive` (CauldronRegistry.sol:1729).
6. `nextSeedWindow` (CauldronRegistry.sol:1701) says the progressive path has "No green-candle buy — the reserve is placed silently single-sided"; the code folds the reserve into a base tranche and buys it out at `_greenCandle` (PoolOps.sol:338).
7. Storage slot comments drift from the compiled layout from `nextSeedWindow` (CauldronBase.sol:317) onward — see the storage section below.
8. `IVaultClose` (CauldronBase.sol:44) is declared as the vault-close surface and imported by the registry (CauldronRegistry.sol:27), but the close is performed through the duplicate declaration `IVaultCloseOps` (PoolOps.sol:70) at `close` (PoolOps.sol:1013). Same shape for `IMiFrensContinuable` (CauldronBase.sol:34) vs `IColMinted` (PoolOps.sol:51), `IPositionManager` (CauldronBase.sol:66) vs `IPositionManagerOps` (PoolOps.sol:31), and `ICollectionLedger` (CauldronBase.sol:59) vs `ILedgerOps` (PoolOps.sol:48).

## Extra 1 — the generation lifecycle, as `CauldronBase` sees it

Every phase variable lives in this file; every transition is written by the registry (the facet writes only `generationQuote` and the legs).

| variable | line | meaning | written by |
|---|---|---|---|
| `summoned` | CauldronBase.sol:179 | one-shot ignition latch | `summoned = true` (CauldronRegistry.sol:699), never cleared |
| `currentGeneration` | CauldronBase.sol:183 | the live iteration | `= 1` at summon (CauldronRegistry.sol:700); `= newGen` at relaunch (CauldronRegistry.sol:857), where `newGen = oldGen + 1` (CauldronRegistry.sol:856) |
| `currentToken` | CauldronBase.sol:184 | the live ERC20 | CauldronRegistry.sol:710 (summon), CauldronRegistry.sol:935 (relaunch) |
| `lastSummonAt` | CauldronBase.sol:292 | start of the grace clock | CauldronRegistry.sol:701, CauldronRegistry.sol:858 |
| `minLifetime` | CauldronBase.sol:294 | grace length, default 1 hour | owner setter; read at `TooYoung` (CauldronRegistry.sol:802) |
| `_seedBuyUnlocked` | CauldronBase.sol:182 | transient unlock permission for the green candle | armed/cleared around the prime buy (CauldronRegistry.sol:755, CauldronRegistry.sol:757) and around the seed (CauldronRegistry.sol:1727, CauldronRegistry.sol:1740); read at CauldronRegistry.sol:1766 |
| `generationToken` | CauldronBase.sol:187 | gen → ERC20 | CauldronRegistry.sol:711, CauldronRegistry.sol:936 |
| `generationQuote` | CauldronBase.sol:358 | gen → quote asset (0 = native) | CauldronRegistry.sol:1000 at rebirth; **flipped mid-life** by a completed rotation at RedemptionExt.sol:527 |
| `generationPoolId` / `generationPoolKey` | CauldronBase.sol:194 / CauldronBase.sol:196 | the primary pair | `_recordSeed` (CauldronRegistry.sol:1746) |
| `generationPositionId` / `generationReservePositionId` | CauldronBase.sol:198 / CauldronBase.sol:201 | the two positions | `_recordSeed` (CauldronRegistry.sol:1746) |
| `reserveTickLower` / `reserveTickUpper` | CauldronBase.sol:203 / CauldronBase.sol:204 | the reserve band | `_recordSeed` (CauldronRegistry.sol:1746) |
| `generationLegs` | CauldronBase.sol:507 | every pool beyond the primary | appended by the rotation, read at RedemptionExt.sol:373 and drained at RedemptionExt.sol:788 |
| `generationProposer` / `generationParent` | CauldronBase.sol:189 / CauldronBase.sol:192 | provenance | CauldronRegistry.sol:1005, CauldronRegistry.sol:1006 |
| `generationCollection` / `generationVault` | CauldronBase.sol:229 / CauldronBase.sol:231 | the brew's NFT side | CauldronRegistry.sol:1183/CauldronRegistry.sol:1184 (new brew) or CauldronRegistry.sol:1208/CauldronRegistry.sol:1209 (MiFrens continuation) |
| `redemptionPaused` / `emergencyReadyAt` / `guardian` | CauldronBase.sol:270 / CauldronBase.sol:290 / CauldronBase.sol:272 | the exit circuit breaker and the armed-action clock | CauldronRegistry.sol:454, CauldronRegistry.sol:421 (arm), CauldronRegistry.sol:409 and CauldronRegistry.sol:440 (disarm/veto) |
| `seeder` / `nextSeedWindow` | CauldronBase.sol:313 / CauldronBase.sol:317 | progressive opt-in; both non-zero selects the streamed path | read at CauldronRegistry.sol:1728 |
| `allowedQuote` / `quoteScale` | CauldronBase.sol:347 / CauldronBase.sol:415 | the curated quote set and its magnitude scalar | CauldronRegistry.sol:175/CauldronRegistry.sol:176 at deploy (native), CauldronRegistry.sol:321/CauldronRegistry.sol:323 by the owner |
| `quoteRotator` / `treasuryGovernor` | CauldronBase.sol:365 / CauldronBase.sol:371 | rotation wiring | set on the facet (`setRotationWiring`), read at RedemptionExt.sol:301 |
| `igniter` | CauldronBase.sol:331 | the one non-owner that may summon | read at CauldronRegistry.sol:695 |
| `poolManager` / `positionManager` / `hook` / `redemptionExt` | CauldronBase.sol:302–CauldronBase.sol:307 | former immutables, promoted to storage so the facet reads them under delegatecall | registry constructor (e.g. CauldronRegistry.sol:168) |

Lifecycle in one line: `summon` (owner/igniter, once) → deploy token → seed (atomic candle or progressive) → trading, with optional rotations that append legs and can flip `generationQuote` → death detected by the hook → `relaunch` (permissionless, governance-fed) which removes the LP, chooses the newborn's denomination in `seedFunding` (PoolOps.sol:1000), deploys the next token and seeds again.

## Extra 2 — registry ↔ facet shared storage

Compiled layouts (`audit/graph/cache/*.storageLayout.json`) for `CauldronBase`, `CauldronRegistry` and `RedemptionExt` each carry **60 entries** and agree on **slot, offset and label for all 60** — the shared prefix is the entire layout, and no two diverge at any slot. The only differences are AST-id suffixes inside type identifiers (`CauldronRegistry` compiles the same struct/enum/contract types with different ids); `CauldronBase` and `RedemptionExt` are byte-identical including those ids.

Slot map (label — slot.offset): `_owner` 0.0 (from Ownable), `nextReserveCeilingOffset` 0.20, `summoned` 0.23, `_seedBuyUnlocked` 0.24, `currentGeneration` 1, `currentToken` 2, `generationToken` 3, `generationProposer` 4, `generationParent` 5, `generationPoolId` 6, `generationPoolKey` 7, `generationPositionId` 8, `generationReservePositionId` 9, `reserveTickLower` 10, `reserveTickUpper` 11, `genesisReserveOutstanding` 12, `claimed` 13, `generationCollection` 14, `generationVault` 15, `collectionLedger` 16, `genesisPending` 17, `factory` 18, `governor` 19, `nftMaxSupply` 20, `royaltyDividend` 21.0, `royaltyBps` 21.20, `genesisMode` 22, `genesisBaseURI` 23, `genesisRenderer` 24, `mifrens` 25, `genesisBonusBps` 26, `genesisShares` 27, `genesisSharePerFren` 28, `enchantFeeMultBps` 29, `redemptionPaused` 30.0, `guardian` 30.1, `successor` 31, `claimGate` 32, `airdropWallet` 33, `airdropReserve` 34, `primeBuyEth` 35, `primeFunder` 36, `emergencyReadyAt` 37, `lastSummonAt` 38, `minLifetime` 39, `autoMigrate` 40, `poolManager` 41, `positionManager` 42, `hook` 43, `redemptionExt` 44, `seeder` 45.0, `nextSeedWindow` 45.20, `igniter` 46, `allowedQuote` 47, `generationQuote` 48, `quoteRotator` 49, `treasuryGovernor` 50, `quoteScale` 51, `generationLegs` 52, `legProceeds` 53.

Observation (DERIVED, from the three cached layouts): the in-source slot comments are correct through `redemptionExt` (CauldronBase.sol:307, slot 44) and `seeder` (CauldronBase.sol:313, slot 45), then drift by one for every variable after the packing of `nextSeedWindow` (CauldronBase.sol:317) into slot 45 beside `seeder` — the comment says slot 46. Consequently `igniter` (CauldronBase.sol:331) is slot 46 not 47, `allowedQuote` (CauldronBase.sol:347) is 47 not 48, `generationQuote` (CauldronBase.sol:358) is 48 not 49, `quoteRotator` (CauldronBase.sol:365) is 49 not 50, `treasuryGovernor` (CauldronBase.sol:371) is 50 not 51, and `quoteScale` (CauldronBase.sol:415) is 51 not 52. The `autoMigrate` (CauldronBase.sol:297) comment "(slot 40)" and the header claim that slots 0..40 are preserved both hold. The invariant the header actually requires — registry layout == facet layout (CauldronBase.sol:79) — holds exactly.

## Extra 3 — reads of live pool state in `PoolOps`, and what is derived from them

| read | line | derived |
|---|---|---|
| `getSlot0` (post-buy tick) | PoolOps.sol:482 | `finalTick` → the reserve band via `reserveTicks` (PoolOps.sol:484), so the band sits below the POST-buy spot rather than the launch tick |
| `getSlot0` (live sqrt price, in the `initialize` catch) | PoolOps.sol:880 | zero ⇒ the pool does not exist ⇒ re-throw `PoolInitRefused` (PoolOps.sol:881); non-zero ⇒ replaces the contributed price so the top-up is sized at the live price (PoolOps.sol:882) |
| `getPositionLiquidity` | PoolOps.sol:914 | the rotation's `take` = liquidity·bps/10000 (PoolOps.sol:917) |
| `getPositionLiquidity` | PoolOps.sol:1144 | the whole-position withdrawal amount at death |
| `getPositionLiquidity` | PoolOps.sol:1183 | the cap `have` that clamps a reserve claim (PoolOps.sol:1184) |
| `getPositionLiquidity` | PoolOps.sol:1265 | reserve capacity → `amt = min(maxAmount, cap)` (PoolOps.sol:1267) |
| `getPositionLiquidity` | PoolOps.sol:1309 | per-holder capacity in the keeper loop → skip when `bal > cap` (PoolOps.sol:1311) |
| swap deltas `delta.amount0/amount1` | PoolOps.sol:519, PoolOps.sol:520 | `ethIn` owed to the pool and `got` owed to us — what is settled (PoolOps.sol:539/PoolOps.sol:564) and taken (PoolOps.sol:568) |
| unlock return | PoolOps.sol:478 | `bought` — the exact reserve size re-parked out of range (PoolOps.sol:486) |
| native/ERC20 balance via `_balance` | PoolOps.sol:1122 | before/after deltas for quote recovery (PoolOps.sol:934, PoolOps.sol:1161) |
| `balanceOf` of the registry | PoolOps.sol:921, PoolOps.sol:935, PoolOps.sol:1149, PoolOps.sol:1162, PoolOps.sol:1225, PoolOps.sol:1238 | token-side recovery and the amount a reserve top-up actually consumed |
| `balanceOf` of the recipient | PoolOps.sol:1187, PoolOps.sol:1199 | `taken` — what a claimant really received |
| `balanceOf` of a holder | PoolOps.sol:1305 | the batch migration amount |

Note what is **not** read: no TWAP, no oracle, and no `slot0` read on the seed path other than the post-buy tick; the launch price is arithmetic (`_sqrtPrice`, PoolOps.sol:181), not observed.

## I. Function inventory

Format: `contract.name (line) — authority — value effect`.

**CauldronBase.sol — interface declarations**

| node | authority | value |
|---|---|---|
| `ICauldronFactory.deployBrew` (25) | anyone (implementation ungated) | none |
| `ICauldronFactory.deployVault` (26) | anyone (implementation ungated) | none |
| `IMiFrensContinuable.setMinter` (32) | deployer or registry | none |
| `IMiFrensContinuable.setVault` (33) | deployer or registry | none |
| `IMiFrensContinuable.totalMinted` (34) | anyone (view) — no caller in this cluster | none |
| `IMiFrensContinuable.custodyTransfer` (38) | registry | NFT custody move |
| `IMiFrensContinuable.everMoved` (41) | anyone (view) — no caller anywhere | none |
| `IVaultClose.close` (45) | registry — declaration unused | vault sweeps native to the registry |
| `IPerpSync.syncGeneration` (51) | anyone | none |
| `IPerpSync.openCount` (55) | anyone (view) — no caller in registry/facet | none |
| `ICollectionLedger.totalEntitled` (59) | anyone (view) | none |
| `IPositionManager.modifyLiquidities` (67) | anyone (v4 authorizes per position) | payable |
| `IPositionManager.nextTokenId` (68) | anyone (view) | none |
| `IPositionManager.getPositionLiquidity` (69) | anyone (view) | none |

**CauldronBase.sol — the base itself**

| node | authority | value |
|---|---|---|
| `CauldronBase.floorPerFren` (376) | anyone | none (reads `genesisShares`, `genesisReserveOutstanding`) |
| `CauldronBase._redeemBlocked` (386) | internal | none |
| `CauldronBase.constructor` (390) | deployer | none (sets the owner via Ownable) |
| `CauldronBase.renounceOwnership` (417) | owner | none — always reverts |

**PoolOps.sol — interface declarations**

| node | authority | value |
|---|---|---|
| `IPositionManagerOps.modifyLiquidities` (32) | anyone (v4) | payable; the only value-forwarding call is PoolOps.sol:761 |
| `IPositionManagerOps.nextTokenId` (33) | anyone (view) | none |
| `IPositionManagerOps.getPositionLiquidity` (34) | anyone (view) | none |
| `ILedgerOps.redeem` (42) | registry | none (accounting) |
| `ILedgerOps.buyback` (43) | registry | none |
| `ILedgerOps.floorPerNFT` (44) | anyone (view) | none |
| `ILedgerOps.credit` (45) | registry | none |
| `ILedgerOps.crystallize` (46) | registry | none |
| `ILedgerOps.crystallized` (47) | anyone (view) | none |
| `ILedgerOps.totalEntitled` (48) | anyone (view) — unused here | none |
| `IColMinted.totalMinted` (52) | anyone (view) | none |
| `IVaultRedeemedOps.redeemed` (55) | anyone (view) — unused here | none |
| `IVaultRedeemedOps.outstanding` (57) | anyone (view) | none |
| `IHookReserves.releaseRelaunchETH` (65) | registry | native into the registry |
| `IHookReserves.releaseRelaunchAsset` (66) | registry | ERC20 into the registry |
| `IVaultCloseOps.close` (71) | registry | native into the registry |
| `ICollectionOps.custodyTransfer` (75) | registry / collection deployer | NFT custody move |
| `ICollectionOps.ownerOf` (76) | anyone (view) | none |
| `ILegacyHookOps.sweepLegacyReserve` (80) | the hook's `legacyRegistry` | ERC20 into the registry |
| `ILegacyHookOps.legacyRegistry` (81) | anyone (view) | none |
| `ICauldronBurn.burn` (85) | registry | destroys token supply |
| `IAutoFlag.autoMigrate` (88) | anyone (view, self-call) | none |
| `IPermit2Ops.approve` (101) | anyone (per-sender allowance) | none |

**PoolOps.sol — the library**

| node | authority | value |
|---|---|---|
| `creatureFor` (153) | ungated at the library; igniter/owner in-protocol | none |
| `_approve` (176) | internal | none (allowances) |
| `_sqrtPrice` (181) | internal | none |
| `createAndSeed` (197) | ungated; **no in-protocol caller** | quote spent inside `_seedActive` |
| `createAndSeedProgressive` (252) | ungated; summon/relaunch in-protocol | sends native + tokens to the seeder |
| `createAndSeedWithBuy` (375) | ungated; summon/relaunch in-protocol | whole tranche into the pool via the candle |
| `_greenCandle` (448) | internal | mint + exact-output buy, self-funding from `ethAmt` |
| `executeBuy` (498) | PoolManager, inside the armed window | settles native or ERC20, takes the token |
| `primeBuy` (581) | ungated; igniter/owner in-protocol | spends `ethIn`, token to a recipient |
| `deployTokenAbove` (682) | ungated; summon/relaunch in-protocol | new token mints its supply to the registry |
| `_seedActive` (722) | internal | native forwarded or quote pulled |
| `_seedReserve` (770) | internal | token pulled; no quote leg |
| `openOrAddPair` (834) | ungated; guild mandate / owner in-protocol | both legs into a new or live pair |
| `removePartial` (905) | ungated; guild mandate in-protocol | both currencies out to the registry |
| `seedFunding` (1000) | ungated; relaunch in-protocol | pulls the vault sweep and both hook reserves; the swept native figure is now reported ONLY by the native branch (PoolOps.sol:1083), and the other two branches return zero for it (PoolOps.sol:1078, PoolOps.sol:1088) so the caller's `mulDiv` (PoolOps.sol:1380) never divides wei by ERC20 units |
| `_pullAsset` (1074) | internal | ERC20 in, best-effort |
| `_pullEth` (1081) | internal | native in, best-effort |
| `sendAsset` (1085) | ungated; guild mandate / owner in-protocol | native or ERC20 out to an arbitrary address |
| `_balance` (1097) | internal | none |
| `removeAll` (1116) | ungated; relaunch / leg recovery in-protocol | both currencies out, NFT burned |
| `claimFromReserve` (1147) | ungated (public); OG redeem / migrate / recycle in-protocol | token out to the recipient |
| `addToReserve` (1187) | ungated (public); ratchet paths in-protocol | token pulled from the registry into the band |
| `migrateUpTo` (1237) | ungated; previous-gen holders in-protocol | burn + 1:1 delivery, capped by capacity |
| `migrateOne` (1248) | ungated (public); holders and the batch | burn + 1:1 delivery, reverts if short |
| `autoMigrateBatch` (1274) | ungated; keeper in-protocol | per-holder burn + delivery |
| `doLegacyNote` (1298) | ungated (public); internal in-protocol | none (ledger credit) |
| `materializeLegacy` (1325) | ungated; permissionless / relaunch in-protocol | sweeps the hook's tokens in, then deposits or burns |
| `crystallizeCollection` (1350) | ungated; relaunch in-protocol | none (freezes an entitlement) |
| `recycleCollection` (1371) | ungated; NFT owner in-protocol | NFT in, floor paid out of the reserve |
| `buyCollection` (1419) | ungated; anyone in-protocol | 2x floor pulled in, NFT out |
