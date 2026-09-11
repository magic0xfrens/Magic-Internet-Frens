# Function graph — cluster `nft`

Generated from the decontaminated tree at `/tmp/blind-final/contracts/solidity`; **line numbers are identical to the repo**.
Machine-checked companion: `audit/graph/nft.json` (153 nodes, `COVERAGE nft: 153/153 nodes, 0 failures`).

| file | lines |
|---|---|
| `cauldron/MiFrensGenesis.sol` | 718 |
| `cauldron/CauldronCollection.sol` | 432 |
| `cauldron/CollectionLedger.sol` | 156 |
| `cauldron/CauldronGachaRouter.sol` | 553 |
| `cauldron/MiFrensDividend.sol` | 543 |
| `cauldron/MintCurvePolicy.sol` | 114 |
| `cauldron/CauldronFactory.sol` | 105 |
| `cauldron/ICreatorToken.sol` | 19 |
| `interfaces/INFTContract.sol` | 12 |

Note on `edges[]`: calls whose callee is defined only under `lib/` (OpenZeppelin `_mint`/`_burn`/`_transfer`/`_requireOwned`/`_setDefaultRoyalty`/`Strings.toString`/`Votes.delegates`, v4-core `poolManager.unlock`/`swap`/`settle`/`sync`/`take`) are recorded in the node's `reachability` prose with the exact call-site line instead of in `edges[]`; in this tree `lib` is a symlink and the graph validator's library index resolves to nothing, so such an edge cannot be verified. Every such call is listed in section D below.

---

## A. Value inventory — every field that holds or counts value

**`MiFrensGenesis`** (native ETH + two supply counters)
- native balance of the contract — denomination: wei. **+** `mint` payable, exact `PRICE * quantity` (MiFrensGenesis.sol:267). **−** `refund` send (MiFrensGenesis.sol:305); **−** `igniteCauldron` forwards `address(this).balance` in full (MiFrensGenesis.sol:584-585). No other exit exists.
- `paid[buyer]` — wei. **+** MiFrensGenesis.sol:270. **−** zeroed MiFrensGenesis.sol:304.
- `minted` — count of art tokens. **+** `m + quantity` MiFrensGenesis.sol:282 (genesis tranche); **+** `minted++` MiFrensGenesis.sol:478 (volume tranche). **No decrement anywhere**, including the burn at MiFrensGenesis.sol:547.
- `liquidatorMinted` — count of badges. **+** `++liquidatorMinted` MiFrensGenesis.sol:379. No decrement, no cap.

**`CauldronCollection`** (no value; two counters)
- `totalMinted` — **+** `++totalMinted` CauldronCollection.sol:210 only. No decrement; the burn at CauldronCollection.sol:386 leaves it.
- `liquidatorMinted` — **+** CauldronCollection.sol:351 only.

**`CollectionLedger`** (pure numbers, denominated in the LIVE iteration token)
- `entitledTokens[gen]` — **+** credit CollectionLedger.sol:108, **+** buyback CollectionLedger.sol:133, **+** crystallize CollectionLedger.sol:151. **−** redeem CollectionLedger.sol:121.
- `totalEntitled` — **+** CollectionLedger.sol:109, **+** 135, **+** 152. **−** CollectionLedger.sol:123. Every mutation moves it by the same amount as the per-gen field, so `totalEntitled == Σ entitledTokens` holds by construction.
- `retired[gen]` — count of NFTs in treasury custody. **+** CollectionLedger.sol:122. **−** CollectionLedger.sol:134.
- `frozenSupply[gen]` — count, written once at CollectionLedger.sol:149.

**`MiFrensDividend`** (native ETH + an ERC20 basket)
- native balance — **+** `receive` (MiFrensDividend.sol:236). **−** treasury sweep MiFrensDividend.sol:240; **−** `withdrawOwed` MiFrensDividend.sol:523; **−** `_claim` MiFrensDividend.sol:538.
- `accPerShare` — wei × `ACC` per active share. **+** MiFrensDividend.sol:246 only.
- `accPerShareOf[asset]` — raw asset units × `ACC` per active share. **+** MiFrensDividend.sol:287 only.
- `residual` — wei carried forward. set 0 at MiFrensDividend.sol:239; set to the full amount on a rejected sweep at MiFrensDividend.sol:241; set to the division remainder at MiFrensDividend.sol:247.
- `activeShares` — count of enchanted frens. **+** MiFrensDividend.sol:397. **−** `unchecked` MiFrensDividend.sol:493.
- `owed[addr]` — wei. **+** MiFrensDividend.sol:401 (stale re-cast), **+** MiFrensDividend.sol:468 (transfer). **−** zeroed MiFrensDividend.sol:521.
- `owedAsset[addr][asset]` — raw units. **+** MiFrensDividend.sol:326 (failed push), **+** 433 (stale re-cast), **+** 488 (transfer). **−** zeroed MiFrensDividend.sol:336.
- `debtOf[id]` — the per-token high-water mark. set MiFrensDividend.sol:403, 535; reset to 0 at MiFrensDividend.sol:495.
- `debtOfAsset[id][asset]` — set MiFrensDividend.sol:323, 435, 489.
- `totalDeposited` — wei, **+** MiFrensDividend.sol:236 only, never decremented (see B).
- `totalClaimed` — wei, **+** MiFrensDividend.sol:522, **+** 537. ETH only; the basket claim path never touches it.
- `assets[]` — the iterated basket. **+** push MiFrensDividend.sol:284 only; **no removal path exists in the file**.

**`CauldronGachaRouter`** (transient balances only)
- native — **+** `msg.value` on the three payable entries (CauldronGachaRouter.sol:274) and the open `receive` (CauldronGachaRouter.sol:552). **−** `settle{value:}` CauldronGachaRouter.sol:507; **−** `_payQuote` CauldronGachaRouter.sol:528; **−** `rescueETH` CauldronGachaRouter.sol:548.
- ERC20 — **+** pulls at CauldronGachaRouter.sol:277 and 298, plus `take` to `address(this)` at 444/475/489. **−** transfers at 331, 497, 510, 531.
- `_locked` — reentrancy flag only (CauldronGachaRouter.sol:179, 181).

**`CauldronFactory` / `MintCurvePolicy`** hold no value and no counters (`owner`, `liquidatorRenderer`; four immutables respectively).

## B. Balance vs counter — where they can diverge

1. **`CollectionLedger` is entirely unbacked inside this cluster.** It holds no tokens and makes no external call (comment CollectionLedger.sol:35, and no call exists in the file). `outstanding` takes the supply term from a caller argument (`mintedNow`, CollectionLedger.sol:87) and `buyback` takes `paid` on trust (CollectionLedger.sol:130). A registry that passes a larger `mintedNow` pays less per redemption and a smaller one pays more; nothing in the ledger can detect either.
2. **`MiFrensDividend.accPerShareOf` is credited with the requested amount** (MiFrensDividend.sol:287), not a measured balance delta; `_pull` only checks the boolean return (MiFrensDividend.sol:351). A fee-on-transfer or rebasing basket asset credits holders more than arrived, and the shortfall surfaces as a failing `_tryPush` for the last claimants (banked to `owedAsset`, MiFrensDividend.sol:326).
3. **`totalDeposited` is not a claim on the balance.** It counts gross `msg.value` (MiFrensDividend.sol:236) including deposits immediately swept to the treasury (MiFrensDividend.sol:240), so `totalDeposited − totalClaimed` overstates what the contract owes.
4. **`activeShares` can outlive the enchantment it counts.** `onMiFrenTransfer` is called inside a try/catch with a fixed stipend (MiFrensGenesis.sol:695); if it reverts, the fren keeps its share while `enchantedBy` points at the seller. The subsequent `_castSpell` stale branch (MiFrensDividend.sol:398-402) re-points without incrementing, which is what keeps the count balanced.
5. **Art counters vs live ERC721 supply.** `minted` (MiFrensGenesis.sol:282/478) and `totalMinted` (CauldronCollection.sol:210) are monotonic; burns at MiFrensGenesis.sol:547 and CauldronCollection.sol:386 reduce the live supply without reducing them, so live supply = counter − burns, and a burned id is never re-issued.
6. **`CauldronGachaRouter._pullQuote` returns the requested amount** (CauldronGachaRouter.sol:278), not a measured delta, so the play size credited to the hook can exceed what arrived; and the native `settle` branch spends the contract's balance (CauldronGachaRouter.sol:507), which is indistinguishable from anything the open `receive` accumulated.

## C. Authority map

| gate | holder | where | rotatable? |
|---|---|---|---|
| `deployer` (genesis) | the deploying EOA | MiFrensGenesis.sol:245 (immutable) | no — no setter, no renounce. Controls `setRegistry`, `cancelPresale`, `setFinalizer`, `setMetadata`, `setRarityOdds`, `setRoyalty`, `setTransferValidator`, `setLiquidatorURI`, `setLiquidatorRenderer` |
| `registry` (genesis) | write-once address | MiFrensGenesis.sol:253 | no — second write reverts (MiFrensGenesis.sol:251). Controls `custodyTransfer` (414) and half of `onlyDeployerOrRegistry` (326) |
| `minter` (genesis) | volume hook | MiFrensGenesis.sol:334 | yes, freely, by deployer or registry; no zero check |
| `vault` (genesis) | floor vault | MiFrensGenesis.sol:339 | yes, freely; grants the burn right (546) |
| `dividend` (genesis) | dividend contract | MiFrensGenesis.sol:344 | yes; setting zero silently disables the enchantment break (693) |
| `liquidatorMinter` (genesis) | PerpEngine | MiFrensGenesis.sol:353 | yes — deployer, registry **or the current `minter`** (352) |
| `finalizer` | optional | MiFrensGenesis.sol:425 | yes; zero = permissionless ignition (581) |
| `deployer` (per-brew collection) = **the registry**, not the factory | immutable | CauldronCollection.sol:156 | no |
| `configurator` = the factory | immutable | CauldronCollection.sol:157 | no; holds `setVault` (287), `setRoyalty` (297), `setLiquidatorRenderer` (374) |
| `minter` (per-brew) | immutable | CauldronCollection.sol:155 | no; also co-holds `setLiquidatorMinter` (307) |
| `vault` (per-brew) | write-once | CauldronCollection.sol:289 | no — `VaultSet` (288) |
| `registry` (ledger) | immutable | CollectionLedger.sol:74 | no; sole mutator of the whole cap table (78) |
| `treasury` (dividend) | immutable | MiFrensDividend.sol:183 | no; holds the two one-time wirings and receives unclaimable fees (240) |
| `registry` (dividend) | write-once | MiFrensDividend.sol:192 | no (191) — cannot be unwired if it misbehaves |
| `funder` (dividend) | write-once | MiFrensDividend.sol:202 | no (201) — sole appender to the iterated basket |
| `mifrens` (dividend) | immutable | MiFrensDividend.sol:176 | no; sole caller of `onMiFrenTransfer` (465) |
| OZ `Ownable` owner (router) | constructor arg | CauldronGachaRouter.sol:185 | yes — `transferOwnership`/`renounceOwnership` are inherited; holds `setOracle` (99) and `rescueETH` (547) |
| `poolManager` (router) | immutable | CauldronGachaRouter.sol:187 | no; sole caller of `unlockCallback` (399) |
| `owner` (factory) | `msg.sender` at deploy | CauldronFactory.sol:21 | yes, single-step, **no zero check** (44) — can dead-end |
| transfer validator | collection admin | MiFrensGenesis.sol:468 / CauldronCollection.sol:195 | yes; a hostile or reverting target halts every mint, transfer, burn and custody move |
| **ungated** | anyone | `MiFrensGenesis.mint` (262), `refund` (300), `igniteCauldron` (575, unless a finalizer is set), `reveal`/`revealBatch` (owner-of-token), `MiFrensDividend.receive` (235), `withdrawOwed` (518), `withdrawOwedToken` (333), `castSpell`/`claim` (owner-of-token), router `play`/`playLiq`/`openReady`/`playChurn`/`receive`, `CauldronFactory.deployBrew` (63) and `deployVault` (99) | |

`CauldronFactory.deployBrew` and `deployVault` are callable by anyone; they confer nothing because the collection takes its controller from the caller-supplied config (CauldronFactory.sol:72) and a collection only honours the vault its own `setVault` recorded.

## D. External calls, with value and CEI ordering

| call site | callee | value | ordering |
|---|---|---|---|
| MiFrensGenesis.sol:305 | `msg.sender.call{value}` | sends wei | `paid` zeroed at 304 **before** the call; `nonReentrant` on 300 |
| MiFrensGenesis.sol:585 | `registry.summon{value: bal}` | sends the whole balance | `finalized = true` at 583 **before**; `nonReentrant` on 575 |
| MiFrensGenesis.sol:656 | `ITransferValidator.validateTransfer` | none | **before** the ERC721 state change at 658 |
| MiFrensGenesis.sol:695 | `dividend.onMiFrenTransfer{gas: 260_000}` | none | **after** ownership has already moved (658); try/catch; caller must leave 320_000 gas (694) |
| MiFrensGenesis.sol:626, 634 | `ICollectionRenderer.tokenURI` | none | view path |
| MiFrensGenesis.sol:279, 383, 481 / 547 / 416 | OZ `_mint` / `_burn` / `_transfer` | none | all funnel through the `_update` override (647) |
| CauldronCollection.sol:176 | `ITransferValidator.validateTransfer` | none | **before** `super._update` (178) |
| CauldronCollection.sol:406, 413 | `ICollectionRenderer.tokenURI` | none | view path; the art branch has no zero-address guard |
| CauldronCollection.sol:162, 299 | OZ `_setDefaultRoyalty` | none | — |
| CauldronFactory.sol:71, 75, 81 | `new CauldronCollection` / `new CauldronVault` / `new RoyaltyRouter` | none — three constructors run inside the call, none of them funded | deploying the collection at 71 is what makes this factory its deployer, and that is the right spent at 76, 82 and 87; the vault at 75 answers to the caller-supplied registry, not to the factory; the router at 81 is installed as the royalty receiver at 82 |
| CauldronFactory.sol:103 | `new CauldronVault` | none | standalone deployment by `deployVault`, wired to nothing — a collection only honours the vault its own `setVault` recorded |
| MiFrensDividend.sol:240 | `treasury.call{value}` | sends wei | `residual` zeroed at 239 first; **no reentrancy guard on `receive`**; the branch returns at 243 |
| MiFrensDividend.sol:348 | `asset.call(transferFrom…)` | pulls ERC20 | **before** `accPerShareOf` is credited (287) |
| MiFrensDividend.sol:357 | `asset.call(transfer…)` | sends ERC20 | debt marker advanced at 323 **before**; failure banked at 326 |
| MiFrensDividend.sol:449, 450, 452, 455, 456, 457 | `everMoved`, `enchantFee`, `currentToken`, `IERC20.transferFrom`, `IERC20.approve`, `donateToReserve` | pulls then forwards the fee | all **before** `activeShares += 1` (397); `approve` return unchecked |
| MiFrensDividend.sol:523, 538 | `msg.sender.call{value}` | sends wei | `owed`/`debtOf` written first (521 / 535); `nonReentrant` on 502/507/518 |
| MiFrensDividend.sol:257, 294, 308, 367, 387, 531 | `mifrens.ownerOf` | none | gate reads |
| CauldronGachaRouter.sol:301, 379 | `poolManager.unlock` | none | re-enters `unlockCallback` (398) |
| CauldronGachaRouter.sol:422, 436, 467, 481 | `poolManager.swap` | none | inside the unlock frame |
| CauldronGachaRouter.sol:507 | `poolManager.settle{value}` | sends wei | native quote branch |
| CauldronGachaRouter.sol:509, 511 | `poolManager.sync` / `settle` | none | ERC20 quote branch, around the transfer at 510 |
| CauldronGachaRouter.sol:516 | `poolManager.take` | pays `to` | destination is the player (431) or the router (444/475/489) |
| CauldronGachaRouter.sol:139 | `IQuoteOracleView.usdPerRawUnit` | none | try/catch; failure falls back to the raw size |
| CauldronGachaRouter.sol:205, 218 | `registry.generationQuote` / `currentGeneration` / `currentToken` | none | re-read on **every** call, never cached |
| CauldronGachaRouter.sol:326, 327, 346, 351, 352, 360, 361, 387, 388 | hook gacha calls | none | commit/resolve happen **before** every payout |
| CauldronGachaRouter.sol:528, 548 | `to.call{value}` | sends wei | last action of the play (338/390); `rescueETH` is unguarded but has no accounting |
| CauldronGachaRouter.sol:537, 543 | `token.call(transfer/transferFrom)` | moves ERC20 | boolean-checked |
| CauldronHook.sol:1627 (inbound) | `INFTContract.getHolderTaxRate` | none | out-of-cluster caller of this cluster's interface |

## E. Loops and their bounds

| loop | bound | who grows it |
|---|---|---|
| MiFrensGenesis.sol:276 mint loop | `quantity`, itself capped by `MAX_PER_WALLET` (268) and `GENESIS_SUPPLY` (266) | the deployer, at construction |
| MiFrensGenesis.sol:512 / CauldronCollection.sol:244 reveal batch | 50, hard (511 / 243) | nobody |
| MiFrensGenesis.sol:552 / CauldronCollection.sol:278 rarity walk | 4, hard | nobody |
| MintCurvePolicy.sol:110 | `supply`, immutable (109) | the deployer; unbounded gas on a large collection, view-only |
| MiFrensDividend.sol:319 (`claimTokens`), 428 (`_castSpell`), 483 (`onMiFrenTransfer`) | `assets.length`, capped at `MAX_ASSETS = 3` (124, 282) | only `funder`; **no removal path** |
| MiFrensDividend.sol:382 (`castMany`), 513 (`claimMany`) | caller's own array, **unbounded** | the caller (pays their own gas) |
| CauldronGachaRouter.sol:465 churn loop | `MAX_LOOPS = 10` (69, 377); up to 2 swaps per iteration | nobody |
| CauldronGachaRouter.sol:408 `liqHints` | **unbounded in this file**; forwarded into hookData | the caller; only the hook limits it |

## F. Denomination and units

- `MiFrensGenesis.PRICE` / `paid` / the contract balance: **wei**. No decimals conversion anywhere.
- `CollectionLedger.entitledTokens` / `totalEntitled`: raw units of the **live iteration token** (comment CollectionLedger.sol:43-44); the number survives a generation change unchanged, so its real value changes when the token does. `retired`, `frozenSupply` are **counts**.
- `MiFrensDividend.accPerShare`: wei × `ACC = 1e18` (43) per share. `accPerShareOf[asset]`: **raw units of that asset** × `ACC` (287) — no decimals normalisation, which is exactly what keeps a 6-decimal and an 18-decimal asset independent; entitlement and settlement are in the same asset, so no oracle is used anywhere in the dividend.
- The enchant fee is denominated in `reg.currentToken()` (MiFrensDividend.sol:452) and the amount comes from `reg.enchantFee()` (450) — neither is converted here.
- `CauldronGachaRouter`: `playWei` is a notional in **the quote's own raw units** (wei for native, 6 decimals for a stablecoin quote) summed from swap deltas (322, 476, 490); `_playInCurveUnits` multiplies by `usdPerRawUnit(_quote())` and divides by `1e18` (141) to reach the hook's USD-at-1e18 curve unit. With no oracle the raw size passes through (138), which is only correct while the hook's curve is ether-denominated. `openReady` deliberately skips the conversion because `costOfNextCrystals` is already in curve units (351-360).
- `MintCurvePolicy` is unit-agnostic: "whatever the hook's credit is denominated in" (comment 55-57); it performs no scaling.
- `rarityCumBps` and royalty `bps` are basis points; `buyWeightBps` is used as a bps divisor at CauldronGachaRouter.sol:353.

## G. `unchecked` blocks and rounding direction

- MiFrensGenesis.sol:280 `unchecked { ++i; }` — loop counter bounded by `quantity`. Safe.
- MiFrensDividend.sol:382, 513 `unchecked { ++i; }` — loop counters. Safe.
- MiFrensDividend.sol:493 `unchecked { activeShares -= 1; }` — the only subtraction of the divisor. It is reached only when `enchantedBy[tokenId]` is non-zero (467), and every non-zero `enchantedBy` came from a fresh join that incremented the counter at 397 (the stale branch at 398 neither increments nor decrements). DERIVED: on that reasoning the counter cannot underflow, but the guard is arithmetic-free and the invariant is not asserted anywhere in the file.
- CauldronGachaRouter.sol:494 `unchecked { ++i; }` — bounded by `MAX_LOOPS`. Safe.
- Rounding, all **down** (truncating integer division), all in the protocol's favour or the survivors': `CollectionLedger.floorPerNFT` (97) and `redeem` (120) leave the remainder in the pot; `MiFrensDividend.receive` carries the remainder explicitly into `residual` (247) — the **only** place a remainder is preserved; `fundToken` (287), `pendingToken` (295), `claimTokens` (321), `_castSpell` (433), `onMiFrenTransfer` (488), `pending` (258) and `_claim` (534) all truncate and the dust stays in the accumulator; `MintCurvePolicy.priceAt` (99) truncates; `CauldronGachaRouter._playInCurveUnits` (141) and the buy-weight scaling (353) truncate.

## H. Comment-vs-code observations (10)

1. `CauldronCollection.sol:22` — "There is no admin surface at all after construction"; the file exposes `setMetadata` (316), `setTransferValidator` (192), `setRarityOdds` (426), `setLiquidatorURI` (328), `setLiquidatorMinter` (306) and `setLiquidatorRenderer` (373) afterwards.
2. `CauldronCollection.sol:17` — metadata is "immutable at deploy"; `setMetadata` (316-324) changes both the mode and its source at any time.
3. `CauldronCollection.sol:99` — rarity is "Rolled at mint … and stored"; the mint stores only the block (212) and the tier is written in the reveal path (270).
4. `CauldronCollection.sol:292` — royalty re-point is "(deployer only)"; the check at 297 also accepts the `configurator`.
5. `CauldronCollection.sol:263` and `MiFrensGenesis.sol:531` — after a re-anchor "the holder (or a keeper) calls reveal() again"; both `_reveal` implementations reject any caller that is not the current owner (248 / 516), so no keeper can.
6. `MiFrensGenesis.sol:615` — the non-genesis branch is described as "the rolled rarity tier"; `ogTrait` (618) returns a constant string and never reads `rarityOf`.
7. `CauldronGachaRouter.sol:210` — "The QUOTE is always currency0 … an INVARIANT"; `_key` (217-218) assigns by role and never compares the two addresses, so the property is enforced only by the registry's admission rule.
8. `CauldronGachaRouter.sol:453` — the churn path encodes only the player into `hookData`, while the play path encodes a second word (408); the two paths hand the hook different payload shapes.
9. `MiFrensDividend.sol:480` — "why MAX_ASSETS is 4"; the constant is 3 (124), which is also what the note at 108-120 argues for.
10. (Recorded on the node) `MiFrensDividend.sol:460` describes the hook as applying to "an enchanted genesis fren", while `onMiFrenTransfer` (464) has no eligibility-cap or id check at all — badge ids and forged ids reach it and return early only because `enchantedBy` is zero (467).

## Cluster extra 1 — every holder claim path

| path | who may call | for which token | what is paid | double-claim prevention |
|---|---|---|---|---|
| `MiFrensGenesis.refund` (300) | any address with a recorded balance | not per-token; per **payer** | native, exactly `paid[msg.sender]` (302) | `paid` zeroed at 304 before the send; a failed send reverts the zeroing (306) |
| `MiFrensGenesis.reveal` / `revealBatch` (487 / 507) | **current owner only** (516) | any unrevealed id | no value — a rarity write | `revealed[tokenId]` guard (517), set at 539 |
| `MiFrensDividend.claim` / `claimMany` (502 / 507) | owner **and** current caster (531, 532) | ids `1..MAX_TOKEN` (530) | native `(accPerShare − debtOf[id]) / ACC` (534) | `debtOf[id] = accPerShare` at 535 **before** the send; `nonReentrant` (502/509) |
| `MiFrensDividend.claimTokens` (307) | owner **and** current caster (308, 309) | ids with a live enchantment | every basket asset, `(accPerShareOf[a] − debtOfAsset[id][a]) / ACC` (321) | per-asset marker advanced at 323 **before** the push; a failed push banks to `owedAsset` (326) rather than replaying |
| `MiFrensDividend.withdrawOwed` (518) | any address with a banked balance | not per-token; per **address** | native `owed[msg.sender]` (519) | zeroed at 521 before the send; revert on failure (524) restores it |
| `MiFrensDividend.withdrawOwedToken` (333) | any address with a banked balance | per **address + asset** | `owedAsset[msg.sender][asset]` (334) | zeroed at 336 before the push; revert on failure (340) restores it |
| `MiFrensDividend.castSpell` / `castMany` (375 / 380) | **current owner only** (387) | ids `1..MAX_TOKEN` (386) | costs the enchant fee (396) for forged ids and moved OGs | idempotent early return at 389; markers set to the current accumulators (403, 435) so joining earns nothing retroactively |
| `CollectionLedger.redeem` (117) | **registry only** (78) — the holder reaches it through the registry | per generation, one NFT per call | `entitledTokens[gen] / outstanding` (120) | the pot and `totalEntitled` are debited by exactly the payout (121, 123) and `retired` is incremented (122); the ledger itself has no per-token record, so the one-NFT-one-redemption rule lives in the registry |
| `MiFrensGenesis.burnFromVault` / `CauldronCollection.burnFromVault` (545 / 384) | **vault only** (546 / 385) | any id | the vault pays; the token is destroyed | the burn cannot be repeated for the same id (OZ `_burn` reverts on a non-existent token) |

The two enchantment-settling paths are the mirror of the claim paths: `onMiFrenTransfer` (464) credits the **leaver** for the window they held the fren (468, 488) before releasing the share (493), and `_castSpell`'s stale branch (398-402, 431-434) does the same when that hook was skipped. Together they are what stops a buyer from claiming the seller's accrual: the buyer cannot claim at all until they re-cast (532), and re-casting resets their markers to "now" (403, 435).

## Cluster extra 2 — supply conservation

**`MiFrensGenesis`** (one collection, three id ranges)
- Mints: genesis tranche `_mint` at MiFrensGenesis.sol:279, ids `m+1 … m+quantity` (275-277), capped by `minted + quantity > GENESIS_SUPPLY` (266) and by `MAX_PER_WALLET` (268); volume tranche `_mint` at 481, id `minted + 1` (477), capped by `minted >= MAX_SUPPLY` (476); badges `_mint` at 383, id `LIQUIDATOR_ID_BASE + ++liquidatorMinted` (379), **uncapped**.
- Burns: `_burn` at 547, vault only (546).
- Counters: `minted` (+282, +478) and `liquidatorMinted` (+379). Neither is ever decremented.
- Conservation: art ids and badge ids cannot collide because the constructor refuses `maxSupply_ >= LIQUIDATOR_ID_BASE` (239). Both tranches share one counter, so ids are unique and monotonic; a burn removes a token without freeing its id. Live art supply = `minted` − (art burns). The cap that governs the volume tranche is `MAX_SUPPLY` (476) while the presale is capped by `GENESIS_SUPPLY` (266) — a presale that never sells out leaves ids below `GENESIS_SUPPLY` that the volume path will mint later, and those ids will read as `isGenesis` (611).
- Ignition reads the same counter (`minted < GENESIS_SUPPLY`, 578), so volume mints would also satisfy it; in practice `minter` is wired only after ignition.

**`CauldronCollection`** (one collection, two id ranges)
- Mints: art `_mint` at 213, id `++totalMinted` (210), capped at `maxSupply` (209), minter-only (208); badges `_mint` at 356, id `LIQUIDATOR_ID_BASE + ++liquidatorMinted` (351), **uncapped**, `liquidatorMinter`-only (350).
- Burns: `_burn` at 386, vault only (385).
- Counters: `totalMinted` (+210) and `liquidatorMinted` (+351), never decremented. `maxSupply` is immutable (158) and the constructor refuses `maxSupply_ >= LIQUIDATOR_ID_BASE` (148), so the two ranges are disjoint. There is no public mint and no owner mint anywhere in the file.

**Custody, not burning.** `custodyTransfer` (MiFrensGenesis.sol:414, CauldronCollection.sol:394) moves a redeemed NFT to the registry and back without burning, so collection size is preserved; on the ledger side the same event is `retired += 1` (CollectionLedger.sol:122) and `retired −= 1` (134), with `outstanding = supply − retired` (89) saturating at zero.

**Entitlement conservation (`CollectionLedger`).** `totalEntitled` moves in lockstep with `entitledTokens[gen]` on all four mutators (108/109, 121/123, 133/135, 151/152), so `totalEntitled == Σ entitledTokens[gen]` is preserved exactly; redemption rounds down (120) so the sum can only drift *below* the reserve backing it, never above. `crystallize` (143) freezes the supply term once (147-149); a zero `mintedAtDeath` makes that generation's `outstanding` zero forever, which strands its pot (redeem reverts at 119) without destroying it.

**Vote supply.** Every MiFren *and every Liquidatoor badge* is an `ERC721Votes` unit: `_update` (647) self-delegates on first receipt (659-661), so badge minting at 383 increases the governance electorate. Burning at 547 removes the vote with the token.

## I. Function inventory (153 nodes)

**CauldronCollection** (`cauldron/CauldronCollection.sol`)

- L133 `constructor( string memory name_, string memory symbol_, address minter_, address registry_, uint256 maxSupply_, Meta...` — **deployer (the CauldronFactory, which becomes `configurator`)** — value: NONE
- L169 `function _update(address to, uint256 tokenId, address auth) internal override returns (address)` — **internal (callers: ERC721 _mint, _burn, _transfer and the inherited public transfer entry points)** — value: NONE
- L182 `function getTransferValidator() external view returns (address)` — **anyone** — value: NONE
- L187 `function getTransferValidationFunction() external pure returns (bytes4 functionSignature, bool isViewFunction)` — **anyone** — value: NONE
- L192 `function setTransferValidator(address validator) external` — **registry (held in the immutable `deployer` slot)** — value: NONE
- L199 `function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool)` — **anyone** — value: NONE
- L207 `function mint(address to) external returns (uint256 tokenId)` — **minter (the volume hook, frozen at deploy)** — value: NONE
- L219 `function reveal(uint256 tokenId) external` — **holder of token** — value: NONE
- L239 `function revealBatch(uint256[] calldata tokenIds) external` — **holder of token** — value: NONE
- L247 `function _reveal(uint256 tokenId) private` — **internal (callers: reveal, revealBatch); the caller must own the token** — value: NONE
- L276 `function _rollRarity(uint256 seed) private view returns (uint8)` — **internal (callers: _reveal)** — value: NONE
- L286 `function setVault(address _vault) external` — **configurator (the factory) or registry** — value: NONE
- L296 `function setRoyalty(address receiver, uint96 bps) external` — **configurator (the factory) or registry** — value: NONE
- L306 `function setLiquidatorMinter(address _minter) external` — **registry or minter (the volume hook)** — value: NONE
- L316 `function setMetadata(MetadataMode _mode, address _renderer, string calldata baseURI_) external` — **registry (held in the immutable `deployer` slot)** — value: NONE
- L328 `function setLiquidatorURI(string calldata uri) external` — **registry (held in the immutable `deployer` slot)** — value: NONE
- L336 `function mintLiquidator(address to) external returns (uint256 tokenId)` — **liquidatorMinter (the wired PerpEngine)** — value: NONE
- L342 `function mintLiquidatorWithStats(address to, LiqStats calldata st) external returns (uint256 tokenId)` — **liquidatorMinter (the wired PerpEngine)** — value: NONE
- L349 `function _mintLiquidator(address to, LiqStats memory st) internal returns (uint256 tokenId)` — **internal (callers: mintLiquidator, mintLiquidatorWithStats)** — value: NONE
- L361 `function liqStats(uint256 tokenId) external view returns (LiqStats memory)` — **anyone** — value: NONE
- L373 `function setLiquidatorRenderer(address r) external` — **configurator (the factory) or registry** — value: NONE
- L379 `function liquidatoorTrait(uint256 tokenId) external view returns (string memory)` — **anyone** — value: NONE
- L384 `function burnFromVault(uint256 tokenId) external` — **vault** — value: NONE
- L394 `function custodyTransfer(address from, address to, uint256 tokenId) external` — **registry (held in the immutable `deployer` slot)** — value: NONE
- L400 `function tokenURI(uint256 tokenId) public view override returns (string memory)` — **anyone** — value: NONE
- L426 `function setRarityOdds(uint16[4] calldata cum) external` — **registry (held in the immutable `deployer` slot)** — value: NONE

**CauldronFactory** (`cauldron/CauldronFactory.sol`)

- L36 `function setLiquidatorRenderer(address r) external` — **owner** — value: NONE
- L42 `function transferOwnership(address to) external` — **owner** — value: NONE
- L63 `function deployBrew(Config calldata c) external returns (address collection, address vault)` — **anyone** — value: NONE
- L99 `function deployVault(address collection, address registry, uint256 floorOffset) external returns (address vault)` — **anyone** — value: NONE

**ICauldronHookGacha (declared in CauldronGachaRouter.sol)** (`cauldron/CauldronGachaRouter.sol`)

- L15 `function commitCrystals(address player, uint256 maxCount, uint256 playWei) external returns (uint256)` — **declaration only (no body); in-cluster callers are _play, openReady and playChurn, all reachable by anyone; the hook holds its own gate** — value: NONE
- L16 `function resolveTickets(uint256 maxCount) external returns (uint256, uint256)` — **declaration only (no body); in-cluster callers are _play, openReady and playChurn** — value: NONE
- L17 `function crystalsReady(address player) external view returns (uint256)` — **declaration only (no body); in-cluster caller is openReady** — value: NONE
- L18 `function costOfNextCrystals(uint256 count) external view returns (uint256)` — **declaration only (no body); in-cluster caller is openReady** — value: NONE
- L19 `function buyWeightBps() external view returns (uint256)` — **declaration only (no body); in-cluster caller is openReady** — value: NONE

**IRegistryCurrent (declared in CauldronGachaRouter.sol)** (`cauldron/CauldronGachaRouter.sol`)

- L23 `function currentToken() external view returns (address)` — **declaration only (no body); in-cluster caller is _key** — value: NONE
- L25 `function currentGeneration() external view returns (uint256)` — **declaration only (no body); in-cluster caller is _quote** — value: NONE
- L29 `function generationQuote(uint256 gen) external view returns (address)` — **declaration only (no body); in-cluster caller is _quote** — value: NONE

**IQuoteOracleView (declared in CauldronGachaRouter.sol)** (`cauldron/CauldronGachaRouter.sol`)

- L37 `function usdPerRawUnit(address quote) external view returns (uint256)` — **declaration only (no body); in-cluster caller is _playInCurveUnits** — value: NONE

**CauldronGachaRouter** (`cauldron/CauldronGachaRouter.sol`)

- L99 `function setOracle(address _oracle) external onlyOwner` — **owner** — value: NONE
- L120 `function playInCurveUnits(uint256 playWei) external view returns (uint256)` — **anyone** — value: NONE
- L136 `function _playInCurveUnits(uint256 playWei) internal view returns (uint256)` — **internal (callers: playInCurveUnits, _play, playChurn)** — value: NONE
- L177 `modifier nonReentrant()` — **internal (callers: play, playLiq, openReady, playChurn)** — value: NONE
- L184 `constructor(IPoolManager _poolManager, address _hook, address _registry, address _owner) Ownable(_owner)` — **deployer** — value: NONE
- L204 `function _quote() internal view returns (address)` — **internal (callers: _key, _playInCurveUnits, playChurn)** — value: NONE
- L215 `function _key() internal view returns (PoolKey memory)` — **internal (callers: _play, unlockCallback, _churn)** — value: NONE
- L233 `function play(uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax) external p...` — **anyone** — value: receives native when the generation's quote is native - declared `payable` (line 235)
- L248 `function playLiq( uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax, uint25...` — **anyone** — value: receives native when the generation's quote is native - declared `payable` (line 257)
- L271 `function _pullQuote(address q, uint256 quoteIn) private returns (uint256)` — **internal (callers: _play, playChurn)** — value: receives native `msg.value` on the native branch (line 274); ERC20 pull of `q` from the caller into this ro...
- L281 `function _play( uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax, uint256[...` — **internal (callers: play, playLiq)** — value: ERC20 pull of the iteration token from the caller at `_safeTransferFrom` (line 298); ERC20 refund of the un...
- L345 `function openReady(uint256 maxCount) external nonReentrant returns (uint256 opened)` — **anyone** — value: NONE
- L368 `function playChurn(uint256 quoteIn, uint256 loops, uint256 openMax) external payable nonReentrant returns (uint256 op...` — **anyone** — value: receives native when the quote is native - declared `payable` (line 370); leftover quote paid back to `msg....
- L398 `function unlockCallback(bytes calldata raw) external returns (bytes memory)` — **poolManager (re-entered during unlock)** — value: the pool manager pays the swap output to the player at `_take` (line 431); the sell output is taken to this...
- L451 `function _churn(ChurnData memory c) private returns (bytes memory)` — **internal (callers: unlockCallback)** — value: leftover iteration token sent to the player at `_safeTransfer` (line 497)
- L501 `function _limit(bool zeroForOne) private pure returns (uint160)` — **internal (callers: unlockCallback, _churn)** — value: NONE
- L505 `function _settle(Currency currency, uint256 amount, bool isNative) private` — **internal (callers: unlockCallback, _churn)** — value: sends native to the pool manager at `settle` (line 507); ERC20 sent to the pool manager at `_safeTransfer` ...
- L515 `function _take(Currency currency, address to, uint256 amount) private` — **internal (callers: unlockCallback, _churn)** — value: the pool manager pays `to` at `take` (line 516)
- L525 `function _payQuote(address q, address to, uint256 amount) private` — **internal (callers: _play, playChurn)** — value: sends native to `to` (line 528); ERC20 sent to `to` at `_safeTransfer` (line 531)
- L535 `function _safeTransfer(address token, address to, uint256 amount) private` — **internal (callers: _play, _churn, _settle, _payQuote)** — value: ERC20 transfer of `token` to `to` (line 537)
- L541 `function _safeTransferFrom(address token, address from, address to, uint256 amount) private` — **internal (callers: _pullQuote, _play)** — value: ERC20 transferFrom of `token` from `from` to `to` (line 543)
- L547 `function rescueETH(address to, uint256 amount) external onlyOwner` — **owner** — value: sends native to `to` (line 548)
- L552 `receive() external payable` — **anyone** — value: receives native - declared `payable` (line 552)

**CollectionLedger** (`cauldron/CollectionLedger.sol`)

- L72 `constructor(address _registry)` — **deployer** — value: NONE
- L77 `modifier onlyRegistry()` — **internal (callers: credit, redeem, buyback, crystallize)** — value: NONE
- L86 `function outstanding(uint256 gen, uint256 mintedNow) public view returns (uint256)` — **anyone** — value: NONE
- L94 `function floorPerNFT(uint256 gen, uint256 mintedNow) public view returns (uint256)` — **anyone** — value: NONE
- L106 `function credit(uint256 gen, uint256 tokens) external onlyRegistry` — **registry** — value: NONE
- L117 `function redeem(uint256 gen, uint256 mintedNow) external onlyRegistry returns (uint256 payout)` — **registry** — value: NONE
- L130 `function buyback(uint256 gen, uint256 mintedNow, uint256 paid) external onlyRegistry` — **registry** — value: NONE
- L143 `function crystallize(uint256 gen, uint256 mintedAtDeath, uint256 extraEntitled) external onlyRegistry` — **registry** — value: NONE

**ITransferValidator (declared in ICreatorToken.sol)** (`cauldron/ICreatorToken.sol`)

- L8 `function validateTransfer(address caller, address from, address to, uint256 tokenId) external view` — **declaration only (no body); in-cluster callers are the two collections' _update overrides; the validator contract itself is chosen by the collection's admin** — value: NONE

**ICreatorToken** (`cauldron/ICreatorToken.sol`)

- L16 `function getTransferValidator() external view returns (address)` — **anyone (the implementations are public views)** — value: NONE
- L17 `function getTransferValidationFunction() external view returns (bytes4 functionSignature, bool isViewFunction)` — **anyone (the implementations are pure)** — value: NONE
- L18 `function setTransferValidator(address validator) external` — **the collection's admin: the genesis deployer or the registry for the per-brew collection** — value: NONE

**IMiFrensShares (declared in MiFrensDividend.sol)** (`cauldron/MiFrensDividend.sol`)

- L8 `function ownerOf(uint256 tokenId) external view returns (address)` — **declaration only (no body); in-cluster callers are pending, pendingToken, isEnchanted, _castSpell and _claim** — value: NONE
- L9 `function GENESIS_SUPPLY() external view returns (uint256)` — **declaration only (no body); in-cluster caller is the constructor** — value: NONE
- L10 `function MAX_SUPPLY() external view returns (uint256)` — **declaration only (no body); in-cluster caller is the constructor** — value: NONE
- L12 `function everMoved(uint256 tokenId) external view returns (bool)` — **declaration only (no body); in-cluster caller is _collectEnchantFee** — value: NONE

**IReserveRegistry (declared in MiFrensDividend.sol)** (`cauldron/MiFrensDividend.sol`)

- L18 `function enchantFee() external view returns (uint256)` — **declaration only (no body); in-cluster caller is _collectEnchantFee** — value: NONE
- L19 `function currentToken() external view returns (address)` — **declaration only (no body); in-cluster caller is _collectEnchantFee** — value: NONE
- L20 `function donateToReserve(uint256 amount) external` — **declaration only (no body); in-cluster caller is _collectEnchantFee** — value: NONE

**MiFrensDividend** (`cauldron/MiFrensDividend.sol`)

- L175 `constructor(address _mifrens, address _treasury)` — **deployer** — value: NONE
- L189 `function setRegistry(address _registry) external` — **treasury** — value: NONE
- L199 `function setFunder(address _funder) external` — **treasury** — value: NONE
- L235 `receive() external payable` — **anyone** — value: receives native - declared `payable` (line 235); sends native to `treasury` (line 240)
- L255 `function pending(uint256 tokenId) public view returns (uint256)` — **anyone** — value: NONE
- L273 `function fundToken(address asset, uint256 amount) external` — **funder (the hook), wired once by the treasury** — value: ERC20 pull of `asset` from the funder into this contract (line 286)
- L292 `function pendingToken(uint256 tokenId, address asset) public view returns (uint256)` — **anyone** — value: NONE
- L299 `function assetCount() external view returns (uint256)` — **anyone** — value: NONE
- L307 `function claimTokens(uint256 tokenId) external nonReentrant` — **holder of token who is also its caster** — value: ERC20 push of `a` to `msg.sender` (line 325)
- L333 `function withdrawOwedToken(address asset) external nonReentrant returns (uint256 amount)` — **anyone (pays only the caller's own banked balance)** — value: ERC20 push of `asset` to `msg.sender` (line 340)
- L347 `function _pull(address asset, address from, uint256 amount) private` — **internal (callers: fundToken)** — value: ERC20 transferFrom into this contract, encoded at `transferFrom` (line 349)
- L356 `function _tryPush(address asset, address to, uint256 amount) private returns (bool)` — **internal (callers: claimTokens, withdrawOwedToken)** — value: ERC20 transfer of `asset` to `to` (line 358)
- L365 `function isEnchanted(uint256 tokenId) external view returns (bool)` — **anyone** — value: NONE
- L375 `function castSpell(uint256 tokenId) external` — **holder of token** — value: NONE
- L380 `function castMany(uint256[] calldata tokenIds) external` — **holder of token** — value: NONE
- L385 `function _castSpell(uint256 tokenId) private` — **internal (callers: castSpell, castMany); the caller must own the token** — value: NONE
- L445 `function _collectEnchantFee(uint256 tokenId) private` — **internal (callers: _castSpell)** — value: ERC20 transferFrom of `tok` from the caster into this contract (line 455); ERC20 approve of `reg` for the f...
- L464 `function onMiFrenTransfer(uint256 tokenId, address /*from*/) external` — **the MiFrens collection** — value: NONE
- L502 `function claim(uint256 tokenId) public nonReentrant returns (uint256 amount)` — **holder of token who is also its caster** — value: sends native to `msg.sender` (line 538)
- L507 `function claimMany(uint256[] calldata tokenIds) external nonReentrant returns (uint256 total)` — **holder of token who is also its caster** — value: sends native to `msg.sender` (line 538)
- L518 `function withdrawOwed() external nonReentrant returns (uint256 amount)` — **anyone (pays only the caller's own banked balance)** — value: sends native to `msg.sender` (line 523)
- L529 `function _claim(uint256 tokenId) private returns (uint256 amount)` — **internal (callers: claim, claimMany); the caller must own the token and be its caster** — value: sends native to `msg.sender` (line 538)

**IRegistrySummon (declared in MiFrensGenesis.sol)** (`cauldron/MiFrensGenesis.sol`)

- L16 `function summon() external payable returns (address token, bytes32 poolId)` — **declaration only (no body); the sole in-cluster caller is MiFrensGenesis.igniteCauldron, which holds the gate; the implementing registry is out of cluster** — value: receives native - declared `payable` (line 16)
- L17 `function summoned() external view returns (bool)` — **declaration only (no body); no call site exists in this cluster** — value: NONE

**IMiFrensDividendHook (declared in MiFrensGenesis.sol)** (`cauldron/MiFrensGenesis.sol`)

- L21 `function onMiFrenTransfer(uint256 tokenId, address from) external` — **declaration only (no body); the only in-cluster caller is MiFrensGenesis._update, and the address it is called on is whatever `setDividend` wired** — value: NONE

**MiFrensGenesis** (`cauldron/MiFrensGenesis.sol`)

- L227 `constructor( string memory name_, string memory symbol_, uint256 genesisSupply_, uint256 maxSupply_, uint256 price_, ...` — **deployer** — value: NONE
- L249 `function setRegistry(address _registry) external` — **deployer** — value: NONE
- L262 `function mint(uint256 quantity) external payable nonReentrant` — **anyone** — value: receives native - exact `msg.value` required (line 267)
- L289 `function cancelPresale() external` — **deployer** — value: NONE
- L300 `function refund() external nonReentrant returns (uint256 amount)` — **anyone (pays out only to a caller with a recorded balance)** — value: sends native to `msg.sender` (line 305)
- L315 `function totalMinted() external view returns (uint256)` — **anyone** — value: NONE
- L320 `function maxSupply() external view returns (uint256)` — **anyone** — value: NONE
- L325 `modifier onlyDeployerOrRegistry()` — **internal (callers: setMinter, setVault, setDividend)** — value: NONE
- L333 `function setMinter(address _minter) external onlyDeployerOrRegistry` — **deployer or registry** — value: NONE
- L338 `function setVault(address _vault) external onlyDeployerOrRegistry` — **deployer or registry** — value: NONE
- L343 `function setDividend(address _dividend) external onlyDeployerOrRegistry` — **deployer or registry** — value: NONE
- L351 `function setLiquidatorMinter(address _minter) external` — **deployer, registry, or the wired minter (the volume hook)** — value: NONE
- L357 `function setLiquidatorURI(string calldata uri) external` — **deployer** — value: NONE
- L365 `function mintLiquidator(address to) external returns (uint256 tokenId)` — **liquidatorMinter (the wired PerpEngine)** — value: NONE
- L370 `function mintLiquidatorWithStats(address to, LiqStats calldata st) external returns (uint256 tokenId)` — **liquidatorMinter (the wired PerpEngine)** — value: NONE
- L377 `function _mintLiquidator(address to, LiqStats memory st) internal returns (uint256 tokenId)` — **internal (callers: mintLiquidator, mintLiquidatorWithStats)** — value: NONE
- L388 `function liqStats(uint256 tokenId) external view returns (LiqStats memory)` — **anyone** — value: NONE
- L393 `function setLiquidatorRenderer(address r) external` — **deployer** — value: NONE
- L399 `function liquidatoorTrait(uint256 tokenId) external view returns (string memory)` — **anyone** — value: NONE
- L414 `function custodyTransfer(address from, address to, uint256 tokenId) external` — **registry** — value: NONE
- L423 `function setFinalizer(address _finalizer) external` — **deployer** — value: NONE
- L429 `function setMetadata(MetadataMode _mode, address _renderer, string calldata baseURI_) external` — **deployer** — value: NONE
- L439 `function setRarityOdds(uint16[4] calldata cum) external` — **deployer** — value: NONE
- L446 `function setRoyalty(address receiver, uint96 bps) external` — **deployer** — value: NONE
- L455 `function getTransferValidator() external view returns (address)` — **anyone** — value: NONE
- L460 `function getTransferValidationFunction() external pure returns (bytes4 functionSignature, bool isViewFunction)` — **anyone** — value: NONE
- L465 `function setTransferValidator(address validator) external` — **deployer** — value: NONE
- L474 `function mint(address to) external returns (uint256 tokenId)` — **minter (the wired volume hook)** — value: NONE
- L487 `function reveal(uint256 tokenId) external` — **holder of token** — value: NONE
- L507 `function revealBatch(uint256[] calldata tokenIds) external` — **holder of token** — value: NONE
- L515 `function _reveal(uint256 tokenId) private` — **internal (callers: reveal, revealBatch); the caller must own the token** — value: NONE
- L545 `function burnFromVault(uint256 tokenId) external` — **vault** — value: NONE
- L550 `function _rollRarity(uint256 seed) private view returns (uint8)` — **internal (callers: _reveal)** — value: NONE
- L575 `function igniteCauldron() external nonReentrant returns (address token)` — **anyone, unless a finalizer is wired - then only that address** — value: sends native to `registry` (line 585)
- L594 `function soldOut() external view returns (bool)` — **anyone** — value: NONE
- L599 `function remaining() external view returns (uint256)` — **anyone** — value: NONE
- L610 `function isGenesis(uint256 tokenId) public view returns (bool)` — **anyone** — value: NONE
- L617 `function ogTrait(uint256 tokenId) external view returns (string memory)` — **anyone** — value: NONE
- L621 `function tokenURI(uint256 tokenId) public view override returns (string memory)` — **anyone** — value: NONE
- L647 `function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Votes) returns (address)` — **internal (callers: ERC721 _mint, _burn, _transfer and the public transfer entry points)** — value: NONE
- L707 `function _increaseBalance(address account, uint128 amount) internal override(ERC721, ERC721Votes)` — **internal (callers: ERC721 batch-mint plumbing)** — value: NONE
- L715 `function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool)` — **anyone** — value: NONE

**MintCurvePolicy** (`cauldron/MintCurvePolicy.sol`)

- L71 `constructor(uint256 _base, uint256 _spread, uint256 _knee, uint256 _supply)` — **deployer** — value: NONE
- L95 `function priceAt(uint256 k, uint256, uint256) external view returns (uint256)` — **anyone** — value: NONE
- L108 `function totalToMintOut() external view returns (uint256 total)` — **anyone** — value: NONE

**INFTContract** (`interfaces/INFTContract.sol`)

- L8 `function getHolderTaxRate(address holder) external view returns (uint256)` — **declaration only (no body); the only caller in the tree is the hook's private tax helper, which is out of cluster** — value: NONE
- L11 `function balanceOf(address holder) external view returns (uint256)` — **declaration only (no body); no call site exists anywhere in the tree** — value: NONE