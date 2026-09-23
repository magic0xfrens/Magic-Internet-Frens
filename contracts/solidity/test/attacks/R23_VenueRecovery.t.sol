// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {Test} from "forge-std/Test.sol";
import {VenueSeeder} from "../../deploy/DeployRotationStack.s.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {IPositionManagerOps} from "../../cauldron/PoolOps.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
interface R23PositionOwner {
    function ownerOf(uint256 id) external view returns(address);
    function getPositionLiquidity(uint256 id) external view returns(uint128);
}
contract R23VenueRecovery is Test {
    function test_reseedRequiresRecoveryAndThenRemainsUsable() public {
        address manager = deployCode("out/PoolManager.sol/PoolManager.json", abi.encode(address(this)));
        address permit = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        deployCodeTo("out/Permit2.sol/Permit2.json", permit);
        address positions = deployCode("out/PositionManager.sol/PositionManager.json",
            abi.encode(manager, permit, uint256(100_000), address(0), address(0)));
        MockQuoteToken token = new MockQuoteToken("USD", "USD", 6);
        VenueSeeder venue = new VenueSeeder();
        vm.deal(address(this), 10 ether);
        token.mint(address(venue), 6000e6);
        uint256 first = venue.seed{value: 1 ether}(IPoolManager(manager), IPositionManagerOps(positions), address(token), 1 ether, 3000e6, 60, 3000);
        vm.expectRevert(bytes("recover existing position first"));
        venue.seed{value: 1 ether}(IPoolManager(manager), IPositionManagerOps(positions), address(token), 1 ether, 3000e6, 60, 3000);
        vm.expectRevert(bytes("recover existing position first"));
        venue.seedBand{value: 1 ether}(IPoolManager(manager), IPositionManagerOps(positions), address(token), 1 ether, 3000e6, 60, 3000, 500);
        assertEq(venue.positionId(), first);
        PoolKey memory key = PoolKey(Currency.wrap(address(0)), Currency.wrap(address(token)), 3000, 60, IHooks(address(0)));
        uint256 beforeRecovery = address(this).balance;
        venue.recover(IPositionManagerOps(positions), key, address(token));
        assertGt(address(this).balance, beforeRecovery);
        assertEq(venue.positionId(), 0);
        assertEq(R23PositionOwner(positions).getPositionLiquidity(first), 0);
        token.mint(address(venue), 3000e6);
        uint256 second = venue.seed{value: 1 ether}(IPoolManager(manager), IPositionManagerOps(positions), address(token), 1 ether, 3000e6, 60, 3000);
        assertTrue(first != second);
        // Launchpad optional mode keeps opening and band positions in separate
        // helpers so both remain reachable by their original deployer.
        VenueSeeder band = new VenueSeeder();
        token.mint(address(band), 3000e6);
        uint256 bandId = band.seedBand{value: 1 ether}(IPoolManager(manager), IPositionManagerOps(positions), address(token), 1 ether, 3000e6, 60, 3000, 500);
        assertGt(R23PositionOwner(positions).getPositionLiquidity(bandId), 0);
        assertEq(R23PositionOwner(positions).ownerOf(second), address(venue));
        band.recover(IPositionManagerOps(positions), key, address(token));
        assertEq(R23PositionOwner(positions).getPositionLiquidity(bandId), 0);
        venue.recover(IPositionManagerOps(positions), key, address(token));
        assertEq(R23PositionOwner(positions).getPositionLiquidity(second), 0);
        assertEq(venue.positionId(), 0);
    }
    receive() external payable {}
}
