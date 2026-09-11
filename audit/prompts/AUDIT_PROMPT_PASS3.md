# Independent Verification + Red-Team of the Remediation

Paste everything below the line into a fresh session opened at the repo root.

---

You are an independent security auditor. A deep audit ran on this repo at commit
`0a1830b`, found 12 issues, and every one was remediated. A second pass then ran over
those fixes and found three more — **two of which the remediation itself had
introduced.** All of it is still **uncommitted in the working tree**.

Your job is the third pass, and you should assume it will find something, because the
base rate here says it will: the last pass's own findings were 66% self-inflicted.

You did not write any of this code. Trust nothing in the reports. A fix marked
verified is a claim by the person who wrote it.

## Read first

- `audit/DEEP_AUDIT_2026-09-08.md` (724 lines) — the audit. Findings preserved as
  written, deliberately not edited over.
- `audit/REMEDIATION_2026-09-08.md` (490 lines) — every fix, the reasoning, and the
  second pass at the end (`S-1`, `U-1`, `A-4 follow-up`).

Do **not** re-report anything already found and fixed. Verify it, then move past it.

## What changed, and why it is the dangerous part

466+ lines across four layers, all uncommitted:

```bash
git status --short          # ~50 modified, 2 deleted, 9 untracked
git diff                    # the remediation itself
```

Modified contracts: `CauldronHook.sol`, `cauldron/MiFrensDividend.sol`,
`cauldron/MiFrensGenesis.sol`, `deploy/DeployLaunchpad.s.sol`. Plus ~25 test files,
`api/fren-teach.ts`, `indexer/src/api/index.ts`, 7 frontend files, and
`.github/workflows/deploy.yml`. New: `src/lib/safeSvg.ts`,
`src/components/shared/IndexerHealthBanner.tsx`, three `AuditPoC5/6/7` suites.

**Deleted, and this is unreviewed:** `MagicFrensPeg.sol` and `MagicFrensPresale.sol`
are gone from the working tree, but these still reference them —
`test/MagicFrensPresale.t.sol`, `deploy/DeployPresale.s.sol`,
`deploy/DeployMagicFrensPeg.s.sol`, `deploy/DeployCauldron.s.sol`,
`deploy/DeployRenderer.s.sol`, `foundry.toml`, `.env.template`, two READMEs.
Determine whether the deletion was intentional dead-code removal or an accident, and
whether any profile still tries to compile the dangling references. The audit excluded
both files from scope, so **nobody has ever reviewed what depended on them.**

## Environment

```bash
cd contracts/solidity
export FORK_RPC=https://ethereum-sepolia-rpc.publicnode.com \
       POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543 \
       POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4
FOUNDRY_PROFILE=cauldron forge build --sizes
FOUNDRY_PROFILE=cauldron forge test
```

Claimed state, all of which you must independently reproduce:

| | Claimed |
|---|---|
| Local | 305 passed, 154 skipped, **0 failed** |
| Fork (Sepolia) | 474 passed, 1 skipped, **0 failed** |
| `CauldronHook` size | 24,522 / 24,576 — **54 bytes margin** |
| `CauldronRegistry` | 24,566 — 10 bytes |
| `PerpEngine` | 24,563 — 13 bytes |

If any number differs, that is finding #1. The skipped count is a live signal: the T-1
fix converted `if (!active) return;` into `vm.skip(!active)` across 154 test functions
specifically so vacuous passes became visible. **If the skip count is still 154 with
fork env exported, the gating is broken and the fork suite is not running.**

## Part 1 — Attack the fixes

Each of these is new code written under remediation pressure. Take each fix and ask
the question its author did not.

**R-1 — per-asset reserve split.** `relaunchAsset` mapping + `releaseRelaunchAsset()`.
The mapping was appended at the *end* of storage under an `APPEND-ONLY` banner because
the first attempt shifted every later slot and broke `F01`/`F03` (which pin
`legacyOwedToReserve` to literal slot 27). Verify the layout is actually safe now —
and that the invariant `hook.balance >= relaunchETH + legacyBuffer` still holds, since
that assertion was one of the 154 vacuously-passing tests. Then attack: can a
generation credit the wrong denomination? Can `releaseRelaunchAsset` be called for an
asset whose balance was already spent by another path? The `legacyBps` carve and the
no-vault floor fallback are now native-gated — what happens to a non-native fee that
falls through, and does anything double-count it?

**V-1 / G-1 — `_toUsd` now uses `cachedUsdPerRawUnit`.** This changed a `staticcall`
into a `call`, which the remediation itself documents as a new reentrancy surface
("a compromised oracle is now a compromised hook"). Take that seriously and go further:
build a malicious `quoteOracle` and see what re-entering from inside `_beforeSwap` /
`_afterSwap` actually reaches. It is timelock-set, so the question is impact-if-
compromised, not access. Separately: the cache holds the last good factor across a
refresh failure — how stale can it get, who pays to refresh it, and can an attacker
pin a favourable stale factor across a window they control?

**D-1 / D-2 / D-3 — the dividend basket.** `fundToken` is now gated to a one-time
`funder`; failed claim legs bank to `owedAsset`; transfers settle the basket via
`onMiFrenTransfer`. Three angles: (a) `MAX_ASSETS` dropped 8→3 and gas forwarding went
60k→180k / 80k→240k, measured at ~33k per asset — re-measure with three assets all
carrying balances and a hostile-but-not-reverting token that burns gas, and check the
F-09 property (a gas-starved transfer is *refused*, not silently mis-settled) still
holds; (b) `owedAsset` is now permanent debt state — can you inflate it; (c) the
one-time `funder` wiring in `DeployLaunchpad.s.sol` — is there a window between deploy
and wiring where anyone can claim it?

**S-1 — `removeAsset` was added, then removed again.** It re-opened the historical
over-claim hole (`test_LateJoinerCannotClaimHistoricalFees`), measured at *a fren owed
1005 USDG against a pot holding 10*, made worse by D-2 banking the shortfall as
permanent phantom debt. It is now gone. **Confirm it is fully gone** — no caller, no
interface, no leftover state — and that the basket genuinely cannot mutate for the
contract's lifetime. Then stress the new invariant I-13
(`test_I13_EntitlementNeverExceedsWhatIsHeld`): is it asserted over *every* asset and
every holder, or only the happy path? This is the single most important invariant in
the dividend contract and it is one pass old.

**U-1 — the unit-coupling revert.** `setDeathThreshold` now takes the ladder and odds
curve and reverts if you wire an oracle without restating them, because
`volumePerNFT`, `nftPriceStep` and `oddsFullVolumeWei` were left in ether terms against
USD-scaled credit (a ~3000x over-issue of dividend-earning NFTs). 15 call sites were
updated. **Check all 15.** Then look for a fourth constant nobody caught — grep every
comparison against a value that flows through `_toUsd` and prove each side's units.
That is exactly the analysis that found three; it does not prove there were only three.

**P-1 — the interlock, not the fix.** `linkVolume` now reverts `PerpsOpen()` while
`openCount > 0`, so a generation runs multiple pools **or** perps, never both. This is
a sequencing guard, not the liquidity-weighted mark the real fix needs. Attack the
guard: can you open a perp position in the window after a second pool is linked? Race
`linkVolume` against `openPosition`. Can `openCount` be made to read 0 while positions
are live? What happens on relaunch with the interlock armed? And confirm the audit's
correction still holds — the depth bound fails *safe*, the mark does not, so summed-
depth bounding must not land first.

**A-4 — the SVG sanitizer.** DOMPurify stripped `<animate>` and killed the
Liquidatoor's reticle, so animation elements were re-admitted behind a
`uponSanitizeElement` hook that drops any whose `attributeName` targets a link or
event attribute. This is a hand-rolled bypass of a deliberate DOMPurify default.
**Break it.** `attributeName` casing and whitespace, namespaced attributes,
`<set>` vs `<animate>` vs `<animateTransform>`, `begin`/`end` event syntax,
`values`/`from`/`to` on a non-link attribute that still reaches a sink, SMIL on
`<use xlink:href>`. All five call sites go through this. The remediation claims six
attack vectors blocked — find a seventh.

**A-2 — the indexer byte cap.** 8KB on `/graphql`, plus a 411 on missing
`Content-Length`. Both derive from a header the client controls. Send a lying
`Content-Length`. Try `Transfer-Encoding: chunked` with the header present. Check
whether the cap sits before or after Ponder's parser, and whether the watchdog
restart-loop concern the remediation raised is actually closed.

**A-6 — `timingSafeEqual` over SHA-256 + 5/min per-IP throttle** in `fren-teach.ts`.
In-memory, per warm instance. Work out how many concurrent warm instances Vercel will
give you and what the real effective rate is. Confirm the IP source cannot be spoofed
via `x-forwarded-for`.

## Part 2 — Attack what was accepted, not fixed

These are live risk, formally accepted. Your job is to price them honestly.

- **A-5 — `emergencyAdmin` is `immutable` and can pull an entire generation's LP.**
  Not fixable in place: the registry has 10 bytes of headroom, so it cannot absorb a
  propose/accept handoff. The protocol's headline claim is protocol-owned LP with no
  team rug, and it rests on one key that cannot be rotated. Model the full compromise:
  what exactly can that key take, how fast, and what would holders see. Then say
  whether the timelock and arming gate genuinely constrain it or just add a delay.
- **Z-11 (carried from red-team pass 3)** — queued PLV exits are senior to live
  shares. Called deliberate design. Prove whether it is bank-runnable now that the
  vault stakes in the generation's quote rather than native ETH.
- **`CauldronHook` at 54 bytes.** There is no room for the next fix. Determine what
  the *next* required change is and whether it can possibly fit — this is the
  practical argument for the Phase 1 facet extraction, and it deserves a number.
- **`linkVolume` hard-depends on `perpEngine.openCount()`.** Registry-only and fails
  closed. Confirm failing closed is actually safe in every reachable state, including
  mid-relaunch.

## Part 3 — Regression and coverage

The remediation touched the hot swap path, the dividend accounting, the genesis
transfer hook, and the deploy script. Any of those can break something that was
previously correct.

- Diff the test files. ~25 were modified. Did any assertion get *weakened* to make a
  fix pass? This is the highest-yield check in the whole engagement — grep the diff
  for loosened bounds, removed asserts, widened tolerances, and changed expected
  values.
- The frontend has **zero unit coverage** — `npm run test:unit` cannot run (`vitest`
  in watch mode, `jsdom` not installed, no test files under `src/`). Seven frontend
  files were just modified, including a new shared component hoisted into the app
  shell. Verify `npm run type-check` and `npm run build` pass, and manually exercise
  `IndexerHealthBanner` and the five `safeSvg` sinks against a running dev server
  (`npm run dev`, port 5173).
- The new `contracts` CI job runs `forge build --sizes` and `forge test` with fork
  secrets. Read `.github/workflows/deploy.yml` — confirm `frontend` actually needs
  `[verify, contracts]`, and that a missing secret degrades to skips rather than a
  silent green.

## Rules

1. **PoC or it is a hypothesis.** Foundry tests in `contracts/solidity/test/audit/`,
   following the house convention: an invariant that FAILS on current code plus a
   positive PoC that PASSES. Reuse `test/attacks/YBase.sol` (raw `modifyLiquidity`,
   directional pumps through the 69× ceiling) and `ZAuditBase.sol` rather than
   rebuilding harnesses.
2. **Quantify.** Cost in, value out, capital required, atomic or multi-block.
3. **Refutations count.** Something you attacked hard that held is a result. Say how
   hard you hit it.
4. **Do not weaken a test to make anything pass.** Ever.
5. **Report Criticals immediately**, mid-engagement.
6. Every claim needs `file.sol:line`.

## Deliverable

`audit/VERIFICATION_PASS3.md`:

1. **Verdict on the remediation** — for each of R-1, V-1, D-1, D-2, D-3, P-1, T-1,
   G-1, A-1, A-2, A-3, A-4, A-6, S-1, U-1: **HOLDS / INCOMPLETE / REGRESSED /
   NEW BUG INTRODUCED**, with evidence.
2. **Reproduced verification table** — your actual numbers against the claimed ones.
3. **New findings** — severity-ordered, with PoC paths.
4. **The deletion question** — what happened to `MagicFrensPeg.sol` /
   `MagicFrensPresale.sol` and what it broke.
5. **Accepted-risk pricing** — A-5, Z-11, the 54-byte ceiling.
6. **Residual risk and blind spots** — what you could not reach.

Final line: **is this working tree safe to commit and deploy?** One word, then the
reasoning.
