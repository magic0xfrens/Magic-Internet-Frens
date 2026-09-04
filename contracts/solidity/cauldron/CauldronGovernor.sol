// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MetadataMode, BrewSpec, ICauldronGovernor, LaunchLib} from "./ICauldron.sol";

/**
 * @title CauldronGovernor
 * @notice Permissionless proposal + voting registry for the eternal Cauldron.
 *
 *  Anyone can `propose()` the next brew: a name, ticker, and the NFT metadata
 *  source — either a base URI (off-chain) or an on-chain renderer contract. The
 *  MiFrens guild votes with 1 NFT = 1 vote (snapshot-free: voting weight is read
 *  live from the MiFrens ERC721 `balanceOf`, and each holder may vote once per
 *  proposal). `winner()` returns the live vote leader; the registry consumes it
 *  on relaunch and calls `markConsumed()` so it can never win twice.
 *
 *  No admin picks the winner. No pause. The only privileged call is
 *  `markConsumed`, restricted to the registry, and it only ever removes the
 *  already-summoned proposal from contention.
 */
contract CauldronGovernor is ICauldronGovernor, Ownable {
    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------
    error EmptyField();
    error BadRenderer();
    error UnknownProposal();
    error AlreadyVoted();
    error AlreadyConsumed();
    error NoVotingPower();
    error NotRegistry();
    error RegistryAlreadySet();
    error NoProposals();
    error SnapshotNotReady();
    error SupplyOutOfRange();
    error VotingClosed();

    /// @notice Hard bound on a proposal's collection size. MUST stay well below the
    ///         collections' `LIQUIDATOR_ID_BASE` (1e6), because the collection
    ///         constructor REVERTS at or above it — and a reverting constructor
    ///         inside `relaunch()` rolls back `markConsumed`, so the poisoned
    ///         proposal would win again forever and freeze the machine. (Audit C-02.)
    uint256 public constant MAX_NFT_SUPPLY = 100_000;

    /// @notice How long a proposal accepts votes before it may be launched. Without
    ///         a deadline, `winner()` is the live leader and a whale can flip the
    ///         result in the same block as the permissionless `relaunch()`.
    ///         (Audit M-02.)
    uint256 public constant VOTING_PERIOD = 3 days;

    // -----------------------------------------------------------------------
    // Types
    // -----------------------------------------------------------------------
    struct Proposal {
        string name;
        string symbol;
        MetadataMode mode;
        string baseURI;
        address renderer;
        string website;     // proposer's site
        string socials;     // community / X link
        uint256 nftSupply;  // proposer-chosen NFT collection max supply
        uint256 volumePerNFT; // credit volume to forge each NFT (0 = hook default)
        address proposer;
        uint256 votes;
        uint256 snapshot;   // block at which voting power is measured
        uint256 votingEndsAt; // timestamp after which votes close and it may win
        bool consumed;
        bool exists;
    }

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    /// @notice The MiFrens checkpointed-voting NFT (electorate).
    IVotes public immutable mifrens;

    /// @notice The registry allowed to consume winners (set once).
    address public registry;

    uint256 public proposalCount;
    mapping(uint256 => Proposal) private _proposals;

    /// @notice proposalId => voter => voted.
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    // Live leader tracking (avoids O(n) scans on winner()).
    uint256 private _leaderId;
    uint256 private _leaderVotes;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    event Proposed(uint256 indexed proposalId, address indexed proposer, string name, string symbol, MetadataMode mode);
    event Voted(uint256 indexed proposalId, address indexed voter, uint256 weight, uint256 totalVotes);
    event Consumed(uint256 indexed proposalId);
    event RegistrySet(address registry);

    constructor(address _mifrens) Ownable(msg.sender) {
        if (_mifrens == address(0)) revert EmptyField();
        mifrens = IVotes(_mifrens);
    }

    /// @notice One-time wiring of the registry that may consume winners.
    /// @dev Owner-gated: an unprotected setter would be front-runnable — an
    ///      attacker could seize `registry` and grief proposals via markConsumed.
    function setRegistry(address _registry) external onlyOwner {
        if (registry != address(0)) revert RegistryAlreadySet();
        if (_registry == address(0)) revert EmptyField();
        registry = _registry;
        emit RegistrySet(_registry);
    }

    // -----------------------------------------------------------------------
    // Propose
    // -----------------------------------------------------------------------

    /**
     * @notice Submit a proposal for the next brew.
     * @param name     Token + collection name.
     * @param symbol   Ticker.
     * @param mode     BaseURI or Renderer.
     * @param baseURI  Base URI (required if mode == BaseURI).
     * @param renderer On-chain renderer contract (required if mode == Renderer).
     */
    /**
     * @param name     Token + collection name (branded on-chain as
     *                 "<name> by Magic Internet Frens" — the suffix is fixed).
     * @param symbol   Ticker.
     * @param mode     BaseURI or Renderer.
     * @param baseURI  Base URI (required if mode == BaseURI).
     * @param renderer On-chain renderer (required if mode == Renderer).
     * @param website  Optional project site.
     * @param socials  Optional community / X link.
     */
    function propose(
        string calldata name,
        string calldata symbol,
        MetadataMode mode,
        string calldata baseURI,
        address renderer,
        string calldata website,
        string calldata socials,
        uint256 nftSupply,
        uint256 volumePerNFT
    ) external returns (uint256 id) {
        // Only the guild may propose the next brew — you must hold a MiFren
        // (auto-delegated on mint, so voting power is live without a delegate tx).
        if (mifrens.getVotes(msg.sender) == 0) revert NoVotingPower();
        if (bytes(name).length == 0 || bytes(symbol).length == 0) revert EmptyField();
        if (mode == MetadataMode.BaseURI) {
            if (bytes(baseURI).length == 0) revert EmptyField();
        } else {
            // Must point at a contract (code size > 0) so tokenURI can render.
            if (renderer == address(0) || renderer.code.length == 0) revert BadRenderer();
        }
        // A proposal is an UNTRUSTED input that flows straight into a constructor
        // at relaunch. Reject anything the collection could never be deployed with,
        // here at the boundary — a revert deeper in `relaunch()` would roll back
        // `markConsumed` and freeze the machine forever. (Audit C-02.)
        if (nftSupply > MAX_NFT_SUPPLY) revert SupplyOutOfRange();

        id = ++proposalCount;
        _proposals[id] = Proposal({
            name: name,
            symbol: symbol,
            mode: mode,
            baseURI: baseURI,
            renderer: renderer,
            website: website,
            socials: socials,
            nftSupply: nftSupply,
            volumePerNFT: volumePerNFT,
            proposer: msg.sender,
            votes: 0,
            snapshot: block.number, // voting power frozen as of this block
            votingEndsAt: block.timestamp + VOTING_PERIOD,
            consumed: false,
            exists: true
        });

        emit Proposed(id, msg.sender, name, symbol, mode);
    }

    /// @notice The public display name for a proposal: "<name> by Magic Internet Frens".
    function displayName(uint256 proposalId) external view returns (string memory) {
        Proposal storage p = _proposals[proposalId];
        if (!p.exists) revert UnknownProposal();
        return LaunchLib.displayName(p.name);
    }

    // -----------------------------------------------------------------------
    // Vote
    // -----------------------------------------------------------------------

    /**
     * @notice Vote for a proposal. Weight = caller's live MiFrens balance.
     *         One vote per address per proposal.
     */
    function vote(uint256 proposalId) external {
        Proposal storage p = _proposals[proposalId];
        if (!p.exists) revert UnknownProposal();
        if (p.consumed) revert AlreadyConsumed();
        // Votes close BEFORE a proposal becomes eligible to win, so nobody can flip
        // the outcome by front-running the permissionless relaunch. (Audit M-02.)
        // Checked ahead of `hasVoted` so a closed window always reports as such,
        // whoever asks.
        if (block.timestamp > p.votingEndsAt) revert VotingClosed();
        if (hasVoted[proposalId][msg.sender]) revert AlreadyVoted();

        // Weight is the caller's CHECKPOINTED power at the proposal's snapshot
        // block. Transferring MiFrens after the snapshot cannot mint new votes —
        // the classic "transfer to a fresh wallet and vote again" attack fails.
        if (block.number <= p.snapshot) revert SnapshotNotReady();
        uint256 weight = mifrens.getPastVotes(msg.sender, p.snapshot);
        if (weight == 0) revert NoVotingPower();

        hasVoted[proposalId][msg.sender] = true;
        p.votes += weight;

        // Update live leader (ties keep the earlier leader).
        if (p.votes > _leaderVotes) {
            _leaderVotes = p.votes;
            _leaderId = proposalId;
        }

        emit Voted(proposalId, msg.sender, weight, p.votes);
    }

    // -----------------------------------------------------------------------
    // Winner / consume
    // -----------------------------------------------------------------------

    /// @notice The current leading, unconsumed proposal.
    function winner() external view returns (uint256 proposalId, BrewSpec memory spec) {
        proposalId = _bestUnconsumed();
        if (proposalId == 0) revert NoProposals();
        Proposal storage p = _proposals[proposalId];
        spec = BrewSpec({
            name: p.name,
            symbol: p.symbol,
            mode: p.mode,
            baseURI: p.baseURI,
            renderer: p.renderer,
            website: p.website,
            socials: p.socials,
            nftSupply: p.nftSupply,
            volumePerNFT: p.volumePerNFT,
            proposer: p.proposer
        });
    }

    function hasProposals() external view returns (bool) {
        return _bestUnconsumed() != 0;
    }

    /// @notice Registry-only: retire a proposal once it has been summoned.
    function markConsumed(uint256 proposalId) external {
        if (msg.sender != registry) revert NotRegistry();
        Proposal storage p = _proposals[proposalId];
        if (!p.exists) revert UnknownProposal();
        if (p.consumed) revert AlreadyConsumed();
        p.consumed = true;

        // If the consumed one was the cached leader, recompute lazily.
        if (proposalId == _leaderId) {
            (_leaderId, _leaderVotes) = _recomputeLeader();
        }
        emit Consumed(proposalId);
    }

    // -----------------------------------------------------------------------
    // Views
    // -----------------------------------------------------------------------

    function getProposal(uint256 id) external view returns (Proposal memory) {
        Proposal memory p = _proposals[id];
        if (!p.exists) revert UnknownProposal();
        return p;
    }

    /// @dev Returns the cached leader if it is still valid AND its voting window has
    ///      CLOSED; otherwise recomputes over settled proposals only. A proposal
    ///      still taking votes can never be launched, which is what removes the
    ///      last-instant front-run (audit M-02).
    function _bestUnconsumed() private view returns (uint256) {
        Proposal storage cached = _proposals[_leaderId];
        if (cached.exists && !cached.consumed && _leaderVotes > 0
            && block.timestamp > cached.votingEndsAt) {
            return _leaderId;
        }
        (uint256 id, ) = _recomputeLeader();
        return id;
    }

    /// @notice Hard bound on the leader rescan (audit Z-03 — High). `relaunch()`
    ///         reaches this scan up to three times per rebirth (`hasProposals`,
    ///         `winner`, and the `markConsumed` recompute), and `propose()` is
    ///         permissionless for the holder of a SINGLE MiFren with no cooldown,
    ///         deposit or per-address cap. An unbounded scan therefore let anyone
    ///         raise the gas cost of every future rebirth without limit — measured at
    ///         ~613 gas per spam proposal per scan, i.e. ~17k proposals (a few
    ///         hundredths of an ETH on an L2) to push `relaunch()` past a 32M block
    ///         and permanently halt the eternal machine. Compounded by the fact that
    ///         `CauldronRegistry.setGovernor` is `onlyOwner` and registry ownership is
    ///         burned into the presale at deploy, so a spammed governor could never be
    ///         swapped out.
    ///
    ///         Bounding the scan makes relaunch gas O(1) in the proposal count. The
    ///         cached-leader fast path in {_bestUnconsumed} is unaffected, so an
    ///         already-established winner keeps winning however much spam follows it;
    ///         a fresh mandate simply has to be among the most recent proposals, which
    ///         it always is.
    uint256 internal constant MAX_LEADER_SCAN = 64;

    /// @dev BOUNDED scan over the most recent SETTLED (voting-closed), unconsumed
    ///      proposals. See {MAX_LEADER_SCAN}.
    function _recomputeLeader() private view returns (uint256 bestId, uint256 bestVotes) {
        uint256 n = proposalCount;
        uint256 first = n > MAX_LEADER_SCAN ? n - MAX_LEADER_SCAN + 1 : 1;
        for (uint256 i = first; i <= n; i++) {
            Proposal storage p = _proposals[i];
            if (!p.exists || p.consumed) continue;
            if (block.timestamp <= p.votingEndsAt) continue; // still open for votes
            if (p.votes > bestVotes) {
                bestVotes = p.votes;
                bestId = i;
            }
        }
    }
}
