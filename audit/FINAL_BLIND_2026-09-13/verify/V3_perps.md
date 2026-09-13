# V3 — subsystem 3 (perps) verification

Workspace: /tmp/blind-final-v3/contracts/solidity (decontaminated copy). PoCs copied from the
real repo's test/attacks/K3*.t.sol (only files read from the real tree).

Run: `forge test --match-path 'test/attacks/K3*' -vv --skip DeployPermit2`
Result: **8 passed, 0 failed, 0 skipped** (3 suites).
`grep -n "return;\|vm.skip\|function test_"` over all three PoCs: **zero** `return;`, **zero**
`vm.skip` in any `test_*` body (the only `return`s in the tree are inside production sources).
Every `test_*` reaches its final assert. K3c also carries a deliberate anti-vacuity control
(`test_control_warmupIsClearedSoNotWarmCannotMasquerade`) and reads the clock via
`vm.getBlockTimestamp()`, which is the viaIR gotcha handled correctly.

---

## T3c — hunter CRITICAL → **DOWNGRADED to HIGH** (VERIFIED)

**Ran:** `[PASS] test_attack_oneWeiOfStakeStrandsThePerpEngine() (gas: 438817)` plus the two
positives (`engineAliveWhileQuoteAgrees`, `rotationAdoptedWhenVaultIsEmpty`) and the control.
Assertions executed: all four in the attack (`syncGeneration refuses: VaultStaked`,
`every open now reverts TokenDead`, `the timelock cannot unwire the vault either`,
`only the vandal's own withdrawal heals it`) — the last one is reached, so nothing short-circuits.
PoC uses the REAL `PerpEngine` + REAL `PerpVault`; only the registry/PM/hook are stubs, and the
guard chain under test lives entirely in the two real contracts.

**Mechanism, quoted:**
- `cauldron/PerpEngine.sol:1337` — `if (vault != address(0) && IPerpVaultStake(vault).hasQuoteStake()) revert VaultStaked();`
- `cauldron/PerpVault.sol:190` — `return (ethShares | pendingEth) != 0;`  (1 wei of shares is enough)
- `cauldron/RedemptionExt.sol:582` — `generationQuote[gen] = toQuote;`
- `cauldron/RedemptionExt.sol:617` — `if (eng != address(0)) { try IPerpSync(eng).syncGeneration() {} catch {} }`  (revert swallowed)
- `cauldron/PerpEngine.sol:1796` — `if (quote != registry.generationQuote(gen)) return true;`
- `cauldron/PerpEngine.sol:1748` — `if (_isDead()) revert TokenDead();`
- `cauldron/PerpEngine.sol:2435` — `if (vault != address(0) && IPerpVaultStake(vault).hasStakers()) revert BadParam();`  (setVault vetoed)

**Counter-argument 1 — is there any un-stranding path?** Enumerated every writer of the state
`_isDead()` reads. `quote` is assigned in exactly one place, `PerpEngine.sol:1393` inside
`syncGeneration`. `generationQuote[...]` is assigned in exactly one place, `RedemptionExt.sol:582`
(grep over `cauldron/*.sol`: the only other hits are comments). Therefore:
  (a) **the staker(s) themselves** — `PerpVault.withdrawEth` (`:274`) has no gate that a dead
      engine trips; the PoC's final assertion proves the withdrawal + a permissionless
      `syncGeneration` heals the engine. Cost to the vandal of holding the veto: 0 (he forgoes 1 wei).
      No forced-exit / eviction function exists anywhere in `PerpVault.sol`.
  (b) **a relaunch** — `generationQuote[newGen]` is never written, so it defaults to
      `address(0)` (native). An engine still pinned native (the fresh-deploy case, and the case
      the PoC models) therefore has `quote == generationQuote(newGen)` again at the next
      generation and revives with no attacker cooperation. This is why "permanently"/"forever"
      is wrong: the ceiling is one generation. (If the engine HAD already adopted a non-native
      quote, the relaunch default re-diverges and the veto bites again.)
  (c) **governance — NONE.** `setVault` (`:2435`) asks `hasStakers()`, a superset of
      `hasQuoteStake()`, so the timelock cannot unwire or replace the vault. Verified by the
      PoC's `setVaultReverted` assertion.

**Counter-argument 2 — does the rotation path unstake first?** No. `RedemptionExt.sol:560-620`
is `rotateSliceFrom`'s completion branch; it flips the quote and best-effort-syncs. Nothing on
that path touches `PerpVault`. Worse than the hunter framed it: *any* healthy vault has ETH-side
LPs, so the stranding is the DEFAULT outcome of a rotation, not an attack. The engine's own
header (`PerpEngine.sol:1294-1296`) documents this as an intentional "park until the vault has
drained". The defect is that a 1-wei holder can hold the park open and no privilege can evict him.

**Counter-argument 3 — is the deploy script's staker production?** `deploy/DeployPerp.s.sol:235`
`IPerpVaultDeposit(address(vault)).depositEth{value: seed}();` with `seed = vm.envOr("PLV_SEED_ETH", uint256(0))`
(`:74`) — production script, but the seed defaults to 0. The claim holds only when PLV_SEED_ETH is
set; it is moot anyway, since real LP capital makes `hasQuoteStake()` true regardless.

**Counter-argument 4 — the "force-closed at minOut=0" loss leg.** Real but contingent.
`PerpEngine.sol:1162` `forceCloseDead(uint256 id) external` is permissionless, requires only
`_isDead()`, and calls `_settle(id, p, 0, MODE_DEATH, msg.sender)` — literal `0` minOut, keeper
paid `msg.sender`. But on the *intended* rotation path the book is empty (see T3d) and re-opens
are blocked by `TokenDead`, so there is nothing to force-close unless T3d's interlock bypass is
in play. The loss leg belongs to T3d; T3c standalone is a generation-long, un-evictable
shutdown of all leverage at a cost of 1 wei.

**Would-fail one-liner:** changing the vandal's deposit to `0 wei` makes `deposit` revert
`ZeroAmount` (`PerpVault.sol:222`) and the whole attack collapses — the mechanism is exactly the
share-count predicate, as claimed.

**Verdict: DOWNGRADED to HIGH.** Permissionless, un-evictable-by-governance denial of the entire
perp engine for the rest of a generation at 1 wei; not a permanent brick.
**Recoverable by:** the quote-side staker's own `withdrawEth` + permissionless `syncGeneration`,
or automatically at the next relaunch when the engine's cached `quote` matches the new
generation's default (`address(0)`). NOT recoverable by owner/timelock/registry.

---

## T3d — hunter HIGH DERIVED → **CONFIRMED HIGH** (DERIVED)

`cauldron/PerpEngine.sol:843-845`:
```
function blocksVolumeLink() external view returns (bool) {
    return openCount != 0 && markSource == address(0);
}
```
`CauldronHook.sol:1624-1628`:
```
function linkVolume(PoolId primary, PoolId secondary) external {
    if (msg.sender != registry) revert OnlyRegistry();
    if (perpEngine != address(0) && IPerpOpenCount(perpEngine).blocksVolumeLink()) {
        revert PerpsOpen();
    }
```
With `markSource != 0` the predicate is false regardless of `openCount`, so `linkVolume`
succeeds over an open book. `RedemptionExt.sol:606-609` justifies the in-line requote with
"reaching this line required `linkVolume` to succeed earlier in this same call (:372) ... So the
book is provably empty right now" — that inference is **false** once a mark source is armed.
Downstream: `:582` flips the quote, `:617`'s sync hits `PerpEngine.sol:1278`
`if (newQuote != quote && openCount != 0) revert PositionsOpen();` — swallowed by the catch — so
`_isDead()` (`:1796`) reads true over solvent positions and every one of them becomes
`forceCloseDead`-able (`:1162`) by a stranger at minOut `0` with the keeper cut. No separate
open-book check exists on the rotation path (grep `blocksVolumeLink`: exactly two sites, the two
above). Cheapest non-fork PoC not attempted within budget; the code path is quoted end to end
and every gate on it was read. Severity HIGH is right (loss to traders, needs a governance-
approved rotation to be in flight).

---

## T3a — hunter HIGH VERIFIED → **DOWNGRADED to MEDIUM** (VERIFIED)

**Ran:** `[PASS] test_attack_staleQueueTakes100PctOfAFreshDeposit() (gas: 268777)` and the
solvent positive. Final assertions executed: `bob paid 10 ETH in`, `bob's shares are worth ~0 the
instant they mint` (`< 1 gwei`), `alice's already-worthless claim took bob's whole deposit`.
Real `PerpVault`, mocked engine — acceptable, since the whole mechanism is in `PerpVault`.

- `PerpVault.sol:196` `return t > pendingEth ? t - pendingEth : 0;` — `assetsEth()` saturates at 0.
- `PerpVault.sol:238` `shares = FullMath.mulDiv(amount, ethShares + OFFSET, assetsEth() + 1);` — with
  `assetsEth()==0` bob mints shares priced against a 1-wei base, i.e. worth nothing.
- `PerpVault.sol:279` `owed = FullMath.mulDiv(shares, assetsEth() + 1, ethShares + OFFSET);` — bob's exit ≈ 0.

**Counter 1 — is the nominal recomputed at claim time?** Yes: `claimPendingEth` (`:324`) calls
`_haircut(owed, engine.totalEth(), pendingEth)` (`:332`). It does not save bob, because
`engine.totalEth()` includes bob's fresh deposit, so backing >= claims again and alice claims in
full. The haircut is the reason bob is robbed rather than the reason he is not.
**Counter 2 — reachable without a loss?** No. It needs `pendingEth > totalEth`, i.e. realised bad
debt at least as large as the queue; the PoC manufactures a total wipe. Partial loss steals
proportionally less.
**Counter 3 — transfer or write-off?** Transfer: alice receives exactly what bob paid in.
**Counter 4 — visible before depositing?** Yes, fully on-chain: `pendingEth()` and `assetsEth()`
are public views and `assetsEth()==0 && pendingEth!=0` is the tell. `deposit` has no guard and
emits no warning, so it is a live footgun, but the victim can see it and the attacker cannot
force him in.
**Verdict: DOWNGRADED to MEDIUM** — real value transfer, but gated behind an insolvency event
and fully observable by the victim before the transaction. Fix shape: refuse (or price-floor)
`deposit` while `pendingEth > engine.totalEth()`.

---

## T3b — hunter MEDIUM VERIFIED → **CONFIRMED MEDIUM** (VERIFIED)

**Ran:** `[PASS] test_attack_rotationPermanentlyLocksTokStakerOutOfFutureYield() (gas: 2601490)`
plus the positive `test_positive_tokStakerClaimsShortSideYield`.
`PerpEngine.sol:1359-1360` — `uint256 writtenOff = tokYieldEth; ... plv = 0; tokYieldEth = 0; insuranceEth = 0;`
zeroes the pot but not `tokYieldCumulative` (`:342`, only ever `+=` at `:1897` and `:2266`).
`PerpVault.claimTokYield` (`:405`) is all-or-nothing — `paid = tokRewardOwed[msg.sender]`, no
partial — and pays through `PerpEngine.withdrawTokYieldTo` (`:2295`), whose first line is
`if (amount > tokYieldEth) revert PlvInsufficient();`. A pre-rotation token staker's `paid`
permanently carries the written-off accrual, so every future claim reverts. Confirmed at MEDIUM.

---

## T3e — hunter MEDIUM DERIVED → **CONFIRMED MEDIUM** (DERIVED)

`PerpMarkSource.sol:174` `if (!armed) return 0;` — an unarmed source answers a valid-looking
tick 0 (1:1). `PerpEngine._currentTick` (`:666-684`) accepts any 32-byte answer
(`ok := and(ok, eq(returndatasize(), 0x20))`) with **no** zero/sanity check and returns it as the
mark. `setPrimary` (`:115-120`) sets `primary = key; armed = true;` with no pair or orientation
check — the sibling path has one (`:123-127` `if (!armed) revert NotArmed();` plus the pair rule),
the primary does not. And `markSource = address(0)` appears exactly once in the engine
(`PerpEngine.sol:1384`), inside the `newQuote != quote` rotation branch, so a **relaunch** leaves
an armed source pointed at the previous generation's pool. Owner-wiring dependent, hence MEDIUM;
the relaunch-staleness leg is the reachable one and would justify HIGH if a fork PoC shows the
stale pool's tick driving liquidations on the new token.

---

## T3f — hunter LOW DERIVED → **CONFIRMED LOW** (DERIVED)

`PerpEngine.sol:1858-1863` `_rebook` sets `p.collateral = 0;`. Funding is sized off collateral:
`:917` `uint256 notional = uint256(p.collateral) * p.leverage;` and `:919`
`int256 cap = int256((uint256(p.collateral) * maxFundingBps) / BPS);` — both become 0, so the
remainder pays no funding until it finally closes. `:1617` `uint256 penalty = (uint256(p.collateral) * liqPenaltyBps) / BPS;`
is likewise 0, so the remainder can be liquidated with no penalty and no keeper cut. The header
comment at `:1849-1856` asserts "funding settles in full against the smaller position on the
final close"; the arithmetic at `:917` contradicts it (comment is not evidence). Backing is not
lost — `p.principal = newBacking` — so this is an economic leak, not a solvency hole. LOW stands.

---

## Tally
Findings examined: 6. Confirmed at hunter severity: 4 (T3d, T3b, T3e, T3f).
Downgraded: 2 (T3c CRITICAL→HIGH, T3a HIGH→MEDIUM). Refuted outright: 0. Not verified: 0.
**Discards (refuted + not-verified): 0; severity discards: 2.**
