# V1 — core / pool verification (blind, 2026-09-11)

Tree verified: `/tmp/blind-final-h1/contracts/solidity`.
Command (both suites, one run):
`forge test --match-path 'test/attacks/X1*' --skip DeployPermit2 -vv`
Result: `3 tests passed, 0 failed` (2 in X1a, 1 in X1b).
`grep -n "return;"` over both PoC files: **zero hits** — no early-return vacuity is possible.

---

## X1a — `legacyBuffer` is a denomination-less balance — **CONFIRMED, UPGRADED to Critical**

### Verdict
Confirmed and upgraded: `legacyBuffer` is a single integer fed by *native-wei* sources and spent
as raw units of `_liveKey.currency0`, so on the protocol's own canonical configuration (a
6-decimal stable quote) a permissionless 0.02-ETH donation makes the hook spend its entire
quote-denominated relaunch reserve into a slippage-unbounded market buy. No role, no large spend.

### `-vv` evidence (verbatim)
```
[PASS] test_X1a_attack_erc20LivePool_spendsErc20ReserveForNativeDonation() (gas: 425422)
Logs:
  attack: wei donated             50000000000000000
  attack: raw quote units offered 50000000000000000
  attack: quote drained from hook 5000000000
  attack: hook eth unchanged      50000000000000000
  attack: buffer left over        49999995000000000

[PASS] test_X1a_control_nativeLivePool_settlesWei() (gas: 321668)
Logs:
  control: native settled (wei) 50000000000000000
  control: buffer after 0
```
The logs print *before* the assertions in both tests, so every assertion line executed.

### Non-vacuity (flip test)
Changed `assertEq(erc20Before - erc20After, reserve, ...)` → `reserve + 1`:
```
[FAIL: FLIPPED: 5000000000 != 5000000001] test_X1a_attack_erc20LivePool_... (gas: 460934)
```
Flipped as expected; file restored byte-for-byte (`grep -c FLIPPED` → 0).

### The mechanism, quoted
`CauldronHook.sol:1096-1098` — permissionless, payable, native:
```solidity
function fundLegacyBuffer() external payable {
    legacyBuffer += msg.value;
}
```
`CauldronHook.sol:1065-1073` — the same integer is handed to the library:
```solidity
uint256 amt = legacyBuffer;
if (amt < legacyThreshold) return;
legacyBuffer = 0;
...
(uint256 spent, uint256 got) = LegacyBuyLib.buyStep(poolManager, key, amt);
```
`cauldron/LegacyBuyLib.sol:55-62, 88-94` — `amt` is the *exact input* of the swap and is settled
in whatever `currency0` is, with **no price floor**:
```solidity
amountSpecified: -int256(amt),
sqrtPriceLimitX96: MIN_SQRT_LIMIT
...
address q = Currency.unwrap(key.currency0);
if (q == address(0)) { poolManager.settle{value: spent}(); }
else { poolManager.sync(key.currency0); IERC20(q).transfer(address(poolManager), spent); poolManager.settle(); }
```
The guarded carve the hunter contrasts it with, `CauldronHook.sol:1317-1318`, does match the quote:
```solidity
if (_feeAsset == Currency.unwrap(_liveKey.currency0)
    && legacyRegistry != address(0) && legacyBps > 0) {
```
…but the twin at `CauldronHook.sol:1340` books **native** wei with no live-key match at all:
```solidity
if (_feeAsset == address(0) && legacyRegistry != address(0)) legacyBuffer += wantFloor;
```
and `cauldron/RoyaltyRouter.sol:33` is a *designed, attacker-free* native feed into the same slot:
```solidity
if (msg.value > 0) ILegacyBuffer(hook).fundLegacyBuffer{value: msg.value}();
```
So ordinary NFT royalties reach the bug without any attacker.

### Reachability of the precondition (every gate read)
1. `CauldronHook.sol:1016` `legacyRegistry != 0 && legacyBuffer >= legacyThreshold` — threshold
   default `0.02 ether` (`CauldronHook.sol:319`), set by anyone's donation.
2. `CauldronHook.sol:1027` `if (!quoteIsCurrency0[id]) return;` — written at
   `CauldronHook.sol:647` as `quoteIsCurrency0[id] = IRegistryQuotes(registry).allowedQuote(currency0)`.
   `CauldronRegistry.sol:302` refuses any quote at/above `QUOTE_WATERMARK`, so **every allowlisted
   ERC20 quote sorts to currency0** and this gate is *always true* for an ERC20-quoted pool.
3. `CauldronHook.sol:1029-1030` live-key match — satisfied because `CauldronRegistry._recordSeed`
   pushes the seeded key itself: `CauldronRegistry.sol:1748 hook.setLiveKey(r.key);`, built from
   `generationQuote[gen]` (`CauldronRegistry.sol:1728`).
4. A non-native `generationQuote` is real: written at `CauldronRegistry.sol:982`
   (`generationQuote[newGen] = specQuote;`) and by a completed rotation (`RedemptionExt.sol:413`,
   pinned by the repo's own `test/functional/F10_QuoteRotationTotality.t.sol:114-116`).
   `CauldronRegistry.sol:301` names USDC/DAI/USDT as the intended quotes — i.e. 6-decimal stables.

### Counter-arguments tried, and their outcome
- **"The PoC uses a stub PoolManager, so the drain is fictional."** Partly fair and it bounds the
  finding, but it does not refute it. In real v4 an exact-input swap with `MIN_SQRT_LIMIT`
  consumes `min(amt, the pool's full currency0 capacity)`; the code itself anticipates the partial
  fill at `CauldronHook.sol:1080` (`if (spent < amt) { legacyBuffer += amt - spent; }`), which is
  exactly what the stub's `capacity` models. Outcome: the drain materialises whenever the pool's
  capacity ≤ the hook's quote balance; when it exceeds it, the ERC20 `transfer` reverts, the whole
  `address(this).call{gas:}` frame at `CauldronHook.sol:1035-1037` unwinds, and it is a safe
  no-op. So the bug is *state-conditional, never privilege-conditional*.
- **"Is there a cap on the buffer?"** No. `legacyBuffer += msg.value` is unbounded.
- **"Is there a slippage bound elsewhere?"** No. `MIN_SQRT_LIMIT` is the only limit passed, so an
  attacker can front-run the hook's own buy and sell into it.
- **"Whose money is drained?"** Protocol money. The tokens paid out are the hook's non-native fee
  reserve, counted by `relaunchAsset[asset]` (`CauldronHook.sol:1217, 2441`) whose only exit is
  `releaseRelaunchAsset` (`CauldronHook.sol:1679-1687`) — the self-funding path for the next
  generation. `LegacyBuyLib` moves the raw balance **without debiting `relaunchAsset`**, so after
  the drain the counter over-states the balance and `FeeRouteLib.send` fails → `revert SendFailed()`
  → the reserve is *locked*, not merely spent.
- **"Is the stuck ether recoverable?"** No. `legacyBuffer` is decremented by exactly one path
  (`legacyBuyStep`) and that path now spends ERC20, so the donated wei can never leave; the log
  shows `4.9999995e16` still armed to fire on the next swap.
- **"Does an 18-decimal quote save it?"** Largely, yes — wei:unit is then 1:1 and the misspend is
  numerically bounded by the donation. The Critical rating rests on a sub-18-decimal quote, which
  is the configuration `CauldronRegistry.sol:301` explicitly designs for.

### The hunter's open question, answered
**`_removeLiquidity` does not decide this, and the answer is "no brick".** `CauldronRegistry._removeLiquidity`
(`CauldronRegistry.sol:1552-1600`) only unwinds LP positions; the hook reserve is pulled on a
separate path, and that pull is already swallowed: `cauldron/PoolOps.sol:1075`
```solidity
try IHookReserves(hookAddr).releaseRelaunchAsset(asset) returns (uint256 g) { got = g; } catch {}
```
So a drained/locked reserve makes the next generation launch **underfunded, not impossible** —
relaunch cannot brick on this. The Critical rating therefore comes from the *permissionless loss
and lock of protocol funds*, not from a brick.

### Severity
**Critical** (hunter said High). Permissionless — anyone, or any NFT royalty via `RoyaltyRouter` —
costs one 0.02-ETH donation, and takes the hook's whole quote reserve through a no-slippage buy
whose counterparty the attacker can be. Degrades to **High** only on an 18-decimal quote.

---

## X1b — anti-sniper surtax jitter is steerable — **CONFIRMED, Medium (unchanged)**

### `-vv` evidence (verbatim)
```
[PASS] test_X1b_surtaxIsGrindableByTheSwappersOwnTick() (gas: 28982562)
Logs:
  window / maxBps         30 9600
  deterministic decay bps 6400
  min surtax over ticks   6402
  max surtax over ticks   9600
  tick that minimises it  -1526
  bps a probe swap saves  3198
```
Assertions after the logs (`assertGe`, `assertLt`, `assertGt`, `assertEq`) all executed.

### Non-vacuity (flip test)
`assertGe(minBps, decayed, ...)` → `decayed + 5000`:
```
[FAIL: FLIPPED: 6402 < 11400] test_X1b_surtaxIsGrindableByTheSwappersOwnTick() (gas: 28981382)
```
Flipped; file restored (`grep -c FLIPPED` → 0).

### The mechanism, quoted — `CauldronHook.sol:1411-1417`
```solidity
(, int24 tick,,) = poolManager.getSlot0(id);
uint256 rnd = uint256(
    keccak256(abi.encodePacked(blockhash(block.number - 1), PoolId.unwrap(id), block.number, tick))
) % (maxBps + 1);
uint256 jitter = (rnd * remaining) / window;
uint256 total = decayed + jitter;
```
`blockhash(n-1)`, `id` and `block.number` are all known at submission — the code's own comment at
`CauldronHook.sol:1391-1393` concedes it ("KNOWN to everyone during block N"). `tick` is the sole
unknown, it is the live pool tick, and it is read in `_beforeSwap` (before the priced swap), so a
probe swap earlier in the same transaction sets it.

### Counter-arguments tried, and their outcome
- **"Reaching the minimising tick costs a real price move."** Partly true — the scan's best tick is
  1526 ticks away (~16%). But `rnd` is redrawn per tick and `jitter < 20 bps` needs `rnd < 30` out
  of 9601, ~1 tick in 320; a few hundred ticks of probe suffices, and the grinder can simulate to
  pick the probe size exactly. It raises the cost, it does not remove the edge.
- **"The probe pays the surtax too."** It does, which is why this stays bounded: the probe's own
  fee/round-trip must be smaller than the 3198 bps saved, so only a large buy profits.
- **"Does the protocol lose funds?"** No. The surtax is a dividend routed to genesis holders; the
  grind transfers value from those holders to the sniper during a 30-block window. Bounded grief.
- **"Is the deterministic floor itself the real protection?"** Yes — `decayed` (6400 bps mid-window)
  survives the grind, so the anti-sniper tax is weakened, not defeated.

### Severity
**Medium** — confirmed as claimed. Bounded, window-limited value leakage from OG holders to a
sophisticated sniper; the jitter's stated purpose ("unknowable at submission time") is false.

---

## X1c — `setTaxExempt` alone exempts nobody — **REFUTED**

### Verdict
Refuted by reading the exemption check together with the actual buy path: both deploy sites route
their buy through the **gacha router, which IS registered as an opener**, so the exemption is live.

### Quoted gates
`CauldronHook.sol:2383-2384`:
```solidity
function _isExemptPlayer(address sender, bytes calldata hookData) private view returns (bool) {
    return taxExempt[_taxedPlayer(sender, hookData)] && isOpener[sender];
}
```
`CauldronHook.sol:2391-2394` — a trusted opener may *name* the player:
```solidity
if (!isOpener[sender] || hookData.length < 32) return sender;
address p = abi.decode(hookData, (address));
return p == address(0) ? sender : p;
```
The missing half the hunter assumed is absent is present in the full deploy:
`deploy/DeployLaunchpad.s.sol:241`
```solidity
hook.setOpener(address(gacha), true); // only the gacha router opens crystals
```
And `LaunchSniper` never swaps as itself — `cauldron/LaunchSniper.sol:76`:
```solidity
IGachaPlay(gachaRouter).play{value: msg.value}(0, minGnomeOut, 0, openMax);
```
with its own comment at `:74-76` ("router tags the swap with this contract as the player, so
exemption [applies]"). So `sender` = the gacha router (`isOpener` true) and `_taxedPlayer` decodes
to the sniper, whose `taxExempt` was set at `deploy/DeployLaunchSniper.s.sol:37`. Both conjuncts hold.

The same reasoning refutes the `deploy/DeployLaunchpad.s.sol:504` claim: `SNIPE_WALLET` is an EOA
and can never be `sender` at all, so tagging through an opener is the *only* way it could ever have
worked — and that is exactly the path it takes.

### Residual (hygiene only, not a finding)
`DeployLaunchSniper.s.sol` is a standalone script reading `HOOK`/`PRESALE` from env; it depends on
`DeployLaunchpad.s.sol:241` having already made the gacha router an opener. Run against a hook
deployed without that call, the exemption would indeed be inert. That is a script-ordering note.

### Severity
**Refuted** — no finding. (Was: Low, DERIVED, no PoC.)

---

## Discards
1 of 3 refuted (X1c). 1 upgraded (X1a → Critical). 1 confirmed as filed (X1b).
