# 07 — Fees, end to end

Sources: `contracts/solidity/CauldronHook.sol`,
`contracts/solidity/cauldron/FeeRouteLib.sol`,
`contracts/solidity/cauldron/DefaultFeeRouter.sol`,
`contracts/solidity/cauldron/SurtaxLib.sol`,
`contracts/solidity/cauldron/LegacyBuyLib.sol`,
`contracts/solidity/cauldron/RoyaltyRouter.sol`.

Every mechanism below carries the source line it was read from. See `06-HOOK.md`
for *when* the fee is taken; this document covers *what happens to it afterwards*.

---

## 1. The one-page table

Every fee leg, the asset it is denominated in, the counter or recipient it lands
in, and how it is claimed.

| # | leg | taken from | asset | credited to (counter / recipient) | claim function | if the recipient is misconfigured |
|---:|---|---|---|---|---|---|
| 1 | **Base tax, buy leg** | the swapper's input, before the swap | the pool's quote currency (`CauldronHook.sol:1469`) | routed by legs 3-7 | — | — |
| 2 | **Base tax, sell leg** | the swapper's output, after the swap | same | routed by legs 3-7 | — | — |
| 3 | **Proposer slice** — `proposerBps` of the fee | off the top of the fee | **native wei only** (`CauldronHook.sol:1303`) | `proposerOwed[activeProposer]` (`:497`, `:1307`) | `claimProposerFees()` (`:2071`), pull, `nonReentrant` | non-native fee ⇒ the slice is **not carved at all**; it stays in `feeAmount` and ends in `relaunchAsset[]` |
| 4 | **Guild slice** — `guildBps` of the fee | after the proposer slice | fee asset | pushed to `guild` (`:469`) — native `.call{value:}` or ERC20 `approve` + `fundToken` (`FeeRouteLib.sol:129-133`) | `MiFrensDividend.claim` / `claimMany` / `claimTokens` | send fails, guild is `address(0)`, or **guild address has no code** ⇒ returned as `leftover` (`FeeRouteLib.sol:65`) and credited to the relaunch reserve |
| 5 | **Legacy-buyback carve** — `legacyBps` of the post-guild fee | taken from the floor share first, then the relaunch share (`:1369-1373`) | **must equal `_liveKey.currency0`** (`:1365`) | `legacyBuffer` (`:318`) + `legacyBufferAsset` (`:2470`) | spent by `legacyBuyStep` (`:1083`); the tokens bought are counted in `legacyOwedToReserve` (`:1119`) | asset mismatch ⇒ carve skipped, the share stays on the floor/relaunch route |
| 6 | **Floor share** — `floorBps` of the post-guild fee | after guild and carve | fee asset | `vault` (`:453`), a `CauldronVault` | `CauldronVault.redeem(tokenId)` | `vault == 0` **and** native ⇒ joins `legacyBuffer` (`:1390-1393`); `vault == 0` otherwise ⇒ folded into relaunch (`:1395`); `vault != 0` but fee is non-native ⇒ folded into relaunch (`:1396-1405`); `vault != 0`, native, send fails ⇒ `leftover` ⇒ relaunch |
| 7 | **Relaunch residual** | the remainder, by subtraction | fee asset | `relaunchETH` (`:286`) if native, else `relaunchAsset[asset]` (`:2452`) | `releaseRelaunchETH()` (`:1662`) / `releaseRelaunchAsset(asset)` (`:1690`) — **registry only** | send failure reverts `SendFailed` and the counter is restored by the revert |
| 8 | **Anti-sniper surtax** — 100% | on top of the base fee, same leg | fee asset | `guild` in full (`:1484`) | dividend claims, as leg 4 | guild unset **or** the guild send returns non-zero leftover ⇒ the whole surtax re-enters the ordinary fee route `_routeEthFee` (`:1485`) |
| 9 | **Perp-swap fee, guild part** — 30% (`3000` bps, `:1239`) | of the base fee when `sender == perpEngine` | fee asset | `guild` (`FeeRouteLib.sol:97`) | dividend claims | failure ⇒ `leftover` ⇒ relaunch reserve (`:1243`) |
| 10 | **Perp-swap fee, staker part** — 70% (remainder, `:1240`) | same | fee asset | the perp engine, via `creditPerpFee()` (buys) / `creditPerpFeeToken()` (sells) / `creditPerpFeeAsset(asset,amount)` (`:1245-1246`) | out of scope — see the perp doc | **codeless engine** ⇒ `_deliver` returns false **before any value leaves** (`FeeRouteLib.sol:162`) ⇒ `leftover` ⇒ relaunch reserve |
| 11 | **ERC-2981 royalties** | marketplace secondary sales | native wei | `legacyBuffer` via `fundLegacyBuffer()` (`:1129`), forwarded by `RoyaltyRouter.receive()` (`RoyaltyRouter.sol:32-34`) | — | `fundLegacyBuffer` **reverts `BadParam`** unless the live quote is native and the buffer is empty-or-native (`:1136-1137`); the router's forward is unguarded, so the whole `receive()` reverts |
| 12 | **Bought-back tokens** | the output of `legacyBuyStep` | the iteration token | `legacyOwedToReserve` (`:332`) | `sweepLegacyReserve(token, to)` (`:1154`) — **`legacyRegistry` only**; pulled by `RedemptionExt.materializeLegacyReserve()` (`cauldron/RedemptionExt.sol:147`) | the amount is clamped to the hook's live token balance (`:1158`), so the counter cannot outrun the balance |

**12 rows.**

---

## 2. Parameters

All bps values are basis points of `BPS = 10_000` (`CauldronHook.sol:149`).

| parameter | default | units | declared | ceiling | setter |
|---|---|---|---:|---|---|
| `defaultTaxBps` | 300 | bps of the quote leg | 234 | `MAX_TAX_BPS = 1_000` (153) | `setDefaultTaxBps` (1647) |
| `proposerBps` | 50 | bps **of the fee** | 491 | `MAX_PROPOSER_BPS = 500` (492) | `setProposerBps` (2063) |
| `guildBps` | 1500 | bps **of the fee** | 477 | 1500, hard-coded in the setter (2049) | `setGuildBps` (2048) |
| `floorBps` | 10_000 | bps **of the post-guild remainder** | 458 | `BPS` (2030) | `setFloorBps` (2029) |
| `legacyBps` | 0 | bps **of the post-guild fee** | 316 | `BPS` (1848) | `setLegacyBuyback` (1846) |
| `legacyThreshold` | `0.02 ether` | raw units of the buffer asset | 320 | — | `setLegacyBuyback` (1851) |
| perp guild split | 3000 | bps of the perp base fee | 1239 | not settable | — |
| `snipeMaxBps` | 9_600 | bps | 513 | `MAX_SNIPE_BPS = 9_900` (516) | `setSnipeParams` (1492) |
| `snipeWindowBlocks` | 30 | **blocks** | 507 | unbounded | `setSnipeParams` (1492) |
| combined base + surtax | — | bps | — | `MAX_TOTAL_FEE_BPS = 9_900` (523) | not settable |
| `SLIP_SQRT_BPS` | 9486 | bps of the **sqrt** price | `LegacyBuyLib.sol:47` | not settable | — |

**Unit trap.** `proposerBps`, `guildBps` and `legacyBps` are fractions **of the
fee**, not of the swap. `floorBps` is a fraction of what is left after the guild
slice. With defaults, a 3% swap fee splits as: 0.5% of the fee to the proposer, 15%
of the remainder to the guild, and 100% of what then remains to the floor —
i.e. roughly 0.015%, 0.45% and 2.5% of the *swap*, before the legacy carve.

---

## 3. How the base fee is routed — `_routeEthFee`

`CauldronHook.sol:1265-1409`, in order.

### Step 1 — the proposer slice (native only)

```
prop = (_feeAsset == address(0)) ? activeProposer : address(0);   // :1303
if (prop != 0 && proposerBps > 0) {
    wantProp = feeAmount * proposerBps / BPS;                     // :1305
    proposerOwed[prop] += wantProp;                               // :1307
    feeAmount -= wantProp;                                        // :1308
}
```

This is a **pull**, never a push. `activeProposer` is attacker-influenced — anyone
can author a winning proposal — so pushing here would put an untrusted external call
in the swap hot path (`:1268-1273`).

The native-only gate at `:1303` is a deliberate narrowing. `claimProposerFees`
(`:2071-2078`) pays with `call{value: amount}` — raw wei, unconditionally. Before the
gate, a fee collected in a 6- or 18-decimal ERC20 credited the same integer and the
claim paid it out as ether, draining the ether that backs `relaunchETH`
(`:1275-1294`). The skipped slice is not lost: it stays in `feeAmount` and reaches
`relaunchAsset[]` through `_creditReserve` (`:1296-1303`).

### Step 2 — the split

A pluggable `IFeeRouter` is consulted first, and its answer is used **only if the
three parts sum exactly to the fee**:

```
try fr.route(feeAmount, guild, vault, guildBps, floorBps) returns (g, f, r) {
    if (g + f + r == feeAmount) { ...; routed = true; }           // :1324-1325
} catch { /* fall through */ }                                     // :1326
```

The built-in split (`:1333-1336`), which is also what `DefaultFeeRouter`
implements (`DefaultFeeRouter.sol:26-29`):

```
wantGuild    = (guild != 0 && guildBps > 0) ? feeAmount * guildBps / BPS : 0;
rem          = feeAmount - wantGuild;
wantFloor    = floorBps > 0 ? rem * floorBps / BPS : 0;
wantRelaunch = rem - wantFloor;            // remainder — the parts sum exactly
```

Every bps division is floor division and every complement is taken by
**subtraction**, so the parts always sum to the input and the dust lands in the
relaunch reserve.

Note one difference between the two: `DefaultFeeRouter` requires `vault != 0` before
allocating a floor share (`DefaultFeeRouter.sol:28`); the hook's built-in branch does
not (`:1335`) and handles `vault == 0` later, in step 4.

### Step 3 — the legacy-buyback carve

```
if (_feeAsset == _liveKey.currency0                                // :1365
    && legacyRegistry != 0 && legacyBps > 0                        // :1366
    && (legacyBuffer == 0 || legacyBufferAsset == _feeAsset)) {    // :1367
    want         = (feeAmount - wantGuild) * legacyBps / BPS;      // :1368
    fromFloor    = min(want, wantFloor);   wantFloor    -= fromFloor;
    fromRelaunch = min(want - fromFloor, wantRelaunch);
    wantRelaunch -= fromRelaunch;
    legacyBufferAsset = _feeAsset;                                  // :1374
    legacyBuffer     += fromFloor + fromRelaunch;                   // :1375
}
```

The floor share is raided first, the relaunch share second. The third condition is
the denomination lock added by `f9c775f`: **one buffer never holds two
denominations.** A fee arriving in a sibling pool's older quote keeps its ordinary
route, where `_creditReserve` denominates it correctly (`:1362-1364`).

### Step 4 — delivering the floor share

```
toFloor = wantFloor;
if (wantFloor > 0) {
    if (vault == address(0)) {                                      // :1386
        toFloor = 0;
        if (_feeAsset == address(0) && legacyRegistry != 0
            && (legacyBuffer == 0 || legacyBufferAsset == address(0))) {
            legacyBufferAsset = address(0);
            legacyBuffer += wantFloor;                              // :1390-1393
        } else wantRelaunch += wantFloor;                           // :1395
    } else if (_feeAsset != address(0)) {                           // :1396
        toFloor = 0; wantRelaunch += wantFloor;                     // :1403-1404
    }
}
```

Two facts a reader needs:

- **Under the shipped configuration `vault` is always zero.** Both
  collection-deployment paths call `hook.setVault(address(0))`
  (`CauldronRegistry.sol:1171`, `:1195`). The floor share therefore becomes token
  **buy pressure** through the legacy buffer, not ETH in a vault. `CauldronVault`
  stays deployed as a supply oracle only (`cauldron/CauldronVault.sol:85-93`).
- **The floor vault can only ever receive native ETH.** `CauldronVault.floorPerNFT`
  counts `address(this).balance` (`CauldronVault.sol:80`), so an ERC20 floor share
  transferred into it would be unredeemable. It is folded into the per-asset
  reserve instead (`:1396-1405`).

### Step 5 — the sends, and the residual

```
_creditReserve(
    wantRelaunch + FeeRouteLib.routeSplit(_feeAsset, guild, vault, wantGuild, toFloor)
);                                                                  // :1407-1408
```

`routeSplit` returns the **leftover** from whatever it could not deliver
(`FeeRouteLib.sol:54`, `:65`, `:69`). Anything a recipient rejects therefore ends up
in the relaunch reserve. `_creditReserve` (`:1255`) is the single denomination
switch: `_creditFor` puts native into `relaunchETH` and everything else into
`relaunchAsset[a]` (`:1259-1263`).

---

## 4. How value actually leaves — `FeeRouteLib`

`cauldron/FeeRouteLib.sol` is a **linked library**: its functions are `external`, so
Solidity deploys it separately and reaches it by `delegatecall`. It runs in the
hook's context — the ether it sends is the hook's, the tokens it moves are the
hook's, and it holds no state of its own (`FeeRouteLib.sol:15-21`).

**Failure is never fatal.** Every send is reached from inside a swap. A recipient
that reverts must not take the trader's swap down with it, so these functions
**report** failure rather than throwing (`:23-28`).

### The four movers

| function | line | used for | native path | ERC20 path | codeless-recipient guard |
|---|---:|---|---|---|---|
| `_move` | 105 | the floor vault | `to.call{value:}("")` (106) | raw `transfer`, accepting empty **or** `true` returndata (107-110) | **none** |
| `_fundGuild` | 128 | the guild dividend | `guild.call{value:}("")` (129) | `approve` (130) then `guild.fundToken(asset, amount)` (133); approval zeroed on failure (145) | **yes — after the call** (142) |
| `_deliver` / `deliver` | 148 / 214 | the perp engine | `to.call{value:}(nativeSel)` (164 / 234) | `approve` (167 / 237) then `to.call(assetSel, asset, amount)` (169 / 241); approval zeroed on failure (172 / 244) | **yes — before anything moves** (162 / 232) |
| `send` | 184 | `releaseRelaunchAsset` | `to.call{value:}("")`, optionally gas-capped (190-191) | raw `transfer`, same acceptance rule (197-200) | none |

### The two codeless guards, and why they differ

Both were added today and both are **deliberate semantic narrowings**.

**`_fundGuild` — guard placed *after* the call (`:142`).**

```
(ok, r) = guild.call(abi.encodeWithSignature("fundToken(address,uint256)", asset, amount));
...
if (ok && guild.code.length == 0) ok = false;                       // :142
```

Commit `02f4e8a`: a call to an address with no code always succeeds on the EVM. A
mistyped or not-yet-deployed `guild` therefore reported the OG holders' share as
*funded* when nothing had happened, so the slice was **written off instead of
reserved**. With the guard, `ok` is false, `routeSplit` returns the amount as
`leftover` (`:65`), and it is credited to the relaunch reserve. Placing the guard
after the call is safe here because the ERC20 path only ever `approve`d — no tokens
moved.

**`_deliver` / `deliver` — guard placed *before* anything moves (`:162`, `:232`).**

```
if (to.code.length == 0) return false;                              // :162
```

Commit `a3773fc`: the perp-engine delivery had the same false-success problem, but
on the native leg `to.call{value: amount}(selector)` to a codeless address **really
sends the ether**, and the engine has no way to send it back. The guard must
therefore come first, before any value leaves. The function returns false and the
amount is reserved instead (`:100-102`).

**`_move` has no guard, by construction.** A native `call{value:}` to a codeless
address does land the ether, and an ERC20 `transfer` to a codeless address is
handled by the token contract — in both cases the value genuinely arrives. There is
no false-success to guard against. The asymmetry with `_fundGuild` and `_deliver` is
real and is a consequence of those two expecting the recipient to *execute
something*.

### ERC20 return-value handling

`_move`, `send` and the pull in the dividend all accept a token that returns **no**
data or returns `true`, and treat a `false` return as failure
(`FeeRouteLib.sol:110`, `:200`). This is the standard non-compliant-token
accommodation. `sweepLegacyReserve` is the exception: it uses `IERC20.transfer`
directly and **does not check the return value** (`CauldronHook.sol:1160`), so a
token that returns `false` instead of reverting would still debit
`legacyOwedToReserve`.

---

## 5. The surtax route

`CauldronHook.sol:1479-1487`:

```
if (surtax > 0) {
    if (guild == address(0)
        || FeeRouteLib.routeSplit(_feeAsset, guild, address(0), surtax, 0) != 0) {
        _routeEthFee(surtax);            // no guild, or the guild rejected it
    }
}
```

The entire surtax goes to the genesis dividend — snipers pay the OG holders
(`:509-512`). `routeSplit` is called with `toFloor = 0`, so its leftover is either
`0` (delivered) or the whole `surtax` (rejected). There is no partial case and no
double-spend: if it was rejected, the value is still on the hook and is re-routed
through the ordinary fee path.

Surtax is computed as the difference between the clamped total and the base
(`:1459-1461`), so when `taxRate + snipeSurtaxBps` exceeds `MAX_TOTAL_FEE_BPS`
(9,900), it is the **surtax** that absorbs the clamp, not the base rate.

---

## 6. The perp-swap route

`_routePerpFee` (`CauldronHook.sol:1238-1248`) is reached only when
`sender == perpEngine` (`:1476`):

```
toGuild   = amount * 3000 / BPS;     // 30%   :1239
toStakers = amount - toGuild;        // 70%   :1240
_creditReserve(FeeRouteLib.routePerp(
    _feeAsset, guild, perpEngine, toGuild, toStakers,
    isBuy ? creditPerpFee.selector : creditPerpFeeToken.selector,   // :1245
    creditPerpFeeAsset.selector                                     // :1246
));
```

Side attribution: **buys credit the ETH/PLV side, sells credit the token side**
(`:76-78`). Non-native assets use a single pull entrypoint,
`creditPerpFeeAsset(address,uint256)` — the engine pulls from the hook, which
approved it first (`FeeRouteLib.sol:167-169`).

The 30/70 split is a hard-coded literal (`:1239`) with no setter. Neither leg's
failure can revert the swap; both fall through to `leftover` and the relaunch
reserve (`FeeRouteLib.sol:98`, `:101`).

The perp engine itself, and what it does with the 70%, is out of scope.

---

## 7. Royalties and `fundLegacyBuffer`

`RoyaltyRouter` (`cauldron/RoyaltyRouter.sol`) is the EIP-2981 receiver for a
creature collection. Its whole body is:

```
receive() external payable {
    if (msg.value > 0) ILegacyBuffer(hook).fundLegacyBuffer{value: msg.value}();
}                                                              // RoyaltyRouter.sol:32-34
```

`hook` is immutable (`:25`). The forward is **unguarded**.

`fundLegacyBuffer` (`CauldronHook.sol:1129-1140`) now enforces:

```
if (Currency.unwrap(_liveKey.currency0) != address(0)
    || (legacyBuffer != 0 && legacyBufferAsset != address(0))) revert BadParam();
legacyBufferAsset = address(0);
legacyBuffer += msg.value;
```

This is the `f9c775f` narrowing. Previously the function was permissionless and
untyped: anyone could donate ether into a buffer that `LegacyBuyLib.buyStep` then
spent as **raw units of the live pool's `currency0`**. On a 6-decimal stablecoin
quote, `0.02 ether` of donated wei meant 2e16 raw units — twenty billion tokens.
Where the hook held less, the buy reverted forever behind a result-ignored
self-call and the feature went silently dead with no reset path at any privilege
level; where it held more, the buy paid for the donation out of `relaunchAsset[q]`
without debiting that counter (`:2454-2469`).

**The consequence, stated plainly:** on a generation whose quote is an ERC20,
`fundLegacyBuffer` reverts, and therefore **any ether sent to `RoyaltyRouter`
reverts**. The router holds nothing and has no recovery path.

---

## 8. Where the money sits, and what reconciles it

| counter | denomination | reconciled against a balance? |
|---|---|---|
| `relaunchETH` (`:286`) | **strictly native wei** | no — paid out of the hook's undivided ether balance |
| `relaunchAsset[a]` (`:2452`) | base units of `a` | no — the send's boolean is required (`:1697`) but the amount is never clamped to the live balance |
| `proposerOwed[a]` (`:497`) | **native wei** | no — same ether balance |
| `legacyBuffer` (`:318`) | the asset named by `legacyBufferAsset` (`:2470`) | no — but the spend clamps itself to the free balance via the `encumbered` argument (`LegacyBuyLib.sol:86-88`) |
| `legacyOwedToReserve` (`:332`) | iteration-token units | **yes** — clamped to the live token balance on every sweep (`:1157-1159`) |

Three native counters (`relaunchETH`, `proposerOwed`, `legacyBuffer` when native) are
paid out of one undivided balance and none is compared against
`address(this).balance`. A shortfall in one shows up as a failed send in whichever
path runs first. That is the structural reason the proposer slice was narrowed to
native-only in step 1 — see `:1283-1289`.

`LegacyBuyLib.buyStep` is the one spender that defends this explicitly: it is passed
the matching reserve counter as `encumbered` and clamps its spend to
`balance - encumbered` (`LegacyBuyLib.sol:86-88`), so a buyback can never move
balance the reserve's own counter still claims.

Value the hook holds that **no counter tracks**: anything arriving through the bare
`receive()` (`:2472`).

---

## 9. Release paths

| function | caller | asset | line |
|---|---|---|---:|
| `releaseRelaunchETH()` | `registry` only | native wei, whole balance of the counter | 1662-1674 |
| `releaseRelaunchAsset(address)` | `registry` only | that asset, whole balance of the counter | 1690-1700 |
| `claimProposerFees()` | the proposer themselves | native wei | 2071-2078 |
| `sweepLegacyReserve(token, to)` | `legacyRegistry` only | the iteration token, clamped | 1154-1161 |

Both release paths zero the counter **before** the send (`:1668`, `:1696`) and
revert `SendFailed` if it does not land (`:1671`, `:1697`), so a failed release
restores the counter by reverting the whole call. `claimProposerFees` follows the
same shape (`:2074-2076`) and is additionally `nonReentrant`.

---

## Verification

- Documented against `git rev-parse --short HEAD` = **`20d6de2`**, reading each file
  from the committed tree (`git show 20d6de2:<path>`). At the time of writing the
  working tree had further uncommitted edits in `CauldronHook.sol`,
  `CauldronRegistry.sol`, `cauldron/CauldronGachaRouter.sol`,
  `cauldron/CauldronGovernor.sol`, `cauldron/PerpEngine.sol` and
  `cauldron/RedemptionExt.sol`. **Those are not reflected here**, and they shift line
  numbers. Re-check any citation against `20d6de2`, not against the working tree.

### Behaviour changes reflected here

- `f9c775f` — `fundLegacyBuffer` now reverts unless the live quote is native
  (`:1136-1137`); `legacyBufferAsset` added (`:2470`); the stale-asset self-heal at
  `:1028-1036`; `LegacyBuyLib.buyStep` gained the `encumbered` clamp
  (`LegacyBuyLib.sol:86-88`) and an ERC20 settle path (`:139-150`).
- `02f4e8a` — `_fundGuild` treats a codeless guild as a failure (`FeeRouteLib.sol:142`).
- `a3773fc` — `_deliver` / `deliver` reject a codeless target **before** any value
  leaves (`FeeRouteLib.sol:162`, `:232`).
- `69dc15d` — the surtax jitter no longer reads the live tick; the jitter now **adds**
  to the decay (`SurtaxLib.sol:97-104`).

### Documentation debt

1. **`CauldronHook.sol:1388`** — "Same native-only rule as the buyback carve above".
   It is not the same rule. The carve at `:1365` tests `_feeAsset` against
   `_liveKey.currency0`; the no-vault fold at `:1390` tests it against `address(0)`.
   The two differ the moment a generation is quoted in an ERC20.
2. **`cauldron/RoyaltyRouter.sol:20-21`** — "If the hook forward ever fails, the ETH
   stays here (recoverable by re-pointing), never lost mid-transfer." The forward at
   `:33` is an unguarded external call, so a reverting `fundLegacyBuffer` reverts the
   whole `receive()` and **nothing is retained** in the router. Since `f9c775f` made
   that revert reachable on any non-native generation, this comment is now actively
   misleading.
3. **`CauldronHook.sol:63-68`** — the `ILegacyNote` interface is documented as "the
   registry entry that records a legacy buyback". `noteLegacyBuy` is **never called**
   anywhere in the hook; the buyback accrues `legacyOwedToReserve` (`:1119`) for a
   later registry-pulled sweep instead. Verified by grep.
4. **`CauldronHook.sol:103-105`** — "the hook collects tiered fees via afterSwap
   return deltas". The buy leg is collected via a `BeforeSwapDelta` (`:1223`).
5. **`CauldronHook.sol:239-252`** — `treasury` is described as a dead slot; the
   constructor still writes it (`:566`). It is `internal`, so no getter advertises
   the non-existent treasury fee route.

### Not verified here

- What the perp engine does with the 70% staker share (out of scope).
- Whether any deployed `IFeeRouter` other than `DefaultFeeRouter` exists.
- Whether `nftContract` is wired on any live deployment — no contract in this tree
  implements `getHolderTaxRate`, so legs 1 and 2 are charged at `defaultTaxBps` (300
  bps) unless an out-of-tree contract is wired. See `06-HOOK.md` debt item 2.
