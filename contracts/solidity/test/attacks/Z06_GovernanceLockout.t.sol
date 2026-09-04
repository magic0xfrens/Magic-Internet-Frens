// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ZAuditBase, ZMockGovernor} from "./ZAuditBase.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

/**
 * FINDING Z-06 (High) — registry ownership is BURNED into the presale contract, so
 * every `onlyOwner` registry setter becomes permanently unreachable at ignition.
 *
 *   deploy/DeployLaunchpad.s.sol:254
 *       IOwnable(address(registry)).transferOwnership(address(presale));
 *
 * `MiFrensGenesis` calls exactly one registry function (`summon()`, from
 * `finalize()`), exposes no generic forwarder, and has no fallback. From ignition
 * onward NOBODY — not the deployer, not the governance timelock — can ever call:
 *
 *   setGovernor, setFactory, setSeeder, setSeedWindow, setReserveCeiling,
 *   setCollectionLedger, setNftMaxSupply, setRoyalty, setGenesisMetadata,
 *   setRedemptionExt, setGenesisBonus, setAirdropReserve, setPrimeFunder
 *
 * That directly contradicts the NatSpec on several of them, e.g.
 *   CauldronRegistry.setReserveCeiling:154  "Owner = timelock; picked per iteration"
 *   CauldronRegistry.setSeedWindow:195      "Owner = timelock, chosen per iteration"
 *
 * Operationally: a spammed governor (Z-03) or a broken factory could never be
 * replaced, and both are called from inside `relaunch()`.
 *
 * STATUS: FIXED. Ignition is now its own role — `CauldronBase.igniter`, set via
 * `setIgniter` — so `summon()` accepts the owner OR the igniter. The deploy script
 * grants the presale the igniter role and hands OWNERSHIP to the governance timelock,
 * which keeps every economic setter reachable for the life of the protocol.
 *
 * FINDING Z-08 (Medium) — `setClaimGate` froze ALL 1:1 migration instantly, with no
 * timelock, no guardian veto and no exit-guarantee override.
 * STATUS: FIXED, asymmetrically — RESTRICTING migration now consumes the armed
 * emergency timelock (and is therefore announced and guardian-vetoable), while
 * RESTORING instant migration stays immediate.
 *
 * FINDING Z-09 (Medium) — crystal credit accrued on ANY tracked pool, including
 * retired generations. STATUS: FIXED, accrual is gated on the live pool's token.
 */
contract Z06_GovernanceLockout is ZAuditBase {
    address internal token1;
    PoolId internal pid;

    function setUp() public {
        _bootstrap(1 ether);
        if (!active) return;
        registry.setGovernor(address(new ZMockGovernor(address(0xBEEF))));
        (token1, pid) = registry.summon{value: 10 ether}();
    }

    // -----------------------------------------------------------------------
    // Z-06 — ownership lockout
    // -----------------------------------------------------------------------

    /// REGRESSION: ownership stays with governance while the presale keeps exactly the
    /// right it needs, so every economic setter survives ignition.
    function test_FIXED_IgniterRoleKeepsOwnershipWithGovernance() public {
        if (!active) return;

        // A fresh registry wired exactly as DeployLaunchpad wires the real one.
        address timelock = address(0x71E0);
        CauldronRegistry reg = new CauldronRegistry(address(pm), posm, address(hook), timelock, 48 hours);
        MiFrensGenesis presale =
            new MiFrensGenesis("MiFrens", "MIFREN", 1111, 2222, 0.0062 ether, 100, "https://x/");

        // The NEW wiring: delegate ignition, hand ownership to governance.
        reg.setGovernor(address(0xAAA1));
        reg.setIgniter(address(presale));
        reg.transferOwnership(timelock);
        assertEq(reg.owner(), timelock, "FIXED: owner is the governance timelock");
        assertEq(reg.igniter(), address(presale), "presale holds only the ignition right");

        // Governance retains every economic setter, for the life of the protocol.
        vm.startPrank(timelock);
        reg.setGovernor(address(0xAAA2));
        reg.setSeedWindow(3600); // NatSpec: "Owner = timelock, chosen per iteration"
        reg.setReserveCeiling(50_000); // NatSpec: "Owner = timelock; picked per iteration"
        reg.setFactory(address(0xF00D));
        vm.stopPrank();
        assertEq(address(reg.governor()), address(0xAAA2), "FIXED: governor is replaceable");
        assertEq(reg.nextSeedWindow(), 3600, "FIXED: seed window is tunable per iteration");

        // The igniter role is NOT a general power: it cannot touch any owner setter.
        vm.prank(address(presale));
        vm.expectRevert();
        reg.setGovernor(address(0xAAA3));

        // ... and a stranger can neither ignite nor configure.
        vm.prank(address(0xBAD));
        vm.expectRevert(); // NotAdmin()
        reg.summon{value: 0}();
    }

    /// The emergency admin retains its own (separate) powers, so safety survives even
    /// though economic tuning does not. Recorded as the mitigating boundary.
    function test_SAFE_EmergencyAdminPowersSurviveTheHandoff() public {
        if (!active) return;
        address timelock = address(0x71E0);
        CauldronRegistry reg = new CauldronRegistry(address(pm), posm, address(hook), timelock, 48 hours);
        reg.transferOwnership(address(0xDEAD));

        vm.prank(timelock);
        reg.setMinLifetime(2 hours); // onlyEmergency, not onlyOwner
        assertEq(reg.minLifetime(), 2 hours, "emergency admin still functions");

        vm.prank(timelock);
        reg.setRedemptionPaused(true);
        assertTrue(reg.redemptionPaused(), "circuit breaker still reachable");
    }

    // -----------------------------------------------------------------------
    // Z-08 — instant, un-vetoable migration freeze
    // -----------------------------------------------------------------------

    /// REGRESSION: restricting migration is now an ANNOUNCED, delayed, vetoable action;
    /// restoring it stays instant. Uses a registry with a real (48h) emergency delay.
    function test_FIXED_ClaimGateRequiresArmedTimelock() public {
        if (!active) return;
        CauldronRegistry reg = new CauldronRegistry(address(pm), posm, address(hook), address(this), 48 hours);

        // Un-announced restriction is refused.
        vm.expectRevert(); // Timelocked()
        reg.setClaimGate(address(0xBEEF));
        assertEq(reg.claimGate(), address(0), "migration stays open");

        // Announce, and the exit is forced open for the whole waiting window.
        reg.armEmergency();
        assertGt(reg.emergencyReadyAt(), 0, "action is announced on-chain");
        vm.expectRevert(); // still inside the delay
        reg.setClaimGate(address(0xBEEF));

        // The guardian can VETO the announced restriction.
        reg.setGuardian(address(this));
        reg.vetoEmergency();
        assertEq(reg.emergencyReadyAt(), 0, "FIXED: the freeze is guardian-vetoable");

        // Re-announce, wait it out, and only then may it land.
        reg.armEmergency();
        vm.warp(reg.emergencyReadyAt());
        reg.setClaimGate(address(0xBEEF));
        assertEq(reg.claimGate(), address(0xBEEF), "restriction applied after the delay");

        // RESTORING instant migration is never delayed (the safe direction).
        reg.setClaimGate(address(0));
        assertEq(reg.claimGate(), address(0), "FIXED: un-freezing is immediate");
    }

    // -----------------------------------------------------------------------
    // Z-09 — fee/credit accrual is gated on `trackedPools`, never on the LIVE pool
    // -----------------------------------------------------------------------

    /// REGRESSION: retired generations still stay `trackedPools` (their fees remain
    /// collectable), but crystal credit is now accrued ONLY for the live pool's token,
    /// so a dead pool an attacker re-provisions and prices themselves cannot farm the
    /// newborn collection.
    function test_FIXED_RetiredPoolEarnsNoCrystalCredit() public {
        if (!active) return;

        vm.roll(block.number + hook.snipeWindowBlocks() + 1);
        _buyExactIn(2 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        registry.relaunch();

        PoolId gen1 = registry.generationPoolId(1);
        PoolId gen2 = registry.generationPoolId(2);
        assertTrue(PoolId.unwrap(gen1) != PoolId.unwrap(gen2), "distinct pools");

        // The retired pool is still "served": full fee logic, volume tracking and
        // crystal-credit accrual in the LIVE epoch all still apply to it.
        assertTrue(hook.trackedPools(gen1), "retired gen-1 pool remains tracked");
        assertTrue(hook.trackedPools(gen2), "live pool tracked");
        // The hook now uses the live key to gate accrual, not merely to gate spending.
        assertEq(
            Currency.unwrap(hook.liveKey().currency1),
            registry.currentToken(),
            "FIXED: accrual is gated on THIS token"
        );

        // A swap on the LIVE pool still earns credit, proving the gate is not a blanket
        // disable.
        uint256 before = hook.creditOf(address(this));
        _buyExactIn(0.2 ether);
        assertGt(hook.creditOf(address(this)), before, "live-pool trading still earns credit");
    }
}
