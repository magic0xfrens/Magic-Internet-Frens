// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title MockAggregator
 * @notice A Chainlink-shaped price feed for TESTNET assets that have no real one.
 *
 *  ── WHY THIS IS HONEST AND A MAINNET MOCK FEED WOULD NOT BE ───────────────
 *  `QuoteOracle` refuses to price anything it has no feed for, which is the safe
 *  default — but it means a testnet deployment can never exercise the priced
 *  path at all: the treasury panel shows amounts with no shares, the USD volume
 *  accounting is bypassed, and death detection reads every pool as unpriceable.
 *  Half the system goes untested precisely because the assets are fake.
 *
 *  The assets ARE fake. `MockQuoteToken` USDG is a mintable 6-decimal token
 *  whose only claim to being worth a dollar is that the deployer says so — so a
 *  feed that says "one dollar" is not a fabrication, it is an accurate model of
 *  a mock. What would be dishonest is pointing this at a mainnet asset whose
 *  price is discovered by a market, and {peg} exists to make that impossible to
 *  do by accident: it is owner-only and every price is set explicitly.
 *
 *  ETH does NOT use this. Sepolia carries a real Chainlink ETH/USD aggregator
 *  (0x694AA1769357215DE4FAC081bf1f309aDC325306), and the deploy points at it, so
 *  the one asset with genuine price discovery on testnet keeps it.
 *
 *  ── ALWAYS FRESH, ON PURPOSE ──────────────────────────────────────────────
 *  `updatedAt` returns `block.timestamp` rather than the moment {peg} was
 *  called. A fixed timestamp would go stale within the heartbeat and the oracle
 *  would correctly refuse it, which is the failure this contract exists to
 *  avoid — a testnet feed nobody keeps poking is a feed that stops working
 *  overnight. Staleness handling is exercised by {setStale} and by the unit
 *  suites, not by letting the fixture rot.
 */
contract MockAggregator {
    error NotOwner();

    address public owner;
    /// @notice Chainlink USD feeds use 8 decimals; matching them means the
    ///         oracle's normalisation path is the same one mainnet will take.
    uint8 public constant decimals = 8;
    string public description;

    int256 private _answer;
    uint80 private _round = 1;
    /// @dev When true, report a timestamp far in the past so the consumer's
    ///      staleness branch can be exercised against a live deployment.
    bool public stale;
    /// @dev When true, revert instead of answering — the failure mode that
    ///      bypassed the oracle's cache before it was made total.
    bool public down;

    event Pegged(int256 answer);

    constructor(string memory desc, int256 initialAnswer) {
        owner = msg.sender;
        description = desc;
        _answer = initialAnswer;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function transferOwnership(address to) external onlyOwner { owner = to; }

    /// @notice Set the price, in 8 decimals ($1.00 = 1e8).
    function peg(int256 answer) external onlyOwner {
        _answer = answer;
        _round += 1;
        emit Pegged(answer);
    }

    /// @notice Make this feed read stale, so a deployment can exercise the
    ///         consumer's "cannot judge" branch without waiting out a heartbeat.
    function setStale(bool s) external onlyOwner { stale = s; }

    /// @notice Make this feed REVERT rather than answer. A retired or migrated
    ///         aggregator behaves this way, and it is the case that used to
    ///         propagate out of `QuoteOracle.cachedUsdPerRawUnit` and bypass the
    ///         cached price entirely.
    function setDown(bool d) external onlyOwner { down = d; }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        require(!down, "feed: down");
        // 1 = the epoch, which is unambiguously outside any sane heartbeat.
        uint256 ts = stale ? 1 : block.timestamp;
        return (_round, _answer, ts, ts, _round);
    }
}
