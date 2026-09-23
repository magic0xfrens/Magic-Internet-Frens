# HANDOFF — the 38 failing tests: find out what's actually wrong, then fix it

Date: 2026-09-23. Written for a fresh session with no prior context.
Tree state: `main`, uncommitted changes present (see §6).

---

## 0. TL;DR of the task

`FOUNDRY_PROFILE=cauldron forge test` gives **850 passing, 38 failing**.

**None of the 38 is a logic failure you can see today** — every one dies before
it asserts anything, because the fork harness never booted. That is the problem:
**we do not know whether these 38 tests pass or fail on their merits.** They have
been "known failing (env)" for long enough that a real regression could be hiding
in the set and nobody would notice.

Your job, in order:

1. Boot the fork harness (§2) and re-run the 38. **Record which now pass and
   which genuinely fail.**
2. For any that genuinely fail — those are real findings. Diagnose and fix.
3. Fix the 14 tests in **Group B** (§4) that crash *opaquely* instead of
   reporting "fork not live". That is a harness defect independent of the RPC.

Do **not** "fix" a test by making it pass vacuously. See §5 — that has happened
here before.

---

## 1. How to run anything at all

**The single most common way to lose an hour on this repo:**

```bash
cd contracts/solidity
export FOUNDRY_PROFILE=cauldron    # ← NOT optional
forge test
```

The **default** profile has never built this tree. It does not skip nested lib
test trees, so it pulls in `lib/v4-periphery/lib/permit2/test/utils/PermitSignature.sol`,
which imports an OZ v4 file that `remappings.txt:6` resolves into OZ **v5**. The
output looks exactly like a corrupted submodule:

```
ERROR ... draft-EIP712.sol": No such file or directory (os error 2)
Error: Found incompatible versions: ... permit2/src/PermitErrors.sol =0.8.17
```

**It is not.** Nothing is wrong with the submodules. Set the profile.

---

## 2. Booting the fork harness

The exact values are already in `scripts/auto-deploy.sh:82-85` (Sepolia v4):

```bash
cd contracts/solidity
export FOUNDRY_PROFILE=cauldron
export FORK_RPC="<an archive-capable Sepolia RPC>"
export POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543
export POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4
forge test
```

`contracts/solidity/.env` exists (80 bytes, mode 600) — check it before asking
for a key. **If you need a new RPC key, ask the owner; do not paste one into
chat or commit one.** A previously-pasted Alchemy Sepolia key should be treated
as compromised and rotated.

Note `vm.createSelectFork` with no block number pins to *latest*, so these tests
are not reproducible run-to-run. If a failure looks flaky, pin a block before
concluding anything.

---

## 3. GROUP A — 24 tests: the gate is working as designed

These call `YBase._boot()`, which no-ops when `FORK_RPC` is unset
(`test/attacks/YBase.sol:101-104`), then **check `active` and fail loudly with a
readable message.** That is the repo convention and it is correct: a PoC that
cannot run must never report green.

| suite | n | message |
|---|--:|---|
| `S0x_RotationPerpHostage` | 4 | fork harness must be live (FORK_RPC) |
| `E1B_LiqDrainScale` | 2 | fork must be live for this regression |
| `P30_FullCascadeSolvency` | 2 | fork harness must be live (FORK_RPC) |
| `R1B_SweepWindowStarvation` | 2 | fork not active - PoC proved nothing |
| `R1C_GasFloorBypass` | 2 | fork not active - PoC proved nothing |
| `D04_RebookErasesFundingAndPenalty` | 1 | fork must be live for this regression |
| `H1B_SweepCapCertifiesUnscanned` | 1 | fork harness did not boot |
| `K5b_ProgressiveSeederUnreachable` | 1 | FORK_RPC/POOL_MANAGER/POSITION_MANAGER must be exported |
| `M1a_LiqGasBand` | 1 | fork must be live for this regression |
| `M3B_ExpiredCrystalForfeit` | 1 | fork inactive: FORK_RPC unset |
| `M4A_RelaunchSeam` | 1 | fork harness must be live |
| `M4B_RelaunchWhale` | 1 | fork harness must be live |
| `M4C_QuoteComeHome` | 1 | fork harness must be live |
| `R1A_FreeKillSlack` | 1 | fork not active - PoC proved nothing |
| `R2D_RotationPrimaryDerivation` | 1 | fork harness must be live |
| `RH2A_BookPadGasFloor` | 1 | fork harness did not boot |
| `S0x_ForceCloseGasWedge` | 1 | `vm.envString: FORK_RPC not found` |

**Nothing to fix in Group A except one nit:** `S0x_ForceCloseGasWedge` uses
`vm.envString` (hard) where every sibling uses `vm.envOr` (soft). It dies on the
env read rather than reporting the gate. Make it match its siblings.

**The real work in Group A is running them.** Boot the fork and see what
happens. Four of them (`S0x_RotationPerpHostage`) cover rotation-with-open-perps
and are directly relevant to the change described in §6 — **run those first.**

---

## 4. GROUP B — 14 tests: a genuine harness defect

These suites also call `_boot()`, but **never check `active`**. They carry on
against an unbooted harness and crash with a message that tells you nothing:

```
[FAIL: EvmError: Revert] setUp()
```

Traced (`LIQ03`, `-vvvv`): setUp constructs a contract whose constructor calls
`registry.currentToken()` on `address(0)` →
`call to non-contract address 0x0000000000000000000000000000000000000000`.

| suite | n |
|---|--:|
| `LIQ02_PreemptiveProjection` | 5 (test bodies) |
| `LIQ03_PreemptiveLiquidation` | 1 (setUp) |
| `LIQ04_CascadeStaleProjection` | 1 (setUp) |
| `LIQ04_ExactOutBypass` | 1 (setUp) |
| `LIQ04_GasStarve` | 1 (setUp) |
| `LIQ04_PrematureKill` | 1 (setUp) |
| `LIQ05_CascadeLossMechanism` | 1 (setUp) |
| `LIQ05_PrematureKillEconomics` | 1 (setUp) |
| `LIQ05_ProjectionOvershoot` | 1 (setUp) |
| `V2A_VoteFarm` | 1 |

**Fix:** give each the same explicit gate its siblings use — assert `active` with
a message naming the suite, so an unbooted run says *why*. Copy the shape from
`R1A_FreeKillSlack` ("fork not active - PoC proved nothing"), which is the best
wording in the repo: it says both what happened and what it means.

Do this **before** §2, because right now these 14 tell you nothing about
whether they would pass with a fork — and that is exactly the blind spot.

---

## 5. Rules that are not optional here

These are scars, not style preferences.

- **A PoC that returns early reports green with zero assertions.** Always re-run
  a "fixed" PoC with `-vv` and confirm the assertion output actually appears.
  Making a test pass by skipping it is worse than leaving it red.
- **A comment is evidence of intent, not of behaviour.** This repo has multiple
  comments that confidently describe behaviour the code does not have. One of
  them (`RedemptionExt.sol:~683`) caused a wrong "this can't happen" conclusion
  in the session before this one. Verify against code, then against execution.
- **Characterise from a clean worktree.** A single uncommitted line once
  produced ~27 phantom failures. Use `git worktree add /tmp/<name> HEAD`, then
  `rm -rf lib && ln -s <main-tree>/contracts/solidity/lib lib` so you don't
  re-clone submodules.
- **`via_ir` is on.** Stack-too-deep errors name no file. Keep new test locals
  under ~12 or you will break the whole tree's compile for everyone.
- **`block.timestamp` can sink past `vm.warp`** under `via_ir`. Use
  `vm.getBlockTimestamp()` and assert the warp landed.

---

## 6. What changed immediately before this handoff (so you don't misread it)

A **D-2 fix** landed in the working tree, uncommitted. It makes the perp
quote-side stake **convert** across a quote rotation instead of being written off
to the treasury.

Touched: `PerpVault.sol`, `PerpEngine.sol`, `PerpSwapLib.sol`, `QuoteRotator.sol`,
`RedemptionExt.sol`, `CauldronBase.sol`, `deploy/DeployPerp.s.sol`,
`test/functional/F12_RequoteBacking.t.sol` (new, 8 passing),
`test/attacks/X3a_QuoteRotationRedenominates.t.sol` (+2 passing).

Full write-up: `audit/STRESS_2026-09-22/REQUOTE_IMPLEMENTATION_PLAN.md`.
Design context: `audit/STRESS_2026-09-22/QUOTE_AGNOSTIC_PERPS_SCOPE.md`.

**This change did not cause any of the 38.** Verified against a clean worktree
at HEAD: `LIQ02`, `V2A` and the `setUp` reverts all fail there too. It *did*
briefly break `X3a_QuoteRotationRedenominates` (a typed `consumeRequote()` call
reverted adoption for any vault predating the feature); that was caught and
fixed via `PerpSwapLib.tryConsumeRequote`.

**Engine headroom is 86 bytes.** `CauldronRegistry` has **8**. If a fix needs
code in either, it does not fit — put it in `PerpVault` (11.1 KB free),
`RedemptionExt` (8.7 KB), `PerpSwapLib` (15.4 KB) or `QuoteRotator` (15.8 KB).
Re-measure with `forge build --sizes` before and after; do not estimate.

---

## 7. Two known-open findings, NOT in the 38

Both are real and neither is covered by any currently-passing test. If your fork
run surfaces something near them, they are probably related.

- **D-1 (High) — force-close settles the book against the pool the rotation just
  drained.** `_settle(..., MODE_DEATH, ...)` swaps through the engine's OLD
  quote. The band does not contain it: `bandLimit` is computed off a mark that
  reads *the same drained pool*, so the bound travels with the damage. The short
  leg charges the overspend to stakers (`_absorbPlvLoss`), and past `plv` it
  becomes `unabsorbedEth`. Nothing sizes a rotation slice against open OI.
  `P30_FullCascadeSolvency` and `S0x_RotationPerpHostage` are the nearest tests
  — **both are in the 38.**

- **Testnet venue is seeded 95% out-of-band.** `DeployLaunchpad.s.sol:935`
  puts only `venueEth / 20` in the tradeable band. With `VENUE_ETH=0.3 ether`
  that is **0.015 ETH**, against a rotation slice of 0.2474 ETH — 16x the depth.
  Any *live* rotation retest measures this seeding artifact, not the protocol.
  Re-seed with a wide open band before drawing conclusions on-chain.

---

## 8. Definition of done

- A table: each of the 38 → `passes on fork` / `genuinely fails` / `still gated`.
- Group B crashes replaced with explicit gates naming the suite.
- Any genuine failure diagnosed with file:line and either fixed or written up
  with a severity and a reproduction.
- `forge build --sizes` before/after, with PerpEngine still under 24,576.
- No test made to pass by weakening or skipping its assertions.
