// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../vendor/HookMiner.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CauldronHook} from "../CauldronHook.sol";
import {CauldronRegistry} from "../CauldronRegistry.sol";
import {CauldronBase} from "../cauldron/CauldronBase.sol";
import {CauldronToken} from "../CauldronToken.sol";
import {CauldronFactory} from "../cauldron/CauldronFactory.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../cauldron/ICauldron.sol";
import {MigrationVesting, IStakerOracle} from "../cauldron/MigrationVesting.sol";

/**
 * @notice Fork integration test for the anti-dump migration VESTING GATE.
 *
 *  Proves the enforcement half of {MigrationVesting}: once the registry's
 *  `claimGate` points at the escrow, an ordinary holder CANNOT migrate instantly
 *  (the drip can't be skipped) — while everything that legitimately needs the 1:1
 *  migration keeps working:
 *    - the ESCROW migrates on the holder's behalf and vests the result;
 *    - the PERP ENGINE stays exempt (its inventory migration is protocol-owned);
 *    - a RELAUNCH still succeeds with the gate on;
 *    - and with the gate OFF, `autoMigrateBatch` / `claimByBurn` are untouched.
 *
 *  Same fork model as CauldronSummon.t.sol: V4 can't be deployed in-process
 *  (permit2 pins solc =0.8.17), so we drive a fork with V4 already deployed.
 *  Without FORK_RPC the tests no-op (suite still compiles + passes in CI).
 *
 *  Run:
 *    export FORK_RPC=https://...   POOL_MANAGER=0x...   POSITION_MANAGER=0x...
 *    FOUNDRY_PROFILE=cauldron forge test --match-contract MigrationVestingGate -vvv
 */
contract MigrationVestingGateForkTest is Test {
    CauldronHook hook;
    CauldronRegistry registry;
    IPoolManager pm;
    MigrationVesting vesting;
    MockStakerOracle oracle;
    bool active;

    uint160 constant MIN_SQRT_LIMIT = 4295128740;
    uint64 constant WINDOW = 72 hours;
    address constant HOLDER = address(0xB0B);

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return; // no fork -> skip
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
        require(address(hook) == hookAddr, "hook addr");

        // emergencyAdmin = address(0) -> defaults to msg.sender (this test), so the
        // test can call setClaimGate directly (delay 0).
        registry = new CauldronRegistry(poolManager, positionManager, address(hook), address(0), 0);
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));

        // The escrow + a toggleable instant-tier oracle.
        oracle = new MockStakerOracle();
        vesting = new MigrationVesting(address(registry), address(this), WINDOW, address(oracle));

        vm.deal(address(this), 20 ether);
    }

    // ── harness: summon gen-1, sell some into circulation, relaunch to gen-2 ──
    // Returns (token1, token2, circulating) with `circulating` gen-1 tokens held by
    // HOLDER (the retail migrator).
    function _summonAndRelaunch() internal returns (address token1, address token2, uint256 circ) {
        registry.setGovernor(address(new MockGovernor()));
        (token1, ) = registry.summon{value: 1 ether}();

        // A tax-exempt buy pulls gen-1 into circulation; park it on HOLDER.
        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true);
        circ = _buyGen1(0.25 ether);
        require(circ > 1e18, "no circulating");
        IERC20(token1).transfer(HOLDER, circ);

        // Age past the volume window + min lifetime, then rebirth.
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        (token2, ) = registry.relaunch();
        require(registry.currentGeneration() == 2, "not gen2");
    }

    // ── 1. access control on the gate setter ─────────────────────────────────
    function test_SetClaimGate_OnlyEmergencyAdmin_OnFork() public {
        if (!active) return;
        vm.prank(address(0xBAD));
        vm.expectRevert(CauldronBase.NotAdmin.selector);
        registry.setClaimGate(address(vesting));

        registry.armEmergency(); // F-19: custody actions must be armed
        registry.setClaimGate(address(vesting)); // admin (this) succeeds
        assertEq(registry.claimGate(), address(vesting), "gate set");
        registry.setClaimGate(address(0)); // and can turn it back off
        assertEq(registry.claimGate(), address(0), "gate cleared");
    }

    // ── 2. THE CORE: gated → direct claim blocked, escrow vests instead ──────
    function test_Gated_DirectClaimBlocked_EscrowVests_OnFork() public {
        if (!active) return;
        (address token1, address token2, uint256 circ) = _summonAndRelaunch();
        registry.armEmergency(); // F-19: custody actions must be armed
        registry.setClaimGate(address(vesting)); // ENFORCE

        // Retail holder can NO LONGER migrate instantly.
        vm.prank(HOLDER);
        vm.expectRevert(CauldronBase.VestingEnforced.selector);
        registry.claimByBurn(1, circ);

        // But going THROUGH the escrow works — and DRIPS (non-staker).
        vm.startPrank(HOLDER);
        IERC20(token1).approve(address(vesting), circ);
        vesting.startVest(1, circ);
        vm.stopPrank();

        assertEq(vesting.claimable(HOLDER), 0, "nothing instantly (dump blocked)");
        assertApproxEqAbs(vesting.locked(HOLDER), circ, circ / 1e6 + 1, "all escrowed + locked");
        assertEq(IERC20(token2).balanceOf(HOLDER), 0, "holder holds no gen2 yet");

        // Anchor the schedule to the grant's start and warp to ABSOLUTE offsets.
        // (Two consecutive `block.timestamp + 36h` warps don't compound reliably
        // under the fork — the second re-reads the pre-warp timestamp — so drive the
        // window explicitly from `vestStart`.)
        uint256 vestStart = block.timestamp;

        // Halfway → ~half claimable.
        vm.warp(vestStart + 36 hours);
        assertApproxEqAbs(vesting.claimable(HOLDER), circ / 2, circ / 100, "half at 50%");

        // Full window (72h) → holder has the whole 1:1 allocation, drip complete.
        vm.warp(vestStart + 72 hours);
        vm.prank(HOLDER);
        vesting.claim();
        assertApproxEqAbs(IERC20(token2).balanceOf(HOLDER), circ, circ / 1e6 + 1, "fully vested 1:1");
        assertEq(vesting.grantCount(HOLDER), 0, "grant drained");
    }

    // ── 2b. instant tier (staker) skips the drip ─────────────────────────────
    function test_Gated_StakerClaimsInstant_OnFork() public {
        if (!active) return;
        (address token1, address token2, uint256 circ) = _summonAndRelaunch();
        registry.armEmergency(); // F-19: custody actions must be armed
        registry.setClaimGate(address(vesting));
        oracle.set(HOLDER, true); // HOLDER is a "staker"

        vm.startPrank(HOLDER);
        IERC20(token1).approve(address(vesting), circ);
        vesting.startVest(1, circ); // auto-releases instant grants in the same tx
        vm.stopPrank();
        assertApproxEqAbs(IERC20(token2).balanceOf(HOLDER), circ, circ / 1e6 + 1, "instant full claim");
    }

    // ── 3. gated → the instant keeper bypass is closed ───────────────────────
    function test_Gated_AutoMigrateBatch_Reverts_OnFork() public {
        if (!active) return;
        _summonAndRelaunch();
        registry.armEmergency(); // F-19: custody actions must be armed
        registry.setClaimGate(address(vesting));

        address[] memory who = new address[](1);
        who[0] = HOLDER;
        vm.expectRevert(CauldronBase.VestingEnforced.selector);
        registry.autoMigrateBatch(1, who);
    }

    // ── 4. autoMigrate STILL WORKS when the gate is OFF (unchanged path) ─────
    function test_Ungated_AutoMigrate_StillWorks_OnFork() public {
        if (!active) return;
        (, address token2, uint256 circ) = _summonAndRelaunch();
        // gate stays OFF (claimGate == 0)

        // HOLDER opts in (non-fren pays the fee) — the hands-off keeper migration.
        // NB: read the fee BEFORE the prank — an external getter inside the
        // `{value: ...}` arg would otherwise consume the prank, so enableAutoMigrate
        // would run as this test contract and opt in the wrong address.
        uint256 fee = registry.AUTO_MIGRATE_FEE();
        vm.deal(HOLDER, 1 ether);
        vm.prank(HOLDER);
        registry.enableAutoMigrate{value: fee}();

        address[] memory who = new address[](1);
        who[0] = HOLDER;
        registry.autoMigrateBatch(1, who); // keeper triggers — instant, no gate

        assertApproxEqAbs(IERC20(token2).balanceOf(HOLDER), circ, circ / 1e6 + 1,
            "opted-in holder auto-migrated 1:1 (unchanged when ungated)");
    }

    // ── 5. gated → the PERP ENGINE is EXEMPT (its migration is not blocked) ──
    function test_Gated_PerpEngineExempt_OnFork() public {
        if (!active) return;
        (address token1, address token2, uint256 circ) = _summonAndRelaunch();

        // Stand a mock engine in via the hook (setPerpEngine try/catches its collection
        // wiring, so this is safe), give it gen-1 inventory, then enforce the gate.
        address engine = address(0xE11E);
        hook.setPerpEngine(engine);
        assertEq(hook.perpEngine(), engine, "engine wired");
        vm.prank(HOLDER);
        IERC20(token1).transfer(engine, circ); // engine's dead-gen inventory

        registry.armEmergency(); // F-19: custody actions must be armed
        registry.setClaimGate(address(vesting)); // ENFORCE for everyone else

        // The engine migrates its own inventory 1:1 despite the gate.
        vm.prank(engine);
        uint256 got = registry.claimByBurn(1, circ);
        assertApproxEqAbs(got, circ, circ / 1e6 + 1, "engine migrated past the gate");
        assertApproxEqAbs(IERC20(token2).balanceOf(engine), circ, circ / 1e6 + 1, "engine holds gen2");
    }

    // ── 6. gated → a RELAUNCH still succeeds (no internal migration dependency) ─
    function test_Gated_RelaunchStillWorks_OnFork() public {
        if (!active) return;
        _summonAndRelaunch(); // now at gen 2
        registry.armEmergency(); // F-19: custody actions must be armed
        registry.setClaimGate(address(vesting)); // gate ON

        // Buy gen-2 into circulation, age it, and rebirth to gen 3 WITH the gate on.
        _buyGen1(0.2 ether); // buys the current (gen-2) token
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        registry.relaunch();
        assertEq(registry.currentGeneration(), 3, "relaunch unaffected by the gate");
    }

    // ── fork swap plumbing (mirrors CauldronSummon.t.sol) ────────────────────
    function _buyGen1(uint256 ethIn) internal returns (uint256 got) {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(registry.currentToken()),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
        got = abi.decode(pm.unlock(abi.encode(key, ethIn)), (uint256));
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

/// Toggleable instant-tier oracle for the vesting escrow.
contract MockStakerOracle is IStakerOracle {
    mapping(address => bool) public instant;
    function set(address who, bool v) external { instant[who] = v; }
    function isInstant(address who) external view returns (bool) { return instant[who]; }
}

/// Minimal governor so relaunch always has a winning proposal.
contract MockGovernor is ICauldronGovernor {
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
