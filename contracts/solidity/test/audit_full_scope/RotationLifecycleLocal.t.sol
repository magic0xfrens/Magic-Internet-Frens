// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "../attacks/YBase.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {QuoteOracle} from "../../cauldron/QuoteOracle.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";
import {IPositionManagerOps} from "../../cauldron/PoolOps.sol";

contract LocalRotationVotes {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    function getPastTotalSupply(uint256) external pure returns (uint256) { return 1000; }
}

/// LP fixture only. All swap, settlement and position management is production V4.
contract LocalRotationVenue is IUnlockCallback {
    IPoolManager internal immutable manager;
    MockQuoteToken internal immutable quote;
    PoolKey internal venue;

    constructor(IPoolManager pm, MockQuoteToken q) {
        manager = pm;
        quote = q;
        venue = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(q)), 3000, 60, IHooks(address(0)));
        pm.initialize(venue, uint160(1 << 96));
    }

    function seed() external payable { manager.unlock(""); }
    function key() external view returns (PoolKey memory) { return venue; }

    function unlockCallback(bytes calldata) external returns (bytes memory) {
        require(msg.sender == address(manager), "only manager");
        (BalanceDelta d,) = manager.modifyLiquidity(
            venue, ModifyLiquidityParams(-887220, 887220, int256(10_000 ether), bytes32(0)), ""
        );
        manager.settle{value: uint256(uint128(-d.amount0()))}();
        manager.sync(venue.currency1);
        require(quote.transfer(address(manager), uint256(uint128(-d.amount1()))));
        manager.settle();
        return "";
    }
}

/// Full registry/facet/governor/rotator lifecycle with real V4 + PositionManager
/// + Permit2. Vote supply, quote token and pegged oracle configuration are fixtures.
contract RotationLifecycleLocalTest is YBase {
    TreasuryGovernor internal gov;
    QuoteRotator internal rot;
    MockQuoteToken internal usd;
    PoolKey internal venue;
    uint256 internal gen;
    address internal guild = address(0x6111D);

    function setUp() public {
        // V4 PoolManager pins solc 0.8.26; the production hook's transient
        // variables require a newer compiler. Deploy each compiled artifact.
        address manager = deployCode("out/PoolManager.sol/PoolManager.json", abi.encode(address(this)));
        address permit = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        // PoolOps uses canonical Permit2. Execute its real constructor at that
        // address in the local EVM; no registry/hook/accounting storage is forced.
        deployCodeTo("out/Permit2.sol/Permit2.json", permit);
        // Descriptor and WETH are unused in these native/ERC20 liquidity paths.
        address positions = deployCode(
            "out/PositionManager.sol/PositionManager.json",
            abi.encode(manager, permit, uint256(100_000), address(0), address(0))
        );
        _bootWithManagers(25 ether, 10, manager, positions);
        hook.setDeathThreshold(0, address(0), 0, 0, 0);
        usd = new MockQuoteToken("Local quote", "LQ", 18);
        assertLt(uint160(address(usd)), uint160(token), "quote below iteration token");
        registry.setAllowedQuote(address(usd), true, 1e18);
        gov = new TreasuryGovernor(
            IVotes721(address(new LocalRotationVotes())), address(registry), address(this),
            1 days, 30 days, 1 days, 1 days, false
        );
        rot = new QuoteRotator(address(registry), pm);
        QuoteOracle oracle = new QuoteOracle(address(this));
        oracle.setPegged(address(0), 18);
        oracle.setPegged(address(usd), 18);
        rot.setArbParams(address(oracle), 1000, 5e18);
        LocalRotationVenue lp = new LocalRotationVenue(pm, usd);
        usd.mint(address(lp), 10_001 ether);
        lp.seed{value: 10_001 ether}();
        venue = lp.key();
        rot.setVenue(venue, true);
        registry.setRotationWiring(address(rot), address(gov));
        gen = registry.currentGeneration();
        assertGt(gen, 0);
        assertGt(IPositionManagerOps(posm).getPositionLiquidity(registry.generationPositionId(gen)), 0);
    }

    function _approveRotation(address destination) internal {
        _warp(1 days + 1);
        vm.prank(guild);
        uint256 proposal = gov.propose(destination, 10_000);
        vm.roll(vm.getBlockNumber() + 1);
        vm.prank(guild);
        gov.vote(proposal, true);
        _warp(1 days + 1);
        gov.execute(proposal);
        (address approved, uint16 remaining) = gov.allowance();
        assertEq(approved, destination);
        assertEq(remaining, 10_000);
    }

    function _move(uint8 source) internal returns (uint256 moved, uint256 position) {
        (moved, position) = registry.rotateSliceFrom(source, 2500, 1, venue);
        assertGt(moved, 0, "slice moved quote");
        assertGt(IPositionManagerOps(posm).getPositionLiquidity(position), 0, "destination funded");
    }

    function _roundTrip() internal {
        _approveRotation(address(usd));
        for (uint256 i; i < 4; ++i) _move(0);
        assertEq(registry.generationQuote(gen), address(usd));
        assertEq(registry.legCount(gen), 1);
        _approveRotation(address(0));
        for (uint256 i; i < 4; ++i) _move(1);
        assertEq(registry.generationQuote(gen), address(0));
    }

    function test_localFullMigrationAndReturnConsolidatesLaunchQuote() public {
        _roundTrip();
        // A returned launch denomination must have one treasury position, not
        // a new uncounted "secondary" beside the old primary residual.
        assertEq(registry.legCount(gen), 1, "return merges into launch position");
    }

    function _launchKeyHash() internal view returns (bytes32) {
        (Currency c0, Currency c1, uint24 fee, int24 spacing, IHooks h) = registry.generationPoolKey(gen);
        return keccak256(abi.encode(c0, c1, fee, spacing, h));
    }

    function test_repeatedRoundTripsPreserveRedemptionReserve() public {
        uint256 reserve = registry.generationReservePositionId(gen);
        uint128 liquidity = IPositionManagerOps(posm).getPositionLiquidity(reserve);
        uint256 floor = registry.floorPerFren();
        bytes32 launchKey = _launchKeyHash();
        assertGt(reserve, 0);
        assertGt(liquidity, 0);
        assertGt(floor, 0);
        _roundTrip();
        _roundTrip();
        assertEq(registry.legCount(gen), 1);
        assertEq(registry.generationReservePositionId(gen), reserve);
        assertEq(IPositionManagerOps(posm).getPositionLiquidity(reserve), liquidity);
        assertEq(_launchKeyHash(), launchKey);
        assertEq(registry.floorPerFren(), floor);
        // The same reserve remains usable after changing the active LP twice.
        vm.prank(victim);
        uint256 redeemed = registry.redeemOgFren(1);
        assertApproxEqAbs(redeemed, floor, 1e12);
        assertEq(frens.ownerOf(1), address(registry));
    }

    function test_failedReturnSliceRollsBackCustodyAndMandate() public {
        _approveRotation(address(usd));
        for (uint256 i; i < 4; ++i) _move(0);
        _approveRotation(address(0));
        uint256 launch = registry.generationPositionId(gen);
        (, uint256 foreign,) = registry.legAt(gen, 0);
        uint128 launchLiquidity = IPositionManagerOps(posm).getPositionLiquidity(launch);
        uint128 foreignLiquidity = IPositionManagerOps(posm).getPositionLiquidity(foreign);
        uint256 nativeBalance = address(registry).balance;
        uint256 quoteBalance = usd.balanceOf(address(registry));
        // Impossible minimum forces the real route to fail after source removal.
        vm.expectRevert();
        registry.rotateSliceFrom(1, 2500, type(uint256).max, venue);
        assertEq(registry.generationPositionId(gen), launch);
        assertEq(IPositionManagerOps(posm).getPositionLiquidity(launch), launchLiquidity);
        assertEq(IPositionManagerOps(posm).getPositionLiquidity(foreign), foreignLiquidity);
        assertEq(address(registry).balance, nativeBalance);
        assertEq(usd.balanceOf(address(registry)), quoteBalance);
        assertEq(registry.generationQuote(gen), address(usd));
        assertEq(registry.legCount(gen), 1);
        (, uint16 remaining) = gov.allowance();
        assertEq(remaining, 10_000);
        _move(1);
    }

    function test_returnedTreasuryAdvancesNextMigrationMandate() public {
        _roundTrip();
        uint8 source;
        uint128 largest = IPositionManagerOps(posm).getPositionLiquidity(registry.generationPositionId(gen));
        // Native positions share the same pool key and range in this fixture,
        // so their liquidity is directly comparable. Select where value lives.
        for (uint256 i; i < registry.legCount(gen); ++i) {
            (address q, uint256 pid,) = registry.legAt(gen, i);
            if (q == address(0)) {
                uint128 liquidity = IPositionManagerOps(posm).getPositionLiquidity(pid);
                if (liquidity > largest) { largest = liquidity; source = uint8(i + 1); }
            }
        }
        assertGt(largest, 0);
        _approveRotation(address(usd));
        (uint256 moved,) = _move(source);
        emit log_named_uint("native source holding returned treasury", source);
        emit log_named_uint("quote moved on next migration", moved);
        (, uint16 remaining) = gov.allowance();
        assertEq(remaining, 7500, "returned treasury is the migration primary");
    }
}
