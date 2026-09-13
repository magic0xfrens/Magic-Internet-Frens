# V1 — Subsystem 1 (core pool) verification

Blind copy: `/tmp/blind-final-v1/contracts/solidity` (rsync of `/tmp/blind-final`, plus the single
hunter PoC `test/attacks/K1a_StaleVolumeKeepsAlive.t.sol`). Nothing else read from the live repo.

## K1a — "24h volume window never expires on an exact-86400s same-bucket ping"

**Verdict: CONFIRMED at High — VERIFIED.**

### What I ran

```
cd /tmp/blind-final-v1/contracts/solidity
FOUNDRY_PROFILE=cauldron forge test --match-path 'test/attacks/K1a*' -vv
```

```
Ran 1 test for test/attacks/K1a_StaleVolumeKeepsAlive.t.sol:K1a_StaleVolumeKeepsAlive
[PASS] test_K1a_staleBucketBlocksRelaunchForever() (gas: 701243)
Logs:
  elapsed_seconds: 2592000
  volume24h_reported: 10000000000000000030
Suite result: ok. 1 passed; 0 failed; 0 skipped
```

Vacuity checks:
- `grep -n "return;\|vm.skip"` on the PoC: **no matches** (the only `return` is the implicit
  end of the internal helpers; the top-level `test_*` has none).
- Both `emit log_named_uint` lines printed, and they sit at `:121-122`, i.e. *above*
  `assertEq(elapsed, ...)` `:123`, `assertGe(volAfter, 10 ether)` `:124`, `assertTrue(aliveAfter)` `:128`
  and `assertTrue(controlDead)` `:117`. The logs prove control flow reached the assertion block; the
  green result proves all four passed.
- Warp actually takes effect: the PoC uses `vm.getBlockTimestamp()` (`:79`, `:93`) rather than
  `block.timestamp`, and the **positive liveness control** `_controlDiesAfterOneDay()` (`:67-83`)
  asserts a second pool with a 10 ETH swap *does* read `isDead == true` after `+86_401`. A warp that
  did not take would have failed `assertTrue(controlDead)`.

### Falsification attempt (the one-line change that should break it if the mechanism is wrong)

I copied the PoC to `K1b_Falsify.t.sol` changing only `t += 86_400` → `t += 86_401` (and relaxing the
`elapsed` equality so the volume assertion is the one under test):

```
[FAIL: stale 30-day-old volume still counted: 1 < 10000000000000000000]
```

With one extra second per ping the reported 24h volume collapses to `1` wei. The mechanism is exactly
the one claimed: the strict `>` comparison at the day boundary, not something incidental.

### The code (quoted before characterised)

`contracts/solidity/CauldronHook.sol:1553-1581`:

```solidity
    function _recordVolume(PoolId id, uint256 amount) private {
        uint256 currentBucket = _getCurrentBucket();
        uint256 lastBucket = _lastBucketIndex[id];
        uint256 lastTs = _lastUpdateTs[id];

        if (block.timestamp > lastTs + SECONDS_PER_DAY) {
            for (uint256 i = 0; i < HOURS_PER_DAY; i++) {
                _volumeBuckets[id][i] = 0;
            }
        } else if (currentBucket != lastBucket) {
            ...
        }
```

`CauldronHook.sol:1583-1584`:

```solidity
    function getVolume24h(PoolId id) public view returns (uint256 total) {
        if (block.timestamp > _lastUpdateTs[id] + SECONDS_PER_DAY) return 0;
```

`_getCurrentBucket()` is `(block.timestamp / SECONDS_PER_HOUR) % HOURS_PER_DAY` (`:1678-1679`), so a
ping exactly 86400s later lands in the **same** ring index: the `else if` at `:1562` is false and the
`if` at `:1558` is false at exactly `+86400`. Zero buckets are cleared, `_lastUpdateTs` is bumped
(`:1578`), and the ancient bucket survives another day.

**Load-bearing line: `CauldronHook.sol:1558` (mirrored by `:1584`) — the strict `>`.** The same-bucket
skip at `:1562` is correct on its own: it is only reachable with a >1h gap when the delta is *exactly*
86400, and every such case is supposed to have been swallowed by `:1558`. Changing `>` to `>=` on
both lines closes the whole hole (delta 86400 then clears; delta <86400 with an equal bucket index
implies <1h, which is genuinely inside the window). This is an off-by-one, not a design flaw in the
ring.

### Reachability

`CauldronRegistry.sol:833`:

```solidity
        if (!hook.isDead(oldPoolId)) revert TokenStillAlive();
```

`isDead` (`CauldronHook.sol:1656-1675`) is `getVolume24h(primary) + Σ siblings < deathThreshold`.
`relaunch()` (`CauldronRegistry.sol:821-838`) is `external`, no role gate — it is the permissionless
rebirth promise, and it is the only caller of `isDead` in the registry (grep: one hit). So a pinned
`getVolume24h` suspends the core promise for everybody. Reachable from a fresh deploy: the PoC's
`setUp` only adopts a pool via `afterInitialize(registry, …)`, the same path the registry uses.

### Counter-arguments tried

1. **Another death trigger / rescue path?** grep for `TokenStillAlive` → one site
   (`CauldronRegistry.sol:833`). grep `isDead(` outside tests → the registry gate, the perp engine's
   own `_isDead`, and the pluggable `IDeathChecker`. There is **no time-since-launch or
   volume-independent death trigger**: `minLifetime` (`CauldronRegistry.sol:838`) is an *additional*
   gate (`TooYoung`), and `NoProposal` (`:841`) is another. Both make relaunch *harder*, never easier.
   The only escape is `CauldronHook.setDeathChecker` (`:1935-1937`), gated
   `msg.sender != registry && msg.sender != owner()` — owner is the emergency multisig behind the
   timelock. So a **role-gated, timelocked rescue exists**: the owner can install a checker that
   returns `dead`. That is what keeps this off Critical (not a permanent brick) — but it needs a
   privileged, announced action, which is the definition of High, not Medium.
2. **Does a wei-sized ping really register?** `CauldronHook.sol:839-843` — the only gate is
   `if (absVolume > 0)`, after `_toUsd(...)`. No minimum swap size, no fee floor, no surtax on the
   record path; grep for `MIN_SWAP|minSwap` in the hook returns nothing. The one real friction is
   `_toUsd`: with an oracle wired, 1 wei can truncate to 0 USD and be skipped — so on a USD-quoting
   deployment the attacker must ping with a dust amount large enough to round to ≥1 unit. Still dust.
   Cost per day is one dust swap's gas, orders of magnitude below the ~1 ETH `deathThreshold` swap
   the honest keep-alive would need. The economic counter-argument fails.
3. **Must the attacker hit the same second every day?** Yes, or drift *earlier*. The condition is
   `sameBucket && delta <= 86400`; if the previous ping was at second `s` of hour `H`, the next must
   land in hour `H` at second `s' <= s`, and the budget shrinks monotonically. This is a real
   practical constraint but a weak defence: starting at `s = 3599` and drifting a block (~12s) per
   day gives ~300 days before the window collapses, and one threshold-sized swap resets `s` to the
   top of a fresh hour. So the suspension is sustainable at roughly "one real swap per year plus
   dust gas per day". I could not turn this into a refutation.
4. **Severity, argued both ways.** *For Critical*: `relaunch()` is permissionless, the suspension is
   indefinite and costs the attacker almost nothing, and holders of the old generation are stranded
   in a token that can never be reborn. *Against Critical*: no funds move or are locked (the old
   token stays fully transferable — `CauldronRegistry.sol:845-847`), the suspension lasts only as
   long as the attacker keeps paying, and a timelocked owner action (`setDeathChecker`) breaks it.
   That is "partial / recoverable-with-a-role" → **High** is the honest tier. Confirmed at the
   hunter's severity, neither upgraded nor downgraded.

Artifacts left in the blind copy only: `/tmp/blind-final-v1/contracts/solidity/test/attacks/K1b_Falsify.t.sol`.

## Lead triage (DERIVED, no PoC)

**L2 — `_getHolderTaxRate` uncapped.** `CauldronHook.sol:1686-1694` returns the NFT contract's
`getHolderTaxRate(holder)` verbatim, with no clamp — while the fallback setter `setDefaultTaxBps`
(`:1698-1699`) *is* capped at `MAX_TAX_BPS`. So a rate of 0 (zero-fee wash-mint) or an absurd rate is
whatever the NFT says. **Gate: `nftContract` is `address(0)` on the deployed path** —
`deploy/DeployLaunchpad.s.sol:158-164` passes `address(0)` as the third constructor arg, which is
`_nftContract` (`CauldronHook.sol:560-569`), so `:1687` short-circuits to the capped `defaultTaxBps`.
Only `setNftContract` (`:1963`, `onlyOwner`) can arm it. **Dormant; owner-gated; Low as deployed**,
but the missing clamp at `:1690` is a real hardening item for the day the NFT is wired.

**L3 — `linkVolume` cap.** Constant `MAX_SIBLINGS = 9` (`CauldronHook.sol:773`); the gate is
`if (sib.length >= MAX_SIBLINGS) revert OnlyRegistry();` (`:1644`) — note it reverts with a
*misleading* selector. `RedemptionExt.sol:473` calls `linkVolume` unconditionally inside the rotation,
so the 10th distinct sibling pool makes the **entire rotation call revert**, not just the link. grep
for `unlink|delete _volumeSiblings|sib.pop` in the hook: **no matches** — there is no way to remove a
sibling, so within a generation the 10th rotation is permanently unavailable (the mapping is keyed by
the primary `PoolId`, so a relaunch does start fresh). Note the link is idempotent (`:1645-1647`), so
re-rotating into an *already-linked* pool is fine; only the 10th *distinct* pool bricks. **Medium-ish,
DERIVED, not PoC'd.**

## Discards

0. One finding examined, one confirmed. No claims discarded, none left NOT VERIFIED.
