# V4 — token / NFT economy verification (blind copy /tmp/blind-final-v4)

Env: `FOUNDRY_PROFILE=cauldron`, `forge test --match-path 'test/attacks/K4*' -vv --skip DeployPermit2`.
Both hunter PoCs compiled and passed on the first run; no `return;`, no `vm.skip`, no `vm.assume`
anywhere in `test/attacks/K4a_*.t.sol` / `K4b_*.t.sol` (grep returned nothing).

---

## K4a — ERC20 royalty stranded on RoyaltyRouter — HIGH → **DOWNGRADED to MEDIUM** (VERIFIED)

Ran:
```
[PASS] test_K4a_erc20_royalty_is_permanently_stranded() (gas: 3325166)
Logs:
  stranded WETH royalty (wei): 5000000000000000000
```
The `log_named_uint` is emitted after `assertFalse(recoverable)` / `assertEq(stranded, 5 ether)`,
so both assertion lines demonstrably executed.

Code (`cauldron/RoyaltyRouter.sol:35-46`) — the whole contract surface:
```solidity
contract RoyaltyRouter {
    address public immutable hook;
    constructor(address _hook) { require(_hook != address(0), "hook"); hook = _hook; }
    receive() external payable {
        if (msg.value > 0) ILegacyBuffer(hook).fundLegacyBuffer{value: msg.value}();
    }
}
```
47 lines total, no `fallback`, no `delegatecall`, no owner, no ERC20 entrypoint. Wired at
`cauldron/CauldronFactory.sol:81-82`:
```solidity
RoyaltyRouter router = new RoyaltyRouter(c.hook);
col.setRoyalty(address(router), c.royaltyBps);
```

Counter-argument 1 — can the receiver be rotated? `CauldronCollection.setRoyalty`
(`cauldron/CauldronCollection.sol:341-345`) is gated `msg.sender != configurator && msg.sender != deployer`.
`configurator` is the factory (which only calls it inside `deployBrew`) and `deployer = registry_`
(`CauldronCollection.sol:156`). Grepping the whole tree for `setRoyalty` callers gives only
`CauldronFactory.sol:82`, `MiFrensGenesis.sol:446` (genesis, different contract) and
`CauldronRegistry.sol:607`, which is the registry's OWN config setter for future deploys, not a call
into a live collection. **No rotation path exists** — counter refuted, "permanent" stands.

Counter-argument 2 — is the royalty enforced on-chain? `CauldronCollection` implements
`ICreatorToken` with a `transferValidator` (`CauldronCollection.sol:165-197`), but
`CauldronFactory.deployBrew` (`CauldronFactory.sol:64-90`) never calls `setTransferValidator`, so a
fresh volume collection ships with validator == 0, which the code itself documents as
"Zero = unrestricted (EIP-2981 declared but not enforced)" (`CauldronCollection.sol:127-129`).
Royalty payment is therefore VOLUNTARY marketplace behaviour; the stranded amount is whatever
2981-honouring venues choose to pay in ERC20, not a guaranteed stream.

Counter-argument 3 — severity. Value at risk is third-party-paid royalty (never a user deposit,
never protocol principal), the ETH path (the documented design intent) works end to end (the PoC's
own positive control: 1 ether reached `fundLegacyBuffer`), and the ERC20 leakage rate is gated by
voluntary marketplace behaviour. Real and unrecoverable, but not High. **MEDIUM.**

One-line falsifier attempted: none available — any change that gives the router an ERC20 exit
requires editing the contract, and every probe selector already returns failure.

---

## K4b — uncapped gacha re-anchor — MEDIUM → **DOWNGRADED to LOW** (VERIFIED, counter-PoC run)

Ran the hunter's PoC:
```
[PASS] test_K4b_expired_ticket_seed_can_be_reground_without_limit() (gas: 418613)
Logs: honest odds (bps): 900 | free re-anchors used: 11 | NFTs minted from ONE crystal: 1
```
Fixture gotcha checked and satisfied: the PoC reads `vm.getBlockNumber()` and asserts
`require(vm.getBlockNumber() == commitBlock + 1, "vm.roll had no effect")` plus
`assertGt(vm.getBlockNumber(), startBlock)`. Assertions after the attack executed (the three logs
precede `assertGt(reanchors,1) / assertTrue(won) / assertEq(outstandingTickets,0)` and the suite is green).

Mechanism is real (`CauldronHook.sol:2391-2394`):
```solidity
if (bh == 0) {
    b.commitBlock = uint48(block.number);
    break; // FIFO: resume from here on the next call
}
```
no re-anchor counter, unlike `CauldronCollection._reveal`.

**Cheapest counter-argument, executed.** Resolution is permissionless (`CauldronHook.sol:2362
resolveTickets`) AND auto-fired on every native swap (`CauldronHook.sol:966-972`,
`address(this).call{gas: gg - GACHA_GAS_RESERVE}(... nativeGachaStep ...)`), so the grind requires
that *nobody* touches the queue for 256 blocks, every round. I copied the PoC to
`test/attacks/K4bC_Counter.t.sol` and inserted one third-party resolve inside the wait window:
```solidity
vm.roll(commitBlock + 2); vm.prank(address(0xB0B)); hook.resolveTickets(30);
```
Result:
```
[FAIL: the ground ticket won] test_K4b_...()
Logs: third party resolved at block: 1002 | free re-anchors used: 999 | NFTs minted from ONE crystal: 0
```
A single unprivileged `resolveTickets` call anywhere in the 256-block window destroys the grind.

Counter 1 (cost): re-anchor costs gas only, but 11 rounds × 256 blocks ≈ 2816 blocks of enforced
market silence (≈9 h on 12 s blocks). Counter 2 (who): only expiry triggers the re-anchor branch,
and expiry cannot be forced by a third party, so a griefer CANNOT re-anchor someone else's winning
ticket — no second finding. Counter 3: the player's credit is spent at commit and never refunded, so
this is a fairness break with a free-option shape (EV >= honest, never worse), bounded by pool
inactivity. Genuine bug, but the exploitability precondition is a dead pool: **LOW.**

---

## K4c — `playChurn` has no slippage bound — MEDIUM **CONFIRMED** (DERIVED, not run)

`cauldron/CauldronGachaRouter.sol:369`:
```solidity
function playChurn(uint256 quoteIn, uint256 loops, uint256 openMax)
```
No `minOut` of any kind, while the sibling entrypoint at `:234`
`function play(uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax)`
takes two. Every leg inside `_churn` uses the extreme tick:
`CauldronGachaRouter.sol:470` and `:496` pass `sqrtPriceLimitX96: _limit(true/false)` where
`_limit` (`:518-520`) returns `4295128740` / `1461446703485210103287273052203988822378723970341`
— MIN_SQRT_PRICE+1 and MAX_SQRT_PRICE-1, i.e. no price protection at all.

Bounds: `MAX_LOOPS = 10` (`:69`, enforced at `:378`), so up to 10 buys + 9 sells = 19 unbounded
swaps in one unlock. Funds are the caller's own (`_pullQuote(q, quoteIn)` at `:374` pulls from
`msg.sender`) and `playChurn` is not callable on anyone else's behalf, so the victim is the caller
only — no third-party or protocol funds. Loss is bounded by `quoteIn`, but within that bound a
sandwicher can take essentially all of it and the caller has no parameter to stop it. Self-inflicted
scope caps this at Medium; the asymmetry with `play` shows the omission is not intentional design.
Not run (no PoC supplied and none written within budget) — tagged DERIVED.

---

## K4d — unbounded external call in `receive()` — LOW **CONFIRMED** (DERIVED)

`cauldron/RoyaltyRouter.sol:44-46`:
```solidity
receive() external payable {
    if (msg.value > 0) ILegacyBuffer(hook).fundLegacyBuffer{value: msg.value}();
}
```
The forward is an unmetered external call into `CauldronHook.fundLegacyBuffer`, which itself does
storage writes and routing. Any payer using `transfer`/`send` (2300 gas stipend) — still present in
older marketplace and splitter code — will run out of gas, and because the call's failure bubbles,
the paying transaction (the secondary sale) reverts wholesale. No funds lost; the failure mode is
"sale cannot settle on that venue", and modern Seaport/Blur use full-gas `call`. LOW stands.

---

## Spot-check — "every native leg in FeeRouteLib checks the recipient has code" — **AGREE**

- `_move` — `cauldron/FeeRouteLib.sol:116-117`: `if (to.code.length == 0) return false;` precedes
  `if (asset == address(0)) { (ok, ) = to.call{value: amount}(""); ... }`.
- `_fundGuild` — `FeeRouteLib.sol:156-157`: same check before `guild.call{value: amount}("")`.
- `_deliver` — `FeeRouteLib.sol:180-181`: same check before `to.call{value: amount}(nativeSel)`.
- external `deliver` — `FeeRouteLib.sol:249-251`: same check before `to.call{value: amount}(nativeSelector)`.

One native leg is uncovered: `send` (`FeeRouteLib.sol:207`)
```solidity
if (gasCap == 0) { (ok, ) = to.call{value: amount}(""); }
else { (ok, ) = to.call{value: amount, gas: gasCap}(""); }
```
has no `to.code.length` guard and would report `ok == true` to a codeless address. However
`grep -rn "FeeRouteLib.send"` across the tree returns **no call site** (only a prose mention at
`cauldron/PoolOps.sol:623`), so nothing in the protocol can strand through it today. The hunter's
refutation holds for every leg that is actually reachable; `send` is a latent footgun for a future
caller, informational only.

---

Discards: 0 findings NOT VERIFIED. Verdict changes: 2 downgrades (K4a High→Medium,
K4b Medium→Low), 2 confirmed as filed (K4c Medium, K4d Low).
Counter-PoC left at `/tmp/blind-final-v4/contracts/solidity/test/attacks/K4bC_Counter.t.sol`
(blind copy only; nothing written into the real repo's test tree).
