// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";

import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronToken} from "../../CauldronToken.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title F04 --- the reserve ceiling and the exit guarantee
 * @notice The migration reserve is a SINGLE-SIDED token position parked out of
 *         range, below the launch tick by `nextReserveCeilingOffset` (default
 *         42400 ticks, about 69x). It delivers pure token1 only while the pool
 *         trades ABOVE it.
 *
 *         This suite establishes what happens when the token appreciates THROUGH
 *         that ceiling --- i.e. exactly when the protocol is most successful. See
 *         finding F-18.
 *
 *   export FORK_RPC=<sepolia> POOL_MANAGER=0x.. POSITION_MANAGER=0x..
 *   FOUNDRY_PROFILE=cauldron forge test --match-path 'test/final/F04*' -vv
 */
contract F04_ReserveCeiling is Test {
    using StateLibrary for IPoolManager;

    CauldronHook internal hook;
    CauldronRegistry internal registry;
    IPoolManager internal pm;
    address internal token;
    bool internal active;

    uint160 internal constant MIN_SQRT_LIMIT = 4295128740;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
        address positionManager = vm.envAddress("POSITION_MANAGER");
        pm = IPoolManager(poolManager);

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs =
            abi.encode(IPoolManager(poolManager), uint256(1 ether), address(0), address(this), address(this));
        (address mined, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManager), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == mined, "hook addr");

        registry = new CauldronRegistry(poolManager, positionManager, address(hook), address(this), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));

        // Tax-exempt so the test's own buys are clean and the reasoning is about
        // price, not about the anti-snipe surtax.
        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true);

        // A genesis bonus must exist for `floorPerFren()` (and therefore
        // `floorClaimableNow`) to be meaningful --- without it the view short-circuits
        // on `perFren == 0` and reports "not claimable" for an unrelated reason.
        mifrens = new CeilingMockMiFrens();
        mifrens.setRegistry(address(registry));
        registry.setGenesisBonus(address(mifrens), 1000, 4); // 10% of supply, 4 shares
        mifrens.mint(address(this), 1);

        vm.deal(address(this), 5000 ether);
        (token,) = registry.summon{value: 2 ether}();
    }

    CeilingMockMiFrens internal mifrens;

    /// @notice BASELINE. While spot trades above the reserve band, migration is
    ///         exactly 1:1, the OG floor is redeemable, and the registry's own
    ///         `floorClaimableNow` view agrees.
    function test_F18_MigrationWorksBelowTheCeiling() public {
        if (!active) return;
        uint256 got = _buy(0.25 ether);
        assertGt(got, 0, "acquired circulating supply");

        (, int24 tick,,) = pm.getSlot0(registry.generationPoolId(1));
        assertGt(tick, registry.reserveTickUpper(1), "spot is above the reserve band");
        (bool claimable, uint256 perFren) = registry.floorClaimableNow();
        assertTrue(claimable, "registry reports the floor as claimable");
        assertGt(perFren, 0, "floor is non-zero");

        // Both exits actually work at this price.
        uint256 redeemed = registry.redeemOgFren(1);
        assertGt(redeemed, 0, "OG redemption succeeds below the ceiling");
    }

    /// @notice THE FINDING (F-18). Push the token THROUGH the reserve ceiling and
    ///         observe that the exit guarantee inverts: the reserve band goes
    ///         in-range, so removing liquidity from it no longer yields pure
    ///         token1, and every consumer that demands the full amount reverts.
    ///
    ///         Concretely, once `tick <= reserveTickUpper`:
    ///           * `claimByBurn` reverts "reserve short" --- 1:1 migration is closed;
    ///           * `redeemOgFren` reverts `NoBalance` --- the OG floor cannot be taken;
    ///         and neither can be repaired for the LIVE generation, because
    ///         `setReserveCeiling` only takes effect at the NEXT summon or relaunch,
    ///         and relaunch requires the pool to be DEAD --- which a token that just
    ///         appreciated 69x will not be.
    ///
    ///         The registry surfaces the condition through `floorClaimableNow`, so
    ///         the behaviour is known to the team; what is missing is any on-chain
    ///         remedy. This test pins the behaviour down so a future fix has a
    ///         reference point.
    function test_F18_MigrationBreaksAboveTheCeiling() public {
        if (!active) return;

        // Acquire circulating supply FIRST, while migration still works --- this is
        // the holder whose exit we are about to strand.
        uint256 circulating = _buy(0.25 ether);
        assertGt(circulating, 0, "holder has supply to migrate");

        PoolId id = registry.generationPoolId(1);
        int24 ceiling = registry.reserveTickUpper(1);

        // Buy hard enough to walk the tick DOWN through the ceiling. In this pool
        // ETH is currency0 and the brew token currency1, so price is TOKENS PER ETH:
        // a buy makes the token dearer, i.e. tokens-per-ETH FALLS and the tick FALLS.
        for (uint256 i = 0; i < 40; i++) {
            (, int24 t,,) = pm.getSlot0(id);
            if (t <= ceiling) break;
            _buy(100 ether);
        }

        (, int24 tickNow,,) = pm.getSlot0(id);
        if (tickNow > ceiling) {
            emit log_named_int("tick still above ceiling; test inconclusive", tickNow);
            return; // not enough depth traversed on this fork block --- do not assert
        }

        // The ceiling has been breached. The registry's own view now says so.
        (bool claimable,) = registry.floorClaimableNow();
        assertFalse(claimable, "registry reports the floor as NOT claimable");

        // 1:1 migration is closed. The burn would otherwise destroy the holder's
        // tokens for a short delivery, so `migrateOne`'s guard reverts the whole
        // transaction --- correct behaviour in isolation, but it means there is no
        // exit at all while the price stays here.
        uint256 balBefore = IERC20(token).balanceOf(address(this));
        vm.expectRevert();
        registry.claimByBurn(1, circulating);

        // The OG redemption path is closed for the same reason.
        vm.expectRevert();
        registry.redeemOgFren(1);

        // Nothing was lost --- the holder keeps every token. It is the EXIT that is
        // stranded, not the value, which is why this is a liveness failure of the
        // guarantee rather than a theft.
        assertEq(IERC20(token).balanceOf(address(this)), balBefore, "balance intact, exit closed");
        assertEq(mifrens.ownerOf(1), address(this), "the fren was not surrendered");
    }

    /// @notice The ceiling is a per-iteration governance choice, and the bounds are
    ///         wide: from 4000 ticks (about 1.5x) to 138000 (about 1e6 x). A launch
    ///         that expects more than 69x of appreciation MUST raise it before the
    ///         summon, because it cannot be changed for a live generation.
    function test_F18_CeilingIsSetBeforeTheSummonOnly() public {
        if (!active) return;
        int24 before = registry.reserveTickUpper(1);

        registry.setReserveCeiling(138_000); // the maximum the setter allows
        assertEq(registry.reserveTickUpper(1), before, "the LIVE generation's band is immovable");

        vm.expectRevert(); // below the sanity floor
        registry.setReserveCeiling(3_999);
        vm.expectRevert(); // above the sanity ceiling
        registry.setReserveCeiling(138_001);
    }

    // ---------------------------------------------------------------------
    function _buy(uint256 ethIn) internal returns (uint256 got) {
        got = abi.decode(pm.unlock(abi.encode(ethIn)), (uint256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "not pm");
        uint256 ethIn = abi.decode(data, (uint256));
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(registry.currentToken()),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
        BalanceDelta d = pm.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(ethIn), sqrtPriceLimitX96: MIN_SQRT_LIMIT}),
            abi.encode(address(this))
        );
        pm.settle{value: uint256(uint128(-d.amount0()))}();
        uint256 got = uint256(uint128(d.amount1()));
        pm.take(key.currency1, address(this), got);
        return abi.encode(got);
    }

    receive() external payable {}
}

/// @notice Minimal genesis-MiFrens stand-in: registry-gated `custodyTransfer` with
///         no approval, plus the `everMoved` flag the recycle path sets.
contract CeilingMockMiFrens {
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => bool) public everMoved;
    address public registry;

    function setRegistry(address r) external { registry = r; }

    function mint(address to, uint256 id) external {
        ownerOf[id] = to;
        balanceOf[to] += 1;
    }

    function custodyTransfer(address from, address to, uint256 id) external {
        require(msg.sender == registry, "not registry");
        require(ownerOf[id] == from, "wrong from");
        balanceOf[from] -= 1;
        balanceOf[to] += 1;
        ownerOf[id] = to;
        everMoved[id] = true;
    }
}
