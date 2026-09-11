// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PerpMarkSource
 * @notice The liquidity-weighted tick for a generation's perp mark — the piece
 *         that lets a generation run SEVERAL POOLS *and* perps at once.
 *
 *  ── THE PROBLEM THIS EXISTS FOR (audit P-1 / Q-07) ────────────────────────
 *  {PerpEngine} marks, sizes and liquidates off `_sqrtP()`, which reads `slot0`
 *  of the ONE pool built from `registry.generationQuote(gen)`. With one pool that
 *  is the same thing as "the market". With two it is not, and the dangerous
 *  direction is not the obvious one: bounding position size against a thinning
 *  primary fails SAFE (positions get smaller), but the MARK does not. A pool that
 *  has lost its liquidity to a sibling is precisely the CHEAP one to push, while
 *  the deep sibling sets the price everyone actually trades at — so liquidations
 *  fire from inside `afterSwap` against a mark the market does not agree with.
 *
 *  The protocol's answer until now was an interlock: a generation may run several
 *  pools, OR it may run perps. This removes the need for that rule by fixing the
 *  property it was working around.
 *
 *  ── WHY WEIGHTING BY LIQUIDITY IS THE SAFE DIRECTION ──────────────────────
 *  The mark becomes `Σ(tickᵢ × Lᵢ) / Σ(Lᵢ)`. The pool that is cheapest to push is
 *  by construction the pool with the least weight in it, so the attack that
 *  motivated the interlock gets strictly worse as the split gets more lopsided —
 *  the opposite of the current behaviour, where a thinning primary becomes MORE
 *  authoritative. It also composes with the existing defences rather than
 *  replacing them: this feeds `_currentTick()`, so every sample still goes
 *  through the engine's TWAP ring and the A-02 `_writeObs` fix. A flash move in
 *  any single pool is still time-averaged away.
 *
 *  ── THE ORIENTATION RULE, ENFORCED RATHER THAN DOCUMENTED ─────────────────
 *  A tick is `log₁.₀₀₀₁` of currency1 priced in currency0. Two pools' ticks are
 *  therefore only comparable when they share BOTH currencies in the SAME order —
 *  an ETH-quoted tick and a USDG-quoted tick measure different things and
 *  averaging them is meaningless, not merely imprecise.
 *
 *  Making cross-quote marks comparable needs a USD normalisation, i.e. an ORACLE
 *  on the liquidation path. That is deliberately NOT done here. Liquidations are
 *  irreversible, and {QuoteOracle}'s own header argues the fail-safe direction
 *  for an irreversible decision — a price that is merely late would liquidate
 *  solvent positions with no way to undo it. So {addPool} REVERTS on a pool whose
 *  currency pair differs from the primary's. Same-quote depth splitting (a second
 *  fee tier, a second tick spacing) is the case that actually splits liquidity,
 *  and it is handled exactly. Cross-quote marking is left for a later phase that
 *  can argue the oracle risk on its own merits.
 *
 *  ── FAIL-SOFT BY CONSTRUCTION ─────────────────────────────────────────────
 *  With no pools registered, one pool registered, or no in-range liquidity
 *  anywhere, this returns the PRIMARY's tick — exactly today's behaviour. The
 *  engine additionally treats a revert or a malformed answer here as "use the
 *  primary", so wiring this can never be worse than not wiring it.
 */
contract PerpMarkSource is Ownable {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager public immutable poolManager;

    /// @notice The generation's PRIMARY pool — the one {PerpEngine._key()}
    ///         builds and the fallback whenever a weighted answer is unavailable.
    PoolKey public primary;
    /// @notice Whether {primary} has been set at all.
    bool public armed;

    /// @notice Additional pools whose depth counts toward the mark.
    PoolKey[] public pools;

    /// @dev The mark is read inside `afterSwap` (via `_writeObs`) on EVERY swap,
    ///      so this loop is on the hottest path in the protocol. Four extra pools
    ///      is already a wider split than a treasury would plausibly run, and it
    ///      keeps the worst case at five `slot0` + five `getLiquidity` reads.
    uint256 public constant MAX_POOLS = 4;

    error NotArmed();
    error PoolCapped();
    error WrongPair();
    error AlreadyAdded();
    error OwnershipCannotBeRenounced();

    /// @notice Ownership of the mark source CANNOT be renounced.
    ///
    ///  Its entire owner surface IS the mark configuration — {setPrimary},
    ///  {addPool}, {removePool}. A renounce pins the weighted mark to whatever
    ///  pools happen to be registered at that instant, and the mark is what
    ///  {PerpEngine} liquidates against. After a quote rotation the generation
    ///  trades against a DIFFERENT pool, so re-pointing the primary is exactly
    ///  the operation that would be needed and exactly the one that would be
    ///  gone. Fail-soft does not save it either: the stale pools still answer, so
    ///  the engine keeps trusting a mark for a pair it no longer trades.
    function renounceOwnership() public pure override {
        revert OwnershipCannotBeRenounced();
    }
    error NotFound();

    event PrimarySet(PoolId indexed id);
    event PoolAdded(PoolId indexed id);
    event PoolRemoved(PoolId indexed id);

    constructor(IPoolManager _poolManager, address _owner) Ownable(_owner) {
        poolManager = _poolManager;
    }

    /// @notice Point the mark at a generation's primary pool. Called on each
    ///         relaunch; clears the sibling set, because a new generation's pools
    ///         have nothing to do with the old one's.
    function setPrimary(PoolKey calldata key) external onlyOwner {
        primary = key;
        armed = true;
        delete pools;
        emit PrimarySet(key.toId());
    }

    /// @notice Register a sibling pool whose depth should count toward the mark.
    /// @dev Refuses any pool that is not the SAME currency pair in the SAME
    ///      order as the primary — see the orientation rule above. This is the
    ///      check that keeps an oracle off the liquidation path.
    function addPool(PoolKey calldata key) external onlyOwner {
        if (!armed) revert NotArmed();
        if (pools.length >= MAX_POOLS) revert PoolCapped();
        if (
            Currency.unwrap(key.currency0) != Currency.unwrap(primary.currency0)
                || Currency.unwrap(key.currency1) != Currency.unwrap(primary.currency1)
        ) revert WrongPair();

        bytes32 id = PoolId.unwrap(key.toId());
        if (id == PoolId.unwrap(primary.toId())) revert AlreadyAdded();
        uint256 n = pools.length;
        for (uint256 i; i < n; ++i) {
            if (PoolId.unwrap(pools[i].toId()) == id) revert AlreadyAdded();
        }
        pools.push(key);
        emit PoolAdded(key.toId());
    }

    /// @notice Retire a sibling from the mark (e.g. its liquidity has gone).
    ///         Safe at any time: dropping a pool only narrows what the mark
    ///         averages, and the primary is never removable.
    function removePool(PoolKey calldata key) external onlyOwner {
        bytes32 id = PoolId.unwrap(key.toId());
        uint256 n = pools.length;
        for (uint256 i; i < n; ++i) {
            if (PoolId.unwrap(pools[i].toId()) == id) {
                pools[i] = pools[n - 1];
                pools.pop();
                emit PoolRemoved(key.toId());
                return;
            }
        }
        revert NotFound();
    }

    function poolCount() external view returns (uint256) { return pools.length; }

    /**
     * @notice The liquidity-weighted tick across the generation's pools.
     *
     *  Zero-argument on purpose: {PerpEngine} calls this from inside a `view` on
     *  the hot path, and every byte of calldata encoding is bytecode the engine
     *  does not have to spare. This contract knows its own pool set.
     *
     * @return tick `Σ(tickᵢ × Lᵢ) / Σ(Lᵢ)` over pools with in-range liquidity,
     *         falling back to the primary's tick when nothing is weighable.
     */
    function weightedTick() external view returns (int24 tick) {
        if (!armed) return 0;
        PoolKey memory p = primary;
        int24 primaryTick;
        (, primaryTick,,) = poolManager.getSlot0(p.toId());

        uint256 n = pools.length;
        if (n == 0) return primaryTick;

        //  int256 accumulator: a tick is bounded by ±887272 and liquidity by
        //  2^128, so the product cannot overflow int256 and the sum over five
        //  pools cannot either.
        uint256 totalL = poolManager.getLiquidity(p.toId());
        int256 acc = int256(primaryTick) * int256(uint256(totalL));

        for (uint256 i; i < n; ++i) {
            PoolId id = pools[i].toId();
            uint128 l = poolManager.getLiquidity(id);
            if (l == 0) continue; // a pool with no in-range depth sets no price
            (, int24 t,,) = poolManager.getSlot0(id);
            acc += int256(t) * int256(uint256(l));
            totalL += l;
        }

        //  Nothing in range anywhere — every pool is a knife-edge. The primary's
        //  tick is still the best available answer and is what the engine used
        //  before this contract existed.
        if (totalL == 0) return primaryTick;
        tick = int24(acc / int256(totalL));
    }
}
