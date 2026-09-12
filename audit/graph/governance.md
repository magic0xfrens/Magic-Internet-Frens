# Function graph — `governance`

| file | lines |
|---|---|
| `cauldron/CauldronGovernor.sol` | 491 |
| `cauldron/TreasuryGovernor.sol` | 797 |

Source tree: `/tmp/blind-final/contracts/solidity`.
Generated from the decontaminated tree; line numbers are identical to the repo.

35 nodes: 2 contracts (`CauldronGovernor`, 11 nodes + 1 constructor-less interface; `TreasuryGovernor`, 18 nodes) and 4 interfaces declared inside the two files (`IRegistryQuotes` twice, `IVotes721`, `IQuotePrice`).

Two independent governors with no code shared between them:
* `CauldronGovernor` — chooses the next NFT brew. One writer of state outside voting: the registry, through `markConsumed` (CauldronGovernor.sol:475).
* `TreasuryGovernor` — approves an ENVELOPE (destination asset + bps budget) that the registry's rotation facet spends. It never touches liquidity itself.

---

## A. Value inventory

Neither file is payable, holds a token balance, or transfers anything: there is no `payable`, no `.call{value:}`, no `transfer`, and no ERC20 interface in either contract (DERIVED — the only external calls are the six view calls listed in section D). Every field below is a COUNTER; two of them authorise value movement in another cluster.

### `CauldronGovernor`

| field | denomination | increases | decreases |
|---|---|---|---|
| `proposalCount` (CauldronGovernor.sol:141) | proposal ids | `++proposalCount` (CauldronGovernor.sol:345) | never |
| `_proposals[id].votes` (CauldronGovernor.sol:124) | MiFrens voting units (1 NFT = 1 vote, checkpointed) | `p.votes += weight` (CauldronGovernor.sol:402); initialised 0 (CauldronGovernor.sol:358) | never — there is no un-vote |
| `_leaderVotes` (CauldronGovernor.sol:149) | same | `= p.votes` (CauldronGovernor.sol:414) | `= _runnerVotes` (CauldronGovernor.sol:491), `= _recomputeLeader()` (CauldronGovernor.sol:495) — both can lower it |
| `_leaderId` (CauldronGovernor.sol:148) | proposal id | `= proposalId` (CauldronGovernor.sol:415), `= _runnerId` (CauldronGovernor.sol:490), `= _recomputeLeader()` (CauldronGovernor.sol:495) | same three writes |
| `_runnerVotes` (CauldronGovernor.sol:179) | same | `= _leaderVotes` (CauldronGovernor.sol:412), `= p.votes` (CauldronGovernor.sol:417) | `= 0` (CauldronGovernor.sol:498), `= 0` (CauldronGovernor.sol:498) |
| `_runnerId` (CauldronGovernor.sol:178) | proposal id | `= _leaderId` (CauldronGovernor.sol:411), `= proposalId` (CauldronGovernor.sol:418) | `= 0` (CauldronGovernor.sol:497), `= 0` (CauldronGovernor.sol:497) |
| `_proposals[id].consumed` (CauldronGovernor.sol:127) | one-way flag | `= true` (CauldronGovernor.sol:480) | only by re-initialisation, which cannot happen: ids are monotone (CauldronGovernor.sol:345) |
| `hasVoted` (CauldronGovernor.sol:145) | one-way flag | `= true` (CauldronGovernor.sol:401) | never |
| `registry` (CauldronGovernor.sol:139) | address | `= _registry` (CauldronGovernor.sol:254) | never (write-once, CauldronGovernor.sol:252) |

The value this cluster actually controls is downstream: the winning proposal's `quote` (CauldronGovernor.sol:354), `nftSupply` (CauldronGovernor.sol:355) and `volumePerNFT` (CauldronGovernor.sol:356) are replayed by `relaunch` through `winner` (CauldronRegistry.sol:867).

### `TreasuryGovernor`

| field | denomination | increases | decreases |
|---|---|---|---|
| `proposalCount` (TreasuryGovernor.sol:137) | proposal ids | `++proposalCount` (TreasuryGovernor.sol:440) | never |
| `proposals[id].forVotes` (TreasuryGovernor.sol:110) | MiFrens voting units at the proposal snapshot | `p.forVotes += w` (TreasuryGovernor.sol:475); initialised 0 (TreasuryGovernor.sol:456) | never |
| `proposals[id].againstVotes` (TreasuryGovernor.sol:111) | same | `p.againstVotes += w` (TreasuryGovernor.sol:475); initialised 0 (TreasuryGovernor.sol:457) | never |
| `_leadVotes` (TreasuryGovernor.sol:164) | same | `= v` (TreasuryGovernor.sol:487), `= v` (TreasuryGovernor.sol:487), `= v` (TreasuryGovernor.sol:487) | `= v` (TreasuryGovernor.sol:487) — the one branch that can lower it |
| `_leadId` (TreasuryGovernor.sol:163) | proposal id | `= id` (TreasuryGovernor.sol:491), `= id` (TreasuryGovernor.sol:491), `= id` (TreasuryGovernor.sol:491) | same writes; never cleared to 0 |
| `_openVotedAt` (TreasuryGovernor.sol:206) | timestamp | `= block.timestamp` (TreasuryGovernor.sol:498), `= block.timestamp` (TreasuryGovernor.sol:498) | never |
| `envelope.maxTotalBps` (TreasuryGovernor.sol:121) | bps budget, 1e4 scale, ceiling 30_000 | `= p.maxTotalBps` (TreasuryGovernor.sol:603) | overwritten only by the next `execute` |
| **`envelope.movedBps`** (TreasuryGovernor.sol:122) | bps of the SOURCE leg, summed across slices | `e.movedBps += bps` (TreasuryGovernor.sol:857) | reset to 0 on a new envelope (TreasuryGovernor.sol:604) |
| **`envelope.movedPrimaryBps`** (TreasuryGovernor.sol:128) | bps taken out of the generation's own position | `e.movedPrimaryBps += bps` (TreasuryGovernor.sol:858) | reset to 0 (TreasuryGovernor.sol:607) |
| `envelope.active` (TreasuryGovernor.sol:124) | flag | `= true` (TreasuryGovernor.sol:606) | `= false` (TreasuryGovernor.sol:619) guardian cancel, `= false` (TreasuryGovernor.sol:870) exhaustion, on the same counter `allowance` reports |
| `envelope.expiry` (TreasuryGovernor.sol:123) | timestamp | `= now + ENVELOPE_LIFETIME` (TreasuryGovernor.sol:605) | never rewound |
| `lastEnvelopeAt` (TreasuryGovernor.sol:141) | timestamp | `= block.timestamp` (TreasuryGovernor.sol:609) | never rewound, not even by `cancel` (TreasuryGovernor.sol:616) |
| `quoteOracle` (TreasuryGovernor.sol:92) | address | `= o` (TreasuryGovernor.sol:945) | same setter, any number of times |
| `guardian` (TreasuryGovernor.sol:133) | address | `= _guardian` (TreasuryGovernor.sol:375), `= g` (TreasuryGovernor.sol:634) | same setter, including to address zero |
| `activeProposal` (TreasuryGovernor.sol:138) | — | **never written** | **never read** — declared and unused; it still occupies its own slot and is exposed as a public getter |

`movedBps` and `movedPrimaryBps` are the only counters in the cluster that gate real value: `allowance` (TreasuryGovernor.sol:753) turns them into the remaining bps the registry may rotate, read at `allowance` (RedemptionExt.sol:303) and booked back at `consume` (RedemptionExt.sol:459).

---

## B. Balance vs counter

Nothing in this cluster reads a balance, a position, or a price magnitude. Three places where a counter and the thing it stands for can diverge:

1. **`envelope.movedBps` is a spend budget, not a position fraction.** `consume` books the caller's nominal `bps` (TreasuryGovernor.sol:857) with no reference to any amount actually moved, and the ceiling `MAX_ENVELOPE_BPS` (TreasuryGovernor.sol:308) is 30_000 — three times a whole position. The comment at `consume` (TreasuryGovernor.sol:284) states the reason: each slice takes its share of the CURRENT position, so budget bps compound rather than sum. `conversionFor` (TreasuryGovernor.sol:317) exists solely to convert the counter into the share it really moves.
2. **`movedPrimaryBps` is asserted by the caller, not verified.** The `fromPrimary` flag arrives as a parameter (TreasuryGovernor.sol:827) and the registry decides it at `consume` (RedemptionExt.sol:459). `migrationMandateSpent` (TreasuryGovernor.sol:811) — the only thing permitted to redenominate a generation, read at `migrationMandateSpent` (RedemptionExt.sol:526) — trusts that flag completely.
3. **`forVotes` is a sum of snapshot weights, never reconciled with supply.** Quorum divides by `getPastTotalSupply` (TreasuryGovernor.sol:887) at the proposal's snapshot while the tallies accumulate live; the two are read at the same timepoint, so they agree, but neither is checked against any balance at execution time.

`CauldronGovernor` has no balance-backed counter at all: `votes` (CauldronGovernor.sol:402) is a pure tally and the winner it elects is consumed on trust by `markConsumed` (CauldronRegistry.sol:995).

---

## C. Authority map

| gate | where | who holds it | rotatable? | dead-end? |
|---|---|---|---|---|
| `onlyOwner` on `setRegistry` | CauldronGovernor.sol:251 | Ownable owner, initially the deployer via `Ownable(msg.sender)` (CauldronGovernor.sol:243) | ownership yes (`transferOwnership`), the registry itself NO — `RegistryAlreadySet` (CauldronGovernor.sol:252) makes it write-once | yes: `renounceOwnership` before wiring leaves `markConsumed` (CauldronGovernor.sol:475) unreachable forever |
| `msg.sender != registry` | CauldronGovernor.sol:476 | the registry address written once at CauldronGovernor.sol:254 | no | yes, if the registry is never set or is set to a contract that never calls it |
| non-zero live votes to propose | CauldronGovernor.sol:294 | any holder of one MiFren | n/a | no |
| one ballot per address, snapshot weight | CauldronGovernor.sol:392, CauldronGovernor.sol:398 | every holder at the proposal's snapshot block | n/a | no |
| `PROPOSAL_THRESHOLD` (5) live votes | TreasuryGovernor.sol:416 | any holder of five MiFrens | n/a | no |
| one ballot per address, snapshot weight | TreasuryGovernor.sol:469, TreasuryGovernor.sol:471 | every holder at the proposal's snapshot block | n/a | no |
| execute — none | TreasuryGovernor.sol:558 | anyone; only proposal STATE gates apply | n/a | no |
| `msg.sender != guardian` on `cancel` | TreasuryGovernor.sol:617 | `guardian` (TreasuryGovernor.sol:375) | yes, via `setGuardian` (TreasuryGovernor.sol:631) | yes — guardian may set itself to address zero (TreasuryGovernor.sol:634), with no zero-check |
| `msg.sender != guardian` on `setGuardian` | TreasuryGovernor.sol:617 | the same address; self-rotating, single-step, no event | yes | yes, same |
| `msg.sender != guardian` on `setQuoteOracle` | TreasuryGovernor.sol:944 | the same address | yes | yes, same |
| `msg.sender != registry` on `consume` | TreasuryGovernor.sol:828 | the immutable `registry` (TreasuryGovernor.sol:374) | **no** — immutable, no setter | yes, if constructed with a wrong or code-less address |
| the quote allowlist | TreasuryGovernor.sol:420, TreasuryGovernor.sol:594 | NOT this contract: the registry owner, via `setAllowedQuote` (CauldronRegistry.sol:308) | outside this cluster | n/a |

Notes.
* Every `TreasuryGovernor` admin power is one address. There is no timelock and no multi-sig requirement anywhere in the file (DERIVED — `guardian` is the only role checked, at TreasuryGovernor.sol:617, TreasuryGovernor.sol:617 and TreasuryGovernor.sol:944).
* `CauldronGovernor` inherits `Ownable` (CauldronGovernor.sol:28), so `owner()`, `transferOwnership(address)` and `renounceOwnership()` are part of its external surface; `TreasuryGovernor` has no owner at all.
* Neither contract is pausable and neither has an upgrade path.

---

## D. External calls, value, and CEI ordering

Six external calls in the cluster. All six target functions declared `view` — `getPastVotes` (TreasuryGovernor.sol:5), `getVotes` (TreasuryGovernor.sol:6), `getPastTotalSupply` (TreasuryGovernor.sol:15), `allowedQuote` (TreasuryGovernor.sol:19), `usdPerRawUnit` (TreasuryGovernor.sol:24), plus OZ's `IVotes` — so solc emits STATICCALL and none of them can re-enter to write state (DERIVED). None carries value.

| # | call site | callee | value | ordering |
|---|---|---|---|---|
| 1 | `mifrens.getVotes` (CauldronGovernor.sol:294) | immutable `mifrens` (CauldronGovernor.sol:245) | none | first statement; all writes follow at CauldronGovernor.sol:345 |
| 2 | `registry.staticcall` (CauldronGovernor.sol:339) | owner-set `registry` (CauldronGovernor.sol:254) — explicit low-level call, return length checked at CauldronGovernor.sol:342 | none | check before effect; the proposal is written after, at CauldronGovernor.sol:346 |
| 3 | `mifrens.getPastVotes` (CauldronGovernor.sol:398) | immutable `mifrens` | none | before the `hasVoted` write (CauldronGovernor.sol:401) and the tally (CauldronGovernor.sol:402) |
| 4 | `mifrens.getVotes` (TreasuryGovernor.sol:416) | immutable `mifrens` (TreasuryGovernor.sol:373) | none | first statement; writes at TreasuryGovernor.sol:440 |
| 5 | `allowedQuote` (TreasuryGovernor.sol:420) and `allowedQuote` (TreasuryGovernor.sol:594) | immutable `registry` (TreasuryGovernor.sol:374) | none | both precede every write in their function (TreasuryGovernor.sol:440, TreasuryGovernor.sol:600) |
| 6 | `usdPerRawUnit` (TreasuryGovernor.sol:938) | mutable `quoteOracle` (TreasuryGovernor.sol:936), guardian-controlled | none | reached from TreasuryGovernor.sol:421 and TreasuryGovernor.sol:598, in both cases before any state write |

`mifrens.getPastTotalSupply` (TreasuryGovernor.sol:887) is inside a `view` function and reachable from `execute` at `_passed` (TreasuryGovernor.sol:563) — again before `p.executed = true` (TreasuryGovernor.sol:600).

Checks-effects ordering is clean everywhere: every function in the cluster does all of its external reads first and all of its writes last. The one call that is NOT a compiler-generated staticcall is #2, `registry.staticcall` (CauldronGovernor.sol:339), whose failure modes are handled explicitly (`!ok`, short return, false decode) at CauldronGovernor.sol:342.

Internal library call, not external: `LaunchLib.displayName` (CauldronGovernor.sol:372) is `internal pure` (ICauldron.sol:38).

Inbound calls into the cluster (the other side of the trust boundary): `hasProposals` (CauldronRegistry.sol:805), `winner` (CauldronRegistry.sol:867), `markConsumed` (CauldronRegistry.sol:995), `allowance` (RedemptionExt.sol:303), `consume` (RedemptionExt.sol:459), `migrationMandateSpent` (RedemptionExt.sol:526).

---

## E. Loops

| loop | bound | who can grow the bound |
|---|---|---|
| `for (uint256 i; i < BENCH_SLOTS; ++i)` in `_recomputeLeader` (CauldronGovernor.sol:560) | FIXED: exactly `BENCH_SLOTS` = 8 (CauldronGovernor.sol:200), whatever the proposal count | no longer grown by anyone: entry is priced in VOTES, not ids — `_benchRecord` (CauldronGovernor.sol:429) admits a proposal only if it out-weighs the weakest LIVE entry at `weakVotes` (CauldronGovernor.sol:443), so filings alone cannot displace a voted mandate. The remaining ceiling is how many mandates can be tracked at once (DERIVED). `markConsumed` still promotes `_runnerId` (CauldronGovernor.sol:490) before rescanning |
| `for (uint256 i; i < BENCH_SLOTS; ++i)` in `winner` (TreasuryGovernor.sol:706) | FIXED: `BENCH_SLOTS` = 8 (TreasuryGovernor.sol:209). The earlier unbounded `1..proposalCount` walk and the time-bounded backwards walk are both gone; `proposalCount` is not read here at all | entry requires a FOR-vote that beats the weakest non-dead entry at `weakVotes` (TreasuryGovernor.sol:549), so a 5-MiFren filer can no longer inflate the scan. The `_leadId` fast path still short-circuits the loop entirely at `_executable` (TreasuryGovernor.sol:672) |
| `for (uint256 i; i < n && rem > 0; ++i)` in `conversionFor` (TreasuryGovernor.sol:322) | `n = spendBps / sliceBps` (TreasuryGovernor.sol:319), both caller-supplied `uint16`; up to 65_535 iterations at `sliceBps == 1` | any caller, but the function is `external pure` with no storage access and no internal caller, so the cost is the caller's own (DERIVED) |

Both governors reach a scan from the path that matters: `_bestUnconsumed` (CauldronGovernor.sol:522) is called by `hasProposals` (CauldronGovernor.sol:471) and `winner` (CauldronGovernor.sol:452), and `markConsumed` can call `_recomputeLeader` (CauldronGovernor.sol:495) — up to three scans per rebirth; `execute` gates on `winner()` (TreasuryGovernor.sol:568).

---

## F. Denomination and units

* **Votes** are NFT units. `CauldronGovernor` weighs with `getPastVotes` (CauldronGovernor.sol:398) and admits with `getVotes` (CauldronGovernor.sol:294); `TreasuryGovernor` does the same at TreasuryGovernor.sol:471 and TreasuryGovernor.sol:416. There is no decimals conversion anywhere in the cluster and no ERC20 amount is ever read.
* **Threshold vs ballot asymmetry**: admission uses LIVE power (`getVotes`, CauldronGovernor.sol:294 and TreasuryGovernor.sol:416) while ballots use SNAPSHOT power (`getPastVotes`, CauldronGovernor.sol:398 and TreasuryGovernor.sol:471).
* **Quorum** is a fraction of `getPastTotalSupply` (TreasuryGovernor.sol:887) at the proposal's snapshot, scaled by `QUORUM_BPS` = 1000 (TreasuryGovernor.sol:328) over a 10_000 denominator written literally at TreasuryGovernor.sol:887. `CauldronGovernor` has NO quorum: the winner is a plurality (CauldronGovernor.sol:566).
* **bps** are 1e4-scale throughout: `BPS_ONE` = 10_000 (TreasuryGovernor.sol:818), `MAX_ENVELOPE_BPS` = 30_000 (TreasuryGovernor.sol:308) which deliberately EXCEEDS one whole position, and `conversionFor` carries its remainder in 1e4 fixed point (TreasuryGovernor.sol:321).
* **`movedBps` and `maxTotalBps` are not the same unit as a position fraction** — see section B item 1. `migrationMandateSpent` (TreasuryGovernor.sol:813) therefore tests INTENT (`maxTotalBps >= BPS_ONE`) plus exhaustion of the primary counter, not a drained pool.
* **`usdPerRawUnit` is used as a boolean.** Its magnitude is discarded; only `== 0` is tested (TreasuryGovernor.sol:938), so no scaling assumption is made about the feed.
* **address zero is a real quote**, not a sentinel: it is the native destination exempted at `quote` (TreasuryGovernor.sol:935) and skipped by the allowlist lookup at CauldronGovernor.sol:338, which is why `allowance` uses the REMAINDER as its liveness flag (TreasuryGovernor.sol:776) and not the returned address.
* **Time** is `block.timestamp` seconds everywhere except the snapshot, which is `block.number` on the brew side (CauldronGovernor.sol:359) and `block.number - 1` — the previous, already-sealed block — on the treasury side (TreasuryGovernor.sol:455). `uint64` casts on timestamps at TreasuryGovernor.sol:444, TreasuryGovernor.sol:498, TreasuryGovernor.sol:605 and TreasuryGovernor.sol:609; `CauldronGovernor` declares `votingEndsAt` as `uint256` (CauldronGovernor.sol:126).

---

## G. `unchecked` blocks and rounding direction

**There is no `unchecked` block in either file** — every arithmetic operation in the cluster is checked (verified by grep over both files).

Rounding and truncation, all integer division:

| site | direction | consequence |
|---|---|---|
| `rem = (rem * (10_000 - sliceBps)) / 10_000` (TreasuryGovernor.sol:323) | remainder truncates DOWN | the returned conversion `10_000 - rem` (TreasuryGovernor.sol:325) rounds UP — it never understates how much a budget converts (DERIVED) |
| `need = (getPastTotalSupply(...) * QUORUM_BPS) / 10_000` (TreasuryGovernor.sol:887) | DOWN | quorum is slightly easier than 10%; the comparison at TreasuryGovernor.sol:888 is inclusive (`>=`), which loosens it by one more vote (DERIVED) |
| `n = uint256(spendBps) / sliceBps` (TreasuryGovernor.sol:319) | DOWN | a partial slice is not counted |
| bench displacement `votes > weakVotes` (CauldronGovernor.sol:443) | exact integer comparison, no division; `MAX_LEADER_SCAN` (CauldronGovernor.sol:550) is no longer read by the scan | |
| `e.maxTotalBps - spent` (TreasuryGovernor.sol:777) | exact; guarded by the early return at TreasuryGovernor.sol:776, where `spent` is `movedPrimaryBps` for a full-position mandate and `movedBps` otherwise (TreasuryGovernor.sol:775) | |
| `uint16(10_000 - rem)` (TreasuryGovernor.sol:325) | cast of a value `<= 10_000` | cannot truncate, since `rem <= 10_000` by construction (DERIVED) |

Accumulators that could in principle overflow are bounded by their own gates: `e.movedBps += bps` (TreasuryGovernor.sol:857) is preceded by `bps > left` (TreasuryGovernor.sol:853) for a primary slice and by the shared-total test at TreasuryGovernor.sol:854 for a secondary one, so the sum never exceeds `maxTotalBps <= 30_000` and stays inside `uint16`; a violation would revert rather than wrap, since the file has no `unchecked`.

---

## H. Comment-vs-code observations

Ten, all recorded on their nodes in `governance.json`.

1. `CauldronGovernor.vote` — comment `balanceOf` (CauldronGovernor.sol:15) says the guild votes snapshot-free with weight read live from the MiFrens ERC721 balance; code `getPastVotes` (CauldronGovernor.sol:398) reads checkpointed weight at the stored `snapshot` (CauldronGovernor.sol:397), and `SnapshotNotReady` (CauldronGovernor.sol:397) refuses any vote in the proposing block.
2. `CauldronGovernor.setRegistry` — comment `markConsumed` (CauldronGovernor.sol:20) says the only privileged call is `markConsumed`, restricted to the registry; code `onlyOwner` (CauldronGovernor.sol:251) adds an owner-gated setter, and `Ownable` (CauldronGovernor.sol:243) adds `transferOwnership` and `renounceOwnership` to the external surface.
3. `CauldronGovernor.propose` — comment `markConsumed` (CauldronGovernor.sol:315) says a proposal is untrusted input that must be rejected at this boundary because a deeper revert would freeze the machine; code bounds `nftSupply` (CauldronGovernor.sol:316) and the five strings at `FieldTooLong` (CauldronGovernor.sol:305) but stores `volumePerNFT` (CauldronGovernor.sol:356) unbounded, and it reaches the hook unclamped at `setNftCurveFrom` (CauldronRegistry.sol:1098).
4. `TreasuryGovernor.propose` — comment `active` (TreasuryGovernor.sol:413) says a proposal occupies the only active slot for three days; code `envelope` (TreasuryGovernor.sol:437) refuses only while an ENVELOPE is live, and `proposalCount` (TreasuryGovernor.sol:440) increments without limit, so any number of proposals can be open at once.
5. `TreasuryGovernor.winner` — the doc block still describes a time-bounded BACKWARDS walk over proposal ids stopping at the first too-old proposal, at `votingEndsAt` (TreasuryGovernor.sol:690), and `MAX_WINNER_SCAN` is described as removed at `MAX_WINNER_SCAN` (TreasuryGovernor.sol:664); code walks only `_bench` (TreasuryGovernor.sol:707). The header's promise of an id-deterministic tie-break at `Ties` (TreasuryGovernor.sol:642) no longer holds on the fallback path, where ties break to the lowest bench SLOT (DERIVED).
6. `TreasuryGovernor.consume` — comment `Registry` (TreasuryGovernor.sol:820) says the function is registry-only; code `registry` (TreasuryGovernor.sol:828) checks the registry but reverts with the guardian's error `NotGuardian` (TreasuryGovernor.sol:828).
7. `TreasuryGovernor.consume` — comment `propose` (TreasuryGovernor.sol:860) cites the proposal gate at line 322 and comment `cancel` (TreasuryGovernor.sol:861) cites line 409; code puts that gate at `envelope` (TreasuryGovernor.sol:437) and declares `cancel` (TreasuryGovernor.sol:616).
8. `TreasuryGovernor._passed` — comment `vote` (TreasuryGovernor.sol:881) says quorum is read at the same timepoint the vote weighs ballots and points at line 384; code weighs ballots at `getPastVotes` (TreasuryGovernor.sol:471) and reads the denominator at `getPastTotalSupply` (TreasuryGovernor.sol:887).
9. `TreasuryGovernor._requirePriceable` — comment `setQuoteAllowed` (TreasuryGovernor.sol:905) names the registry's allowlist setter; the registry declares it as `setAllowedQuote` (CauldronRegistry.sol:308) and writes the mapping at `allowedQuote` (CauldronRegistry.sol:321).
10. `TreasuryGovernor.setQuoteOracle` — comment `Timelock` (TreasuryGovernor.sol:941) says the oracle is timelock-set and comment `timelock` (TreasuryGovernor.sol:48) says only the timelock adds assets; code gates this setter on `guardian` (TreasuryGovernor.sol:944) and the allowlist on the registry owner at `setAllowedQuote` (CauldronRegistry.sol:308). No timelock contract is referenced anywhere in the file.

---

## I. Function inventory


### `cauldron/CauldronGovernor.sol`

| line | signature | authority | value effect |
|---|---|---|---|
| 25 | `allowedQuote(address quote) external view returns (bool)` | anyone (declaration only, no body in this file; the selector is dispatched by propose through a low-level staticcall on the owner-set registry address) | NONE |
| 195 | `renounceOwnership() public view override onlyOwner` | owner (and it always reverts) | none - it reverts (DERIVED) |
| 243 | `constructor(address _mifrens) Ownable(msg.sender)` | deployer | NONE |
| 251 | `setRegistry(address _registry) external onlyOwner` | owner | NONE |
| 280 | `propose( string calldata name, string calldata symbol, MetadataMode mode, string calldata baseURI, address renderer, string calldata website, string calldata socials, uint256 nftSupply, uint256 volumePerNFT, address quote ) external returns (uint256 id)` | voter/holder (any address with non-zero live MiFrens voting power) | NONE |
| 369 | `displayName(uint256 proposalId) external view returns (string memory)` | anyone | NONE |
| 383 | `vote(uint256 proposalId) external` | anyone holding checkpointed MiFrens voting power at the proposal's snapshot | none - it only records votes; no asset moves (DERIVED) |
| 429 | `_benchRecord(uint256 id, uint256 votes) private` | private (single caller: vote) | none - bookkeeping only (DERIVED) |
| 451 | `winner() external view returns (uint256 proposalId, BrewSpec memory spec)` | anyone (the registry is the production caller) | NONE |
| 470 | `hasProposals() external view returns (bool)` | anyone (the registry is the production caller) | NONE |
| 475 | `markConsumed(uint256 proposalId) external` | registry | NONE |
| 512 | `getProposal(uint256 id) external view returns (Proposal memory)` | anyone | NONE |
| 522 | `_bestUnconsumed() private view returns (uint256)` | internal (callers: winner, hasProposals) | NONE |
| 554 | `_recomputeLeader() private view returns (uint256 bestId, uint256 bestVotes)` | private view (caller: _bestUnconsumed) | none - a view (DERIVED) |

### `cauldron/TreasuryGovernor.sol`

| line | signature | authority | value effect |
|---|---|---|---|
| 5 | `getPastVotes(address account, uint256 blockNumber) external view returns (uint256)` | anyone (declaration only, no body; dispatched on the immutable mifrens address) | NONE |
| 6 | `getVotes(address account) external view returns (uint256)` | anyone (declaration only, no body; dispatched on the immutable mifrens address) | NONE |
| 15 | `getPastTotalSupply(uint256 timepoint) external view returns (uint256)` | anyone (declaration only, no body; dispatched on the immutable mifrens address) | NONE |
| 19 | `allowedQuote(address quote) external view returns (bool)` | anyone (declaration only, no body; dispatched on the immutable registry address) | NONE |
| 24 | `usdPerRawUnit(address quote) external view returns (uint256)` | anyone (declaration only, no body; dispatched on the guardian-set quoteOracle address) | NONE |
| 317 | `conversionFor(uint16 spendBps, uint16 sliceBps) external pure returns (uint16)` | anyone | NONE |
| 363 | `constructor( IVotes721 _mifrens, address _registry, address _guardian, uint64 votingPeriod, uint64 envelopeLifetime, uint64 cooldown, uint64 executionWindow, bool testnet )` | deployer | NONE |
| 415 | `propose(address quote, uint16 maxTotalBps) external returns (uint256 id)` | anyone holding at least PROPOSAL_THRESHOLD MiFrens of live voting power | none - filing a proposal moves nothing (DERIVED) |
| 465 | `vote(uint256 id, bool support) external` | anyone holding checkpointed MiFrens power at the proposal's snapshot | none - it only records votes (DERIVED) |
| 534 | `_benchRecord(uint256 id, uint256 votes) private` | private (single caller: vote, on a FOR-vote only) | none - bookkeeping only (DERIVED) |
| 558 | `execute(uint256 id) external` | anyone (permissionless, by design - an approved rotation must not need a privileged executor) | no asset moves here - it installs the envelope that later authorises `rotateSliceFrom` to move liquidity, at `envelope` (line 601) |
| 616 | `cancel(uint256 id) external` | guardian | NONE |
| 631 | `setGuardian(address g) external` | guardian only | none (DERIVED) |
| 667 | `winner() public view returns (uint256 best)` | anyone (public view) | none - a view (DERIVED) |
| 717 | `_executable(Proposal storage p) private view returns (bool)` | internal (callers: winner) | NONE |
| 736 | `_dead(Proposal storage p) private view returns (bool)` | internal (callers: vote) | NONE |
| 753 | `allowance() public view returns (address quote, uint16 remainingBps)` | anyone (public view) | none - a view (DERIVED) |
| 811 | `migrationMandateSpent() external view returns (bool)` | anyone (the registry rotation path is the production caller) | NONE |
| 827 | `consume(uint16 bps, bool fromPrimary) external` | registry only | none - accounting only; the liquidity has already moved in the caller (DERIVED) |
| 876 | `_passed(Proposal storage p) private view returns (bool)` | internal (callers: execute, winner, _executable, passing) | NONE |
| 891 | `_settled(uint256 id) private view returns (bool)` | internal (callers: none in this file) | NONE |
| 897 | `passing(uint256 id) external view returns (bool)` | anyone | NONE |
| 934 | `_requirePriceable(address quote) internal view` | internal (callers: propose, execute) | NONE |
| 943 | `setQuoteOracle(address o) external` | guardian | NONE |
