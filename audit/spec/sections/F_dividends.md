# Area F — Dividends and the multi-asset fee basket

Files read in full: `contracts/solidity/cauldron/MiFrensDividend.sol` (543 lines),
`contracts/solidity/cauldron/FeeRouteLib.sol` (213 lines),
`contracts/solidity/cauldron/RoyaltyRouter.sol` (35 lines),
`contracts/solidity/cauldron/DefaultFeeRouter.sol` (31 lines).
Fee-routing region read: `contracts/solidity/CauldronHook.sol:1140-1440` (`_routePerpFee`,
`_creditReserve`, `_routeEthFee`, `_takeEthFee`, `_feeAsset` at line 661).
Supporting reads: `contracts/solidity/CauldronRegistry.sol:319-324` (`enchantFee`),
`:649-955` (`summon`/`relaunch`, `currentToken`/`generationQuote` writes),
`contracts/solidity/cauldron/CauldronBase.sol:176` (`currentToken`), `:368-372`
(`floorPerFren`), `contracts/solidity/cauldron/RedemptionExt.sol:380-424`
(`generationQuote[gen]` flip on rotation completion).

Line numbers below were re-verified against the live tree, not `/tmp/blind-tree`.

## F1 — Multi-asset basket (`fundToken`, `claimTokens`, `claim`, `claimMany`, `withdrawOwed`, `withdrawOwedToken`)

**Purpose.** One MasterChef-style accumulator per fee asset (`accPerShareOf[asset]`,
MiFrensDividend.sol:101), sharing one divisor — `activeShares` (line 73) — so a
holder's entitlement is exact per asset with no oracle and no price risk between
accrual and claim (design note, lines 90-100).

**Entrypoints + actual authority.**
- `fundToken(address,uint256)` (line 273) — `msg.sender != funder` reverts `NotOwner()` (line 278). `funder` is set once by `treasury` via `setFunder` (line 199-204); comments identify `funder` as "the hook" (line 135, 146).
- `claimTokens(uint256)` (line 307) — any address that both owns (`mifrens.ownerOf`, line 308) and has cast (`enchantedBy[tokenId]==msg.sender`, line 309) the token.
- `claim(uint256)` (line 502) / `claimMany(uint256[])` (line 507) — ETH-only, same owner+enchanted gate inside `_claim` (lines 530-532).
- `withdrawOwed()` (line 518) — anyone, pays their own `owed[msg.sender]` balance.
- `withdrawOwedToken(address)` (line 333) — anyone, pays their own `owedAsset[msg.sender][asset]`.

**Preconditions.** `fundToken`: `funder` wired, `asset != 0`, `amount != 0` (line 279), `activeShares != 0` (line 280, else `NotEnchanted()` — deposit is refused, not banked), asset list not full (`MAX_ASSETS = 3`, line 124, checked line 282).

**Behavior.** First-time asset: `knownAsset[asset]=true`, pushed to `assets` (lines 281-285). Funds pulled via `transferFrom` with return-value check (`_pull`, lines 347-352). Accumulator bumped: `accPerShareOf[asset] += (amount * ACC) / activeShares` (line 287, `ACC = 1e18`, line 43) — a **flat increment**, no `residual` dust-carry for ERC20 (unlike ETH's `receive()`, which tracks `residual` at line 76/247). `claimTokens` loops all `assets` (line 318-328): per asset it computes `(accPerShareOf[a]-debtOfAsset[tokenId][a])/ACC`, sets the debt to the current accumulator *before* the transfer (line 322-323, effects-before-interaction), and on transfer failure banks the amount to `owedAsset[msg.sender][a]` rather than reverting the whole loop (lines 324-327, "audit D-2").

**Postconditions/invariants.** Sum of `pendingToken` + `owedAsset` + claimed, per asset, equals total funded for that asset (asset-scoped conservation; each asset's accounting is fully isolated — no cross-asset mixing anywhere in the contract). `MAX_ASSETS=3` is permanent — no `removeAsset` (design note lines 206-230: a retire/re-add would let a debt marker of 0 be misread as "entitled from inception" for an asset a holder was never part of; probed at "1005 USDG owed from a pot holding 10", line 220).

**Edge cases.** A reverting/blacklisting token degrades gracefully to `owedAsset` (claimTokens) but `withdrawOwedToken` **does** revert on failure (`TransferFailed()`, line 340) since it settles exactly one asset the caller chose.

**Events.** `TokenDeposited(asset,amount)` (line 148, emitted 288), `TokenClaimed(tokenId,asset,amount)` (line 149, emitted 325), `TokenWithdrawn(to,asset,amount)` (line 151, emitted 341), `FunderSet(funder)` (line 150).

**DENOMINATION: quote-agnostic — MiFrensDividend.sol:101-134 (per-asset mapping), :273-289 (`fundToken`), no dependence on any single quote asset.**

## F2 — Native-ETH accrual (`receive()`)

**Purpose.** ETH-denominated leg of the basket, independent accumulator (`accPerShare`, line 71) with its own `residual` dust-carry (line 76).

**Entrypoints.** `receive() external payable` (line 235) — open to anyone (line 144: "cannot be poisoned because there is nothing to enumerate").

**Behavior.** `totalDeposited += msg.value` (line 236). If `activeShares == 0` (line 238): the whole amount (`msg.value + residual`) sweeps to `treasury` via `.call{value:}` (line 240); on send failure it is held in `residual` for retry on the next deposit (line 241) rather than lost. Emits `TreasuryFunded(amt)` (line 164/242) on success. If `activeShares > 0`: `inc = (amt*ACC)/activeShares`, `accPerShare += inc`, and the floor-division remainder is kept in `residual = amt - (inc*activeShares)/ACC` (lines 245-247) so sub-share dust is never dropped. Emits `Deposited(msg.value, accPerShare)` (line 159/248).

**activeShares == 0 case.** Deposit is never lost: swept to `treasury` (not reverted, unlike `fundToken`'s ERC20 refusal at line 280) — comment lines 267-271 explains the asymmetry (a native sweep cannot fail the way an arbitrary-token transfer can within a swap).

**DENOMINATION: ETH-only — MiFrensDividend.sol:235-249 (separate storage/accumulator from the basket).**

## F3 — Settlement on transfer (`onMiFrenTransfer`)

**Purpose.** Stop a leaving fren's earning window exactly at transfer and free its `activeShares` slot for the correct future divisor.

**Entrypoints + authority.** `onMiFrenTransfer(uint256 tokenId, address /*from*/)` (line 464) — gated `msg.sender != address(mifrens)` → `NotCollection()` (line 465); called from the MiFrens collection's `_update` per the doc comment (lines 460-463) — not independently verified inside this file (the collection contract itself is out of scope for this pass).

**Behavior.** No-op if `enchantedBy[tokenId]==0` (line 467). Else: settles ETH to `owed[cur]` (line 468), then loops `assets` and settles each ERC20 leg into `owedAsset[cur][a]`, advancing `debtOfAsset[tokenId][a]` to the current accumulator (lines 482-491, "audit D-3" — this was previously ETH-only and silently forfeited ERC20 accrual on transfer; comment explicitly documents the prior bug). Then `activeShares -= 1` (unchecked, line 493), `enchantedBy[tokenId]=0`, `debtOf[tokenId]=0` (lines 494-495). Emits `SpellBroken(tokenId, cur)` (line 162/496).

**If not called.** Doc comment (lines 32-33, 398-399) states a skipped hook leaves the entry "stale"; `_castSpell`'s stale branch (`cur != address(0)`, lines 398-402, 427-436) handles recovery by settling the prior caster (both ETH and all basket assets, mirroring `onMiFrenTransfer`) when the *new* owner next calls `castSpell`, without changing `activeShares` net. No other automatic recovery path exists in this file; until a new cast happens, `pending`/`pendingToken` read `enchantedBy[tokenId] != mifrens.ownerOf(tokenId)` (lines 257, 294) and return 0 for the token — it neither earns for the new owner nor pays out to the old one until settled.

**DENOMINATION: quote-agnostic — MiFrensDividend.sol:482-491 (loops all basket assets, mirrors the ETH settlement).**

## F4 — Enchant / re-enchant (`castSpell`, `enchantFee`)

**Purpose.** Join the active earning set; a moved (non-original) fren pays a fee that grows the genesis redemption reserve.

**Entrypoints.** `castSpell(uint256)` (line 375) → `_castSpell` (line 385); `castMany(uint256[])` (line 380).

**Fee computation trace.** `_collectEnchantFee` (line 445): no-op if `registry` unset (line 447) or the token is an original never-moved OG (`tokenId<=SHARES && !everMoved`, line 449). Else `fee = reg.enchantFee()` (line 450) — this calls `CauldronRegistry.enchantFee()` (CauldronRegistry.sol:322-324): `return (floorPerFren() * enchantFeeMultBps) / 10_000`. `floorPerFren()` (CauldronBase.sol:368-372) = `genesisReserveOutstanding / genesisShares`.

**What asset is `floorPerFren` in, and what does the caller pay?** `genesisReserveOutstanding` is sized from `genesisSharePerFren * genesisShares` at `summon`-time (CauldronRegistry.sol:687) and incremented from proceeds denominated in the **iteration token** (`currentToken`) — not the fee/quote asset. `_collectEnchantFee` reads `tok = reg.currentToken()` (MiFrensDividend.sol:452), pulls `fee` of `tok` via `transferFrom` (line 455), approves, and calls `reg.donateToReserve(fee)` (lines 456-457). `currentToken` is the live generation's deployed ERC20 (`CauldronBase.sol:176`, written at `CauldronRegistry.sol:673` and `:898`), e.g. the "Gnomeland" meme-token contract — a **different asset** from the fee-basket's `assets[]` (ETH/USDG/xNVDA quote assets accrued via `fundToken`/`receive()`). The enchant fee is paid in the current *iteration token*, never in a basket quote asset, and this fee is routed into the registry's genesis reserve (`donateToReserve`), not into `MiFrensDividend`'s own accumulators.

**Do they agree after a rotation?** No — they are orthogonal axes by design and were never meant to agree. Rotation (`RedemptionExt.sol:413`) re-points `generationQuote[gen]` (the AMM's quote/fee asset), while `currentToken` (the iteration token `enchantFee` is paid in) is re-pointed separately at `CauldronRegistry.sol:898` on `relaunch`. A caller re-enchanting must hold/approve whatever `currentToken()` is *at call time*; this is unrelated to which asset(s) sit in the dividend's fee basket.

**Behavior (state).** Fresh join (`cur==0`, line 390): fee collected first (line 396), then `activeShares += 1` (line 397). Stale re-point (`cur!=0`, line 398): settles prior caster's ETH into `owed[cur]` (line 401) without changing `activeShares`. Both branches then set `debtOf[tokenId]=accPerShare` (line 403) and loop all basket `assets` to set `debtOfAsset[tokenId][a] = accPerShareOf[a]` — settling the stale caster's basket legs into `owedAsset[cur][a]` first if `cur != address(0)` (lines 427-436, "audit"). `enchantedBy[tokenId]=msg.sender` (line 437). Emits `SpellCast(tokenId, msg.sender)` (line 161/438).

**DENOMINATION: quote-agnostic for the earning mechanics (F1-style basket settlement, lines 427-436) — ETH-only... actually asset-of-`currentToken` for the enchant fee itself, which is NEITHER "ETH-only" nor a basket quote asset — MiFrensDividend.sol:452-457, CauldronRegistry.sol:322-324.**

## F5 — Route from `afterSwap` to a holder's claimable balance

**Purpose.** Trace a collected fee, per asset, from the hook's swap hot path to a genesis holder's claimable balance.

**Behavior.** `_takeEthFee` (CauldronHook.sol:1390) records `_feeAsset = Currency.unwrap(feeCur)` (line 1423) **before** any routing (comment lines 1418-1421: leaving it stale would misattribute a USDG fee as ETH), where `feeCur` is whichever side of the pool is the quote (`quoteIsCurrency0[id]`, line 1422). Base fee routes via `_routePerpFee` (perp sender, line 1429) or `_routeEthFee` (line 1430); surtax always via `_routeEthFee` (or `FeeRouteLib.routeSplit` guild-only path, lines 1432-1439).

`_routeEthFee` (line 1184): optionally carves `proposerOwed` (native-only, line 1222). Computes `wantGuild`/`wantFloor`/`wantRelaunch` (built-in split or pluggable `IFeeRouter`, lines 1232-1256). Legacy-buyback and non-native-floor carve-outs (lines 1258-1316) can zero `toFloor` and fold it to `wantRelaunch`. Final send: `_creditReserve(wantRelaunch + FeeRouteLib.routeSplit(_feeAsset, guild, vault, wantGuild, toFloor))` (lines 1317-1319).

`FeeRouteLib.routeSplit` (FeeRouteLib.sol:48-71): `toGuild` portion → `_fundGuild(asset, guild, toGuild)` (line 64, private helper lines 128-135). For `asset==address(0)`: `guild.call{value:amount}("")` — lands in `MiFrensDividend.receive()` (F2). For an ERC20: `approve(guild, amount)` then `guild.call(fundToken(asset,amount))` — lands in `MiFrensDividend.fundToken` (F1, line 273), which pulls via `transferFrom`. Failure of either leg (`!ok`/`!approved`) is swallowed, `routeSplit` returns the un-delivered amount as `leftover`, and `_creditReserve` books it to `relaunchETH`/`relaunchAsset[a]` instead (never lost, never retried automatically into the guild).

`_routePerpFee` (line 1160) mirrors this via `FeeRouteLib.routePerp` (FeeRouteLib.sol:79-103) — same `_fundGuild` call for the 30% guild share (line 97).

**Per-asset claimable path.** ETH: `receive()` bumps `accPerShare` → `pending(tokenId)` (line 258) → `claim`/`claimMany` pay wei. ERC20: `fundToken` bumps `accPerShareOf[asset]` → `pendingToken(tokenId,asset)` (line 295) → `claimTokens` pays that ERC20 (or banks to `owedAsset` on failure, withdrawable via `withdrawOwedToken`).

**DENOMINATION: quote-agnostic — CauldronHook.sol:1423 (`_feeAsset` set from the pool's live quote side, carried through `_routeEthFee`/`FeeRouteLib.routeSplit`/`_fundGuild` unchanged) into MiFrensDividend's matching accumulator.**

## Open deltas

- **F4 naming trap.** `enchantFee` reads as though it should be priced/paid in a basket quote asset given the file's heavy multi-quote framing, but it is priced in `floorPerFren()` (iteration-token units via `genesisReserveOutstanding`) and paid in `currentToken()` — a third, unrelated asset axis from both ETH and the `assets[]` basket. Not a bug (both sides are internally consistent — `floorPerFren` and `currentToken` are always the same generation's reserve/token pair), but the DENOMINATION line for F4 cannot be answered with the file's own "ETH-only / quote-agnostic" vocabulary without qualification. Flagged, not fixed, per instructions.
- **Asymmetric dust handling.** ETH's `receive()` tracks `residual` (MiFrensDividend.sol:76, 247) so floor-division dust is never dropped; `fundToken`'s ERC20 accumulator (line 287) has no equivalent `residual` — each `(amount*ACC)/activeShares` truncation is simply lost (stays undistributed in the contract's ERC20 balance, uncredited to any accumulator or `owedAsset`, permanently — bounded by `activeShares` wei-equivalent per deposit, not swept anywhere). Flagged, not fixed.
- **`activeShares==0` asymmetry.** ETH sweeps to `treasury` when nobody is enchanted (line 238-243); `fundToken` instead reverts (`NotEnchanted()`, line 280), leaving the fee with the caller (`FeeRouteLib`/hook then books it to the relaunch reserve as `leftover`, CauldronHook.sol:1317-1319) rather than reaching `treasury` at all. Both are total (nothing lost), but they resolve to different destinations. Flagged, not fixed.

## Denomination answers

**1. New asset added mid-life — does it accrue correctly, and can a first deposit be lost/misrouted?** No loss, and it *is* credited to the correct share base. `fundToken` (MiFrensDividend.sol:273-289) requires `activeShares != 0` (line 280) — it cannot be the very first deposit into an empty room. On first-ever funding of `asset`, `accPerShareOf[asset]` starts at 0 and is bumped by `(amount*ACC)/activeShares` (line 287) using the CURRENT `activeShares` — i.e. exactly the holders active at that moment. Every already-active token's `debtOfAsset[tokenId][asset]` mapping default is 0 (never written before), and per the design note (lines 212-214) a 0 marker correctly means "entitled from this asset's inception" for a holder who was already enchanted when the asset first funded — `pendingToken` (line 295) immediately reflects their pro-rata share. A holder who casts *after* the first deposit gets `debtOfAsset[tokenId][a]=accPerShareOf[a]` set at cast time (lines 427-436) — no backpay, no double-count. No sweep-to-treasury or wrong-share-base path exists for ERC20 (that behavior is ETH-only, F2).

**3. Payout sites — call{value} vs ERC20 transfer; any cross-denomination mismatch?** Two fully separate rails, never crossed inside this file: native ETH pays via `.call{value:amount}("")` at `withdrawOwed` (line 523), `_claim` (line 538), and the basket sweep in `receive()` (line 240); ERC20 pays via `_tryPush`'s `transfer` call at `claimTokens` (line 325) and `withdrawOwedToken` (line 340), and pulls via `_pull`'s `transferFrom` at `fundToken` (line 286) and `_collectEnchantFee` (line 455). No owed balance in this file accrues in one denomination and pays in another. The bug class named in the prompt (accrue-in-fee-asset, pay-native-wei) exists in `CauldronHook.sol` for `proposerOwed`/`claimProposerFees` (lines 1222, 1980-1986) but is already fixed there: `proposerOwed` is credited ONLY when `_feeAsset==address(0)` (line 1222, marked "NATIVE ONLY (red-team B-06 — High)" in-code), matching `claimProposerFees`'s native-only payout (line 1984). Re-verified, not re-flagged.

## Denomination table

| Asset class | Accrual path | Claim path | Verdict |
|---|---|---|---|
| Native ETH | `receive()` MiFrensDividend.sol:235-249, `accPerShare`/`residual` | `claim`/`claimMany`/`withdrawOwed`, `.call{value:}` (lines 502-527) | Total; own dust-carry residual |
| 18-decimal ERC20 (e.g. xNVDA-style) | `fundToken` :273-289, `accPerShareOf[asset]`, `ACC=1e18` is a fixed precision constant independent of asset decimals | `claimTokens`/`withdrawOwedToken`, ERC20 `transfer` (lines 307-343) | Total for credited funds; no dust residual (see Open deltas) |
| 6-decimal ERC20 (e.g. USDG) | Same code path as above — arithmetic is decimal-agnostic (raw base units in, `ACC` scaling only affects internal precision, not asset semantics) | Same as above | Same as 18-decimal row; verified no hardcoded 1e18-input assumption anywhere in `fundToken`/`pendingToken`/`claimTokens` |
