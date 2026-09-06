// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CauldronHook} from "../CauldronHook.sol";
import {CauldronRegistry} from "../CauldronRegistry.sol";
import {CauldronFactory} from "../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../cauldron/RedemptionExt.sol";
import {QuoteRotator} from "../cauldron/QuoteRotator.sol";
import {PoolOps, IPositionManagerOps} from "../cauldron/PoolOps.sol";
import {HookMiner} from "../vendor/HookMiner.sol";

/// @dev A quote asset the treasury might allowlist. Deliberately deployed with
///      plain CREATE so its address is arbitrary — the iteration token is mined
///      above the watermark, so it must still sort above THIS.
contract MockUSDG is IERC20 {
    string public constant name = "Mock USDG";
    string public constant symbol = "USDG";
    uint8 public constant decimals = 6; // NOT 18 — the decimals trap
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 a) external { balanceOf[to] += a; totalSupply += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= a;
        balanceOf[f] -= a; balanceOf[to] += a; return true;
    }
}

/**
 * @dev The rotation round trip, against REAL Uniswap v4.
 *
 *  Everything before this exercised the rotation against stubs, which proves the
 *  bookkeeping and none of the machinery that actually moves funds: v4's
 *  unlock/settle/take dance, the PositionManager's encoding, and whether a
 *  partial withdrawal really leaves the original pair tradeable.
 *
 *  Skips cleanly without FORK_RPC so CI still passes.
 */
contract RotationRoundTripTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    bool active;
    IPoolManager pm;
    CauldronHook hook;
    CauldronRegistry registry;
    QuoteRotator rotator;
    MockUSDG usdg;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;

        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("POSITION_MANAGER");
        pm = IPoolManager(poolManager);

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG
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

        registry = new CauldronRegistry(poolManager, positionManager, address(hook), address(0), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));

        usdg = new MockUSDG();
        registry.setAllowedQuote(address(usdg), true, 1e18);
        rotator = new QuoteRotator(address(registry), pm);

        vm.deal(address(this), 100 ether);
    }

    /// The invariant the whole design rests on, against a real deployment: the
    /// iteration token must sort ABOVE an arbitrary ERC20 quote, so "quote =
    /// currency0" holds and none of the liquidity math has to mirror.
    function test_MinedTokenOutranksAnArbitraryQuote_OnFork() public {
        if (!active) return;

        (address token, address quoteUsed) =
            PoolOps.deployTokenAbove("Gnomeland", "GNOME", 2, 777_000_000e18, address(usdg));

        assertEq(quoteUsed, address(usdg), "the quote was honoured");
        assertGt(uint160(token), uint160(address(usdg)), "token sorts above a CREATE-deployed quote");
    }

    /// A pair can be OPENED against a non-ETH quote and then TOPPED UP, because
    /// the guild must be able to rotate back later without a second code path.
    function test_OpenThenTopUpTheSamePair_OnFork() public {
        if (!active) return;

        address positionManager = vm.envAddress("POSITION_MANAGER");
        (address token, ) =
            PoolOps.deployTokenAbove("Gnomeland", "GNOME", 2, 777_000_000e18, address(usdg));

        usdg.mint(address(this), 2_000_000e6);

        (PoolId id1, uint256 pos1) = PoolOps.openOrAddPair(
            pm, IPositionManagerOps(positionManager), address(hook),
            token, address(usdg), 1_000_000e6, 100_000e18, 200, 0
        );
        assertGt(pos1, 0, "pair opened");

        (uint160 sqrtAfterOpen,,,) = pm.getSlot0(id1);
        assertGt(sqrtAfterOpen, 0, "pool is live");

        // Top up the SAME pair. initialize must fail harmlessly and the existing
        // price must survive — a top-up that repriced a live pool would hand a
        // free arbitrage to whoever triggered it.
        (PoolId id2, uint256 pos2) = PoolOps.openOrAddPair(
            pm, IPositionManagerOps(positionManager), address(hook),
            token, address(usdg), 500_000e6, 25_000e18, 200, 0
        );

        assertEq(PoolId.unwrap(id2), PoolId.unwrap(id1), "same pair, not a second pool");
        assertGt(pos2, 0, "top-up minted more liquidity");

        (uint160 sqrtAfterTopUp,,,) = pm.getSlot0(id1);
        assertEq(sqrtAfterTopUp, sqrtAfterOpen, "a top-up must NOT reprice a live pool");
    }

    /// A partial withdrawal must leave the original pair alive. Removing
    /// everything is the DEATH path; a rotation is a reallocation and the pair
    /// has to keep trading while the conversion runs over hours.
    function test_PartialRemovalLeavesThePairTradeable_OnFork() public {
        if (!active) return;

        address positionManager = vm.envAddress("POSITION_MANAGER");
        (address token, ) =
            PoolOps.deployTokenAbove("Gnomeland", "GNOME", 2, 777_000_000e18, address(usdg));
        usdg.mint(address(this), 1_000_000e6);

        (PoolId id, uint256 pos) = PoolOps.openOrAddPair(
            pm, IPositionManagerOps(positionManager), address(hook),
            token, address(usdg), 1_000_000e6, 100_000e18, 200, 0
        );

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(usdg)),
            currency1: Currency.wrap(token),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });

        uint128 before = IPositionManagerOps(positionManager).getPositionLiquidity(pos);
        assertGt(before, 0, "liquidity present");

        (uint256 quoteOut, uint256 tokenOut) = PoolOps.removePartial(
            IPositionManagerOps(positionManager), pos, key, token, address(usdg), 3000 // 30%
        );

        assertGt(quoteOut, 0, "recovered the QUOTE side, not address(this).balance");
        assertGt(tokenOut, 0, "recovered the token side");

        uint128 remaining = IPositionManagerOps(positionManager).getPositionLiquidity(pos);
        assertGt(remaining, 0, "the pair MUST still be tradeable");
        assertLt(remaining, before, "and it did withdraw something");

        (uint160 sqrtNow,,,) = pm.getSlot0(id);
        assertGt(sqrtNow, 0, "pool still initialized after a partial pull");
    }

    /// A rotation must never be able to empty the pair it is rotating out of.
    function test_RemovalIsCappedAtHalf_OnFork() public {
        if (!active) return;

        address positionManager = vm.envAddress("POSITION_MANAGER");
        (address token, ) =
            PoolOps.deployTokenAbove("Gnomeland", "GNOME", 2, 777_000_000e18, address(usdg));
        usdg.mint(address(this), 1_000_000e6);

        (, uint256 pos) = PoolOps.openOrAddPair(
            pm, IPositionManagerOps(positionManager), address(hook),
            token, address(usdg), 1_000_000e6, 100_000e18, 200, 0
        );

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(usdg)),
            currency1: Currency.wrap(token),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });

        vm.expectRevert(bytes("bps"));
        PoolOps.removePartial(
            IPositionManagerOps(positionManager), pos, key, token, address(usdg), 5001
        );
    }

    receive() external payable {}
}
