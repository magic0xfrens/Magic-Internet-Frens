// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

/**
 * @title QuoteOracle
 * @notice Turns "how much volume" into a number that means the same thing in
 *         every pool: US dollars.
 *
 *  Volume is measured on the quote side, so a generation trading in both ETH and
 *  a 6-decimal stable produces two figures that differ by 1e12 before any price
 *  difference. Everything downstream then breaks in a way that looks like data
 *  rather than a bug: death detection sums them, and a fren's mint-out cost
 *  depends on which pool you happened to trade in.
 *
 *  Denominating in USD fixes both at once. A fren costs $X of volume wherever it
 *  was generated, and a generation is dead when it does less than $Y a day
 *  across ALL its pools.
 *
 *  ── Why an oracle here, having argued against one ─────────────────────────
 *  I previously used a governance-set scalar and defended it. That was wrong,
 *  and the reason I gave — "an oracle on death detection is a manipulation
 *  surface" — conflated two different things. Deriving a price from our OWN thin
 *  pools is manipulable; a Chainlink feed aggregated off-chain from many venues
 *  is not, and no flash loan touches it. The governance scalar's actual property
 *  was not safety, it was staleness: set when ETH was $3,000 it is 2x wrong at
 *  $6,000, and nothing corrects it.
 *
 *  What remains true is that death is IRREVERSIBLE — relaunch is permissionless.
 *  So the failure mode is chosen deliberately: when a price is unusable this
 *  returns 0, and callers must treat 0 as "cannot judge" rather than "no
 *  volume". Failing toward ALIVE is the only safe direction when the wrong
 *  answer cannot be undone.
 *
 *  ── What "unusable" means ──────────────────────────────────────────────────
 *  Three conditions, all of which have caused real losses elsewhere:
 *
 *    1. NO FEED configured for that quote.
 *    2. STALE — no update within the feed's heartbeat. A frozen feed reporting a
 *       months-old price is worse than no feed, because it looks fine.
 *    3. SEQUENCER DOWN, or up for less than the grace period. On an L2 the feed
 *       cannot update while the sequencer is down, so every price is stale by
 *       definition; the grace period exists because the moment it returns there
 *       is a backlog of stale-priced transactions to clear.
 */
contract QuoteOracle {
    error NotOwner();
    error BadConfig();

    struct Feed {
        IAggregatorV3 aggregator;
        /// Seconds after which an answer is considered stale. Chainlink
        /// publishes a heartbeat per feed; this should match it, with headroom.
        uint32 heartbeat;
        /// Decimals of the QUOTE TOKEN itself (not the feed) — 18 for ETH, 6 for
        /// most stables. Stored rather than read per call, since a token cannot
        /// change its decimals and the read would be pure overhead.
        uint8 quoteDecimals;
    }

    address public owner;
    mapping(address => Feed) public feeds;

    /// @notice L2 sequencer uptime feed. Unset on an L1, where the concept does
    ///         not apply and the check is skipped.
    IAggregatorV3 public sequencerUptime;
    /// @notice How long the sequencer must have been back before answers are
    ///         trusted again.
    uint32 public gracePeriod = 3600;

    event FeedSet(address indexed quote, address aggregator, uint32 heartbeat, uint8 quoteDecimals);
    event SequencerSet(address feed, uint32 gracePeriod);

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function transferOwnership(address to) external onlyOwner { owner = to; }

    /**
     * @notice Point a quote asset at its price feed.
     * @dev Owner-only, and the owner is the timelock. This deliberately sits
     *      beside the allowlist in the trust model: choosing which assets exist
     *      and choosing how they are priced are the same decision, and neither
     *      is votable — a vote that could set its own feed could price anything
     *      at anything.
     * @param quoteDecimals decimals of the TOKEN. Native ETH is 18; pass 0 to
     *        read it from the contract.
     */
    function setFeed(address quote, address aggregator, uint32 heartbeat, uint8 quoteDecimals)
        external
        onlyOwner
    {
        if (heartbeat == 0) revert BadConfig();
        uint8 dec = quoteDecimals;
        if (dec == 0) {
            dec = quote == address(0) ? 18 : IERC20Decimals(quote).decimals();
        }
        feeds[quote] = Feed(IAggregatorV3(aggregator), heartbeat, dec);
        emit FeedSet(quote, aggregator, heartbeat, dec);
    }

    function setSequencer(address feed, uint32 grace) external onlyOwner {
        sequencerUptime = IAggregatorV3(feed);
        gracePeriod = grace;
        emit SequencerSet(feed, grace);
    }

    // -----------------------------------------------------------------------

    /**
     * @notice USD value of ONE RAW UNIT of `quote`, scaled by 1e18.
     *
     *  Raw unit rather than whole token on purpose: volume arrives as raw
     *  amounts, so the caller multiplies and divides once —
     *  `usdVolume = rawVolume * factor / 1e18` — with no decimals handling at
     *  the call site. Getting decimals wrong at each call site is exactly the
     *  bug this exists to remove.
     *
     * @return factor 0 when the price is unusable. Callers MUST treat 0 as
     *         "cannot judge", never as "zero volume".
     */
    function usdPerRawUnit(address quote) external view returns (uint256 factor) {
        Feed memory f = feeds[quote];
        if (address(f.aggregator) == address(0)) return 0;
        if (!_sequencerOk()) return 0;

        (, int256 answer,, uint256 updatedAt,) = f.aggregator.latestRoundData();
        if (answer <= 0) return 0;
        // A feed that has stopped updating still answers, and its answer looks
        // perfectly valid — which is what makes staleness worth checking.
        if (updatedAt == 0 || block.timestamp - updatedAt > f.heartbeat) return 0;

        uint8 feedDec = f.aggregator.decimals();
        // The feed reports USD per WHOLE token at its own decimals. Normalise
        // that to 1e18 first...
        uint256 perWhole = feedDec <= 18
            ? uint256(answer) * (10 ** (18 - feedDec))
            : uint256(answer) / (10 ** (feedDec - 18));

        //  ...then convert to per RAW unit, keeping the 1e18 scale.
        //
        //  The 1e18 must be applied BEFORE dividing by the token's units, not
        //  after: dividing first floors the result to an integer number of
        //  dollars per wei, which is zero for every real asset. My first version
        //  did exactly that and reported 1 ETH as "$3000 / 1e18" — the scale was
        //  in the comment and not in the arithmetic.
        factor = (perWhole * 1e18) / (10 ** f.quoteDecimals);
    }

    struct Cached { uint256 factor; uint64 at; }
    mapping(address => Cached) public cache;

    /// @dev How long a cached price stays good.
    uint64 public constant TTL = 15 minutes;

    /**
     * @notice Same as {usdPerRawUnit}, but cached — and the caching lives HERE
     *         rather than in the caller.
     *
     *  A Chainlink read costs ~30k gas (measured against the live Sepolia
     *  feeds). Paying that on every swap is roughly a 15% tax on trading for a
     *  number that does not need to be minute-fresh: volume feeds a 24-hour
     *  death window and a cumulative mint-out counter, where a fifteen-minute-old
     *  price is indistinguishable from a current one.
     *
     *  Caching in the oracle rather than in the hook is deliberate twice over.
     *  The hook is against the EIP-170 ceiling and has no room for the mappings,
     *  and every consumer of a price wants the same amortisation — so putting it
     *  here means none of them has to implement it again.
     *
     *  A refresh that comes back unusable keeps the LAST GOOD value. For volume
     *  accounting a stale price is far better than a zero, because zero reads as
     *  "no trading" and would push a live generation toward death.
     */
    function cachedUsdPerRawUnit(address quote) external returns (uint256) {
        Cached storage c = cache[quote];
        if (block.timestamp <= c.at + TTL && c.factor != 0) return c.factor;
        uint256 fresh = this.usdPerRawUnit(quote);
        c.at = uint64(block.timestamp);
        if (fresh > 0) c.factor = fresh;
        return c.factor;
    }

    /// @notice Whether `quote` can be priced right now. Exposed so a caller can
    ///         distinguish "unpriced" from "worth nothing" without a second call.
    function priceable(address quote) external view returns (bool) {
        return this.usdPerRawUnit(quote) > 0;
    }

    function _sequencerOk() internal view returns (bool) {
        IAggregatorV3 s = sequencerUptime;
        if (address(s) == address(0)) return true; // L1: not applicable
        (, int256 up, uint256 startedAt,,) = s.latestRoundData();
        // 0 = up, 1 = down.
        if (up != 0) return false;
        // Just back up: prices are still catching up, and the backlog of
        // stale-priced transactions clears in this window.
        return startedAt != 0 && block.timestamp - startedAt > gracePeriod;
    }

}
