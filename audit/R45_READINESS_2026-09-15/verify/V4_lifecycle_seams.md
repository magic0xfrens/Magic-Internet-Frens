# V4 — lifecycle seams (R4A seed-funding strand, R4B sibling cap)

## R4A — VERDICT: CONFIRMED, severity MEDIUM (as reported)

**Evidence (VERIFIED, ran):** `forge test --match-path 'test/attacks/R4*_*.t.sol' -vv` → 3/3 pass in
R4A, assertion logs observed:
`attack: quoteUsed 0x0`, `attack: seeded 10000000000000000000`,
`attack: usdg moved to registry 673940063`, `attack: usdg left on hook 0`;
and `registry-held USDG never re-entered the cycle 673940063`.
`grep -n "return;\|vm.skip"` on both PoCs: the only hit is R4B_SiblingCap.t.sol:20, inside a
block comment quoting hook source — no `return;`/`vm.skip` in any `test_*` body.

### The ordering (VERIFIED by reading, contracts/solidity/cauldron/PoolOps.sol:1171-1187)

```
1171  // 1. The proposal's choice, if value already exists in that denomination.
1172  if (wantQuote != address(0) && (recovered == 0 || oldQuote == wantQuote)) {
1173      uint256 p = (oldQuote == wantQuote ? recovered : 0) + _pullAsset(hookAddr, wantQuote);
1174      if (p >= MIN_SEED_UNITS) return (wantQuote, p, 0);
1175  }
```
`_pullAsset` (PoolOps.sol:1195-1197) is a state change, not a view:
```
1195  function _pullAsset(address hookAddr, address asset) private returns (uint256 got) {
1196      try IHookReserves(hookAddr).releaseRelaunchAsset(asset) returns (uint256 g) { got = g; } catch {}
1197  }
```
Hook side (CauldronHook.sol:1824-1834) — zeroes the counter and pushes the balance to the registry:
```
1824  function releaseRelaunchAsset(address asset) external returns (uint256 amount) {
1825      if (msg.sender != registry) revert OnlyRegistry();
1827      amount = relaunchAsset[asset];
1828      if (amount == 0) revert NoETHToRelease();
1830      relaunchAsset[asset] = 0;
1831      if (!FeeRouteLib.send(asset, registry, amount, 0)) revert SendFailed();
```
So the acceptance test at :1174 runs strictly AFTER the irreversible move. The PoC's `StrandHook`
(test/attacks/R4A_SeedFundingStrand.t.sol:35-40) is a faithful mirror of those four lines
(zero-revert, zero the slot, transfer to `msg.sender`); the PoC calls the REAL `PoolOps.seedFunding`,
so the branch logic under test is production code, not a reimplementation.

Same hazard on branch 3 (PoolOps.sol:1183-1186) for `oldQuote`; branch 2's `_pullEth`
(PoolOps.sol:1202-1204) has the identical shape for native but the registry keeps spendable ETH
(see table).

### Step 4 — reader-by-reader table for a registry-held loose balance of the relaunch asset

| Reader (path:line) | Gate | What it does with a loose registry balance of the quote asset |
|---|---|---|
| `seedFunding` branch 1, PoolOps.sol:1172-1175 | internal, called from relaunch | Reads ONLY the hook reserve via `_pullAsset`; never `balanceOf(address(this))`. Next rebirth sees 0. |
| branch 2, PoolOps.sol:1178-1181 | same | `recovered + vaultSwept + _pullEth` — native only. Ignores the ERC20 balance. |
| branch 3, PoolOps.sol:1183-1186 | same | `recovered + _pullAsset(oldQuote)` — hook reserve again, not the loose balance. |
| `PoolOps._balance` PoolOps.sol:1218 (callers :986/:1000, :1245/:1258) | internal | Used only as a before/after DELTA to measure LP recovery; a pre-existing loose balance cancels out and is never spent. |
| `RedemptionExt.sweepLegProceeds` RedemptionExt.sol:963-972 | `onlyOwner` | Sends `legProceeds[asset]`, an accounting mapping — the stranded pull is never booked there, so `amount == 0` → `revert NoBalance()`. Cannot recover it. |
| `CauldronRegistry.emergencySweep` CauldronRegistry.sol:488-495 | `onlyEmergency timelocked nonReentrant` | `IERC20(token).transfer(emergencyAdmin, IERC20(token).balanceOf(address(this)))` — the ONLY path that moves it, and it pays `emergencyAdmin`, not the machine. |
| `CauldronRegistry.emergencyWithdrawLP` :485-484 | `onlyEmergency timelocked` | Transfers `generationToken[gen]` + ETH to `emergencyAdmin`; does not touch a foreign quote asset. |
| V2 migration loose-balance sweep CauldronRegistry.sol:565-573 | migration path | Sweeps `generationToken[g]` and `address(this).balance` only — an ERC20 quote that is not the gen token is left behind. |
| `CauldronHook.sweepLegacyReserve` (iface PoolOps.sol:80) | hook-side reserve | Operates on hook storage; cannot see a registry balance. |
| `rotateSlice*` / treasury rotation | registry/hook | Operate on LP/treasury positions, not on a loose registry ERC20 balance (no `balanceOf(address(this))` reader exists in CauldronRegistry.sol other than :493 and :567). |

`grep -n "balanceOf(address(this))" CauldronRegistry.sol` returns exactly two hits, :493 and :567 —
both quoted above. **No permissionless or governor-to-machine path returns the value.** (VERIFIED)

### Step 3 — reachability chain (DERIVED for end-to-end; each gate read)

`CauldronRegistry.relaunch()` CauldronRegistry.sol:821-826 is **permissionless**: `external
nonReentrant`, guarded only by `if (!summoned) revert NotSummoned();` and
`if (!hook.isDead(oldPoolId)) revert TokenStillAlive();` (:833). It reaches the single call site
`PoolOps.seedFunding(address(hook), specQuote, currency0(oldGen), ethFromLP, generationVault[oldGen])`
at CauldronRegistry.sol:1002 with exactly the shape the PoC uses. Branch 1 is entered whenever the
winning proposal names a non-native `wantQuote` and the dying pool recovered nothing
(`recovered == 0`, "a dead position with zero liquidity makes `recovered == 0` perfectly ordinary" —
PoolOps.sol:1158). It strands whenever `0 < relaunchAsset[wantQuote] < MIN_SEED_UNITS`.

This is a NORMAL outcome, not an attack primitive: a lightly-traded USDG-quoted guild accrues tens of
USDG of fee reserve (PoolOps.sol:1156-1158 says so explicitly), and any proposal naming USDG then
burns that reserve. An attacker cannot choose `wantQuote` (governance does) and gains nothing — the
value goes to the registry, not to them — but they CAN choose the *timing*: `relaunch()` is open to
anyone, so a bystander who sees the reserve sitting just under the floor can fire the rebirth before
it crosses. Frequency: **once per rebirth**, bounded by whatever has re-accrued since the last one,
not repeatable within a generation.

### Step 5 — MIN_SEED_UNITS is decimal-blind (VERIFIED, PoolOps.sol:220)

`uint256 internal constant MIN_SEED_UNITS = 777_000_000e18 >> 60;` = 777e24 / 2^60 =
**673,940,064 base units**. In an 18-decimal quote that is 6.7394e-10 tokens — dust, so branch 1
effectively always accepts and the strand cannot bind. In a 6-decimal quote (USDG, the live
manifest asset) the same constant is **673.940064 USDG**. Its safety purpose is still met in both
(it clears the `_sqrtPrice` hard floor of 42,121,254 base units cited at PoolOps.sol:1153), so it is
not a *safety* defect — it is a *magnitude* defect: the amount at risk of being stranded scales with
1/10^decimals, which is why the same code is harmless on ETH and costs up to 673.94 USDG per rebirth
under a 6-decimal quote. Secondary defect, INFO-to-LOW on its own.

### Step 6 — severity

MEDIUM. Bounded per rebirth (< 673.94 USDG under the live 6-decimal quote), no attacker profit, no
repetition within a generation, and the only recovery is `emergencySweep` — timelocked and payable to
`emergencyAdmin` rather than back to the machine (CauldronRegistry.sol:488-495). Not HIGH: nobody
else's earmarked value is taken and the loss is not attacker-directed. Not LOW: no normal path
returns it, and the branch-1 pull happens on a permissionless call.

### One-line PoC change that would falsify the mechanism

Change `uint256 amt = 673_940_063;` (test/attacks/R4A_SeedFundingStrand.t.sol:130) to
`673_940_064` (== MIN_SEED_UNITS): if the pull were conditional on the acceptance test, both
variants would behave alike; instead `assertEq(q, address(0))` at :139 fails and branch 1 returns
USDG. The hunter already shipped that as the positive control (`test_positive_fundedQuoteIsUsed`,
:115-124, seeded 800000000 in USDG). Counter-argument tried and failed: I looked for a later reader
of the loose balance (table above) and for a gate on `relaunch()` (there is none beyond
`summoned`/`isDead`).

## R4B — refutation CONFIRMED as a genuine refutation; nit CONFIRMED (Low)

VERIFIED, 2/2 pass with logs `first leg index that could not be linked: 10` and
`retry of the refused leg succeeded? false`. It carries real assertions, not a bare pass:
- `assertEq(fail, 0, "the first three legs must link")` (R4B:60) — positive control.
- `assertGt(fail, 0, "some link must fail (cap is real)")` (R4B:72)
- `assertLe(fail, 10, "cap binds at or below the tenth leg")` (R4B:73)
- `assertFalse(ok2, "a refused leg can never be linked later - no unlinkVolume exists")` (R4B:81)

So the cap binds atomically and one-way; no exploit there.

**Nit CONFIRMED (Low/Informational).** The refusal reuses an unrelated selector,
CauldronHook.sol:1723 inside `_addSibling`:
```
1722      }
1723      if (s.length >= MAX_SIBLINGS) revert OnlyRegistry();
1724      s.push(b);
```
An operator decoding `OnlyRegistry()` from a failed `linkVolume` would chase an access-control
problem that does not exist; the real cause is the sibling ceiling. Cosmetic, no value at risk.

## Tags
- R4A ordering, hook body, registry call site, reader table, `relaunch()` gate: VERIFIED (read + grepped).
- R4A end-to-end through `CauldronRegistry.relaunch()` (PoC exercises the library directly with a mirrored hook mock): DERIVED.
- R4B cap behaviour and the `OnlyRegistry()` nit: VERIFIED.

Discards: 0 (both items survived; 2 counter-arguments — a later balance reader, and a gate on
`relaunch()` — were tried and failed).
