# V2 — lifecycle & governance: verification

Tree: `/tmp/blind-final-h2/contracts/solidity`. All runs `FOUNDRY_PROFILE=cauldron`, `--skip DeployPermit2`, `-vv`.
Baseline run of the hunter's four PoCs: **8 tests passed, 0 failed** (X2a 2/2, X2b 2/2, X2c 2/2, X2d 2/2).
`grep -n "return;"` over `test/attacks/X2*.t.sol` → **no hits**; every PoC reaches its final assertion, and each ships a positive control that exercises the same machinery with the mechanism absent.

---

## X2a — migration mandate starved through a secondary leg — **CONFIRMED (High)**, precondition narrowed

Evidence:
```
[PASS] test_X2a_control_primarySlicesCompleteTheMigration() (gas: 299682)
[PASS] test_X2a_legSlicesStarveTheMigrationMandate() (gas: 285017)
  X2a grief gas (governor side only): 14057
```
Non-vacuous: the control is the one-line flip — `gov.consume(2500, true)` x4 sets `migrationMandateSpent()` true; `gov.consume(2500, false)` x4 leaves it false with the envelope at zero.

Gates read (not assumed):
- `TreasuryGovernor.sol:697` `function consume(uint16 bps, bool fromPrimary) external` — registry-only; `:708-718` debits `movedBps` always, `movedPrimaryBps` only when `fromPrimary`, and deactivates on `movedBps >= maxTotalBps`.
- `TreasuryGovernor.sol:683` `return e.maxTotalBps >= BPS_ONE && e.movedPrimaryBps >= e.maxTotalBps;`
- `RedemptionExt.sol:280` `function rotateSliceFrom(uint8 fromLeg, ...) public` — no role gate ("PERMISSIONLESS, WITHIN WHAT THE GUILD APPROVED", `:294`); `fromLeg` is caller-supplied and reaches the governor verbatim at `:437` `ITreasuryGovernor(gov).consume(sliceBps, fromLeg == 0);`
- `TreasuryGovernor.sol:387` `if (lastEnvelopeAt != 0 && block.timestamp < lastEnvelopeAt + COOLDOWN) revert CooldownActive();` — the 7-day block on a corrective proposal is real.

**Counter-argument tried (partly succeeded — precondition, not refutation).** Every leg is recorded with the envelope's own destination: `RedemptionExt.sol:423-424` `_recordLeg(gen, toQuote, ...)`, and `:358-359` `if (fromQuote == toQuote) revert BadConfig();`. So legs created *under the envelope being starved* cannot be used to starve it; `generationLegs` is `mapping(uint256 => TreasuryLeg[])` (`CauldronBase.sol:460`), so an out-of-range `fromLeg` panics, and `:371` `if (quoteOut == 0 || tokenOut == 0) revert BadConfig();` demands a leg with real liquidity. The attack therefore needs **at least one pre-existing leg whose quote differs from the new envelope's destination** — impossible on a first migration from a fresh deploy (legCount 0), routine afterwards (my X2e fork run creates exactly that state). Once such a leg exists the denial is permissionless, gas-only, and repeatable every envelope, and the guild cannot escape by re-voting: it can only win the race for each envelope. Severity stands at High.

---

## X2b — `recoverLegs` retry is unreachable — **CONFIRMED (Medium, defense-in-depth)**

Evidence:
```
[PASS] test_X2b_control_neighbouringLegSelectorsAreRouted() (gas: 26044)
[PASS] test_X2b_recoverLegsRetryIsUnreachableAndSilent() (gas: 31762)
```
Non-vacuous: the control routes three neighbouring facet selectors through the same etched registry (`legCount`, `legAt`, `sweepLegProceeds`) and gets `NotConfigured()`/success, while `recoverLegs(uint256)` returns empty revert data — the discriminator works.

Gates read:
- `CauldronRegistry.sol:63` `bytes4 private constant RECOVER_LEGS = bytes4(keccak256("recoverLegs(uint256)"));` — the selector exists only as an internal constant for the one call inside `_removeLiquidity`.
- `CauldronRegistry.sol:248` "facet with no stub here, and there is no catch-all fallback"; `:1407-1410` "this contract declares `receive()` and no `fallback()`".
- `CauldronRegistry.sol:282` `function sweepLegProceeds(address, address) external returns (uint256) { _forwardToExt(); }` and `:284` "`legProceedsOf` is deliberately NOT stubbed".

**Counter-argument tried (failed).** `sweepLegProceeds` *is* routed, so it looked like the recovery path. It is not: `RedemptionExt.sol:794 function sweepLegProceeds(address asset, address to) external onlyOwner` moves already-**booked** ERC20 proceeds out of `legProceeds`; it cannot unwind an LP position that `recoverLegs`' per-leg `try/catch` left in place. No substitute exists. Held at Medium rather than raised: the hunter demonstrates no reachable way to *make* a leg fail its catch, so this is a missing safety net (conditional lock), not a live lock. The header's promise ("can be retried once whatever broke is fixed") is prose and carries no weight either way.

---

## X2c — "frozen oracle cache" — **REFUTED as stated → DOWNGRADED to Low**

The hunter's PoC passes, but the named mechanism is not load-bearing. I edited the source (not the test) at `QuoteOracle.sol:309`, turning `c.at = uint64(block.timestamp);` into `if (fresh > 0) c.at = uint64(block.timestamp);` — the exact fix the finding implies — and re-ran:
```
[PASS] test_X2c_control_liveFeedIsTracked() (gas: 90374)
[FAIL: and re-stamps itself on every failed refresh: 1000000 != 347896960]
       test_X2c_deadFeedServesAFrozenPriceForever() (gas: 110895)
```
Only the assertion *about `c.at` itself* (line 104) flipped. Everything before it still passed: `afterOneTtl == f0`, `afterOneYear == f0`, **`afterTenYears == f0`**. A dead feed serves its last price for ten years with the re-stamp removed. Source restored (`grep -n "c.at = uint64" cauldron/QuoteOracle.sol` → `309:` unchanged).

The cause is the tail of the function, which is documented behaviour, not an oversight: `uint256 fresh = this.usdPerRawUnit(quote); ... if (fresh > 0) c.factor = fresh; return c.factor;` — "A refresh that comes back unusable keeps the LAST GOOD value" (`QuoteOracle.sol:305-311` header). `c.at` only decides whether the 30k-gas feed read is re-attempted.

**And the implied fix is strictly worse for the drain vector cited.** If the cache returned 0 instead, `QuoteRotator._usd` (`:564-574`, `return f == 0 ? 0 : ...`) returns 0, and `_oracleFloor` (`:398-404`) returns 0 — "FAILS OPEN, DELIBERATELY ... the caller's `minOut` stands alone". `swapOnce` then enforces `if (out < (minOut > floor ? minOut : floor))` with `floor == 0`, i.e. **no floor at all** on the permissionless path. A stale floor is a degraded guard; the alternative is a removed one.

Residual, genuine and small: `priceable()` (`QuoteOracle.sol:318`) reports false while `cachedUsdPerRawUnit` keeps pricing, so `TreasuryGovernor._requirePriceable` (`:782`) blocks *new* envelopes into an asset that in-flight rotations still price off a dead feed. Hygiene → **Low**. No attacker trigger: it needs an independent feed failure plus a large real move.

---

## X2d — settled mandate erased by 64 filings — **DOWNGRADED to Medium**

Evidence (mechanism confirmed, PoC non-vacuous — the control is the same sequence minus the flood):
```
[PASS] test_X2d_control_scanRecoversTheForgottenMandate() (gas: 882952)
[PASS] test_X2d_spamErasesTheVotedMandate() (gas: 12805124)
  X2d flood gas for 64 filings: 11844209
  X2d erased mandate id: 2
```
Gates read: `CauldronGovernor.sol:474` `MAX_LEADER_SCAN = 64`; `:478-483` positional window `first = n > MAX_LEADER_SCAN ? n - MAX_LEADER_SCAN + 1 : 1`; `:412-419` one-deep runner promotion then fallback `(_leaderId, _leaderVotes) = _recomputeLeader();`; `:356-359` the runner slot is overwritten by the *displaced leader*; `propose` requires only `mifrens.getVotes(msg.sender) != 0` (`:240`) with no cooldown; `CauldronRegistry.sol:787` `if (address(governor) == address(0) || !governor.hasProposals()) revert NoProposal();`.

**Counter-argument tried (succeeded, partially).** `_bestUnconsumed` (`CauldronGovernor.sol:446-452`) returns `_leaderId` directly — no scan — whenever it exists, is unconsumed, has votes and its window has closed. So **any freshly voted proposal is immune to unlimited spam**: the flood can only erase mandates that are *not* the cached leader, i.e. stockpiled runners-up. Recovery is the ordinary governance action the guild performs each generation (file + vote + 3-day `VOTING_PERIOD`), and `relaunch()` reverts at the top, before any state change, so the retry is clean — no brick. Cost 11.8M gas per flood against a stall of one voting period: bounded grief.

Not Low, because the damage is permanent for the targeted proposal: `vote` reverts `VotingClosed()` at `:337`, so a settled-but-erased mandate can never be re-cached — it is dead for good, and the vote that produced it is wasted. **Medium.**

---

## X2e — residual frozen after a completed migration — **CONFIRMED (High)**, upgraded DERIVED → VERIFIED

I wrote the missing PoC: `/tmp/blind-final-h2/contracts/solidity/test/attacks/X2e_FrozenResidualAfterMigration.t.sol`, inheriting the existing fork harness `test/functional/F10_QuoteRotationTotality.t.sol` so the migration is a *real* one against the Sepolia PoolManager/PositionManager.
```
[PASS] test_X2e_residualIsFrozenAfterTheQuoteFlips() (gas: 5989780)
  X2e: harness live
  X2e: quote flipped to USDG, primary pair still currency0 = ETH, position 39209
  X2e control - slice out of leg 1 succeeded: true
  X2e primary slice ok? false
  X2e primary revert data: 0x07cc321c
```
`cast sig "BadConfig()"` → `0x07cc321c`, i.e. `RedemptionExt.sol:371 if (quoteOut == 0 || tokenOut == 0) revert BadConfig();`.

Not skipped (`X2e: harness live` proves `active`), and non-vacuous by construction: the **control** rotates a slice out of leg 1 successfully in the same test, same envelope, same venue, same block — so the primary's failure is not the envelope, the cooldown, the allowlist or the route.

Mechanism, read: the completed migration writes only the quote — `RedemptionExt.sol:504-505` `if (fromLeg == 0 && ITreasuryGovernor(gov).migrationMandateSpent()) { generationQuote[gen] = toQuote; ... }` — while `generationPositionId` / `generationPoolKey` are written in exactly one place in the non-test tree, `CauldronRegistry.sol:1743-1744` (inside relaunch). Afterwards `rotateSliceFrom` with `fromLeg == 0` (`:346-349`) pairs the NEW quote with the OLD position and key, and `PoolOps.removePartial` measures `quoteRecovered = _balance(quote) - qBefore` against a currency the withdrawal never touches → 0 → `BadConfig`. The ~32% residual (the code's own figure at `RedemptionExt.sol:500`) is unreachable by any rotation until the next relaunch. High.

---

## X2f — guardian settable to `address(0)` — **CONFIRMED (Low)**

`TreasuryGovernor.sol:523-526`:
```solidity
function setGuardian(address g) external {
    if (msg.sender != guardian) revert NotGuardian();
    guardian = g;
}
```
No zero check. The guardian is the only caller of `cancel` (`:516-517`, the sole emergency kill for a live envelope) and `setQuoteOracle` (`:791-792`). Role-gated and self-inflicted, no attacker path → Low.

## X2g — dead `completeRotation`, codeless-address transfer — **CONFIRMED (Low)**

`RedemptionExt.sol:605-609 function completeRotation(address quote, uint256 quoteAmount, uint256 tokenAmount) external onlyOwner` — `grep -n completeRotation CauldronRegistry.sol` returns **nothing**: no stub, and the registry has no fallback (`:1407-1410`), so the function is unreachable through the only address that owns the storage it writes. Dead weight against the EIP-170 ceiling.
`QuoteRotator.sol:691-695 _safeTransfer` accepts `ok && ret.length == 0`, which a codeless address satisfies — a mis-set token address reports a successful transfer. Both Low (hygiene).
