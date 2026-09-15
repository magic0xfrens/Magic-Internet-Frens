# H4 — Lifecycle seams (relaunch / rotation / denomination / adoption)

Tree: `/tmp/r45-blind-h4/contracts/solidity`. Citations use `contracts/solidity/<File>.sol:<line>`.

## 1. MODEL FROM CODE

**Relaunch** `CauldronRegistry.sol:821` `relaunch() external nonReentrant` — permissionless, no params.
Gates, in order: `summoned` (:828); `hook.isDead(oldPoolId)` (:833); `block.timestamp >= lastSummonAt + minLifetime` (:837); `governor.hasProposals()` (:841).
Then: `_perpHousekeep(false)` (:854) → `hook.forceClosePerps()` (Registry:1183, **not** try-wrapped) → `CauldronHook.sol:1929`, which try/catches `forceCloseAllDead()` but then `if (IPerpForceClose(eng).openCount() != 0) revert PerpsOpen();` (CauldronHook.sol:1961).
`_removeLiquidity(oldGen)` (:857) unwinds primary + reserve + seeder bands + `delegatecall RECOVER_LEGS` into `RedemptionExt._recoverLegs` (RedemptionExt.sol:869).
`spec.quote` is re-allowlisted then degraded to native (:951). `_deployToken` (:970). `PoolOps.seedFunding` (:1021) decides the funding denomination. Only then `if (totalETH == 0) revert NoLiquidityToSeed(); governor.markConsumed(winId);` (:1035-1036) and `generationQuote[newGen] = specQuote` (:1040). Everything after :1036 is the fatal window.

**Adoption** `CauldronHook._afterInitialize` (:629) — `require(sender == registry)` (:636); `quoteIsCurrency0[id] = allowedQuote(currency0)` (:654). `allowedQuote[address(0)] = true` at Registry:181. Every `poolManager.initialize` in the tree is inside `PoolOps` (`:282,:358,:533,:943`), a DELEGATECALL library, so `sender` is always the registry. Squatting closed.

**Rotation** `RedemptionExt.rotateSliceFrom` (:280), permissionless, bounded by `TreasuryGovernor.allowance()` (:782) / `consume` (:869). Caller supplies `fromLeg`, `sliceBps`, `minOut`, `route`; the route is checked against `QuoteRotator.allowedVenue` (QuoteRotator.sol:359) and an oracle floor (`:373`, `if (floor == 0 && quoteOracle != address(0)) revert NotPriceable()`). `generationQuote[gen]` flips only on `fromLeg == 0 && migrationMandateSpent()` (RedemptionExt.sol:588).

**Volume / death** `CauldronHook.isDead` (:1735) sums `getVolume24h` over `_volumeSiblings` (cap 9, `MAX_SIBLINGS` :777). Volume is USD-normalised by `_toUsd` (:1552) before recording (:858).

## 2. FINDINGS

```
id: R4A   severity: Medium   confidence: VERIFIED
subsystem: relaunch funding / per-asset relaunch reserve
file:line: contracts/solidity/cauldron/PoolOps.sol:1172-1181
  // 1. The proposal's choice, if value already exists in that denomination.
  if (wantQuote != address(0) && (recovered == 0 || oldQuote == wantQuote)) {
      uint256 p = (oldQuote == wantQuote ? recovered : 0) + _pullAsset(hookAddr, wantQuote);
      if (p >= MIN_SEED_UNITS) return (wantQuote, p, 0);
  }
  // 2. Native ...
  if (recovered == 0 || oldQuote == address(0)) {
      uint256 n = (oldQuote == address(0) ? recovered : 0) + vaultSwept + _pullEth(hookAddr);
      if (n >= MIN_SEED_UNITS) return (address(0), n, vaultSwept);
  }
title: A relaunch whose requested quote holds less than MIN_SEED_UNITS drains that
       asset's entire relaunch reserve out of the hook and then abandons it in the
       registry, uncounted by the seed and unreachable by the normal cycle.
```
`_pullAsset` (PoolOps.sol:1190) is a **state change**, not a read: `CauldronHook.releaseRelaunchAsset` (CauldronHook.sol:1877-1887) does
```
amount = relaunchAsset[asset];
if (amount == 0) revert NoETHToRelease();
relaunchAsset[asset] = 0;
if (!FeeRouteLib.send(asset, registry, amount, 0)) revert SendFailed();
```
The branch's acceptance test `p >= MIN_SEED_UNITS` runs **after** the pull. On a short branch the reserve has already left the hook, is not part of the returned `amount`, and is not read by branch 2 or 3. PoolOps' own comment at :1128 states the consequence: *"nothing in the normal cycle spends a loose registry balance — only `migrateToSuccessor` and the timelocked `emergencySweep` do, both break-glass."* `emergencySweep` (CauldronRegistry.sol:488) sends to `emergencyAdmin`, i.e. out of the machine, not back into it.

`MIN_SEED_UNITS = 777_000_000e18 >> 60` (PoolOps.sol:220) = **673,940,064 base units**, a single constant applied to every decimal. In an 18-decimal asset that is 6.7e-10 tokens (irrelevant); in the 6-decimal USDG the manifest allowlists it is **673.94 USDG**.

```
precondition: `recovered == 0` (the dying position returned no quote — Registry:1066
  documents this as reachable: "a fully drained book, or a progressive generation
  whose teardown recovered no token"), and the winning proposal names a quote whose
  hook reserve is below 673.94 raw units. Both ordinary. No attacker required; an
  attacker with the governor's proposal threshold can also aim `wantQuote`.
sequence:
  1. (ordinary operation) swap fees accrue N < 673.94 USDG into
     CauldronHook.relaunchAsset[USDG] (credited per-asset at CauldronHook.sol:1349).
  2. a proposer files a brew with spec.quote = USDG; it wins.
  3. anyone calls CauldronRegistry.relaunch() (0 ETH).
  4. PoolOps.seedFunding branch 1 pulls all N USDG, fails `p >= MIN_SEED_UNITS`,
     falls through; branch 2 seeds in ether. The N USDG is now registry-held and
     invisible to every later relaunch.
attacker_cost: gas only (~0 ETH); the proposal threshold if the quote is steered.
damage: up to 673.93 raw units of the requested quote per relaunch, permanently out
  of the self-funding reserve. Recoverable only via the timelocked `emergencySweep`,
  which pays `emergencyAdmin`, not the next generation. Bounded, repeatable once per
  rebirth per asset.
poc: test/attacks/R4A_SeedFundingStrand.t.sol   needs_fork: no
```
Observed under `-vv` (all three assertion sets executed; `grep -n "return;" test/attacks/R4A_*.t.sol` is empty):
```
[PASS] test_positive_fundedQuoteIsUsed()                       (800 USDG -> quoteUsed = USDG, seeded 800e6)
[PASS] test_attack_shortQuoteReserveIsPulledAndAbandoned()      quoteUsed 0x0, seeded 10e18 wei,
                                                                usdg moved to registry 673940063, usdg left on hook 0
[PASS] test_attack_abandonedReserveIsNotRecoveredNextTime()     second run seeded 0, registry-held USDG 673940063
```

**Liveness positive test (VERIFIED, existing suite, not weakened):** `forge test --match-path test/LifecycleE2E.t.sol -vv` on the Sepolia fork — `test_FullLifecycle_ToRound3_OnFork` PASS, 2 passed / 0 skipped, gen1 → relaunch → gen2 → relaunch → gen3 plus perp open/close/liquidate. "Relaunch eventually succeeds" holds on the native path from a realistic state. I could not break it from any state I reached (see §3).

## 3. REFUTATIONS (attacked hard, held)

1. **Unclosable perp survivor bricks relaunch forever.** `hook.forceClosePerps()` is deliberately *not* try-wrapped and ends `if (openCount() != 0) revert PerpsOpen();` (CauldronHook.sol:1961), so one position that can never be settled would revert every future `relaunch()`. Attacked three ways. (a) **Hostile trader recipient:** `_settle`'s payout goes through `_payOut` → `_tryPush` (PerpEngine.sol:2084, :2106), which does a 30k-gas-capped `call` and *credits* `payoutOwed` on failure instead of reverting. Held. (b) **Death-band on the wrong side of spot** (would make v4 revert `PriceLimitAlreadyExceeded`): `PerpSwapLib._band` (PerpSwapLib.sol:359-372) returns `sp - 1` / `sp + 1` whenever the band is already passed, so the limit is never on the wrong side — it fills nothing instead of reverting. Held. (c) **Deadlock between the two death tests:** `PerpEngine._isDead` (:1797) resolves to `hook.isDead(registry.generationPoolId(gen))`, byte-identical to relaunch's own gate at Registry:833, so `_deadPrep` cannot refuse a book that relaunch is entitled to close. Held. Book bounded at `MAX_OPEN_POSITIONS = 64` < `FORCE_CLOSE_MAX = 96` (PerpEngine.sol:198, :201), and `_rebook` is suppressed in `MODE_DEATH` (`:1682`), so one call drains it.
2. **Next-generation PoolKey squat.** `_afterInitialize` `require(sender == registry)` (CauldronHook.sol:636) plus the fact that every `initialize` in the tree lives in the delegatecalled `PoolOps` library (`:282, :358, :533, :943`) means no third party can open a pool naming this hook. `openOrAddPair` re-throws a genuine refusal rather than swallowing it (`if (live == 0) revert PoolInitRefused();`, PoolOps.sol:947). Held.
3. **Orientation inversion at adoption.** `quoteIsCurrency0[id] = allowedQuote(currency0)` (CauldronHook.sol:654) is correct for both orderings because the iteration token is never allowlisted, and `setAllowedQuote` refuses any quote at or above `QUOTE_WATERMARK` (Registry:314 ff.) so the mined token always sorts above. Held.
4. **Cross-denomination sum at teardown.** `RedemptionExt._recoverLegs` (:869) matches on `Currency.unwrap(generationPoolKey[gen].currency0)`, *not* `generationQuote[gen]`, so a completed rotation cannot add 6-decimal USDG into the 18-decimal `ethRecovered` that `_removeLiquidity` (Registry:1558) feeds to `seedFunding`. Held.
5. **A stale/lapsed price feed kills a live generation.** `_toUsd` returns 0 on failure and nothing is recorded (CauldronHook.sol:1552-1561), which would let a 24h feed outage make `isDead` true. But `QuoteOracle.cachedUsdPerRawUnit` (:—, the body quoted below) never zeroes a factor it once had:
   `if (c.factor != 0 && block.timestamp <= uint256(c.triedAt) + TTL) return c.factor;` … `if (fresh > 0) { c.factor = fresh; … } return c.factor;`
   A lapsed feed keeps returning the last good factor, so volume keeps recording. Fails **alive**. Held (the never-priced case is Lead L3).
6. **Proposal strings OOG the rebirth past `markConsumed`.** `CauldronGovernor._propose` bounds `name`/`symbol`/`baseURI`/`website`/`socials`/`logo`/`banner` (`:507-521`, `MAX_NAME_BYTES = 64`, `MAX_SYMBOL_BYTES = 16`, `MAX_URI_BYTES = 256`) and rejects a non-contract renderer. Held (see Lead L4 for the governor-swap gap).
7. **Bench flooding erases a voted treasury mandate.** `TreasuryGovernor._benchRecord` (:551-577) orders eviction lexicographically as *unprotected before protected, then fewer votes*, and `_executable` entries are protected — so eight open filings cannot push a settled, passed mandate off all eight slots. Any genuinely passing proposal has `forVotes >= quorum`, which strictly exceeds any spam that fails quorum, so it always out-weighs the weakest unprotected slot. Held.

8. **Sibling cap is an off-by-one / half-linked-graph bug (L6, closed).** `_addSibling` reverts at `MAX_SIBLINGS = 9` (CauldronHook.sol:1723) and `linkVolume` grows the *secondary*'s list inside its loop before it ever touches the primary's (`:1709-1715`), so I expected the real ceiling to land below 9 or to leave a partially-linked graph. Measured off-chain against the production hook bytecode: the ceiling is exactly the documented one — legs 1..9 link, **leg 10 is the first refused** — and the refusal is atomic (the whole `linkVolume` reverts, so `rotateSliceFrom` reverts the whole slice; no half-linked state is observable). Retrying the refused leg still fails, which is correct-but-permanent: CauldronHook.sol:1729 states there is deliberately no `unlinkVolume`, so a generation that reaches nine linked pools can never open a tenth leg for the rest of its life. That is a bounded, documented design limit, not a defect. PoC: `test/attacks/R4B_SiblingCap.t.sol` — VERIFIED under `-vv`:
```
[PASS] test_positive_earlyLegsLink()             first failure linking 3 legs (0 = none): 0
[PASS] test_attack_legCeilingIsAOneWayRatchet()  first leg index that could not be linked: 10
                                                 retry of the refused leg succeeded? false
```
**Low (hygiene), no separate finding:** the cap reverts with `OnlyRegistry()` (CauldronHook.sol:1723) — a borrowed selector chosen for bytecode reasons. An operator whose rotation slice fails at the tenth leg will read "not the registry" and look in entirely the wrong place.

## 4. LEADS (HYPOTHESIS — next step named)

- **L1 — rotated treasury leaves the autonomous cycle at rebirth.** `RedemptionExt._recoverLegs` books any leg whose quote differs from the primary's `currency0` to `legProceeds[l.quote]` (`:912`), and the only exit is `sweepLegProceeds(address,address) external onlyOwner` (RedemptionExt.sol:964; registry stub at CauldronRegistry.sol:306). After a completed 10,000-bps migration mandate the majority of the generation's LP is in those legs, so the newborn is seeded from the residual tail plus reserves and the rest becomes owner-discretionary. The behaviour is documented at Registry:300-307, so it is a design choice rather than a defect — but it contradicts "self-funding, permissionless rebirth". *Next step:* a fork PoC that runs an ETH→USDG migration to `migrationMandateSpent()`, relaunches, and asserts `legProceedsOf(USDG) > 0` while `totalETH` came only from the ETH residual. Measure the ratio.
- **L2 — death-band zero-fill transfers a long's whole equity to the LP.** In `MODE_DEATH` a long sells with `band = _band(mark, sp, false)`; when spot has moved past the band (`r <= sp`) the limit is `sp + 1` and the sell fills ~nothing, so `proceeds == 0`, `_writeOffTok(id, p.size, true)` keeps the token as engine inventory and `_replenishPlv(p.principal)` drains insurance (PerpEngine.sol:1643-1665, PerpSwapLib.sol:365-370). *Next step:* on a fork, open a long, dump the token to push sqrtPrice above `mark * 1.054093`, then call `forceCloseAllDead()` and measure trader residual vs. insurance drawdown. Price whether the dump+rebuy round trip is cheaper than the equity captured.
- **L3 — a quote that was *never* priced records zero volume forever.** `_toUsd` returns 0 when `cachedUsdPerRawUnit` has no factor at all (CauldronHook.sol:1557-1560), so with `quoteOracle` wired but no feed for the live quote, `getVolume24h` stays 0 and `isDead` is true from `lastSummonAt + minLifetime` onward — a permissionless kill of a healthy generation. `TreasuryGovernor._requirePriceable` covers rotation destinations, but nothing covers the **genesis/native** quote at summon. *Next step:* deploy the off-chain rig with `quoteOracle` set and no native feed, swap, assert `getVolume24h == 0` and `isDead == true`. Then confirm against `deploy/` whether a native feed is mandatory.
- **L4 — the registry re-clamps `nftSupply` and `specQuote` "so it survives a governor swap" (Registry:1043-1050, :951) but not the strings or the renderer.** `setGovernor` is `onlyOwner` (:585). A governor replaced with one lacking `MAX_URI_BYTES` re-opens the OOG-past-`markConsumed` brick. *Next step:* decide whether a length clamp belongs at Registry:1044 alongside the supply clamp; measure the EIP-170 cost.
- **L5 — `linkVolume`'s perp gate is a rotation hostage when `markSource` is unarmed.** `RedemptionExt.rotateSliceFrom` calls `linkVolume` unconditionally (`:472`), and `CauldronHook.linkVolume` reverts `PerpsOpen` when `IPerpOpenCount(perpEngine).blocksVolumeLink()` (`:1670`). `blocksVolumeLink` (PerpEngine.sol:1856) is `openCount != 0 && markSource == address(0) && !twapTick().ok`. A rotation that drops `markSource` (PerpEngine.sol:1424 ff.) followed by a TWAP reset puts the engine in exactly that state. *Next step:* on a fork, complete a rotation (which drops `markSource`), open one minimum perp, and try `rotateSliceFrom` — if it reverts for the 30-day `ENVELOPE_LIFETIME` and `COOLDOWN` blocks the replacement, that is a cheap High.
