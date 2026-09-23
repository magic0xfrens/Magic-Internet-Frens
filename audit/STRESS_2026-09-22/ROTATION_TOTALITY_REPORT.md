# Rotation totality + the 38 failing tests — report

> **UPDATE, same day — D-1 FIXED, D-2 REDESIGNED.** Owner decision: rotation
> must work with a NON-EMPTY book, converting everything, positions carried onto
> the new quote. Implemented as `PerpEngine.requoteBook` (see §"Part 2" at the
> end). That supersedes the vault-driven D-2 path below: RT-1, RT-2 and RT-4 no
> longer apply (that code is gone), and RT-5 is fixed for rotations. Read Part 2
> first; Parts above it are the record of how we got there.

Date: 2026-09-23. Executes `BRIEF_ROTATION_TOTALITY.md` and `HANDOFF_38_FAILING_TESTS.md`.
Nothing committed. All numbers below were measured in this session, not carried over.

**Fork used for every fork number:** local `anvil` on :8547 forking Sepolia via
`ethereum-sepolia-rpc.publicnode.com` (the `auto-deploy.sh:18` default), **pinned at
block 11,763,300**, so runs are reproducible. (A stale anvil from Monday still holds
:8545 on a pruned block; it was left alone in case another session owns it.)

---

## TASK 1 — the 38

### Headline

- **None of the 38 is a genuine failure.** With the fork live, all 38 pass, and so
  do the **24 test bodies that were hidden** behind 9 `setUp()` reverts. So the 38
  red lines stood for 53 tests.
- **The bigger blind spot was the other way round.** Without `FORK_RPC` the suite
  runs 888 tests; with it, **1,194**. So 306 tests were reporting green without
  executing their fork path. Exactly one of them failed once the fork was live:
  `CHURN1_LiveRevert` (below).
- No early `return` ahead of assertions in any of the 27 suites. Every `return` is
  either in `setUp` behind a later `assertTrue(active/ran)`, or in a search helper
  that the assertions follow.

### Table

| suite | n (of 38) | on fork |
|---|--:|---|
| `S0x_RotationPerpHostage` | 4 | passes |
| `E1B_LiqDrainScale` | 2 | passes |
| `P30_FullCascadeSolvency` | 2 | passes |
| `R1B_SweepWindowStarvation` | 2 | passes |
| `R1C_GasFloorBypass` | 2 | passes |
| `D04_RebookErasesFundingAndPenalty` | 1 | passes |
| `H1B_SweepCapCertifiesUnscanned` | 1 | passes |
| `K5b_ProgressiveSeederUnreachable` | 1 | passes |
| `M1a_LiqGasBand` | 1 | passes |
| `M3B_ExpiredCrystalForfeit` | 1 | passes |
| `M4A_RelaunchSeam` / `M4B_RelaunchWhale` / `M4C_QuoteComeHome` | 3 | pass |
| `R1A_FreeKillSlack` | 1 | passes |
| `R2D_RotationPrimaryDerivation` | 1 | passes |
| `RH2A_BookPadGasFloor` | 1 | passes |
| `LIQ02_PreemptiveProjection` | 5 | passes |
| `LIQ03_PreemptiveLiquidation` (setUp) | 1 → 3 bodies | all pass |
| `LIQ04_CascadeStaleProjection` (setUp) | 1 → 2 | all pass |
| `LIQ04_ExactOutBypass` (setUp) | 1 → 1 | passes |
| `LIQ04_GasStarve` (setUp) | 1 → 1 | passes |
| `LIQ04_PrematureKill` (setUp) | 1 → 3 | all pass |
| `LIQ05_CascadeLossMechanism` (setUp) | 1 → 1 | passes |
| `LIQ05_PrematureKillEconomics` (setUp) | 1 → 2 | all pass |
| `LIQ05_ProjectionOvershoot` (setUp) | 1 → 2 | all pass |
| `S0x_ForceCloseGasWedge` (setUp) | 1 → 9 | all pass |
| `V2A_VoteFarm` | 1 | passes |

Genuinely fails: **0**. Still gated: **0** (all run with the fork).

### Harness fixes

- **Group B** (the 9 `LIQ0x` suites and `V2A_VoteFarm`) now `require(active, "<Suite>: fork not
  active - PoC proved nothing")` right after `_boot`. They used to crash with
  `EvmError: Revert` (a constructor calling `currentToken()` on `address(0)`).
- **`S0x_ForceCloseGasWedge`**: `vm.envString` → `vm.envOr` plus the same explicit gate.
- **`CHURN1_LiveRevert`** (not in the 38; it only failed with the fork live). It probed
  the **r44** router `0x4658…2FDa`, whose on-chain bytecode lacks `playChurn`
  (`0xdf70b5a4`, reverts after 537 gas). That is the known r43/r44 deploy-seam
  incident. The fix shipped in r45, and the r45 router in
  `indexer/deployments/round.json` (`0x16df…15b4`) has the selector. The test was
  still pinned to r44, so it kept failing as if the regression were live. It is
  now a positive check against r45 (`play` opened 5 crystals and `playChurn`
  succeeded), and fails loudly rather than vacuously without a fork.

No-fork suite after all changes: **860 pass / 38 fail**, and every one of the 38 fails
with a readable fork-gate message. Fork suite: **1,206 pass / 1 fail** (CHURN1,
before the repoint; it passes now). F14c and the repointed CHURN1 were run on their own after that full run.

---

## TASK 2 — rotation totality

### Findings

| id | sev | what | status |
|---|---|---|---|
| **RT-1** | High | The D-2 conversion **could never execute on the real engine** | **fixed** |
| **RT-2** | Critical (latent) | The window between conversion and adoption: a dust deposit mints ~all shares | **fixed** (same change) |
| **RT-3** | High | `DEPLOY_QUOTES` deploys never gave the hook/router/governor an oracle → a rotated generation reads **dead** | **fixed** (deploy script) |
| **RT-4** | High | The D-2 converter gate was wired by **no** deploy path | **fixed** (scripts) |
| **RT-5** | Medium | Engine without `quoteOracle` → `quoteUnit` is decimals-only (1 ETH ≙ 1 USDG) after rotating to a 6-dec quote | documented |
| **RT-6** | Low | Rotation-created legs inherit the launch anti-snipe surtax for 30 blocks | documented |
| RT-7 | Info | Stakers convert after the rotation has walked the venue price | measured |
| **D-1** | **High** | Force-close against the drained pool: **a solvent long is paid 0 and the short takes it** | **measured, deferred** |
| D-3 | Medium | `markSource` dropped at sync, never re-armed | deferred (unchanged) |

#### RT-1 — D-2 was dead code on the real engine

`PerpVault.requoteQuoteSide` credited the proceeds with `engine.fundFromVault` **before**
the engine adopted. `fundFromVault → _pullQuote` pulls in the engine's **current**
quote (`PerpEngine.sol:267-280`), which at that moment is still the old one:

- ETH → USDG: the vault sends no value to a native book, so it reverts `BadParam` (`:269`)
- USDG → ETH: the vault sends value to an ERC20 book, so it reverts `BadParam` (`:271`)

The rotation wraps the call in `try` (`RedemptionExt.sol:~717`), so every rotation
silently fell back to the veto or write-off that D-2 was meant to replace.

**Why the tests were green:** F12 ran the real vault against a *mock* engine whose
`fundFromVault` took any asset, and X3a ran the real engine against a *mock* vault
that only claimed a conversion happened. Each covered one half of the seam, and
nothing executed the two real contracts together.

**Proof:** `test/functional/F12b_RequoteRealEngine.t.sol` uses the real engine and the
real vault. Against the pre-fix vault (clean worktree) it goes **3/3 red, all `BadParam()`**.
With the fix it goes 3/3 green: 5 ETH → 15,000 USDG adopted in one call, ETH → USDG → ETH
returns exactly 4 ETH, and there is no residue in either asset.

**Fix (`PerpVault.sol`, +111 B):** arm the flag, call `engine.syncGeneration()`, require
that the flag was consumed, then credit. The engine now speaks the new asset when
the proceeds land. The F12 mock engine is now quote-strict and models
`syncGeneration`, so the mock cannot hide this again.

#### RT-2 — the window (closed by the same change)

Had the credit simply been made to succeed, the conversion and the adoption would
have stayed separate calls. That leaves a state where `plv` is in the new unit
while the engine still prices, pays and pulls in the old one. The window is
reachable two ways:

- via the permissionless retry, which did not sync, or
- via an owed payout, which makes `syncGeneration` revert `VaultStaked`.

Inside it, a 0.001 ETH deposit is read as 1e15 *USDG units* and mints almost every
share; the attacker then adopts and withdraws the stakers' pot. The fix makes
conversion and adoption **one transaction or neither**. Pinned by F12 `T8` and F12b
`BlockedAdoption`: with adoption blocked, nothing converts, and the attacker's
0.001 ETH ends up worth 3 USDG.

#### RT-3 — rotated generation reads dead (`DeployLaunchpad`)

Without `hook.quoteOracle`, `_toUsd` returns **raw** quote units. F14b measures it:
**$30k of USDG-leg volume records as 4.66e10 against a 1e18 threshold**, so a
generation trading 10× its threshold reads `isDead`. That is the gate on
permissionless `relaunch()`.

The `DEPLOY_QUOTES` path created its QuoteOracle inside `_deployRotationStack`, *after*
the wiring block had read `QUOTE_ORACLE` from the environment. So the oracle reached
the rotator (rotation runs) and nothing else. Fixed: the oracle is now created before
the wiring (`_deployQuoteOracle`), so the hook's volume and mint ladder, the router's
play size, the treasury governor and the rotator floor all share one oracle.
Setting `QUOTE_ORACLE` as well is refused.

**Verified by execution:** I simulated `forge script DeployLaunchpad` with
`DEPLOY_QUOTES=true` on the fork. The old script deploys `QuoteOracle 0xFa83…` and
never logs `volume denominated in USD via oracle`. The new one logs it, with the same
address as `QuoteOracle`.

*Not done:* an on-chain guard (refuse a rotation while the hook has no oracle). It
needs a hook getter (the hook has 598 B free, so it fits), but every existing rotation
harness runs without a hook oracle and would have to be updated with it.

#### RT-4 — the converter gate was never wired

`rotator.setConverter(vault)` runs only when `DeployPerp` gets `QUOTE_ROTATOR`.
`go-testnet.sh`, `arc-ignite.sh` and `deploy-mainnet-rh.sh` passed none. So even with
RT-1 fixed, every deploy path would have shipped the write-off.

The scripts now pass it. `DeployPerp` checks `rotator.owner()` and prints the
governance call if the rotator is already timelock-owned, rather than reverting
the perp deploy. *Checked with `bash -n` and a compile only; the scripts were not
executed.*

#### RT-5 — engine `quoteUnit` without an oracle

`PerpSwapLib.quoteFactor` with no oracle falls back to `10**decimals`. Measured in a
debug run: `quoteUnit = 1,000,000` after adopting USDG, meaning 1 ETH ≙ 1 USDG. So the
dust filter, the leverage tier depths and the insurance floor sit **3,000× too low in
value** after an ETH → USDG rotation. F14 wires the engine oracle, as `go-testnet.sh`
does, and pins `quoteUnit = 3000e6` on the way out and `1e18` on the way back.

`DeployPerp` wires `QUOTE_ORACLE` "unconditionally", but wires `address(0)` when it is
unset, and `arc-ignite.sh` never set it. Now passed through when provided.
**Recommend:** make `DeployPerp` refuse a set `QUOTE_ROTATOR` without `QUOTE_ORACLE`.
I did not add that because it changes mainnet-script behaviour mid-stage.

#### RT-6 — surtax on new legs

A rotation's first slice *initializes* the destination pool, so `poolInitBlock[leg]`
starts the launch surtax window: up to ~96% surtax plus the base fee, for
`snipeWindowBlocks = 30`. Anyone trading the new leg in that window pays it (to the
guild). The engine itself is protected in practice by the ring warm-up. F14 hit this
only because the harness advanced time without blocks: the engine's own buy paid
~99%, and the position was liquidated inside its own open.

#### RT-7 — stakers pay the rotation's price impact

The stake converts after the LP rotation has pushed its own slices through the same
venue. In F14 the venue was 1,000 ETH deep and the rotation moved ~20 ETH, which
took spot from 3,000 to **2,882 USDG/ETH** before the conversion ran. The round trip
cost stakers **506 bps**, entirely execution cost; the accounting is exact. It scales
with rotation size ÷ venue depth, which is the same missing sizing check as D-1.

#### D-1 — measured (`F14c_D1ForceCloseAfterDrain`), deferred

This used the largest long and short the engine would sell (0.5 ETH at 2×). Both
were **solvent at the flip**: the rotation removed the pool's liquidity, not its
price. After 12 slices, `forceCloseAllDead` produced:

- long: **payout 0**. It lost all 0.4655 ETH of collateral, plus a 0.4336 ETH shortfall that
  **insurance** covered (`BadDebt`).
- short: **payout 1.246 ETH (+0.78)**. It bought back into the price the long's forced
  sale had just crushed.
- stakers: unchanged. `unabsorbedEth` = 0 *at this book size*; a larger book exhausts
  insurance and spills into `plv`.

So D-1 is a **forced wealth transfer between solvent traders**, ordered by whoever
calls `forceCloseDead` first, and that call is permissionless. It is sharper than
"staker bad debt". It is pinned as a characterisation, so a fix has to flip it
deliberately.

**Why deferred:** every fix changes rotation semantics, so it is your call:

1. **Gate the mandate-completing slice on `openCount == 0`** (scope doc F-2.2). This
   brings back the dust-position hostage for that one slice.
2. **Bound slices by open interest** (F-2.1). The rotation stalls while a big
   book stays open, and nothing can close it.
3. **Force-close before the drain.** Signal divergence at the *first* slice of a
   migration mandate, so the book settles against a full pool. This is the only
   option that neither hostages the rotation nor transfers wealth. It needs the engine
   to read the mandate, and the engine has 86 B free (DELEGATECALL via `PerpSwapLib` is the
   route).

My recommendation is option 3, measured before anything is built.

### Per-subsystem answers

Buckets: **(a)** ratios/shares, which survive the flip untouched; **(b)** absolute amounts
in the quote, which must convert at one rate, atomically; **(c)** per-asset ledgers,
where each figure stays in the asset it was earned in.

| subsystem | state | old-asset value at the flip | pinned by |
|---|---|---|---|
| **Perps** | (b) `plv`, `ethQueueIndex`, `ethBackingMark`: converted together **and adopted in the same call**. (a) `ethShares`. `insuranceEth`/`tokYieldEth` are swept to treasury in the old asset (by design). Token side untouched. | Open book → park → force-close (D-1) → anyone converts + adopts. Empty book → converted inside the flipping slice. | F12 (9), F12b (3), F14 |
| **Dividends** | (c) `accPerShare` (ETH) plus `accPerShareOf[asset]`. The hook's `_fundGuild` uses `fundToken` for non-native quotes, including `routePerp` (Q-01/B-01). | ETH accruals stay claimable in ETH. USDG swap fees **and a USDG perp fee** reach the guild through `fundToken` on the rotated quote. | F14 (claim + claimTokens both pay) |
| **Collection floor** | (a) `entitledTokens` is in the generation **token**. Its backing is the out-of-range reserve LP. The ETH vault is confirmed still wired off (`vault == 0`). | Untouched. The reserve LP's liquidity is **identical** before and after the round trip. | F14 |
| **Gacha** | (a) with the oracle: the router's `_quote()` follows `generationQuote`, and play size is restated in USD. | $3000 of play = 3000e18 on both sides (1 ETH before, 3000e6 USDG after). Without the router oracle: raw units (RT-3). | F14 |
| **Hook fees** | (c) `relaunchETH` / `relaunchAsset[q]`. A stale-asset `legacyBuffer` is credited back to its own bucket (`CauldronHook.sol:1147`). | `relaunchETH` never shrinks or cross-credits. USDG fees go only to the USDG bucket. After the round trip, the USDG bucket stays **parked but accounted**: `seedFunding` releases one asset per relaunch, so only a USDG-quoted relaunch reclaims it. | F14 |
| **Treasury/governor** | (a) only: bps envelopes, NFT votes, time. `CauldronGovernor` bands `volumePerNFT` against the hook's live value. | Nothing to convert. | — (no money state) |
| **Volume/death** | (a) **only with the hook oracle** (USD at 1e18); raw units without it. | With the oracle, a $30k USDG leg keeps the generation alive. Without it, the generation reads dead (RT-3). | F14, F14b |
| **Seeder/reserve** | `CauldronSeeder` is native-only (`ethTotal`, `primeBudget`) and spends in its own asset. `ReserveLib` is tick math. | Not redenominated. The seeder keeps placing into the primary ETH pool. | — (code-read) |

Also noted: `MiFrensDividend.MAX_ASSETS = 3`. After three non-native quotes, the guild
share falls back to the relaunch reserve (fail-soft, not lost). The legacy buyback for
non-native quotes is treated as **still deferred** per the 2026-09-18 decision and was
not revisited. Consequence: after ETH → USDG, the floor carve on USDG fees accrues to
`relaunchAsset[USDG]` instead of buying tokens, so the floor stops growing but nothing
is lost.

### Sizes (`FOUNDRY_PROFILE=cauldron forge build --sizes`)

| contract | before | after | free |
|---|--:|--:|--:|
| PerpEngine | 24,490 | 24,490 | **86** |
| CauldronRegistry | 24,568 | 24,568 | 8 |
| CauldronHook | 23,978 | 23,978 | 598 |
| RedemptionExt | 15,826 | 15,826 | 8,750 |
| PerpVault | 13,461 | **13,572** | 11,004 |
| QuoteRotator / PerpSwapLib | unchanged | unchanged | |

The only runtime over 24,576 is the pre-existing `K3d` **test harness**.

### Files touched this session

- `cauldron/PerpVault.sol`: RT-1/RT-2
- `deploy/DeployLaunchpad.s.sol`: RT-3
- `deploy/DeployPerp.s.sol`: RT-4 ownership-aware converter
- `scripts/go-testnet.sh`, `scripts/deploy-mainnet-rh.sh`, `scripts/arc-ignite.sh`: RT-4 (plus a QUOTE_ORACLE passthrough for arc)
- new: `test/functional/F12b_RequoteRealEngine.t.sol`, `F14_RotationTotality.t.sol` (F14 + F14b),
  `F14c_D1ForceCloseAfterDrain.t.sol`
- `test/functional/F12_RequoteBacking.t.sol`: quote-strict mock; T1/T3/T4/T7 moved to atomic-adoption semantics, T8 added
- the 9 `LIQ0x` suites, `V2A_VoteFarm`, `S0x_ForceCloseGasWedge`, `CHURN1_LiveRevert`: fork gates

Assertions changed rather than added (so they can be checked): F12 T1 and T3 asserted
"engine has NOT adopted / flag armed" after a conversion. That was the window state
RT-2 removes, so they now assert the stronger "adopted in the same call / flag
consumed". T7 expected `AlreadyRequoted`, and a second call now finds no divergence
(`NotDiverged`). In F14 itself, a 5% round-trip bound I had guessed failed at 506 bps.
It was replaced by per-leg bounds (venue market / oracle floor) plus a logged drag,
with the cause measured (venue spot 2,882 before the conversion).

---

## Part 2 — D-1 fixed: the book is carried across the flip

### Design (owner-approved)

At the slice that flips `generationQuote`, the registry calls
`PerpEngine.requoteBook(rotator)` — **not** try/caught — and the engine carries its
whole book onto the new quote in that same transaction, positions open:

| state | treatment |
|---|---|
| tokens (long `size` held, short `size` owed) | untouched — both pools trade the same token |
| money held in the old quote: `plv`, each short's collateral + proceeds, `insuranceEth`, `tokYieldEth` | **swapped once** through the rotator's curated venue for the pair, under its oracle floor; each re-expressed at the **realized** rate |
| claims that aren't money: each long's principal + collateral, `longOiEth` | **restated at the oracle rate** (debt rounds up) — the swap's slippage stays with the money that was swapped, never moves from longs onto stakers |
| funding index | untouched (a rate) |
| TWAP ring | **shifted** by the oracle tick offset, never reset — a carried book is never marked off the new pool's spot for a warm-up window |
| vault | `beforeBookRequote` (settle queue + yield in old units) → restate → `afterBookRequote` (queue index × newTotal/oldTotal, re-mark, yield scale) |
| `quoteUnit` | restated from the **rotator's** oracle (fixes RT-5 for rotations) |
| `markSource` | dropped (it priced the old pair); the carried ring marks until re-armed (D-3 remains an ops step, now non-urgent) |

**All or nothing.** Unpriceable pair, owed payouts, a venue that cannot clear the
floor, a vault that won't re-express its ledger — each reverts, the flipping slice
reverts with it, and nothing moves. The engine can never sit diverged with a
book open, so the park-and-drain (and its forced sale) is unreachable.

**No wiring.** The rotator recognises `registry.hook().perpEngine()` for
`swapOnce`/`withdraw` and exposes `venueFor(a, b)` (recorded by `setVenue`). The
previous design's `converter` slot — which no deploy path set (RT-4) — is gone.

### Measured (pinned fork, block 11,763,300)

**D-1, against a control** (`F14c`): max long + short (0.5 ETH at 2× each),
full 12-slice rotation, then each owner closes on the new pool. Control = the
same closes with no rotation (snapshot/revert).

| | control (no rotation) | carried book | pre-fix (force-closed) |
|---|---|---|---|
| long | 0.3388 ETH ≈ 1,016 USDG | **992.7 USDG (−2.3%)** | **0** + 0.43 ETH insurance shortfall |
| short | 0.4881 ETH ≈ 1,464 USDG | **1,247.5 USDG (−14.8%)** | 1.246 ETH (+168% of collateral) |

- The long's −2.3%: the rotation's own slices price the new pool at the venue
  rate they walked (~4% under the oracle the long was restated at).
- The short's −14.8%: its backing (~3× collateral at 2×) is money and took the
  swap's 5.2% slippage — by design. Deeper venue ⇒ smaller.
- No forced sale, no bad debt, insurance drawn only by funding dust.

**Round trip with a carried book both ways** (`F14`): ETH → USDG with a long +
short open (carried, then closed in USDG); a USDG long left open is carried back
across USDG → ETH and closed in ETH. Dividends, floor, hook fees, volume, gacha
all as in Part 1; `unabsorbedEth == 0` throughout; round-trip staker drag 490 bps
(venue impact).

**Real engine ↔ real vault** (`F12b`, 7/7): 5.5 ETH (plv + insurance + yield) →
15,675 USDG at the venue's 2,850; plv 11,400, insurance 1,425, yield 2,850 —
converted, not swept or forfeited; carol's 1 ETH of token yield paid as 2,850
USDG; exact round trip; TWAP shifted by +196,256 ticks and still warm; registry-
only; owed payouts / unpriceable quote refuse with nothing moved.

### Found and fixed while building it

- **Token-yield rescale destroyed precision.** First cut rescaled
  `accEthPerTokShare` by the realized rate; with the 1e6 share offset the
  accumulator is ~1e9 and ×2.85e-9 floored it to **2** — carol's 2,850 USDG came
  out as 2,000 (and 0.70 ETH after a round trip). Fixed by keeping the per-share
  ledger in one fixed internal unit and converting only at the edges
  (`tokYieldScale`), which also removed all per-staker state.
- **`via_ir` typed library calls are expensive.** The first engine entry point
  put PerpEngine 644 B over EIP-170. Bisected: an empty new function costs 36 B;
  one typed call into a new `PerpSwapLib` function costs **726 B**; the same call
  as a raw `delegatecall` costs **144 B**. The engine uses the raw call and
  bubbles revert data. (`memory-safe` assembly made no difference.)

### New liveness property to know

The flipping slice needs the venue to absorb the engine's quote-side money
within the rotator's oracle band. `S01` (60 ETH donated `plv` against a 20 ETH
pool) now refuses its last slice with `SlippageTooHigh` — nothing moved — and
lands once the venue is deepened. **Size the (full-range) venue for the LP
slices plus the perp book's money.**

### Sizes (`FOUNDRY_PROFILE=cauldron forge build --sizes`)

| contract | HEAD | now | free |
|---|--:|--:|--:|
| PerpEngine | 24,338 | **24,536** | **40** |
| PerpSwapLib | 8,978 | 13,653 | 10,923 |
| PerpVault | 11,613 | see final build | |
| QuoteRotator | 8,502 | 9,839 | 14,737 |
| RedemptionExt | 13,916 | 15,467 | 9,109 |
| CauldronRegistry | 24,568 | 24,568 | 8 |

### Tests changed (so they can be checked)

- Rewritten: `F12_RequoteBacking` (vault hooks: blended pot, queued exit moves
  with it, engine-only), `F12b_RequoteRealEngine` (7 cases above).
- Updated: `F14_RotationTotality` (book carried both ways), `F14c` (from
  "D-1 characterised" to "D-1 fixed, against a control").
- Re-amended, old design asserted: `F10`/`X2e` funded branch asserted the engine
  PARKS — now asserts it ADOPTS with plv converted and held; `S01` routeB
  asserted plv SWEPT — now asserts the flip refuses cleanly on a too-thin venue
  and lands, converted, once deepened.
- Restored to HEAD: `X3a` (its two D-2 cases tested the removed path).
- Import only: `PerpRebookAccounting` (`Position` is now file-level).
- Reverted to HEAD (no longer needed): `DeployPerp.s.sol`, `go-testnet.sh`,
  `deploy-mainnet-rh.sh`; `arc-ignite.sh` keeps only a `QUOTE_ORACLE` passthrough.
- Backup of the superseded D-2 files: `/tmp/d2-backup/` (not in git).

---

## Part 3 — adversarial pass, legacy buyback, mark source

### Adversarial pass (`test/attacks/RQ1_CarriedBookAdversarial.t.sol`, pinned fork)

| id | attack | result |
|---|---|---|
| A1 | a contract whose `receive` reverts leaves a payout owed, which `requoteBook` refuses on | **MEASURED residual (Medium).** 0.006 ETH of fees + a forfeited 0.0049 ETH payout holds the flipping slice; the owner's `retirePayout` write-off (a timelock call) restores it. Repeatable once per timelock delay. A real fix needs owed payouts escrowed per asset (e.g. in the vault) — an engine change, not done. |
| A2 | push the venue, fire the permissionless flip, unwind | **MEASURED, bounded by the band.** At the default 3% band: best attacker profit 0.097 ETH (6 ETH push); worst engine outcome 98.82% of an honest flip; a 9 ETH push is refused outright. Same class as every LP slice — the band is the defence. |
| A3 | hold a hedged long+short across the flip for a free lunch | **HOLDS.** 905.6 USDG carried vs 987.6 closing first. |
| A4 | call the library directly / call `requoteBook` as a stranger | **HOLDS.** Both revert. |
| A5 | flip with a full 64-position book | **MEASURED.** 1.21M gas for the flipping slice. |
| A6 | relaunch after a rotation, stakers present | **WAS BROKEN, FIXED.** Relaunch forces native; the engine's sync hit the old stakers-present veto inside the registry's `try`, so the engine sat on the dead generation. Now `requoteBook` remembers the rotator, and `syncGeneration`'s quote change carries the (empty) book home through it — all-or-nothing, owner keeps the old write-off path. Alice's 28,481 USDG came back as 9.94 ETH. |

### Legacy buyback on a rotated quote — done, not deferred

- Non-native LAUNCHES are refused (registry forces native), and every protocol pool
  has the quote at currency0, so `LegacyBuyLib` needed no change.
- What was missing: the hook's `_liveKey` never moved at a rotation, so after
  ETH → USDG the floor buyback waited for trades on the drained ETH pool, and the
  floor-share carve (the bigger one, 84.6% channel) was still native-only.
- Fixed: the flip calls `hook.setLiveKey(new leg)`; the floor-share carve matches the
  live quote like the first carve already did; the trigger threshold is sized by
  oracle VALUE, so it stays ~0.02 ETH worth instead of becoming 2 cents of USDG.
- Measured (F14): floor buyback 4.48M tokens before the flip → 16.04M after USDG
  trading on the new leg; stale ETH buffer lands in the ETH reserve bucket.

### Mark source (D-3) — resolved by design, pinned

`PerpMarkSource` only weights pools of the SAME pair, so it never weighted the USDG
leg; re-armed on the new pair with no siblings it returns the new pool's own tick —
what the engine reads without it. The engine now marks the NEW (deep) pool with its
carried ring (F14 asserts the ring is warm and `blocksVolumeLink()` is false after
the flip). A new mark source is only needed if governance adds same-pair fee tiers
on the new quote.

### Sizes (final)

| contract | HEAD | now | free |
|---|--:|--:|--:|
| PerpEngine | 24,338 | **24,168** | **408** |
| PerpSwapLib | 8,978 | 15,610 | 8,966 |
| PerpVault | 11,613 | 12,287 | 12,289 |
| QuoteRotator | 8,502 | 9,874 | 14,702 |
| RedemptionExt | 13,916 | 15,786 | 8,790 |
| CauldronHook | 23,978 | 24,374 | 202 |
| CauldronRegistry | 24,568 | 24,568 | 8 |

Moving `syncGeneration`'s quote-change branch into the library freed 368 B net.
Nothing is over EIP-170, test harnesses included.

### Suite

Fork (pinned 11,763,300): **1,224 passed, 0 failed, 1 skipped.**
No fork: 870 passed, 39 failed — every one a fork gate with a readable message.
