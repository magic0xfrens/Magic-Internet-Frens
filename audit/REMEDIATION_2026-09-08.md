# Remediation — Deep Audit 2026-09-08

Companion to [`DEEP_AUDIT_2026-09-08.md`](DEEP_AUDIT_2026-09-08.md). Every finding
is addressed. Fixed in severity order; each entry says what changed, why that
shape and not another, and what proves it.

A **second audit pass** then ran over the fixes themselves — they were the newest
and least-reviewed code in the repo. It found three more issues, two of them in
this remediation's own first draft. Those are in [§ Second pass](#second-pass-re-audit-of-the-fixes)
at the end, and are fixed too.

## Verification

| | Before | After |
|---|---|---|
| Local suite | 443 passed, 3 skipped | **305 passed, 154 skipped, 0 failed** |
| Fork suite (Sepolia) | 461 passed, 1 skipped | **474 passed, 1 skipped, 0 failed** |
| Frontend `type-check` | pass | **pass** |
| Frontend `build` | pass | **pass** |
| Indexer `tsc --noEmit` | pass | **pass** |
| `verify-manifest` | pass | **pass** |
| Secrets in `dist/` | none | **none** |

The local count *drops* because the suite now tells the truth: 154 tests are
fork-gated and had been passing vacuously. Nothing was removed — the fork run
went **up**, from 461 to 474, on the new regression tests.

### Contract sizes (EIP-170 = 24,576)

| Contract | Before | After | Margin |
|---|---|---|---|
| CauldronHook | 24,408 | 24,522 | **54** |
| CauldronRegistry | 24,566 | 24,566 | 10 (untouched) |
| PerpEngine | 24,563 | 24,563 | 13 (untouched) |
| MiFrensDividend | 6,427 | 7,585 | 16,991 |
| MiFrensGenesis | 20,258 | 20,261 | 4,315 |

The hook absorbed a new mapping, a new external function and an interlock while
staying under the limit. That was paid for by collapsing thirteen duplicated
revert strings into two custom errors (`SendFailed`, `BadParam`) — the four
copies of `"ETH transfer failed"` alone returned 107 bytes. **No fix required
registry or engine bytecode**, which is what kept them out of scope.

---

## R-1 (High) — phantom `relaunchETH` on a non-ETH generation

**`CauldronHook.sol`**

The reserve is now split by denomination. `relaunchETH` is documented as
strictly native wei; a new append-only `relaunchAsset` mapping holds the
non-native side, and `_creditReserve()` routes each residual to the right one.
`releaseRelaunchAsset(address)` gives that value the exit it never had —
registry-gated exactly like the native path, with the transfer's return value
checked so a token that returns `false` cannot zero the counter while the tokens
stay put.

Two adjacent paths had the same conflation and are now native-gated: the
`legacyBps` buyback carve and the no-vault floor fallback both feed
`legacyBuffer`, which `legacyBuyStep` spends as native ether. A non-native fee
skips the buyback and its share falls through to `_creditReserve`.

**Why not convert at collection instead:** swapping mid-swap sells the basket at
whatever price that block produces and adds a nested swap to the hot path. The
split is bookkeeping only.

**Storage note:** `relaunchAsset` is appended at the *end* of the layout under a
new `APPEND-ONLY STORAGE` banner. The first attempt put it next to `relaunchETH`
and shifted every later slot, which broke `F03`/`F01` — those suites pin
`legacyOwedToReserve` to literal slot 27 and probe it before each write. That
guard did its job; the banner is there so the next person doesn't rediscover it.

**Proof:** `test/audit/AuditPoC6_QuoteReserve.t.sol` (fork). A 10,000 USDG swap
now yields `relaunchETH = 0`, `relaunchAsset[USDG] = 9.9e9` matching the hook's
actual balance exactly, and the reserve releases to the registry. Pre-fix the
same test showed 9.9e9 phantom **wei** and `releaseRelaunchETH()` reverting.

---

## V-1 (High) — stale oracle collapses volume and fakes death

**`CauldronHook.sol`**

Two changes, and the first does most of the work:

1. `_toUsd` now calls **`cachedUsdPerRawUnit`** instead of the uncached view.
   The cache keeps the last good factor across a refresh failure, so an ordinary
   heartbeat miss no longer changes what a recorded number means. This is also
   the G-1 fix — see below.
2. A genuine `0` returns **`0`, never `raw`**, and the call site skips the write
   entirely. Falling back to `raw` was never graceful degradation: it silently
   switched the unit of the ledger, and `getVolume24h` then summed two
   incompatible scales.

`_lastUpdateTs` is deliberately left untouched when unpriced, so the existing 24h
window becomes the grace period — a brief outage costs nothing and a day-long one
is the operational emergency it actually is.

**Proof:** `test/audit/AuditPoC7_StaleOracleDeath.t.sol` (fork). The same trade
through a lapsed feed now records `1.0e20` — identical to the live-feed reading —
where it previously recorded `1.0e8`, a 1e12× collapse. `isDead()` returns false
across a full outage. A second test pins that a never-priced quote records
*nothing* rather than a raw figure.

---

## D-1 (High) — permissionless basket funding

**`MiFrensDividend.sol`, `deploy/DeployLaunchpad.s.sol`**

`fundToken` is gated to a one-time `funder` (the hook), wired by `treasury`
alongside `setRegistry`. Closed by default, which is the safe direction: an
un-fundable basket loses nothing, an openly fundable one is unrecoverable.

The ETH path stays open to anyone — a bare `receive()` has nothing to enumerate
and so cannot be poisoned.

**Proof:** `AuditPoC5::test_D1_StrangersCannotConsumeBasketSlots`, plus
`DividendBasket::test_OnlyTheFunderCanFundTheBasket`.

---

## D-2 (High) — one hostile asset bricked every claim

**`MiFrensDividend.sol`**

`claimTokens` no longer pushes with a reverting helper. `_tryPush` reports
failure, and a failed leg is banked to `owedAsset` for later retry via the new
`withdrawOwedToken(asset)`. The debt marker still advances, so nothing
double-counts and nothing is lost. `removeAsset` (treasury-gated) retires a dead
or drained asset from both loops without touching accumulators, so anything
already banked stays claimable.

`withdrawOwedToken` *does* revert on failure, which is correct where it was wrong
in `claimTokens`: it settles exactly one caller-chosen asset, so a failure blocks
nothing else and the balance stays banked.

**Proof:** `AuditPoC5::test_D2_AHostileAssetCannotBrickOtherClaims` — the good
asset is delivered, the hostile one is banked, and it is recoverable once the
token behaves.

---

## D-3 (Medium) — transfer forfeited accrued ERC20 dividends

**`MiFrensDividend.sol`, `MiFrensGenesis.sol`**

`onMiFrenTransfer` now settles the basket alongside ETH, into `owedAsset`.

**This had to happen at transfer time and nowhere else**, and that constraint
drove the rest of the change. The moment the hook returns, the token is out of
`activeShares`, so every later deposit divides among the remaining holders —
computing the leaver's share at any subsequent point pays them out of value that
is no longer theirs. A lazy or claim-time settlement is therefore not a cheaper
version of this fix, it is a different and wrong one.

That forced two consequences, both deliberate:

- **`MAX_ASSETS` drops 8 → 3.** The walk runs under the collection's forwarded
  gas budget, and that budget must cover the worst case because it is checked
  before the walk begins — so every slot is gas *every* genesis transfer reserves
  forever. Measured at ~33k per asset carrying a balance. The live manifest has
  two non-ETH quotes; three leaves one slot of headroom, and `removeAsset`
  handles rotation beyond that.
- **`GAS_DIVIDEND_FWD` 60k → 180k, `GAS_DIVIDEND_MIN` 80k → 240k.** Sized from
  measurement, not estimate. At 60k the basket settlement would simply have
  failed inside the existing try/catch — silently, which is the exact failure
  mode that path exists to prevent. The F-09 property (a gas-starved transfer is
  *refused*, not silently mis-settled) is unchanged and still tested.

**Proof:** `AuditPoC5::test_D3_TransferSettlesTokenDividendsToTheLeaver` and
`test_D3_SettlementFitsTheGasBudgetWithAFullBasket`. The second one caught the
first budget I picked being too small — 160k — which is why the number above is
measured rather than guessed.

---

## P-1 (Medium/High, was a hypothesis) — perps mark the primary pool

**`CauldronHook.sol`**

The full fix is a liquidity-weighted mark across a generation's pools, which
needs multi-pool infrastructure that does not exist yet. Shipping that blind
would be worse than shipping nothing. What ships instead is the **interlock**:
`linkVolume` now reverts `PerpsOpen()` while the engine reports `openCount > 0`.

A generation may run several pools, **or** it may run perps. The sequencing from
the audit's migration plan is now enforced in code rather than living in a doc
and being hoped for.

Note the audit's correction still stands: the depth bound fails *safe* (a
thinning primary tightens position limits), the **mark** does not. So the fix the
frontier doc proposed second — bounding size against summed depth — must not land
first; it would license larger positions against a mark the engine still cannot
compute.

**Proof:** `CauldronHookAccess::test_P1_CannotAddASecondPoolWhilePerpsAreOpen`
and `test_P1_NoEngineMeansNoInterlock` (the interlock must not fire on an
ETH-only generation with perps unwired).

---

## T-1 (Medium) — vacuous tests and no contract CI

**154 test files/functions, `.github/workflows/deploy.yml`**

`if (!active) return;` became `vm.skip(!active)` in every **test** function —
invariant functions and helpers were left alone deliberately. `view` was stripped
where the cheatcode required it.

The local run now reports **305 passed / 154 skipped** instead of 451 passed. The
gap was nearly **twice** what the audit first reported: I counted 78 from the
`*ForkTest` suites, but attack, audit, final and invariant suites gate the same
way. **154** is the real figure, and that correction matters — the invariant that
catches R-1 (`hook.balance >= relaunchETH + legacyBuffer`, asserted in two
suites) was among them.

A `contracts` CI job now runs `forge build --sizes` and `forge test`, with
`FORK_RPC`/`POOL_MANAGER`/`POSITION_MANAGER` from repo secrets so the gated
suites can run too. `frontend` now needs `[verify, contracts]`. Without the
secret the skipped count is the signal: if it grows, coverage moved behind
the gate.

---

## G-1 (Medium, gas) — the oracle cache was never used

Fixed by the same line as V-1. `_toUsd` was `view` and so could only reach the
uncached entrypoint, meaning every swap on an oracle-wired generation paid a full
~30k Chainlink read — the precise cost `QuoteOracle`'s caching was written to
avoid, and which its own comment claimed was already avoided. `_toUsd` is now
non-view and uses the cache.

---

## A-1 (Low/Med) — header-controlled system prompt

**`api/fren-ask.ts`**

`loadDocs` built its URL from `x-forwarded-host` / `x-forwarded-proto` and spliced
the response into the system prompt as "DOCS (source of truth)" — so pointing the
header at your own host let you supply your own system prompt and use the
project's Groq/Gemini key as a free general-purpose LLM. Now pinned to a
constant, overridable only through `FREN_DOCS_URL`, with a 5s timeout.

---

## A-2 (Low) — unbounded public GraphQL

**`indexer/src/api/index.ts`**

An 8KB request-body cap on `/graphql` (`MAX_GRAPHQL_BYTES`). A byte cap is blunt
but it is the bound that cannot be reasoned around — depth, breadth and alias
multiplication all have to be spelled out in the document to be requested. Real
queries are a few hundred bytes.

This matters more than its severity suggests because the watchdog would restart
the container straight back into the same load, turning a slow query into a
restart loop.

---

## A-3 (Low) — freshness gate on 1 of 19 indexer consumers

**`src/components/shared/IndexerHealthBanner.tsx`, `src/app/App.tsx`,
`src/components/cauldron/TheCauldron.tsx`**

`useIndexerHealth`'s own header already reached the right conclusion — the
problem "cannot be fixed hook by hook", so the page must say when its data is
untrustworthy. The banner implementing that was mounted inside one route, so
every other page kept rendering wrong numbers silently.

Extracted to a shared component and hoisted into the app shell, covering all 19
consumers at once. Its CSS travels with it (it previously lived in
`TheCauldron`'s style block and would not have applied elsewhere). The
route-local copy is removed so it does not double-render. `PerpPanel`'s
more specific "verify on the explorer before trading" guard is untouched — this
is the floor, not a replacement.

**Not done:** routing all 19 hooks through one health-aware fetch client. That is
the architecturally correct end state and a large refactor I could not verify
without running the UI; the global banner delivers the safety property now.

---

## A-4 (Informational) — unsanitized SVG sinks

**`src/lib/safeSvg.ts` + 5 call sites**

All five `dangerouslySetInnerHTML` SVG sinks now pass through DOMPurify with an
SVG profile that keeps the gradients, filters, patterns and same-origin `<image>`
the badge art uses while dropping scripting.

These were not exploitable — every caller builds markup from viem-decoded typed
values. But that is a property of the *callers*, not the sink, and the first
change that pipes a name or trait string into badge art would turn five inert
sites into stored XSS with nothing in between.

---

## A-6 (Informational) — admin secret comparison and brute force

**`api/fren-teach.ts`**

`===` replaced with `timingSafeEqual` over SHA-256 digests — hashing first makes
the comparison total and constant-time regardless of input length (raw
`timingSafeEqual` throws on length mismatch, which leaks length by itself).

Added a per-IP throttle on **failed** attempts (5/min). In-memory, so per warm
instance — honest about what a serverless function can enforce alone, and it
still turns an unbounded guessing loop into a slow one. This guards a write path
that feeds AUTHORITATIVE CORRECTIONS straight into the Guide's system prompt and
previously had no rate limit at all.

SQL was already correctly parameterized via `neon` tagged templates; unchanged.

---

## A-5 (Informational) — immutable `emergencyAdmin`

**Not fixed. Not fixable in place.**

`emergencyAdmin` is `immutable` and can pull an entire generation's LP. Adding
rotation means changing the constructor and redeploying the registry — and the
registry has **10 bytes** of headroom, so it cannot absorb a two-step
propose/accept handoff without the facet extraction described in the audit's
Phase 1.

Recorded as an accepted design risk. The mitigations that exist are real
(timelocked on mainnet, arming-gated even at delay 0), but the protocol's
headline claim of protocol-owned LP with no team rug rests on one key that cannot
be rotated. **This should be resolved at the next registry redeploy**, and is the
strongest independent argument for doing the Phase 1 facet extraction.

---

## Also fixed in passing

**Duplicate `GuildFunded` event.** `_takeEthFee` emitted `GuildFunded` for the
surtax, and `FeeRouteLib.routeSplit` already emits it from inside the delegatecall
— attributed to the hook, so an indexer could not tell them apart and
double-counted every surtax in the guild-funding feed. The duplicate is removed;
removing it also helped pay for the R-1 mapping.

## Pre-existing, untouched

`npm run test:unit` cannot run: it invokes `vitest` in watch mode, `jsdom` is not
installed, and there are **no test files** under `src/`. Unrelated to these
changes (`package.json` and `vitest.config.ts` are unmodified) and left alone,
but it means the frontend has no unit coverage at all — worth a separate look.

---

# Second pass — re-audit of the fixes

The first pass changed 466 lines across four layers. That made the fixes the
newest and least-reviewed code in the repo, so they got their own audit. Three
findings, two of them mine.

## S-1 (High) — `removeAsset` re-opened the historical over-claim hole

**Introduced by this remediation. Now removed.**

The D-2 fix shipped a treasury-gated `removeAsset` to reclaim the claim loop's
gas. It re-opened precisely what `test_LateJoinerCannotClaimHistoricalFees`
exists to close.

A debt marker of `0` means "entitled from this asset's inception" — correct for
an asset first funded while you were already enchanted, because `fundToken`
divided that deposit by an `activeShares` that included you. But `_castSpell` can
only set markers for assets currently in the list. Retire USDG, let a new holder
cast (marker stays `0`, USDG is not iterated), re-add USDG, and its accumulator
resumes from the old high-water mark — that holder is now owed the entire history
they were never part of.

Measured on a probe: **a fren owed 1005 USDG against a pot holding 10.** And the
D-2 fix makes it worse rather than better — the shortfall no longer reverts, it
banks to `owedAsset` as permanent phantom debt.

**Fix: `removeAsset` is gone**, with the reasoning recorded in the contract where
the next person will look for it. Every safe version needs a second retired-list
for `_castSpell` to walk, or a sentinel encoding to tell "uninitialised" from
"joined at zero" — more branching in the accounting that is hardest to reason
about and cheapest to get wrong, for a gas optimisation. The basket is capped at
`MAX_ASSETS` for the contract's lifetime; a fourth quote is a dividend migration,
which is a deliberate reviewed operation rather than a live mutation of a list
that per-holder debt markers are keyed against.

**Also added: invariant I-13**, which the audit had listed as UNENFORCED and
which catches this whole class —
`AuditPoC5::test_I13_EntitlementNeverExceedsWhatIsHeld`. For every asset, what
every enchanted fren can claim must be backed by what the contract actually
holds. No oracle, no prices; just the identity per-asset accounting exists to
give us.

## U-1 (High) — V-1's root cause had a second victim

**Pre-existing. Missed in the first pass.**

`_toUsd` changes what every recorded volume figure *means*: quote-raw wei become
USD at 1e18. `deathThreshold` was migrated when the oracle landed. Three
constants were not, and each is compared directly against that changed number:

| Constant | Compared against | Where |
|---|---|---|
| `volumePerNFT`, `nftPriceStep` | `nftCredit` | `_commitCrystals` |
| `oddsFullVolumeWei` | play size | `oddsForPlay` |

Left in ether terms against USD-scaled credit, a $3,000 ETH inflates every
trader's mint credit **~3000x** against a ladder priced in wei. The collection
over-issues by that factor and the odds curve pins to max for any trade —
silently, the moment the oracle is wired, with nothing reverting. An NFT that
earns perpetual dividends is not a figure to get wrong by three orders of
magnitude.

The contract cannot detect the mismatch: both sides are just 1e18-scaled
integers. So it forces the restatement instead. `setDeathThreshold` now takes the
ladder and the odds curve, and **reverts if you wire an oracle without restating
them**. That extends the maintainer's own rationale for combining the threshold
and the oracle — *"one decision… meaningless without knowing the units it is
compared in"* — to the three constants that share the same dependency.

15 call sites updated. Callers passing `address(0)` keep today's behaviour
exactly; the curve is only touched when an oracle is actually wired.

**Proof:** `CauldronHookAccess::test_U1_WiringAnOracleForcesTheUnitsToBeRestated`
and `test_U1_WithoutAnOracleTheCurveIsUntouched`.

## A-4 follow-up (Medium) — the sanitizer broke the badge art

**Introduced by this remediation. Now fixed.**

Verifying rather than assuming is what caught it: DOMPurify strips `<animate>`,
and the Liquidatoor's pulsing reticle uses it. Sanitizing without it would have
shipped a visibly dead badge.

It is stripped for a real reason — `<animate attributeName="href"
to="javascript:…">` mutates a static attribute into an active one *after*
sanitization, the one attack a static allowlist cannot see. So animation elements
are re-admitted behind a `uponSanitizeElement` hook that drops any whose
`attributeName` targets a link or event attribute.

Verified against the real element set: all 18 artwork elements survive
(`animate`, `image` with `xlink:href`, `clipPath`, `pattern`, gradients,
`feGaussianBlur`, `tspan`, …) and all six attack vectors are blocked, including
the `attributeName` mutation the blanket ban was protecting against.

## Closed with no finding

Two items the first pass listed under "what I could not verify":

- **Vendored `BaseHook`.** No upstream copy ships at the pinned v4-periphery
  revision, so it was audited on its own merits. Every external callback is
  `onlyPoolManager`-gated, and `validateHookAddress` runs in the constructor and
  is **not** overridden in `CauldronHook` — upstream makes it virtual so tests
  can bypass it, and production does not.
- **Hook permission bits vs the mined address.** Declared permissions
  (`afterInitialize`, `beforeSwap`, `afterSwap`, both returnDelta flags), the
  three implemented internal callbacks, and the deploy-script mining flags match
  exactly. No declared-but-unimplemented callback (which would revert
  `HookNotImplemented`) and none implemented-but-undeclared.

## Hardened further

- **Indexer GraphQL** now rejects a POST with **no** `Content-Length` (411) as
  well as an oversized one (413). A missing header means chunked encoding, which
  is exactly how the byte cap would have been sidestepped. Reading the body to
  measure it was rejected as a fix: it risks consuming the stream before Ponder
  parses it, and this is the frontend's whole read layer.
- **`_toUsd` trust delta documented.** The V-1 fix changed a `staticcall` to a
  `call`, which can re-enter where the former could not. `quoteOracle` therefore
  sits at the same trust tier as `feeRouter`, `deathChecker` and `surtaxPolicy` —
  all timelock-set, all already reached with plain calls from this same callback.
  It does not widen the hook's exposure class, but a compromised oracle is now a
  compromised hook, and that is stated in the code rather than implied.

## Noted, not changed

- **`CauldronHook` is at 54 bytes of margin.** It absorbed the per-asset reserve,
  the release path, the P-1 interlock and the U-1 unit coupling. It fits, but
  there is no room left for the next fix — which is the strongest practical
  argument for the Phase 1 facet extraction in the audit's migration plan.
- **`linkVolume` hard-depends on `perpEngine.openCount()`.** A `perpEngine` set
  to a contract without it would make `linkVolume` revert. Registry-only, and
  failing closed is the right direction here (do not diversify if you cannot
  verify perp exposure), so it is left as-is.
- **`askOllama` has no request timeout.** Added to `fren-ask.ts` by separate work
  while this pass was running. Consistent with the existing Groq and Gemini paths
  and bounded by `maxDuration: 30`; env-driven rather than request-driven, so no
  SSRF. Left alone as someone else's in-flight change.
