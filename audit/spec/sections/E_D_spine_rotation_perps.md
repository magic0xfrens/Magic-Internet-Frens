# Spine — Denomination Totality across rotation (areas D + E)

Orchestrator-owned section. Every line number below was read in the working tree
on branch `fix/b05-b07-relaunch-totality`, after the mid-session edits of
2026-09-10 20:14 (see `## Provenance`).

---

## S1. Where a generation's denomination actually lives

Three separate slots claim to answer "what asset is this generation in?".

| Slot | Declared | Written by | Read by |
|---|---|---|---|
| `generationQuote[gen]` | `cauldron/CauldronBase.sol:332` (slot 49) | `CauldronRegistry.sol:924` (relaunch) **and** `cauldron/RedemptionExt.sol:413` (completed rotation) | `RedemptionExt.sol:323`, `PerpEngine.sol:985` |
| `PerpEngine.quote` | `cauldron/PerpEngine.sol:170` | `cauldron/PerpEngine.sol:1027` — **the only write in the file** | `PerpEngine._key():450`, `_quoteIsNative():173` |
| `CauldronHook._feeAsset` | `CauldronHook.sol:661` (transient) | `CauldronHook.sol:1423`, from the live `PoolKey` | fee routing, `CauldronHook.sol:1166-1318` |

`generationQuote` is the record of intent; `PerpEngine.quote` is what the perp
engine actually trades against; `_feeAsset` is derived per-swap from the pool
that is executing, so it needs no synchronisation and has none.

**INTENT/ACTUAL DELTA (documentation).** `CauldronHook.sol:1499` states
"`PerpEngine._key()` is built from `generationQuote[gen]`". It is not.
`PerpEngine._key()` reads the engine's own `quote` storage slot
(`PerpEngine.sol:450`, `address q = quote;`). The two are equal only immediately
after `syncGeneration` and diverge for the whole window described in S3. The
comment describes the intended invariant, not the code.
CLASS: `DEVIATES` (comment vs code) · low impact alone, but it is the reasoning
the P-1 interlock below is justified on.

---

## S2. The P-1 interlock — rotation and perps are mutually exclusive

`RedemptionExt.rotateSlice` must register the destination pool as a volume
sibling, or splitting liquidity would read as the generation dying
(`RedemptionExt.sol:372`, `IHookVolume(address(hook)).linkVolume(...)`).

`CauldronHook.linkVolume` refuses while any perp position is open:

```
CauldronHook.sol:1516-1520
function linkVolume(PoolId primary, PoolId secondary) external {
    if (msg.sender != registry) revert OnlyRegistry();
    if (perpEngine != address(0) && IPerpOpenCount(perpEngine).openCount() > 0) {
        revert PerpsOpen();
    }
```

This is deliberate and documented (`CauldronHook.sol:1498-1515`, "audit P-1"):
a generation may run several pools **or** it may run perps, not both, because
the mark reads the primary pool's `slot0` (`PerpEngine._sqrtP():456`) and a
primary that has lost its liquidity to a sibling is the cheap one to push.

CLASS: `CONFORMS` — the guard exists, is enforced on the only path that creates
a sibling, and matches its stated intent.

### Consequence for the audit's Journey 4 — NOT CONSTRUCTABLE AS SPECIFIED

The brief asks for: *"iteration on ETH, perp positions open, dividends accrued,
floors funded → proposal names USDG → rotateSlice streams it."*

That journey cannot be built. With any position open, the first `rotateSlice`
reverts `PerpsOpen()` before moving liquidity. Journey 4 is only constructable
with `openCount == 0`. This is a finding about the SPEC, not the code: the
protocol deliberately forbids the combination the journey assumes.

---

## S3. THE GAP — the post-rotation window (headline)

The interlock protects the *moment* of rotation. It does not protect the window
after it.

**Reachable sequence, all steps permissionless unless noted:**

1. Generation is alive on ETH. `openCount == 0` (required, per S2).
2. Governance approves an envelope; `rotateSlice` runs to exhaustion. On the
   final slice `RedemptionExt.sol:411-415` flips
   `generationQuote[gen] = toQuote` (USDG). Liquidity is now principally in the
   USDG pair; the ETH pair retains only what was never converted (a full
   30,000-bps envelope converts ~96.85%, per `useTreasuryRotation.ts:39-41`).
3. `PerpEngine.quote` is still `address(0)` (ETH). Nothing has re-pointed it —
   `PerpEngine.sol:1027` is the only writer and it lives inside
   `syncGeneration`.
4. **A trader opens a position.** `_guardOpen` (`PerpEngine.sol:1210-1214`)
   checks exactly three things — warmup, `_isDead()`, leverage bounds. It does
   **not** compare `quote` against `registry.generationQuote(...)`:

```
PerpEngine.sol:1210-1214
function _guardOpen(uint8 leverage) internal view {
    if (block.timestamp < registry.lastSummonAt() + warmup) revert NotWarm();
    if (_isDead()) revert TokenDead(); // no leverage into a death
    if (leverage < 1 || leverage > maxLeverage()) revert BadLeverage();
}
```

5. Now `openCount > 0`, so `syncGeneration` reverts `PositionsOpen()`
   (`PerpEngine.sol:987`). The engine is **pinned** to the drained ETH pool.
6. It cannot be freed by force: `forceCloseDead` and `forceCloseAllDead` both
   require `_isDead()` (`PerpEngine.sol:937`, `:950`), and the generation is
   alive. Only voluntary closes by every trader, or a real death, clear it.

**What the engine does while pinned.** `_key()` → the ETH pool, so `_sqrtP()`
(`:456`), the TWAP ring, `_currentTick()`, `_quoteMark` → `_underwater`
(`:1042-1061`) and `activeEthDepth()` all read the pool the rotation drained.
That is precisely the hazard `CauldronHook.sol:1504-1508` names: the thin pool
is cheap to push while the deep sibling sets the real price, and liquidations
fire from inside `afterSwap` against a mark the market does not agree with.

**Why `_isDead()` does not save it.** `isDead` sums the primary and its linked
siblings, and step 2 linked them — so the generation reads healthy and step 4's
`_isDead()` check passes.

CLASS: `DEVIATES`
DENOM: `breaks-on-transition` — ETH → USDG, in the window between the final
slice and the first `syncGeneration`.
IMPACT: a trader can re-pin the perp engine to a drained pool and hold it there;
marks, funding and liquidations then run off a price that is cheap to
manipulate. Collateral of positions opened in this window is taken and
accounted in the OLD asset while the generation's record says the new one.
REPRO: not yet constructed as a Foundry journey — requires a full fork rotation
to exhaustion. The reachability is established from the call graph above.

### Recommended fix (NOT yet applied — see the size blocker)

Refuse to open while the engine's quote is stale, forcing the permissionless
`syncGeneration` (callable, since `openCount == 0` at that instant) to run
first:

```solidity
// in _guardOpen
if (quote != registry.generationQuote(registry.currentGeneration())) revert StaleQuote();
```

This closes the window without re-denominating anything: it does not touch open
positions, and `syncGeneration` already refuses to switch under them
(`PerpEngine.sol:1026`).

⚠️ **BLOCKER — EIP-170.** `PerpEngine` measures **24,541 bytes, 35 bytes of
runtime margin** (`FOUNDRY_PROFILE=cauldron forge build --sizes`, this tree).
Two external calls plus a custom error will not fit. Landing this fix requires
reclaiming bytecode from `PerpEngine` first, which is a separate change with its
own blast radius. Surfaced rather than forced in.

---

## S4. Reachability of the rotation API (area E)

`CauldronRegistry` declares `receive()` (`:508`) and **no `fallback()`** —
verified against the compiled ABI (`fallback entries: []`). Facet functions are
reached only through explicit `_forwardToExt` stubs (`CauldronRegistry.sol:1368`).
Two comments claim otherwise and are wrong: `CauldronRegistry.sol:1695` ("the
fallback delegatecalls any unknown selector to the facet") and
`CauldronBase.sol:426`.

| `RedemptionExt` entrypoint | Routable | Status |
|---|---|---|
| `redeemOgFren` / `buyTreasuryOgFren` / `donateToReserve` / `materializeLegacyReserve` | yes | stubs at `:1309`–`:1327` |
| `setRotationWiring` | yes | `:242` |
| `rotateSlice(uint16,uint256,PoolKey)` | yes | `:235` |
| `floorClaimableNow` / `legCount` / `legAt` | yes | **fixed this session** at `:1344`–`:1354` |
| `rotateSliceFrom(uint8,...)` | **was NO** | **fixed this session** — see below |
| `completeRotation` | no | `DEPRECATED-PRESENT`, superseded dead code |
| `recoverLegs` | no | correct — internal-only, called by selector at `:1490` |

**`rotateSliceFrom` (fixed).** It had no stub, so the multi-leg rotation that
`RedemptionExt.sol:307-318` calls the entire point of `fromLeg` — merging legs,
rebalancing between them, moving USDG→anything instead of only ever draining the
original quote — had no reachable path. Worse, it is the ONLY write the shipped
treasury UI issues for a rotation (`src/hooks/useTreasuryRotation.ts:290` calls
`rotateSliceFrom` for every slice, **including the default `fromLeg = 0`**), so
the rotate button reverted on every press. Fixed by adding the forwarder.

This is the **third** instance of this defect class in this contract pair, after
`setRotationWiring` (recorded at `RedemptionExt.sol:215-227`) and the three views
above. A facet function is only real once BOTH halves exist.

**A catch-all `fallback()` is the wrong fix** and was rejected: it would make
`recoverLegs(uint256)` externally callable by anyone, and that must stay internal.
Pinned by `test/functional/F20_FacetReachability.t.sol`.

---

## Provenance

`contracts/solidity/CauldronRegistry.sol` was edited by the author at
2026-09-10 20:14, mid-audit, adding the `floorClaimableNow` / `legCount` /
`legAt` stubs (+40 lines) and re-pointing two tests. Findings above are stated
against the tree AFTER that edit. An earlier draft of this section, written
against the pre-edit tree, correctly reported those three as unreachable — the
live revert is preserved in the F04 trace and in
`test/functional/F20_FacetReachability.t.sol`.
