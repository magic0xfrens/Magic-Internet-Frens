# Reconciliation — FINAL_BLIND_2026-09-11 (directory pass) against everything before it

Role: reconciler. I read the six `verify/V*.md` (authoritative verdicts) and the six
`hunt/H*.md` (mechanism, refutations, leads) first, then the prior output:
`audit/FINAL_BLIND_2026-09-11.md` (a **different** review run earlier the same day),
`audit/REMEDIATION_2026-09-11.md`, `audit/CauldronRedTeamSafu.md`,
`audit/BLIND_REDTEAM_2026-09-09{,_B0x,_B05-B06}.md`, `audit/DEEP_AUDIT_2026-09-08.md`,
`audit/REMEDIATION_2026-09-08.md`. Source checks are against `/tmp/blind-final/contracts/solidity`
(line numbers identical to the repo) and `git log -S`.

Prior-report ID namespaces used below:
`R-1…A-6` = DEEP_AUDIT_2026-09-08 / REMEDIATION_2026-09-08 · `B-0x` = BLIND_REDTEAM_2026-09-09 ·
`R-01…R-09` = CauldronRedTeamSafu / REMEDIATION_2026-09-11 · `C-x / H-1 / M-x / O-x` =
FINAL_BLIND_2026-09-11 (flat file).

---

## 1. Every finding of this pass, bucketed

| # | Sev | Finding | Bucket | Justification (prior id / commit) |
|---|-----|---------|--------|-----------------------------------|
| X4a/X1a | Critical | legacy buffer native-vs-quote denomination | **fix-induced** | `577a332` (2026-09-10) "the collection-floor buyback works in any quote, not just ether" generalised `LegacyBuyLib.buyStep`'s settle and removed the native-only skip that was the safety; `fundLegacyBuffer` stayed native |
| X3a | High | rotation redenominates `tokYieldEth`/`insuranceEth`/`payoutOwed` | **fix-induced** | the cited line **is** the R-08 fix: `PerpEngine.sol:1098 if (newQuote != quote && plv != 0) revert VaultStaked();` (REMEDIATION_2026-09-11 R-08, code in `1e98bb4`) |
| X3c | High | stale `PerpVault` exit queue survives rotation | **fix-induced** | same R-08 guard, and R-09 built the exact primitive (`PerpVault.hasStakers()`) that R-08's guard does not call |
| X3b | High | `_creditPerp` native ingress, no `_quoteIsNative()` | **missed by prior passes** | B-03 (09-09) read `_creditPerp` and filed a *different* Low about it; no prior pass drove an ERC20-quoted perp book |
| X3d | High | permissionless mark-ring reset collapses TWAP | **new** | no prior document mentions `delete observations` / the warm-up not being re-armed |
| X2a | High | migration envelope starved via a secondary leg | **fix-induced** | the C-3 fix (same-day, `1e98bb4`) split `movedBps`→`movedPrimaryBps` but left *deactivation* on the unsplit counter — third generation of R-04 → C-3 → X2a |
| X2e | High | frozen residual after migration | **still-open** | = **O-10**, VERIFIED and never fixed in FINAL_BLIND_2026-09-11; this pass upgraded it DERIVED → VERIFIED with a fork PoC |
| X5a | High | genesis ignite ignores `cancelled` | **new** | `AlreadyCancelled` has existed since `d8461b3`; it was never a gate in `igniteCauldron`, and no prior pass read that function |
| X5c | High | vault close sweeps native, `PoolOps:1356` divides by a quote-denominated `totalETH` | **missed by prior passes** | H-1/O-9 audited this exact arithmetic pair for the *base count* and fixed one half; nobody asked what unit `swept` and `totalETH` were in |
| X6b | High | UI encodes a perp `openLong` selector the engine lacks | **new** | FINAL_BLIND_2026-09-11 §9: the off-chain agent "died to a session limit and was not relaunched" |
| X6d | High | `/api/brand` unauthenticated | **new** | `api/brand.ts` untouched since `d8461b3`; not among the A-1…A-6 routes reviewed on 09-08 |
| X1b | Medium | surtax jitter steerable by a same-tx tick probe | **fix-induced** | B-03's fix (`d3c10a1`, 2026-09-09) turned `max(decayed, jitter)` into `decayed + jitter`, making dead jitter live, and *deliberately* left the tick entropy source. Also = **O-4** |
| X2b | Medium | `recoverLegs` has no forwarder | **missed by prior passes** | M-1's ABI-diff found 4 unrouted facet functions and classified two "unrouted by design"; `recoverLegs` was one of them |
| X2d | Medium | spam erases a **stockpiled** mandate | **PRIOR FIX FAILED (partial)** | B-10 fix `dd570c7` added `_runnerId`/`_runnerVotes` and claims "spam cannot displace it"; the positional window `CauldronGovernor.sol:478-483` is unchanged, so anything below the runner-up still dies. Also = **O-6** |
| X4b | Medium | gacha `_churn` confiscates a partial-fill refund | **new** | no prior document covers `CauldronGachaRouter._churn` |
| X6a | Medium | UI rotation `minOut` flat 1 token | **new** (UI) — on-chain half **re-confirmed safe** | the floor that caps it (`QuoteRotator.sol:355,365-366`) is R-01's fix, independently re-confirmed here |
| X6c | Medium | fren-ask host-controlled doc fetch | **PRIOR FIX FAILED (never landed)** | **A-1**, reported fixed in REMEDIATION_2026-09-08 ("pinned to a constant, overridable only through `FREN_DOCS_URL`"). `FREN_DOCS_URL` appears in **no commit**; the header fetch is verbatim |
| X6e | Medium | `keeper.sh` binds before sourcing env | **new** | operator scripts never reviewed |
| X6f | Medium | perp close signs `minOut = 0` | **new** | UI never reviewed |
| X2c | Low | oracle cache keeps its old factor (**refuted as stated**) | **re-confirmed safe** (prior-open refuted) | = **O-1** (prior High, "16.4% ROI"). Patching the named line changes nothing: a dead feed still serves a 10-year-old price, and the implied fix removes the floor entirely |
| X2f | Low | guardian settable to zero | **missed by prior passes** | prior pass DERIVED the *opposite* ("the guardian is unremovable and self-perpetuating"); `setGuardian` has no zero check |
| X2g | Low | dead `completeRotation`; `_safeTransfer` codeless success | **missed by prior passes** | a **fourth** unrouted facet function M-1's ABI-diff did not report |
| X4c | Low | `FeeRouteLib._fundGuild` codeless-recipient success | **new** | the 09-09 pass proved `fundToken` return handling and never asked about a codeless guild |
| X5b | Low | LaunchSniper dead selector | **new** | `LaunchSniper` appears in no prior document |
| X5d | Low | `deployments/*.json` inconsistency | **new** | ops artefacts never reviewed |
| X6g | Low | phantom `UnclaimedBurned` indexer event | **new** | indexer never reviewed |
| X6h | Low | keys in argv (7 scripts) | **new** | scripts never reviewed |
| X6i | Low | `api/x-token` unthrottled | **new** | sibling of A-6 (`fren-teach`); this route was not in that sweep |
| X6j | Low | `liquidatoor.ts?col=` reads any contract | **missed by prior passes** | A-4 sanitized five **frontend** SVG sinks; this is the **server-side** SVG route the sweep never reached |
| X1c | — | `setTaxExempt` (**refuted**) | **re-confirmed safe** (prior false positive) | prior pass filed it VERIFIED-open; refuted by `DeployLaunchpad.s.sol:241 hook.setOpener(address(gacha), true)` |
| X4d | — | dividend basket cap (**refuted**) | **re-confirmed safe** | = **D-1** (09-08, "anyone can permanently close the basket"), fixed by the funder gate; attacked here and it held at `MiFrensDividend.sol:278` |

**Counts:** new 14 · still-open (prior-known, unfixed) 1 · fix-induced 5 · prior fix failed 2 ·
re-confirmed safe 3 · missed by prior passes 6. **Total 31.**

---

## 2. Fix-induced — the code that carries it was written by a prior remediation

### X4a/X1a (Critical) ← commit `577a332`, 2026-09-10
The commit generalised `LegacyBuyLib.buyStep` from `poolManager.settle{value: spent}()` to a
currency0 branch. Its own diff comment states what it was undoing: *"the hook refused to buffer a
non-native fee at all … Skipping the buyback was the safe workaround; generalising the settlement
removes the reason for it."* The same commit **did** think about the mixed-denomination hazard —
it replaced the hook's `_feeAsset == address(0)` credit with a live-quote **match** at
`CauldronHook.sol:1318` and wrote *"It is replaced by a MATCH, not by nothing … buffering both
would have the library try to pay USDG amounts as ether."* It then closed one of three doors:
`CauldronHook.sol:1340` (`_feeAsset == address(0)` → `legacyBuffer += wantFloor`, no live-key
match) and `CauldronHook.sol:1096 fundLegacyBuffer()` (permissionless, payable, native, uncapped,
fed by `RoyaltyRouter.sol:33` on every marketplace royalty) were left native. The library header
still says *"ETH-QUOTE ONLY … The caller gates on that"* and `_maybeLegacyBuyback`'s comment still
says *"the native settle would revert against an ERC20 quote anyway"* — both prose describing the
gate this commit deleted. Two independent verifiers confirmed Critical; no reset path exists at
any privilege level.

### X3a + X3c (High ×2) ← R-08, REMEDIATION_2026-09-11 (code in `1e98bb4`)
R-08's fix line *is* the finding: `PerpEngine.sol:1098 if (newQuote != quote && plv != 0) revert
VaultStaked();`. R-08 chose refusal over conversion and priced it (§4.1: "Rotation and a funded
perp engine are mutually exclusive"), but `plv` is not a proxy for `tokYieldEth`, `insuranceEth`,
`payoutOwed` (X3a) or the vault's `pendingEth` (X3c). X3c is the sharper one: `totalEth() = plv +
longOiEth` and `syncGeneration` forces `longOiEth == 0`, so `plv == 0` — the state in which the
guard *passes* — is exactly when the queue is maximally unbacked. R-08's own escape clause ("the
refusal lifts the moment the vault drains") is unenforceable: `PerpVault.sol:295` writes the
haircut to zero and `:296 if (owed == 0) revert ZeroAmount();` rolls it back in the same
transaction. And **R-09, in the same remediation, built the correct primitive** —
`PerpVault.hasStakers() = (ethShares | tokShares | pendingEth | pendingTok) != 0` — for
`setVault`. R-08's guard does not call it.

### X2a (High) ← the C-3 fix, FINAL_BLIND_2026-09-11 (same day, `1e98bb4`)
C-3 was itself a regression of R-04. Its fix added `Envelope.movedPrimaryBps` and
`consume(uint16,bool fromPrimary)` so that "secondary legs stay rotatable under the same envelope
… but cannot declare a migration done". It split the *completion* test and left the *deactivation*
test on the unsplit counter: `TreasuryGovernor.sol:708-718` debits `movedBps` on every call and
deactivates at `movedBps >= maxTotalBps`, while `migrationMandateSpent()` (`:683`) reads
`movedPrimaryBps`. A permissionless `rotateSliceFrom(fromLeg != 0, …)` therefore burns the whole
envelope without ever advancing the migration, and `:387`'s 7-day `CooldownActive` blocks the
corrective proposal. Precondition narrowed by the verifier: needs one pre-existing leg in a quote
different from the envelope's destination — impossible on a first migration, routine afterwards.
**R-04 → C-3 → X2a is three remediations deep on one counter.**

### X1b (Medium) ← B-03's fix, commit `d3c10a1`, 2026-09-09
B-03 proved the jitter was dead code (`jitter ≤ decayed` for all inputs under `max`) and fixed it
to `min(decayed + jitter, maxBps)`, so the jitter now genuinely raises the rate. The same report
states: *"I deliberately did **not** touch the entropy *source* (the tick's knowability to a
first-in-block sniper is the pre-existing, documented L-02 tradeoff) — only made the existing
jitter apply."* Making a dead term live turned a documented, inert trade-off into a live,
steerable one — a same-tx probe swap sets the tick that seeds it (3198 bps swing measured).

### PRIOR FIX FAILED — X6c ← A-1 (never landed)
REMEDIATION_2026-09-08 A-1: *"Now pinned to a constant, overridable only through `FREN_DOCS_URL`,
with a 5s timeout."* `git log -S 'FREN_DOCS_URL' -- api/fren-ask.ts` returns **nothing** —
the identifier appears in no commit in the repository's history — and `api/fren-ask.ts:55-64`
reads verbatim:

```ts
const host = (req.headers["x-forwarded-host"] || req.headers.host) as string;
const proto = (req.headers["x-forwarded-proto"] as string) || "https";
const res = await fetch(`${proto}://${host}/llms-full.txt`, { headers: { accept: "text/plain" } });
```

The only commits that have ever touched this file are `c3dc671 push` and `dd570c7` (which fixed
the *rate limiter*'s leftmost-`x-forwarded-for` bug, not this). The A-1 fix was reported and never
shipped. V6 downgrades the impact to Medium (self-scoped, `no-store`), but the remediation record
is wrong.

### PRIOR FIX FAILED (partial) — X2d ← B-10, fix commit `dd570c7` (2026-09-10)
`dd570c7` added an explicit two-deep carry — `_runnerId` / `_runnerVotes`, with the comment
*"Spam cannot displace it: both …"* — and shipped `test/audit/B10_ScanWindowErasure.t.sol`. That
half holds: V2's counter-argument landed, and `_bestUnconsumed` returns `_leaderId` directly, so
**any freshly voted proposal is immune to unlimited spam**. What the fix did not change is the
shape of the scan: `CauldronGovernor.sol:478-483` is still a positional window
(`first = n > MAX_LEADER_SCAN ? n - MAX_LEADER_SCAN + 1 : 1`), so a settled mandate that is
neither leader nor runner-up is erased by 64 filings and can never be re-cached (`vote` reverts
`VotingClosed()` at `:337`). Downgraded to Medium here, but the fix is partial, not complete.

---

## 3. Re-confirmed safe

### X4d ← D-1 (DEEP_AUDIT_2026-09-08, High), fixed in REMEDIATION_2026-09-08
D-1 was *"anyone can permanently close the dividend basket with junk"*. The fix made `fundToken`
funder-gated. This pass attacked the cap and it held: `MiFrensDividend.sol:278 if (msg.sender !=
funder) revert NotOwner();` runs **before** `:282`'s `MAX_ASSETS` check, so no stranger can append
a slot; and a fourth asset's revert is swallowed by `FeeRouteLib._fundGuild` and rolls to
`relaunchAsset[]`, so nothing is destroyed. Matches the 09-09 pass's own "proven safe" note.
Residual: a stale comment (`:480` says "why MAX_ASSETS is 4"; the constant at `:124` is 3).

### X1c ← "setTaxExempt alone is inert", FINAL_BLIND_2026-09-11 Medium/Low list, **VERIFIED**
This is a **prior false positive**, refuted here. The prior claim was that both deploy scripts set
`taxExempt` without `isOpener`, so "the snipe wallet believes it pays 0 and pays 99%". The missing
half is present: `deploy/DeployLaunchpad.s.sol:241 hook.setOpener(address(gacha), true);`, and
`LaunchSniper.sol:76` never swaps as itself — it calls `IGachaPlay(gachaRouter).play{value:}(…)`,
so `sender` is the opener and `_taxedPlayer` (`CauldronHook.sol:2391-2394`) decodes the sniper.
The `SNIPE_WALLET` half is refuted a fortiori: an EOA can never be `sender`, so tagging through an
opener is the only path that could ever have worked — and it is the path taken.

### X2c ← O-1 (FINAL_BLIND_2026-09-11, **High**, "measured +1.639 ETH on 10 ETH, 16.4% ROI")
No fix ever landed for O-1; this pass attacked the named mechanism and it is **not load-bearing**.
V2 edited the source to O-1's implied fix — `QuoteOracle.sol:309` `c.at = uint64(block.timestamp);`
→ `if (fresh > 0) c.at = …` — and re-ran: only the assertion *about `c.at`* flipped.
`afterOneTtl == afterOneYear == afterTenYears == f0`. The freeze comes from the documented tail
(*"A refresh that comes back unusable keeps the LAST GOOD value"*), not the re-stamp.

**Both arguments, since this reverses a prior High:**
- O-1: *"`c.at` is written unconditionally, `c.factor` only on success, so a failing feed re-arms
  the TTL and the cache never expires. It is the entire price floor on a permissionless rotation
  slice."*
- This pass: the re-stamp only decides whether the 30k-gas feed read is re-attempted; and the
  implied fix is **strictly worse** — a zero factor makes `QuoteRotator._usd` return 0, so
  `_oracleFloor` returns 0, which *"FAILS OPEN, DELIBERATELY … the caller's `minOut` stands
  alone"*. A stale floor is a degraded guard; the alternative is no guard.

Surviving residual (Low): `priceable()` reports false while `cachedUsdPerRawUnit` keeps pricing,
so `TreasuryGovernor._requirePriceable` blocks *new* envelopes into an asset that in-flight
rotations still price off a dead feed.

### Cross-reference: R-01 held (relevant to X6a)
X6a's on-chain half is R-01's fix and it holds independently for the second pass running:
`QuoteRotator.sol:355` `allowedVenue[PoolIdLibrary.toId(route)]` and `:365-366`
`if (out < (minOut > floor ? minOut : floor))` take the **max** of the caller's `minOut` and an
oracle floor the caller cannot lower (`rotationSlipBps = 300`, owner-capped at 2000). The UI's
decorative slippage box is real, but the ~99.999% loss the hunter computed cannot execute on a
deployment with the oracle wired — the same conclusion the prior pass reached when it retracted
the predecessor session's "94% of the slice extracted" claim.

---

## 4. Missed by prior passes — and honestly why

- **X3b** (`_creditPerp` native ingress). B-03 (09-09) read this exact function at what was then
  `:1495` and filed a *different* Low (sell-fee misrouting), and B-02 (09-09) read
  `syncGeneration`'s denomination hazard and named `minCollateral`/`insuranceFloor`/`tierDepthWei`
  — not the ingress. **Why missable:** the prior pass's own coverage-gap list says it: *"No test
  drives a non-native (ERC20-quoted) perp book. `YBase._boot` only stands up a native-quote
  generation, so `creditPerpFeeAsset` and the ERC20 payout path were read, never executed."* The
  reachability argument also needs `CauldronHook._feeAsset` and `registry.generationQuote(gen)` to
  be recognised as two different sources — which only a rotation makes visible.
- **X5c** (`PoolOps.sol:1356`). H-1 and O-9 audited the neighbouring arithmetic in the same file
  — the *population* of `activeBase` vs the ledger's `retired` — and H-1's fix landed 12 lines
  away in `recycleCollection`. **Why missable:** they were hunting the numerator's base, not the
  denominator's currency, and the registry's own comment (`CauldronRegistry.sol:936-937`,
  *"`totalETH` keeps its name for the native case it is usually carrying, but it is now
  denominated in `specQuote`'s OWN units"*) reads as a resolved note rather than a live hazard.
- **X2b** and **X2g** (`recoverLegs`, `completeRotation` unrouted). M-1 (same day) ran exactly the
  right method — ABI-diffing the facet against the dispatcher — found four unstubbed functions,
  stubbed `sweepLegProceeds`, knowingly left `legProceedsOf`, and classified the remaining two as
  "unrouted by design". **Why missable:** `recoverLegs` *is* called, from inside `_removeLiquidity`
  via the `RECOVER_LEGS` selector constant (`CauldronRegistry.sol:63`), so it looks routed; what is
  unreachable is the **retry** the header promises. `completeRotation` is simply dead weight
  against EIP-170. Both are defence-in-depth, correctly held at Medium/Low.
- **X2f** (guardian settable to zero). The prior pass DERIVED the **opposite** conclusion —
  *"TreasuryGovernor's guardian is unremovable and self-perpetuating"*. `setGuardian`
  (`:523-526`) has no zero check, so it is removable, terminally. A DERIVED claim that was never
  executed against the source.
- **X6j** (`liquidatoor.ts?col=`). A-4 (09-08) swept SVG injection sinks and shipped
  `src/lib/safeSvg.ts` across five `dangerouslySetInnerHTML` call sites, then a follow-up
  Medium for the sanitizer breaking the badge art. **Why missable:** the whole sweep was scoped to
  `src/`; the server-rendered badge in `api/cauldron/liquidatoor.ts` was never in it. (V6's verdict
  — typed ABI decode, no markup injection possible — means the sanitizer would not have been the
  fix anyway.)

---

## 5. Reverse direction — prior findings marked OPEN/UNFIXED that this pass did **not** re-find

Source presence checked in `/tmp/blind-final/contracts/solidity` unless noted.

| Prior id | Mechanism | Still there? |
|---|---|---|
| **O-2** (High) | queued vault exits 100% senior to live shares — `_haircut` measures the queue against the *whole* vault | **YES.** `PerpVault.sol:295 _haircut(owed, engine.totalEth(), pendingEth)` with `PerpEngine.sol:466 totalEth() = plv + longOiEth`. X3c quoted these same lines for a different purpose and walked past the seniority |
| **O-3** (High) | `plvToken` *assigned*, not adjusted, at sync — whatever failed to migrate is written to zero | **YES.** `PerpEngine.sol:1051 plvToken = newInv;`, four lines above the ring reset X3d attacks |
| **O-5** (High) | envelope hijack — `execute` enforces neither one-envelope-at-a-time nor the cooldown `propose` enforces | **PARTLY CLOSED.** `TreasuryGovernor.sol:488 if (id != winner()) revert DidNotPass();` now blocks the runner-up execution the finding described. Still no `envelope.active` or cooldown test in `execute` (`:478-511`). Not re-tested this pass |
| **O-7** (High) | treasury scan flood — one FOR-vote every ≤5 days pins the O(1) hint on a corpse | **YES.** `_leadVotes` (`:164`) and the reverse scan `:593 for (uint256 i = n; i >= 1; --i)` both present |
| **O-8** (High) | `MigrationVesting.vestBatch` permissionless, `_release` unpaginated | **YES.** `MigrationVesting.sol:153` + `:221-223 for (uint256 i; i < gs.length; )` |
| **O-9** (High) | live collection floor divides a forged-only pot by an OG-inclusive count | **NOT RE-CHECKED.** H-1's fix landed in `recycleCollection`; whether it closed O-9's 12.11× under-payment was outside what I verified. X5c hit the adjacent `crystallizeCollection` |
| **B-02** (09-09) / prior M | `minCollateral` an absolute 18-decimal constant vs a 6-decimal quote | **YES.** `PerpEngine.sol:144 uint256 public minCollateral = 0.003 ether;` compared at `:786`/`:823`. Fails safe |
| prior M | `quoteScale` write-only dead storage | **YES.** Written `CauldronRegistry.sol:174` and `:305`, declared `CauldronBase.sol:368`, **read nowhere** outside the public getter |
| prior M | `sweepLegacyReserve` takes a caller-chosen `token` while the counter accrues in another | **YES** (read by V4 while refuting X4a counter-arg 3: it moves `legacyOwedToReserve` tokens and cannot touch `legacyBuffer`). Not separately attacked |
| prior M | `renounceOwnership` live on `CauldronGovernor` and `MigrationVesting` | **YES.** `CauldronBase.sol:417` blocks it only for `CauldronBase` inheritors; neither of those two inherits it |
| prior M | gacha reveal grindable via the expired-seed re-anchor (`MiFrensGenesis.sol:532-537`) | **NOT RE-CHECKED.** H5 covered `MiFrensGenesis` and found X5a instead |
| prior M | TEST-SUITE INTEGRITY — nine `vm.warp` functions CSE'd under `via_ir`, incl. `test_FullLifecycle_ToRound3_OnFork` | **NOT RE-CHECKED.** No agent this pass audited the existing suite |
| **A-2 / A-3 / A-5 / A-6** (09-08) | GraphQL byte cap, indexer freshness gate, immutable `emergencyAdmin`, `fren-teach` secret comparison | **NOT RE-CHECKED.** H6 covered `fren-ask`, `brand`, `x-token`, `liquidatoor`, the indexer event table, the UI and the scripts; these four were out of its sample |
| FINAL_BLIND leads 1–6 | sequencer-restart window, `arbStep` under a frozen cache, hook volume collapse with no oracle, `PerpMarkSource` not following a rotation, `_castSpell` CEI, `_leadVotes` poisoning | **NONE ADVANCED.** X2c partially touches lead 2's premise (the cache is stale by design, not by the re-stamp), which makes leads 1 and 2 cheaper to settle, not settled |

**14 prior-open findings were not re-found. 8 of them I confirmed still present in source; 6 I did
not re-check and say so.**

---

## 6. What the blind method bought, and what it missed

It bought the thing anchored review structurally cannot buy: **two independent hunters, given no
finding list, converged on the same Critical from opposite ends of the codebase** (H1 through the
hook's fee router, H4 through the NFT royalty path) — and one of them found the *brick* branch the
other's *drain* framing had under-rated. It also bought the honest reverse: three findings a prior
pass had filed with confidence (O-1's 16.4% ROI sandwich, the `setTaxExempt` inert-exemption, the
guardian being "unremovable") did not survive contact with a verifier who did not know they were
supposed to be true. And the single strongest regularity in this repo held for the fourth
consecutive pass: **five of this pass's top findings live in code a prior remediation wrote**, and
the one Critical sits in a commit whose own diff comment shows the author reasoning about exactly
this hazard and closing one of three doors.

What it missed is the price of blinding. Because nobody was allowed to read the prior reports,
**14 known-open findings were not re-tested** — including two Highs (O-2, O-3) whose lines this
pass's own verifier quoted verbatim while chasing a different bug, which is the clearest
demonstration that the hunters were reading the right code and had no way to know the seniority
and the assignment beside it were already on a list. The blind sample was also uneven: six agents
over a codebase where the prior pass's off-chain agent had died meant `api/`, `src/`, `indexer/`
and `scripts/` got their first review ever (and yielded 12 findings, one of them a remediation that
was reported and never committed), while the perp engine got its fourth. And two prior remediation
*claims* — A-1's `FREN_DOCS_URL` pin and B-10's "spam cannot displace it" — were only caught
because a reconciler was allowed to diff the report against `git log`. No blind hunter could have
found those, because from inside the tree there is nothing to notice.

---

## 7. PoCs — not copied (per revised instruction)

Fixers are working in the real tree and own their own regression files, so nothing was copied and
no file under `contracts/` or `test/` was touched. **Had step 5 run, these 14 would have been
copied** (13 surviving hunter PoCs + 1 verifier-written):

```
/tmp/blind-final-h1/.../test/attacks/X1a_LegacyBufferDenomination.t.sol
/tmp/blind-final-h1/.../test/attacks/X1b_SurtaxJitterSteerable.t.sol
/tmp/blind-final-h2/.../test/attacks/X2a_MigrationMandateStarvation.t.sol
/tmp/blind-final-h2/.../test/attacks/X2b_StrandedLegNoRetry.t.sol
/tmp/blind-final-h2/.../test/attacks/X2d_MandateErasedBySpam.t.sol
/tmp/blind-final-h2/.../test/attacks/X2e_FrozenResidualAfterMigration.t.sol   (written by V2)
/tmp/blind-final-h3/.../test/attacks/X3a_QuoteRotationRedenominates.t.sol
/tmp/blind-final-h3/.../test/attacks/X3b_NativeCreditIntoErc20Plv.t.sol
/tmp/blind-final-h3/.../test/attacks/X3c_StaleQueueSurvivesRotation.t.sol
/tmp/blind-final-h3/.../test/attacks/X3d_RingResetCollapsesTwap.t.sol
/tmp/blind-final-h4/.../test/attacks/X4a_LegacyBufferDenomination.t.sol
/tmp/blind-final-h4/.../test/attacks/X4b_ChurnConfiscatesRefund.t.sol
/tmp/blind-final-h5/.../test/attacks/X5a_GenesisCancelledIgnite.t.sol
/tmp/blind-final-h5/.../test/attacks/X5b_SniperSelectorDead.t.sol
/tmp/blind-final-h5/.../test/attacks/X5c_VaultSweptDenomination.t.sol
```

**Deliberately left behind:** `X2c_FrozenOracleCache.t.sol` — the finding was refuted as stated
(the PoC passes but asserts a re-stamp that is not the cause; keeping it would pin the wrong
invariant). X4d and X1c have no PoC. X1a and X4a are two independent PoCs for the same Critical
and both are worth keeping — they cover the drain branch and the brick branch respectively.
