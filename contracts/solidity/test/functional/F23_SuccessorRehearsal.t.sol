// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {HookMiner} from "../../vendor/HookMiner.sol";
import {IPositionManager as IPositionManagerErrors} from "v4-periphery/src/interfaces/IPositionManager.sol";

import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronToken} from "../../CauldronToken.sol";
import {CauldronBase} from "../../cauldron/CauldronBase.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {MiFrensDividend} from "../../cauldron/MiFrensDividend.sol";
import {YGov} from "../attacks/YBase.sol";

/**
 * @title F23 — Successor rehearsal: can the protocol actually be upgraded?
 * @notice `setSuccessor` → `armEmergency` → `migrateToSuccessor` plus the hook's
 *         7-day `proposeRegistryOverride` / `executeRegistryOverride` is the ONLY
 *         route to new core code (the registry is at EIP-170 with no catch-all
 *         fallback, and `redemptionExt` freezes after its first set). Any future
 *         feature that needs new registry entrypoints — cross-chain launches
 *         among them — has to ship through it.
 *
 *  The one existing test of that route (`CauldronSummon.t.sol:487`) proves the
 *  position NFTs change owner. Nothing proved a successor can then RUN the
 *  machine. This rehearsal runs the real handover against the real collection,
 *  dividend and token, and asks the questions a holder would.
 *
 *  ── CONVENTION ─────────────────────────────────────────────────────────────
 *  Each `H*` test first shows the capability WORKS before the handover (so no
 *  assertion here can pass vacuously on a broken rig), then asserts what the
 *  code does AFTER it. Where that is a defect the test pins the CURRENT broken
 *  behaviour, PoC-style, and says what a fixed system must do instead — flip
 *  the assertion when the fix lands (see docs/UPGRADE_READINESS.md).
 *
 *  Local V4 lane (fresh PoolManager/PositionManager from `out/`), no RPC:
 *    FOUNDRY_PROFILE=cauldron forge test --match-contract F23_SuccessorRehearsal -vv
 */
contract F23_SuccessorRehearsal is Test {
    CauldronHook internal hook;
    CauldronRegistry internal v1;
    CauldronRegistry internal v2;
    MiFrensGenesis internal genesis;
    MiFrensDividend internal dividend;
    address internal posm;
    address internal manager;
    address internal token1;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA201);

    uint256 internal constant OG = 10;
    uint256 internal constant PRICE = 0.1 ether;
    /// Mainnet-shaped timelock so the rehearsal exercises the real arm → wait path.
    uint256 internal constant EMERGENCY_DELAY = 2 days;

    function setUp() public {
        manager = deployCode("out/PoolManager.sol/PoolManager.json", abi.encode(address(this)));
        address permit = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
        deployCodeTo("out/Permit2.sol/Permit2.json", permit);
        posm = deployCode(
            "out/PositionManager.sol/PositionManager.json",
            abi.encode(manager, permit, uint256(100_000), address(0), address(0))
        );

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs =
            abi.encode(IPoolManager(manager), uint256(1 ether), address(0), address(this), address(this));
        (address mined, bytes32 salt) = HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(IPoolManager(manager), 1 ether, address(0), address(this), address(this));
        require(address(hook) == mined, "hook addr");

        v1 = new CauldronRegistry(manager, posm, address(hook), address(0), EMERGENCY_DELAY);
        v1.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(v1));
        hook.setOpener(address(v1), true);
        hook.setTaxExempt(address(v1), true);
        v1.setFactory(address(new CauldronFactory()));
        v1.setGovernor(address(new YGov()));

        // The REAL genesis collection + dividend, wired exactly as DeployLaunchpad does.
        genesis = new MiFrensGenesis("MiFrens", "MIF", OG, 2 * OG, PRICE, OG, "ipfs://mifrens/");
        genesis.setRegistry(address(v1));
        v1.setIgniter(address(genesis));
        v1.setGenesisBonus(address(genesis), 2000, OG);
        dividend = new MiFrensDividend(address(genesis), address(this));
        dividend.setRegistry(address(v1));
        genesis.setDividend(address(dividend));

        // Sell out: alice 1..5, bob 6..10. Then anyone ignites.
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.prank(alice);
        genesis.mint{value: 5 * PRICE}(5);
        vm.prank(bob);
        genesis.mint{value: 5 * PRICE}(5);
        genesis.igniteCauldron();
        token1 = v1.currentToken();
        require(token1 != address(0) && v1.floorPerFren() > 0, "rig: summon + genesis floor");
    }

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------

    function _warp(uint256 dt) internal {
        vm.warp(vm.getBlockTimestamp() + dt); // viaIR TIMESTAMP-CSE safe
    }

    /// The documented V2 route, end to end: successor registry, arm, wait out the
    /// registry timelock, migrate custody, then re-point the hook (7 days).
    function _handover() internal {
        v2 = new CauldronRegistry(manager, posm, address(hook), address(0), EMERGENCY_DELAY);
        v2.setRedemptionExt(address(new RedemptionExt()));

        v1.setSuccessor(address(v2));
        v1.armEmergency();
        _warp(EMERGENCY_DELAY);
        v1.migrateToSuccessor();

        hook.proposeRegistryOverride(address(v2));
        _warp(7 days);
        hook.executeRegistryOverride();
        hook.setOpener(address(v2), true);
        hook.setTaxExempt(address(v2), true);
    }

    function _redeem(CauldronRegistry r, address who, uint256 id) internal returns (bool ok, bytes memory err) {
        vm.prank(who);
        (ok, err) = address(r).call(abi.encodeWithSignature("redeemOgFren(uint256)", id));
    }

    // -----------------------------------------------------------------------
    // H0 — the route itself runs, and custody really moves
    // -----------------------------------------------------------------------

    /// The mechanical handover works: v2 owns both LP positions and the hook
    /// answers to v2. This is the part that was already known to work.
    function test_H0_HandoverMovesCustodyAndHook() public {
        uint256 activeId = v1.generationPositionId(1);
        uint256 reserveId = v1.generationReservePositionId(1);
        _handover();
        assertEq(IERC721(posm).ownerOf(activeId), address(v2), "v2 owns the active LP");
        assertEq(IERC721(posm).ownerOf(reserveId), address(v2), "v2 owns the reserve LP");
        assertEq(hook.registry(), address(v2), "hook re-pointed to v2");
    }

    // -----------------------------------------------------------------------
    // H1 — v2 owns the LP but knows nothing about it
    // -----------------------------------------------------------------------

    /// `migrateToSuccessor` moves the position NFTs and loose balances. It moves
    /// NO STATE: generation, tokens, reserve ticks, genesis floor, treasury count.
    /// There is no export on v1 and no import on v2, so a successor built from
    /// today's code holds the whole LP with an empty ledger.
    /// FIXED SYSTEM: v2 is constructed from (or imports) a verified v1 snapshot.
    function test_H1_SuccessorInheritsNoState() public {
        uint256 floorBefore = v1.floorPerFren();
        assertGt(floorBefore, 0, "control: v1 prices the genesis floor");
        _handover();

        assertFalse(v2.summoned(), "v2 was never summoned");
        assertEq(v2.currentGeneration(), 0, "v2 knows no generation");
        assertEq(v2.currentToken(), address(0), "v2 knows no token");
        assertEq(v2.floorPerFren(), 0, "v2 prices no genesis floor");
    }

    // -----------------------------------------------------------------------
    // H2 — the genesis collection cannot follow the successor (F14)
    // -----------------------------------------------------------------------

    /// `migrateToSuccessor`'s docstring says the MiFrens custody pointer is
    /// re-homed by governance via `mifrens.setRegistry(successor)`. That call is
    /// deployer-only and one-shot. `custodyTransfer` — the primitive behind OG
    /// redemption and treasury resale — therefore stays bound to v1 forever.
    /// FIXED SYSTEM: the collection re-points through an armed, delayed pair.
    function test_H2_GenesisCannotRepointToSuccessor() public {
        _handover();

        vm.expectRevert(MiFrensGenesis.RegistryAlreadySet.selector);
        genesis.setRegistry(address(v2)); // this test contract IS the deployer

        vm.prank(address(v2));
        vm.expectRevert(MiFrensGenesis.NotAuthorized.selector);
        genesis.custodyTransfer(alice, address(v2), 1);
    }

    // -----------------------------------------------------------------------
    // H3 — the OG exit is closed on BOTH sides after the handover
    // -----------------------------------------------------------------------

    /// Before: an OG redeems through v1 (control). After: the same call fails on
    /// v1 (it no longer owns the reserve position) AND on v2 (no state, and even
    /// with state it could not move the fren — H2). A fren already in v1's
    /// treasury can never be resold either, so it is stranded.
    /// FIXED SYSTEM: the redeem that failed on v1 succeeds on v2.
    function test_H3_OgExitClosedOnBothSides() public {
        (bool okBefore,) = _redeem(v1, alice, 1);
        assertTrue(okBefore, "control: OG redeems through v1 before the handover");
        assertEq(genesis.ownerOf(1), address(v1), "control: fren 1 is in v1's treasury");

        _handover();

        (bool okV1, bytes memory errV1) = _redeem(v1, bob, 6);
        assertFalse(okV1, "v1 can no longer redeem");
        //  Pinned: the PositionManager refuses v1 because v2 now owns the reserve.
        assertEq(errV1, abi.encodeWithSelector(IPositionManagerErrors.NotApproved.selector, address(v1)), "v1: NotApproved");

        (bool okV2, bytes memory errV2) = _redeem(v2, bob, 6);
        assertFalse(okV2, "v2 cannot redeem either");
        //  Pinned: v2 holds the LP but was never summoned (H1).
        assertEq(errV2, abi.encodeWithSelector(CauldronBase.NotSummoned.selector), "v2: NotSummoned");
        assertEq(genesis.ownerOf(6), bob, "bob keeps a fren whose floor is unreachable");

        // The treasury fren: resale fails on both sides; it never leaves v1.
        vm.deal(carol, 1 ether);
        vm.prank(carol);
        (bool buyV1,) = address(v1).call(abi.encodeWithSignature("buyTreasuryOgFren(uint256)", 1));
        vm.prank(carol);
        (bool buyV2,) = address(v2).call(abi.encodeWithSignature("buyTreasuryOgFren(uint256)", 1));
        assertFalse(buyV1 || buyV2, "no registry can resell the treasury fren");
        assertEq(genesis.ownerOf(1), address(v1), "fren 1 is stranded in v1's custody");
    }

    // -----------------------------------------------------------------------
    // H4 — a moved fren can never earn again after the handover
    // -----------------------------------------------------------------------

    /// A moved fren pays a re-enchant fee that the dividend routes into
    /// `registry.donateToReserve`. The dividend's registry is one-shot, so after
    /// the handover the fee goes to v1, which no longer owns the reserve.
    /// FIXED SYSTEM: the dividend follows the successor (or v2 redeploys it and
    /// the collection re-points its dividend) and the post-handover cast succeeds.
    function test_H4_MovedFrenCannotReEnchant() public {
        // Two moved frens: alice sells #2 and #3 to carol.
        vm.startPrank(alice);
        genesis.transferFrom(alice, carol, 2);
        genesis.transferFrom(alice, carol, 3);
        vm.stopPrank();
        assertTrue(genesis.everMoved(2) && genesis.everMoved(3), "both moved");

        uint256 fee = v1.enchantFee();
        assertGt(fee, 0, "moved frens pay to re-enchant");
        deal(token1, carol, 10 * fee);
        vm.prank(carol);
        IERC20(token1).approve(address(dividend), type(uint256).max);

        // Control: before the handover the paid re-enchant works.
        vm.prank(carol);
        dividend.castSpell(2);
        assertTrue(dividend.isEnchanted(2), "control: fren 2 earns again");

        vm.expectRevert(MiFrensDividend.NotOwner.selector);
        dividend.setRegistry(address(v2)); // one-shot, even for the treasury wirer

        _handover();

        vm.prank(carol);
        (bool ok, bytes memory err) = address(dividend).call(abi.encodeWithSignature("castSpell(uint256)", 3));
        assertFalse(ok, "fren 3 can never re-enchant: its fee has nowhere to go");
        //  Pinned: the fee reaches v1.donateToReserve, and the PositionManager
        //  refuses v1 because v2 owns the reserve position.
        assertEq(err, abi.encodeWithSelector(IPositionManagerErrors.NotApproved.selector, address(v1)), "NotApproved(v1)");
        assertFalse(dividend.isEnchanted(3), "fren 3 stays out of the earning set");
    }

    // -----------------------------------------------------------------------
    // H5 — v2 can never burn a v1-era token
    // -----------------------------------------------------------------------

    /// `CauldronToken.registry` is immutable. Today's registry burns the dying
    /// generation's recovered tokens at relaunch (step 3a) and burns a holder's
    /// old tokens in `claimByBurn`; a successor running the same code reverts on
    /// both for every generation v1 created.
    /// FIXED SYSTEM: v2 retires foreign-generation tokens by lock/transfer-to-dead.
    function test_H5_SuccessorCannotBurnV1EraTokens() public {
        (bool ok,) = _redeem(v1, alice, 1);
        assertTrue(ok, "control: alice holds real gen-1 tokens");
        uint256 bal = IERC20(token1).balanceOf(alice);
        assertGt(bal, 0, "alice has tokens to migrate");

        _handover();

        vm.prank(address(v2));
        vm.expectRevert(CauldronToken.NotRegistry.selector);
        CauldronToken(token1).burn(alice, bal);

        vm.prank(address(v1));
        CauldronToken(token1).burn(alice, 1); // only the dead registry still can
        assertEq(IERC20(token1).balanceOf(alice), bal - 1, "v1 alone holds the burn right");
    }

    // -----------------------------------------------------------------------
    // H6 — old-generation migration dies at the handover
    // -----------------------------------------------------------------------

    /// `claimByBurn` (gen N → gen N+1, 1:1) is the path any cross-chain migration
    /// is built on. Control: after a real relaunch to gen 2 (which also CONTINUES
    /// the real MiFrens collection), a gen-1 holder migrates through v1. After the
    /// handover the same call fails on v1 (reserve moved) and on v2 (no state —
    /// and H5: no burn right over gen-1 tokens even with state).
    /// FIXED SYSTEM: the remaining gen-1 balance migrates through v2.
    function test_H6_OldGenMigrationDiesAtHandover() public {
        (bool ok,) = _redeem(v1, alice, 1); // alice now holds gen-1 tokens
        assertTrue(ok, "control: redeem");

        _warp(26 hours); // zero volume + past minLifetime → gen 1 reads dead
        (bool relaunched, bytes memory rerr) = address(v1).call(abi.encodeWithSignature("relaunch()"));
        if (!relaunched) emit log_named_bytes("relaunch revert", rerr);
        assertTrue(relaunched, "control: v1 relaunches to gen 2");
        assertEq(v1.currentGeneration(), 2, "gen 2 live");
        assertEq(genesis.minter(), address(hook), "gen 2 continues the real MiFrens");

        uint256 bal = IERC20(token1).balanceOf(alice);
        assertGt(bal, 1, "alice holds gen-1 tokens");
        vm.prank(alice);
        v1.claimByBurn(1, bal / 2);
        assertEq(IERC20(token1).balanceOf(alice), bal - bal / 2, "control: half migrated through v1");

        _handover();
        uint256 rest = IERC20(token1).balanceOf(alice);

        vm.prank(alice);
        (bool okV1, bytes memory e1) =
            address(v1).call(abi.encodeWithSignature("claimByBurn(uint256,uint256)", 1, rest));
        assertFalse(okV1, "v1 can no longer migrate gen-1 holders");
        //  Pinned: the burn succeeds, then the 1:1 pull from the reserve is refused
        //  because v2 owns it — the whole call reverts and nothing is lost, but
        //  nothing can ever migrate either.
        assertEq(e1, abi.encodeWithSelector(IPositionManagerErrors.NotApproved.selector, address(v1)), "v1: NotApproved");

        vm.prank(alice);
        (bool okV2, bytes memory e2) =
            address(v2).call(abi.encodeWithSignature("claimByBurn(uint256,uint256)", 1, rest));
        assertFalse(okV2, "v2 cannot migrate them either");
        //  Pinned: v2's generation counter is 0, so gen 1 reads as "not a past gen".
        assertEq(e2, abi.encodeWithSelector(CauldronBase.CannotClaimCurrentGen.selector), "v2: CannotClaimCurrentGen");
        assertEq(IERC20(token1).balanceOf(alice), rest, "the rest of alice's gen-1 balance is stuck");
    }
}
