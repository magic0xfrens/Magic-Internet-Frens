// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CauldronHook} from "../../CauldronHook.sol";
import {PoolOps, IPositionManagerOps} from "../../cauldron/PoolOps.sol";
import {QuoteOracle} from "../../cauldron/QuoteOracle.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";

contract Stable6 is IERC20 {
    string public constant name = "Stable";
    string public constant symbol = "USDG";
    uint8 public constant decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 a) external { balanceOf[to] += a; totalSupply += a; }
    function transfer(address to, uint256 a) external returns (bool) { balanceOf[msg.sender] -= a; balanceOf[to] += a; return true; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= a;
        balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

/// @dev A $1.00 feed whose `updatedAt` is FROZEN at construction, so wall-clock
///      time can carry it past its heartbeat exactly like a real feed that has
///      stopped publishing.
contract FreezableUsdFeed {
    uint256 public updatedAt;
    constructor() { updatedAt = block.timestamp; }
    function refresh() external { updatedAt = block.timestamp; }
    function decimals() external pure returns (uint8) { return 8; }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, 1e8, updatedAt, updatedAt, 1);
    }
}

contract Swapper {
    IPoolManager public immutable pm;
    constructor(IPoolManager _pm) { pm = _pm; }
    function swap(PoolKey memory key, bool zeroForOne, int256 amount) external payable {
        pm.unlock(abi.encode(key, zeroForOne, amount));
    }
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        (PoolKey memory key, bool zeroForOne, int256 amount) =
            abi.decode(data, (PoolKey, bool, int256));
        BalanceDelta d = pm.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amount,
                sqrtPriceLimitX96: zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970342 - 1
            }),
            ""
        );
        int128 a0 = d.amount0();
        int128 a1 = d.amount1();
        if (a0 < 0) _pay(key.currency0, uint256(uint128(-a0)));
        if (a1 < 0) _pay(key.currency1, uint256(uint128(-a1)));
        if (a0 > 0) pm.take(key.currency0, address(this), uint256(uint128(a0)));
        if (a1 > 0) pm.take(key.currency1, address(this), uint256(uint128(a1)));
        return "";
    }
    function _pay(Currency c, uint256 amt) private {
        if (Currency.unwrap(c) == address(0)) { pm.settle{value: amt}(); }
        else { pm.sync(c); IERC20(Currency.unwrap(c)).transfer(address(pm), amt); pm.settle(); }
    }
    receive() external payable {}
}

/**
 * @dev REGRESSION test for V-1 — a lapsed feed must not make a HEALTHY
 *      generation read as dead.
 *
 *  {QuoteOracle} is explicit about its contract:
 *
 *      "when a price is unusable this returns 0, and callers MUST treat 0 as
 *       'cannot judge' rather than 'no volume'. Failing toward ALIVE is the
 *       only safe direction when the wrong answer cannot be undone."
 *
 *  The hook's consumer did the opposite — `f == 0 ? raw : ...` — which is not
 *  graceful degradation but a silent change to the UNIT of the volume ledger.
 *  Raw quote units and USD-at-1e18 differ by the quote's decimals AND its price
 *  (1e12x for a 6-decimal stable, 3000x for ETH), so the fallback UNDER-counted
 *  in every case and `_volumeBuckets` ended up holding a mixture of two
 *  incompatible scales that `getVolume24h` summed without discrimination.
 *
 *  Because `relaunch()` is permissionless and death is irreversible, an ordinary
 *  Chainlink heartbeat miss — the very thing the staleness check exists to
 *  detect — handed any observer a free option to tear down a generation that was
 *  trading normally.
 *
 *  The fix has two halves, and this pins both:
 *    1. `_toUsd` now reads the CACHED entrypoint, which keeps the last good
 *       factor across a refresh failure. An ordinary lapse no longer changes
 *       what a recorded number means. (It also stops paying a full Chainlink
 *       read on every swap — audit G-1.)
 *    2. A genuine 0 records NOTHING rather than a raw figure, so the two scales
 *       can never be mixed in the same ledger.
 *
 *  Run:
 *    export FORK_RPC=<sepolia> POOL_MANAGER=0x.. POSITION_MANAGER=0x..
 *    FOUNDRY_PROFILE=cauldron forge test --match-contract AuditPoC7 -vv
 */
contract AuditPoC7_StaleOracleDeath is Test {
    using PoolIdLibrary for PoolKey;

    bool active;
    IPoolManager pm;
    CauldronHook hook;
    Stable6 usdg;
    Swapper swapper;
    QuoteOracle oracle;
    FreezableUsdFeed feed;

    function allowedQuote(address q) external view returns (bool) {
        return q == address(usdg) || q == address(0);
    }

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
        pm = IPoolManager(poolManager);

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs = abi.encode(
            IPoolManager(poolManager), uint256(1 ether), address(0), address(this), address(this)
        );
        (, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManager), 1 ether, address(0), address(this), address(this)
        );

        hook.setRegistry(address(this));
        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true);

        usdg = new Stable6();
        swapper = new Swapper(pm);
        vm.deal(address(this), 200 ether);
    }

    function test_V1_LapsedFeedKeepsTheLedgerInOneUnit_OnFork() public {
        
        vm.skip(!active);
        address positionManager = vm.envAddress("POSITION_MANAGER");

        (address token, ) =
            PoolOps.deployTokenAbove("Gnome", "GNOME", 2, 777_000_000e18, address(usdg));
        usdg.mint(address(this), 5_000_000e6);

        (PoolId id, ) = PoolOps.openOrAddPair(
            pm, IPositionManagerOps(positionManager), address(hook),
            token, address(usdg), 1_000_000e6, 1_000_000e18, 200, 0
        );

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(usdg)),
            currency1: Currency.wrap(token),
            fee: 0, tickSpacing: 200, hooks: IHooks(address(hook))
        });

        // A $1.00 feed on a 1-hour heartbeat — shorter than the 24h volume
        // window, so a lapse is visible without the buckets ageing out.
        oracle = new QuoteOracle(address(this));
        feed = new FreezableUsdFeed();
        oracle.setFeed(address(usdg), address(feed), 1 hours, 6);
        // Wiring an oracle re-denominates every volume figure to USD-1e18, so the
        // crystal ladder and the odds curve must be restated in the same units
        // (audit U-1). $50 a fren, $1,000 for the top of the odds curve.
        hook.setDeathThreshold(0, address(oracle), 50e18, 0, 1000e18);

        usdg.mint(address(swapper), 1_000_000e6);

        // ── Leg 1: the feed is live. Volume is denominated in USD. ───────────
        swapper.swap(key, true, -10_000e6);
        uint256 healthy = hook.getVolume24h(id);
        emit log_named_uint("volume with a LIVE feed  (1e18 = $1)", healthy);
        assertGt(healthy, 1e18, "a live feed records USD-scaled volume");

        // ── Leg 2: the feed stops publishing. Nothing else changes. ──────────
        vm.warp(block.timestamp + 1 hours + 1);
        assertEq(
            oracle.usdPerRawUnit(address(usdg)), 0,
            "the oracle still correctly refuses the raw read"
        );

        uint256 beforeSecond = hook.getVolume24h(id);
        swapper.swap(key, true, -10_000e6); // an IDENTICAL trade
        uint256 contributed = hook.getVolume24h(id) - beforeSecond;
        emit log_named_uint("same trade with a LAPSED feed       ", contributed);

        // THE FIX: the cache carries the last good factor, so the same dollar
        // trade still registers the same order of magnitude. Pre-fix this
        // collapsed by exactly 1e12.
        assertApproxEqRel(
            contributed, healthy, 0.05e18,
            "a lapsed feed must not change the scale of the ledger"
        );

        // ── And death does not fire on a generation that is trading. ─────────
        uint256 threshold = healthy / 2;
        hook.setDeathThreshold(threshold, address(0), 0, 0, 0);

        vm.warp(block.timestamp + 23 hours);
        swapper.swap(key, true, -10_000e6);
        swapper.swap(key, true, -10_000e6);

        emit log_named_uint("threshold                           ", threshold);
        emit log_named_uint("volume now read by isDead()         ", hook.getVolume24h(id));

        assertFalse(
            hook.isDead(id),
            "a generation trading through a feed outage must stay alive"
        );
    }

    /// The other half: a quote that has NEVER had a usable price records
    /// nothing at all, rather than silently logging raw units into a ledger
    /// whose other entries are USD.
    function test_V1_AnUnpriceableQuoteRecordsNothing_OnFork() public {
        
        vm.skip(!active);
        address positionManager = vm.envAddress("POSITION_MANAGER");

        (address token, ) =
            PoolOps.deployTokenAbove("Gnome", "GNOME", 2, 777_000_000e18, address(usdg));
        usdg.mint(address(this), 5_000_000e6);

        (PoolId id, ) = PoolOps.openOrAddPair(
            pm, IPositionManagerOps(positionManager), address(hook),
            token, address(usdg), 1_000_000e6, 1_000_000e18, 200, 0
        );

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(usdg)),
            currency1: Currency.wrap(token),
            fee: 0, tickSpacing: 200, hooks: IHooks(address(hook))
        });

        // An oracle is wired, but USDG has NO feed — the "cannot judge" case.
        oracle = new QuoteOracle(address(this));
        // Wiring an oracle re-denominates every volume figure to USD-1e18, so the
        // crystal ladder and the odds curve must be restated in the same units
        // (audit U-1). $50 a fren, $1,000 for the top of the odds curve.
        hook.setDeathThreshold(0, address(oracle), 50e18, 0, 1000e18);

        usdg.mint(address(swapper), 100_000e6);
        swapper.swap(key, true, -10_000e6);

        assertEq(
            hook.getVolume24h(id), 0,
            "an unpriceable quote records nothing, never a raw 6-decimal figure"
        );
    }
}
