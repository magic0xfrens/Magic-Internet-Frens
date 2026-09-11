# Function graph — `governance`

| file | lines |
|---|---|
| `cauldron/CauldronGovernor.sol` | 491 |
| `cauldron/TreasuryGovernor.sol` | 797 |

Source tree: `/tmp/blind-final/contracts/solidity`.
Generated from the decontaminated tree; line numbers are identical to the repo.

35 nodes: 2 contracts (`CauldronGovernor`, 11 nodes + 1 constructor-less interface; `TreasuryGovernor`, 18 nodes) and 4 interfaces declared inside the two files (`IRegistryQuotes` twice, `IVotes721`, `IQuotePrice`).

Two independent governors with no code shared between them:
* `CauldronGovernor` — chooses the next NFT brew. One writer of state outside voting: the registry, through `markConsumed` (CauldronGovernor.sol:399).
* `TreasuryGovernor` — approves an ENVELOPE (destination asset + bps budget) that the registry's rotation facet spends. It never touches liquidity itself.

---

## A. Value inventory

Neither file is payable, holds a token balance, or transfers anything: there is no `payable`, no `.call{value:}`, no `transfer`, and no ERC20 interface in either contract (DERIVED — the only external calls are the six view calls listed in section D). Every field below is a COUNTER; two of them authorise value movement in another cluster.

### `CauldronGovernor`

| field | denomination | increases | decreases |
|---|---|---|---|
| `proposalCount` (CauldronGovernor.sol:141) | proposal ids | `++proposalCount` (CauldronGovernor.sol:291) | never |
| `_proposals[id].votes` (CauldronGovernor.sol:124) | MiFrens voting units (1 NFT = 1 vote, checkpointed) | `p.votes += weight` (CauldronGovernor.sol:348); initialised 0 (CauldronGovernor.sol:304) | never — there is no un-vote |
| `_leaderVotes` (CauldronGovernor.sol:149) | same | `= p.votes` (CauldronGovernor.sol:360) | `= _runnerVotes` (CauldronGovernor.sol:415), `= _recomputeLeader()` (CauldronGovernor.sol:419) — both can lower it |
| `_leaderId` (CauldronGovernor.sol:148) | proposal id | `= proposalId` (CauldronGovernor.sol:361), `= _runnerId` (CauldronGovernor.sol:414), `= _recomputeLeader()` (CauldronGovernor.sol:419) | same three writes |
| `_runnerVotes` (CauldronGovernor.sol:179) | same | `= _leaderVotes` (CauldronGovernor.sol:358), `= p.votes` (CauldronGovernor.sol:363) | `= 0` (CauldronGovernor.sol:422), `= 0` (CauldronGovernor.sol:427) |
| `_runnerId` (CauldronGovernor.sol:178) | proposal id | `= _leaderId` (CauldronGovernor.sol:357), `= proposalId` (CauldronGovernor.sol:364) | `= 0` (CauldronGovernor.sol:421), `= 0` (CauldronGovernor.sol:426) |
| `_proposals[id].consumed` (CauldronGovernor.sol:127) | one-way flag | `= true` (CauldronGovernor.sol:404) | only by re-initialisation, which cannot happen: ids are monotone (CauldronGovernor.sol:291) |
| `hasVoted` (CauldronGovernor.sol:145) | one-way flag | `= true` (CauldronGovernor.sol:347) | never |
| `registry` (CauldronGovernor.sol:139) | address | `= _registry` (CauldronGovernor.sol:200) | never (write-once, CauldronGovernor.sol:198) |

The value this cluster actually controls is downstream: the winning proposal's `quote` (CauldronGovernor.sol:300), `nftSupply` (CauldronGovernor.sol:301) and `volumePerNFT` (CauldronGovernor.sol:302) are replayed by `relaunch` through `winner` (CauldronRegistry.sol:849).

### `TreasuryGovernor`

| field | denomination | increases | decreases |
|---|---|---|---|
| `proposalCount` (TreasuryGovernor.sol:137) | proposal ids | `++proposalCount` (TreasuryGovernor.sol:389) | never |
| `proposals[id].forVotes` (TreasuryGovernor.sol:110) | MiFrens voting units at the proposal snapshot | `p.forVotes += w` (TreasuryGovernor.sol:416); initialised 0 (TreasuryGovernor.sol:397) | never |
| `proposals[id].againstVotes` (TreasuryGovernor.sol:111) | same | `p.againstVotes += w` (TreasuryGovernor.sol:416); initialised 0 (TreasuryGovernor.sol:398) | never |
| `_leadVotes` (TreasuryGovernor.sol:164) | same | `= v` (TreasuryGovernor.sol:428), `= v` (TreasuryGovernor.sol:433), `= v` (TreasuryGovernor.sol:441) | `= v` (TreasuryGovernor.sol:461) — the one branch that can lower it |
| `_leadId` (TreasuryGovernor.sol:163) | proposal id | `= id` (TreasuryGovernor.sol:432), `= id` (TreasuryGovernor.sol:440), `= id` (TreasuryGovernor.sol:460) | same writes; never cleared to 0 |
| `_openVotedAt` (TreasuryGovernor.sol:206) | timestamp | `= block.timestamp` (TreasuryGovernor.sol:439), `= block.timestamp` (TreasuryGovernor.sol:466) | never |
| `envelope.maxTotalBps` (TreasuryGovernor.sol:121) | bps budget, 1e4 scale, ceiling 30_000 | `= p.maxTotalBps` (TreasuryGovernor.sol:503) | overwritten only by the next `execute` |
| **`envelope.movedBps`** (TreasuryGovernor.sol:122) | bps of the SOURCE leg, summed across slices | `e.movedBps += bps` (TreasuryGovernor.sol:708) | reset to 0 on a new envelope (TreasuryGovernor.sol:504) |
| **`envelope.movedPrimaryBps`** (TreasuryGovernor.sol:128) | bps taken out of the generation's own position | `e.movedPrimaryBps += bps` (TreasuryGovernor.sol:709) | reset to 0 (TreasuryGovernor.sol:507) |
| `envelope.active` (TreasuryGovernor.sol:124) | flag | `= true` (TreasuryGovernor.sol:506) | `= false` (TreasuryGovernor.sol:519) guardian cancel, `= false` (TreasuryGovernor.sol:718) exhaustion |
| `envelope.expiry` (TreasuryGovernor.sol:123) | timestamp | `= now + ENVELOPE_LIFETIME` (TreasuryGovernor.sol:505) | never rewound |
| `lastEnvelopeAt` (TreasuryGovernor.sol:141) | timestamp | `= block.timestamp` (TreasuryGovernor.sol:509) | never rewound, not even by `cancel` (TreasuryGovernor.sol:516) |
| `quoteOracle` (TreasuryGovernor.sol:92) | address | `= o` (TreasuryGovernor.sol:793) | same setter, any number of times |
| `guardian` (TreasuryGovernor.sol:133) | address | `= _guardian` (TreasuryGovernor.sol:324), `= g` (TreasuryGovernor.sol:525) | same setter, including to address zero |
| `activeProposal` (TreasuryGovernor.sol:138) | — | **never written** | **never read** — declared and unused; it still occupies its own slot and is exposed as a public getter |

`movedBps` and `movedPrimaryBps` are the only counters in the cluster that gate real value: `allowance` (TreasuryGovernor.sol:643) turns them into the remaining bps the registry may rotate, read at `allowance` (RedemptionExt.sol:303) and booked back at `consume` (RedemptionExt.sol:437).

---

## B. Balance vs counter

Nothing in this cluster reads a balance, a position, or a price magnitude. Three places where a counter and the thing it stands for can diverge:

1. **`envelope.movedBps` is a spend budget, not a position fraction.** `consume` books the caller's nominal `bps` (TreasuryGovernor.sol:708) with no reference to any amount actually moved, and the ceiling `MAX_ENVELOPE_BPS` (TreasuryGovernor.sol:257) is 30_000 — three times a whole position. The comment at `consume` (TreasuryGovernor.sol:233) states the reason: each slice takes its share of the CURRENT position, so budget bps compound rather than sum. `conversionFor` (TreasuryGovernor.sol:266) exists solely to convert the counter into the share it really moves.
2. **`movedPrimaryBps` is asserted by the caller, not verified.** The `fromPrimary` flag arrives as a parameter (TreasuryGovernor.sol:697) and the registry decides it at `consume` (RedemptionExt.sol:437). `migrationMandateSpent` (TreasuryGovernor.sol:681) — the only thing permitted to redenominate a generation, read at `migrationMandateSpent` (RedemptionExt.sol:504) — trusts that flag completely.
3. **`forVotes` is a sum of snapshot weights, never reconciled with supply.** Quorum divides by `getPastTotalSupply` (TreasuryGovernor.sol:735) at the proposal's snapshot while the tallies accumulate live; the two are read at the same timepoint, so they agree, but neither is checked against any balance at execution time.

`CauldronGovernor` has no balance-backed counter at all: `votes` (CauldronGovernor.sol:348) is a pure tally and the winner it elects is consumed on trust by `markConsumed` (CauldronRegistry.sol:977).

---

## C. Authority map

| gate | where | who holds it | rotatable? | dead-end? |
|---|---|---|---|---|
| `onlyOwner` on `setRegistry` | CauldronGovernor.sol:197 | Ownable owner, initially the deployer via `Ownable(msg.sender)` (CauldronGovernor.sol:189) | ownership yes (`transferOwnership`), the registry itself NO — `RegistryAlreadySet` (CauldronGovernor.sol:198) makes it write-once | yes: `renounceOwnership` before wiring leaves `markConsumed` (CauldronGovernor.sol:399) unreachable forever |
| `msg.sender != registry` | CauldronGovernor.sol:400 | the registry address written once at CauldronGovernor.sol:200 | no | yes, if the registry is never set or is set to a contract that never calls it |
| non-zero live votes to propose | CauldronGovernor.sol:240 | any holder of one MiFren | n/a | no |
| one ballot per address, snapshot weight | CauldronGovernor.sol:338, CauldronGovernor.sol:344 | every holder at the proposal's snapshot block | n/a | no |
| `PROPOSAL_THRESHOLD` (5) live votes | TreasuryGovernor.sol:365 | any holder of five MiFrens | n/a | no |
| one ballot per address, snapshot weight | TreasuryGovernor.sol:410, TreasuryGovernor.sol:412 | every holder at the proposal's snapshot block | n/a | no |
| execute — none | TreasuryGovernor.sol:478 | anyone; only proposal STATE gates apply | n/a | no |
| `msg.sender != guardian` on `cancel` | TreasuryGovernor.sol:517 | `guardian` (TreasuryGovernor.sol:324) | yes, via `setGuardian` (TreasuryGovernor.sol:523) | yes — guardian may set itself to address zero (TreasuryGovernor.sol:525), with no zero-check |
| `msg.sender != guardian` on `setGuardian` | TreasuryGovernor.sol:524 | the same address; self-rotating, single-step, no event | yes | yes, same |
| `msg.sender != guardian` on `setQuoteOracle` | TreasuryGovernor.sol:792 | the same address | yes | yes, same |
| `msg.sender != registry` on `consume` | TreasuryGovernor.sol:698 | the immutable `registry` (TreasuryGovernor.sol:323) | **no** — immutable, no setter | yes, if constructed with a wrong or code-less address |
| the quote allowlist | TreasuryGovernor.sol:369, TreasuryGovernor.sol:494 | NOT this contract: the registry owner, via `setAllowedQuote` (CauldronRegistry.sol:290) | outside this cluster | n/a |

Notes.
* Every `TreasuryGovernor` admin power is one address. There is no timelock and no multi-sig requirement anywhere in the file (DERIVED — `guardian` is the only role checked, at TreasuryGovernor.sol:517, TreasuryGovernor.sol:524 and TreasuryGovernor.sol:792).
* `CauldronGovernor` inherits `Ownable` (CauldronGovernor.sol:28), so `owner()`, `transferOwnership(address)` and `renounceOwnership()` are part of its external surface; `TreasuryGovernor` has no owner at all.
* Neither contract is pausable and neither has an upgrade path.

---

## D. External calls, value, and CEI ordering

Six external calls in the cluster. All six target functions declared `view` — `getPastVotes` (TreasuryGovernor.sol:5), `getVotes` (TreasuryGovernor.sol:6), `getPastTotalSupply` (TreasuryGovernor.sol:15), `allowedQuote` (TreasuryGovernor.sol:19), `usdPerRawUnit` (TreasuryGovernor.sol:24), plus OZ's `IVotes` — so solc emits STATICCALL and none of them can re-enter to write state (DERIVED). None carries value.

| # | call site | callee | value | ordering |
|---|---|---|---|---|
| 1 | `mifrens.getVotes` (CauldronGovernor.sol:240) | immutable `mifrens` (CauldronGovernor.sol:191) | none | first statement; all writes follow at CauldronGovernor.sol:291 |
| 2 | `registry.staticcall` (CauldronGovernor.sol:285) | owner-set `registry` (CauldronGovernor.sol:200) — explicit low-level call, return length checked at CauldronGovernor.sol:288 | none | check before effect; the proposal is written after, at CauldronGovernor.sol:292 |
| 3 | `mifrens.getPastVotes` (CauldronGovernor.sol:344) | immutable `mifrens` | none | before the `hasVoted` write (CauldronGovernor.sol:347) and the tally (CauldronGovernor.sol:348) |
| 4 | `mifrens.getVotes` (TreasuryGovernor.sol:365) | immutable `mifrens` (TreasuryGovernor.sol:322) | none | first statement; writes at TreasuryGovernor.sol:389 |
| 5 | `allowedQuote` (TreasuryGovernor.sol:369) and `allowedQuote` (TreasuryGovernor.sol:494) | immutable `registry` (TreasuryGovernor.sol:323) | none | both precede every write in their function (TreasuryGovernor.sol:389, TreasuryGovernor.sol:500) |
| 6 | `usdPerRawUnit` (TreasuryGovernor.sol:786) | mutable `quoteOracle` (TreasuryGovernor.sol:784), guardian-controlled | none | reached from TreasuryGovernor.sol:370 and TreasuryGovernor.sol:498, in both cases before any state write |

`mifrens.getPastTotalSupply` (TreasuryGovernor.sol:735) is inside a `view` function and reachable from `execute` at `_passed` (TreasuryGovernor.sol:483) — again before `p.executed = true` (TreasuryGovernor.sol:500).

Checks-effects ordering is clean everywhere: every function in the cluster does all of its external reads first and all of its writes last. The one call that is NOT a compiler-generated staticcall is #2, `registry.staticcall` (CauldronGovernor.sol:285), whose failure modes are handled explicitly (`!ok`, short return, false decode) at CauldronGovernor.sol:288.

Internal library call, not external: `LaunchLib.displayName` (CauldronGovernor.sol:318) is `internal pure` (ICauldron.sol:38).

Inbound calls into the cluster (the other side of the trust boundary): `hasProposals` (CauldronRegistry.sol:787), `winner` (CauldronRegistry.sol:849), `markConsumed` (CauldronRegistry.sol:977), `allowance` (RedemptionExt.sol:303), `consume` (RedemptionExt.sol:437), `migrationMandateSpent` (RedemptionExt.sol:504).

---

## E. Loops

| loop | bound | who can grow the bound |
|---|---|---|
| `for (uint256 i = first; i <= n; i++)` in `_recomputeLeader` (CauldronGovernor.sol:481) | POSITIONAL: at most `MAX_LEADER_SCAN` = 64 (CauldronGovernor.sol:474), the newest ids, computed at `first` (CauldronGovernor.sol:480) | the window size is fixed, but WHICH proposals fall inside it is grown by anyone: `propose` (CauldronGovernor.sol:226) needs one MiFren of live votes (CauldronGovernor.sol:240), no deposit, no cooldown. A settled, voted proposal older than 64 ids is invisible to this scan; that is why `markConsumed` promotes `_runnerId` (CauldronGovernor.sol:414) instead of rescanning first |
| `for (uint256 i = n; i >= 1; --i)` in `winner` (TreasuryGovernor.sol:593) | TEMPORAL: walks ids downward from `proposalCount` (TreasuryGovernor.sol:566) and `break`s at the first proposal whose window closed more than `EXECUTION_WINDOW` ago (TreasuryGovernor.sol:597). Span = `VOTING_PERIOD + EXECUTION_WINDOW` (6 days on mainnet defaults) | anyone with `PROPOSAL_THRESHOLD` = 5 MiFrens (TreasuryGovernor.sol:365). The COUNT inside the 6-day span is unbounded; the cost ages out rather than persisting (DERIVED). No underflow at `i` = 1: the update runs to 0 and the condition then fails |
| `for (uint256 i; i < n && rem > 0; ++i)` in `conversionFor` (TreasuryGovernor.sol:271) | `n = spendBps / sliceBps` (TreasuryGovernor.sol:268), both caller-supplied `uint16`; up to 65_535 iterations at `sliceBps == 1` | any caller, but the function is `external pure` with no storage access and no internal caller, so the cost is the caller's own (DERIVED) |

Both governors reach a scan from the path that matters: `_bestUnconsumed` (CauldronGovernor.sol:446) is called by `hasProposals` (CauldronGovernor.sol:395) and `winner` (CauldronGovernor.sol:376), and `markConsumed` can call `_recomputeLeader` (CauldronGovernor.sol:419) — up to three scans per rebirth; `execute` gates on `winner()` (TreasuryGovernor.sol:488).

---

## F. Denomination and units

* **Votes** are NFT units. `CauldronGovernor` weighs with `getPastVotes` (CauldronGovernor.sol:344) and admits with `getVotes` (CauldronGovernor.sol:240); `TreasuryGovernor` does the same at TreasuryGovernor.sol:412 and TreasuryGovernor.sol:365. There is no decimals conversion anywhere in the cluster and no ERC20 amount is ever read.
* **Threshold vs ballot asymmetry**: admission uses LIVE power (`getVotes`, CauldronGovernor.sol:240 and TreasuryGovernor.sol:365) while ballots use SNAPSHOT power (`getPastVotes`, CauldronGovernor.sol:344 and TreasuryGovernor.sol:412).
* **Quorum** is a fraction of `getPastTotalSupply` (TreasuryGovernor.sol:735) at the proposal's snapshot, scaled by `QUORUM_BPS` = 1000 (TreasuryGovernor.sol:277) over a 10_000 denominator written literally at TreasuryGovernor.sol:735. `CauldronGovernor` has NO quorum: the winner is a plurality (CauldronGovernor.sol:485).
* **bps** are 1e4-scale throughout: `BPS_ONE` = 10_000 (TreasuryGovernor.sol:688), `MAX_ENVELOPE_BPS` = 30_000 (TreasuryGovernor.sol:257) which deliberately EXCEEDS one whole position, and `conversionFor` carries its remainder in 1e4 fixed point (TreasuryGovernor.sol:270).
* **`movedBps` and `maxTotalBps` are not the same unit as a position fraction** — see section B item 1. `migrationMandateSpent` (TreasuryGovernor.sol:683) therefore tests INTENT (`maxTotalBps >= BPS_ONE`) plus exhaustion of the primary counter, not a drained pool.
* **`usdPerRawUnit` is used as a boolean.** Its magnitude is discarded; only `== 0` is tested (TreasuryGovernor.sol:786), so no scaling assumption is made about the feed.
* **address zero is a real quote**, not a sentinel: it is the native destination exempted at `quote` (TreasuryGovernor.sol:783) and skipped by the allowlist lookup at CauldronGovernor.sol:284, which is why `allowance` uses the REMAINDER as its liveness flag (TreasuryGovernor.sol:646) and not the returned address.
* **Time** is `block.timestamp` seconds everywhere except the snapshot, which is `block.number` (CauldronGovernor.sol:305, TreasuryGovernor.sol:396). `uint64` casts on timestamps at TreasuryGovernor.sol:393, TreasuryGovernor.sol:439, TreasuryGovernor.sol:505 and TreasuryGovernor.sol:509; `CauldronGovernor` declares `votingEndsAt` as `uint256` (CauldronGovernor.sol:126).

---

## G. `unchecked` blocks and rounding direction

**There is no `unchecked` block in either file** — every arithmetic operation in the cluster is checked (verified by grep over both files).

Rounding and truncation, all integer division:

| site | direction | consequence |
|---|---|---|
| `rem = (rem * (10_000 - sliceBps)) / 10_000` (TreasuryGovernor.sol:272) | remainder truncates DOWN | the returned conversion `10_000 - rem` (TreasuryGovernor.sol:274) rounds UP — it never understates how much a budget converts (DERIVED) |
| `need = (getPastTotalSupply(...) * QUORUM_BPS) / 10_000` (TreasuryGovernor.sol:735) | DOWN | quorum is slightly easier than 10%; the comparison at TreasuryGovernor.sol:736 is inclusive (`>=`), which loosens it by one more vote (DERIVED) |
| `n = uint256(spendBps) / sliceBps` (TreasuryGovernor.sol:268) | DOWN | a partial slice is not counted |
| `first = n - MAX_LEADER_SCAN + 1` (CauldronGovernor.sol:480) | exact; guarded by the `n > MAX_LEADER_SCAN` ternary so it cannot underflow | |
| `e.maxTotalBps - e.movedBps` (TreasuryGovernor.sol:647) | exact; guarded by the early return at TreasuryGovernor.sol:646 | |
| `uint16(10_000 - rem)` (TreasuryGovernor.sol:274) | cast of a value `<= 10_000` | cannot truncate, since `rem <= 10_000` by construction (DERIVED) |

Accumulators that could in principle overflow are bounded by their own gates: `e.movedBps += bps` (TreasuryGovernor.sol:708) is preceded by `bps > left` (TreasuryGovernor.sol:707), so the sum never exceeds `maxTotalBps <= 30_000` and stays inside `uint16`; a violation would revert rather than wrap, since the file has no `unchecked`.

---

## H. Comment-vs-code observations

Ten, all recorded on their nodes in `governance.json`.

1. `CauldronGovernor.vote` — comment `balanceOf` (CauldronGovernor.sol:15) says the guild votes snapshot-free with weight read live from the MiFrens ERC721 balance; code `getPastVotes` (CauldronGovernor.sol:344) reads checkpointed weight at the stored `snapshot` (CauldronGovernor.sol:343), and `SnapshotNotReady` (CauldronGovernor.sol:343) refuses any vote in the proposing block.
2. `CauldronGovernor.setRegistry` — comment `markConsumed` (CauldronGovernor.sol:20) says the only privileged call is `markConsumed`, restricted to the registry; code `onlyOwner` (CauldronGovernor.sol:197) adds an owner-gated setter, and `Ownable` (CauldronGovernor.sol:189) adds `transferOwnership` and `renounceOwnership` to the external surface.
3. `CauldronGovernor.propose` — comment `markConsumed` (CauldronGovernor.sol:261) says a proposal is untrusted input that must be rejected at this boundary because a deeper revert would freeze the machine; code bounds `nftSupply` (CauldronGovernor.sol:262) and the five strings at `FieldTooLong` (CauldronGovernor.sol:251) but stores `volumePerNFT` (CauldronGovernor.sol:302) unbounded, and it reaches the hook unclamped at `setNftCurveFrom` (CauldronRegistry.sol:1080).
4. `TreasuryGovernor.propose` — comment `active` (TreasuryGovernor.sol:362) says a proposal occupies the only active slot for three days; code `envelope` (TreasuryGovernor.sol:386) refuses only while an ENVELOPE is live, and `proposalCount` (TreasuryGovernor.sol:389) increments without limit, so any number of proposals can be open at once.
5. `TreasuryGovernor.winner` — comment `execute` (TreasuryGovernor.sol:538) cites the gate at line 273 and comment `MAX_WINNER_SCAN` (TreasuryGovernor.sol:550) describes a positional bound; code declares `execute` (TreasuryGovernor.sol:478) and bounds the loop by the time test at `break` (TreasuryGovernor.sol:597), with no such constant declared.
6. `TreasuryGovernor.consume` — comment `Registry` (TreasuryGovernor.sol:690) says the function is registry-only; code `registry` (TreasuryGovernor.sol:698) checks the registry but reverts with the guardian's error `NotGuardian` (TreasuryGovernor.sol:698).
7. `TreasuryGovernor.consume` — comment `propose` (TreasuryGovernor.sol:711) cites the proposal gate at line 322 and comment `cancel` (TreasuryGovernor.sol:712) cites line 409; code puts that gate at `envelope` (TreasuryGovernor.sol:386) and declares `cancel` (TreasuryGovernor.sol:516).
8. `TreasuryGovernor._passed` — comment `vote` (TreasuryGovernor.sol:729) says quorum is read at the same timepoint the vote weighs ballots and points at line 384; code weighs ballots at `getPastVotes` (TreasuryGovernor.sol:412) and reads the denominator at `getPastTotalSupply` (TreasuryGovernor.sol:735).
9. `TreasuryGovernor._requirePriceable` — comment `setQuoteAllowed` (TreasuryGovernor.sol:753) names the registry's allowlist setter; the registry declares it as `setAllowedQuote` (CauldronRegistry.sol:290) and writes the mapping at `allowedQuote` (CauldronRegistry.sol:303).
10. `TreasuryGovernor.setQuoteOracle` — comment `Timelock` (TreasuryGovernor.sol:789) says the oracle is timelock-set and comment `timelock` (TreasuryGovernor.sol:48) says only the timelock adds assets; code gates this setter on `guardian` (TreasuryGovernor.sol:792) and the allowlist on the registry owner at `setAllowedQuote` (CauldronRegistry.sol:290). No timelock contract is referenced anywhere in the file.

---

## I. Function inventory

### `CauldronGovernor.sol`

| line | signature | authority | value effect |
|---|---|---|---|
| 25 | `IRegistryQuotes.allowedQuote(address) external view` | declaration only; dispatched by `propose` | none |
| 189 | `constructor(address _mifrens)` | deployer | none; freezes `mifrens` (CauldronGovernor.sol:191) |
| 197 | `setRegistry(address) external onlyOwner` | owner, once | none; names the only `markConsumed` caller |
| 226 | `propose(string,string,MetadataMode,string,address,string,string,uint256,uint256,address) external` | any holder with non-zero live votes (CauldronGovernor.sol:240) | none; writes the spec `relaunch` will replay |
| 315 | `displayName(uint256) external view` | anyone | none |
| 329 | `vote(uint256) external` | one ballot per address, snapshot weight (CauldronGovernor.sol:344) | none; moves the leader/runner pair |
| 375 | `winner() external view` | anyone; registry is the real caller | none; returns the spec consumed at CauldronRegistry.sol:849 |
| 394 | `hasProposals() external view` | anyone | none; false blocks `relaunch` at CauldronRegistry.sol:787 |
| 399 | `markConsumed(uint256) external` | registry only (CauldronGovernor.sol:400) | none; retires the launched proposal |
| 436 | `getProposal(uint256) external view` | anyone | none |
| 446 | `_bestUnconsumed() private view` | internal (winner, hasProposals) | none |
| 478 | `_recomputeLeader() private view` | internal (markConsumed, _bestUnconsumed) | none |

### `TreasuryGovernor.sol`

| line | signature | authority | value effect |
|---|---|---|---|
| 5 | `IVotes721.getPastVotes(address,uint256) external view` | declaration only | none |
| 6 | `IVotes721.getVotes(address) external view` | declaration only | none |
| 15 | `IVotes721.getPastTotalSupply(uint256) external view` | declaration only | none; quorum denominator |
| 19 | `IRegistryQuotes.allowedQuote(address) external view` | declaration only | none |
| 24 | `IQuotePrice.usdPerRawUnit(address) external view` | declaration only | none |
| 266 | `conversionFor(uint16,uint16) external pure` | anyone | none; no storage access |
| 312 | `constructor(IVotes721,address,address,uint64,uint64,uint64,uint64,bool)` | deployer | none; fixes all four durations |
| 364 | `propose(address,uint16) external` | holder with >= 5 votes (TreasuryGovernor.sol:365) | none; names a destination + bps budget |
| 406 | `vote(uint256,bool) external` | one ballot per address, snapshot weight (TreasuryGovernor.sol:412) | none |
| 478 | `execute(uint256) external` | **anyone** (TreasuryGovernor.sol:478) | installs the envelope that authorises LP rotation (TreasuryGovernor.sol:501) |
| 516 | `cancel(uint256) external` | guardian (TreasuryGovernor.sol:517) | stands down a live envelope (TreasuryGovernor.sol:519) |
| 523 | `setGuardian(address) external` | guardian (TreasuryGovernor.sol:524) | none; rotates or renounces the role |
| 558 | `winner() public view` | anyone | none; selects which proposal may execute |
| 607 | `_executable(Proposal storage) private view` | internal (winner) | none |
| 626 | `_dead(Proposal storage) private view` | internal (vote) | none |
| 643 | `allowance() public view` | anyone; the rotation facet is the real caller | none; reports remaining rotation budget |
| 681 | `migrationMandateSpent() external view` | anyone; the rotation facet is the real caller | none; true lets a generation be redenominated |
| 697 | `consume(uint16,bool) external` | registry only (TreasuryGovernor.sol:698) | books spent bps (TreasuryGovernor.sol:708) and can close the envelope (TreasuryGovernor.sol:718) |
| 724 | `_passed(Proposal storage) private view` | internal (execute, winner, _executable, passing) | none |
| 739 | `_settled(uint256) private view` | internal, **no call site in the file** | none; unreachable |
| 745 | `passing(uint256) external view` | anyone | none |
| 782 | `_requirePriceable(address) internal view` | internal (propose, execute) | none |
| 791 | `setQuoteOracle(address) external` | guardian (TreasuryGovernor.sol:792) | none; controls whether non-native mandates can exist |

---

## Cluster extras — quorum and timing

### Every threshold, window, delay, snapshot and expiry

| quantity | value | kind | declared | enforced |
|---|---|---|---|---|
| `CauldronGovernor.VOTING_PERIOD` | 3 days | `constant` | CauldronGovernor.sol:61 | set at `votingEndsAt` (CauldronGovernor.sol:306); votes refused after it at CauldronGovernor.sol:337; eligibility requires it to have passed at CauldronGovernor.sol:449 and CauldronGovernor.sol:484 |
| `CauldronGovernor` proposal snapshot | current block | — | CauldronGovernor.sol:305 | ballots must be in a LATER block (CauldronGovernor.sol:343) and are weighed at it (CauldronGovernor.sol:344) |
| `CauldronGovernor` quorum | **none** | — | — | the leader is a plurality (CauldronGovernor.sol:485); a single vote of weight 1 can win |
| `MAX_NFT_SUPPLY` | 100_000 | `constant` | CauldronGovernor.sol:55 | CauldronGovernor.sol:262 |
| `MAX_NAME_BYTES` / `MAX_SYMBOL_BYTES` / `MAX_URI_BYTES` / `MAX_LINK_BYTES` | 64 / 16 / 256 / 128 | `constant` | CauldronGovernor.sol:97-100 | CauldronGovernor.sol:247-251 |
| `MAX_LEADER_SCAN` | 64 | `internal constant` | CauldronGovernor.sol:474 | CauldronGovernor.sol:480 |
| `CauldronGovernor` expiry of a proposal | **none** — a settled proposal stays winnable forever | — | — | `_recomputeLeader` only skips consumed and still-open proposals (CauldronGovernor.sol:483-484) |
| `TreasuryGovernor.PROPOSAL_THRESHOLD` | 5 votes | `constant` | TreasuryGovernor.sol:280 | TreasuryGovernor.sol:365 |
| `TreasuryGovernor.QUORUM_BPS` | 1000 (10% of snapshot supply) | `constant` | TreasuryGovernor.sol:277 | TreasuryGovernor.sol:735 |
| majority rule | strict `forVotes > againstVotes` | — | — | TreasuryGovernor.sol:725 — a tie FAILS |
| `VOTING_PERIOD` | ctor arg; default 3 days (`MAINNET_VOTING`, TreasuryGovernor.sol:290), floor 1 day (`MIN_VOTING`, TreasuryGovernor.sol:298) unless `testnet` | `immutable` | TreasuryGovernor.sol:223 | `votingEndsAt` (TreasuryGovernor.sol:393); ballots refused at/after it (TreasuryGovernor.sol:409); execution refused before it (TreasuryGovernor.sol:481) |
| `EXECUTION_WINDOW` | ctor arg; default 3 days (TreasuryGovernor.sol:293), floor 1 day (TreasuryGovernor.sol:300) | `immutable` | TreasuryGovernor.sol:229 | staleness at TreasuryGovernor.sol:491, TreasuryGovernor.sol:597, TreasuryGovernor.sol:610, TreasuryGovernor.sol:628 and in the hint-retirement test at TreasuryGovernor.sol:444 |
| `COOLDOWN` | ctor arg; default 7 days (TreasuryGovernor.sol:292), floor 1 day (TreasuryGovernor.sol:299) | `immutable` | TreasuryGovernor.sol:225 | TreasuryGovernor.sol:387 — blocks PROPOSING, measured from `lastEnvelopeAt` (TreasuryGovernor.sol:509) |
| `ENVELOPE_LIFETIME` | ctor arg; default 30 days (TreasuryGovernor.sol:291); no floor of its own, but must be >= `EXECUTION_WINDOW` in both modes (TreasuryGovernor.sol:341) | `immutable` | TreasuryGovernor.sol:224 | `expiry` (TreasuryGovernor.sol:505), read at TreasuryGovernor.sol:386 and TreasuryGovernor.sol:645 |
| `MAX_ENVELOPE_BPS` | 30_000 | `constant` | TreasuryGovernor.sol:257 | TreasuryGovernor.sol:366 |
| `BPS_ONE` | 10_000 | `internal constant` | TreasuryGovernor.sol:688 | TreasuryGovernor.sol:683 |
| `TreasuryGovernor` proposal snapshot | current block | — | TreasuryGovernor.sol:396 | ballot weight (TreasuryGovernor.sol:412) and quorum denominator (TreasuryGovernor.sol:735) |
| testnet waiver | `bool testnet` ctor arg | — | TreasuryGovernor.sol:320 | skips all three floors at TreasuryGovernor.sol:333 |

Boundary behaviour (DERIVED from the comparison operators):
* `CauldronGovernor`: at exactly `votingEndsAt`, voting is still OPEN (`>` at CauldronGovernor.sol:337) and the proposal is NOT yet winnable (`>` at CauldronGovernor.sol:449, `<=` at CauldronGovernor.sol:484) — no overlap.
* `TreasuryGovernor`: at exactly `votingEndsAt`, voting is CLOSED (`>=` at TreasuryGovernor.sol:409) and execution is OPEN (`<` at TreasuryGovernor.sol:481) — no gap.
* At exactly `envelope.expiry`, `allowance` reports nothing (`>=` at TreasuryGovernor.sol:645) and `propose` is unblocked (`<` at TreasuryGovernor.sol:386) — consistent.

### Who can propose, vote, execute, cancel

| action | CauldronGovernor | TreasuryGovernor |
|---|---|---|
| propose | any address with `getVotes > 0` (CauldronGovernor.sol:240) | any address with `getVotes >= 5` (TreasuryGovernor.sol:365); also needs no live envelope (TreasuryGovernor.sol:386) and no active cooldown (TreasuryGovernor.sol:387) |
| vote | any address with non-zero snapshot weight, once per proposal (CauldronGovernor.sol:338, CauldronGovernor.sol:344); FOR only — there is no against option | any address with non-zero snapshot weight, once per proposal (TreasuryGovernor.sol:410, TreasuryGovernor.sol:412); FOR or AGAINST (TreasuryGovernor.sol:416) |
| execute / consume | only the registry, via `markConsumed` (CauldronGovernor.sol:400) — the registry both selects and retires | **anyone**, via `execute` (TreasuryGovernor.sol:478); spending the envelope afterwards is registry-only (TreasuryGovernor.sol:698) |
| cancel | **nobody** — there is no cancel, and no expiry either | guardian only (TreasuryGovernor.sol:517), on any id, at any time |

### What execution is allowed to call, and with what value

`TreasuryGovernor.execute` (TreasuryGovernor.sol:478) does not call any target. It is not a generic proposal executor: a proposal carries exactly two decision fields, `quote` (TreasuryGovernor.sol:391) and `maxTotalBps` (TreasuryGovernor.sol:392), there is no `target`, `calldata` or `value` anywhere in the struct, and execution's only effect is the local struct write at `envelope` (TreasuryGovernor.sol:501). No native value can be attached — `execute` is not `payable`. The envelope is then spent by a different contract entirely, gated on the immutable `registry` (TreasuryGovernor.sol:698).

`CauldronGovernor` likewise executes nothing: it stores a spec and the registry pulls it at `winner` (CauldronRegistry.sol:849).

The consequence: a captured vote cannot make either governor call an arbitrary address. The reachable damage is bounded by the allowlist the vote cannot widen (`allowedQuote`, TreasuryGovernor.sol:369 and TreasuryGovernor.sol:494, written only at CauldronRegistry.sol:290) and by the proposal-field validation at CauldronGovernor.sol:241-288.

### How a proposal is selected among several

**`CauldronGovernor`** — highest `votes` among proposals that exist, are unconsumed, and whose window has CLOSED:
1. Fast path: the cached `_leaderId` is returned if it still exists, is unconsumed, has votes, and `block.timestamp > votingEndsAt` (CauldronGovernor.sol:448-450).
2. Otherwise the positional scan `_recomputeLeader` (CauldronGovernor.sol:478) takes the strict maximum over the newest 64 ids (CauldronGovernor.sol:485) — ties keep the LOWER id, because the walk is ascending and the comparison is strict.
3. The hint is maintained incrementally in `vote` (CauldronGovernor.sol:353-364), with a single runner-up slot carried at `_runnerId` (CauldronGovernor.sol:357) so that `markConsumed` can promote (CauldronGovernor.sol:414) rather than rescan.
4. `markConsumed` clears both hint slots after promoting (CauldronGovernor.sol:421-422) and also clears the runner-up when the runner-up itself is consumed (CauldronGovernor.sol:426-427).

**`TreasuryGovernor`** — highest `forVotes` among proposals that are executable RIGHT NOW:
1. Fast path: `_leadId` is returned if `_executable` accepts it (TreasuryGovernor.sol:563), which requires closed voting, not executed, not cancelled, inside the execution window, and `_passed` (TreasuryGovernor.sol:607-611).
2. Otherwise the descending time-bounded scan (TreasuryGovernor.sol:593-602) takes the strict maximum on `forVotes` (TreasuryGovernor.sol:601); because the walk is descending and the comparison is strict, a tie keeps the LOWEST id.
3. `execute` refuses anything that is not the selected id (TreasuryGovernor.sol:488), so concurrent passing proposals resolve to one winner rather than a race.
4. The hint's five maintenance branches live in `vote` (TreasuryGovernor.sol:422-467); only TreasuryGovernor.sol:461 can lower `_leadVotes`, and only after the incumbent is `_dead` (TreasuryGovernor.sol:443) and a full `VOTING_PERIOD + EXECUTION_WINDOW` has passed since the last untracked live vote (TreasuryGovernor.sol:444).
