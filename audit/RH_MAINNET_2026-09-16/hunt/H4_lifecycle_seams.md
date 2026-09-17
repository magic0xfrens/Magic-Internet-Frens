# H4 — Lifecycle seams (relaunch / rotation / denomination / adoption / PoolKey)

Blind tree: `/tmp/rh-blind-h4`. PoCs: `test/attacks/M4{A,B,C,D}_*.t.sol` (all 4 PASS on the
Sepolia v4 fork). Copies in `audit/RH_MAINNET_2026-09-16/poc/h4/`.

---

## 1. Model from code

**Lifecycle state machine (derived).**
`summon()` (CauldronRegistry.sol:722, permissionless-with-value) → gen 1, `generationQuote[1]`
stays `address(0)` (:748). `relaunch()` (:821, **permissionless**, `nonReentrant`) gates on
`hook.isDead(oldPoolId)` (:832) → `lastSummonAt + minLifetime` (:837) → `governor.hasProposals()`
(:841). It then: force-closes perps (`_perpHousekeep(false)`, :855); `_removeLiquidity(oldGen)`
(:1606 — active + reserve positions, seeder teardown, and a delegatecall to
`RedemptionExt.recoverLegsAtTeardown`, :1663); burns recovered tokens (:866); `_deployToken`
(:1680 → `PoolOps.deployTokenAbove`, :753, **CREATE2** with `salt = keccak256(abi.encode(gen,i))`
mined above `QUOTE_WATERMARK = 0xf000…`, PoolOps.sol:718); `PoolOps.seedFunding` (:1002); then the
one-way line `if (totalETH == 0) revert NoLiquidityToSeed(); governor.markConsumed(winId);`
(:1034-1035) followed by `generationQuote[newGen] = specQuote` (:1036) and `_seedGeneration`
(:1757 → `_greenCandle`, PoolOps.sol:519).

**Adoption gate.** `CauldronHook._afterInitialize` (:635) — `require(sender == registry);` (:643).
Every `initialize` naming this hook must come from the registry, so the (publicly derivable) next
PoolKey is **unsquattable**. `quoteIsCurrency0[id]` is set from `allowedQuote(currency0)` (:657);
`allowedQuote[address(0)] = true` at CauldronRegistry.sol:181, and `setAllowedQuote` refuses any
quote `>= QUOTE_WATERMARK` (:326), so orientation (`quote = currency0`) is an invariant.

**Rotation.** `RedemptionExt.rotateSliceFrom` (:280, **permissionless**) reads the envelope from
`TreasuryGovernor.allowance()` (:817), re-checks `allowedQuote`, caps `sliceBps <= MAX_SLICE_BPS`
(2500, :653), takes `PoolOps.removePartial` out of `fromLeg`, converts through
`QuoteRotator.swapOnce`, redeploys via `PoolOps.openOrAddPair` (PoolOps.sol:905), links volume
(`CauldronHook.linkVolume`, :1706, registry-gated, `MAX_SIBLINGS = 9`, :783), records the leg, and
— only when `fromLeg == 0 && migrationMandateSpent()` — flips `generationQuote[gen]` (:581-582)
and re-points the perp engine.

**Asset flows.** In: `summon` value, swap fees → `relaunchETH`/`relaunchAsset[q]`
(CauldronHook.sol:1385-1386), vault donations. Out: `releaseRelaunchETH/Asset` → registry →
newborn LP; `sweepLegProceeds` (RedemptionExt.sol:964, **onlyOwner**); `emergencySweep` /
`migrateToSuccessor` (onlyEmergency + timelock).

**Cross-subsystem.** `generationQuote[gen]` has exactly **two** writers (CauldronRegistry.sol:1036,
RedemptionExt.sol:582) and is read by `PerpEngine.syncGeneration` (:1276) — the engine's only
re-point — and by `PerpEngine._isDead`. `generationPoolKey[gen]` is written **once**, in
`_recordSeed` (:1794), and never re-pointed; `seedFunding`, `_recoverLegs` and `rotateSliceFrom`
all key off its `currency0` rather than off `generationQuote`.

---

## 2. Findings

```
id: T4C   severity: Medium   confidence: VERIFIED
subsystem: quote rotation / denomination totality
cauldron/RedemptionExt.sol:371:      fromQuote = Currency.unwrap(srcKey.currency0);
cauldron/RedemptionExt.sol:381:      if (fromQuote == toQuote) revert BadConfig();
cauldron/RedemptionExt.sol:581-582:  if (fromLeg == 0 && ITreasuryGovernor(gov).migrationMandateSpent()) {
                                         generationQuote[gen] = toQuote;
cauldron/TreasuryGovernor.sol:900:   if (fromPrimary) e.movedPrimaryBps += bps;
cauldron/TreasuryGovernor.sol:855:   return e.maxTotalBps >= BPS_ONE && e.movedPrimaryBps >= e.maxTotalBps;
title: Once a generation's quote has been migrated away from its launch asset, the guild can never
       bring the DENOMINATION home; a "return to ETH" mandate reverts on every primary slice.
precondition: A completed guild-approved migration (generationQuote[gen] != launch quote).
  Reachable by exactly the supported governance flow — no attacker needed. Also reachable on
  a fresh generation, which is what the PoC executes directly.
sequence:
  1. Guild passes an envelope with `quote = <launch quote>` (native ETH) and maxTotalBps = 10000.
  2. Anyone calls `rotateSliceFrom(fromLeg = 0, sliceBps, minOut, route)` — the ONLY shape that
     advances `movedPrimaryBps` (:900) and therefore the ONLY shape that can satisfy
     `migrationMandateSpent()` (:855) and reach the flip at :582.
  3. `srcKey = generationPoolKey[gen]` is still the LAUNCH pair (never re-pointed, written once at
     CauldronRegistry.sol:1794), so `fromQuote == toQuote` at :381 → `BadConfig()`. Always.
  4. `movedPrimaryBps` stays 0 forever ⇒ `allowance()` (:817) never decrements ⇒ the envelope never
     deactivates at :902 ⇒ `propose` (:437 `if (envelope.active && …) revert ProposalActive()`)
     blocks every new treasury proposal until the envelope EXPIRES.
  Measured (M4C, -vv): destination = launch quote → 0x07cc321c `BadConfig()`;
  identical call, destination = a NEW quote → 0xaa213bcd `ReachedRotator()`. Only `toQuote` differs.
capital: none. FLASHLOANABLE n/a — this is not an attacker action, it is a governance action that
  cannot complete. Cost to a griefer who wants to wedge treasury governance: one
  PROPOSAL_THRESHOLD MiFren holding + gas, repeatable every envelope.
attacker_cost: ~0 (gas). damage: the generation's denomination is pinned at the migrated asset for
  its whole life. `PerpEngine.syncGeneration` (:1276) adopts `registry.generationQuote(gen)`, so
  after the guild rotates the LIQUIDITY home from the legs (which IS permitted — fromLeg >= 1) the
  engine still marks/funds/liquidates against the now-drained destination pool — the thin-pool mark
  the code itself flags at CauldronHook.sol:1500-1508. Plus a treasury-governance stall for the
  envelope's lifetime (30 d default) on every attempt, compounded by COOLDOWN (:438).
  Only a relaunch clears it.
poc: test/attacks/M4C_QuoteComeHome.t.sol   needs_fork: yes
```

```
id: T4E   severity: Low   confidence: DERIVED
subsystem: volume linking
CauldronHook.sol:783:   uint256 internal constant MAX_SIBLINGS = 9;
CauldronHook.sol:1760:  if (s.length >= MAX_SIBLINGS) revert OnlyRegistry();
CauldronHook.sol:1766:  //  deliberately NO unlinkVolume yet. MAX_SIBLINGS is therefore a one-way
title: The 10th distinct rotation destination in one generation makes every further rotation revert.
precondition: 9 distinct allowlisted quotes rotated into within one generation. `linkVolume` is
  registry-gated (:1707) and its only caller is `rotateSliceFrom` (RedemptionExt.sol:473, called
  UNCONDITIONALLY), so each new destination costs a governance vote — not attacker-reachable.
  `_volumeSiblings` is keyed by PoolId and every generation mints a new token, so the ratchet
  RESETS at relaunch; the lock is bounded to one generation.
capital: n/a  attacker_cost: n/a  damage: rotation disabled for the rest of one generation.
poc: none (grep-verified, not executed — DERIVED).  needs_fork: n/a
```

```
id: T4F   severity: Low   confidence: VERIFIED
subsystem: rotation → rebirth economics
cauldron/RedemptionExt.sol:913:  legProceeds[l.quote] += q;
cauldron/RedemptionExt.sol:964:  function sweepLegProceeds(address asset, address to) external onlyOwner
title: A completed migration's treasury does NOT seed the newborn; it lands in `legProceeds` and
       requires a manual owner sweep + manual redeployment.
precondition: a completed quote migration, then a relaunch. Executed end-to-end in M4D.
measured: after one 2500-bps ETH→USD migration on a 25 ETH generation, `generationQuote[1]` flipped
  to the destination asset, relaunch succeeded, gen 2 launched back in ETH
  (`generationQuote(2) == address(0)`) seeded only from the ~75% ETH residual, and the full
  18,749,999,998 destination-asset units came back through `sweepLegProceeds` — i.e. RECOVERABLE,
  but only by the owner, and by no automatic path. A full 10,000-bps mandate moves ~68% of the LP,
  so ~68% of the treasury sits outside the newborn's book after every completed migration.
  At a 1,000 ETH generation that is ~680 ETH needing a manual owner action each rebirth.
damage: no loss while ownership is live; becomes a permanent lock if ownership is ever renounced.
poc: test/attacks/M4D_MigratedTreasuryStrands.t.sol   needs_fork: yes
```

**Liveness positive controls (both PASS).**
- *Relaunch always eventually succeeds*: `M4A_RelaunchSeam` — gen 1 → 2 → 3, reserve position
  minted for gen 2 (`reserveId2 = 39412`).
- *A position can always be exited*: `M4B_RelaunchWhale` — 500 ETH buy (103.6 M tokens),
  26 h decay, relaunch lands, `claimByBurn` returns 103,600,000,000,000,000,276,266,639 against
  103,600,000,000,000,000,276,266,735 bought (96 wei of rounding, ≤ 1000 wei asserted).
- *A rotation completes or reverts whole*: `M4D` — the slice lands, the leg is opened through the
  hook's adoption gate, the flip fires, and the subsequent relaunch still succeeds.

---

## 3. Refutations (attacked hard, held)

1. **PoolKey / CREATE2 squat.** The next generation's token address IS publicly derivable
   (`PoolOps.deployTokenAbove:753` — CREATE2, `salt = keccak256(abi.encode(gen, i))`, initHash over
   public `(name, symbol, gen, registry, TOTAL_SUPPLY)`), and pending-tx calldata is public on this
   chain. But the deployer is the registry, so the ADDRESS cannot be squatted, and
   `CauldronHook._afterInitialize:643 require(sender == registry);` makes the POOL KEY
   un-initializable by anyone else. `PoolOps.openOrAddPair:948-953` re-throws `PoolInitRefused`
   rather than swallowing a hook refusal. No squat.
2. **Caller-supplied venue + minOut in the rotation.** `QuoteRotator.swapOnce:359` requires
   `allowedVenue[route.toId()]` (keyed by PoolId, not by pair), `:374` computes an oracle floor
   BEFORE the swap, `:389` reverts `NotPriceable()` when the floor is unpriceable and an oracle is
   wired, and `:393` enforces `max(minOut, floor)`. The caller can only tighten. Not a drain.
3. **Whale drain of the dying pool before relaunch.** `M4B` — 500 ETH (flashloanable many times
   over: the v4 PoolManager holds 21,218 ETH) bought out 13.3% of supply and pushed the tick to
   166,651 immediately before the rebirth. Relaunch landed and the 1:1 exit still worked.
   `newActive` is clamped at CauldronRegistry.sol:1113 and `_seedReserve` no-ops at zero liquidity
   (PoolOps.sol:840-857), so the two obvious brick shapes are both closed.
4. **`seedFunding` peek-before-pull (the 2026-09-15 code).** `_pullAsset:1224` / `_pullEth:1243`
   staticcall the real public getters (`CauldronHook.relaunchETH:300`, `relaunchAsset` mapping) and
   only fire the release when `have + peek >= MIN_SEED_UNITS` (:225, `777_000_000e18 >> 60`), so a
   short branch no longer consumes a reserve it declines. Every branch is try/catch'd and a total
   failure returns 0, which reverts `NoLiquidityToSeed` on the SAFE side of `markConsumed`
   (CauldronRegistry.sol:1034-1035). Read line by line; found no path that reverts to the right of
   `markConsumed`.
5. **Denomination mixing at teardown.** `_recoverLegs:902` matches on
   `generationPoolKey[gen].currency0`, not on the flipped `generationQuote`, so a 6-decimal leg is
   never summed into 18-decimal wei. Confirmed by execution in M4D (gen 2 seeded in ETH from the
   ETH residual; the destination asset booked separately).
6. **Secondary-leg starvation of a migration mandate.** `TreasuryGovernor.consume:893-900` meters
   primary slices against `movedPrimaryBps` and secondary slices against the shared `movedBps`, and
   `allowance:817` reports `maxTotalBps - movedPrimaryBps`. A stranger spending the shared total on
   side pools cannot reduce the primary's budget. Held.

## 4. Leads (HYPOTHESIS — exact next step)

- **L1.** `PoolOps.seedFunding` branch 1/3 call `releaseRelaunchAsset` and trust the returned `g`.
  A fee-on-transfer or partially-delivering allowlisted quote makes `p` exceed the registry's real
  balance, and `_greenCandle`'s `executeBuy` settle (PoolOps.sol:634) sits to the RIGHT of
  `markConsumed` → permanent brick. Gated only by the owner-curated allowlist.
  *Next step:* add a 1%-fee-on-transfer mock to the M4D harness, credit it into
  `relaunchAsset[q]` via a hook swap, and relaunch with `specQuote = q`.
- **L2.** `linkVolume:1735` expands to a fully-connected graph inside one call
  (`_addSibling(sib[i], secondary)` for every existing sibling). With 8 existing siblings the new
  pool's own list reaches 9 in one transaction; the 9th distinct destination therefore reverts one
  slice EARLIER than `MAX_SIBLINGS` suggests. *Next step:* drive 9 distinct allowlisted quotes
  through the M4D mock-governor harness and record which slice index first reverts.
- **L3.** `CauldronToken.burn(address(this), tokensFromLP)` (CauldronRegistry.sol:867) burns a sum
  that now includes leg-recovered tokens (`_removeLiquidity:1665`). If any leg's `removeAll` lands
  tokens the registry does not hold (hostile token, partial transfer), that burn reverts to the
  LEFT of `markConsumed` — recoverable, but it permanently blocks relaunch while the leg exists.
  *Next step:* record a leg on a hostile token and run relaunch.
