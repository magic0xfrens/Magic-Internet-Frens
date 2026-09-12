# V4 — token / NFT surface, verification pass

Tree: `/tmp/blind-final-h4/contracts/solidity`. All runs:
`FOUNDRY_PROFILE=cauldron forge test --skip DeployPermit2 --match-path 'test/attacks/X4*' -vv`.

Baseline: `3 tests passed, 0 failed` (X4a 2, X4b 1). Neither PoC file contains a
`return;` (`grep -n "return;" test/attacks/X4*.t.sol` → no hits), so no assertion
can be skipped; every final assertion block is reached.

---

## X4a — legacy buffer is written in wei and spent in the quote token
### Verdict: **CONFIRMED — Critical** (conditional on an ERC20-quoted live generation, a configuration the code explicitly implements)

**-vv evidence (unmodified tree)**

```
Ran 2 tests for test/attacks/X4a_LegacyBufferDenomination.t.sol
[PASS] test_dust_royalty_permanently_bricks_the_floor_buyback() (gas: 225831)
  brick: attacker spend (wei): 20000000000000000
  brick: buffer stuck at: 20000000000000000
[PASS] test_royalty_eth_is_spent_as_quote_token_and_stranded() (gas: 227486427)
  control: wei spent on a native generation: 1000000000000000000
  attack:  buffer after a 1 ETH royalty (USDG gen): 1000000000000000000
  attack:  RAW USDG units paid to the pool: 1000000000000000000
  attack:  hook ETH now tracked by no counter: 1000000000000000000
Suite result: ok. 2 passed; 0 failed
```

**Non-vacuity.** One-line mutation in `CauldronHook.legacyBuyStep`, inserted at
:1065 immediately after the `OnlySelf` check — the guard the library's own
doc-comment claims already exists:

```solidity
if (Currency.unwrap(key.currency0) != address(0)) return; // MUTATION
```

Result — both tests flip:

```
[FAIL: first buyback attempt reverts] test_dust_royalty_permanently_bricks_the_floor_buyback()
[FAIL: hook paid buffer-many RAW USDG units: 0 != 1000000000000000000] test_royalty_eth_is_spent_as_quote_token_and_stranded()
Suite result: FAILED. 0 passed; 2 failed
```

Mutation reverted from backup; `diff` clean (`RESTORED_CLEAN`).

**The three writers, quoted.** Only five sites touch `legacyBuffer`
(`grep -rn "legacyBuffer" --include=*.sol`, excluding lib/out/test): :1065 read,
:1067 `= 0`, :1080 `+= amt - spent`, plus the three credits:

- `CauldronHook.sol:1318` — matches the live quote:
  `if (_feeAsset == Currency.unwrap(_liveKey.currency0) && legacyRegistry != address(0) && legacyBps > 0)` → `legacyBuffer += fromFloor + fromRelaunch;` (:1325)
- `CauldronHook.sol:1340` — native regardless of the live quote:
  `if (_feeAsset == address(0) && legacyRegistry != address(0)) legacyBuffer += wantFloor;`
- `CauldronHook.sol:1096-1098` — native, ungated, permissionless:
  ```solidity
  function fundLegacyBuffer() external payable {
      legacyBuffer += msg.value;
  }
  ```
  No `msg.sender` check, no quote check, no cap. `RoyaltyRouter.receive`
  (`cauldron/RoyaltyRouter.sol:32-34`) forwards every marketplace royalty into it:
  `if (msg.value > 0) ILegacyBuffer(hook).fundLegacyBuffer{value: msg.value}();`

**The spender, quoted.** `LegacyBuyLib.buyStep` (`cauldron/LegacyBuyLib.sol:87-94`)
branches on the pool's currency0 and pays `spent` — which is `amt = legacyBuffer`
— in whatever that token is:

```solidity
address q = Currency.unwrap(key.currency0);
if (q == address(0)) {
    poolManager.settle{value: spent}();
} else {
    poolManager.sync(key.currency0);
    IERC20(q).transfer(address(poolManager), spent);
    poolManager.settle();
}
```

**Counter-arguments tried, all failed.**

1. *"A gate stops the buyback on an ERC20 quote."* `_maybeLegacyBuyback`
   (CauldronHook.sol:1015-1032) has exactly four gates and **none** of them is
   "currency0 is native":
   ```solidity
   if (legacyRegistry == address(0) || legacyBuffer < legacyThreshold) return;
   if (!quoteIsCurrency0[id]) return;                                  // layout, not denomination
   if (Currency.unwrap(live.currency1) == address(0)) return;          // currency1, "not wired yet"
   if (PoolId.unwrap(id) != PoolId.unwrap(live.toId())) return;
   ```
   Its comment still asserts "the native settle would revert against an ERC20
   quote anyway" (:1020) and the library header still says "ETH-QUOTE ONLY …
   The caller gates on that" (LegacyBuyLib.sol:41-44). Both are stale prose
   describing a gate that was never added when the settle path was generalised
   (rule 6: comments are not evidence). The mutation above is exactly that
   missing gate, and adding it fixes the finding — which proves it is absent.

2. *"An ERC20-quoted live generation is not a real configuration."* It is the
   configuration the whole ERC20 branch exists for. `_routeFee` at :1318 reads
   `Currency.unwrap(_liveKey.currency0)` as the fee asset to match, `_creditReserve`
   books non-native fees to `relaunchAsset[]` (:1217), `releaseRelaunchAsset` (:1679)
   exists solely so such a generation's fees have an exit, and `RedemptionExt.sol:505`
   flips it live: `generationQuote[gen] = toQuote;`.

3. *"A role can reset the buffer."* No. The grep is exhaustive: there is no
   setter, no admin write, no zeroing path outside `legacyBuyStep` itself. The
   hook's only recovery function is `sweepLegacyReserve(address token, address to)`
   (:1112), which moves `legacyOwedToReserve` **tokens** — it does not touch
   `legacyBuffer` and cannot move the stranded ETH.

4. *"The brick self-heals as fees accrue."* The PoC tests this directly: after
   the first revert it mints `realisticReserve * 1000` (10,000,000 USDG) and
   retries; `assertTrue(second, ...)` passes. 0.02 ETH = 2e16 raw units; on a
   6-decimal quote that is 20 billion USDG of accrued fees. Unreachable.

5. *"The failure is loud / it breaks the swap, so it gets noticed."* The
   opposite, which is what makes it permanent: the buy is fired by
   `address(this).call{gas: gl - LEGACY_GAS_RESERVE}(...)` at :1035-1037 with the
   return value **unread**. Every user swap succeeds; the floor buyback is simply
   dead and silent.

6. *"The money lost is protocol-owned, so it's not a user loss."* Partly, and it
   does not reduce the severity. In the non-bricking branch the buy drains
   `relaunchAsset[q]` — the reserve `releaseRelaunchAsset` hands to the registry
   to back the **next relaunch and the legacy entitlements crystallised at death**,
   i.e. holder-facing backing, not surplus. And the donated ETH survives under no
   counter at all: the PoC asserts `hookEthAfter == donation` while
   `relaunchETH() == 0` and `legacyBuffer == 0`, and the hook has no ETH sweep —
   which also breaks the stated solvency invariant
   `balance >= relaunchETH + legacyBuffer` in the *other* direction (excess ETH
   nobody can claim).

7. *"There is a slippage bound somewhere."* There is not.
   `LegacyBuyLib.MIN_SQRT_LIMIT = 4295128740` is the absolute floor tick, i.e. no
   price limit, and `amountSpecified: -int256(amt)` spends the whole buffer in one
   exact-input swap. The second hunter's "no slippage bound, whole reserve in one
   swap" is the same root cause, not a separate issue.

**Severity call — Critical, not High.** Against the brief's bar ("permissionless
loss or lock of funds or permanent brick of a core promise at any cost"): the
brick is **permanent** (no reset path exists at any privilege level, and the
threshold it pins is beyond any plausible fee accrual), **permissionless**
(`fundLegacyBuffer` is `external payable`, unauthenticated), and **cheap**
(0.02 ETH measured; any marketplace royalty does it by accident). It kills the
collection floor buyback — a core promise — outright. The other hunter's High
rating measured only the *drain* branch (0.05 ETH → 5,000 USDG reserve in one
swap), which is the softer of the two outcomes; the brick branch is strictly
worse and is what settles the rating. The one honest qualifier is that it needs
the live generation to be ERC20-quoted, which is a governance-reached state
rather than the day-one default — so: Critical the moment a quote rotation lands,
and a hard blocker on shipping that rotation.

*Adjacent, same root, not separately rated:* `IERC20(q).transfer(...)` in
`buyStep` is raw, with no return-value check. A quote token that returns `false`
instead of reverting would let `settle()` credit nothing, leaving currency0's
delta open — and unlike the revert path, that failure is **not** contained by the
result-ignored self-call's revert, so it would close the unlock with
`CurrencyNotSettled()` and take the user's parent swap down with it.

---

## X4b — `_churn` confiscates the unconsumed quote
### Verdict: **CONFIRMED — Medium**

**-vv evidence**

```
[PASS] test_playChurn_never_refunds_the_unconsumed_quote() (gas: 5672267)
  play()      refunded: 400000000000000000
  playChurn() refunded: 0
  playChurn() stranded (wei): 400000000000000000
  playChurn() stranded (raw USDG): 400000000
Suite result: ok. 1 passed; 0 failed
```

**The line.** `cauldron/CauldronGachaRouter.sol:466-478` — the buy leg settles
only what the pool took, then discards the difference instead of debiting it:

```solidity
uint256 inE = uint256(uint128(-delta.amount0()));
...
_settle(eth, inE, isNative);
playWei += inE;
tokBal += outG;
ethBal = 0;            // :478  — should be `ethBal -= inE;`
```

`_churn` returns `abi.encode(playWei, ethBal)` (:498). The sell leg is guarded by
`if (i + 1 < loops && tokBal > 0)`, so on the final iteration nothing restores
`ethBal` — the refund is structurally 0 whenever the last buy underfills.

**Non-vacuity.** One-line mutation at :478, `ethBal = 0;` → `ethBal -= inE;`:

```
[FAIL: playChurn refunds nothing: 400000000000000000 != 0] test_playChurn_never_refunds_the_unconsumed_quote()
Suite result: FAILED. 0 passed; 1 failed
```

Reverted; `diff` clean (`RESTORED_CLEAN`).

**Counter-arguments tried.**

1. *"The rig is stacked."* No — it is differential. `play()` and `playChurn()` run
   against the **same** mock at the **same** 60% fill (`pm.setFill(6_000)`), and
   `play()` refunds 0.4 ether while `playChurn()` refunds 0. The asymmetry is
   isolated to `_churn`, which is the claim.
2. *"A price limit makes the partial fill unreachable."* `_limit` (:501-503)
   returns `4295128740` / `1461446703485210103287273052203988822378723970341` —
   the extreme ticks, i.e. no bound. So a partial fill needs liquidity exhaustion
   rather than a binding limit: reachable on a thin or freshly launched
   generation pool with a large churn size, but not on a deep book. This is what
   caps the finding at Medium — the precondition is real but not attacker-chosen,
   and the size is chosen by the victim.
3. *"The owner can give it back."* Only on a native quote. `rescueETH(address,uint256)`
   (:547) is `onlyOwner` and native-only; the PoC probes for a token twin and
   asserts its absence (`assertFalse(tokenRescueExists, ...)`, passing). On an
   ERC20-quoted generation the stranded input has **no** exit from the router at
   any privilege level. Owner-only recovery is not user recovery either way.

Medium stands: bounded to the caller's own unfilled input, no attacker profit,
but a real and in the ERC20 case unrecoverable user loss.

---

## X4c — `_fundGuild` treats a codeless recipient as success
### Verdict: **CONFIRMED — Low (hygiene)**

`cauldron/FeeRouteLib.sol:128-135`, quoted in full:

```solidity
function _fundGuild(address asset, address guild, uint256 amount) private returns (bool ok) {
    if (asset == address(0)) { (ok, ) = guild.call{value: amount}(""); return ok; }
    (bool approved, ) = asset.call(abi.encodeWithSignature("approve(address,uint256)", guild, amount));
    if (!approved) return false;
    (ok, ) = guild.call(abi.encodeWithSignature("fundToken(address,uint256)", asset, amount));
    if (!ok) asset.call(abi.encodeWithSignature("approve(address,uint256)", guild, uint256(0)));
}
```

Neither branch checks `extcodesize` and neither decodes returndata. The native
branch is benign — a `call{value:}` to a codeless address genuinely moves the ETH.
The ERC20 branch is not: against a codeless `guild`, the `fundToken` call returns
`ok = true` with empty returndata, so `routeFee` emits `GuildFunded(guild, toGuild)`
(:64, :97) and books the share as delivered while `MiFrensDividend.fundToken` — a
**pull** (`_pull(asset, msg.sender, amount)`) — never ran. The tokens stay on the
hook with a live allowance and no holder credit, and the allowance-clearing line
is skipped because `ok` was true.

Reachability: needs `guild` set to a codeless address, i.e. a deployment or
governance misconfiguration, not a permissionless action. No PoC written (the
brief scoped this to a read-and-rule). Low is correct.

---

## X4d — dividend basket cap 3, no removal
### Verdict: **NOT VERIFIED** (refuted; no PoC written — the gate refutes it on reading)

The finding claims "a griefable or dead-end cap". Both halves fail.

**Not griefable.** `MiFrensDividend.fundToken` is funder-gated on its first line,
before the cap is ever consulted:

```solidity
function fundToken(address asset, uint256 amount) external {
    if (msg.sender != funder) revert NotOwner();          // :278
    if (asset == address(0) || amount == 0) revert NotShare();
    if (activeShares == 0) revert NotEnchanted();
    if (!knownAsset[asset]) {
        if (assets.length >= MAX_ASSETS) revert NotShare();  // :282, MAX_ASSETS = 3 at :124
        knownAsset[asset] = true;
        assets.push(asset);
    }
```

`funder` is the hook alone (`:135` "The only address allowed to fund the basket —
the hook", wired one-time by `treasury` at `:196`). A stranger cannot append a
slot, so nobody outside the protocol can fill the cap, inflate the per-transfer
settle loop, or reach the cap at all. The contract's own note at :274-276 states
the gate is there for exactly this reason.

**Not a dead end that loses anything.** If a fourth distinct quote asset is ever
routed, `fundToken` reverts `NotShare()` — and `FeeRouteLib._fundGuild` is a
low-level call whose failure is swallowed and returned as `false` (:132, and the
:123-125 note: "`fundToken` legitimately reverts when … the basket is full — the
low-level call swallows that and reports false, so the caller buffers the share
to the relaunch reserve rather than bricking the swap"). The guild share then
lands in `relaunchAsset[]` (CauldronHook.sol:1217, :1253) and exits via
`releaseRelaunchAsset` (:1679). The swap does not brick and no value is
destroyed; the fourth asset's holders simply do not receive that dividend leg.
The absence of `removeAsset` is documented as deliberate at :206-227.

Residual, hygiene only: the comment at `MiFrensDividend.sol:480` says "why
MAX_ASSETS is 4" while the constant at :124 is `3`. Stale prose, no behavioural
effect (rule 6).

---

## Tally
- Confirmed: 3 (X4a Critical, X4b Medium, X4c Low)
- Discarded: 1 (X4d)
- Source tree left byte-identical: both mutations restored from backup, `diff` clean.
