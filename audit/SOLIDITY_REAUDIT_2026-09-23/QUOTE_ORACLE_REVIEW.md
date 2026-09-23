# QuoteOracle review — intermediate

Baseline: BASELINE.json, cauldron/QuoteOracle.sol. Entire source body read in
this fresh pass. The 11 implementation declarations below have source-level
review notes; three interface declarations and compiler getters remain separate
mechanical surfaces. This is not completed cross-contract/property coverage.

All IDs below have prefix `0.8.30:` in COMPILER_GRAPH.json. No production edit.

| ID / source line | Node | Authority, effects and property evidence |
|---|---|---|
| 42931 / 110 | constructor | Deployment assigns owner directly; no external calls or custody. Zero owner accepted. GAP: explicit zero-owner/initialization assertion. |
| 42943 / 114 | onlyOwner | Reads owner; exact msg.sender equality; otherwise NotOwner. QuoteOracle.test_OnlyOwnerCanSetFeeds and F14.test_F14_OnlyOwnerMayPrice exercise gated setters. |
| 42955 / 119 | transferOwnership | Owner-only direct replacement; zero allowed; no acceptance step/event. GAP: old-owner rejection, new-owner success and intentional lock behavior. |
| 43033 / 131 | setFeed | Owner-only; nonzero heartbeat required; optional STATICCALL to token decimals before write; preserves bounds, clears peg, emits FeedSet. QuoteOracle.test_ZeroHeartbeatIsRefused; F14.test_F14_SettingAFeedClearsThePeg. GAP: metadata failures and extreme decimals. |
| 43096 / 153 | setPegged | Owner-only; optional token metadata read; overwrites feed with $1 peg, clears bounds; emits FeedSet. F14.test_F14_PeggedStableNeedsNoFeed and test_F14_PegHandlesAnyDecimals cover 6/18 decimals only. Peg bypasses sequencer/feed checks by construction; depeg risk is a configuration assumption. |
| 43140 / 175 | setBounds | Owner-only; rejects inverted nonzero maximum; writes two feed fields; BoundsSet. F14 bounds tests cover rejection, out-of-band and open upper bound. Cache is not invalidated. |
| 43165 / 182 | setSequencer | Owner-only; stores feed/grace; SequencerSet. QuoteOracle owner, down and grace tests. No feed validation; zero disables check. |
| 43365 / 202 | usdPerRawUnit | Public view; reads feed, sequencer, timestamp; external STATICCALLs to round data/decimals. Returns USD per raw unit scaled 1e18; floors divisions. Rejects nonpositive/stale/future/out-of-band values. No writes, asset movement or loops. Checked exponent/multiplication can revert on extreme configured/input values; malformed return behavior remains untested. |
| 43474 / 334 | cachedUsdPerRawUnit | Permissionless cache write for caller-selected quote; self-call to fresh view; updates triedAt before call, at/factor only on usable answer; revert rolls back all writes. TTL early return and failed-refresh throttle; retains old factor indefinitely on zero result. T02 tests execute retention, true age and recovery assertions. Configuration changes do not clear cache. |
| 43490 / 346 | priceable | Public view, self STATICCALL to fresh price, true iff positive. B11.test_INVARIANT_B11_ViewsDegradeRatherThanThrow exercises reverting feed. Does not describe usability of retained volume cache. |
| 43558 / 350 | _sequencerOk | Internal view; no sequencer means true; otherwise static read, up==0, nonzero nonfuture start and elapsed strictly greater than grace. Catch returns false. QuoteOracle and B11 exercise down/grace/reverting/future cases. GAP: exact boundary and malformed ABI. |

## Executed evidence

- logs/oracle-local-review.*: 26 passed, 0 failed, 0 skipped (QuoteOracle,
  F14_OracleSafety, F15_QuotePriceability). Source assertions inspected.
- logs/oracle-cache-review.*: 9 passed, 0 failed, 0 skipped (B11, T02).
- These are local fixtures, not deployed-feed verification. Existing time-based
  tests do not uniformly assert warp landing via vm.getBlockTimestamp; do not
  treat their success as exhaustive optimizer/time-boundary coverage.

## Evidence-quality corrections

T02.test_T02_POC_RotationFloorIsBuiltOnTheStalePrice never invokes the rotator.
It establishes that a cached old factor remains nonzero while priceable is
false. It does NOT demonstrate the named rotation-floor vulnerability in this
tree. QuoteRotator._oracleFloor:469 calls _usdLive:665, which reads uncached
usdPerRawUnit by staticcall. Its historical test name/comment is stale evidence.

B11.test_B11a_StaleFeedKeepsTheCachedValue sets updatedAt=1 and advances only
TTL+1 (901 seconds), with heartbeat=3600. It does not assert fresh-price rejection
before testing retention. The claimed stale precondition is not established by
the test and, at the ordinary initial timestamp of 1, is false. Other stale tests
exist; this particular pass is not proof of stale-cache fallback.

## Remaining boundary work

Verify actual feed/peg/sequencer/owner configuration and consumers. In particular,
comments describing peg pricing as volume-only are insufficient now that rotator
and perp conversion also consume this oracle. Establish supported asset decimals,
malformed or overflowing feed behavior, cache changes after configuration edits,
and downstream handling of zero/revert. No severity is assigned from an oracle
unit failure without reachable consumer impact and the appropriate trust model.
