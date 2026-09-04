// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "../vendor/HookMiner.sol";

import {CauldronHook} from "../CauldronHook.sol";
import {CauldronRegistry} from "../CauldronRegistry.sol";
import {CauldronToken} from "../CauldronToken.sol";
import {CauldronFactory} from "../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../cauldron/RedemptionExt.sol";
import {CauldronSeeder} from "../cauldron/CauldronSeeder.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../cauldron/ICauldron.sol";

/**
 * @notice Fork test that MEASURES the anti-snipe effect of progressive seeding
 *         against LIVE Uniswap v4: the SAME buy suffers MORE price impact (gets
 *         FEWER tokens per ETH) early in the launch window (thin streamed book)
 *         than late (fully seeded) — and vs the atomic book, where a block-0
 *         sniper gets a cheap bag. Buyers are tax-exempt so we isolate the DEPTH
 *         (price-impact) effect from the surtax (which stacks on top in prod).
 *
 *  Run:
 *    export FORK_RPC=... POOL_MANAGER=0x... POSITION_MANAGER=0x...
 *    FOUNDRY_PROFILE=cauldron forge test --match-contract LaunchSnipeForkTest -vv
 *  Without FORK_RPC the tests no-op (suite still compiles + passes in CI).
 */
contract LaunchSnipeForkTest is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    CauldronHook hook;
    CauldronRegistry registry;
    CauldronSeeder seeder;
    IPoolManager pm;
    address posm;
    bool active;

    uint160 constant MIN_SQRT_LIMIT = 4295128740;
    uint64 constant WINDOW = 900;        // 15-min launch window
    uint256 constant SNIPE_ETH = 1 ether; // whale-sized buy (== the 1 ETH raise)

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);
        address poolManager = vm.envAddress("POOL_MANAGER");
        posm = vm.envAddress("POSITION_MANAGER");
        pm = IPoolManager(poolManager);

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
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
        registry.setGovernor(address(new SnipeGov()));

        seeder = new CauldronSeeder(address(registry), posm, poolManager);

        // buyers are tax-exempt → we measure pure depth/price impact.
        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true);
        vm.deal(address(this), 100 ether);
    }

    /// PROGRESSIVE: the SAME whale buy suffers FAR more price impact (and gets fewer
    /// tokens per ETH) at block-0 (thin 10% floor) than after the window fully seeds
    /// — measured from INDEPENDENT post-summon states (snapshot/revert) so the two
    /// buys don't compound. This is the structural anti-snipe: size is punished early.
    function test_Progressive_PunishesEarlySnipe_OnFork() public {
        if (!active) return;
        registry.setSeeder(address(seeder));
        registry.setSeedWindow(WINDOW);
        registry.summon{value: 1 ether}();
        PoolId pid = registry.generationPoolId(1);

        uint256 snap = vm.snapshotState();

        // EARLY: block-0 whale into the thin 10% floor.
        (, int24 e0,,) = pm.getSlot0(pid);
        uint256 gotEarly = _buy(SNIPE_ETH);
        (, int24 e1,,) = pm.getSlot0(pid);
        int24 impactEarly = e0 - e1; // buy pushes tick DOWN → positive
        console2.log("progressive block-0  tokens/1E:", gotEarly);
        console2.log("progressive block-0  tick impact:", uint256(int256(impactEarly)));

        vm.revertToState(snap); // undo the early buy → back to the fresh 10% floor

        // LATE: fully stream the book, then the SAME whale buy.
        vm.warp(block.timestamp + WINDOW + 1);
        seeder.poke();
        assertEq(seeder.deployedWad(), 1e18, "fully seeded");
        (, int24 l0,,) = pm.getSlot0(pid);
        uint256 gotLate = _buy(SNIPE_ETH);
        (, int24 l1,,) = pm.getSlot0(pid);
        int24 impactLate = l0 - l1;
        console2.log("progressive full     tokens/1E:", gotLate);
        console2.log("progressive full     tick impact:", uint256(int256(impactLate)));

        // Anti-snipe: the same buy moves price much more early (thin) and the sniper
        // gets fewer tokens per ETH than a buyer once the book has fully streamed.
        assertGt(impactEarly, impactLate, "thin book: block-0 buy eats MORE price impact");
        assertLt(gotEarly, gotLate, "block-0 sniper gets FEWER tokens/ETH than the late buyer");
        console2.log("impact early/late ratio (x100):", (uint256(int256(impactEarly)) * 100) / uint256(int256(impactLate)));
    }

    /// ATOMIC (window 0): the book is fully deep from block 0, so a block-0 buy has
    /// the SAME low impact as a later buy — no structural anti-snipe (the edge the
    /// progressive book removes). Same measurement, for contrast.
    function test_Atomic_NoStructuralAntiSnipe_OnFork() public {
        if (!active) return;
        registry.setSeedWindow(0); // atomic green candle (no streaming)
        registry.summon{value: 1 ether}();
        PoolId pid = registry.generationPoolId(1);

        uint256 snap = vm.snapshotState();
        (, int24 a0,,) = pm.getSlot0(pid);
        uint256 got1 = _buy(SNIPE_ETH);
        (, int24 a1,,) = pm.getSlot0(pid);
        int24 impact1 = a0 - a1;
        console2.log("atomic block-0 tokens/1E:", got1);
        console2.log("atomic block-0 tick impact:", uint256(int256(impact1)));

        vm.revertToState(snap);
        (, int24 b0,,) = pm.getSlot0(pid);
        uint256 got2 = _buy(SNIPE_ETH);
        (, int24 b1,,) = pm.getSlot0(pid);
        int24 impact2 = b0 - b1;

        // Deep from t0 → the "early" and "repeat" buys are essentially identical.
        assertApproxEqRel(uint256(int256(impact1)), uint256(int256(impact2)), 0.02e18, "atomic: no early penalty");
        assertApproxEqRel(got1, got2, 0.02e18, "atomic: block-0 fills same as later");
    }

    // --- helpers -------------------------------------------------------------
    function _buy(uint256 ethIn) internal returns (uint256 got) {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(registry.currentToken()),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
        bytes memory res = pm.unlock(abi.encode(key, ethIn));
        got = abi.decode(res, (uint256));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "not pm");
        (PoolKey memory key, uint256 ethIn) = abi.decode(data, (PoolKey, uint256));
        BalanceDelta d = pm.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(ethIn), sqrtPriceLimitX96: MIN_SQRT_LIMIT}),
            abi.encode(address(this))
        );
        uint256 ethOwed = uint256(uint128(-d.amount0()));
        uint256 got = uint256(uint128(d.amount1()));
        pm.settle{value: ethOwed}();
        pm.take(key.currency1, address(this), got);
        return abi.encode(got);
    }

    receive() external payable {}
}

contract SnipeGov is ICauldronGovernor {
    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external {}
    function winner() external pure returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Ethereal Spirit", symbol: "SPIRIT", mode: MetadataMode.BaseURI,
            baseURI: "ipfs://spirit/", renderer: address(0), website: "spirit.xyz",
            socials: "x.com/spirit", nftSupply: 1000, volumePerNFT: 0, proposer: address(0xBEEF)
        });
        id = 1;
    }
}
