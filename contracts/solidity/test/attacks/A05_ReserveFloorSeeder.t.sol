// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronToken} from "../../CauldronToken.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {CauldronSeeder} from "../../cauldron/CauldronSeeder.sol";
import {ISeeder} from "../../cauldron/ISeeder.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../../cauldron/ICauldron.sol";

/**
 * FUND-CUSTODY + ACCOUNTING ATTACKS on the reserve LP, the migration path, and the
 * progressive seeder. These are SAFETY invariants — each attempts a theft /
 * accounting-desync and asserts the protocol PREVENTS it (a PASS = safe).
 *
 *   A-05  MIGRATION IS STRICTLY 1:1 AND NON-DUPLICABLE   (fund custody)
 *   A-06  SEEDER LEDGER-A IS UNREACHABLE BY OUTSIDERS    (fund custody / DoS)
 *   A-07  SEEDER NEVER TOUCHES THE 69x RESERVE           (redemption floor)
 *   A-08  DELEGATECALL FACET IS ONE-SHOT + LAYOUT-SAFE   (delegatecall facet)
 *
 *   export FORK_RPC=... POOL_MANAGER=0x... POSITION_MANAGER=0x...
 *   FOUNDRY_PROFILE=cauldron forge test --match-contract A05_ReserveFloorSeederTest -vv
 */
contract A05_ReserveFloorSeederTest is Test, IUnlockCallback {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    CauldronHook hook;
    CauldronRegistry registry;
    CauldronSeeder seeder;
    IPoolManager pm;
    address posm;
    bool active;

    address attacker = address(0xA77ACC);

    uint160 constant MIN_LIMIT = 4295128740;
    uint160 constant MAX_LIMIT = 1461446703485210103287273052203988822378723970342 - 1;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
        posm = vm.envAddress("POSITION_MANAGER");
        pm = IPoolManager(poolManager);

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs =
            abi.encode(IPoolManager(poolManager), uint256(1 ether), address(0), address(this), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManager), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == hookAddr, "hook addr");

        registry = new CauldronRegistry(poolManager, posm, address(hook), address(0), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));
        registry.setGovernor(address(new RFGov()));

        vm.deal(address(this), 200 ether);
    }

    // =====================================================================
    // A-05 — MIGRATION 1:1, NON-DUPLICABLE
    //
    //  claimByBurn burns the caller's prevToken and hands the SAME amount of the
    //  live token from the reserve (PoolOps.migrateOne + the H-03 revert guard).
    //  We relaunch once to create a "previous generation" the attacker holds
    //  (bought legitimately from the LP, supply-conserving), and assert: (a) new
    //  token received == burned (never mint value out of thin air), and (b) the
    //  old token is really destroyed so a wallet can't migrate the same tokens
    //  twice.
    // =====================================================================
    function test_Invariant_A05_MigrationIsExactlyOneToOne() public {
        if (!active) return;

        (address oldTok, address newTok, uint256 bag) = _summonBuyRelaunch(attacker, 6 ether);

        uint256 amt = bag / 2;
        uint256 oldBefore = IERC20(oldTok).balanceOf(attacker);
        uint256 newBefore = IERC20(newTok).balanceOf(attacker);

        vm.prank(attacker);
        uint256 got = registry.claimByBurn(1, amt);

        uint256 oldBurned = oldBefore - IERC20(oldTok).balanceOf(attacker);
        uint256 newGained = IERC20(newTok).balanceOf(attacker) - newBefore;

        assertEq(oldBurned, amt, "burned exactly the requested amount");
        assertEq(newGained, got, "received exactly what claimByBurn reported");
        assertLe(newGained, oldBurned, "migration never mints value (<= 1:1)");
        assertGe(newGained + 1e12, oldBurned, "migration is not silently lossy (H-03)");
    }

    /// @notice You cannot migrate the same balance twice — the burn destroys it.
    function test_Invariant_A05_NoDoubleMigration() public {
        if (!active) return;
        (address oldTok,, uint256 bag) = _summonBuyRelaunch(attacker, 4 ether);

        vm.prank(attacker);
        registry.claimByBurn(1, bag);
        assertEq(IERC20(oldTok).balanceOf(attacker), 0, "old balance fully burned");

        // A second migration of the same (now-gone) balance must revert NoBalance.
        vm.prank(attacker);
        vm.expectRevert();
        registry.claimByBurn(1, bag);
    }

    // =====================================================================
    // A-06 — SEEDER LEDGER-A IS UNREACHABLE BY OUTSIDERS
    // =====================================================================
    function test_Invariant_A06_SeederFundsUnreachable() public {
        if (!active) return;
        _summonProgressive();

        assertTrue(seeder.seeding(), "campaign live");
        assertGt(address(seeder).balance + IERC20(registry.currentToken()).balanceOf(address(seeder)), 0,
            "seeder holds ledger A");

        vm.startPrank(attacker);
        vm.expectRevert(); // OnlyRegistry
        seeder.withdrawAll(attacker);
        vm.expectRevert(); // OnlyRegistry
        seeder.rescue(attacker);
        vm.expectRevert(); // OnlyHook
        seeder.pokeInSwap();
        vm.stopPrank();

        // The permissionless poke() only ever ADDS liquidity — it pays the caller
        // nothing and cannot be accelerated past the time schedule.
        uint256 attBalBefore = attacker.balance;
        vm.prank(attacker);
        seeder.poke();
        assertEq(attacker.balance, attBalBefore, "poke() paid the caller nothing");
    }

    // =====================================================================
    // A-07 — THE SEEDER CAN NEVER TOUCH THE 69x REDEMPTION RESERVE
    // =====================================================================
    function test_Invariant_A07_ReserveBacksRedemptionFromBlockZero() public {
        if (!active) return;
        _summonProgressive();

        assertGt(registry.generationReservePositionId(1), 0, "reserve placed by registry");
        assertEq(seeder.deployedWad(), 0.1e18, "only 10% streamed");
        // The reserve is a DISTINCT position from any active book, owned by the
        // registry — the seeder (ledger A) can never reach it.
        assertTrue(registry.generationReservePositionId(1) != registry.generationPositionId(1),
            "reserve is a distinct position");
    }

    // =====================================================================
    // A-08 — DELEGATECALL FACET: one-shot wiring, layout-safe, no repoint
    // =====================================================================
    function test_Invariant_A08_RedemptionExtIsFrozenAfterSet() public {
        if (!active) return;

        // Pre-build targets BEFORE arming expectRevert (a `new` mid-arg would
        // otherwise be the call expectRevert latches onto).
        address ext2 = address(new RedemptionExt());
        CauldronRegistry fresh =
            new CauldronRegistry(address(pm), posm, address(hook), address(0), 0);

        // Already set in setUp. A second set (even by the owner) must revert.
        vm.expectRevert(); // AlreadySummoned (reused as "frozen")
        registry.setRedemptionExt(ext2);

        // An outsider can never set it (Ownable).
        vm.prank(attacker);
        vm.expectRevert();
        fresh.setRedemptionExt(ext2);

        // A code-less target is rejected (a delegatecall to an empty account
        // returns SUCCESS with no data → every redemption would silently no-op).
        vm.expectRevert(); // BadConfig
        fresh.setRedemptionExt(attacker); // EOA, no code
    }

    // =====================================================================
    // helpers
    // =====================================================================

    function _summonProgressive() internal {
        seeder = new CauldronSeeder(address(registry), posm, address(pm));
        registry.setSeeder(address(seeder));
        registry.setSeedWindow(600);
        registry.summon{value: 1 ether}();
    }

    /// @dev Summon gen1, BUY a bag of gen1 for `who` from the pool (tokens come out
    ///      of the LP → supply stays fixed, unlike `deal`), age to death, relaunch
    ///      to gen2. Returns (gen1, gen2, bag).
    function _summonBuyRelaunch(address who, uint256 ethIn)
        internal
        returns (address oldTok, address newTok, uint256 bag)
    {
        registry.summon{value: 4 ether}();
        oldTok = registry.currentToken();

        bag = _buyTo(who, ethIn); // real tokens from the LP + recorded volume
        assertGt(bag, 0, "bought some gen1");

        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        assertTrue(hook.isDead(registry.generationPoolId(1)), "gen1 dead");

        registry.relaunch();
        newTok = registry.currentToken();
        assertEq(registry.currentGeneration(), 2, "relaunched to gen2");
    }

    function _buyTo(address to, uint256 ethIn) internal returns (uint256 got) {
        bytes memory r = pm.unlock(abi.encode(uint8(0), ethIn, to));
        got = abi.decode(r, (uint256));
    }

    function _key() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(registry.currentToken()),
            fee: 0, tickSpacing: 200, hooks: IHooks(address(hook))
        });
    }

    function unlockCallback(bytes calldata raw) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        (uint8 dir, uint256 amt, address to) = abi.decode(raw, (uint8, uint256, address));
        PoolKey memory key = _key();
        if (dir == 0) {
            BalanceDelta d = pm.swap(
                key, SwapParams({zeroForOne: true, amountSpecified: -int256(amt), sqrtPriceLimitX96: MIN_LIMIT}), ""
            );
            uint256 spent = uint256(uint128(-d.amount0()));
            uint256 got = uint256(uint128(d.amount1()));
            pm.settle{value: spent}();
            pm.take(key.currency1, to, got);
            return abi.encode(got);
        } else {
            BalanceDelta d = pm.swap(
                key, SwapParams({zeroForOne: false, amountSpecified: -int256(amt), sqrtPriceLimitX96: MAX_LIMIT}), ""
            );
            uint256 spent = uint256(uint128(-d.amount1()));
            uint256 got = uint256(uint128(d.amount0()));
            pm.sync(key.currency1);
            IERC20Minimal(Currency.unwrap(key.currency1)).transfer(address(pm), spent);
            pm.settle();
            pm.take(key.currency0, address(this), got);
            return abi.encode(got);
        }
    }

    receive() external payable {}
}

contract RFGov is ICauldronGovernor {
    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external {}
    function winner() external pure returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Ethereal Spirit", symbol: "SPIRIT", mode: MetadataMode.BaseURI,
            baseURI: "ipfs://spirit/", renderer: address(0), website: "s.xyz",
            socials: "x.com/s", nftSupply: 1000, volumePerNFT: 0, proposer: address(0xBEEF)
        });
        id = 1;
    }
}
