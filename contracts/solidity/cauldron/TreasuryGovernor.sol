// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IVotes721 {
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);
    function getVotes(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IRegistryQuotes {
    function allowedQuote(address quote) external view returns (bool);
}

/**
 * @title TreasuryGovernor
 * @notice The guild votes on what backs its own liquidity.
 *
 *  Rotation used to be `onlyOwner` on a timelock the deployer controlled both
 *  ends of — propose and execute. That is one admin key with a delay in front of
 *  it, not governance, and calling it governance would have been the dishonest
 *  part. This is the actual thing: MiFren holders approve a policy, and anyone
 *  can then execute inside it.
 *
 *  ── What is voted on ───────────────────────────────────────────────────────
 *  An ENVELOPE, not a transaction: "we may move up to N% of the LP into asset X,
 *  before date D". Holders have opinions about whether the treasury should hold
 *  USDG; they do not have opinions about whether slice fourteen fills at 3pm.
 *  Approving the policy and leaving execution mechanical is what keeps the vote
 *  meaningful and the process usable.
 *
 *  ── Where the guardrails are ───────────────────────────────────────────────
 *  This is the part that decides whether a DAO gets drained, so each limit is
 *  deliberate:
 *
 *  1. THE ALLOWLIST IS NOT VOTABLE. Only the timelock adds assets. A vote can
 *     only choose among assets already vetted, so even a fully captured vote
 *     cannot route the treasury into an attacker's token. This is the single
 *     most important guardrail here — everything else limits damage, this one
 *     removes the category.
 *  2. VOTING POWER IS SNAPSHOTTED at the proposing block, so nobody can buy or
 *     borrow MiFrens after reading a proposal and vote with them.
 *  3. QUORUM, so a proposal cannot pass on three votes at 4am.
 *  4. A CEILING on any envelope, and a floor left in the primary quote, so no
 *     vote — however legitimate — can move the treasury entirely into one asset.
 *  5. EXPIRY. An approved envelope goes stale rather than sitting dormant and
 *     executing a year later into a different market.
 *  6. ONE ACTIVE ENVELOPE and a cooldown, so the LP cannot be churned by
 *     back-to-back proposals.
 *  7. A GUARDIAN can cancel, which is the emergency stop when a proposal turns
 *     out to be malicious after passing.
 *
 *  ── On front-running the vote ──────────────────────────────────────────────
 *  A proposal is public for its whole voting period, so the destination is known
 *  in advance: someone can buy the target first and sell into the treasury's
 *  buying. Three things defuse it, and none of them is secrecy.
 *
 *  The per-slice price floor is the real one. Execution carries a `minOut`, so a
 *  pumped price does not produce a bad fill — it produces NO fill. The rotation
 *  stalls until the price is acceptable again, leaving the front-runner holding
 *  inventory they bid up. An envelope is permission to buy at a good price, never
 *  an obligation to buy at any price.
 *
 *  Slicing means the flow is small and spread out, so there is little to extract
 *  per slice and it must be extracted repeatedly. And restricting the allowlist
 *  to deep assets makes protocol-sized flow immaterial against real depth.
 *
 *  Hiding the target (commit-reveal) would defeat the point: holders cannot
 *  meaningfully approve a destination they are not told. Liquidity plus a price
 *  floor is the better trade.
 */
contract TreasuryGovernor {
    error NoVotingPower();
    error BelowProposalThreshold();
    error QuoteNotAllowed();
    error ProposalActive();
    error CooldownActive();
    error BadParam();
    error UnknownProposal();
    error VotingClosed();
    error VotingOpen();
    error AlreadyVoted();
    error AlreadyExecuted();
    error DidNotPass();
    error NotGuardian();

    struct Proposal {
        address quote;        // destination asset (must stay allowlisted)
        uint16 maxTotalBps;   // ceiling on cumulative rotation under this envelope
        uint64 votingEndsAt;
        uint256 snapshot;     // block whose voting power counts
        uint256 forVotes;
        uint256 againstVotes;
        address proposer;
        bool executed;
        bool cancelled;
    }

    /// @notice The approved policy rotation executes against. Read by the
    ///         registry; there is at most one at a time.
    struct Envelope {
        address quote;
        uint16 maxTotalBps;
        uint16 movedBps;   // consumed so far, written by the registry
        uint64 expiry;
        bool active;
    }

    IVotes721 public immutable mifrens;
    address public immutable registry;
    address public guardian;

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    uint256 public proposalCount;
    uint256 public activeProposal;

    Envelope public envelope;
    uint64 public lastEnvelopeAt;

    // ── Guardrails. Constants rather than settable: a governor that can vote to
    //    weaken its own limits does not have limits.
    uint64 public constant VOTING_PERIOD = 3 days;
    uint64 public constant ENVELOPE_LIFETIME = 30 days;
    uint64 public constant COOLDOWN = 7 days;
    /// Most of the LP that any single envelope may move.
    uint16 public constant MAX_ENVELOPE_BPS = 4000; // 40%
    /// Share of total MiFren supply that must vote FOR for a proposal to pass.
    uint16 public constant QUORUM_BPS = 1000; // 10%
    /// MiFrens required to open a treasury proposal. Higher than the brew
    /// governor's threshold because this one moves money rather than art.
    uint256 public constant PROPOSAL_THRESHOLD = 5;

    event Proposed(uint256 indexed id, address indexed proposer, address quote, uint16 maxTotalBps);
    event Voted(uint256 indexed id, address indexed voter, bool support, uint256 weight);
    event Executed(uint256 indexed id, address quote, uint16 maxTotalBps, uint64 expiry);
    event Cancelled(uint256 indexed id, address by);
    event EnvelopeConsumed(uint16 bps, uint16 movedTotal);

    constructor(IVotes721 _mifrens, address _registry, address _guardian) {
        mifrens = _mifrens;
        registry = _registry;
        guardian = _guardian;
    }

    // -----------------------------------------------------------------------
    // Proposing + voting
    // -----------------------------------------------------------------------

    /**
     * @notice Open a treasury proposal.
     * @dev The threshold is the anti-spam measure: a proposal occupies the only
     *      active slot for three days, so opening one has to cost something.
     */
    function propose(address quote, uint16 maxTotalBps) external returns (uint256 id) {
        if (mifrens.getVotes(msg.sender) < PROPOSAL_THRESHOLD) revert BelowProposalThreshold();
        if (maxTotalBps == 0 || maxTotalBps > MAX_ENVELOPE_BPS) revert BadParam();
        // Checked here AND at execution: the timelock can de-list an asset while
        // a proposal is out for vote, and the check that matters is the later one.
        if (!IRegistryQuotes(registry).allowedQuote(quote)) revert QuoteNotAllowed();

        uint256 act = activeProposal;
        if (act != 0 && !_settled(act)) revert ProposalActive();
        if (envelope.active && block.timestamp < envelope.expiry) revert ProposalActive();
        if (block.timestamp < lastEnvelopeAt + COOLDOWN) revert CooldownActive();

        id = ++proposalCount;
        proposals[id] = Proposal({
            quote: quote,
            maxTotalBps: maxTotalBps,
            votingEndsAt: uint64(block.timestamp) + VOTING_PERIOD,
            // Voting power is frozen at the PROPOSING block, so MiFrens bought
            // or borrowed after reading this proposal carry no weight.
            snapshot: block.number,
            forVotes: 0,
            againstVotes: 0,
            proposer: msg.sender,
            executed: false,
            cancelled: false
        });
        activeProposal = id;
        emit Proposed(id, msg.sender, quote, maxTotalBps);
    }

    function vote(uint256 id, bool support) external {
        Proposal storage p = proposals[id];
        if (p.votingEndsAt == 0) revert UnknownProposal();
        if (block.timestamp >= p.votingEndsAt) revert VotingClosed();
        if (hasVoted[id][msg.sender]) revert AlreadyVoted();

        uint256 w = mifrens.getPastVotes(msg.sender, p.snapshot);
        if (w == 0) revert NoVotingPower();

        hasVoted[id][msg.sender] = true;
        if (support) p.forVotes += w; else p.againstVotes += w;
        emit Voted(id, msg.sender, support, w);
    }

    /**
     * @notice Turn a passed proposal into the live envelope.
     * @dev Permissionless: if the guild approved it, no privileged account
     *      should be able to sit on the result. That is the half of "governance"
     *      an admin key cannot provide.
     */
    function execute(uint256 id) external {
        Proposal storage p = proposals[id];
        if (p.votingEndsAt == 0) revert UnknownProposal();
        if (block.timestamp < p.votingEndsAt) revert VotingOpen();
        if (p.executed || p.cancelled) revert AlreadyExecuted();
        if (!_passed(p)) revert DidNotPass();
        // Re-checked, because the timelock may have de-listed the asset during
        // the vote and the allowlist is the guardrail that must not be stale.
        if (!IRegistryQuotes(registry).allowedQuote(p.quote)) revert QuoteNotAllowed();

        p.executed = true;
        envelope = Envelope({
            quote: p.quote,
            maxTotalBps: p.maxTotalBps,
            movedBps: 0,
            expiry: uint64(block.timestamp) + ENVELOPE_LIFETIME,
            active: true
        });
        lastEnvelopeAt = uint64(block.timestamp);
        emit Executed(id, p.quote, p.maxTotalBps, envelope.expiry);
    }

    /// @notice Emergency stop. A proposal that turns out to be malicious can pass
    ///         legitimately; the guardian is the answer to that, and it can only
    ///         ever STOP a rotation, never start or redirect one.
    function cancel(uint256 id) external {
        if (msg.sender != guardian) revert NotGuardian();
        proposals[id].cancelled = true;
        if (envelope.active && proposals[id].executed) envelope.active = false;
        emit Cancelled(id, msg.sender);
    }

    function setGuardian(address g) external {
        if (msg.sender != guardian) revert NotGuardian();
        guardian = g;
    }

    // -----------------------------------------------------------------------
    // Consumed by the registry
    // -----------------------------------------------------------------------

    /// @notice The rotation the registry is currently permitted to perform.
    /// @return quote destination asset, or address(0) when nothing is approved
    /// @return remainingBps how much of the LP may still be moved
    function allowance() public view returns (address quote, uint16 remainingBps) {
        Envelope storage e = envelope;
        if (!e.active || block.timestamp >= e.expiry) return (address(0), 0);
        if (e.movedBps >= e.maxTotalBps) return (address(0), 0);
        return (e.quote, e.maxTotalBps - e.movedBps);
    }

    /// @notice Record a slice against the envelope. Registry-only: it is the
    ///         contract that actually moves the liquidity, so it is the only one
    ///         that may say how much has moved.
    function consume(uint16 bps) external {
        if (msg.sender != registry) revert NotGuardian();
        Envelope storage e = envelope;
        (address q, uint16 left) = allowance();
        if (q == address(0) || bps > left) revert BadParam();
        e.movedBps += bps;
        emit EnvelopeConsumed(bps, e.movedBps);
    }

    // -----------------------------------------------------------------------

    function _passed(Proposal storage p) private view returns (bool) {
        if (p.forVotes <= p.againstVotes) return false;
        // Quorum on TOTAL supply rather than turnout: a low-turnout vote should
        // fail rather than let a handful of holders move the treasury.
        uint256 need = (mifrens.totalSupply() * QUORUM_BPS) / 10_000;
        return p.forVotes >= need;
    }

    function _settled(uint256 id) private view returns (bool) {
        Proposal storage p = proposals[id];
        return p.executed || p.cancelled || block.timestamp >= p.votingEndsAt;
    }

    /// @notice Whether `id` would pass if the vote closed now.
    function passing(uint256 id) external view returns (bool) {
        return _passed(proposals[id]);
    }
}
