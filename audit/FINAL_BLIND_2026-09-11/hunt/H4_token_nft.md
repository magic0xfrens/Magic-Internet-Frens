# H4 — Token / NFT economy (blind hunt)

Tree: `/tmp/blind-final-h4/contracts/solidity`. PoCs: `test/attacks/X4*.t.sol`, run with
`FOUNDRY_PROFILE=cauldron forge test --match-path 'test/attacks/X4*' --skip DeployPermit2 -vv`.
3/3 pass, no fork needed.

## 1. Model from code

**Assets in.** Swap fees are taken on the quote side inside the hook's swap callbacks
(`_takeEthFee`, CauldronHook.sol:1458-1460): `_feeAsset` (transient, :697) is set to the
quote currency and `poolManager.take` credits the hook. `_routeEthFee` (:1220) splits
guild → floor → relaunch and carves `legacyBps` into `legacyBuffer`; `_routePerpFee`
(:1196) splits 30/70 guild/stakers. Both hand the split to `FeeRouteLib` by delegatecall,
which sends native (`call{value:}`) or, for an ERC20, `approve` + a pull, and *never
reverts* — undelivered value is returned as `leftover` and booked by `_creditReserve`
(:1214-1218) into `relaunchETH` or `relaunchAsset[asset]`.

Two other inflows: `CauldronHook.fundLegacyBuffer()` (:1096, **ungated, payable**), the sole
exit of `RoyaltyRouter.receive` (RoyaltyRouter.sol:33), and `MiFrensDividend.receive` /
`fundToken` (funder-only, :271).

**Assets out.** `legacyBuyStep` (:1063, self-only) spends the whole `legacyBuffer` through
`LegacyBuyLib.buyStep`, which settles native **or** ERC20 depending on `key.currency0`
(LegacyBuyLib.sol:87-94); the bought token is parked in `legacyOwedToReserve` and swept by
the registry into `CollectionLedger.credit`. Redemptions pay `entitledTokens[gen]/outstanding`
(CollectionLedger.sol:120). Dividends pay per-share ETH (`accPerShare`) and per-asset
baskets (`accPerShareOf`, cap `MAX_ASSETS = 3`, no removal).

**Gacha.** `CauldronGachaRouter` pulls the quote (`_pullQuote` :271, native XOR ERC20),
swaps under its own `unlock`, then calls `hook.commitCrystals`/`resolveTickets`. Odds come
from the router-supplied `playWei` converted by `_playInCurveUnits` (:136); the roll is
`keccak256(blockhash(commitBlock), player, batchIdx, i) % 10_000` (CauldronHook.sol:2319).

**Cross-subsystem.** One number, `legacyBuffer`, is written by the fee path, by the royalty
path and by anyone, and is spent in whatever the *live pool* is quoted in. That coupling is
finding X4a.

## 2. Findings

```
id: X4a   severity: Critical   confidence: VERIFIED
subsystem: legacy floor buyback / royalty routing
CauldronHook.sol:1096-1097:
    function fundLegacyBuffer() external payable {
        legacyBuffer += msg.value;
CauldronHook.sol:1340:
        if (_feeAsset == address(0) && legacyRegistry != address(0)) legacyBuffer += wantFloor;
CauldronHook.sol:1065-1067 / 1075:
        uint256 amt = legacyBuffer;
        if (amt < legacyThreshold) return;
        legacyBuffer = 0;
        (uint256 spent, uint256 got) = LegacyBuyLib.buyStep(poolManager, key, amt);
LegacyBuyLib.sol:87-94:
        address q = Currency.unwrap(key.currency0);
        if (q == address(0)) {
            poolManager.settle{value: spent}();
        } else {
            poolManager.sync(key.currency0);
            IERC20(q).transfer(address(poolManager), spent);
title: On a non-native generation anyone can pay native wei into `legacyBuffer`, a counter
       that is spent as RAW UNITS of the live ERC20 quote — permanently bricking the
       collection floor buyback for ~0.02 ETH, or draining the hook's quote-token reserve
       and stranding the ETH under no counter.
precondition: the live generation's quote is an allowlisted ERC20. Fully supported and
       advertised: `hook.setLiveKey` accepts a non-native key (CauldronRegistry.sol:874
       "hook.setLiveKey refused any non-native key … ALL FOUR ARE NOW FIXED"), the registry
       pushes it at CauldronRegistry.sol:1748, and `RedemptionExt` rotates a LIVE generation's
       quote at RedemptionExt.sol:505. No role needed; `fundLegacyBuffer` is ungated.
       Three writers disagree with the spender: :1317 books the buffer in the LIVE QUOTE,
       :1340 books it in NATIVE regardless of the live quote, and :1096 is native and
       unconditional. A rotation also leaves sub-threshold native residue in the same slot.
sequence:
  1. generation rotates (or launches) onto a 6-decimal quote; hook holds e.g. 10,000e6 of it
     as accrued fees booked to `relaunchAsset[q]`.
  2. attacker (or any marketplace paying a royalty through RoyaltyRouter):
     `hook.fundLegacyBuffer{value: 0.02 ether}()`  → `legacyBuffer = 2e16`.
  3. next swap fires `_maybeLegacyBuyback` → `legacyBuyStep` → `IERC20(q).transfer(pm, 2e16)`
     reverts (2e16 >> 1e10 balance). The self-call's result is IGNORED (CauldronHook.sol:1035),
     so the user's swap survives and `legacyBuffer = 0` is rolled back.
  4. every later attempt reverts on the same `amt`. Confirmed still bricked after 10,000,000
     more USDG of fee accrual.
  5. variant: if the hook DOES hold `legacyBuffer`-many raw units, the buy succeeds and pays
     them out of the relaunch reserve, while the donated ETH stays in the hook with
     `legacyBuffer = 0` and `relaunchETH = 0` — tracked by no counter, and the hook has no
     ETH sweep of any kind (only `sweepLegacyReserve(token,…)`, :1112).
attacker_cost: 0.02 ETH (= `legacyThreshold`) + ~40k gas. Not recoverable by the attacker
       either — this is pure vandalism, or an accident any royalty payment causes for free.
damage: permanent brick of the collection floor buyback (the mechanism the whole
       `MintCurvePolicy` floor argument rests on); or, in the variant, 1 ETH of royalties
       stranded per payment plus an equal RAW-UNIT drain of `relaunchAsset[q]`.
poc: test/attacks/X4a_LegacyBufferDenomination.t.sol   needs_fork: no
```

Measured (`-vv`): control native generation spends exactly the 1 ETH donated; ERC20
generation books `1e18` into the buffer and pays `1,000,000,000,000 USDG` (1e18 raw units of
a 6-decimal token) to the pool for a 1 ETH royalty, leaving 1 ETH in the hook under no
counter. Brick case: buffer pinned at `2e16` across two attempts.

```
id: X4b   severity: Medium   confidence: VERIFIED
subsystem: cauldron/CauldronGachaRouter.sol — `_churn`
CauldronGachaRouter.sol:472-478:
                uint256 inE = uint256(uint128(-delta.amount0()));
                uint256 outG = uint256(uint128(delta.amount1()));
                _settle(eth, inE, isNative);
                _take(tok, address(this), outG);
                playWei += inE;
                tokBal += outG;
                ethBal = 0;
CauldronGachaRouter.sol:498 / 390:
        return abi.encode(playWei, ethBal);
        if (ethLeftover > 0) _payQuote(q, msg.sender, ethLeftover);
title: `playChurn` zeroes the buy leg's input instead of debiting what the pool consumed, so
       any partially-filled leg confiscates the remainder into the router — with no recovery
       path at all when the quote is an ERC20.
precondition: a buy leg that consumes less than `ethBal` — the exact state LegacyBuyLib.sol:65-70
       says the code must handle ("If the price limit ever binds, the pool consumes LESS than
       `amt`"). `_limit(true)` is the extreme bound, so this needs a thin/exhausted book.
       `_play` handles the identical state correctly at :337 (`spend - ethConsumed` is refunded),
       which is what makes `_churn` an omission rather than a choice. Note the loop always
       ends on a buy (the sell is gated `i + 1 < loops`), so `ethBal` is 0 on every normal
       return — line 390 is dead code as written.
sequence:
  1. player: `playChurn{value: 1 ether}(0, loops, 0)` on a book that fills 60% of the leg.
  2. router settles 0.6 ETH, keeps 0.4 ETH, returns `ethLeftover = 0`; nothing is refunded.
  3. ERC20 quote: identical, 400e6 USDG left in the router. `rescueETH` (:547) is the router's
     ONLY recovery function and is native-only — there is no `rescueToken`.
attacker_cost: n/a (self-inflicted on the player; a griefer could arrange the thin book).
damage: the unconsumed share of the player's own input. Native: owner-recoverable.
        ERC20: permanently locked, no role can move it.
poc: test/attacks/X4b_ChurnConfiscatesRefund.t.sol   needs_fork: no
```

Measured (`-vv`): `play()` refunded `4e17`, `playChurn()` refunded `0` and stranded `4e17`
wei / `400e6` raw USDG on the identical pool; the probe call to `rescueToken(...)` reverts.

```
id: X4c   severity: Low   confidence: DERIVED
subsystem: cauldron/FeeRouteLib.sol
FeeRouteLib.sol:128-135:
    function _fundGuild(address asset, address guild, uint256 amount) private returns (bool ok) {
        if (asset == address(0)) { (ok, ) = guild.call{value: amount}(""); return ok; }
        (bool approved, ) = asset.call(abi.encodeWithSignature("approve(address,uint256)", guild, amount));
        if (!approved) return false;
        (ok, ) = guild.call(abi.encodeWithSignature("fundToken(address,uint256)", asset, amount));
FeeRouteLib.sol:105-110 (`_move`) and :137-151 (`_deliver`) have the same shape.
title: A low-level call to a CODELESS recipient returns success, so an ERC20 fee is marked
       delivered (and `GuildFunded` is emitted, :64) while the tokens never move and a
       standing allowance is left behind.
precondition: `guild` / `vault` / `engine` is an EOA or a contract that has selfdestructed.
       `setGuild`/`setVault` do no `code.length` check. Config error, not an attack — but the
       failure is silent and the value lands under no counter (it is excluded from `leftover`,
       so `_creditReserve` never books it and `releaseRelaunchAsset` can never release it).
sequence: 1. guild mis-set to an EOA. 2. any swap on an ERC20-quoted pool. 3. the guild share
       stays on the hook, uncounted, with `allowance[hook][EOA] = share`.
attacker_cost: none (requires the owner/registry to mis-wire).   damage: silent permanent
       strand of every guild leg, plus a live allowance to a stranger.
poc: none (covered by inspection; would need a deliberately mis-wired deployment)   needs_fork: no
```

```
id: X4d   severity: Medium   confidence: DERIVED
subsystem: cauldron/MiFrensDividend.sol
MiFrensDividend.sol:124 / 281-283:
    uint256 internal constant MAX_ASSETS = 3;
        if (!knownAsset[asset]) {
            if (assets.length >= MAX_ASSETS) revert NotShare();
MiFrensDividend.sol:480 (comment): "…and why MAX_ASSETS is 4"
title: The dividend basket is capped at three assets with no removal path anywhere in the
       file, so from the fourth distinct quote onward the OG holders' guild share of every
       fee is permanently diverted to the relaunch reserve.
precondition: four distinct quote assets over the protocol's life (native + three ERC20s, or
       four ERC20s). `rotateSlice` makes each rotation add one. `assets` has no `pop`, no
       `delete`, and `funder` is write-once (:202).
sequence: 1. generations rotate through quotes A, B, C. 2. generation rotates to D.
       3. `FeeRouteLib._fundGuild` → `fundToken(D, …)` reverts `NotShare` → caught → `leftover`
       → `_creditReserve` → `relaunchAsset[D]`. The guild dividend for quote D never pays,
       forever, and no admin call can prune the basket.
attacker_cost: none; reached by normal protocol operation.
damage: `guildBps` (1%) of all fee volume on every generation after the third rotation is
       permanently redirected from OG holders to the relaunch reserve.
poc: none (state is many rotations deep; the cap and the missing removal path are mechanical)
needs_fork: no
```

## 3. Refutations

- **Gacha odds/roll unit mismatch.** `roll = keccak256(...) % 10_000` (CauldronHook.sol:2319) is
  compared against `b.oddsBps`, produced by `oddsForPlay` and clamped to `maxOddsBps` ≤
  `ODDS_HARD_CAP_BPS = 9_500` (:436, :2145, :2150). The `uint16(odds)` cast at :2255 cannot
  truncate (9500 < 65535). Both sides are bps out of 10,000. Held. I also chased the
  `openReady` path (:345-367), which deliberately skips `_playInCurveUnits` because
  `costOfNextCrystals` is already in curve units — that is internally consistent.
- **Seed grinding.** `_resolveTickets` refuses to resolve a batch committed this block
  (:2296) and, on an expired (>256 block) seed, re-anchors `commitBlock` to the present
  (:2306-2308) instead of substituting a deterministic fallback, so a player who lets a batch
  age cannot read their roll in advance. Held.
- **`routePerp` burning ETH to `address(0)`.** `routePerp` has no `engine != address(0)` guard
  (FeeRouteLib.sol:100) where `routeSplit` has one for the guild (:64), so a zero engine with a
  native fee would `call{value:}` `address(0)` and succeed. Unreachable: the only caller gates
  on `sender == perpEngine && perpEngine != address(0)` (CauldronHook.sol:1465). Refuted.
- **Surtax double-payment.** `if (guild == address(0) || FeeRouteLib.routeSplit(...) != 0)
  _routeEthFee(surtax);` (CauldronHook.sol:1473-1474) looks like a re-route of an already-paid
  amount, but `routeSplit` returns non-zero only when `_fundGuild` reported false, i.e. nothing
  moved. Refuted.
- **Gacha router value conservation in `_play`.** Traced both branches: native inflow
  `msg.value` + `take(eth)` vs outflow `settle{value: ethConsumed}` + `_payQuote(sellEthGross +
  spend - ethConsumed)` nets exactly zero; the ERC20 branch does too. `_pullQuote` (:271-279)
  makes native and ERC20 mutually exclusive. Held — the leak is only in `_churn` (X4b).
- **`unlockCallback` cross-entry.** `if (msg.sender != address(poolManager)) revert` (:399) plus
  v4's "unlock calls back on the caller" means only the router's own `unlock` can reach it.
  Refuted.
- **MintCurvePolicy dilutes the floor.** `priceAt(k) = base + spread*k*k/(k+knee)` (:99) is
  monotone **non-decreasing** in integer arithmetic (truncation can make it locally flat for
  small `k`, never decreasing), and `floorPerNFT = Σcost/n` falls only if `cost[n] <
  mean(cost[0..n-1])`, which a non-decreasing ladder cannot produce. The constructor's
  `spread == 0` rejection (:82) covers the one flat case. Refuted as a curve bug — but see Lead 3.

## 4. Leads (HYPOTHESIS)

1. **Banked credit cashed at max odds.** `_commitCrystals` spends the player's *entire*
   accumulated `nftCredit` at the odds of the *current* play (CauldronHook.sol:2255), and
   `_maybeGacha`'s self-call is gas-bounded and result-ignored (:963-967). Next step: drive a
   real hook + pool, make many small direct buys with `gasleft()` tuned just under
   `GACHA_GAS_MIN` so `nativeGachaStep` never fires, then one 0.5 ETH router `play` — assert
   every banked crystal resolves at `maxOddsBps` instead of the per-trade odds it was earned at.
2. **`_fundGuild` allowance residue.** The zero-approve at FeeRouteLib.sol:134 is itself a
   low-level call whose result is discarded; a token that reverts on `approve` while a non-zero
   allowance stands (USDT shape) leaves the guild approved for the failed amount. Next step:
   route a USDT-shaped fee to a guild whose `fundToken` reverts and read `allowance(hook, guild)`.
3. **Token-denominated floor vs credit-denominated ladder.** `MintCurvePolicy.sol:39` claims
   "`r` cancels. So does the token price" — but `CollectionLedger.entitledTokens` counts the
   *iteration token* while the ladder prices in credit, and the buyback converts at spot. On a
   rising token price a late mint adds fewer tokens than the running mean, so
   `floorPerNFT` (CollectionLedger.sol:94-98) can fall in token terms. Next step: a ledger-level
   PoC crediting `credit(gen, 100)` then `credit(gen, 1)` across two mints and asserting
   `floorPerNFT` strictly decreases — then decide whether the stated guarantee or the ledger's
   denomination is the thing to change.
