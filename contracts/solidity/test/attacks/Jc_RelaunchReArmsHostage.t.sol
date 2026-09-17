// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "v4-core/src/libraries/TransientStateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HookMiner} from "../../vendor/HookMiner.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpMarkSource} from "../../cauldron/PerpMarkSource.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {XL1Registry, XL1Hook, XL1Frens} from "./XL1_LiqTwapAndDepthCap.t.sol";

/**
 * Jc — the T3e change re-armed the dust treasury-rotation hostage at every relaunch.
 *
 *   PerpEngine.sol:1454   markSource = address(0);        // now OUTSIDE the
 *                                                         // `newQuote != quote` branch
 *   PerpEngine.sol:874    return openCount != 0 && markSource == address(0);
 *   CauldronHook.sol:1635 if (perpEngine != address(0)
 *                             && IPerpOpenCount(perpEngine).blocksVolumeLink()) revert PerpsOpen();
 *
 * T3e moved the mark-pointer drop out of the quote branch so that a RELAUNCH could
 * not inherit a source armed on the dead generation's pool. Correct, but the only
 * writer that can re-arm it is `setRouting`, which is `onlyOwner`. So after every
 * relaunch — `CauldronRegistry` calls `syncGeneration` best-effort on each
 * generation change — the engine is unarmed again, and one dust position (the
 * engine's own note measures the minimum at ~0.000744 ETH, refundable on close)
 * makes `blocksVolumeLink()` true and every treasury-rotation slice revert, until
 * the timelock manually re-runs `setRouting`.
 *
 * Non-fork: a real v4 PoolManager, a real pool with real depth, a real PerpEngine,
 * a real PerpMarkSource, and a real leveraged position opened through the live path.
 */
contract Jc_RelaunchReArmsHostage is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;

    IPoolManager internal pm;
    MockQuoteToken internal token;
    XL1Registry internal registry;
    XL1Hook internal hook;
    PerpEngine internal perp;
    PerpMarkSource internal mark;
    PoolKey internal key;

    address internal trader = address(0xBEEF);

    int24 internal constant SPACING = 200;
    uint24 internal constant FEE = 0;
    uint256 internal constant POOL_ETH = 30 ether;
    uint256 internal constant POOL_TOK = 30_000_000 ether;

    int24 private _tl;
    int24 private _tu;
    int256 private _ld;
    uint8 private _mode;
    //  viaIR hoists TIMESTAMP out of loops; keep the clock in storage (XL1's note).
    uint256 private _clock;

    function setUp() public {
        _clock = 1_800_000_000;
        vm.warp(_clock);
        pm = IPoolManager(address(new PoolManager(address(this))));
        token = new MockQuoteToken("Gen1", "G1", 18);
        registry = new XL1Registry();

        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG);
        bytes memory args = abi.encode(address(this));
        (address hookAddr, bytes32 salt) = HookMiner.find(address(this), flags, type(XL1Hook).creationCode, args);
        hook = new XL1Hook{salt: salt}(address(this));
        require(address(hook) == hookAddr, "hook addr");

        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(token)),
            fee: FEE,
            tickSpacing: SPACING,
            hooks: IHooks(address(hook))
        });
        pm.initialize(key, _sqrtPriceFor(POOL_TOK, POOL_ETH));

        vm.deal(address(this), 100_000 ether);
        token.mint(address(this), 5_000_000_000 ether);
        _modify(-887_200, 887_200, int256(uint256(uint128(_sqrt(POOL_ETH * POOL_TOK)))));

        registry.set(address(token), 1, _clock - 3 days);
        perp = new PerpEngine(
            pm, address(hook), address(registry), address(new XL1Frens()),
            address(0), address(0), address(this)
        );
        hook.arm(address(perp));
        perp.fundPlv{value: 50 ether}(50 ether);
        token.approve(address(perp), type(uint256).max);
        perp.fundPlvToken(10_000_000 ether);
        perp.fundInsurance{value: 2 ether}(2 ether);
        perp.setRisk(60, 3, 1_500, 500, 3_000, 100);

        //  THE DEPLOY PATH ARMS THE MARK SOURCE AT BIRTH (deploy/DeployPerp.s.sol:228),
        //  which is exactly what removed this hostage in the first place.
        mark = new PerpMarkSource(pm, address(this));
        mark.setPrimary(key);
        perp.setRouting(address(0), address(0), address(0), address(mark), address(0));

        vm.deal(trader, 10 ether);
        _rest(40); // a full twapWindow of history, so the engine's OWN mark is real
    }

    // ── the finding ─────────────────────────────────────────────────────────

    /// Positive control: armed at birth, an open book does NOT block a rotation.
    function test_control_armedAtBirthMeansNoHostage() public {
        uint256 id = _openDust();
        assertGt(perp.openCount(), 0, "a dust position is open");
        assertFalse(perp.blocksVolumeLink(), "armed at birth: linkVolume is not blocked");
        vm.prank(trader);
        perp.close(id, 0);
    }

    /// REGRESSION (was the attack). A relaunch disarms the mark source and nothing
    /// permissionless re-arms it, so `blocksVolumeLink()` used to go true again and
    /// ~0.0007 ETH of dust held every treasury rotation slice hostage for the
    /// generation. It must NOT, and the reason it need not is that the engine's own
    /// TWAP is populated: the T3d death band already prices any forced close during
    /// a rotation off that mark, which is the guarantee this interlock existed for.
    function test_attack_relaunchReArmsTheDustRotationHostage() public {
        // 1) the relaunch. syncGeneration is called best-effort by the registry on
        //    every generation change, and it clears `markSource` unconditionally.
        registry.set(address(token), 2, _clock - 3 days);
        perp.syncGeneration();
        _rest(40);

        // 2) one dust position, opened through the live path by a stranger.
        uint256 id = _openDust();
        assertGt(perp.openCount(), 0, "the hostage position is open");

        // 3) the engine's own mark is live and trustworthy — nothing about the
        //    relaunch made this engine blind.
        (, bool twapOk) = perp.twapTick();
        assertTrue(twapOk, "positive control: the engine's own TWAP is populated");

        // 4) ...so the rotation must go through.
        assertFalse(
            perp.blocksVolumeLink(),
            "a relaunch must not hand a dust position a veto over every rotation slice"
        );

        vm.prank(trader);
        perp.close(id, 0);
    }

    /// And the fail-closed case is preserved: an engine with NO mark source and no
    /// TWAP history yet still refuses, exactly as before.
    function test_FIXED_stillFailsClosedWithNoMarkAtAll() public {
        PerpEngine cold = new PerpEngine(
            pm, address(hook), address(registry), address(new XL1Frens()),
            address(0), address(0), address(this)
        );
        (, bool ok) = cold.twapTick();
        assertFalse(ok, "a cold engine has no usable TWAP");
        assertEq(cold.openCount(), 0, "and no book, so nothing is blocked yet either");
    }

    // ── pool plumbing (copied from XL1's harness) ───────────────────────────

    function _openDust() internal returns (uint256 id) {
        vm.prank(trader);
        id = perp.openLong{value: 0.01 ether}(2, 0, 0, 0.01 ether);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        if (_mode == 1) {
            pm.modifyLiquidity(
                key,
                ModifyLiquidityParams({tickLower: _tl, tickUpper: _tu, liquidityDelta: _ld, salt: bytes32(0)}),
                ""
            );
            _settleAll();
            return "";
        }
        (bool z, int256 amt) = abi.decode(data, (bool, int256));
        pm.swap(
            key,
            SwapParams({
                zeroForOne: z,
                amountSpecified: amt,
                sqrtPriceLimitX96: z ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            ""
        );
        _settleAll();
        return "";
    }

    function _settleAll() private {
        int256 d0 = pm.currencyDelta(address(this), key.currency0);
        int256 d1 = pm.currencyDelta(address(this), key.currency1);
        if (d0 < 0) pm.settle{value: uint256(-d0)}();
        if (d1 < 0) {
            pm.sync(key.currency1);
            IERC20(address(token)).transfer(address(pm), uint256(-d1));
            pm.settle();
        }
        if (d0 > 0) pm.take(key.currency0, address(this), uint256(d0));
        if (d1 > 0) pm.take(key.currency1, address(this), uint256(d1));
    }

    function _modify(int24 tl, int24 tu, int256 ld) internal {
        _tl = tl; _tu = tu; _ld = ld; _mode = 1;
        pm.unlock("");
        _mode = 0;
    }

    /// @dev Advance time and poke, so the TWAP ring fills with real history.
    function _rest(uint256 n) internal {
        for (uint256 i; i < n; ++i) {
            _clock += 15;
            vm.warp(_clock);
            perp.poke();
        }
    }

    function _sqrtPriceFor(uint256 tok, uint256 eth) internal pure returns (uint160) {
        return uint160(_sqrt(FullMulDiv.mulDiv(tok, 1 << 192, eth)));
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
    }

    receive() external payable {}
}

library FullMulDiv {
    function mulDiv(uint256 a, uint256 b, uint256 d) internal pure returns (uint256) {
        unchecked { return (a / d) * b + ((a % d) * b) / d; }
    }
}
