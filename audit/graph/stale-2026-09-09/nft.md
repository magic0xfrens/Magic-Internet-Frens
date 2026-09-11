# NFT Cluster Extraction — Cauldron

Scope: `cauldron/MiFrensDividend.sol` (520 lines), `cauldron/MiFrensGenesis.sol` (709), `cauldron/CauldronCollection.sol` (432), `cauldron/CollectionLedger.sol` (156), `cauldron/CauldronVault.sol` (126), `cauldron/CauldronGachaRouter.sol` (448), `cauldron/RedemptionExt.sol` (347), `cauldron/ILiquidatorMintable.sol` (48), `cauldron/ICreatorToken.sol` (19). Read in full (all files' line counts verified with `wc -l` against the brief). Solidity `^0.8.26` throughout — arithmetic is checked except inside the explicit `unchecked` blocks listed in section G.

For accuracy on shared storage/reachability I also grepped (not fully audited) `cauldron/CauldronBase.sol` (storage shared with `RedemptionExt` via delegatecall), `cauldron/PoolOps.sol` (library `RedemptionExt` calls into), `cauldron/ICauldron.sol` (shared types), and `../CauldronRegistry.sol` (the delegatecall forwarder for `RedemptionExt`). Those files are **not** part of the assigned cluster and were not read in full; anything sourced from them is marked accordingly.

Every line number below was read directly from the file at that line; nothing is from memory.

---

## A. THE HOLDER CLAIM PATH

There are **four separate, non-interoperating** claim/redemption systems in this cluster. None of them share an accumulator with another.

### A1. `MiFrensDividend` — genesis MiFren ETH dividend (MasterChef accumulator)

State: `accPerShare` (MiFrensDividend.sol:71), `activeShares` (:73), `residual` (:76), `debtOf[tokenId]` (:82).

- CREDIT — `receive()` (:235-249). When `activeShares==0` the whole deposit sweeps to `treasury` instead of accruing (:238-244). Otherwise:
  ```
  uint256 inc = (amt * ACC) / activeShares;          // :245
  accPerShare += inc;                                  // :246
  residual = amt - (inc * activeShares) / ACC;         // :247
  ```
- Claim formula (view) — `pending(tokenId)` (:255-259):
  ```
  return (accPerShare - debtOf[tokenId]) / ACC;         // :258
  ```
- DEBIT — `_claim(tokenId)` (:506-519):
  ```
  amount = (accPerShare - debtOf[tokenId]) / ACC;       // :511
  debtOf[tokenId] = accPerShare;                          // :512, before interaction
  ```
  paid via `msg.sender.call{value: amount}("")` (:515).
- Checkpoint/marker: `debtOf[tokenId]`, set to `accPerShare` on cast (`_castSpell` :403) and zeroed on transfer-out (`onMiFrenTransfer` :472).
- **Scoping**: no generation/epoch inside this contract — the pot is perpetual across every brew ("iteration #1, #2, #3… forever", :26). The scoping unit is the **active set** (currently-enchanted frens only): enforced at `pending()` line 257 `if (enchantedBy[tokenId] != mifrens.ownerOf(tokenId)) return 0;` and at `_claim()` line 509 `if (enchantedBy[tokenId] != msg.sender) revert NotEnchanted();`.

### A2. `MiFrensDividend` — per-asset ERC20 basket (same active-share base)

State: `accPerShareOf[asset]` (:101), `debtOfAsset[tokenId][asset]` (:102), `assets[]`/`knownAsset` (:122-123), `MAX_ASSETS=3` (:124), `owedAsset[holder][asset]` (:133).

- CREDIT — `fundToken(asset, amount)` (:273-289): `accPerShareOf[asset] += (amount * ACC) / activeShares;` (:287).
- Claim formula (view) — `pendingToken(tokenId, asset)` (:292-296): `return (accPerShareOf[asset] - debtOfAsset[tokenId][asset]) / ACC;` (:295).
- DEBIT — `claimTokens(tokenId)` (:307-329), per asset in the (≤3-entry) basket:
  ```
  uint256 amt = (accPerShareOf[a] - debtOfAsset[tokenId][a]) / ACC;  // :321
  debtOfAsset[tokenId][a] = accPerShareOf[a];                          // :323, before interaction
  ```
  A failed push is banked to `owedAsset[msg.sender][a]` (:326) rather than reverting the batch; `withdrawOwedToken(asset)` (:333-343) pays that out separately and *does* revert on failure.
- Checkpoint set on cast: `_castSpell` loop (:409-413) sets `debtOfAsset[tokenId][a] = accPerShareOf[a]` for every current basket asset — the header comment (:404-408) explains this is required or a late joiner would claim the entire pre-join history.
- Checkpoint settled on transfer: `onMiFrenTransfer` loop (:459-468) banks `owedAsset[cur][a] += (acc-d)/ACC` and advances `debtOfAsset[tokenId][a] = acc` — must happen in the same call that drops the token from `activeShares` (comment :452-456).
- **Comment/code discrepancy (rule 4)**: the header comment block above `assets` (:108-121) says "THREE, NOT EIGHT" and matches `MAX_ASSETS = 3` (:124). But the comment inside `onMiFrenTransfer` (:457) says *"why MAX_ASSETS is 4"* — the code constant is unambiguously `3` (:124, grepped, only one declaration exists). Recorded as a comment/code mismatch, not evaluated for impact.

### A3. `CauldronVault` — per-brew NFT floor (ETH, burn-to-redeem)

State: `redeemed` (:40), `floorOffset` (immutable, :47), `closed` (:51).

- Formula: `outstanding() = eligible - redeemed`, `eligible = minted > floorOffset ? minted - floorOffset : 0` (:55-59, `minted` read live via `collection.totalMinted()`). `floorPerNFT() = address(this).balance / outstanding()` (:77-81).
- CREDIT: ETH simply arrives via `receive()` (:72-74); no per-holder accumulator, the floor is inferred fresh from `balance / outstanding` every call.
- DEBIT — `redeem(tokenId)` (:94-112):
  ```
  amount = n == 0 ? 0 : address(this).balance / n;   // :100
  redeemed += 1;                                        // :106
  collection.burnFromVault(tokenId);                     // :107
  (bool ok, ) = msg.sender.call{value: amount}("");      // :109
  ```
  State (`redeemed`) and the NFT burn both happen before the ETH leaves (CEI honored).
- **Scoping**: `if (tokenId <= floorOffset) revert NotOwner();` (:96) — this vault serves only ids `> floorOffset` (the header comment :42-46 explains `floorOffset = GENESIS_SUPPLY` for the iteration-#2 continuation, so genesis ids never draw this vault). `if (closed) revert Closed();` (:95) ends the epoch at brew death.
- **Comment claim, not verified in this cluster**: lines 85-93 assert that under the shipped configuration `hook.setVault(0)` is wired so this vault's balance is always zero and `redeem` always reverts `UnifiedFloorActive` (:101-104). `hook`/`CauldronHook.sol` is not in the assigned cluster, so this is recorded as a comment claim, not independently confirmed.

### A4. `CollectionLedger` — per-collection token-denominated floor (live token, "recycle not burn")

State (all keyed by `gen`): `entitledTokens[gen]` (:45), `retired[gen]` (:48), `frozenSupply[gen]` (:52), `crystallized[gen]` (:55), plus global `totalEntitled` (:59).

- Formula: `outstanding(gen, mintedNow) = supply - retired[gen]`, `supply = crystallized[gen] ? frozenSupply[gen] : mintedNow` (:86-90). `floorPerNFT(gen, mintedNow) = entitledTokens[gen] / outstanding(gen, mintedNow)` (:94-98).
- No per-holder checkpoint exists here at all — this is **not** a MasterChef accumulator. Each redeem computes a fresh pro-rata share of the *current* pot, like the Vault (A3), not a debt-tracked claim like A1/A2.
- CREDIT — `credit(gen, tokens)` (onlyRegistry) (:106-111): `entitledTokens[gen] += tokens; totalEntitled += tokens;`
- DEBIT — `redeem(gen, mintedNow)` (onlyRegistry) (:117-125):
  ```
  payout = entitledTokens[gen] / n;     // :120, rounds DOWN — comment: "Σ never drifts above reserve"
  entitledTokens[gen] -= payout;          // :121
  retired[gen] += 1;                      // :122
  totalEntitled -= payout;                // :123
  ```
- Un-retire — `buyback(gen, mintedNow, paid)` (onlyRegistry) (:130-136): `entitledTokens[gen] += paid; retired[gen] -= 1;` (requires `retired[gen] != 0`, :132).
- Freeze — `crystallize(gen, mintedAtDeath, extraEntitled)` (onlyRegistry), one-time per `gen` (:143-155).
- **Scoping**: every mapping is keyed by `gen`; there is no cross-generation mixing possible by construction. This contract itself never checks NFT ownership or moves an NFT or a token — "Pure accounting: holds no tokens, makes no external calls" (:35-36) is accurate: grepped, `CollectionLedger.sol` contains no `.call`/`.transfer`/external interface invocation of any kind. Eligibility/ownership verification is therefore necessarily done by the caller (the registry, `onlyRegistry`-gated, out of cluster) before it calls `redeem`.

### A5. `RedemptionExt` (+ `CauldronBase` shared storage) — genesis OG "reserve" recycle

State (declared in `CauldronBase.sol`, shared via delegatecall — see file header comment RedemptionExt.sol:19-39): `genesisReserveOutstanding` (CauldronBase.sol:198), `genesisShares` (:236), `genesisPending` (:211), `currentGeneration` (:175).

- Formula — `floorPerFren()` (CauldronBase.sol:368-372): `genesisReserveOutstanding / genesisShares`.
- DEBIT — `redeemOgFren(mifrenTokenId)` (RedemptionExt.sol:72-100):
  ```
  uint256 F = floorPerFren();                                          // :80
  if (genesisReserveOutstanding >= F) genesisReserveOutstanding -= F;  // :85 — quoted verbatim; no `else` branch
  IMiFrensContinuable(mifrens).custodyTransfer(msg.sender, address(this), mifrenTokenId); // :86 — NFT to treasury
  amount = PoolOps.claimFromReserve(..., F, msg.sender);                // :89-93 — pulls token straight to msg.sender
  if (amount + 1e12 < F) revert NoBalance();                            // :98 — dust-tolerance check AFTER both external calls
  ```
  Comment (:82-84) labels this ordering "Effects first: debit the reserve accounting + move the NFT to treasury ... Then pull the tokens from the LP" — the debit and NFT move precede the value pull; the post-hoc revert at :98 unwinds the whole transaction (including the NFT move) if the LP came up short.
- CREDIT — `_pullGrow(from, amount)` (private, :159-178), invoked by `donateToReserve` (:130-134, permissionless) and `buyTreasuryOgFren` (:109-121, pays `2×floorPerFren()`):
  ```
  IERC20(generationToken[g]).transferFrom(from, address(this), amount);   // :161
  added = PoolOps.addToReserve(...);                                       // :162-166
  if (added == 0) revert NoBalance();                                       // :175
  genesisReserveOutstanding += added;                                       // :176
  ```
- **Scoping**: `if (mifrenTokenId == 0 || mifrenTokenId > genesisShares) revert BadConfig();` (:77) is the OG-only tranche gate. There is otherwise **no per-generation reset** of `genesisReserveOutstanding` — the same global balance persists across relaunches (header comment RedemptionExt.sol:58-60: "LIVE floor share of WHATEVER token the eternal machine is currently running"). What *is* re-read per call is `g = currentGeneration` (:88), used to select which V4 reserve *position* (`generationReservePositionId[g]`, `generationPoolKey[g]`, `reserveTickLower/Upper[g]`) backs the payout — i.e. the epoch scoping applies to *which LP position is drained*, not to the entitlement balance itself.
- A related but distinct accumulator, `genesisPending`, is credited from `materializeLegacyReserve()` (:141-154) at `genesisPending += og;` (:152) — the comment at CauldronBase.sol:209-210 states this folds into `genesisReserveOutstanding` "at the next relaunch"; the folding code itself was not found anywhere in this cluster (UNSURE — likely lives in `CauldronRegistry.sol`, outside the assigned scope).

### A6. Cross-system fee flow (worth recording explicitly)

`MiFrensDividend._collectEnchantFee` (:422-435) pulls a re-enchant fee in `reg.currentToken()` from the caster (:432) and routes it into system A5's reserve via `reg.donateToReserve(fee)` (:434) — i.e. paying to re-enchant a *moved* genesis fren grows the OG reserve floor (A5), not the ETH dividend pot (A1). The fee is collected **before** `activeShares += 1` (:396 call precedes :397 increment) — comment (:393-395): "Fee collected before any state change so a fren can never activate unpaid."

---

## B. DENOMINATION

- **`MiFrensDividend`**: two fully separate denominations, never compared or cross-paid.
  - Native ETH: `accPerShare`/`debtOf`/`owed` (A1). Chosen implicitly — `receive()` (:235) is the only ETH entry, no `asset` parameter.
  - ERC20 basket: `accPerShareOf`/`debtOfAsset`/`owedAsset`/`assets[]` (A2). Asset is chosen by whoever calls `fundToken(address asset, uint256 amount)` (:273) — **but that caller is gated**: `if (msg.sender != funder) revert NotOwner();` (:278). The `funder` (the hook, wired once by `treasury` via `setFunder`, :199-204) picks which ERC20 addresses ever enter the basket, capped at `MAX_ASSETS = 3` total for the contract's lifetime (:281-282, no removal path — see comment :206-230).
  - No line in this file compares or pays an ETH amount from the ERC20 accounting or vice versa — `claim`/`claimMany`/`withdrawOwed` touch only ETH state; `claimTokens`/`withdrawOwedToken` touch only the basket maps.
- **`CauldronVault`**: ETH only. `receive()` (:72), payout `.call{value: amount}` (:109), sweep `.call{value: swept}` (:121). No ERC20 handling anywhere in the file.
- **`CollectionLedger`**: no fixed asset identity — `entitledTokens[gen]` is "denominated in the LIVE iteration token; migrates as a pure number" (comment :16, :44). The contract never names an ERC20 address and moves no tokens itself (confirmed above, A4) — the actual token identity/consistency is entirely the calling registry's responsibility, not enforced here.
- **`RedemptionExt`**: the reserve is denominated in `generationToken[currentGeneration]` — the CURRENT iteration's ERC20 (never ETH). `_pullGrow` pulls via `IERC20(generationToken[g]).transferFrom` (:161). `redeemOgFren`'s payout comes back through `PoolOps.claimFromReserve`, which (per `PoolOps.sol:985-1013`, read for verification only, not in cluster) reads/pays `IERC20(Currency.unwrap(key.currency1))` — i.e. `key.currency1`, treated throughout `PoolOps.sol` as "the token" side of the pair (ETH is `currency0` by the `address(0)`-sorts-first convention also used in `CauldronGachaRouter._key()`, :171-179).
- **`CauldronGachaRouter`**: routes both ETH (`msg.value`, currency0) and the current iteration token (currency1, via `registry.currentToken()`, :174) through the same V4 pool; never mixes them in a balance comparison — `ethConsumed`/`tokenConsumed`/`sellEthGross` are tracked as separate return values (:231-232) and paid out separately (:247-253).
- **`MiFrensGenesis` presale**: ETH only — `msg.value != PRICE * quantity` (:267).

---

## C. SUPPLY CONSERVATION

### NFT mints

| # | Function | Bound | Bound quote |
|---|---|---|---|
| 1 | `MiFrensGenesis.mint(uint256 quantity)` (presale) :262-284 | `GENESIS_SUPPLY` (immutable) | `if (minted + quantity > GENESIS_SUPPLY) revert ExceedsSupply();` (:266) |
| 2 | `MiFrensGenesis.mint(address to)` (volume) :474-483 | `MAX_SUPPLY` (immutable) | `if (minted >= MAX_SUPPLY) revert MintedOut();` (:476) |
| 3 | `MiFrensGenesis._mintLiquidator` :377-385 | **none** | `tokenId = LIQUIDATOR_ID_BASE + (++liquidatorMinted);` (:379) — **UNBOUNDED at line 379**, matches doc claim "uncapped" (:31) |
| 4 | `CauldronCollection.mint(address to)` :207-215 | `maxSupply` (immutable) | `if (totalMinted >= maxSupply) revert MintedOut();` (:209) |
| 5 | `CauldronCollection._mintLiquidator` :349-358 | **none** | `tokenId = LIQUIDATOR_ID_BASE + (++liquidatorMinted);` (:351) — **UNBOUNDED at line 351** |

Both uncapped Liquidatoor counters live in a disjoint id space (`LIQUIDATOR_ID_BASE = 1_000_000`, MiFrensGenesis.sol:181 / CauldronCollection.sol:74) that the art-supply cap is constructor-checked to never reach: `if (maxSupply_ < genesisSupply_ || maxSupply_ >= LIQUIDATOR_ID_BASE) revert ExceedsSupply();` (MiFrensGenesis.sol:239); `if (maxSupply_ == 0 || maxSupply_ >= LIQUIDATOR_ID_BASE) revert BadConfig();` (CauldronCollection.sol:148) — so the two counters cannot collide, though badge count itself has no cap.

**2 of 5 NFT-mint sites are unbounded** (both Liquidatoor badge mints).

### NFT burns

Both `MiFrensGenesis.burnFromVault` (:545-548) and `CauldronCollection.burnFromVault` (:384-387) are single-token, `vault`-gated (`if (msg.sender != vault) revert OnlyVault();`), and are the only `_burn` call sites in the cluster (grepped: no other `_burn(` appears in either file). Each burn is paired 1:1 with `CauldronVault.redeem`'s `redeemed += 1` (:106) — the vault's own header states the invariant explicitly: "as holders redeem the remaining floor is unaffected (balance and outstanding both drop by one share). No NFT is ever unbacked." (CauldronVault.sol:23-24).

The A4/A5 redemption paths (`CollectionLedger`, `RedemptionExt`) never burn — they move the NFT to treasury custody instead, via `custodyTransfer` (MiFrensGenesis.sol:414-417, CauldronCollection.sol:394-397), explicitly documented as non-burning: "The fren is NEVER burned — the collection stays 1111." (MiFrensGenesis.sol:413); "Never burns — the collection size is preserved; the NFT just recycles." (CauldronCollection.sol:393).

### Ledger/entitlement "supply"

`CollectionLedger.credit(gen, tokens)` (:106-111) has **no upper bound on `tokens` inside this contract** — `entitledTokens[gen] += tokens; totalEntitled += tokens;` (:108-109) is unconditional past the `tokens != 0` check (:107). The invariant `totalEntitled == Σ entitledTokens[gen]` is preserved by construction (every mutator updates both in lockstep) but nothing in this file bounds it against actual token backing — the header comment (:19-21) states the registry is relied on to keep the reserve LP ≥ `totalEntitled` ("Invariant R"), which is enforced outside this cluster.

`RedemptionExt._pullGrow` bounds its credit by what `PoolOps.addToReserve` actually accepted (`added`, possibly less than `amount` due to rounding — comment :167-174), not by a local cap; `redeemOgFren`'s debit at :85 is conditionally skipped (`if (genesisReserveOutstanding >= F)`) rather than unconditionally subtracted, so it cannot underflow but can also silently not-decrement if ever called when `genesisReserveOutstanding < F` (recorded as fact only; whether that state is reachable depends on code outside this cluster).

No ERC20 `_mint`/`_burn` occurs directly in any of the 9 cluster files. `PoolOps.materializeLegacy`'s `toReserve==false` branch calls `ICauldronBurn(token).burn(registryAddr, amt)` (seen while verifying `RedemptionExt.materializeLegacyReserve`'s target, `PoolOps.sol` line ~1178) — reachable from `RedemptionExt.materializeLegacyReserve` (:141) only if the registry ever calls `PoolOps.materializeLegacy` with `toReserve=false`; the call actually made from this cluster (:145-151) passes `true`, so this branch is not reached from `RedemptionExt.sol` as written.

---

## D. UNBOUNDED LOOPS

Grepped every `for (`/`while (` across all 9 files — 11 loop sites total, 0 in `CollectionLedger.sol`, `CauldronVault.sol`, `RedemptionExt.sol`, or either interface file.

| Loop | Bound enforced | Caller-growable? |
|---|---|---|
| `MiFrensGenesis.mint` presale, :276 `for (uint256 i = 0; i < quantity;)` | `quantity` checked against `MAX_PER_WALLET` (immutable, :268) and remaining `GENESIS_SUPPLY` (:266) | No — capped by deploy-time immutable |
| `MiFrensGenesis.revealBatch`, :512 `for (uint256 i; i < n; ++i) _reveal(tokenIds[i]);` | `if (n == 0 \|\| n > 50) revert BadBatch();` (:511) | No — hard cap 50 |
| `MiFrensGenesis._rollRarity`, :552 `for (uint8 i = 0; i < 4; i++)` | fixed 4 (rarity tiers) | No |
| `CauldronCollection.revealBatch`, :244 | `if (n == 0 \|\| n > 50) revert BadBatch();` (:243) | No — hard cap 50 |
| `CauldronCollection._rollRarity`, :278 | fixed 4 | No |
| `CauldronGachaRouter._churn`, :376 `for (uint256 i = 0; i < loops;)` | `if (loops == 0 \|\| loops > MAX_LOOPS) revert BadLoops();` checked in the caller `playChurn` (:291) before `_churn` is reached | No — hard cap 10 |
| `MiFrensDividend.claimTokens`, :319 `for (uint256 i; i < n; ++i)`, `n = assets.length` | `assets.length` capped at `MAX_ASSETS = 3`, growable only by `funder` (`fundToken`, :278/:282) | No, not by the *looping* caller — only `funder` can grow `assets[]`, and it's capped at 3 regardless |
| `MiFrensDividend._castSpell` internal loop, :410 | same `assets.length` bound (≤3) | No |
| `MiFrensDividend.onMiFrenTransfer` internal loop, :460 | same `assets.length` bound (≤3); this one runs under `MiFrensGenesis`'s fixed forwarded gas budget (`GAS_DIVIDEND_FWD = 260_000`, MiFrensGenesis.sol:110) | No |
| **`MiFrensDividend.castMany`, :382** `for (uint256 i = 0; i < n;) { _castSpell(tokenIds[i]); unchecked { ++i; } }`, `n = tokenIds.length` | **none in this function** | **YES — caller supplies the array length directly with no cap, contrast `revealBatch`'s explicit `n > 50` guard.** An invalid/unowned id reverts the whole call (`_castSpell` reverts on tokenId out of range or not owned, :386-387), so garbage cannot be used to grief cheaply, but a caller can size the array as large as gas allows. |
| **`MiFrensDividend.claimMany`, :490** `for (uint256 i = 0; i < n;) { total += _claim(tokenIds[i]); unchecked { ++i; } }`, `n = tokenIds.length` | **none in this function** | **YES — same pattern as `castMany`.** Is `nonReentrant`-guarded (unlike `castMany`, which has no `nonReentrant`). |

**2 caller-growable loops** (both in `MiFrensDividend.sol`: `castMany` line 382, `claimMany` line 490).

---

## E. EXTERNAL CALLS WITH VALUE / CEI ORDERING

All `.call{value:...}`, low-level token `.call(...)`, and library calls that move value, with ordering relative to the state update that protects them.

- **MiFrensDividend.sol**
  - `:240` `treasury.call{value: amt}("")` in `receive()` — `residual` zeroed first (:239); on failure `residual = amt` restores it (:241). Not `nonReentrant`.
  - `:348-351` `_pull`: `asset.call(transferFrom...)`, used by `fundToken` — the pull (:286) happens **before** `accPerShareOf[asset] += ...` (:287): interaction precedes that specific effect.
  - `:357-360` `_tryPush`: `asset.call(transfer...)`, used by `claimTokens` (debt marker set at :323 *before* the push at :325 — CEI honored, failure banked not reverted) and `withdrawOwedToken` (`owedAsset` zeroed at :336 before push at :340 — CEI honored, failure reverts the whole call, undoing the zeroing).
  - `:500` `msg.sender.call{value: amount}("")` in `withdrawOwed()` — `owed[msg.sender] = 0` at :498 precedes it; `nonReentrant`.
  - `:515` `msg.sender.call{value: amount}("")` in `_claim()` — `debtOf[tokenId] = accPerShare` at :512 precedes it (inline comment "effects before interaction"); `claim`/`claimMany` are `nonReentrant`.
  - `castSpell`/`castMany` (:375-383) are **not** `nonReentrant` despite `_castSpell` reaching `_collectEnchantFee`'s external calls (`transferFrom`, `approve`, `reg.donateToReserve`, :432-434).
- **CauldronVault.sol**
  - `:109` `msg.sender.call{value: amount}("")` in `redeem()` — `redeemed += 1` (:106) and `collection.burnFromVault(tokenId)` (:107) both precede it; `nonReentrant`.
  - `:121` `registry.call{value: swept}("")` in `close()` — `closed = true` (:118) precedes it; `nonReentrant`.
- **MiFrensGenesis.sol**
  - `:305` `msg.sender.call{value: amount}("")` in `refund()` — `paid[msg.sender] = 0` (:304, comment "CEI") precedes it; `nonReentrant`.
  - `:576` `registry.summon{value: bal}()` in `finalize()` — `finalized = true` (:574) precedes it; `nonReentrant`.
  - `:686` `IMiFrensDividendHook(dividend).onMiFrenTransfer{gas: GAS_DIVIDEND_FWD}(tokenId, from)` inside `_update`, wrapped in try/catch (:686-687) — a gas floor is enforced immediately before it: `if (gasleft() < GAS_DIVIDEND_MIN) revert InsufficientGas();` (:685).
- **CauldronGachaRouter.sol**
  - `:252` and `:305` `msg.sender.call{value: ...}("")` in `_play`/`playChurn` — both occur after `hook.commitCrystals`/`hook.resolveTickets` (:243-244, :301-302), matching the inline comment "EFFECTS first ... THEN pay the player out (audit L3)" (:237-238).
  - `:443` `to.call{value: amount}("")` in `rescueETH`, `onlyOwner`.
  - `:418` `poolManager.settle{value: amount}()` in `_settle`, to the (trusted) V4 core.
- **RedemptionExt.sol**
  - `redeemOgFren` (:72-100): `genesisReserveOutstanding` debit (:85) and `custodyTransfer` (:86, external call into `mifrens`) both precede `PoolOps.claimFromReserve` (:89-93, which pays `msg.sender` directly); the dust-check revert (:98) is *after* all of the above — see A5.
  - `rotateSlice` (:211-283): value-moving calls — `PoolOps.removePartial` (:245), `PoolOps.sendAsset` (:257), `IQuoteRotator.swapOnce`/`withdraw` (:258-259), `PoolOps.openOrAddPair` (:264), `IHookVolume.linkVolume` (:278) — **all precede** the governor bookkeeping call `ITreasuryGovernor(gov).consume(sliceBps)` (:281); comment (:279-280): "Booked AFTER the move succeeds, so a reverted slice does not burn envelope the treasury never actually spent." This function has **no `nonReentrant` modifier**.
  - `completeRotation` (:316-342, `onlyOwner`, also no `nonReentrant`): `PoolOps.openOrAddPair` (:325) then `IHookVolume.linkVolume` (:339).

---

## F. RANDOMNESS

Only the NFT rarity **reveal** step uses on-chain randomness in this cluster; the crystal-gacha itself lives in `hook`/`ICauldronHookGacha`, outside the cluster — `CauldronGachaRouter` only forwards `commitCrystals`/`resolveTickets` calls to it (:243-244 etc.) and rolls nothing itself. Grepped the whole cluster for `prevrandao`, `block.timestamp`, `VRF`, `ecrecover`, `block.difficulty` — zero hits outside of explanatory comments; the only randomness primitive used anywhere is `blockhash`.

Identical mechanism in `MiFrensGenesis._reveal` (:515-542) and `CauldronCollection._reveal` (:247-274):

1. **Commit** at mint: `mintBlockOf[tokenId] = uint48(block.number);` (MiFrensGenesis.sol:480 volume mint only — the presale mint path, :262-284, sets `revealed[id]=true` immediately at :278 and never rolls rarity at all; CauldronCollection.sol:212, its only mint path).
2. **Reveal gate**: `if (block.number <= mb) revert NotReady();` (MiFrensGenesis.sol:519 / CauldronCollection.sol:251).
3. **Source**: `bytes32 bh = blockhash(mb);` (MiFrensGenesis.sol:520 / CauldronCollection.sol:252) — the mint block's hash.
4. **Expiry handling**: if `bh == 0` (blockhash unavailable, >256 blocks old), re-anchor rather than fall back to a predictable value: `mintBlockOf[tokenId] = uint48(block.number); emit ReAnchored(...); return;` (MiFrensGenesis.sol:532-536 / CauldronCollection.sol:264-268) — no revert, so the re-anchor is not rolled back.
5. **Roll**: `uint8 rarity = _rollRarity(uint256(keccak256(abi.encodePacked(bh, tokenId, address(this)))));` (MiFrensGenesis.sol:537 / CauldronCollection.sol:269). Feeds: mint-block hash, `tokenId`, own contract address.
6. **Bucketing** — `_rollRarity(seed)`: `uint16 r = uint16(seed % 10_000); for (i=0;i<4;i++) if (r < rarityCumBps[i]) return i; return 0;` (MiFrensGenesis.sol:550-556 / CauldronCollection.sol:276-282) against `rarityCumBps` default `[7900, 9400, 9900, 10000]` (MiFrensGenesis.sol:210 / CauldronCollection.sol:101), deployer-settable (`setRarityOdds`; `CauldronCollection`'s version additionally requires `totalMinted == 0`, :428, `MiFrensGenesis`'s does not, :439-443).

No VRF, signature, or committee input anywhere in this reveal path — the sole trust assumption is that the block proposer for block `mb+1..mb+256` cannot both know `tokenId`'s pending reveal and select a favorable `blockhash(mb)` (blockhash is fixed by the time the mint block itself is mined, before the token owner can act).

---

## G. `unchecked` BLOCKS (rule 5 — every one, grepped)

| File:Line | Content |
|---|---|
| MiFrensDividend.sol:382 | `unchecked { ++i; }` — loop counter in `castMany` |
| MiFrensDividend.sol:470 | `unchecked { activeShares -= 1; }` — real arithmetic (not a loop counter), in `onMiFrenTransfer` |
| MiFrensDividend.sol:490 | `unchecked { ++i; }` — loop counter in `claimMany` |
| MiFrensGenesis.sol:280 | `unchecked { ++i; }` — loop counter in presale `mint` |
| CauldronGachaRouter.sol:405 | `unchecked { ++i; }` — loop counter in `_churn` |

No other `unchecked` blocks in the cluster (grepped all 9 files).

---

## Storage layout per contract

**`CauldronVault.sol`** (:26-126): `collection` (immutable, IBurnableCollection, :34), `registry` (immutable, :37), `redeemed` (uint256, :40), `floorOffset` (immutable uint256, :47), `closed` (bool, :51). Errors: NotOwner, NothingToRedeem, TransferFailed, Closed, NotRegistry, UnifiedFloorActive (:27-32). Events: Deposited, Redeemed, VaultClosed (:61-63).

**`CollectionLedger.sol`** (:38-156): `registry` (immutable, :41), `entitledTokens` (mapping uint256=>uint256, :45), `retired` (mapping uint256=>uint256, :48), `frozenSupply` (mapping uint256=>uint256, :52), `crystallized` (mapping uint256=>bool, :55), `totalEntitled` (uint256, :59). Errors: OnlyRegistry, AlreadyCrystallized, NothingOutstanding, NothingRetired, ZeroAmount (:66-70). Events: Crystallized, Credited, Redeemed, BoughtBack (:61-64).

**`MiFrensDividend.sol`** (:42-520): `mifrens` (immutable, :46), `SHARES` (immutable, :51), `MAX_TOKEN` (immutable, :58), `treasury` (immutable, :63), `registry` (IReserveRegistry, :68), `accPerShare` (:71), `activeShares` (:73), `residual` (:76), `totalDeposited`/`totalClaimed` (:78-79), `debtOf` (mapping uint256=>uint256, :82), `accPerShareOf` (mapping address=>uint256, :101), `debtOfAsset` (mapping uint256=>mapping address=>uint256, :102), `assets` (address[], :122), `knownAsset` (mapping address=>bool, :123), `MAX_ASSETS=3` (constant, :124), `owedAsset` (mapping address=>mapping address=>uint256, :133), `funder` (:146), `enchantedBy` (mapping uint256=>address, :154), `owed` (mapping address=>uint256, :157). Inherits `ReentrancyGuard`.

**`MiFrensGenesis.sol`** (:48-709): ERC721 + ERC721Votes + ERC2981 + ICreatorToken + ILiquidatorMintable + ReentrancyGuard. `GENESIS_SUPPLY`/`MAX_SUPPLY`/`PRICE`/`MAX_PER_WALLET` (immutables, :116-119), `registry` (:123), `deployer` (immutable, :126), `minter` (:130), `vault` (:133), `dividend` (:137), `minted` (:139), `finalized` (:140), `cancelled` (:146), `paid` (mapping address=>uint256, :148), `finalizer` (:158), `_base` (:159), `mode` (:162), `transferValidator` (:169), `renderer` (:170), `LIQUIDATOR_ID_BASE=1_000_000` (constant, :181), `liquidatorMinter` (:184), `liquidatorMinted` (:187), `isLiquidatoor` (mapping, :190), `_liqStats` (mapping uint256=>LiqStats, :193), `liquidatorRenderer` (:198), `liquidatorURI` (:204), `rarityCumBps` (uint16[4], :210), `rarityOf` (:211), `revealed` (:212), `mintBlockOf` (mapping uint256=>uint48, :216), `unrevealedURI` (:217), `everMoved` (mapping uint256=>bool, :406). Gas constants `GAS_DIVIDEND_FWD=260_000` / `GAS_DIVIDEND_MIN=320_000` (:110-111, both keyed to `MiFrensDividend.MAX_ASSETS=3`, cross-checked by an out-of-cluster test per the comment at :107-109).

**`CauldronCollection.sol`** (:24-432): ERC721 + ERC2981 + ICreatorToken + ICauldronCollection + ILiquidatorMintable — **no ReentrancyGuard**. `minter`/`deployer`/`configurator` (immutables, :37-48), `vault` (:51), `maxSupply` (immutable, :54), `mode`/`renderer`/`_baseTokenURI` (:59-65), `totalMinted` (:67), `LIQUIDATOR_ID_BASE=1_000_000` (:74), `liquidatorMinter` (:77), `liquidatorMinted` (:80), `isLiquidatoor` (:83), `_liqStats` (:87), `liquidatorRenderer` (:91), `liquidatorURI` (:94), `rarityCumBps` (:101), `rarityOf` (:104), `mintBlockOf` (:112), `revealed` (:115), `unrevealedURI` (:118), `transferValidator` (:131).

**`CauldronGachaRouter.sol`** (:52-449): `IUnlockCallback`, `Ownable`. `poolManager`/`hook`/`registry`/`hookAddr` (immutables, :55-58), `POOL_FEE=0`/`TICK_SPACING=200`/`MAX_MINTS_PER_CALL=30`/`MAX_LOOPS=10` (constants, :60-63), `_locked` (custom reentrancy flag, :65), `oracle` (:88). Custom `nonReentrant` modifier (:154-159), independent of OZ's.

**`RedemptionExt.sol`** (:56-347): `is CauldronBase` — declares **no new storage of its own**; every storage read/write resolves against `CauldronBase`'s slots under delegatecall (confirmed by the file's own header comment, :14-39, and cross-checked by reading the relevant `CauldronBase.sol` declarations: `summoned` bool :171, `currentGeneration` uint256 :175, `generationToken`/`generationPoolId`/`generationPoolKey`/`generationPositionId`/`generationReservePositionId`/`reserveTickLower`/`reserveTickUpper` mappings :179-196, `genesisReserveOutstanding` uint256 :198, `generationCollection` :203, `collectionLedger` :208, `genesisPending` :211, `mifrens` :232, `genesisShares` :236, `positionManager`/`hook` (storage, not immutable, under delegatecall — :277-278), `allowedQuote` :321, `generationQuote` :332, `quoteRotator` :339, `treasuryGovernor` :345). `MAX_SLICE_BPS=500` is declared locally in `RedemptionExt.sol:287`.

**`ILiquidatorMintable.sol`**: declares `struct LiqStats` (:19-28, packs into 3 slots per its own doc comment) and the interface `mintLiquidatorWithStats`/`mintLiquidator`/`liqStats`, implemented by both `MiFrensGenesis` and `CauldronCollection`.

**`ICreatorToken.sol`**: declares `ITransferValidator.validateTransfer` (external view, called but never implemented in this cluster — the validator is a separate, external contract) and `ICreatorToken`'s three methods, implemented by both `MiFrensGenesis` and `CauldronCollection`.

---

## Function table

128 function bodies recorded in `/tmp/graph/nft.json` (`CauldronVault` 6, `CollectionLedger` 7, `MiFrensDividend` 22, `MiFrensGenesis` 41, `CauldronCollection` 26, `CauldronGachaRouter` 19, `RedemptionExt` 7). Each JSON record carries: contract, signature, visibility, mutability, modifiers, authority, authority_gate_quote, reads, writes, value, edges (target/line/trust-tag), reachability, line. Pure interface declarations (`ITransferValidator.validateTransfer`, and the various external-contract interfaces like `IReserveRegistry`, `IMiFrensShares`, `ICauldronHookGacha`, `ITreasuryGovernor`, `IQuoteRotator`, `IHookVolume`) are not given their own rows (no body to analyze) but appear as `edges` targets on the calling functions instead.

Notable cross-cutting observations surfaced while building the table:

- **Error-name reuse** (factual, not evaluated for severity): `MiFrensGenesis.setRegistry` reverts `ZeroAddress()` for a deployer-authority failure, not an actual zero-address condition (:250). `MiFrensGenesis._reveal` and `CauldronCollection._reveal` both revert `OnlyMinter()` for an *ownership* check unrelated to the minter role (MiFrensGenesis.sol:516, CauldronCollection.sol:248). `CauldronCollection.setTransferValidator`/`setMetadata`/`setLiquidatorURI` all gate on `deployer` but revert `OnlyMinter()` (:193,317,329). `CauldronCollection.custodyTransfer` gates on `deployer` but reverts `OnlyVault()` (:395). `CauldronCollection.setRarityOdds`'s `totalMinted != 0` guard reverts `VaultSet()` (:428).
- **Reentrancy-guard coverage is inconsistent by design-looking omission**: `CauldronCollection.sol` inherits no `ReentrancyGuard` at all (grepped, zero hits). `MiFrensDividend.receive`, `fundToken`, `castSpell`, `castMany` have no `nonReentrant` although `fundToken`/`_castSpell` perform external calls. `RedemptionExt.rotateSlice` and `completeRotation` have no `nonReentrant` while the other five `RedemptionExt`/registry-forwarded functions do.
- **`RedemptionExt.completeRotation`** (:316-342, `onlyOwner`) has **no corresponding forwarder** in `CauldronRegistry.sol` (grepped `completeRotation` there: zero matches, versus explicit thin forwarders found for `rotateSlice`, `redeemOgFren`, `buyTreasuryOgFren`, `donateToReserve`, `materializeLegacyReserve`). Per this file's own header comment (:32-38) a direct call to the deployed `RedemptionExt` runs against its own empty storage. This function's practical reachability is therefore UNSURE beyond what the grep shows — `CauldronRegistry.sol`/`CauldronBase.sol` ownership wiring is outside the assigned cluster and was only spot-checked, not audited.

Full per-function detail (all 128 rows) is in `/tmp/graph/nft.json`.
