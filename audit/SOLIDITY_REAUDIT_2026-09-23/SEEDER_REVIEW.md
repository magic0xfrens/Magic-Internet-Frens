# CauldronSeeder — fresh source review in progress

Read complete production source (constructor through final view) during this
pass. Historical vulnerability narratives in comments are not treated as proof.
Local batch `seeder-local-review` covers SeedLib and T9b/T9c existing assertions;
result pending. Fork-only CauldronSeeder tests are not included or called passed.

## Math caller reconciliation

Actual production askBand/bidBand calls use index 0 and count 1, not arbitrary
external indices/counts. This removes the library's index narrowing concern at
these sites. `_placeStep` independently checks aHi<=liveTick for token-only asks
and bLo>liveTick for native-only bids before sizing. Thus degenerate math ranges
do not automatically imply wrong-currency funding here. `_spacing` and bandWidth
still need registry config joins. Seeder is native currency0/token currency1;
ERC20 quote support must be established at its registry selection boundary,
not inferred from its generic PoolKey type.

## Authority and state observations

- startSeed, withdrawAll, rescue: immutable registry-only, reentrancy lock.
- poke: public, lock; schedule placement precedes separately caught prime call.
- pokeInSwap: configured pool hook only, lock, no nested unlock or prime buy.
- unlockCallback: immutable manager only; other tags select teardown, relying
  on trusted manager callback provenance rather than caller-controlled routing.
- fundPrime: deployer OR registry owner, recipient pinned while unspent budget
  exists; no lock. refundPrime shares principals, locks, requires no campaign
  ever started (gen==0), clears counters before forwarding full native balance.
- _syncRef moves at most 1000 ticks on each observed new block; repeated calls
  in the same block cannot move it again. Multi-block economics remain a gap.
- _teardown removes only tracked ranges; checked native forwarding, unchecked
  token transfer relies on trusted CauldronToken. rescue leaves seeding true so
  later teardown remains reachable. No production changes made in this review.

## R23-L2 — unconfirmed range bookkeeping lead

`_placeStep` reserves an ask range and THEN a bid range before minting either.
At MAX_RANGES, each `_reserveRange` independently evicts the farthest tracked
non-base range, writes new coordinates, and returns. Hypothesis: under a large
reference/spot divergence, the second reservation can evict the just-reserved
ask slot (currently no liquidity), after which ask minting creates liquidity at
coordinates no longer tracked. Teardown would then miss that position.

Not confirmed: must construct a reachable 64-range campaign, force this precise
selection ordering using actual swaps/reference updates, and compare every
minted position with teardown recovery. Existing T9c drift success alone does
not prove this negative property. No severity assigned until reproduced.
Next use its real-manager fixture, preserving existing tests and avoiding
storage-forced production states. Check both ordering and whether the ask
range was already tracked, which would refute the proposed sequence.

Existing local batch completed: 20 passed, zero failures/skips, exit 0 in
2.80s. Includes 16 SeedLib tests and four seeder tests; this is not evidence of
range-set completeness. Added `R23_SeederRangeTracking.t.sol` with actual swaps,
64-range precondition, alternating large spot/reference divergence, tracked
membership checks for sampled newly requested bands, and post-withdraw zero
liquidity checks. Session 97629 / `seeder-range-tracking` pending.

Counterargument to the lead: during ordinary monotonic drift, older farther
ranges can be selected before a newly reserved ask, preventing the proposed
overwrite. Need execution and stronger general reasoning; do not promote the
lead solely from call ordering. Sampling requested bands is also not an
exhaustive event-derived inventory of every historical minted position.

### Execution and reachability update

First range-tracking run passed one test, zero failures/skips (20.84s), session
97629 terminal. Strengthened it with per-poke schedule advancement and positive
funded-position assertions so tracking checks cannot pass merely because both
requested positions are empty. Rerun `seeder-range-tracking-nonvacuous`, session
16808, pending. No production fix or confirmed range-loss finding.

Production caller join: only PoolOps.createAndSeedProgressive invokes startSeed
(besides the interface and standalone contract definition). PoolOps.sol:173 has
`SEED_BASE_WAD = 1e18`; :400-401 therefore allocate the entire active budget to
the base, and :412 returns before :415 startSeed. The non-native quote branch
at :361 separately seeds atomically and returns. Accordingly current registry
launches do not arm progressive campaigns. This is DERIVED from current source,
not an on-chain wiring assertion. Standalone seeder fixtures impersonate the
registry and start campaigns directly; their results cover the seeder component
but do not prove production reachability. A future base-constant change would
re-open that integration surface and needs fresh validation. FundPrime/refund
pre-campaign behavior remains relevant even without active streaming.

Strengthened range test completed: one pass, no failures/skips, exit 0 in
20.86s; session 16808 terminal. Tested six alternating divergence steps, each
with schedule advancement and nonzero liquidity. No range loss reproduced.

## Prime funding/refund boundaries

New `R23_SeederPrimeRefund.t.sol` tests refund rejection rollback then recovery
by the registry owner, stranger exclusion for refund/funding, and recipient
pinning while budget remains. Uses production seeder and a minimal owner getter;
no manager calls or campaign are needed. `seeder-prime-refund` running in session
9480. This does not simulate actual governance ownership or deployment wiring.

Authority qualification: pinning primeTo does NOT prevent both authorized
principals from redirecting pre-campaign value via refundPrime(to), which accepts
any nonzero recipient. The immutable deployer remains a refund authority even
after registry ownership changes. This is explicit source behavior, not a
permissionless theft finding; deployment/authority report must disclose it.
The claim that committed recipients are irrevocable would be false before the
first campaign. Owner/deployer funding is treated as an administrative budget,
not user deposits, pending verification of real funding consumers.

## Final disposition (2026-09-23)

Final: R23-L2 not reproduced; seeder dormant in shipped launches. Signed off.
