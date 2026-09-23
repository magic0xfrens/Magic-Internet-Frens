# Function graph — `governance`

Current source-derived semantic map: **48 nodes** across **2 files**. The JSON file is canonical; this document renders every semantic field for review.

## Source files

| file | lines |
|---|---:|
| `cauldron/CauldronGovernor.sol` | 860 |
| `cauldron/TreasuryGovernor.sol` | 1067 |


## `IRegistryQuotes (declared in CauldronGovernor.sol)`

### `allowedQuote/function` — CauldronGovernor.sol:25

- Signature: `function allowedQuote(address quote) external view returns (bool)`
- Authority: anyone (declaration only, no body in this file; the selector is dispatched by propose through a low-level staticcall on the owner-set registry address)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only: `allowedQuote` (CauldronGovernor.sol:25) has no body here. Its selector is encoded by `abi.encodeWithSelector` (CauldronGovernor.sol:394) and dispatched by `staticcall` (CauldronGovernor.sol:388) inside propose, where a failed call, a short return or a false decode all revert `QuoteNotAllowed` (CauldronGovernor.sol:601). The callee address is the storage slot `registry` (CauldronGovernor.sol:23), so the code actually reached is the registry's public allowlist mapping `allowedQuote` (CauldronRegistry.sol:327), which is written only by the owner-gated `setAllowedQuote` (CauldronRegistry.sol:314) and pre-seeded true for native ether at `allowedQuote` (CauldronRegistry.sol:181).
- Edges: none
- Observations: none


## `IRegistryHook (declared in CauldronGovernor.sol)`

### `hook/function` — CauldronGovernor.sol:32

- Signature: `function hook() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `hook` is declared at CauldronGovernor.sol:32; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `IHookCurve (declared in CauldronGovernor.sol)`

### `curvePolicy/function` — CauldronGovernor.sol:35

- Signature: `function curvePolicy() external view returns (address)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `curvePolicy` is declared at CauldronGovernor.sol:35; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `ICurveCalibration (declared in CauldronGovernor.sol)`

### `supply/function` — CauldronGovernor.sol:38

- Signature: `function supply() external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `supply` is declared at CauldronGovernor.sol:38; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `IHookCurveBase (declared in CauldronGovernor.sol)`

### `volumePerNFT/function` — CauldronGovernor.sol:43

- Signature: `function volumePerNFT() external view returns (uint256)`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `volumePerNFT` is declared at CauldronGovernor.sol:43; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `CauldronGovernor`

### `renounceOwnership/function` — CauldronGovernor.sol:315

- Signature: `function renounceOwnership() public view override onlyOwner`
- Authority: owner (and it always reverts)
- Gate evidence: `function renounceOwnership() public view override onlyOwner { (CauldronGovernor.sol:315)`
- Reads: none
- Writes: none
- Value: none - it reverts (DERIVED)
- Reachability: Override that disables OpenZeppelin's live `renounceOwnership` by reverting `OwnershipCannotBeRenounced` (CauldronGovernor.sol:313). The owner is the only caller of `setRegistry` (CauldronGovernor.sol:304), so renouncing would permanently pin the registry wiring with no redeploy that preserves the stockpiled mandates. `transferOwnership` is untouched, so handing the seat away remains available (DERIVED).
- Edges: none
- Observations: none

### `constructor/constructor` — CauldronGovernor.sol:365

- Signature: `constructor(address _mifrens, uint256 _votingPeriod) Ownable(msg.sender)`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `constructor` is declared at CauldronGovernor.sol:365; deployer.
- Edges: none
- Observations: none

### `setRegistry/function` — CauldronGovernor.sol:375

- Signature: `function setRegistry(address _registry) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronGovernor.sol:375)`
- Reads: `registry (line 374)`
- Writes: `registry (line 374)`
- Value: NONE
- Reachability: Owner-only and one-shot: a non-zero current value reverts `RegistryAlreadySet` (CauldronGovernor.sol:376) and a zero argument reverts `EmptyField` (CauldronGovernor.sol:377), so the consumer address can never be rotated or cleared once written to `registry` (CauldronGovernor.sol:374). Whatever lands here becomes the sole caller accepted by `NotRegistry` (CauldronGovernor.sol:764) and the target of the allowlist `staticcall` (CauldronGovernor.sol:388) in propose. Ownership itself is Ownable's: it can be transferred or renounced, and renouncing before this call leaves `markConsumed` (CauldronGovernor.sol:374) permanently unreachable (DERIVED).
- Edges: none
- Observations: comment `markConsumed` (CauldronGovernor.sol:374) says the only privileged call is markConsumed, restricted to the registry; code `onlyOwner` (CauldronGovernor.sol:375) adds an owner-gated setter, and `Ownable` (CauldronGovernor.sol:303) adds transferOwnership and renounceOwnership to the external surface.

### `_calibratedSupply/function` — CauldronGovernor.sol:391

- Signature: `function _calibratedSupply() private view returns (uint256)`
- Authority: internal (callers are paths that reference this function)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `_calibratedSupply` is declared at CauldronGovernor.sol:391; internal (callers are paths that reference this function).
- Edges: `CauldronGovernor._liveHook (CauldronGovernor.sol:392), TRUSTED, in-cluster`; `IHookCurve.curvePolicy (CauldronGovernor.sol:394), UNTRUSTED, out-of-cluster`; `ICurveCalibration.supply (CauldronGovernor.sol:398), UNTRUSTED, out-of-cluster`
- Observations: none

### `_liveHook/function` — CauldronGovernor.sol:405

- Signature: `function _liveHook() private view returns (address)`
- Authority: internal (callers are paths that reference this function)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `_liveHook` is declared at CauldronGovernor.sol:405; internal (callers are paths that reference this function).
- Edges: `IRegistryHook.hook (CauldronGovernor.sol:408), UNTRUSTED, out-of-cluster`
- Observations: none

### `_liveCurveBase/function` — CauldronGovernor.sol:415

- Signature: `function _liveCurveBase() private view returns (uint256)`
- Authority: internal (callers are paths that reference this function)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `_liveCurveBase` is declared at CauldronGovernor.sol:415; internal (callers are paths that reference this function).
- Edges: `CauldronGovernor._liveHook (CauldronGovernor.sol:416), TRUSTED, in-cluster`; `IHookCurveBase.volumePerNFT (CauldronGovernor.sol:418), UNTRUSTED, out-of-cluster`
- Observations: none

### `propose/function` — CauldronGovernor.sol:443

- Signature: `function propose( string calldata name, string calldata symbol, MetadataMode mode, string calldata baseURI, address renderer, string calldata website, string calldata socials, string calldata logo, string calldata banner, uint256 nftSupply, uint256 volumePerNFT, address quote ) external returns (uint256 id)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Permissionless entry that forwards every field, including the requested quote asset for the new generation, to `_propose` (CauldronGovernor.sol:457), where all validation and the proposal bond live.
- Edges: `CauldronGovernor._propose (CauldronGovernor.sol:457), TRUSTED, in-cluster`
- Observations: none

### `propose/function` — CauldronGovernor.sol:472

- Signature: `function propose( string calldata name, string calldata symbol, MetadataMode mode, string calldata baseURI, address renderer, string calldata website, string calldata socials, uint256 nftSupply, uint256 volumePerNFT, address quote ) external returns (uint256 id)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `propose` is declared at CauldronGovernor.sol:472; anyone.
- Edges: `CauldronGovernor._propose (CauldronGovernor.sol:484), TRUSTED, in-cluster`
- Observations: none

### `_propose/function` — CauldronGovernor.sol:490

- Signature: `function _propose( string memory name, string memory symbol, MetadataMode mode, string memory baseURI, address renderer, string memory website, string memory socials, string memory logo, string memory banner, uint256 nftSupply, uint256 volumePerNFT, address quote ) internal returns (uint256 id)`
- Authority: internal (callers are paths that reference this function)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `_propose` is declared at CauldronGovernor.sol:490; internal (callers are paths that reference this function).
- Edges: `IVotes.getVotes (CauldronGovernor.sol:506), UNTRUSTED, out-of-cluster`; `IRegistryQuotes.allowedQuote (CauldronGovernor.sol:599), UNTRUSTED, out-of-cluster`; `CauldronGovernor._calibratedSupply (CauldronGovernor.sol:544), TRUSTED, in-cluster`; `CauldronGovernor._liveCurveBase (CauldronGovernor.sol:571), TRUSTED, in-cluster`
- Observations: none

### `displayName/function` — CauldronGovernor.sol:630

- Signature: `function displayName(uint256 proposalId) external view returns (string memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `_proposals (line 631)`; `_proposals[proposalId].exists (line 632)`; `_proposals[proposalId].name (line 629)`
- Writes: none
- Value: NONE
- Reachability: Unrestricted view. Reverts `UnknownProposal` (CauldronGovernor.sol:632) for an id that was never written, otherwise returns the stored name through the pure library helper `displayName` (CauldronGovernor.sol:630). No state, no value, no reachable side effect.
- Edges: `LaunchLib.displayName (CauldronGovernor.sol:630), TRUSTED, library`
- Observations: none

### `vote/function` — CauldronGovernor.sol:644

- Signature: `function vote(uint256 proposalId) external`
- Authority: anyone holding checkpointed MiFrens voting power at the proposal's snapshot
- Gate evidence: `if (weight == 0) revert NoVotingPower(); (CauldronGovernor.sol:659)`
- Reads: `_proposals (line 645)`; `hasVoted (line 650)`; `mifrens (line 659, immutable)`; `_leaderVotes (line 668)`; `_leaderId (line 671)`; `_runnerVotes (line 673)`
- Writes: `hasVoted (line 650)`; `_proposals.votes (line 656)`; `_runnerId (line 667)`; `_runnerVotes (line 673)`; `_leaderVotes (line 668)`; `_leaderId (line 671)`; `_runnerVotes (line 673)`; `_runnerId (line 667)`
- Value: none - it only records votes; no asset moves (DERIVED)
- Reachability: Permissionless per proposal, once per address: an unknown or already-consumed proposal is refused at `UnknownProposal` (CauldronGovernor.sol:646) and `AlreadyConsumed` (CauldronGovernor.sol:647), the window is checked before the double-vote test so a closed vote always reports as closed at `VotingClosed` (CauldronGovernor.sol:652), and repeat voting at `AlreadyVoted` (CauldronGovernor.sol:653). Weight is CHECKPOINTED power at the proposal's snapshot block at `getPastVotes` (CauldronGovernor.sol:659), with the snapshot required to be in the past at `SnapshotNotReady` (CauldronGovernor.sol:658), so moving MiFrens to a fresh wallet mints no new votes. The leader/runner-up hints are still maintained - ties keep the incumbent at `_leaderVotes` (CauldronGovernor.sol:668), and a leader gaining votes is not demoted into its own runner slot at `_leaderId` (CauldronGovernor.sol:671) - and the NEW effect is that every vote also enters the fixed 8-slot bench at `_benchRecord` (CauldronGovernor.sol:682), which is what the leader rescan now walks instead of a positional window over the proposal list.
- Edges: `IVotes.getPastVotes (CauldronGovernor.sol:659), TRUSTED, out-of-cluster`; `CauldronGovernor._benchRecord (CauldronGovernor.sol:682), TRUSTED, in-cluster`
- Observations: none

### `_benchRecord/function` — CauldronGovernor.sol:706

- Signature: `function _benchRecord(uint256 id, uint256 votes) private`
- Authority: internal (callers are paths that reference this function)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `_benchRecord` is declared at CauldronGovernor.sol:706; internal (callers are paths that reference this function).
- Edges: none
- Observations: none

### `winner/function` — CauldronGovernor.sol:739

- Signature: `function winner() external view returns (uint256 proposalId, BrewSpec memory spec)`
- Authority: anyone (the registry is the production caller)
- Gate evidence: `UNGATED`
- Reads: `_proposals (line 742)`; `_proposals[proposalId].name (line 744)`; `_proposals[proposalId].quote (line 751)`; `_proposals[proposalId].nftSupply (line 752)`; `_proposals[proposalId].volumePerNFT (line 753)`; `_proposals[proposalId].proposer (line 754)`
- Writes: none
- Value: NONE
- Reachability: Unrestricted view, but only meaningful to the registry: `relaunch` calls `winner` (CauldronRegistry.sol:900) to build the next brew and later retires it with `markConsumed` (CauldronRegistry.sol:1008). Selection is delegated to `_bestUnconsumed` (CauldronGovernor.sol:740), which returns the cached leader only once its voting window has closed; zero reverts `NoProposals` (CauldronGovernor.sol:741). The returned struct copies seven proposer-controlled strings and addresses into memory, which is the replay cost the byte caps in propose bound.
- Edges: `CauldronGovernor._bestUnconsumed (CauldronGovernor.sol:740), TRUSTED, in-cluster`
- Observations: none

### `hasProposals/function` — CauldronGovernor.sol:758

- Signature: `function hasProposals() external view returns (bool)`
- Authority: anyone (the registry is the production caller)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Unrestricted view wrapping the same selection as winner. `relaunch` gates the whole rebirth on it at `hasProposals` (CauldronRegistry.sol:838) and reverts `NoProposal` there when it is false, so a false answer stops the machine being reborn until a settled, unconsumed proposal exists. It costs a scan whenever the cached-leader fast path in `_bestUnconsumed` (CauldronGovernor.sol:759) misses.
- Edges: `CauldronGovernor._bestUnconsumed (CauldronGovernor.sol:759), TRUSTED, in-cluster`
- Observations: none

### `markConsumed/function` — CauldronGovernor.sol:763

- Signature: `function markConsumed(uint256 proposalId) external`
- Authority: registry
- Gate evidence: `if (msg.sender != registry) revert NotRegistry(); (CauldronGovernor.sol:763)`
- Reads: `registry (line 764)`; `_proposals (line 765)`; `_proposals[proposalId].exists (line 766)`; `_proposals[proposalId].consumed (line 767)`; `_leaderId (line 771)`; `_runnerId (line 775)`; `_runnerVotes (line 777)`
- Writes: `_proposals[proposalId].consumed (line 767)`; `_leaderId (line 771)`; `_leaderVotes (line 779)`; `_runnerId (line 775)`; `_runnerVotes (line 777)`
- Value: NONE
- Reachability: Reachable only from the address stored in `registry` (CauldronGovernor.sol:764), which in production is CauldronRegistry inside relaunch at `markConsumed` (CauldronRegistry.sol:1008); any other caller reverts `NotRegistry` (CauldronGovernor.sol:764). It re-checks existence `UnknownProposal` (CauldronGovernor.sol:766) and idempotence `AlreadyConsumed` (CauldronGovernor.sol:767), then sets `consumed` (CauldronGovernor.sol:767) one-way. Leader maintenance: consuming the leader promotes the carried runner-up when it is still live at `_runnerVotes` (CauldronGovernor.sol:777), else falls back to the bounded rescan `_recomputeLeader` (CauldronGovernor.sol:783); both slots are then cleared at `_runnerId` (CauldronGovernor.sol:775). Because this call sits inside relaunch, any revert downstream of it rolls the consumption back with the transaction (DERIVED).
- Edges: `CauldronGovernor._recomputeLeader (CauldronGovernor.sol:783), TRUSTED, in-cluster`
- Observations: none

### `getProposal/function` — CauldronGovernor.sol:800

- Signature: `function getProposal(uint256 id) external view returns (Proposal memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `_proposals (line 801)`; `_proposals[id].exists (line 802)`
- Writes: none
- Value: NONE
- Reachability: Unrestricted view. Copies the whole proposal, five strings included, into memory `_proposals` (CauldronGovernor.sol:801) and reverts `UnknownProposal` (CauldronGovernor.sol:802) for an id never written. No gate, no state change, no value.
- Edges: none
- Observations: none

### `_bestUnconsumed/function` — CauldronGovernor.sol:810

- Signature: `function _bestUnconsumed() private view returns (uint256)`
- Authority: internal (callers: winner, hasProposals)
- Gate evidence: `UNGATED`
- Reads: `_proposals (line 811)`; `_leaderId (line 811)`; `_proposals[_leaderId].exists (line 812)`; `_proposals[_leaderId].consumed (line 812)`; `_leaderVotes (line 812)`; `_proposals[_leaderId].votingEndsAt (line 813)`
- Writes: none
- Value: NONE
- Reachability: Private; reached from `winner` (CauldronGovernor.sol:340) and `hasProposals` (CauldronGovernor.sol:336), hence from the registry's relaunch path. The fast path returns the cached `_leaderId` (CauldronGovernor.sol:811) only when it exists, is unconsumed, has votes and its window has closed at `votingEndsAt` (CauldronGovernor.sol:813); a proposal still taking votes therefore cannot be launched. Any miss pays the bounded scan `_recomputeLeader` (CauldronGovernor.sol:816), and returning zero is what makes relaunch revert.
- Edges: `CauldronGovernor._recomputeLeader (CauldronGovernor.sol:816), TRUSTED, in-cluster`
- Observations: none

### `_recomputeLeader/function` — CauldronGovernor.sol:842

- Signature: `function _recomputeLeader() private view returns (uint256 bestId, uint256 bestVotes)`
- Authority: private view (caller: _bestUnconsumed)
- Gate evidence: `UNGATED`
- Reads: `BENCH_SLOTS (line 848, constant)`; `_bench (line 847)`; `_proposals (line 851)`
- Writes: none
- Value: none - a view (DERIVED)
- Reachability: The rescan behind `_recomputeLeader` (CauldronGovernor.sol:842), reached from `hasProposals` (CauldronGovernor.sol:336) and from `winner` (CauldronGovernor.sol:340) - i.e. on the relaunch path - whenever the cached leader is consumed, gone or still taking votes at `votingEndsAt` (CauldronGovernor.sol:853). It now iterates the fixed 8-slot bench at `_bench` (CauldronGovernor.sol:847) instead of a window over the most recent proposal ids, which is what removes the flood: ids were mintable by any single MiFren holder with no cooldown, so a voted, settled, unconsumed mandate could be pushed out of a positional window. Each candidate must still exist and be unconsumed at `consumed` (CauldronGovernor.sol:852) and must have CLOSED its voting window at `votingEndsAt` (CauldronGovernor.sol:853), and the comparison is strict at `bestVotes` (CauldronGovernor.sol:842) so ties keep the lower bench slot rather than the earlier proposal.
- Edges: none
- Observations: the doc block for `MAX_LEADER_SCAN` (CauldronGovernor.sol:841) still describes bounding a scan over the proposal list at 64; code no longer reads that constant here - the loop bound is `BENCH_SLOTS` (CauldronGovernor.sol:848) - so the constant is retained but unused by this function


## `IVotes721 (declared in TreasuryGovernor.sol)`

### `getPastVotes/function` — TreasuryGovernor.sol:5

- Signature: `function getPastVotes(address account, uint256 blockNumber) external view returns (uint256)`
- Authority: anyone (declaration only, no body; dispatched on the immutable mifrens address)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only: `getPastVotes` (TreasuryGovernor.sol:5) has no body here. It is called once, in vote at `getPastVotes` (TreasuryGovernor.sol:5), against the proposal's stored `snapshot` (TreasuryGovernor.sol:474), and a zero result reverts `NoVotingPower` (TreasuryGovernor.sol:475). The callee is the immutable set at `mifrens` (TreasuryGovernor.sol:373), so a deployment that wires a contract without this selector makes every vote revert (DERIVED).
- Edges: none
- Observations: none

### `getVotes/function` — TreasuryGovernor.sol:6

- Signature: `function getVotes(address account) external view returns (uint256)`
- Authority: anyone (declaration only, no body; dispatched on the immutable mifrens address)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only: `getVotes` (TreasuryGovernor.sol:6) has no body here. It is called once, as the proposal-threshold gate `getVotes` (TreasuryGovernor.sol:6), where a live balance below `PROPOSAL_THRESHOLD` (TreasuryGovernor.sol:416) reverts BelowProposalThreshold. Unlike the ballot weight it is read LIVE, not at a snapshot, so threshold power can be borrowed for the length of one transaction (DERIVED).
- Edges: none
- Observations: none

### `getPastTotalSupply/function` — TreasuryGovernor.sol:15

- Signature: `function getPastTotalSupply(uint256 timepoint) external view returns (uint256)`
- Authority: anyone (declaration only, no body; dispatched on the immutable mifrens address)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only: `getPastTotalSupply` (TreasuryGovernor.sol:15) has no body here. It is the quorum denominator, called once at `getPastTotalSupply` (TreasuryGovernor.sol:15) inside the pass test, measured at the proposal's `snapshot` (TreasuryGovernor.sol:1005) and scaled by `QUORUM_BPS` (TreasuryGovernor.sol:931). Every path that decides an outcome runs through it: `_passed` (TreasuryGovernor.sol:596) in execute, `_passed` (TreasuryGovernor.sol:767) inside the bench scan's executability test, `_passed` (TreasuryGovernor.sol:767) and the public `passing` (TreasuryGovernor.sol:1015), so a reverting or missing implementation blocks execution entirely.
- Edges: none
- Observations: none


## `IRegistryQuotes (declared in TreasuryGovernor.sol)`

### `allowedQuote/function` — TreasuryGovernor.sol:19

- Signature: `function allowedQuote(address quote) external view returns (bool)`
- Authority: anyone (declaration only, no body; dispatched on the immutable registry address)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only: `allowedQuote` (TreasuryGovernor.sol:19) has no body here. It is called twice on the immutable `registry` (TreasuryGovernor.sol:374): once when a rotation target is named at `allowedQuote` (TreasuryGovernor.sol:19) and again when the envelope is installed at `allowedQuote` (TreasuryGovernor.sol:19), both reverting QuoteNotAllowed. The implementation is the registry's public mapping `allowedQuote` (CauldronRegistry.sol:327), writable only through the owner-gated `setAllowedQuote` (CauldronRegistry.sol:314) — so the allowlist is outside the reach of any vote here.
- Edges: none
- Observations: none


## `IQuotePrice (declared in TreasuryGovernor.sol)`

### `usdPerRawUnit/function` — TreasuryGovernor.sol:24

- Signature: `function usdPerRawUnit(address quote) external view returns (uint256)`
- Authority: anyone (declaration only, no body; dispatched on the guardian-set quoteOracle address)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only: `usdPerRawUnit` (TreasuryGovernor.sol:24) has no body here. It is called once, at `usdPerRawUnit` (TreasuryGovernor.sol:24), and only when the target is non-native and an oracle is wired; a zero price reverts `QuoteNotPriceable` (TreasuryGovernor.sol:1056). The address is the mutable `quoteOracle` (TreasuryGovernor.sol:1054), which the guardian may repoint at any contract via `setQuoteOracle` (TreasuryGovernor.sol:1061), so this call is to an address an admin controls (DERIVED).
- Edges: none
- Observations: none


## `TreasuryGovernor`

### `conversionFor/function` — TreasuryGovernor.sol:317

- Signature: `function conversionFor(uint16 spendBps, uint16 sliceBps) external pure returns (uint16)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Unrestricted pure helper with no storage access and no caller inside this file; it exists for user interfaces that must translate a spend budget into the share of the position it converts. Both arguments are caller-supplied, so the loop trip count `n` (TreasuryGovernor.sol:319) is spendBps divided by sliceBps and is bounded only by the uint16 range — up to 65535 iterations when `sliceBps` (TreasuryGovernor.sol:319) is 1, which is a caller-paid cost in a view call (DERIVED). Each step multiplies before dividing at `rem` (TreasuryGovernor.sol:323), truncating toward zero, so the remaining share rounds DOWN and the reported conversion at `rem` (TreasuryGovernor.sol:325) rounds UP (DERIVED).
- Edges: none
- Observations: none

### `constructor/constructor` — TreasuryGovernor.sol:363

- Signature: `constructor( IVotes721 _mifrens, address _registry, address _guardian, uint64 votingPeriod, uint64 envelopeLifetime, uint64 cooldown, uint64 executionWindow, bool testnet )`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: `MAINNET_VOTING (line 379, constant)`; `MAINNET_LIFETIME (line 380, constant)`; `MAINNET_COOLDOWN (line 381, constant)`; `MAINNET_EXEC_WINDOW (line 382, constant)`; `MIN_VOTING (line 385, constant)`; `MIN_COOLDOWN (line 386, constant)`; `MIN_EXEC_WINDOW (line 387, constant)`
- Writes: `mifrens (line 373, immutable)`; `registry (line 374, immutable)`; `guardian (line 375)`; `VOTING_PERIOD (line 394, immutable)`; `ENVELOPE_LIFETIME (line 395, immutable)`; `COOLDOWN (line 396, immutable)`; `EXECUTION_WINDOW (line 397, immutable)`
- Value: NONE
- Reachability: Runs once at deployment and is the only writer of every timing parameter. Zero arguments fall back to the mainnet defaults at `MAINNET_VOTING` (TreasuryGovernor.sol:379) and its three siblings; unless `testnet` (TreasuryGovernor.sol:384) is passed, the one-day floors at `MIN_VOTING` (TreasuryGovernor.sol:385), `MIN_COOLDOWN` (TreasuryGovernor.sol:386) and `MIN_EXEC_WINDOW` (TreasuryGovernor.sol:387) apply, and in BOTH modes a lifetime shorter than the execution window reverts `BadTiming` (TreasuryGovernor.sol:392). No floor exists on `ENVELOPE_LIFETIME` (TreasuryGovernor.sol:395) itself beyond that coherence test, and neither `mifrens` (TreasuryGovernor.sol:373) nor `registry` (TreasuryGovernor.sol:374) nor `guardian` (TreasuryGovernor.sol:375) is checked for zero or for code, so a mis-wired deployment is only detectable later: a zero guardian dead-ends `cancel` (TreasuryGovernor.sol:619), `setGuardian` (TreasuryGovernor.sol:675) and `setQuoteOracle` (TreasuryGovernor.sol:1061) forever (DERIVED).
- Edges: none
- Observations: none

### `propose/function` — TreasuryGovernor.sol:415

- Signature: `function propose(address quote, uint16 maxTotalBps) external returns (uint256 id)`
- Authority: caller satisfying the in-body msg.sender check
- Gate evidence: `if (mifrens.getVotes(msg.sender) < PROPOSAL_THRESHOLD) revert BelowProposalThreshold(); (TreasuryGovernor.sol:415)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `propose` is declared at TreasuryGovernor.sol:415; caller satisfying the in-body msg.sender check.
- Edges: `IVotes721.getVotes (TreasuryGovernor.sol:416), UNTRUSTED, out-of-cluster`; `IRegistryQuotes.allowedQuote (TreasuryGovernor.sol:420), UNTRUSTED, out-of-cluster`; `TreasuryGovernor._requirePriceable (TreasuryGovernor.sol:421), TRUSTED, in-cluster`; `TreasuryGovernor.stalled (TreasuryGovernor.sol:440), TRUSTED, in-cluster`
- Observations: none

### `vote/function` — TreasuryGovernor.sol:468

- Signature: `function vote(uint256 id, bool support) external`
- Authority: anyone holding checkpointed MiFrens power at the proposal's snapshot
- Gate evidence: `if (w == 0) revert NoVotingPower(); (TreasuryGovernor.sol:474)`
- Reads: `proposals (line 469)`; `hasVoted (line 472)`; `mifrens (line 474, immutable)`; `_leadId (line 481)`; `_leadVotes (line 495)`; `_openVotedAt (line 504)`; `VOTING_PERIOD (line 509, immutable)`; `EXECUTION_WINDOW (line 509, immutable)`
- Writes: `hasVoted (line 472)`; `proposals.forVotes (line 478)`; `_leadVotes (line 490)`; `_leadId (line 494)`; `_openVotedAt (line 504)`; `_leadId (line 505)`; `_leadVotes (line 502)`; `_leadId (line 525)`; `_leadVotes (line 526)`; `_openVotedAt (line 531)`
- Value: none - it only records votes (DERIVED)
- Reachability: Permissionless once per address per proposal: unknown ids are refused at `UnknownProposal` (TreasuryGovernor.sol:470), a closed window at `VotingClosed` (TreasuryGovernor.sol:471), a repeat at `AlreadyVoted` (TreasuryGovernor.sol:472), and zero checkpointed power at `NoVotingPower` (TreasuryGovernor.sol:475). Weight comes from the proposal's own snapshot at `getPastVotes` (TreasuryGovernor.sol:474). The `_leadId` hint is maintained here, where the counts move: the incumbent growing at `_leadVotes` (TreasuryGovernor.sol:490), the first-ever support at `_leadId` (TreasuryGovernor.sol:494), an overtake, including an exact tie won by the LOWER proposal id so the hint agrees with `winner` (`lead` TreasuryGovernor.sol:496), that dates the displaced rival at `_openVotedAt` (TreasuryGovernor.sol:504), the ONLY branch that lowers the bar - retiring a hint that is provably dead and older than a full vote-plus-execution window at `_dead` (TreasuryGovernor.sol:508) - and otherwise just re-dating at `_openVotedAt` (TreasuryGovernor.sol:531). NEW: a FOR-vote also enters the fixed 8-slot bench at `_benchRecord` (TreasuryGovernor.sol:534), which is what `winner` now falls back to instead of any scan over the proposal list. AGAINST-votes are counted at `againstVotes` (TreasuryGovernor.sol:478) but touch neither the hint nor the bench (DERIVED).
- Edges: `IVotes721.getPastVotes (TreasuryGovernor.sol:474), TRUSTED, out-of-cluster`; `TreasuryGovernor._dead (TreasuryGovernor.sol:508), TRUSTED, in-cluster`; `TreasuryGovernor._benchRecord (TreasuryGovernor.sol:534), TRUSTED, in-cluster`
- Observations: none

### `_benchRecord/function` — TreasuryGovernor.sol:557

- Signature: `function _benchRecord(uint256 id, uint256 votes) private`
- Authority: internal (callers are paths that reference this function)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `_benchRecord` is declared at TreasuryGovernor.sol:557; internal (callers are paths that reference this function).
- Edges: `TreasuryGovernor._dead (TreasuryGovernor.sol:570), TRUSTED, in-cluster`; `TreasuryGovernor._executable (TreasuryGovernor.sol:573), TRUSTED, in-cluster`
- Observations: none

### `execute/function` — TreasuryGovernor.sol:591

- Signature: `function execute(uint256 id) external`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `proposals (line 592)`; `envelope (line 628)`; `lastEnvelopeAt (line 629)`; `COOLDOWN (line 629, constant)`; `registry (line 632, immutable)`
- Writes: `proposals.executed (line 638)`; `activeProposal (line 641)`; `envelope (line 642)`; `lastEnvelopeAt (line 650)`
- Value: NONE
- Reachability: Permissionless once voting has closed: the proposal must exist, be neither executed nor cancelled (`AlreadyExecuted` TreasuryGovernor.sol:595), have passed (`_passed` TreasuryGovernor.sol:596), be the current `winner` (TreasuryGovernor.sol:601) and still be inside its execution window (`EXECUTION_WINDOW` TreasuryGovernor.sol:604). A live, unexpired, non-stalled envelope blocks it (`ProposalActive` TreasuryGovernor.sol:628), as does the cooldown since the last one (`CooldownActive` TreasuryGovernor.sol:629); the quote must still be allowlisted on the registry and priceable (`_requirePriceable` TreasuryGovernor.sol:636). It then marks the proposal executed, records which proposal owns the envelope (`activeProposal` TreasuryGovernor.sol:641) and installs a fresh envelope with zero spent.
- Edges: `IRegistryQuotes.allowedQuote (TreasuryGovernor.sol:632), UNTRUSTED, out-of-cluster`; `TreasuryGovernor._passed (TreasuryGovernor.sol:596), TRUSTED, in-cluster`; `TreasuryGovernor.winner (TreasuryGovernor.sol:601), TRUSTED, in-cluster`; `TreasuryGovernor.stalled (TreasuryGovernor.sol:628), TRUSTED, in-cluster`; `TreasuryGovernor._requirePriceable (TreasuryGovernor.sol:636), TRUSTED, in-cluster`
- Observations: none

### `cancel/function` — TreasuryGovernor.sol:657

- Signature: `function cancel(uint256 id) external`
- Authority: guardian
- Gate evidence: `if (msg.sender != guardian) revert NotGuardian(); (TreasuryGovernor.sol:657)`
- Reads: `guardian (line 658)`; `envelope (line 663)`; `activeProposal (line 663)`
- Writes: `proposals (line 659)`; `envelope (line 663)`
- Value: NONE
- Reachability: Only the `guardian` (TreasuryGovernor.sol:658) reaches this; everyone else reverts NotGuardian. It accepts any id and writes `cancelled` (TreasuryGovernor.sol:659) unconditionally. The live envelope is stood down only when the cancelled id is the proposal that installed it (`activeProposal` TreasuryGovernor.sol:663), so cancelling an old executed proposal no longer kills a newer envelope, and `lastEnvelopeAt` is not rewound, so the cooldown still runs. The guardian can stop but cannot start or redirect a rotation: no path here writes the envelope's quote or budget.
- Edges: none
- Observations: none

### `setGuardian/function` — TreasuryGovernor.sol:675

- Signature: `function setGuardian(address g) external`
- Authority: guardian only
- Gate evidence: `if (msg.sender != guardian) revert NotGuardian(); (TreasuryGovernor.sol:675)`
- Reads: `guardian (line 676)`
- Writes: `guardian (line 676)`
- Value: none (DERIVED)
- Reachability: Guardian-only hand-off of the guardian seat. Zero is now REFUSED at `BadParam` (TreasuryGovernor.sol:677): the guardian is the sole caller of `cancel` (TreasuryGovernor.sol:619) and of the oracle setter, and this setter is itself guardian-gated at `guardian` (TreasuryGovernor.sol:676), so burning the seat would dead-end the emergency stop permanently with no way to appoint a replacement. There is no two-step acceptance, so a typo'd non-zero address still loses the seat irrecoverably (DERIVED).
- Edges: none
- Observations: comment at `cancel` (TreasuryGovernor.sol:621) cites cancel at ':518'; code has it at `cancel` (TreasuryGovernor.sol:619) (DERIVED)

### `winner/function` — TreasuryGovernor.sol:711

- Signature: `function winner() public view returns (uint256 best)`
- Authority: anyone (public view)
- Gate evidence: `UNGATED`
- Reads: `_leadId (line 715)`; `proposals (line 716)`; `BENCH_SLOTS (line 752, constant)`; `_bench (line 751)`
- Writes: none
- Value: none - a view (DERIVED)
- Reachability: Public view that `execute` gates on, so it sits on the only path that installs an envelope. Fast path: the `_leadId` (TreasuryGovernor.sol:715) hint is returned only after the same executability test the fallback applies (`_executable` TreasuryGovernor.sol:716), so a stale or beaten hint costs a scan rather than electing the wrong proposal. The fallback is the fixed 8-slot bench (`_bench` TreasuryGovernor.sol:753), not a loop over a list anyone may grow. Candidates must be executable (`_executable` TreasuryGovernor.sol:756); more FOR votes win and an exact tie goes to the lower proposal id (`best` TreasuryGovernor.sol:757), the same rule `vote` applies to the hint, so the result does not depend on bench slot order. Cost is O(1) in the proposal count (DERIVED).
- Edges: `TreasuryGovernor._executable (TreasuryGovernor.sol:716), TRUSTED, in-cluster`; `TreasuryGovernor._executable (TreasuryGovernor.sol:756), TRUSTED, in-cluster`
- Observations: the doc block above still describes a time-bounded BACKWARDS walk over proposal ids stopping at the first too-old proposal, at `votingEndsAt` (TreasuryGovernor.sol:736); code walks only `_bench` (TreasuryGovernor.sol:751) and never touches `proposalCount`, so that description no longer matches the loop it precedes

### `_executable/function` — TreasuryGovernor.sol:763

- Signature: `function _executable(Proposal storage p) private view returns (bool)`
- Authority: internal (callers: winner)
- Gate evidence: `UNGATED`
- Reads: `proposals[hint].votingEndsAt (line 764)`; `proposals[hint].executed (line 761)`; `proposals[hint].cancelled (line 764)`; `EXECUTION_WINDOW (line 766, immutable)`
- Writes: none
- Value: NONE
- Reachability: Private; the single call site is the fast path in `_executable` (TreasuryGovernor.sol:763). It is the one definition of executability: unknown, executed or cancelled proposals fail at `votingEndsAt` (TreasuryGovernor.sol:764), a still-open vote fails at `votingEndsAt` (TreasuryGovernor.sol:764), a stale one fails at `EXECUTION_WINDOW` (TreasuryGovernor.sol:766), and the remainder must clear `_passed` (TreasuryGovernor.sol:767). Because it is a superset of the scan's own tests, trusting the hint can only elect a proposal the scan would also accept, though not necessarily the highest-voted one unless the hint is maintained as a maximum (DERIVED).
- Edges: `TreasuryGovernor._passed (TreasuryGovernor.sol:767), TRUSTED, in-cluster`
- Observations: none

### `_dead/function` — TreasuryGovernor.sol:782

- Signature: `function _dead(Proposal storage p) private view returns (bool)`
- Authority: internal (callers: vote)
- Gate evidence: `UNGATED`
- Reads: `proposals[lead].executed (line 781)`; `proposals[lead].cancelled (line 783)`; `proposals[lead].votingEndsAt (line 780)`; `EXECUTION_WINDOW (line 784, immutable)`
- Writes: none
- Value: NONE
- Reachability: Private; reached only from the hint-retirement branch at `_dead` (TreasuryGovernor.sol:782). It is monotone: `executed` (TreasuryGovernor.sol:781) and `cancelled` (TreasuryGovernor.sol:783) are one-way flags and the deadline at `EXECUTION_WINDOW` (TreasuryGovernor.sol:784) only recedes, so a true answer can never become false. An id that was never proposed reads dead because `votingEndsAt` (TreasuryGovernor.sol:780) is zero (DERIVED).
- Edges: none
- Observations: none

### `allowance/function` — TreasuryGovernor.sol:799

- Signature: `function allowance() public view returns (address quote, uint16 remainingBps)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `allowance` is declared at TreasuryGovernor.sol:799; anyone.
- Edges: none
- Observations: none

### `migrationMandateSpent/function` — TreasuryGovernor.sol:870

- Signature: `function migrationMandateSpent() external view returns (bool)`
- Authority: anyone (the registry rotation path is the production caller)
- Gate evidence: `UNGATED`
- Reads: `envelope (line 868)`; `envelope.maxTotalBps (line 872)`; `envelope.movedPrimaryBps (line 872)`; `BPS_ONE (line 872, constant)`
- Writes: none
- Value: NONE
- Reachability: Unrestricted view with one production consumer: the rotation facet reads it (`migrationMandateSpent` RedemptionExt.sol:658), and only when the slice came from the primary leg. It returns true only when the guild budgeted at least one whole position `BPS_ONE` (TreasuryGovernor.sol:872) AND that budget has been spent out of the generation's own position `movedPrimaryBps` (TreasuryGovernor.sol:872), so secondary-leg slices counted in `movedBps` (TreasuryGovernor.sol:862) can never declare a migration complete. Because slices take a share of CURRENT liquidity, a spent budget does not mean a drained position (DERIVED).
- Edges: none
- Observations: none

### `stalled/function` — TreasuryGovernor.sol:935

- Signature: `function stalled() public view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `stalled` is declared at TreasuryGovernor.sol:935; anyone.
- Edges: none
- Observations: none

### `consume/function` — TreasuryGovernor.sol:944

- Signature: `function consume(uint16 bps, bool fromPrimary) external`
- Authority: caller satisfying the in-body msg.sender check
- Gate evidence: `if (msg.sender != registry) revert NotGuardian(); (TreasuryGovernor.sol:944)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `consume` is declared at TreasuryGovernor.sol:944; caller satisfying the in-body msg.sender check.
- Edges: `TreasuryGovernor.allowance (TreasuryGovernor.sol:947), TRUSTED, in-cluster`
- Observations: none

### `_passed/function` — TreasuryGovernor.sol:994

- Signature: `function _passed(Proposal storage p) private view returns (bool)`
- Authority: internal (callers: execute, winner, _executable, passing)
- Gate evidence: `UNGATED`
- Reads: `proposals[id].forVotes (line 995)`; `proposals[id].againstVotes (line 995)`; `mifrens (line 1005, immutable)`; `proposals[id].snapshot (line 1005)`; `QUORUM_BPS (line 1005, constant)`
- Writes: none
- Value: NONE
- Reachability: Private, reached from `_passed` (TreasuryGovernor.sol:994) in execute, `_passed` (TreasuryGovernor.sol:994) inside the bench scan's executability test, `_passed` (TreasuryGovernor.sol:994) in the executability test and `_passed` (TreasuryGovernor.sol:994) in the public view. Two conditions: a strict majority at `forVotes` (TreasuryGovernor.sol:995), so a tie fails, and a quorum of `QUORUM_BPS` (TreasuryGovernor.sol:1005) — ten percent — of the supply measured at the proposal's own `snapshot` (TreasuryGovernor.sol:1005), not live, so minting or burning after the vote opens cannot move the bar. The comparison at `forVotes` (TreasuryGovernor.sol:995) is inclusive, and the division at `need` (TreasuryGovernor.sol:1005) truncates, so the effective quorum rounds DOWN (DERIVED).
- Edges: `IVotes721.getPastTotalSupply (TreasuryGovernor.sol:1005), TRUSTED, out-of-cluster`
- Observations: comment `vote` (TreasuryGovernor.sol:996) says quorum is read at the same timepoint the vote weighs ballots and points at line 384; code weighs ballots at `getPastVotes` (TreasuryGovernor.sol:474) and reads the denominator at `getPastTotalSupply` (TreasuryGovernor.sol:1003).

### `_settled/function` — TreasuryGovernor.sol:1009

- Signature: `function _settled(uint256 id) private view returns (bool)`
- Authority: internal (callers: none in this file)
- Gate evidence: `UNGATED`
- Reads: `proposals (line 1010)`; `proposals[id].executed (line 1011)`; `proposals[id].cancelled (line 1011)`; `proposals[id].votingEndsAt (line 1011)`
- Writes: none
- Value: NONE
- Reachability: Private and unreferenced: no call site exists for `_settled` (TreasuryGovernor.sol:1009) anywhere in the file, so it is unreachable from every external entry and contributes no runtime behaviour (DERIVED). Had it been used it would report a proposal as settled once `executed` (TreasuryGovernor.sol:1011) or `cancelled` (TreasuryGovernor.sol:1011) is set or its window has closed — a WEAKER condition than `_executable` (TreasuryGovernor.sol:716) and a different one from `_dead` (TreasuryGovernor.sol:782).
- Edges: none
- Observations: none

### `passing/function` — TreasuryGovernor.sol:1015

- Signature: `function passing(uint256 id) external view returns (bool)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `proposals (line 1016)`
- Writes: none
- Value: NONE
- Reachability: Unrestricted view for interfaces: it answers whether `_passed` (TreasuryGovernor.sol:1016) holds right now, with no timing test at all, so it reports on an open vote and on a long-stale one alike. An id that was never proposed reads false because both tallies are zero and the majority test at `forVotes` (TreasuryGovernor.sol:995) fails first (DERIVED).
- Edges: `TreasuryGovernor._passed (TreasuryGovernor.sol:1016), TRUSTED, in-cluster`
- Observations: none

### `_requirePriceable/function` — TreasuryGovernor.sol:1052

- Signature: `function _requirePriceable(address quote) internal view`
- Authority: internal (callers: propose, execute)
- Gate evidence: `UNGATED`
- Reads: `quoteOracle (line 1054)`
- Writes: none
- Value: NONE
- Reachability: Internal, reached from `_requirePriceable` (TreasuryGovernor.sol:1052) when a target is named and again from `_requirePriceable` (TreasuryGovernor.sol:1052) when the envelope is installed. Two exemptions make it a no-op: a native destination returns at `quote` (TreasuryGovernor.sol:1052) and an unset oracle returns at `o` (TreasuryGovernor.sol:1054). Otherwise it calls out to the guardian-controlled `quoteOracle` (TreasuryGovernor.sol:1054) and treats a zero price as fatal `QuoteNotPriceable` (TreasuryGovernor.sol:1056); a reverting oracle propagates and blocks both proposing and executing, and a guardian able to repoint `setQuoteOracle` (TreasuryGovernor.sol:1061) therefore controls whether any non-native mandate can be installed (DERIVED).
- Edges: `IQuotePrice.usdPerRawUnit (TreasuryGovernor.sol:1056), UNTRUSTED, out-of-cluster`
- Observations: comment `setQuoteAllowed` (TreasuryGovernor.sol:1023) names the registry's allowlist setter; code in the registry declares it as `setAllowedQuote` (CauldronRegistry.sol:314) and writes the mapping at `allowedQuote` (CauldronRegistry.sol:327).

### `setQuoteOracle/function` — TreasuryGovernor.sol:1061

- Signature: `function setQuoteOracle(address o) external`
- Authority: guardian
- Gate evidence: `if (msg.sender != guardian) revert NotGuardian(); (TreasuryGovernor.sol:1061)`
- Reads: `guardian (line 1062)`
- Writes: `quoteOracle (line 1063)`
- Value: NONE
- Reachability: Only the current `guardian` (TreasuryGovernor.sol:1062) may write `quoteOracle` (TreasuryGovernor.sol:1063), with no zero-check and no code-check, and it may be rewritten any number of times. Because the stored address is called during both `_requirePriceable` (TreasuryGovernor.sol:1060) and `_requirePriceable` (TreasuryGovernor.sol:1060), the holder of this setter can make any non-native quote unproposable and unexecutable, or clear the slot to skip the check entirely at `o` (TreasuryGovernor.sol:1061) (DERIVED).
- Edges: none
- Observations: comment `Timelock` (TreasuryGovernor.sol:1059) says the oracle is timelock-set, and comment `timelock` (TreasuryGovernor.sol:48) says only the timelock adds assets; code gates this setter on `guardian` (TreasuryGovernor.sol:1062) and the allowlist on the registry owner at `setAllowedQuote` (CauldronRegistry.sol:314).
