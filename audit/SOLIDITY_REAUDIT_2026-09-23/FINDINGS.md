# Fresh findings ledger — audit incomplete

Only findings established in this pass are listed. Absence from this ledger is
not evidence of safety. Full-scope review and final validation remain underway.

## FS-badge-floor-01 — liquidation badges consume art-only floor backing

- Severity: **High**. Status: patched; targeted verification passes; full-scope validation pending.
- Location: PoolOps.recycleCollection/buyCollection; analogous missing admission
  guard in CauldronVault.redeem for explicitly enabled legacy mode.
- Cause: ownership admits badge IDs although totalMinted and the floor denominator
  count only art. One badge consumes one art claim and increments shared retirement.
- VERIFIED: `badge-floor-impact` on real local pool/position managers, registry,
  hook, collection and ledger pays 3154856711094924582688880 raw token units from
  3154856711094924582688881 backing, leaving ledger entitlement zero. One art NFT
  and one badge exist. The real engine is wired through hook.setPerpEngine.
- Fixture limitation: authorized hook/engine roles are impersonated to mint the
  initial NFTs, not to redeem. The later earned-badge regression below removes
  badge-minter impersonation; acquiring art through a funded draw remains open.
  Production claimLiquidatorBadges mints the same badge type for earned credits.
- Candidate remedy: reject IDs above totalMinted before ledger, payment or custody
  mutation on recycle/buyback and legacy vault redemption. Existing ownership and
  OG-offset checks remain. Fresh compiler checks POOLOPS_SURFACE_CHECK.json and
  VAULT_SURFACE_CHECK.json pass: current source hashes, unchanged ABI/selectors
  and storage, same compiler, zero unresolved references. Runtime/init sizes: PoolOps 24,465/24,497 bytes (111 runtime bytes
  headroom); CauldronVault 2,495/2,775 bytes. See BADGE_BYTECODE_SIZES.json.
- `badge-floor-fix` finished: 21 passed, zero failed/skipped. Additional
  legacy-vault rejection/state-preservation/both-art-payout test passes in
  `badge-legacy-and-earned-yield` (whose separate perp property fails).
  Same-reviewer verification. Earned-badge integration now passes separately
  in `earned-badge-floor-wired`: actual healthy short, ordinary45ETH buy closes
  it and awards exactly one badge, badge recycle reverts `not art`, custody,
  holder token balance and funded ledger backing remain unchanged. No public
  poke, including setup. Local real managers/hook/engine; mock discount NFT,
  explicit PLV token fixture funding and ambient manager native inventory.
  Art is still issued through an impersonated authorized hook; funded art-draw
  acquisition and full-scope verification remain open. Initial runs retained:
  `earned-badge-floor` had no credited backing (same-block buyback pacing);
  `earned-badge-floor-nextblock` and `earned-badge-floor-trace` stopped at the
  missing NFT-discount dependency. None counts as a passing property.
- Expanded integration `earned-art-and-badge-native` passes: actual paid
  untagged swap auto-commits two crystals to tx.origin, resolver delivers art
  through configured pity, actual liquidation earns badge, and badge recycle
  rejects with backing/custody/token conservation. No art/badge minter-role
  impersonation and no public poke. Owner-configured zero random odds, pity1,
  flat0.007ETH credit price and supplied blockhash make the draw deterministic;
  this is not randomness-quality testing. Earlier fixture limitations above
  apply to their historical runs. Failed `earned-art-and-badge-floor` used the
  token recipient instead of tx.origin for commit attribution and is retained.
  Full-scope validation remains pending; this supersedes the art-acquisition gap.
- First attempt `badge-floor-local` stopped at missing engine fixture wiring;
  `badge-floor-wired` subsequently reached the unexpected accepted redemption.

## FS-surtax-01 — malformed policy return blocks fee-bearing swaps

- Severity: **Medium**. Status: patched; selected regressions pass; full-scope validation pending.
- Location: SurtaxLib.surtaxBps typed return handling. Successful empty response
  escapes fallback during ABI decode and reverts CauldronHook's fee calculation.
- Preconditions: owner/registry-configured faulty policy. No outsider policy
  control or theft demonstrated; replace/unset recovers availability.
- Evidence: direct library failure in fee-policy-treasury-acceptance and actual
  funded local-manager swap failure in surtax-hook-boundaries-corrected;
  ordinary revert controls pass in both.
- Candidate: bounded one-word STATICCALL and minimum-length validation, preserving
  hard cap and normal fallback. SURTAX_SURFACE_CHECK.json confirms unchanged
  ABI/storage/selectors. `surtax-policy-fix` finished successfully after 642.45s:
  seven tests passed, including 256 default-policy fuzz cases and both funded
  swap fallback checks. Compiled SurtaxLib runtime/init sizes changed from
  723/753 to 687/717 bytes; both remain below deployment limits.

## FS-treasury-L01 — tied proposals do not follow documented lower-id rule

- Severity: **Low**, left unfixed as requested. Winner selection retains the
  proposal that reached tied support first, not necessarily the earlier id.
- Evidence: fee-policy-treasury-acceptance; later proposal voted first, equal
  100-vote support and satisfied quorum on both, winner=2 instead of documented 1.
- Impact: equal-support outcome depends on vote ordering. No lower-weight
  proposal beating a greater-weight executable proposal demonstrated here.
- Recommendation: define one tie ordering and apply to hint/bench consistently;
  reconcile interface documentation. Fixture uses mock historical votes.

## FS-treasury-L02 — stale cancellation id deactivates current envelope

- Severity: **Low**, left unfixed as requested. TreasuryGovernor.cancel checks
  whether the named proposal was executed, not whether it installed the current
  envelope. Cancelling an old consumed proposal disables a newer active envelope.
- Evidence: fee-policy-treasury-acceptance; new allowance falls from 3000 to zero
  after guardian cancels oldId. Only the authorized guardian can perform this.
- Impact: operational targeting mistake and misleading cancellation attribution;
  no privilege escalation because guardian can already cancel current proposal.
- Recommendation: bind active envelope to its proposal id and target only that
  id when clearing activity. No production edits made for this Low finding.

## FS-feerouter-01 — invalid router responses bypass swap fallback

- Severity: **Medium**. Status: patched; eight targeted tests and compiler
  surface checks pass; full-scope validation pending.
- Location: CauldronHook custom fee split (`fr.route`). Empty return decoding
  and checked overflow in `g + f + r` escape typed try/catch and revert the swap.
- Preconditions: owner-selected faulty router. No outsider configuration control
  or theft demonstrated. Fee-bearing trading is unavailable until configuration
  is repaired; intended built-in fallback fails for these dependency responses.
- Evidence: fee-router-boundaries logs; actual funded local-manager swaps,
  two failed properties and one passing ordinary-revert control.
- Candidate: fixed 96-byte STATICCALL output, minimum response size, short-circuit
  subtraction bounds before accepting sums. Existing custom split semantics and
  fallback retained. Runtime size, additional valid/invalid cases and compiler
  surface checks pending; no universal gas-exhaustion guarantee.

Later validation: fee-router-fix 3/3 passes; fee-policy-treasury-acceptance
fee-router subset 5/5 exact payout cases passes. Runtime 24,401 bytes (+27),
175 bytes EIP-170 headroom; HOOK_SURFACE_CHECK.json unchanged ABI/storage/selectors.

## FS-ledger-01 — pre-death credit survives a permanent zero-claimant freeze

- Severity: **Medium**. Status: fixed with targeted validation; full scope pending.
- Location: CollectionLedger.crystallize. Existing credit accepted while live
  remained booked when freezing supply left no outstanding shares. Zero floor
  blocks public treasury resale, leaving reserve allocation unclaimable.
- Evidence: ledger-death-credit fails with 500 token liability; production
  source flushes buyback credit before freeze. ledger-release-conservation:
  27 passes. ledger-registry-reference-mature: funded actual hook/registry/V4
  empty-collection relaunch passes, nonzero pending buyback asserted beforehand.
- Fix: release existing dead-end entitlement, debit totalEntitled equally, emit
  EntitlementReleased. Live accrual and still-claimable pots retained. Exact
  conservation model includes released liabilities; no weakened inequality.
- Compatibility: unchanged storage/function selectors, one explicit new event,
  runtime 2,092 bytes (+120). See LEDGER_SURFACE_CHECK.json and LEDGER.md.
- Limits: not theft; all-retired nonempty full-registry scenario still pending.
  Candidate does not repair already-deployed frozen state.

## FS-dividend-02 — malformed token responses block unrelated basket payouts

- Severity: **Medium**. Confidence: VERIFIED dependency-failure mechanism.
  Status: **Fixed; targeted tests and compiler-surface checks verified; full
  validation pending**.
- Location: MiFrensDividend._tryPush, original
  `ok = ok && (ret.length == 0 || abi.decode(ret, (bool)))`.
- Preconditions: trusted funder/treasury admits a token that later returns
  malformed transfer data. No unprivileged basket registration demonstrated.
- Impact: claimTokens reverts for the entire basket, including healthy assets;
  native claims remain independent. No list removal exists; recovery depends
  on token behavior or users settling via other valid lifecycle paths.
- Reproduction: R23_DividendMalformedPayout.t.sol; authorized registration while
  healthy, then invalid bool before token movement; expected healthy payout and
  recoverable failed liability. dividend-malformed-payout exits 1 with revert.
- Counterargument: standard immutable honest tokens do not emit malformed ABI;
  this finding concerns failure isolation of admitted configurable dependencies,
  not an assertion that presently configured assets are malicious.
- Candidate fix: self-call-only pushTokenIsolated checks bounded return data and
  reverts on failed/invalid result, rolling back token-side effects. _tryPush
  catches isolated failure and banks the claim through existing caller logic.
  One external self-only selector added; no storage additions intended.
- Verification: dividend-payout-isolation 22 passes (includes six inherited
  duplicate cases); dividend-payout-atomicity two passes, proving direct caller
  rejection and rollback of transfer-then-false before banking/retry. Fresh
  compiler comparison verifies unchanged storage and all original ABI entries,
  with exactly pushTokenIsolated(address,address,uint256), selector e184e3bb,
  added. Runtime/init 8,194/8,899 bytes; runtime headroom 16,382 bytes.
- Pending: complete consumer ABI joins and full validation.
  Gas-burning callbacks and cross-function interactions need further review;
  this patch is not a universal hostile-token guarantee.

## FS-dividend-01 — repeated receipts credit the same native rounding residual

- Severity: **Medium**. Confidence: VERIFIED. Status: **Fixed; targeted/fuzz and
  compiler-surface checks verified; full validation pending**.
  Location: MiFrensDividend.sol receive(), original expression
  `residual = amt - (inc * activeShares) / ACC`.
- Property: aggregate native entitlement must not exceed custody. Scaled
  fractional credits were issued while their enclosing whole wei remained in
  residual, available for repeated crediting, even on zero-value receipts.
- Reachability: production genesis/dividend fixture, three legitimately minted
  and enchanted tokens, one wei funded, six permissionless zero-value receipts.
  No privileged configuration, forged ownership or forced dividend storage.
- Evidence: R23_DividendResidual.t.sol; logs/dividend-residual-solvency.* exits 1
  with pending sum 6 > balance 1. Earlier log dividend-residual-boundary proves
  accumulator growth with unchanged custody. Test transaction gas ~1,006,658
  includes mint/enchantment setup, not the isolated repeated-call cost.
- Impact: unbacked native claims, potentially reverting claims or competing for
  later deposits. Repeatable dust-scale error; no material profitable drain
  established. Ordinary indivisible deposits can also exercise the mechanism.
- Counterargument: two active shares with a divisible deposit do not reproduce
  it, explaining why the existing conservation test passes. Gas cost greatly
  exceeds dust created; severity is bounded accounting/liveness, not Critical.
- Patch: round aggregate credited scaled value upward to whole wei before
  retaining residual. Thus residual never includes a fraction already credited.
  No external interface/storage changes intended. At most activeShares-1 units
  of 1/ACC wei can remain unallocated per deposit from division rounding;
  no duplicate whole-wei credit. Individual claim rounding is unchanged.
- Verification: dividend-residual-fix exit 0, 13 passes (three inherited
  duplicates), and dividend-conservation-sequence exit 0, 256 fuzz cases of
  24 deposits with actual mint/enchant/transfer/claim paths. ABI, selectors,
  storage unchanged; DIVIDEND_SURFACE_CHECK.json matches candidate source hash.
  Runtime 8,078 bytes (baseline 8,050); init 8,783 (baseline 8,755), +28 bytes.
- Pending: broader sequences and full validation. Existing deployed accounting
  is not repaired by changing source; no live-state remediation performed.

## FS-vesting-01 — malformed optional policy blocks new migrations

- Severity: **Medium**, bounded availability. Confidence: VERIFIED for the
  isolated escrow mechanism. Status: **Fixed; focused regressions and compiler
  surface verified; post-fix invariants and full validation pending**.
- Location: `cauldron/MigrationVesting.sol:310`, `_isInstant`; original expression
  `try stakerOracle.isInstant(who) returns (bool ok) { return ok; }`.
- Property: an unavailable instant-tier policy should fall back to ordinary
  vesting, not prevent funding a grant. Successful malformed return data raises
  a caller-side ABI decode error outside the catch; a code-less policy also fails.
- Preconditions: owner configures an invalid address/replacement policy or a
  configured policy begins returning malformed data. Standard deployed
  PerpStakerOracle is not shown to produce malformed bools. No permissionless
  policy mutation or attack on a third-party oracle is established.
- Impact: startVest and nonempty eligible vestBatch revert until owner repairs
  configuration or dependency recovers. Transaction rollback prevents partial
  burns or grant writes. Existing grant claims do not call the policy. No fund
  loss or permanent lock established; duration depends on operator recovery.
- Reproduction: `test/attacks/R23_VestingOracleBoundary.t.sol`; command and exits
  in `logs/vesting-oracle-boundaries.*`: three failures, ordinary-revert control
  passes. Mock registry isolates escrow behavior; production registry integration
  remains a gap. No capital extraction; failed callers pay transaction gas.
- Counterargument: owner can unset the policy. This limits severity and duration
  but does not make malformed failures follow the intended conservative path.
- Remediation: bounded one-word static call, length validation, accept only the
  canonical true word. Preserve valid false/true and zero-address behavior.
- Verification: `logs/vesting-policy-fix.*` exit 0, 29 passing tests, no failures
  or skips (includes nine inherited duplicate unit cases). All four new boundary
  tests pass. `remediation/VESTING_SURFACE_CHECK.json` verifies current source,
  unchanged ABI/selectors/storage and zero unresolved compiler edges. Runtime
  4,740 bytes versus 4,757 baseline; init 5,187 versus 5,204. EIP-170 headroom
  19,836 bytes. Post-fix invariants and full applicable validation pending.
  Same reviewer; no independent-review claim.

## FS-oracle-01 — malformed price responses suppress legitimate trade volume

- Severity: **Medium**. Confidence: VERIFIED. Status: **Fixed; targeted and
  neighboring regressions verified; full-scope final validation pending**.
- Location: baseline cauldron/QuoteOracle.sol:202 (usdPerRawUnit), :334
  (cachedUsdPerRawUnit), :350 (_sequencerOk); CauldronHook.sol:790/982/1867.
- Nodes: baseline 0.8.30:43365, 43474, 43558; downstream conversion, volume
  recording and death classification. Candidate adds two private read helpers.
- Property: an unusable configured feed must not bypass the retained-price
  fallback for volume while otherwise equivalent feed outages use that fallback.
- Preconditions: configured feed becomes malformed/codeless or returns an
  unrepresentable value. Feed choice remains owner-only. Death impact requires
  a nonzero threshold and insufficient other recorded generation volume.
- Reproduction: deploy local production managers/hook/registry; configure a
  synthetic healthy feed; execute a funded trade and prove cache/volume; make
  the dependency return empty successful data; advance 25 hours; execute another
  funded trade. It succeeds with zero recorded volume. Control with an ordinary
  feed revert records volume and remains alive. No target storage forced.
- Root cause: successful-call ABI decoding errors and arithmetic panics occur
  outside high-level try/catch. The self-called fresh getter then reverts the
  entire cache refresh instead of returning the existing usable factor.
- Impact: missing volume/crystal-accounting contributions during the incident;
  rolling volume can fall below death threshold despite ongoing trading. The
  zero-volume result was executed pre-fix; false death follows from the threshold
  comparison. No live-chain incident or completed harmful relaunch is claimed.
- Cost/authority: not a permissionless ability to corrupt a trusted feed. The
  incident requires dependency failure or privileged misconfiguration; ordinary
  traders still pay the normal trade costs. It can persist until repair.
- Refutation: ordinary revert uses the same setup successfully; nonzero cache
  is proven before the incident. Zero death threshold or sibling volume removes
  false-death impact but not the recorded-volume failure. Strict-price rotator
  consumers fail closed; no treasury drain was demonstrated.
- Fix: root QuoteOracle uses bounded fixed-prefix STATICCALL reads, validates
  ABI field widths/lengths, and returns zero for unrepresentable normalization.
  Sequencer reads share the safe helper. Cached-price/timestamp policy unchanged.
- Regressions: R23_OracleFailureBoundaries (five tests), R23_OracleHookLifecycle
  (two tests including control). Baseline six failing properties retained in
  snapshot; all seven pass against candidate. See VERIFICATION.md.
- Compatibility: ABI, selectors and storage unchanged. Runtime grows 149 bytes,
  from 3,821 to 3,970 under both recorded compiler versions. No deployment.
- Residual: retained cache is intentionally stale during outages; spending
  consumers must continue using strict live prices. Gas-burning dependencies
  remain a liveness assumption. Unsupported extreme inputs are unpriceable,
  not invented prices. Same reviewer performed reproduction and verification.

## Unconfirmed leads

- R23-L1: cascade completion/projection ordering. Current 64-case mixed-book
  probe passes; this does not yet confirm or refute all reachable cases.
- Remaining oracle gaps and test-evidence limitations: QUOTE_ORACLE_REVIEW.md.

### Earned token-yield replacement guard — reproduced mechanism, impact pending

`badge-legacy-and-earned-yield` executes
`R23VaultRewardStake.test_earnedYieldMustKeepReplacementGuardActive` and fails
its final guard assertion. Deposit, mock-engine yield accrual, and full principal
withdrawal leave positive `tokRewardOwed` with zero token shares/queue units,
while `hasStakers()` returns false. No target storage was force-written.
Production `PerpEngine.setVault` relies on this boolean and
`withdrawTokYieldTo` requires the currently appointed vault. Thus replacement
can disable the old claim path by source derivation; actual funded-engine
replacement, recovery, and value-loss behavior remain untested. Owner action is
required; no permissionless replacement shown. No confirmed severity or patch
yet. Do not confuse this earned balance with yield accrued at zero shares.

## FS-perpvault-01 — vault replacement disables earned reward claims

- Severity: **Medium**. Confidence: VERIFIED for owner-triggered claim outage.
  Status: Patched with targeted verification; full-scope validation pending.
- Location: PerpVault.hasStakers (263), withdrawToken (788), claimTokYield (776);
  PerpEngine.setVault (3000), onlyVault (603), withdrawTokYieldTo (2862).
- Property: replacement must preserve access to earned, backed user liabilities.
- Sequence: deposit token principal; authorized hook credits short-side fees;
  withdraw all principal, leaving earned reward debt; owner replaces vault;
  old vault cannot exercise its engine payment authority.
- Evidence: R23_VaultReplacementYield.test_replacementDisablesEarnedClaimAndRestoringVaultRecoversIt;
  logs/perp-replacement-earned-yield.json and .log, one pass/zero failures/skips.
  Production engine and vault; stub registry/pool, impersonated authorized hook
  for actual funded credit. No target storage writes.
- Impact: bounded reward claim outage requiring privileged replacement. No
  outsider ability to replace vault or demonstrated direct theft.
- Refutation: restoring the old vault while replacement is empty recovers exact
  payout; therefore permanent loss is NOT established. Funded replacement and
  broader recovery constraints remain to be tested.
- Root cause: guard counts only principal shares/queue units, while withdrawToken
  retains earned rewards in a separately claimable ledger.
- Recommendation: include backed attributed outstanding rewards in replacement
  eligibility, preserving replacement when only unattributed yield/dust remains.
  Account for lazy write-offs, quote scaling, claims and multiple users.
- Fix: PerpVault maintains a current-epoch aggregate of settled reward units.
  hasStakers includes those liabilities unless a lazy write-off forfeits them.
  Claim subtracts exact owed units; write-off resets the aggregate. Unattributed
  engine yield and rounding residue never enter it.
- Zero-rounded positive owned claims may be cleared by their owner with a zero
  payout; genuinely empty claims still revert ZeroAmount. This is an intentional
  behavior change, tested against a modeled quote conversion.
- Regression: perp-earned-yield-fix exit 0, 32 executions/25 distinct tests,
  zero failures/skips; scale batch adds two vault tests (both pass). Includes
  production-engine replacement blocking/release, multiple departed claimants,
  orphan residue, write-offs, payment rejection rollback and 256-run fuzz suites.
- Artifact: source 70318531e5b0ee890a884587a48fa8e46fbee7c652ffa59cce49fc52f3b5176b;
  ABI/selectors unchanged; one appended private uint256 slot, no previous slots
  changed. Runtime/init 12,287/12,681 -> 12,608/13,009 bytes. Fresh deployment
  only; this does not repair existing deployed vaults.
- Residual: same-reviewer verification, full stateful accounting/production
  conversion integration and consumer/deployment parity remain pending. The
  current StakePanel hides claim when displayed reward is zero, so dust-clearing
  consumer flow still needs resolution before final sign-off.

## FS-perpmark-01 — invalid configured mark disables beforeSwap sweep

- Severity: **Medium**. Confidence: VERIFIED. Status: patched with targeted verification; full-scope validation pending.
- Location: PerpEngine._currentTick, _pokeFunding, _doSweep;
  CauldronHook._beforeSwap/_liqSweep; PerpSwapLib.sqrtPriceAtTick.
- Cause: exactly-one-word mark answers were narrowed to int24 without a valid
  TickMath-range check. A successful answer 887273 enters the ring; subsequent
  funding valuation throws InvalidTick rather than using primary-pool fallback.
- Preconditions: owner wires faulty mark dependency. Shipped PerpMarkSource on
  a valid V4 manager does not naturally emit such ticks; no unprivileged ability
  to replace/configure source is demonstrated.
- VERIFIED intended path: R23MarkBeforeSwap opens one funded healthy short with
  real production hook/engine and local V4 managers, configures faulty source,
  executes a small buy, advances time, and attempts another small buy. Public
  poke is never called in this tested sequence. The second buy reverts through
  the pre-trade sweep; identical reverting-source control delivers tokens and
  retains the healthy position. Logs: perp-mark-before-swap-recipient.
- Fixture limitation: local boot explicitly supplies ambient manager native
  inventory. This is not deployed/fork parity or an empty-manager test.
- Earlier tests: malformed public mark fails; ordinary revert control passes.
  XL1 fixture fails during poke warm-up before close; do not claim it executed
  close. Initial XL1 run had a compile error; initial hook run had an incorrect
  recipient balance assertion. Corrected runs retain full evidence history.
- Impact: quote/swap availability outage through normal beforeSwap automation.
  Hook fails closed rather than allowing an unverified unsafe trade. No direct
  theft/insolvency demonstrated. Owner reconfiguration and TWAP recovery remain
  to be characterized; no unconditional permanent-loss claim.
- Remedy: bound full signed return word to [-887272, 887272] before narrowing;
  invalid values take existing primary fallback. No public-poke dependency,
  keeper requirement, hook bypass, or normal mark-source policy change.
- Verification: perp-mark-range-fix exit 0: four executed tests pass, zero
  failures/skips (do not count unexecuted names in command regex).
  perp-mark-acceptance-and-reward-sequence adds five passing tick cases and a
  separate passing vault sequence fuzz test. perp-mark-neighbor-regressions adds
  15 passing local tests, no failures/skips, including pre-sweep book checks.
- Fresh compiler surface matches ABI/selectors/storage. Versioned 0.8.26 and
  0.8.30 artifacts both match source metadata hash and are 24,207 runtime bytes
  (369 headroom), 26,229 init bytes. Unversioned PerpEngine.json is stale and
  explicitly excluded; see PERPENGINE_BYTECODE_SIZES.json.
- Residual: same-reviewer verification; no deployed poisoned-ring recovery or
  complete deployment parity established. Full-scope validation remains open.

## FS-artbuffer-01 — dense valid owner-uploaded art breaks rendering

- Severity: Low. Status: reproduced, unpatched.
- FrenRenderer uses a fixed 200,000-byte buffer with unchecked mcopy appends.
  TraitStorage accepts valid dense 120x120 two-color art that expands beyond it.
- `renderer-dense-upload` fails with array-out-of-bounds panic on the renderer
  call. R23_RenderBuffer.t.sol uploads a 7,210-byte body via ordinary owner API;
  no target storage writes or malformed pixel/header data. Expected successful
  rendering property remains a failing regression, not counted as passing.
- Impact: metadata availability for such configured art. Requires privileged
  upload; shipped checked binaries remain within the conservative 118,476-byte
  bound. No fund loss or outsider upload demonstrated. The panic is observed;
  exact overwritten memory location has not been independently instrumented.
- Suggested remedy: checked capacity/growth on every buffer append, or enforce
  a verified render-output bound before immutable art publication. Gas for
  worst-case dense art still needs a separate operational limit.

## FS-deployfactory-01 — rerun schedules and executes different factory calldata

Severity: Low. Status: source-confirmed, unpatched; script execution pending.
FixFactoryWiring.run deploys a fresh factory before both branches. A later
EXECUTE=true run encodes the newly created address rather than the scheduled
factory address. TimelockController hashes payload into operation identity and
requires that identity ready. Documented workflow therefore does not complete.
Existing scheduled operation can still be executed with its original calldata;
no irreversible factory loss or protocol freeze demonstrated. Persist and reuse
the original factory/operation data for execution. Do not broadcast to verify.

## FS-deployvesting-01 — enforcement script ignores emergency gate delay

Severity: Low. Status: source-confirmed, unpatched; script execution pending.
DeployMigrationVesting tells operators delay is irrelevant and attempts immediate
setClaimGate(nonzero) when broadcaster is emergencyAdmin. Registry actually calls
_consumeTimelock for nonzero gates. Without a matured emergency authorization this
reverts; deployment/enforcement may be incomplete. Existing delay is a protection,
not a registry vulnerability. Script must preflight and accurately describe the
arming/delay/veto workflow and distinguish deployed escrow from enforced gate.

FS-deployfactory-01 supplemental evidence: factory-operation-identity passes
one test with actual TimelockController and two actual CauldronFactory deployments.
Fresh address payload is not ready and execute reverts; original scheduled
payload executes successfully. Registry target is a restricted setter fixture;
the script itself is not executed. This confirms mechanism and recovery, not
full broadcaster/deployment parity. Finding remains unpatched Low.

## FS-venueseed-01 — repeated funding strands earlier venue position

Severity: Medium. Confirmed by funded local reproduction; candidate patch under
verification. VenueSeeder.seed and seedBand overwrite a single positionId while
recover can only burn that ID. Actual local V4 PoolManager/PositionManager and
Permit2 test creates two positions, recovers twice, and confirms earlier NFT
still owned by helper with positive liquidity. Helper has no NFT rescue route.
Log: venue-repeated-seed-recovery (one passing vulnerability characterization).
Owner must repeat funding; no outsider trigger. Deployer's testnet venue funds
are affected, not protocol LP. Local managers loaded from existing artifacts;
full fresh-artifact parity remains open.

Candidate adds positionId==0 admission guard to both seed paths. Existing funded
position must be recovered first; then normal reseeding is permitted. No ABI or
storage declarations changed. New source does not repair already deployed helpers
or recover previously orphaned IDs. Targeted postpatch lifecycle run pending.

FS-venueseed-01 targeted remediation now verified: venue-reseed-guard exit0,
one lifecycle test passes. Both repeated seed paths reject, stored first ID
preserved, recovery returns native funds, subsequent seed and recovery succeed.
Full band-seed success, independent/source-matched manager builds, ABI/storage
and deployment-size checks remain pending. No final sign-off.

FS-venueseed-01 reachability strengthened: DeployLaunchpad optional VENUE_BAND_BPS
path performs seed then seedBand on the same helper. Candidate updates this
caller to use two independently recoverable helpers; prior guard-only test
does not establish this caller compatibility. New integration batch running.

FS-venueseed-01 caller compatibility: local full-range plus separately funded
band helper each retain/recover their own NFT successfully. Mixed batch had
unrelated preflight failures; serial12-test preflight rerun passes. Complete
script broadcast simulation, ABI/storage/size parity remain final gates.

## FS-deployhook-01 — obsolete permission mask blocks minimal hook deployment

- Severity: Low; deterministic deployment availability/configuration issue,
  no user-fund loss demonstrated.
- Location: deploy/DeployCauldron.s.sol, run / _hookFlags.
- Cause: original mask omitted BEFORE_SWAP_FLAG and BEFORE_SWAP_RETURNS_DELTA_FLAG
  required by current CauldronHook. Mined address fails BaseHook validation.
- Reproduction: R23_DeployHookFlags.t.sol mines original mask and deploys actual
  hook, asserting exact HookAddressNotValid(predicted) revert.
- Fix: add both permissions via _hookFlags used by run. Regression consumes
  script helper and successfully CREATE2-deploys actual hook with correct owner,
  manager and predicted address. No production contract ABI/storage change.
- Evidence: deploy-hook-permission-offline, two pass, zero fail/skip, exit0.
  Initial deploy-hook-permission-flags crashed in Foundry network setup, exit-6;
  not a protocol failure or passing check. All retained.
- Limits: local constructor only, placeholder manager; full script deployment,
  canonical factory and summon still require verification. No transactions sent.

---

# Continuation 2026-09-23 (Claude Opus 5.5, after Codex credit exhaustion)

Same working tree, different model. Prior evidence was re-read from logs rather
than re-asserted. Reproduction and verification below are by one reviewer; no
reviewer-independence claim.

## FS-gacha-01 — failed art mint erases earned pity and inflates `opened`

- Severity: **Medium**. Confidence: VERIFIED (production path). Status: **Fixed;
  targeted and neighbouring regressions verified; final-suite result in FINAL_REPORT.md**.
- Location: cauldron/GachaLib.sol resolveTickets win branch (baseline :236-251):
  `missStreak[player] = 0; opened[player] += 1;` precede `try col.mint(player)`;
  the `catch` only emits TicketLost. The adjacent comment promises a failed mint
  is recorded "WITHOUT counting against the player's pity streak".
- Reachability: MiFrensGenesis.setTransferValidator (deployer, :644) installs an
  ERC-721C validator; Genesis._update (:887) validates mints too, with the hook
  as `_msgSender()`. Registry._continueMiFrens makes Genesis the hook collection
  for generation 2. Enabling royalty enforcement with a validator that does not
  whitelist the hook (or rejects a receiver class) is an ordinary operator
  action, not a malicious one. CauldronCollection's equivalent setter is
  registry-deployer-only with no forwarder, so brew collections are not reached.
- VERIFIED before fix: logs/genesis-paid-mint-failure.* (exit 1) —
  R23_GenesisMintFailure: real local V4 managers/hook/registry, Genesis
  ignition and relaunch to generation 2, paid swap credit, real commit/resolve,
  deployer-set rejecting validator. Pity falls 1 -> 0 on the undelivered forced
  win; `opened` increments. Library mechanism: R23_GachaFailedMint (8 -> 0).
- Impact: permanent loss of paid-for pity progress for every player whose
  forced win lands while a rejecting validator is set (fixing the validator does
  not restore it); `opened` (UI scoreboard) diverges from indexer `wins`, which
  counts TicketWon. The spent crystal itself is the documented failure-isolation
  cost and is unchanged. No outsider trigger; no theft.
- Fix: snapshot the streak before the effects-first writes; in `catch` restore
  the streak and undo the `opened` increment. The reverted call's writes —
  including any re-entrant frame's — are already rolled back, so the snapshot is
  the exact pre-roll state and GACHA1-g effects-before-interaction is preserved.
  No storage, ABI, selector or event change. Library bytecode changes, so the
  hook must be linked against the new GachaLib address on redeploy.
- Verification: logs/gacha-pity-fix.* exit 0 (704s incl. compile): 32 passed,
  0 failed, 17 skipped. Skips are the fork-only F02_L2Semantics, Y03 and Z05
  suites (FORK_RPC empty) and are NOT counted. Both pre-fix failing properties
  now pass: R23GenesisMintFailure (pity stays 1, opened unchanged, queue not
  wedged, no art minted) and R23GachaFailedMint (pity stays 8). GACHA1g
  re-entrant mint, GACHA1b rejecting-validator FIFO, GACHA1e outstanding
  conservation, R2E seed pinning, R3A/K4b regrind characterizations, R3C supply
  conservation, R3D aged queue, churn and earned-badge integration all pass.
  Candidate SHA256 1b6593e140b0cf28b74bd52c12f6458599278c90a55154f7185b80e0e00869a9.
- Counterargument: validator misconfiguration already makes all wins fail. True,
  but the documented contract of this branch is to isolate that failure to the
  crystal; erasing accrued, paid-for pity is additional permanent user loss.

## Dispositions of remaining worksheet leads (this continuation)

| ID | Lead | Disposition | Evidence |
|---|---|---|---|
| FS-registry-L01 | emergencyWithdrawLP pays the recovered currency0 amount as native ETH | **Low**, DERIVED, unfixed. For an ERC20-seeded generation the admin break-glass reverts (EthSend) unless the registry coincidentally holds that much native ETH, in which case it pays native from other buckets and leaves the ERC20 behind (emergencySweep recovers it). Emergency-admin-only; migrateToSuccessor remains an alternative. | CauldronRegistry.sol:475-484, _removeLiquidity :1606-1668 (currency0 measured) |
| FS-registry-L02 | OG share of relaunch-flushed buybacks added to genesisPending after the fold | **Low**, DERIVED, unfixed. Folded one generation late (next relaunch); new reserve is not sized for it meanwhile, but nothing claims against genesisPending, so no insolvency. Unclaimable if no further relaunch occurs. Contradicts the step-8 comment's "fold BEFORE sizing" intent. | CauldronRegistry.sol:1016-1018 fold, :1045 _flushLegacyAtRelaunch, :1548-1556 |
| FS-hook-L01 | Curve policy malformed return escapes nftPriceAt try/catch | **Low**, DERIVED, unfixed. Swaps unaffected (native gacha is an isolated self-call with ignored result, CauldronHook.sol:1102-1108); router commits and cost views revert until owner repairs policy; credit stays banked. Owner-configured dependency. | CauldronHook.sol:2453-2462, :2578-2600 |
| FS-venueband-L01 | VenueSeeder.seedBand tick width 10x documented band | **Low**, DERIVED by arithmetic, unfixed. `bandBps*995/100` = 9.95 ticks/bp; comment's own figure is 0.995 ticks/bp. 500 bps -> 4,975 ticks (~±64%) not ~488 (±5%). Optional testnet mock venue only (VENUE_BAND_BPS default 0); thinner depth than the documented slippage table. | deploy/DeployRotationStack.s.sol:358-360 |
| FS-router-L01 | Malformed owner-configured oracle reply escapes CauldronGachaRouter.playInCurveUnits fallback | **Low**, DERIVED, unfixed. Same typed-decode pattern as the fixed Mediums, but scoped to router plays: hook swaps, native in-swap gacha and direct commits are unaffected; owner can replace/unset the oracle. Q02 covers ordinary reverting oracles. | GACHA_ROUTER_REVIEW.md; CauldronGachaRouter.playInCurveUnits |
| FS-deployperp-I01 | Mark-source handoff keyed on env flag, not on "we deployed it" | **Informational**. Supplied source + flag attempts transfer of a caller-supplied source, contrary to the comment; forge simulation fails before any broadcast if broadcaster is not its owner. | deploy/DeployPerp.s.sol:205-206, :251-254 |
| FS-deployrender-I01 | BATCH=0 never advances upload loop | **Informational**. Simulation stalls before broadcast; operator input validation. | DEPLOY_PERP_ART_PROBE_REVIEW.md |
| FS-rotation-I01 | rotateSlice/rotateSliceFrom lack nonReentrant | **Informational**, DERIVED. All callbacks in the path are owner-curated (allowlisted quote tokens, exact-PoolId venues, rotator, engine, V4 managers); no outsider-controlled callback reaches the registry mid-rotation. Registry stub cannot grow (8 bytes headroom). Defense-in-depth only. | TREASURY_REVIEW.md rotation join; QuoteRotator.setVenue exact PoolId |
| R23-L2 | Seeder range bookkeeping eviction | **Not reproduced**; production launches do not arm streaming (SEED_BASE_WAD=1e18). Re-open if the base constant changes. | seeder-range-tracking-nonvacuous p1; PoolOps.sol:173,400-415 |
| Governor bench | >8 mandates can be evicted | **Informational (design)**; characterized, no permanent freeze. | governor-bench-recovery-snapshot p1, governor-settled-bench-flood p2 |
| Vault accountedDeposits | cumulative, not decremented | **Informational**; legacy vault redemption disabled by both registry creation paths (hook.setVault(0)). | VAULT_REVIEW.md |

## FS-relaunch-01 — any caller can complete a relaunch that permanently strands the perp book

- Severity: **High**. Confidence: VERIFIED. Status: **Fixed; targeted and
  neighbouring regressions verified; final-suite result in FINAL_REPORT.md**.
- Location: CauldronRegistry._perpHousekeep(false) (baseline :1190-1193):
  `uint256 g = gasleft(); if (g > RELAUNCH_TAIL_RESERVE) { hook.forceClosePerps{gas: g - RELAUNCH_TAIL_RESERVE}(); }`
- Property: a completed relaunch must never leave perp positions open. The
  hook enforces it (CauldronHook.forceClosePerps reverts `PerpsOpen` on any
  survivor, :2104) and the registry comment states the design: an insufficient
  budget must revert the rebirth so a later caller retries with more gas.
- Root cause: the reserve guard SKIPS the close instead of failing. The rest of
  relaunch (LP teardown, token deploy, seed, collection) fits under 8M gas, so a
  budget that reaches this point at <= 8M completes the rebirth without ever
  calling the hook.
- Preconditions: relaunch is permissionless once the generation is dead, past
  minLifetime and a proposal exists — every generation's normal end. Attacker
  needs no capital or role, only a chosen transaction gas limit.
- VERIFIED: R23_RelaunchGasSkip (real local V4 managers, production hook/
  registry/facet/engine, funded 0.5 ETH long + 0.5 ETH short, ordinary trade
  warm-up, no public poke). Scan 6.0M..26.0M in 500k steps with state reverted
  between attempts: 41 completed relaunches; the five at 6.0M-8.0M completed
  with both positions open. Afterwards syncGeneration, forceCloseAllDead and
  both traders' close revert, engine syncedGeneration stays 1, openCount stays
  2. Control at full gas drains the book and re-arms the engine.
  logs/registry-perp-leads.* (exit 1 — this property failing pre-fix).
- Impact: every position open at relaunch is locked permanently (trader
  collateral and the engine inventory backing it); the engine can never sync
  (`syncGeneration` requires openCount == 0), so perps stay down until the owner
  deploys and wires a replacement engine. Repeatable once per generation.
- Honest-caller reachability: the dapp's relaunch (src/hooks/useCauldronMachine.ts:313)
  sends `writeContractAsync` with no gas override, so the limit comes from
  eth_estimateGas, whose binary search converges on the LOWEST succeeding limit
  — inside the stranding band, because pre-fix success is non-monotonic in gas
  (success 6.0-8.0M, revert 8.0-8.5M, success >= 8.5M). The default UI path
  would strand the book without any attacker.
- Severity note: timing-bound (the relaunch transaction) and scoped to the perp
  book open at that moment, so High under this brief's scheme; it is
  permissionless and capital-free, and a reviewer could argue Critical.
- Fix: always make the gas-capped, non-`try` call:
  `hook.forceClosePerps{gas: gasleft() - RELAUNCH_TAIL_RESERVE}();` Checked
  subtraction reverts below the reserve; a budget too small for the close
  reverts through the call (the hook's own OOG or PerpsOpen). The rebirth
  therefore drains the book or does not happen, rolling back markConsumed so the
  proposal stays live. After the fix, success is monotonic in gas, so gas
  estimation returns a safe limit. Removes a branch (no bytecode growth).
- Residual: minimum relaunch gas rises to reach the reserve even with an empty
  book (well within block limits); deployed registries are not repaired.

## FS-successor-01 — V2 successor handoff permanently strands rotated treasury legs

- Severity: **Medium**. Confidence: VERIFIED. Status: **Fixed; targeted and
  neighbouring regressions verified; final-suite result in FINAL_REPORT.md**.
- Location: CauldronRegistry.migrateToSuccessor (:540-590) transfers only the
  current generation's active/reserve NFTs, seeder assets, current token and
  native balance; RedemptionExt.recoverLegs rejects the current generation
  (baseline :915) and emergencyWithdrawLP must burn the transferred active NFT.
- VERIFIED: R23_SuccessorLegHandoff (real local managers, registry/facet,
  funded native launch, voted ERC20 rotation leg). After the armed handoff the
  leg NFT stays owned by the old registry with 31108410940295381152350
  liquidity; recoverLegs(current) reverts CannotClaimCurrentGen (0xbffafcbc),
  emergencyWithdrawLP reverts. No other path moves or unwinds it.
  logs/registry-perp-leads.* (exit 1).
- Preconditions: emergency-admin (timelocked, guardian-vetoable) executes the
  documented V2 handoff while a rotation leg exists. No outsider trigger.
- Impact: the rotated slice of treasury liquidity (up to the governance
  rotation envelope) is permanently stranded behind the retired controller.
  Rated consistently with FS-venueseed-01 (owner action orphans an LP NFT with
  no rescue).
- Fix (facet only; registry has 8 bytes headroom): when `gen == currentGeneration`
  and the primary reserve (or active) NFT is owned by the recorded `successor`,
  the already-forwarded `recoverLegs(gen)` transfers every leg NFT to that
  successor and drops it from the list, emitting LegHandedOff. Ownership moves,
  liquidity stays in place (matching migrateToSuccessor's "ownership move — no
  liquidity withdrawal" promise); the destination is never caller-chosen, so it
  is safe to leave permissionless; nothing is unwound, so there is no price
  exposure. Past-generation retry and the live-generation protection are
  unchanged. One new facet event; no storage, selector or registry change.

### Verification of FS-relaunch-01 and FS-successor-01; R23-L1 disposition

logs/relaunch-successor-fix.* exit 0 (676.86s incl. compile): 16 suites, 46
passed, 0 failed, 0 skipped. Candidate SHA256: CauldronRegistry.sol 5831cab4bc5957e77e16453527a9c2ae07a057aab0be01f6de7f8f8b2773c96b;
RedemptionExt.sol 1dc4d83fa0d26552d9740f382d09b2ac47b60d9af6cd8e194baa0ebf4abf1d60.

- FS-relaunch-01: the same 6.0M..26.0M scan now yields 36 completed
  relaunches, the lowest at 8.5M, and **0** with open positions; 6.0M-8.0M caps
  revert instead of completing. Full-gas control drains the book and re-arms the
  engine. Neighbours pass: LocalM4ARelaunchTest (two consecutive relaunches),
  LocalM4BWhaleTest, R23LedgerRegistryLocal, R23VestingRegistryLocal,
  R23GenesisMintFailure (iteration-2 relaunch), D04/LIQ02/LIQ03 local lanes,
  RotationTotalityLocal open-book carry.
- FS-successor-01: pre-migration recoverLegs(current) still reverts
  CannotClaimCurrentGen; after migrateToSuccessor an arbitrary caller's
  recoverLegs moves the leg NFT to the successor with liquidity unchanged
  (31108410940295381152350), legCount becomes 0, a repeat call is a no-op.
  Rotation lifecycle/emergency recovery suites pass unchanged.
- R23-L1 (cascade exit condition) — **Informational, not reproduced**.
  R23CascadeMixedLeverage orders sturdy (lev 1-2) shorts before max-leverage
  shorts so a later kill moves spot after earlier survivors were checked.
  256 fuzz runs plus a 24-step ladder (24 fills, **21 with in-sweep kills**,
  0 refusals): no trade-condemned survivor, no insolvent survivor, no PLV loss.
  Together with cascade-ordering-64 (uniform book). The source still exits
  "clean" after a killing pass whose earlier survivors were not re-checked,
  contrary to its own comment ("the ONLY clean exit is a full pass that finds
  nothing condemned"); no harm was reproduced, so this remains a documentation/
  defense-in-depth note, unfixed.

## Owner-requested Low remediation (2026-09-23, after sign-off)

The owner asked to fix every documented Low that fits, plus the StakePanel
dust-claim gap, before the Sepolia r47 redeploy. All are now FIXED with a
regression in test/attacks/R23_LowFixes.t.sol unless noted:

| ID | Fix | Regression |
|---|---|---|
| FS-registry-L01 | emergencyWithdrawLP pays the recovered quote in the generation's own currency0 via PoolOps.sendAsset. The body moved into RedemptionExt behind a registry stub that still enforces onlyEmergency + the armed timelock on the registry's immutables (the in-place fix put the registry 73 bytes over EIP-170). | R23LowEmergencyERC20: real USD-quoted generation 2, admin paid USD, no native |
| FS-registry-L02 | Relaunch flushes the dying collection's buybacks BEFORE folding genesisPending, so the OG share is covered by this relaunch's reserve sizing. | R23LowOgFold: real Genesis continuation, genesisPending 0 after relaunch |
| FS-hook-L01 | nftPriceAt reads the curve policy as one bounded word; short/codeless/zero replies take the built-in curve. | R23LowHookCurve incl. funded buy still committing crystals |
| FS-router-L01 | _playInCurveUnits bounded oracle read; unusable, zero or unrepresentable factors pass the size through. | R23LowRouterOracle incl. a funded router play |
| FS-treasury-L01 | vote hint and winner scan break equal support to the lower id. | R23TreasuryTargeting tie test now passes |
| FS-treasury-L02 | execute records the installing id in the previously unused `activeProposal` slot; cancel deactivates only that envelope. | R23TreasuryTargeting stale-cancel test now passes |
| FS-artbuffer-01 | FrenRenderer buffer doubles capacity before any append would overflow. | R23RenderBuffer dense-art test now passes |
| FS-venueband-L01 | seedBand width bandBps*995/1000. | R23LowVenueBand (real PositionManager tick bounds) |
| FS-deployfactory-01 | EXECUTE run reuses FACTORY from the schedule run. | R23LowScripts factory test (real TimelockController) |
| FS-deployvesting-01 | setClaimGate only with a matured emergency arm; otherwise prints arm -> wait -> set. | R23LowScripts vesting test (registry-semantics stub) |
| StakePanel | "Clear dust reward" when tokRewardOwed > 0, staker epoch current and displayed reward rounds to 0. | npm run type-check exit 0 |

logs/lowfix-full-local.* (before the facet move): 1113 pass / 39 fail / 276 skip;
all 39 failures need a fork; the three former Low failures now pass; no new
failures. Final sizes and the post-move suite: VALIDATION.md.
