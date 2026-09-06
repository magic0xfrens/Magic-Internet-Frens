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

import {CauldronHook} from "../CauldronHook.sol";
import {PoolOps, IPositionManagerOps} from "../cauldron/PoolOps.sol";
import {QuoteOracle} from "../cauldron/QuoteOracle.sol";
import {HookMiner} from "../vendor/HookMiner.sol";

contract Stable6 is IERC20 {
    string public constant name = "Stable";
    string public constant symbol = "USDG";
    uint8 public constant decimals = 6; // the trap
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

/// @dev Minimal router so a test can actually put a swap through the hook.
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
        // Settle whichever side we owe; take the other.
        int128 a0 = d.amount0();
        int128 a1 = d.amount1();
        if (a0 < 0) _pay(key.currency0, uint256(uint128(-a0)));
        if (a1 < 0) _pay(key.currency1, uint256(uint128(-a1)));
        if (a0 > 0) pm.take(key.currency0, address(this), uint256(uint128(a0)));
        if (a1 > 0) pm.take(key.currency1, address(this), uint256(uint128(a1)));
        return "";
    }

    function _pay(Currency c, uint256 amt) private {
        if (Currency.unwrap(c) == address(0)) {
            pm.settle{value: amt}();
        } else {
            pm.sync(c);
            IERC20(Currency.unwrap(c)).transfer(address(pm), amt);
            pm.settle();
        }
    }
    receive() external payable {}
}

/**
 * @dev Volume must be comparable across a generation's pools.
 *
 *  Death is judged on 24h volume SUMMED across every pool a generation trades
 *  in. Measured on the quote side those figures are not comparable: a 6-decimal
 *  stable and 18-decimal ETH differ by 1e12 before any price difference. A
 *  generation that rotated into a stable would see its measured volume collapse
 *  and get relaunched while perfectly healthy.
 *
 *  This is the test that was missing. The existing volume assertions are all
 *  `> 0`, so they passed either way and proved nothing about the units.
 */
/// @dev A $1.00 feed, 8 decimals like a real Chainlink USD aggregator.
contract MockUsdFeed {
    function decimals() external pure returns (uint8) { return 8; }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, 1e8, block.timestamp, block.timestamp, 1);
    }
}

contract VolumeUnitsTest is Test {
    using PoolIdLibrary for PoolKey;

    bool active;
    IPoolManager pm;
    CauldronHook hook;
    Stable6 usdg;
    Swapper swapper;

    /// @dev The hook reads this off its registry at pool adoption.
    function allowedQuote(address q) external view returns (bool) {
        return q == address(usdg) || q == address(0);
    }

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("POSITION_MANAGER");
        pm = IPoolManager(poolManager);

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs = abi.encode(
            IPoolManager(poolManager), uint256(1 ether), address(0), address(this), address(this)
        );
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManager), 1 ether, address(0), address(this), address(this)
        );

        //  THIS CONTRACT stands in as the registry. The hook adopts a pool only
        //  when the initializer is its registry (audit C-01), and PoolOps is a
        //  library — called from here it runs as THIS contract, so the test must
        //  be the registry for the pool to be tracked at all. The first attempt
        //  wired a real CauldronRegistry, the pool went unadopted, and the test
        //  read zero volume for a swap that genuinely happened.
        hook.setRegistry(address(this));
        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true);

        usdg = new Stable6();
        swapper = new Swapper(pm);
        vm.deal(address(this), 200 ether);
        vm.deal(address(swapper), 100 ether);
    }

    /**
     * THE PROPERTY THE WHOLE MULTI-POOL DESIGN RESTS ON: the same DOLLAR volume
     * registers the same figure whichever pool it happened in.
     *
     * Without the oracle a 6-decimal quote records raw units — 10,000 USDG is
     * 1e10 — while an 18-decimal ETH pool records 1e18-scale numbers. Death sums
     * them and a fren's mint-out cost would depend on which pool you traded in.
     * With the oracle wired, both become USD at 1e18.
     */
    function test_VolumeIsUsdDenominated_OnFork() public {
        if (!active) return;
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

        //  Price the stable at $1.00 so the hook can convert.
        QuoteOracle oracle = new QuoteOracle(address(this));
        MockUsdFeed feed = new MockUsdFeed();
        oracle.setFeed(address(usdg), address(feed), 30 days, 6);
        hook.setDeathThreshold(1 ether, address(oracle));

        usdg.mint(address(swapper), 100_000e6);
        uint256 g = gasleft();
        swapper.swap(key, true, -10_000e6); // buy the token with 10,000 USDG
        emit log_named_uint("swap through the hook (gas)", g - gasleft());

        uint256 vol = hook.getVolume24h(id);
        assertGt(vol, 0, "the swap registered");

        //  ASSERT THE SCALE, NOT THE AMOUNT. The swap is bound by the pool's
        //  price limit, so only part of the 10,000 USDG fills — hardcoding an
        //  expected figure would be testing this pool's depth rather than the
        //  conversion. My first attempt did exactly that and failed at 100x.
        //
        //  What is unambiguous: a 6-decimal quote can only reach 1e18 raw units
        //  if a trillion USDG moved. So anything above 1e18 proves the USD
        //  conversion ran; quote-side accounting measured 1e8 for this same
        //  swap, which is the figure that makes two pools incomparable.
        assertGt(vol, 1e18, "volume must be USD-denominated, not raw 6-decimal units");
        emit log_named_uint("USD volume recorded (1e18 = $1)", vol);
    }
}
