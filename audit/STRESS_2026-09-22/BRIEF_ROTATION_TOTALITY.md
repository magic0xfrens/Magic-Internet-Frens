# BRIEF — make an LP quote rotation correct for EVERY subsystem

Owner-authorised. You are working on the owner's own protocol, pre-deployment,
with permission to attack it, write PoCs, and change code.

The question this brief exists to answer:

> The community votes to move the pool's quote asset — ETH → USDG, or back.
> **Does every subsystem that counts money survive that, or does something
> silently redenominate, strand, or forfeit?**

Not "does the swap execute". It does. The question is whether the *accounting*
follows it, everywhere.

---

## 0. Tree rules — read before your first command

You share this working tree with other sessions. It has **uncommitted work in
it right now** and you can see all of it.

- **NEVER** run `git stash`, `git checkout -- .`, `git reset --hard`, or any
  bulk revert. A subagent here once destroyed another session's work by putting
  a status check and a `cp` in one command. Recovery took parsing
  `~/.claude/projects/*.jsonl` for Edit records.
- Commit **only files you touched**, by explicit path. Never `git add -A`.
- To characterise a baseline, use a worktree — never the shared tree:
  ```bash
  git worktree add /tmp/<name> HEAD
  cd /tmp/<name>/contracts/solidity
  rm -rf lib && ln -s "<main-tree>/contracts/solidity/lib" lib   # don't re-clone submodules
  ```

## 1. How to run anything

```bash
cd contracts/solidity
export FOUNDRY_PROFILE=cauldron     # ← NOT optional, and this is the #1 time sink
forge test
```

The **default** profile has never built this tree and fails with output that
looks exactly like corrupted submodules (`draft-EIP712.sol: No such file`,
`Found incompatible versions ... permit2 =0.8.17`). **The submodules are fine.**
Set the profile.

For fork tests (`scripts/auto-deploy.sh:82-85` has the values):

```bash
export FORK_RPC="<archive-capable Sepolia RPC>"
export POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543
export POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4
```

`contracts/solidity/.env` exists — check it before asking. **Never paste a key
into chat or commit one.** Ask the owner if you need one.

---

## TASK 1 — the 38 failing tests

Full detail: **`audit/STRESS_2026-09-22/HANDOFF_38_FAILING_TESTS.md`**. Summary:

`forge test` = **850 pass, 38 fail**. **None of the 38 is a visible logic
failure** — every one dies before asserting, because the fork never booted. So
nobody knows whether they pass on their merits. A real regression could be
hiding there.

- **Group A (24)** — correctly detect the dead harness and fail loudly. Just
  need running with a fork. Fix one nit: `S0x_ForceCloseGasWedge` uses
  `vm.envString` where siblings use `vm.envOr`.
- **Group B (14)** — `LIQ02`–`LIQ05`, `V2A`. These call `YBase._boot()` and
  **never check `active`**, so they crash with a useless `EvmError: Revert` in
  `setUp()` (traced: a constructor calling `registry.currentToken()` on
  `address(0)`). **Fix Group B first** — until you do, those 14 can't tell you
  anything either way.

Deliverable: a table of all 38 → `passes on fork` / `genuinely fails` / `still
gated`, and every genuine failure diagnosed at file:line.

---

## TASK 2 — rotation totality across every subsystem

This is the bigger and more valuable half.

### What is already done (do not redo — verify, then build on)

**Perps: the quote-side stake now CONVERTS instead of being written off.**
Implemented, tested, uncommitted in this tree.

- Design: `audit/STRESS_2026-09-22/QUOTE_AGNOSTIC_PERPS_SCOPE.md`
- Build log + measured sizes: `audit/STRESS_2026-09-22/REQUOTE_IMPLEMENTATION_PLAN.md`
- Tests: `test/functional/F12_RequoteBacking.t.sol` (8), plus 2 in
  `test/attacks/X3a_QuoteRotationRedenominates.t.sol`

The load-bearing insight, which generalises to every subsystem below:

> Vault share value is **derived** (`assetsEth() = engine.totalEth() -
> pendingEth()`), so live shares redenominate for free — only the pot's unit
> changes. But `pendingEth()` is an **absolute old-asset figure**. Convert one
> without the other and a 6-decimal backing has an 18-decimal claim subtracted
> from it: `assetsEth` saturates to zero, every live share is worth nothing, and
> the queue is retired as if it were a total loss.

**Generalised: for each subsystem, sort its state into (a) ratios/shares, which
survive a unit change untouched, and (b) absolute amounts, which must convert at
the SAME realized rate, atomically. Anything in (b) you miss is silent loss.**

### The map — who reads `generationQuote`

```
CauldronRegistry.sol      CauldronHook.sol        RedemptionExt.sol
PerpEngine.sol            PerpVault.sol           PerpMarkSource.sol
CauldronGachaRouter.sol   CauldronBase.sol
```

Perp* is covered. **`CauldronGachaRouter` and `CauldronHook` are not, by me.**

### Subsystems to audit, with the specific question for each

Each of these needs the (a)/(b) sort above, plus: *what happens to value already
accrued in the OLD asset at the moment of the flip?*

| subsystem | file | the question |
|---|---|---|
| **Dividends** | `MiFrensDividend.sol` | It already has dual paths: native `claim()` and `fundToken()`/`claimTokens()`. After a rotation, does the hook actually route fees via `fundToken` for the new quote, or does the guild share strand? *(Prior findings Q-01 and B-01 were exactly this shape — `routePerp` stranded non-ETH guild fees. Verify they hold on a rotated quote, not just a non-native launch.)* |
| **Collection floor** | `CauldronVault.sol`, `CollectionLedger.sol` | `floorPerNFT()` — what unit is it in? If the floor is quote-denominated and the quote rotates 1 ETH → 3000 USDG, does the floor become 3000x, or 1/3000th, or correctly rescale? Who can redeem against it in between? *(Note: the ETH vault is reportedly wired off at ~84.6% in favour of one token-denominated floor — confirm that is still true before reasoning.)* |
| **Gacha** | `CauldronGachaRouter.sol`, `GachaLib.sol` | It reads `generationQuote`. Is the mint price redenominated, and does `setOracle` follow? A 6-decimal quote with an 18-decimal price constant is a 1e12 error. |
| **Hook fees / buyback** | `CauldronHook.sol`, `FeeRouteLib.sol`, `LegacyBuyLib.sol` | Fee accrual, the buyback price bound, and `linkVolume`. **Known: the legacy buyback has 4 hardcodes and its price bound INVERTS on direction flip — the owner DEFERRED this. Confirm it is still deferred before spending time.** |
| **Treasury / governor** | `CauldronGovernor.sol`, `TreasuryGovernor.sol` | `setQuoteOracle`, proposal thresholds, the migration mandate. Are thresholds absolute amounts (b) or ratios (a)? |
| **Volume / death** | `CauldronHook.sol` | 24h volume sums across siblings. Is volume recorded in a consistent unit across a flip, or does a rotated leg record 0 / 1e12x? *(`NATIVE_PEGGED_USD` matters here.)* |
| **Seeder / reserve** | `CauldronSeeder.sol`, `ReserveLib.sol`, `PoolOps.sol` | Per-asset reserves across a flip. |

### Known-open, already diagnosed — fix or formally defer

**D-1 (High) — force-close settles the book against the pool the rotation just
drained.** `_settle(..., MODE_DEATH, ...)` swaps through the engine's OLD quote.
The band does not contain it: `PerpSwapLib.bandLimit` is computed off a mark
that reads *the same drained pool*, so the bound travels with the damage. The
short leg charges the overspend to stakers via `_absorbPlvLoss`, and past `plv`
it becomes `unabsorbedEth` — real bad debt. **Nothing sizes a rotation slice
against open OI.** Nearest tests are `P30_FullCascadeSolvency` and
`S0x_RotationPerpHostage` — both are in the 38, so this is currently unguarded.

**D-3 (Med)** — `markSource` is correctly dropped on every sync but never
re-armed, so the engine marks off its own freshly-rotated (thin, cheap-to-push)
pool exactly while the book is force-closing against it. Needs an ops step or a
re-arm path.

**Testnet venue is seeded 95% out-of-band.** `DeployLaunchpad.s.sol:935` puts
only `venueEth / 20` in the tradeable band — with `VENUE_ETH=0.3 ether` that is
**0.015 ETH**, against a 0.2474 ETH slice (16x the depth). Any *live* rotation
test measures this artifact, not the protocol. Re-seed with a wide open band
before concluding anything on-chain.

---

## 2. Hard constraints

**EIP-170 headroom, measured — re-measure, never estimate:**

| contract | free |
|---|--:|
| `CauldronRegistry` | **8 B** |
| `PerpEngine` | **86 B** |
| `CauldronHook` | 598 B |
| `RedemptionExt` | 8,750 B |
| `PerpVault` | 11,115 B |
| `PerpSwapLib` | 15,433 B |
| `QuoteRotator` | 15,845 B |

`CauldronRegistry` dispatches to `RedemptionExt` through **explicit per-selector
stubs** — with 8 bytes free, **you cannot add a new registry entry point.** Plan
around that from the start; it invalidated the first design of the perp fix.

`PerpSwapLib` and other libraries with `external` functions are **linked and
DELEGATECALLed** — putting code there costs the engine only a call site, and
`address(this)` stays the engine so `onlyX` gates still hold. That is the escape
hatch when the engine has no room.

Run `forge build --sizes` before and after. **PerpEngine must stay under 24,576.**

---

## 3. Rules that are not optional — these are scars

- **A PoC that returns early reports green with zero assertions.** Re-run every
  "fixed" PoC with `-vv` and confirm assertion output actually appears. Making a
  test pass by skipping it is worse than leaving it red.
- **A comment is evidence of intent, not of behaviour.** This repo contains
  comments that confidently describe behaviour the code does not have. One
  (`RedemptionExt.sol:~683`) claims `linkVolume` proves `openCount == 0`; it does
  not — `PerpEngine.blocksVolumeLink()` short-circuits to `false` whenever
  `markSource` is armed, **and we arm it**. That comment caused a wrong "this
  can't happen" conclusion. Verify against code, then against execution.
- **Two readings agreeing is not confirmation** if both made the same omission.
  Prefer executing the thing.
- **Characterise from a clean worktree.** One uncommitted line once produced ~27
  phantom failures.
- **`via_ir` is on.** Stack-too-deep names no file; keep new test locals under
  ~12 or you break the compile for every other session.
- **`block.timestamp` can sink past `vm.warp`** under `via_ir`. Use
  `vm.getBlockTimestamp()` and assert the warp landed.
- **Report faithfully.** If a test fails, say so with the output. If you skipped
  something, say that. Do not relay a pass you did not open and read — a
  "92 actions, 89 passed" was once relayed from a file whose `results` array was
  empty.

---

## 4. Definition of done

1. All 38 classified and every genuine failure diagnosed or fixed.
2. Group B's opaque crashes replaced with explicit gates naming the suite.
3. For **each** subsystem in the table: its state sorted into ratios vs absolute
   amounts, with a written answer to "what happens to old-asset value at the
   flip" — and a test pinning it.
4. A round-trip test: **ETH → USDG → ETH**, with perps open, dividends accrued,
   and the floor funded, asserting no subsystem stranded or forfeited value and
   `unabsorbedEth == 0` throughout.
5. `forge build --sizes` before/after; PerpEngine under 24,576.
6. Anything you choose not to fix: written up with severity, file:line, and a
   reproduction. Deferring is fine; deferring silently is not.

**Do not weaken or skip an assertion to make something green.** If a fix does
not fit in the byte budget, say so and propose where it should live instead.
