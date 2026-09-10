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
        /// @notice PEGGED: price this asset at exactly $1 and consult no feed.
        ///
        ///  For a dollar stablecoin the feed answers ~1.0000 and the only thing
        ///  it can realistically contribute is a way to FAIL. Sepolia proved it:
        ///  the USDC/USD feed drifted 23.7h against a 12h heartbeat, the oracle
        ///  correctly reported "cannot judge", and a USDG generation would have
        ///  recorded no volume at all — a live outage caused entirely by asking
        ///  a question whose answer was never in doubt.
        ///
        ///  What genuinely needs an oracle is ETH/USD, which moves. A peg cannot
        ///  go stale, cannot be manipulated and cannot revert.
        ///
        ///  THE TRADE, STATED: a depeg is not tracked. That is acceptable here
        ///  and would not be for collateral — this factor denominates VOLUME
        ///  (death, crystal credit, spin odds), so a 2% depeg mis-measures
        ///  volume by 2%. It cannot make the protocol insolvent, and it is
        ///  strictly better than the alternative that was live: a stale feed
        ///  measuring volume as ZERO.
        bool pegged;
        /// @notice Sanity band on the feed's answer, in whole USD 1e18. An
        ///         answer outside it is treated as unusable rather than
        ///         believed. Zero on either side disables that side.
        uint128 minUsd;
        uint128 maxUsd;
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
    event BoundsSet(address indexed quote, uint128 minUsd, uint128 maxUsd);

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
        Feed storage ex = feeds[quote];
        feeds[quote] = Feed(IAggregatorV3(aggregator), heartbeat, dec, false, ex.minUsd, ex.maxUsd);
        emit FeedSet(quote, aggregator, heartbeat, dec);
    }

    /**
     * @notice Price `quote` at exactly $1, consulting no feed.
     *
     *  For a dollar stablecoin this removes the only thing the feed could
     *  contribute, which is a failure mode. See {Feed.pegged} for the trade.
     *
     * @param dec decimals of the token; pass 0 to read them from the contract.
     */
    function setPegged(address quote, uint8 dec) external onlyOwner {
        uint8 d = dec;
        if (d == 0) d = quote == address(0) ? 18 : IERC20Decimals(quote).decimals();
        //  heartbeat 1 is a non-zero placeholder: nothing reads it on the pegged
        //  path, and zero is the struct's "unconfigured" sentinel elsewhere.
        feeds[quote] = Feed(IAggregatorV3(address(0)), 1, d, true, 0, 0);
        emit FeedSet(quote, address(0), 1, d);
    }

    /**
     * @notice Refuse a feed answer outside [minUsd, maxUsd], in whole USD 1e18.
     *
     *  A stale feed is caught by the heartbeat and a dead one by the try/catch,
     *  but a feed that is fresh, responsive and WRONG passes both. That is the
     *  case with teeth here: this factor scales recorded volume, and volume mints
     *  NFTs that earn a perpetual dividend — so an answer of $10m/ETH would issue
     *  the collection against trades that never happened. The band turns a
     *  mispriced feed into "cannot judge", which the hook already handles by
     *  recording nothing rather than recording a fiction.
     *
     *  Zero on either side leaves that side open.
     */
    function setBounds(address quote, uint128 minUsd, uint128 maxUsd) external onlyOwner {
        if (maxUsd != 0 && minUsd > maxUsd) revert BadConfig();
        feeds[quote].minUsd = minUsd;
        feeds[quote].maxUsd = maxUsd;
        emit BoundsSet(quote, minUsd, maxUsd);
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
        //  PEGGED: $1 per whole token, converted to per raw unit at the token's
        //  own decimals. No aggregator, so nothing here can go stale, revert or
        //  be manipulated — the failure modes below simply do not exist for it.
        if (f.pegged) return 1e18 * 1e18 / (10 ** f.quoteDecimals);
        if (address(f.aggregator) == address(0)) return 0;
        if (!_sequencerOk()) return 0;

        //  ── A FEED CAN REVERT, NOT ONLY GO STALE ────────────────────────────
        //  The three unusable conditions above are all cases where the feed
        //  ANSWERS and the answer is no good. A feed can also fail by not
        //  answering at all: a retired or migrated aggregator, an
        //  access-controlled one, or simply an address with no code behind it
        //  (a high-level call to a codeless address reverts on the extcodesize
        //  check). None of those returned 0 — they threw, straight through this
        //  function and out of {cachedUsdPerRawUnit}, which is a `view` called
        //  via `this.` and so propagates.
        //
        //  That mattered because it bypassed the cache. A STALE feed degrades
        //  to 0, and the cache below keeps the last good factor; a REVERTING
        //  feed never reached that line, so the caller saw a failure instead of
        //  a price. `CauldronHook._toUsd` turns that failure into a 0 volume
        //  contribution, and volume is what `isDead` judges — so a feed that
        //  broke by reverting pushed a live generation toward a permissionless,
        //  irreversible relaunch, while the identical feed going stale did not.
        //  Same real-world condition, opposite outcomes.
        int256 answer;
        uint256 updatedAt;
        try f.aggregator.latestRoundData() returns (
            uint80, int256 a, uint256, uint256 u, uint80
        ) {
            answer = a;
            updatedAt = u;
        } catch {
            return 0;
        }
        if (answer <= 0) return 0;
        // A feed that has stopped updating still answers, and its answer looks
        // perfectly valid — which is what makes staleness worth checking.
        // `updatedAt` in the FUTURE is also refused rather than subtracted:
        // `block.timestamp - updatedAt` is checked arithmetic, so a feed with a
        // skewed clock would have reverted here too.
        if (updatedAt == 0 || updatedAt > block.timestamp) return 0;
        if (block.timestamp - updatedAt > f.heartbeat) return 0;

        uint8 feedDec;
        try f.aggregator.decimals() returns (uint8 d) {
            feedDec = d;
        } catch {
            return 0;
        }
        // The feed reports USD per WHOLE token at its own decimals. Normalise
        // that to 1e18 first...
        uint256 perWhole = feedDec <= 18
            ? uint256(answer) * (10 ** (18 - feedDec))
            : uint256(answer) / (10 ** (feedDec - 18));

        //  A FRESH, RESPONSIVE, WRONG ANSWER passes every check above. The
        //  heartbeat catches a stale feed and the try/catch catches a dead one,
        //  but neither notices an aggregator reporting ETH at $10m. This factor
        //  scales recorded volume, and volume mints NFTs that earn a perpetual
        //  dividend — so believing that answer issues the collection against
        //  trades that never happened. Out of band becomes "cannot judge", which
        //  the hook already handles by recording nothing rather than a fiction.
        if (f.minUsd != 0 && perWhole < f.minUsd) return 0;
        if (f.maxUsd != 0 && perWhole > f.maxUsd) return 0;

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
        // The uptime feed is a feed like any other and can refuse to answer.
        // Treat that as "cannot confirm the sequencer is healthy" — which makes
        // the price unusable, which keeps the cached factor, which keeps volume
        // recording. Failing toward ALIVE, the same direction as everything else
        // here, because death cannot be undone.
        try s.latestRoundData() returns (
            uint80, int256 up, uint256 startedAt, uint256, uint80
        ) {
            // 0 = up, 1 = down.
            if (up != 0) return false;
            // A startedAt in the future would underflow the subtraction below,
            // which is checked arithmetic — refuse rather than revert.
            if (startedAt == 0 || startedAt > block.timestamp) return false;
            // Just back up: prices are still catching up, and the backlog of
            // stale-priced transactions clears in this window.
            return block.timestamp - startedAt > gracePeriod;
        } catch {
            return false;
        }
    }

}
