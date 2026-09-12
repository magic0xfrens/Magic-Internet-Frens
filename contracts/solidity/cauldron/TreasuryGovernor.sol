// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IVotes721 {
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);
    function getVotes(address account) external view returns (uint256);
    /// @dev The quorum denominator. NOT `totalSupply()`: the contract actually
    ///      wired here is {MiFrensGenesis}, which is `ERC721Votes` but NOT
    ///      `ERC721Enumerable` and therefore has no `totalSupply` and no
    ///      fallback — every quorum read reverted `unrecognized function
    ///      selector`, which killed `execute` outright. `getPastTotalSupply` is
    ///      what `Votes` actually maintains, it is measured AT THE PROPOSAL'S
    ///      SNAPSHOT (so quorum cannot be moved by minting or burning after the
    ///      vote opens), and it follows burns, which a mint counter would not.
    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);
}

interface IRegistryQuotes {
    function allowedQuote(address quote) external view returns (bool);
}

/// @dev Just enough of QuoteOracle to ask "can this asset be valued at all?".
interface IQuotePrice {
    function usdPerRawUnit(address quote) external view returns (uint256);
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
    error QuoteNotPriceable();

    /// @notice Oracle consulted to confirm a rotation target can be valued at
    ///         all. Unset skips the check — see {_requirePriceable}.
    address public quoteOracle;
    event QuoteOracleSet(address indexed oracle);
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
        /// @dev Of `movedBps`, the part taken out of the GENERATION'S OWN
        ///      position rather than a secondary rotated leg. Only this part may
        ///      declare a migration finished — see {migrationMandateSpent}.
        uint16 movedPrimaryBps;
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

    /// @dev Highest-voted proposal seen by {vote}, so {winner} does not have to
    ///      scan in the common case. Appended after `lastEnvelopeAt`, so no
    ///      existing slot moves.
    ///
    ///  This is the O(1) half of the fix described on {winner}: maintained
    ///  incrementally where the votes actually change, and only VALIDATED on
    ///  read. {winner} re-checks executability before trusting it, and falls back
    ///  to the time-bounded scan when the hint is not executable.
    ///
    ///  ── WHAT MAKES THE FAST PATH SOUND ─────────────────────────────────────
    ///  {winner} returns the hint on an EXECUTABILITY test alone, so the hint has
    ///  to be a MAXIMUM and not merely a candidate — otherwise the fast path
    ///  elects a proposal the scan would have beaten. The invariant that earns it:
    ///
    ///      every proposal that is not yet {_dead} holds at most `_leadVotes`
    ///      FOR-votes.
    ///
    ///  Executable implies not-dead, so the hint dominates every proposal the scan
    ///  could have returned. {vote} is the only writer and is responsible for
    ///  keeping it true; read the branches there before changing any of them.
    uint256 private _leadId;
    uint256 private _leadVotes;

    /// @dev When a FOR-vote last landed on a proposal that the hint does NOT
    ///      track and that was still alive at the time. Nothing else; it exists
    ///      only so {vote} can prove when a stale hint is safe to retire.
    ///
    ///  ── WHY A HINT MUST BE RETIRABLE AT ALL (S-04) ─────────────────────────
    ///  `_leadVotes` used to be a permanent high-water mark — written in one
    ///  place, lowered nowhere. So once a proposal drew V votes, `_leadId` went on
    ///  pointing at it after it was executed, cancelled, or simply aged out, every
    ///  later proposal passing quorum with fewer than V could never become the
    ///  hint, and EVERY {winner} call fell through to the scan. `propose` costs
    ///  {PROPOSAL_THRESHOLD} MiFrens and nothing else, so a third party could then
    ///  price the guild's own mandate out of a block: measured at 6,421 gas honest
    ///  and 363,633 with 400 junk filings, 888 gas apiece.
    ///
    ///  ── WHY THE OBVIOUS REPAIR IS WRONG ────────────────────────────────────
    ///  "Let a later vote take over once the leader is no longer executable"
    ///  breaks the maximality above, and does it silently:
    ///
    ///      L filed t=0,    500 votes         → hint L; dead from t=6d
    ///      M filed t=4d,   400 votes at t=5d → 400 < 500, so M is untracked
    ///      N filed t=6d+1, 150 votes         → L is dead, so N takes the hint
    ///      read at t=9d+2                    → M and N are both executable
    ///
    ///  and the fast path elects N on 150 votes where the scan elects M on 400. A
    ///  liveness fix that changes who won is not a fix. The hint cannot be handed
    ///  to a smaller proposal while an unseen bigger one may still be alive.
    ///
    ///  ── WHAT MAKES RETIREMENT PROVABLE ─────────────────────────────────────
    ///  Death has a deadline that voting itself fixes. `votingEndsAt` is set at
    ///  creation and a vote can only land while it is in the future, so a proposal
    ///  voted at `t` is dead by `t + VOTING_PERIOD + EXECUTION_WINDOW` — always,
    ///  with no further transaction. Recording the last moment an untracked LIVE
    ///  proposal was voted therefore dates every rival the hint cannot see: past
    ///  that mark plus one full lifetime, all of them are provably dead, and a
    ///  dead leader can be handed over to the voter in front of us because there
    ///  is nothing left that could outrank them. That is the whole rule in {vote}.
    ///
    ///  The bound is TIGHT rather than conservative: in the M case above it
    ///  refuses the handover until t=11d, which is exactly when M can no longer be
    ///  executed. Refusing costs a scan; it never costs a wrong winner.
    uint64 private _openVotedAt;

    /// @dev How many mandates the bench below can hold.
    uint256 internal constant BENCH_SLOTS = 8;

    /// @dev The proposals {winner}'s fallback may choose from. Appended after
    ///      `_openVotedAt`, so no existing storage slot moves.
    ///
    ///  ── THE TIME BOUND WAS NOT ENOUGH, BECAUSE THE HINT IS PINNABLE ───────
    ///  The reverse scan below is bounded by TIME rather than by position, which
    ///  is the right shape and fixed the flood the positional version had. It
    ///  still spans every proposal filed in the last VOTING_PERIOD +
    ///  EXECUTION_WINDOW, and `propose` has no per-proposal cooldown — so during
    ///  the exact window in which the guild is trying to install an envelope
    ///  (no envelope active, cooldown elapsed: the only window in which `propose`
    ///  is open at all) a stranger holding PROPOSAL_THRESHOLD MiFrens can file
    ///  arbitrarily many and make the scan arbitrarily expensive. `execute` gates
    ///  on `id != winner()`, so an over-budget scan is an un-executable mandate.
    ///
    ///  The fast path was supposed to make that irrelevant, and it is PINNABLE.
    ///  `_leadVotes` is lowered in exactly one branch — case (4) in {vote} — which
    ///  requires `block.timestamp > _openVotedAt + VOTING_PERIOD +
    ///  EXECUTION_WINDOW`. Case (5) rewrites `_openVotedAt` on ANY FOR-vote for a
    ///  live untracked proposal. So one junk filing plus one FOR-vote every six
    ///  days — gas only, one MiFren — keeps case (4) permanently out of reach:
    ///  `_leadId` stays pointed at a corpse, no later proposal can ever take the
    ///  hint, and EVERY {winner} call falls through to the scan the attacker is
    ///  also inflating. The two halves feed each other.
    ///
    ///  The fallback therefore stops being over the proposal list. This is the
    ///  same shape as {CauldronGovernor._bench}, and it fits here for the same
    ///  reason it fits there: entry is by FOR-VOTES, which cost MiFrens, rather
    ///  than by position or recency, which cost gas. A proposal nobody supported
    ///  can never enter, and it could never have won either — `_passed` needs
    ///  `forVotes > againstVotes` AND quorum. Displacing an incumbent means
    ///  out-voting the weakest one still alive; executed, cancelled, stale and
    ///  empty slots count as weight 0 and are reclaimed first, so the bench
    ///  self-cleans as envelopes are installed and age out.
    ///
    ///  WHAT DIFFERS FROM THE SIBLING: a brew mandate is stockpiled indefinitely,
    ///  so over there the bench is the ONLY memory. Here a proposal is dead six
    ///  days after it is filed, so the bench is only ever holding the handful of
    ///  proposals that could still be executed — eight slots is generous, not
    ///  tight, and a ninth simultaneously-executable passed proposal with more
    ///  votes than all eight is not a state this governor can reach in practice.
    ///
    ///  The pinnable hint is LEFT AS IS on purpose. With an O(BENCH_SLOTS)
    ///  fallback, pinning it costs eight cold reads instead of one — a gas
    ///  regression a stranger pays for in votes, not a denial. Its maximality
    ///  invariant is unchanged and still carries the fast path, so the cheaper
    ///  path keeps working for everyone who is not being attacked.
    uint256[BENCH_SLOTS] private _bench;

    // ── Guardrails. Constants rather than settable: a governor that can vote to
    //    weaken its own limits does not have limits.
    //  ── TIMING IS IMMUTABLE PER DEPLOYMENT, NOT CONSTANT ────────────────
    //  These were `constant`, on the correct principle that a governor able to
    //  vote its own limits down has no limits. That principle is about what
    //  GOVERNANCE can change after deployment, not about what a deployment may
    //  be configured with — and hardcoding mainnet durations made the contract
    //  untestable on a testnet, where a full rotation would take 80+ days of
    //  real waiting.
    //
    //  So they are `immutable`: fixed at construction, unchangeable afterwards
    //  by anyone including the guardian and the vote, and floored below so a
    //  mainnet deploy cannot be talked into testnet numbers by a careless
    //  argument. `TESTNET_MODE` opens the floors and is a DEPLOY-TIME flag, so
    //  the mainnet script simply never passes it.
    uint64 public immutable VOTING_PERIOD;
    uint64 public immutable ENVELOPE_LIFETIME;
    uint64 public immutable COOLDOWN;
    /// @notice How long after its vote closes a winning proposal stays
    ///         executable. Past this it is stale: the market it was voted about
    ///         is not the market it would execute into.
    uint64 public immutable EXECUTION_WINDOW;
    /// @notice Cumulative SLICE BUDGET a single envelope may spend.
    ///
    ///  ── THIS IS A SPEND COUNTER, NOT A POSITION FRACTION ────────────────
    ///  {consume} books the NOMINAL `sliceBps` of each rotation, while
    ///  `PoolOps.removePartial` takes that share of the CURRENT position. The
    ///  position therefore decays geometrically and the nominal spend needed to
    ///  convert most of it exceeds 100%: reaching 5% of the original costs
    ///  about 27,500 bps of budget at a 25% slice, and about 29,500 at 5%.
    ///
    ///  The old value of 4000 (40%) read as "40% of the LP" and was neither. It
    ///  bought 8 slices of 5%, which moved 1 - 0.95^8 = 33.66% of the position,
    ///  and a full de-risking rotation needed roughly eight consecutive
    ///  envelopes — about 80 days with the vote and cooldown counted. A guild
    ///  that votes to move into a stable at a suspected top cannot act on that
    ///  decision a quarter later.
    ///
    ///  30,000 lets ONE approved envelope carry a rotation to ~95% conversion.
    ///  It is a budget, so read it with {conversionFor}, which converts a spend
    ///  into the share of the position it actually moves.
    ///
    ///  The safety of a rotation does not rest on this number. It rests on the
    ///  destination being owner-allowlisted (`allowedQuote`, which a vote cannot
    ///  widen), on the 3-day vote and 10% quorum, on each slice's own `minOut`,
    ///  on the venue allowlist in {QuoteRotator}, and on
    ///  {PoolOps.MAX_ROTATION_BPS} capping any single call at 50% of the live
    ///  position. This constant governs how FAST an approved policy executes,
    ///  not what may be approved.
    uint16 public constant MAX_ENVELOPE_BPS = 30_000;

    /// @notice The share of the position a `spendBps` budget actually converts,
    ///         in bps, at slice size `sliceBps`.
    ///
    ///  Exposed because the budget's units are not the units a voter reasons in:
    ///  "30,000" is not 300% of anything, it is enough slices to convert ~95%.
    ///  A UI that showed the raw number would mislead, and a voter who has to do
    ///  a geometric-series calculation by hand will not do it.
    function conversionFor(uint16 spendBps, uint16 sliceBps) external pure returns (uint16) {
        if (sliceBps == 0 || spendBps == 0) return 0;
        uint256 n = uint256(spendBps) / sliceBps;          // whole slices affordable
        // remaining = (1 - sliceBps/1e4)^n, carried in 1e4 fixed point.
        uint256 rem = 10_000;
        for (uint256 i; i < n && rem > 0; ++i) {
            rem = (rem * (10_000 - sliceBps)) / 10_000;
        }
        return uint16(10_000 - rem);
    }
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

    /// @notice Mainnet defaults. The zero-argument constructor is the one a
    ///         production deploy uses, so shipping safe timing takes no thought.
    uint64 internal constant MAINNET_VOTING = 3 days;
    uint64 internal constant MAINNET_LIFETIME = 30 days;
    uint64 internal constant MAINNET_COOLDOWN = 7 days;
    uint64 internal constant MAINNET_EXEC_WINDOW = 3 days;

    /// @notice Floors that apply unless `testnet` is set. A deploy may lengthen
    ///         these but never shorten them, so a fat-fingered argument cannot
    ///         quietly ship a 60-second vote to mainnet.
    uint64 internal constant MIN_VOTING = 1 days;
    uint64 internal constant MIN_COOLDOWN = 1 days;
    uint64 internal constant MIN_EXEC_WINDOW = 1 days;

    error BadTiming();

    /// @param votingPeriod    how long a proposal accepts votes
    /// @param envelopeLifetime how long an executed envelope stays live
    /// @param cooldown        gap between envelopes
    /// @param executionWindow how long a passed proposal stays executable
    /// @param testnet         waive the floors. TESTNET ONLY — a mainnet deploy
    ///        must pass false (or use the zero-arg constructor), because the
    ///        floors are the only thing standing between a typo and a treasury
    ///        that can be rotated out from under holders in a minute.
    constructor(
        IVotes721 _mifrens,
        address _registry,
        address _guardian,
        uint64 votingPeriod,
        uint64 envelopeLifetime,
        uint64 cooldown,
        uint64 executionWindow,
        bool testnet
    ) {
        mifrens = _mifrens;
        registry = _registry;
        guardian = _guardian;

        //  Zero means "use the mainnet default", so a caller that only wants to
        //  change one duration does not have to restate the others correctly.
        votingPeriod = votingPeriod == 0 ? MAINNET_VOTING : votingPeriod;
        envelopeLifetime = envelopeLifetime == 0 ? MAINNET_LIFETIME : envelopeLifetime;
        cooldown = cooldown == 0 ? MAINNET_COOLDOWN : cooldown;
        executionWindow = executionWindow == 0 ? MAINNET_EXEC_WINDOW : executionWindow;

        if (!testnet) {
            if (votingPeriod < MIN_VOTING) revert BadTiming();
            if (cooldown < MIN_COOLDOWN) revert BadTiming();
            if (executionWindow < MIN_EXEC_WINDOW) revert BadTiming();
        }
        //  An envelope that expires before its own execution window closes would
        //  be un-executable on arrival. Checked in BOTH modes: it is an
        //  incoherence, not a policy choice.
        if (envelopeLifetime < executionWindow) revert BadTiming();

        VOTING_PERIOD = votingPeriod;
        ENVELOPE_LIFETIME = envelopeLifetime;
        COOLDOWN = cooldown;
        EXECUTION_WINDOW = executionWindow;
        emit TimingSet(votingPeriod, envelopeLifetime, cooldown, executionWindow, testnet);
    }

    event TimingSet(
        uint64 votingPeriod, uint64 envelopeLifetime, uint64 cooldown,
        uint64 executionWindow, bool testnet
    );

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
        _requirePriceable(quote);

        //  PROPOSALS COMPETE; THEY DO NOT QUEUE.
        //
        //  An earlier version allowed one open proposal at a time, which read as
        //  a safety property and was actually an attack: anyone holding the
        //  5-MiFren threshold could file junk every three days and block
        //  treasury governance permanently, for the price of gas. Serialising a
        //  public queue hands a veto to whoever is fastest.
        //
        //  Concurrent proposals with a winner-takes-all close removes that. Junk
        //  simply loses, and two genuine proposals for different assets resolve
        //  the way a disagreement should — by vote, not by who filed first.
        //  This mirrors CauldronGovernor, which already picks brews this way.
        //
        //  Only the ENVELOPE is exclusive: one rotation may be live at a time.
        if (envelope.active && block.timestamp < envelope.expiry) revert ProposalActive();
        if (lastEnvelopeAt != 0 && block.timestamp < lastEnvelopeAt + COOLDOWN) revert CooldownActive();

        id = ++proposalCount;
        proposals[id] = Proposal({
            quote: quote,
            maxTotalBps: maxTotalBps,
            votingEndsAt: uint64(block.timestamp) + VOTING_PERIOD,
            // Voting power is frozen at the PROPOSING block, so MiFrens bought
            // or borrowed after reading this proposal carry no weight.
            //  THE PREVIOUS BLOCK, NOT THIS ONE. The comment below has always
            //  claimed power is frozen at the proposing block so MiFrens "bought
            //  or borrowed after reading this proposal carry no weight" — and
            //  `block.number` does not deliver that, because `getPastVotes` at the
            //  CURRENT block counts every transfer that lands later in the same
            //  block. A proposer could file, then acquire in the same block behind
            //  their own transaction, and vote with power the proposal was supposed
            //  to have excluded. `block.number - 1` is already sealed.
            snapshot: block.number - 1,
            forVotes: 0,
            againstVotes: 0,
            proposer: msg.sender,
            executed: false,
            cancelled: false
        });
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
        //  ── THE HINT IS MAINTAINED HERE, WHERE THE VOTE COUNTS MOVE ─────────
        //  Five cases, and the only interesting question in each is whether the
        //  invariant on `_leadId` still holds afterwards: EVERY PROPOSAL THAT IS
        //  NOT DEAD HOLDS AT MOST `_leadVotes`. Ties keep the incumbent, matching
        //  the strict `>` the scan uses.
        if (support) {
            uint256 v = p.forVotes;
            uint256 lead = _leadId;
            if (lead == id) {
                //  (1) The leader gained. It only ever grows, so everything that
                //      was under it still is.
                _leadVotes = v;
            } else if (lead == 0) {
                //  (2) The first support ever cast. Nothing else has a FOR-vote,
                //      so nothing else can be over it.
                _leadId = id;
                _leadVotes = v;
            } else if (v > _leadVotes) {
                //  (3) Overtaken. The demoted leader is now a rival the hint
                //      cannot see, and it may well outlive this vote, so date it:
                //      it is bounded by `_leadVotes < v` today, but case (4) will
                //      one day lower the bar and must not forget it existed.
                _openVotedAt = uint64(block.timestamp);
                _leadId = id;
                _leadVotes = v;
            } else if (
                _dead(proposals[lead]) &&
                block.timestamp > uint256(_openVotedAt) + VOTING_PERIOD + EXECUTION_WINDOW
            ) {
                //  (4) RETIRING A STALE HINT — the fix for S-04, and the only
                //      branch that lowers `_leadVotes`.
                //
                //      Two facts together say nothing alive can outrank `id`:
                //      the leader is dead and death is permanent; and every OTHER
                //      rival the hint never tracked was last voted at or before
                //      `_openVotedAt`, so each died at `_openVotedAt +
                //      VOTING_PERIOD + EXECUTION_WINDOW` at the latest — which is
                //      already behind us. Proposals with no FOR-votes at all sit
                //      at zero and are under `v` regardless.
                //
                //      Without this branch the hint pointed at a corpse forever
                //      and every {winner} call paid for a scan a stranger could
                //      inflate. With it, one honest vote restores the O(1) path.
                _leadId = id;
                _leadVotes = v;
            } else {
                //  (5) A live proposal the hint does not track. Date it, so a
                //      later case (4) cannot hand the lead to something smaller
                //      while this one is still executable.
                _openVotedAt = uint64(block.timestamp);
            }
        }
        if (support) _benchRecord(id, p.forVotes);
        emit Voted(id, msg.sender, support, w);
    }

    /// @dev Keep `id` on the bench if it out-weighs the weakest mandate already
    ///      there. See {_bench}. O(BENCH_SLOTS), and only on a FOR-vote.
    function _benchRecord(uint256 id, uint256 votes) private {
        uint256 weakSlot;
        uint256 weakVotes = type(uint256).max;
        for (uint256 i; i < BENCH_SLOTS; ++i) {
            uint256 b = _bench[i];
            if (b == id) return;                       // already tracked
            uint256 v;
            if (b != 0) {
                Proposal storage q = proposals[b];
                //  Anything that can never be executed again is dead weight, not
                //  a mandate — same monotone test the hint retires on.
                if (!_dead(q)) v = q.forVotes;
            }
            if (v < weakVotes) { weakVotes = v; weakSlot = i; }
        }
        if (votes > weakVotes) _bench[weakSlot] = id;
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
        //  Only the LEADER may execute. Without this, several proposals passing
        //  in the same window would let whoever executes first install their
        //  envelope regardless of which the guild preferred — turning a vote
        //  into a race.
        if (id != winner()) revert DidNotPass();
        //  And a stale winner cannot be installed months later into a market
        //  nobody voted about.
        if (block.timestamp > p.votingEndsAt + EXECUTION_WINDOW) revert VotingClosed();
        //  ── THE GATES `propose` ENFORCES MUST HOLD HERE TOO (:387-388) ──────
        //  `propose` refuses while an envelope is live and inside COOLDOWN of the
        //  last one; `execute` checked NEITHER, and `id != winner()` does not
        //  cover it. Proposals compete rather than queue, so two can pass in the
        //  same window. Execute the leader: an envelope is installed and
        //  `lastEnvelopeAt` is stamped. The loser is now the leader — the winner
        //  is executed, so `_executable` drops it — and executing THAT one
        //  overwrites the live envelope with a second mandate, with `movedBps`
        //  and `movedPrimaryBps` reset to zero. Two full envelopes' worth of the
        //  treasury moves inside one cooldown, which is precisely the budget
        //  COOLDOWN exists to bound, and the guild voted for one of them as an
        //  alternative to the other rather than in addition to it.
        //
        //  Same errors as `propose`, so a UI that already maps them needs no
        //  change. A guardian `cancel` does not reopen the window: it clears
        //  `active` but not `lastEnvelopeAt`, which is exactly how `propose`
        //  already behaves after a cancel, and an emergency stop that let a
        //  second envelope straight through would not be a stop.
        if (envelope.active && block.timestamp < envelope.expiry) revert ProposalActive();
        if (lastEnvelopeAt != 0 && block.timestamp < lastEnvelopeAt + COOLDOWN) revert CooldownActive();
        // Re-checked, because the timelock may have de-listed the asset during
        // the vote and the allowlist is the guardrail that must not be stale.
        if (!IRegistryQuotes(registry).allowedQuote(p.quote)) revert QuoteNotAllowed();
        //  Re-checked at execution for the same reason the allowlist is: a feed
        //  can be de-configured, or simply go stale, between the vote and the
        //  moment the rotation would actually move the treasury.
        _requirePriceable(p.quote);

        p.executed = true;
        envelope = Envelope({
            quote: p.quote,
            maxTotalBps: p.maxTotalBps,
            movedBps: 0,
            expiry: uint64(block.timestamp) + ENVELOPE_LIFETIME,
            active: true,
            movedPrimaryBps: 0
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

    /// @notice Hand the guardian seat to someone else.
    ///
    ///  ZERO IS REFUSED. The guardian is the SOLE caller of {cancel} (:518) and
    ///  of {setQuoteOracle}, so setting it to the zero address does not "disable
    ///  the guardian" — it dead-ends both controls permanently, with no way to
    ///  appoint a replacement because this setter is itself guardian-only. A
    ///  deployment that genuinely wants no emergency stop must say so by never
    ///  appointing one, not by burning the seat after the fact.
    function setGuardian(address g) external {
        if (msg.sender != guardian) revert NotGuardian();
        if (g == address(0)) revert BadParam();
        guardian = g;
    }

    /**
     * @notice The proposal the guild actually chose: among those whose vote has
     *         CLOSED, passed quorum, and remain executable, the one with the most
     *         support. 0 when there is none.
     *
     *  Ties break to the LOWER id — the earlier proposal — so the result is
     *  deterministic rather than dependent on iteration order.
     */
    ///  ── BOUNDED SCAN (audit: the Z-03 shape, never applied here) ────────
    ///  This looped `i = 1; i <= proposalCount` — every proposal ever filed —
    ///  and {execute} gates on `id != winner()` (:273), so the scan sits on the
    ///  ONLY path that installs an envelope. `propose` needs
    ///  {PROPOSAL_THRESHOLD} MiFrens and nothing else: {COOLDOWN} and the
    ///  `envelope.active` check gate ENVELOPES, not proposals, so one holder can
    ///  file indefinitely. Each filing permanently lengthens the loop until
    ///  `execute` cannot fit in a block — and then no rotation can ever be
    ///  installed again, for the price of gas.
    ///
    ///  `CauldronGovernor` already carries exactly this fix
    ///  ({MAX_LEADER_SCAN}, 64) for exactly this reason; it was simply never
    ///  mirrored onto the treasury side.
    ///
    ///  Bounding to the most recent {MAX_WINNER_SCAN} makes `execute` O(1) in the
    ///  proposal count. It cannot orphan a live proposal: a winner must be
    ///  executed inside {EXECUTION_WINDOW} (3 days) of its vote closing, so an
    ///  executable proposal is always among the most recent — anything older is
    ///  already stale and skipped by the `EXECUTION_WINDOW` test below.
    //  MAX_WINNER_SCAN removed: a positional bound was the wrong shape entirely.
    //  See {winner} for why the scan is bounded by TIME instead.

    function winner() public view returns (uint256 best) {
        //  FAST PATH. The hint from {vote} is trusted only after the same
        //  executability tests the scan applies, so a stale or beaten hint costs
        //  a scan rather than electing the wrong brew.
        uint256 hint = _leadId;
        if (hint != 0 && _executable(proposals[hint])) return hint;

        uint256 bestVotes;
        //  BOUNDED BY TIME, NOT BY POSITION — and the difference is a bug I put
        //  here and took back out.
        //
        //  The first version of this scanned `1..proposalCount`: unbounded, so
        //  filing enough proposals made `execute` un-runnable forever, since it
        //  gates on `id != winner()`.
        //
        //  The first FIX was a positional window (the newest 64), copied from
        //  `CauldronGovernor.MAX_LEADER_SCAN`. That reintroduced this repo's own
        //  B-10: a window over a list anyone may grow is a window anyone may
        //  flood. Measured — a genuine proposal, voted and still inside its
        //  execution window, was pushed out by 64 later filings and `winner()`
        //  returned 0. The guild's mandate was erased by spam that cost gas.
        //
        //  Walking BACKWARDS and stopping at the first proposal too old to
        //  execute is bounded without being positional. `votingEndsAt` is
        //  `block.timestamp + VOTING_PERIOD` fixed at creation and ids are
        //  chronological, so it is monotonic non-decreasing in `i` — once one is
        //  stale, every older one is too, and the loop can stop rather than
        //  `continue`.
        //
        //  What that buys: the scan spans only proposals from the last
        //  VOTING_PERIOD + EXECUTION_WINDOW (6 days). Spam still costs gas to
        //  read, but it is paid for per proposal AND it ages out — where the
        //  original was a permanent brick and the positional fix silently
        //  discarded live mandates.
        //  ...AND TIME WAS STILL NOT ENOUGH. The window above is six days wide and
        //  `propose` has no per-proposal cooldown, so a stranger can fill it. The
        //  fallback now walks the bench — eight slots, entry priced in FOR-votes —
        //  and is O(1) in the proposal count no matter what anyone files. See
        //  {_bench}.
        for (uint256 i; i < BENCH_SLOTS; ++i) {
            uint256 id = _bench[i];
            if (id == 0) continue;
            Proposal storage p = proposals[id];
            if (!_executable(p)) continue;
            if (p.forVotes > bestVotes) { bestVotes = p.forVotes; best = id; }
        }
    }

    /// @dev Can this proposal be executed right now? One definition, used by both
    ///      the cached-hint fast path and the scan, so the two can never disagree.
    function _executable(Proposal storage p) private view returns (bool) {
        if (p.votingEndsAt == 0 || p.executed || p.cancelled) return false;
        if (block.timestamp < p.votingEndsAt) return false;                  // still open
        if (block.timestamp > p.votingEndsAt + EXECUTION_WINDOW) return false; // stale
        return _passed(p);
    }

    /// @dev Can this proposal NEVER be executable again? The retirement test for a
    ///      stale hint (see case (4) in {vote}).
    ///
    ///  MONOTONE BY CONSTRUCTION, which is the only property the hint invariant
    ///  leans on: `executed` and `cancelled` are one-way flags, and the third
    ///  clause is a deadline that time only moves further past. Nothing here can
    ///  go from true back to false, so retiring a hint on it is safe.
    ///
    ///  Strictly weaker than `!_executable`: a proposal still taking votes is not
    ///  executable YET but is very much alive, and must never be treated as dead.
    ///  A nonexistent id (`votingEndsAt == 0`) reads dead, which is correct — it
    ///  can never be executed.
    function _dead(Proposal storage p) private view returns (bool) {
        if (p.executed || p.cancelled) return true;
        return block.timestamp > uint256(p.votingEndsAt) + EXECUTION_WINDOW;
    }

    // -----------------------------------------------------------------------
    // Consumed by the registry
    // -----------------------------------------------------------------------

    /// @notice The rotation the registry is currently permitted to perform.
    /// @return quote destination asset. MEANINGLESS unless `remainingBps > 0` —
    ///         `address(0)` is a LEGITIMATE destination (native ether), so it can
    ///         never be the "nothing is approved" signal. See {consume}.
    /// @return remainingBps how much of the LP may still be moved. **This is the
    ///         liveness flag**: 0 means no envelope (absent, expired or spent),
    ///         and a live envelope always reports a non-zero remainder because
    ///         the `movedBps >= maxTotalBps` case returns early.
    function allowance() public view returns (address quote, uint16 remainingBps) {
        Envelope storage e = envelope;
        if (!e.active || block.timestamp >= e.expiry) return (address(0), 0);
        //  ── A MIGRATION MANDATE REPORTS ITS OWN PROGRESS, NOT THE SHARED SUM ─
        //  `movedBps` counts EVERY slice, including ones taken out of a secondary
        //  leg by a permissionless caller who is not executing the migration. So
        //  reporting `maxTotalBps - movedBps` let a stranger spend a voted
        //  10,000-bps migration envelope entirely out of a side pool: the remainder
        //  reached 0, {consume} read that as "no envelope", the envelope
        //  deactivated, and `movedPrimaryBps` — the only counter
        //  {migrationMandateSpent} reads — was still zero. The migration could then
        //  never complete, and COOLDOWN (7 days) blocked the replacement. Gas only,
        //  repeatable at every envelope.
        //
        //  A full-position mandate therefore meters against the position it is
        //  about. Leg-to-leg rebalancing stays available under the same envelope
        //  (it is authorised, and rotating a leg home to ether is a normal move) —
        //  {consume} bounds it separately — it simply can no longer eat the budget
        //  the guild voted for the migration.
        //
        //  Partial envelopes are unchanged: below a whole position there is no
        //  migration to protect and one shared budget is the honest accounting.
        uint16 spent = e.maxTotalBps >= BPS_ONE ? e.movedPrimaryBps : e.movedBps;
        if (spent >= e.maxTotalBps) return (address(0), 0);
        return (e.quote, e.maxTotalBps - spent);
    }

    /// @notice Did the guild's mandate cover the WHOLE position, and is it spent?
    ///
    ///  ── WHY REDENOMINATION NEEDS ITS OWN TEST (red-team R-04) ──────────────
    ///  Consumers used to read "the envelope has no allowance left" as "the
    ///  rotation finished", and re-denominated the generation on it. But
    ///  `maxTotalBps` is how much the guild VOTED to move, not how much of the LP
    ///  exists: a fully-spent 2500-bps mandate left ~76% of the pair in the old
    ///  asset and still flipped the generation's quote. Measured, pre-fix.
    ///
    ///  A mandate that budgets less than the whole position is PARTIAL by
    ///  construction and must never redenominate. Only one that budgeted at least
    ///  the entire position (>= BPS) can be said to have migrated the generation.
    ///
    ///  HONEST ABOUT THE UNIT: slices are a share of CURRENT liquidity, so budget
    ///  bps compound rather than sum to a clean fraction — 12 slices of 2500 move
    ///  ~96.8%, not 300%. This therefore tests INTENT (did the guild authorise
    ///  moving the whole position?) plus exhaustion, and a small tail can remain
    ///  in the old pair. Relaunch handles that tail explicitly rather than
    ///  assuming it away; see {CauldronRegistry.relaunch}'s `oldQuote`.
    ///
    ///  ── AND THE BPS MUST HAVE COME OUT OF THE POSITION BEING MIGRATED ──────
    ///  `movedBps` counts every slice, but `rotateSliceFrom` lets a
    ///  PERMISSIONLESS caller choose WHICH LEG a slice comes out of, and bps of a
    ///  0.1% dust leg are not bps of the treasury. Testing `movedBps` therefore
    ///  let a stranger spend a whole migration mandate against a leg the mandate
    ///  was not about and redenominate the generation with the primary pair
    ///  untouched. `movedPrimaryBps` counts only what left the generation's own
    ///  position, which is the unit the "did the whole position move" question
    ///  was always assuming. Secondary legs remain rotatable under the same
    ///  envelope — that is rebalancing, and it is authorised — they simply
    ///  cannot be what declares the migration complete.
    function migrationMandateSpent() external view returns (bool) {
        Envelope storage e = envelope;
        return e.maxTotalBps >= BPS_ONE && e.movedPrimaryBps >= e.maxTotalBps;
    }

    /// @dev One whole position, in bps. Named rather than inlined so the
    ///      "did the mandate cover everything" test reads as intent.
    uint16 internal constant BPS_ONE = 10_000;

    /// @notice Record a slice against the envelope. Registry-only: it is the
    ///         contract that actually moves the liquidity, so it is the only one
    ///         that may say how much has moved.
    /// @param  bps         share of the SOURCE leg this slice moved.
    /// @param  fromPrimary whether the source was the generation's own position.
    ///                     Only these advance {migrationMandateSpent} — bps of a
    ///                     secondary leg are not bps of the generation.
    function consume(uint16 bps, bool fromPrimary) external {
        if (msg.sender != registry) revert NotGuardian();
        Envelope storage e = envelope;
        (, uint16 left) = allowance();
        //  ── `left`, NOT `quote`, IS THE LIVENESS TEST (red-team R-03) ───────
        //  This read `q == address(0)` as "nothing approved". address(0) is also
        //  how a rotation BACK TO NATIVE ETHER names its destination, so a
        //  perfectly valid envelope was indistinguishable from no envelope and
        //  every slice of it reverted. `allowance` already returns 0 remaining
        //  for all three no-envelope cases, so the remainder is the honest flag.
        if (left == 0) revert BadParam();
        //  ── AND A SECONDARY LEG SPENDS ITS OWN BUDGET, NOT THE MIGRATION'S ──
        //  `left` is now the budget for the thing this slice actually is (see
        //  {allowance}). A primary slice is bounded by it. A secondary slice is
        //  bounded by the SHARED total instead, so leg-to-leg rebalancing is still
        //  capped by what the guild voted and still cannot run forever — it just
        //  cannot starve the migration, because the primary's remaining budget is
        //  tracked separately and nothing a stranger does reduces it.
        //
        //  Reachable, narrowly, which is why this was a High and not a Critical:
        //  `_recordLeg` upserts by quote and `fromQuote == toQuote` reverts
        //  BadConfig, so a secondary leg in a DIFFERENT quote must already exist. A
        //  generation's FIRST migration could not be starved; every one after it
        //  could.
        uint16 cap = e.maxTotalBps;
        if (fromPrimary) {
            if (bps > left) revert BadParam();
        } else if (e.movedBps >= cap || bps > cap - e.movedBps) {
            revert BadParam();
        }
        e.movedBps += bps;
        if (fromPrimary) e.movedPrimaryBps += bps;
        //  ── A SPENT ENVELOPE MUST STOP BLOCKING GOVERNANCE (red-team R-05) ──
        //  `propose` refuses while `envelope.active && now < expiry` (:322), and
        //  nothing cleared `active` on exhaustion — only the guardian's `cancel`
        //  (:409) ever did. So a mandate spent in its first hour locked out every
        //  new treasury proposal until it EXPIRED, 30 days on mainnet defaults,
        //  leaving the guild unable to even FILE a correction to a bad rotation.
        //  `allowance()` already reported this envelope as finished; this makes
        //  the stored state agree with what it reports.
        //  DEACTIVATION FOLLOWS THE SAME COUNTER {allowance} REPORTS: a migration
        //  envelope is finished when the MIGRATION is finished, not when a stranger
        //  has spent the shared total on side pools.
        if (cap >= BPS_ONE ? e.movedPrimaryBps >= cap : e.movedBps >= cap) e.active = false;
        emit EnvelopeConsumed(bps, e.movedBps);
    }

    // -----------------------------------------------------------------------

    function _passed(Proposal storage p) private view returns (bool) {
        if (p.forVotes <= p.againstVotes) return false;
        // Quorum on TOTAL supply rather than turnout: a low-turnout vote should
        // fail rather than let a handful of holders move the treasury.
        //
        // Read at the PROPOSAL'S SNAPSHOT, the same timepoint `vote` weighs
        // ballots against (:384). Reading a live supply here would have let
        // anyone move the bar under a vote already in progress — and, more
        // bluntly, the live getter this used to call does not exist on the
        // contract that is actually wired (see {IVotes721.getPastTotalSupply}),
        // so every quorum read reverted and no proposal could ever execute.
        uint256 need = (mifrens.getPastTotalSupply(p.snapshot) * QUORUM_BPS) / 10_000;
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
    /**
     * @notice Refuse a quote the oracle cannot value.
     *
     *  ── WHY A ROTATION TARGET MUST BE PRICEABLE ────────────────────────────
     *  Allowlisting and pricing were independent, and nothing joined them. The
     *  registry's `setQuoteAllowed` validates that a quote sorts below the token
     *  (so `quote == currency0` holds) and nothing else — so an asset could be
     *  approved, voted in, and become a generation's base while the oracle had
     *  no feed for it.
     *
     *  The result is not a revert. `CauldronHook._toUsd` returns 0 for an
     *  unpriceable asset, and 0 means CANNOT JUDGE: `_recordVolume` writes
     *  nothing, no bucket, no cumulative total, no crystal credit. A generation
     *  rotated onto that quote therefore trades normally while recording NO
     *  volume, and after the 24h grace window built into that path it reads as
     *  dying — a silent, slow failure with no error anywhere to explain it.
     *
     *  Checking it HERE is the cheapest honest place: it is the moment an asset
     *  is first named as a rotation target, the caller is a human at a UI who
     *  can be told why, and this contract has the room (the hook has ~68 bytes
     *  of EIP-170 margin and the registry ~81).
     *
     *  NATIVE IS EXEMPT. address(0) is the fallback quote every generation can
     *  always launch against, and refusing it because a feed lapsed would strand
     *  the treasury with nowhere to rotate BACK to — turning a price outage into
     *  a governance deadlock. Volume for a native generation is what the
     *  unwired-oracle case already measures, so it degrades to the old behaviour
     *  rather than to nothing.
     *
     *  UNSET ORACLE IS ALSO EXEMPT, for the same don't-brick reason: a
     *  deployment that never wires one is measuring volume in raw quote units
     *  throughout, which is self-consistent. The check binds only where there IS
     *  an oracle and it declines to price the asset.
     */
    function _requirePriceable(address quote) internal view {
        if (quote == address(0)) return;
        address o = quoteOracle;
        if (o == address(0)) return;
        if (IQuotePrice(o).usdPerRawUnit(quote) == 0) revert QuoteNotPriceable();
    }

    /// @notice Oracle used to check a rotation target can be valued. Timelock-set,
    ///         and unset means the check is skipped (see {_requirePriceable}).
    function setQuoteOracle(address o) external {
        if (msg.sender != guardian) revert NotGuardian();
        quoteOracle = o;
        emit QuoteOracleSet(o);
    }

}
