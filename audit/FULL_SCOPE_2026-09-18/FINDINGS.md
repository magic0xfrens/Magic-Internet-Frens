# Findings and Remediation Ledger

Status values: `OPEN`, `PATCHED-UNVERIFIED`, `FIXED`, `CANDIDATE`, `ACCEPTED-LOW`, `REJECTED`.

| ID | Severity | Component | Finding | Status |
|---|---|---|---|---|
| CORE-01 | High | `DeployLaunchpad.s.sol` | Direct launch script defaulted to a freely mintable mock quote and a Sepolia-only feed without an in-script chain gate. | FIXED |
| HOOK-01 | Medium | `CauldronHook.sol` | Buyback trigger compared an 18-decimal configured threshold with raw live-quote units, making a 6-decimal generation require an economically unreachable buffer. | FIXED |
| PERP-01 | Medium | `PerpEngine._rebook` | Partial short settlement set `collateral = 0`, erasing the basis for later funding, liquidation penalty, keeper reward, and badge bounty. | FIXED |
| ROT-01 | High (conditional on missing oracle and adverse venue price) | `QuoteRotator.swapOnce` | Current source again exempts an unset oracle from the zero-floor rejection; prior remedy is absent. | OPEN |
| ROT-02 | Medium | `RedemptionExt.rotateSliceFrom`, `_recordLeg` | Returning to the launch quote creates a second treasury position; the next migration credits the depleted original position instead of the larger returned treasury. | FIXED |
| CORE-02 | Low | `DeployRenderer.s.sol` | `BATCH=0` makes the post-deployment upload loop non-terminating. | OPEN |
| HOOK-02 | Low (governance-selected hostile metadata) | `CauldronHook._cacheLegacyThreshold` | Unbounded metadata gas consumption can exhaust a bounded setter call; 200k fails atomically, 2M succeeds in the local reproduction. | OPEN |
| NFT-02 | Low (protocol-controlled callback dependency) | `MiFrensDividend._castSpell` | Fee collection before activation permits a malicious wired registry to double-count a share; historical Z-13, not a passing reentrancy defense. | OPEN |
| PERP-02 | Medium | `PerpVault._syncTokYield` | A delayed write-off sync double-counts still-backed yield and masks a later write-off, letting stale rewards consume another staker's new yield. | FIXED |
| UI-01 | Medium | `useTreasuryRotation` | Native-return allowance is misclassified as idle by the zero-address destination. | FIXED |
| UI-02 | Medium | `TreasuryRotation` | Venue route uses generation denomination instead of the selected source leg. | FIXED |
| API-01 | Medium (credential-bearing RPC configuration) | `api/cauldron/creature.ts` | Public metadata serializes RPC errors containing provider URL credentials. | FIXED |
| IDX-01 | Medium | Indexer pool discovery and market selection | Rotation destination pools were not indexed; consumers assumed one pool per generation. | FIXED |
| NFT-01 | Medium (holder interaction required) | `CauldronVault.redeem` | Donated/forced ETH re-enables burning despite unified-floor mode, bypassing the token-floor lifecycle. | FIXED |
| UI-03 | Low | Cauldron volume/phase display | Selected-market quote volume is rendered as ETH and compared with a differently denominated death threshold. | OPEN |
| PERP-03 | Medium | `PerpEngine._settle` | A partial owner short close bypasses nonzero `minOut` and mutates settlement state while paying zero output. | PATCHED-UNVERIFIED |
| GAS-01 | Low | Pre-trade liquidation gas budget | Four-position fixture needs a 3M gas cap versus 400K without positions, exceeding an old <=4x test expectation. | OPEN |
| PERP-04 | Medium (historical insolvency reproduction; current traversal/liveness acceptance reopened) | `PerpEngine._doSweep` | Current cap/check-only implementation differs from the verified traversal patch; seven large-book/deferred-badge regressions fail. | OPEN |

PERP-04 reproduction and remedy boundaries: `REVIEW_PRESWEEP_COMPLETENESS.md`.

**Acceptance correction (supersedes the table's provisional `FIXED` labels):**
those labels recorded patches plus focused test outcomes, not completed
acceptance. Treat a row with outstanding finding-specific acceptance checks as
`PATCHED-UNVERIFIED` until its evidence is reconciled. In particular HOOK-01
metadata/layout checks, ROT-02 selector/legacy reconciliation, PERP-02 real
engine/rotation integration, and NFT-01 deployment/lifecycle acceptance remain
open in the descriptions below. Do not report all thirteen as fully verified
fixes. Unrelated global graph gaps do not themselves invalidate an individual
fix; the missing finding-specific checks must be evaluated individually.

See `REVIEW_DIVIDEND_CALLBACK.md` for NFT-02: the local reproduction asserts
phantom shares and stranded entitlement. Retained unfixed per the owner's
Low/Informational exception. No ordinary-holder production callback path has
been demonstrated; the fixture substitutes the treasury-wired registry.

## CORE-01 — unsafe mock quote/feed deployment defaults

Evidence and impact are documented in `REVIEW_CORE.md`. The local patch:

- changes `DEPLOY_QUOTES` from opt-out to opt-in;
- rejects the integrated freely mintable quote stack on every chain except Sepolia;
- permits feed addresses to be supplied explicitly;
- requires feed bytecode and a nonzero live oracle result before continuing; and
- adds `DeployLaunchpadSafety.t.sol` to pin the chain allowlist.

Three focused tests now pass against the actual `run()` entry point, rejecting mainnet mock quotes, a codeless native feed, and a stale native feed before signer/config loading or broadcast. Tests use one thread because `vm.setEnv` modifies process-global environment. Final production build and broader configuration acceptance remain pending.

## HOOK-01 — buyback threshold decimal-domain mismatch

The configured threshold is now treated as an 18-decimal whole-quote-token quantity and cached in raw units whenever the live quote or threshold changes. Ordinary failed/short metadata responses degrade to a one-raw-unit trigger; adversarial metadata gas/return-data behavior still requires review. This normalizes decimals, not prices between quote assets. The cache is appended to the storage layout.

Acceptance requires:

- the 6-decimal regression and 18-decimal control to pass;
- native and denomination-rotation regressions to pass;
- storage-layout and EIP-170 size checks; and
- review of malformed and greater-than-18-decimal metadata behavior.

Continuation: `REVIEW_HOOK_THRESHOLD_ACCEPTANCE.md` records 9/9 passing tests
(seven new plus two inherited), including 512 metadata fuzz cases, decimal
scaling/saturation, configuration refresh and denomination cache transitions.
Current-source artifact is 23,762 bytes; cache field is appended at slot 69.
Hostile metadata resource use, actual native-pool execution and baseline layout
parity are not established by those tests; acceptance remains incomplete.

## PERP-01 — partial rebook erased economic obligations

Direct source evidence showed `_rebook` writing `p.collateral = 0` and moving all remaining backing into `principal`, while `_fundingDelta` and liquidation penalties derive from collateral. The patch spends principal first, preserves collateral up to the remaining backing, and maintains `collateral + principal == newBacking`. The existing `D04_RebookErasesFundingAndPenalty.t.sol` asserts this invariant but requires a live fork in its current harness.

The deterministic local V4 partial-close test now passes against production PoolManager and PerpEngine with fixture hook/registry dependencies. It asserts the partial-close event, reduced nonzero size, retained collateral, backing conservation and subsequent funding. The isolated rebook suite also passes two unit tests and 256 fuzz cases. Broader liquidation, funding proportionality, generation-sync, and size acceptance remain open.

## ROT-01 — missing oracle bypasses treasury rotation floor

VERIFIED at the production rotator boundary: `swapOnce` rejected a zero floor only when `quoteOracle != address(0)`. `RedemptionExt.rotateSliceFrom` is permissionless and forwards caller-selected `minOut`, so registry-only forwarding does not make that minimum trustworthy. An allowlisted pool can still offer an adverse execution price.

The local integration test uses the real V4 PoolManager, a curated native/quote pool at 1:1 with 10 units of liquidity, and the production rotator. A 5-unit trade with `minOut=1` unexpectedly succeeded with an unset oracle (the rejection assertion failed). The same trade with a fresh independent 1:1 oracle reverted for slippage; a small trade succeeded and conserved input/output balances. The fixture models registry allowlisting/forwarding; a full registry lifecycle exploit has not yet been reproduced.

The patch requires `floor != 0` regardless of oracle configuration. This intentionally pauses this path until independent pricing is configured/restored. The older X2c regression's explicit no-oracle bypass expectation was changed to require rejection; it was an unsafe policy expectation, not a valid compatibility invariant. Owner-planned `rotateStep` retains its separately governed rate bound. Post-patch focused regression passed (43 tests across six suites, including all four real V4 rotation tests and three X2c tests). Both rotation deployment paths contain `setArbParams(address(oracle), ...)` wiring; deployed configuration is not attested. Broader lifecycle/full-suite acceptance remains pending.

## ROT-02 — round-trip rotation misclassifies the returned treasury

VERIFIED against a local production V4 PoolManager, PositionManager, Permit2, registry, hook, redemption facet, TreasuryGovernor and QuoteRotator. A mock quote and fixed voting supply are fixture dependencies; native and quote are explicitly pegged 1:1 for this test. No target storage is forced. The canonical Permit2 system contract is bootstrapped with its actual constructor/runtime in the test EVM.

`RotationLifecycleLocalTest` executes a successful 10,000-bps migration in four allowed 2,500-bps slices, votes to return to native, and executes another four slices. Two assertions fail before the patch:

- The return creates a second native position (`legCount == 2` versus the expected single foreign leg plus consolidated launch active position).
- A subsequent 2,500-bps slice from the larger returned native position moves 2.892015795849702371 quote tokens but leaves primary mandate allowance at 10,000 rather than 7,500.

Root cause: `_recordLeg` only upserts `generationLegs`, while the launch active position is tracked separately in `generationPositionId`. The `fromPrimary` expression selects the launch active position whenever the current denomination equals the launch quote. The duplicate is therefore real treasury value but counted as secondary rebalancing. Impact demonstrated is governance progress misaccounting; no theft or protocol-wide insolvency is claimed.

The local patch consolidates both the existing destination leg and the launch active position when rotating back to the launch quote, stores the replacement in `generationPositionId`, and removes a duplicate leg reference if present. It leaves the reserve position and generation pool key unchanged. The registry's `setRedemptionExt` is one-shot: an already-wired deployment cannot simply adopt this new facet. This is a fresh-source remediation, not an upgrade path or attestation that existing duplicate positions have been repaired. Any deployed recovery requires a separately reviewed, authorized migration plan.

Four post-patch local lifecycle tests now pass: round-trip consolidation, subsequent primary allowance consumption, two round trips preserving a nonzero reserve/key/floor followed by OG redemption, and failed-swap rollback followed by retry. The facet runtime is 13,744 bytes, below EIP-170. Acceptance still requires final storage/selector checks, legacy-duplicate reconciliation, broader regressions and independent re-review.

## Remaining review matrices

### PERP-03 — partial owner-close minimum bypass

**VERIFIED before patch:** `PerpPartialCloseMinimumTest` reports one failed security assertion and one passing explicit-zero-minimum control. A short is opened against production V4/PerpEngine; the fixture LP removes liquidity until the remaining pool holds less than the token debt. `close(id, 1)` unexpectedly succeeds through `PartiallyClosed` and pays no quote to the trader. `close(id, 0)` also takes that path and reduces the debt, proving partial settlement was actually reached. This uses fixture hook/registry and LP control; it does not claim an outsider can withdraw protocol-owned LP.

The partial branch returns before the ordinary short `_ownerFloor` check. The narrow remedy calls `_ownerFloor(ownerSlippage, 0, minOut)` before rebooking: nonzero minimum atomically rejects this zero-output result; zero minimum still permits partial progress. Liquidations/death and normal-long/full-short behavior are unchanged. Independent source review confirmed the boundary. Post-patch focused run: **22 passed, 0 failed, 0 skipped** across six suites, including both new assertions, existing partial funding/backing checks, isolated rebook fuzzing and local cascade/exact-output controls. Some inherited XL1 cases execute in both derived suites; they are not distinct properties. Full-scope acceptance remains open.

Do not interpret this patch as redefining every minimum as final net payout: existing normal-long checks compare gross sale proceeds, and complete-short checks compare residual before funding. The separate question of unbanded owner-close spending against socialized backing remains an unconfirmed reachability/economics hypothesis; this regression does not establish a production drain.

### PERP-02 — repeated write-offs resurrect stale reward claims

2026-09-20 follow-up: `REVIEW_ENGINE_VAULT_INTEGRATION.md` records a passing
production-engine AND production-vault sequence with two actual
`syncGeneration` quote round trips, treasury write-off transfers, late sync,
and actual reward payouts. This supersedes the statement below that the engine
boundary has not been executed. Real registry/governance/V4 rotation and other
listed lifecycle acceptance remain open; those dependencies are still fixtures.

VERIFIED at the production-vault boundary with the existing model engine. Before the fix, `PerpVaultRepeatedWriteoffTest` reports two failed security assertions and one passing no-write-off control. Alice deposits 1,000 tokens; 5 ETH yield is credited and written off; another 1 ETH accrues; Bob deposits 9,000 tokens and triggers a late sync. The vault records 6 ETH pulled/written off although 1 ETH remains backed. After a second write-off and 10 ETH new yield, Alice claims 2 ETH instead of her rightful 1 ETH. That excess consumes Bob's backing. Principal is outside the demonstrated impact.

The ordinary staker needs no privileged vault call. Two engine write-offs and delayed synchronization are preconditions; governance/rotation controls constrain their occurrence. Production `PerpEngine.syncGeneration` zeros the pot but retains cumulative credits, matching the model boundary. Full production-engine/rotation integration has not yet been executed for this sequence. Severity is Medium for lifecycle-conditioned reward misallocation, not permissionless protocol-wide insolvency.

The minimal source patch sets `totalTokYieldPulled = pulled + lost`, excluding the still-backed pot. All four focused tests pass, including 256 fuzz cases spanning two-to-eight write-off cycles, varied reward sizes, both claim orders and view/write consistency. The independent boundary review is in `REVIEW_PERP_VAULT_WRITEOFF.md`; runtime is 11,284 bytes. Full production-engine/rotation integration remains an explicit gap.

CORE-01 follow-up: the nine-case preflight harness initially suffered process-global environment contamination; explicit per-test environment resets left eight passing controls and one real failure: a positive stable-feed answer normalizing to zero was accepted. The remediation now explicitly rejects zero normalized prices. Post-patch: 9/9 edge cases and 3/3 run-entry rejection tests pass. This is acceptance hardening of CORE-01, not a second deployment finding.

### IDX-01 — rotation-market discovery and selection

Actual registered indexer handlers failed the pre-patch regression for rotation `LegOpened`. The fix derives authenticated destination pool identity from persistent generation state and event quote, avoiding PositionManager NFTs that may already be burned at the event block's end. Transient identity/decimal RPC failures now reject for retry, rather than silently losing the event. The non-reorg-aware negative cache was removed. API consumers select the registry's current denomination explicitly while retaining the launch pool for lifecycle identity. Independent root `npm test` execution passed 19 Node + 2 API + 7 indexer tests, including same-generation native-to-token-to-native market selection. Tests mock framework/RPC/database boundaries; no full service/reorg rehearsal is claimed. See `REVIEW_INDEXER_LIFECYCLE.md` and the actual API diff; its earlier downstream warning predates the consumer fix.

### NFT-01 — balance is not an authorization signal for legacy burns

Pre-patch `UnifiedVaultDonationTest`: two security assertions fail and the explicit legacy-floor control passes. Production collection/vault/ledger are used with fixture hook/registry roles. In unified mode (`hook.vault() == 0`), donating 2 wei to a two-NFT vault lets a holder burn an NFT for 1 wei; forced balance also enables the path. `burnFromVault` does not update the collection ledger. A third party cannot burn another holder's NFT directly: the holder must call the deprecated redemption endpoint. The ledger credit in this fixture is accounting-only, not a funded reserve-loss demonstration. A mode-based guard and legacy compatibility review are pending; no deployed remediation is claimed.

The local remedy permits ETH redemption only when the collection's minter returns this exact vault as its active legacy floor. A zero/different address, EOA, revert, empty response or malformed address remains inactive. `floorPerNFT` reports zero when disabled/closed. A typed try/catch first failed the empty-response test because caller-side return decoding is not caught; raw length/word validation corrects that case. Post-patch: **8/8 new regressions plus 6/6 existing legacy payout/donation-accounting controls pass**. Existing fixtures now explicitly declare legacy hook routing; none of their assertions was removed. Vault runtime 2,402 bytes; factory 20,427; no storage/ABI constructor change. Actual fresh/continuation deployment paths were source-reviewed, not separately rehearsed in these tests. Deployment and final lifecycle acceptance remain pending.

### UI-03 — quote-volume labels and phase ratio mix units (left unfixed)

**DERIVED:** `indexer/src/index.ts:377` converts swap amount to whole quote units; `/cauldron` sums only the selected market and compares that with `deathThresholdEth` (`indexer/src/api/index.ts:1210-1234`). With a hook oracle configured, the on-chain death threshold is compared against USD-normalized linked-pool volume (`CauldronHook.sol:884-918,1794-1803`), not that selected-market quote amount. `useCauldronMachine.ts:240-242` repeats the ratio and `TheCauldron.tsx:824,878,991,1016` labels it with ETH symbols. The authoritative `dead` decision still reads `hook.isDead(launchPool)`; no on-chain liquidation/death or fund-routing defect is established. Low display/health-indicator correctness; left unfixed as requested. A later UI fix should expose explicit units and use the same normalized linked-pool measure for lifecycle health, not merely change a currency label.

### GAS-01 — bounded loaded-book transaction cost (left unfixed)

**VERIFIED:** `LocalLiquidationGasTest` preserves the existing gas-ladder test and fails `3,000,000 <= 4 * 400,000`. Its actual book holds four positions. Caps below 3M revert; tested 3M/5M/8M/15M caps succeed and clear all four, with no success-to-failure reversal as gas increases. The app's swap and open paths specify 8M gas (`useCauldronSwap.ts:70`, `usePerpEngine.ts:67`), above this tested threshold; fixed lower-cap third-party routes can fail. No permanent protocol halt, bypass or asset loss was established by this result. Classified Low integration/cost limitation, consistent with the already documented preemption safety tradeoff. Left unfixed, and the failed assertion remains visible. Larger-book gas and kill-cap correctness require separate tests; this classification does not pre-judge those.

UI remediation uses remaining allowance rather than destination address for idleness and derives the venue pair from the selected source-leg index. Six helper regressions pass; no browser interaction test is claimed. Combined `npm test` reports 19 Node tests plus two API tests passing; frontend type-check passes. Broader build/parity acceptance remains pending.

API-01 was reproduced without network or real credentials: the installed viem client/error class includes a synthetic URL path credential inside the first 160 characters, and the actual metadata handler returned it publicly. The regression failed before patch while a sealed-token control passed. The patch replaces provider diagnostics with the fixed public category `chain read failed`; no production secret or deployed leak is claimed. Root independently source-checked UI-01/UI-02 against the governor and registry; bounded frontend remediation/tests are in progress.

Perp/rotation review is not complete. Open matrices include:

- long/short solvency and conservation across normal close, partial close, liquidation, death close, and generation sync;
- funding caps/signs/order and OI bookkeeping after partial fills;
- vault queue epoch/write-down and donation/seniority behavior;
- stale/zero/reverting oracle paths and decimal conversions;
- partial, repeated, expired, and reversed quote rotations;
- destination pool identity/squatting and curated-route constraints;
- failed venue/position recovery, dust legs, and proceeds denomination;
- old/new pair custody conservation and open-perp interlocks; and
- NativeQuoteZap multi-tick `owed > amountIn` liveness.
