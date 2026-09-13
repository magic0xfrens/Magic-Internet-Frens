// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";

import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {CauldronSeeder} from "../../cauldron/CauldronSeeder.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../../cauldron/ICauldron.sol";

/**
 * K5b — THE WHOLE PROGRESSIVE LAUNCH SEEDER IS DEAD CODE, AND FUNDING IT LOCKS ETH.
 *
 *  PoolOps.sol:168   `uint256 internal constant SEED_BASE_WAD = 1e18;`
 *  PoolOps.sol:395-6 `uint256 baseTok = (activeTokens * SEED_BASE_WAD) / 1e18;`
 *                    `uint256 baseEth = (ethAmount   * SEED_BASE_WAD) / 1e18;`
 *  PoolOps.sol:405   `if (activeTokens <= baseTok || ethAmount <= baseEth) return r;`
 *  PoolOps.sol:409-10 (unreachable) `IERC20(token).approve(sp.seeder, ...);`
 *                                   `ISeeder(sp.seeder).startSeed{value: ...}(...)`
 *
 *  With SEED_BASE_WAD == 1e18 the two equalities always hold, so the early return
 *  ALWAYS fires and `startSeed` is never called from anywhere in the tree
 *  (it is `onlyRegistry`, and PoolOps.sol:410 is its only call site).
 *
 *  Consequences proven below:
 *   1. `registry.setSeedWindow(w>0)` + `registry.setSeeder(s)` read as "progressive
 *      armed" but the campaign never starts: seeding=false, gen=0, token=0.
 *   2. `fundPrime` (CauldronSeeder.sol:338) accepts ETH from the deployer/registry
 *      owner, but `primePending` (:364) returns 0 forever because `!seeding`.
 *   3. That ETH cannot come back. `withdrawAll` is onlyRegistry and the registry
 *      only calls it behind `ISeeder(_seeder).seeding()`; the break-glass
 *      `registry.rescueSeeder()` -> `CauldronSeeder.rescue` (:838) reverts, because
 *      `token` was never assigned by `startSeed` and
 *      `IERC20(address(0)).balanceOf(...)` reverts on an empty account.
 */
contract K5b_ProgressiveSeederUnreachable is Test {
    CauldronHook hook;
    CauldronRegistry registry;
    CauldronSeeder seeder;
    IPoolManager pm;
    bool active;

    uint64 constant WINDOW = 3600;
    address constant TREASURY = address(0x00000000000000000000000000000000000Add11);
    address constant STRANGER = address(0x00000000000000000000000000000000000baD11);

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
        address posm = vm.envAddress("POSITION_MANAGER");
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

        // emergencyAdmin = this, delay = 0 → the break-glass path is fully available.
        registry = new CauldronRegistry(poolManager, posm, address(hook), address(this), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));

        seeder = new CauldronSeeder(address(registry), posm, poolManager);
        registry.setSeeder(address(seeder));
        registry.setSeedWindow(WINDOW);
        hook.setOpener(address(seeder), true);
        hook.setTaxExempt(address(seeder), true);

        vm.deal(address(this), 100 ether);
    }

    function test_K5b_ProgressiveSeedNeverStarts_AndPrimeFundingIsLocked() public {
        require(active, "FORK_RPC/POOL_MANAGER/POSITION_MANAGER must be exported");

        // --- POSITIVE: the launch itself works and the config reads as armed. ---
        registry.setGovernor(address(new K5bGov()));
        assertEq(registry.seeder(), address(seeder), "positive: seeder wired");
        assertEq(registry.nextSeedWindow(), WINDOW, "positive: progressive window armed");

        uint256 seederEthBefore = address(seeder).balance;
        (address token,) = registry.summon{value: 1 ether}();
        assertTrue(token != address(0), "positive: generation 1 summoned");
        assertGt(registry.generationPositionId(1), 0, "positive: a pool was seeded");

        // --- DEFECT 1: the campaign the config promised never begins. ---
        bool seeding = seeder.seeding();
        uint256 sgen = seeder.gen();
        address stok = seeder.token();
        uint256 eth = seeder.ethTotal();
        emit log_named_uint("seeder.seeding()", seeding ? 1 : 0);
        emit log_named_uint("seeder.gen()", sgen);
        emit log_named_address("seeder.token()", stok);
        emit log_named_uint("seeder.ethTotal()", eth);
        assertFalse(seeding, "DEAD FEATURE: startSeed never ran on an armed progressive summon");
        assertEq(sgen, 0, "DEAD FEATURE: no campaign generation recorded");
        assertEq(stok, address(0), "DEAD FEATURE: no campaign token recorded");
        assertEq(eth, 0, "DEAD FEATURE: no ledger-A ETH handed over");
        assertEq(address(seeder).balance - seederEthBefore, 0, "DEAD FEATURE: no ETH handed over");

        // --- DEFECT 2: the prime budget is accepted and immediately inert. ---
        seeder.fundPrime{value: 1 ether}(TREASURY);
        assertEq(seeder.primeBudget(), 1 ether, "prime budget booked");
        assertEq(seeder.primePending(), 0, "prime buy can never fire (!seeding)");
        seeder.poke(); // permissionless, and a total no-op
        assertEq(seeder.primeSpent(), 0, "poke spends nothing");
        assertEq(seeder.deployedWad(), 0, "poke streams nothing");

        // --- FIXED (K5b): the funder can take an unspendable budget back out. ---
        // A stranger cannot: refundPrime is the same principal gate as fundPrime.
        vm.prank(STRANGER);
        vm.expectRevert();
        seeder.refundPrime(STRANGER);
        assertEq(address(seeder).balance - seederEthBefore, 1 ether, "stranger moved nothing");

        uint256 treasuryBefore = TREASURY.balance;
        seeder.refundPrime(TREASURY); // caller == the seeder's deployer EOA
        assertEq(TREASURY.balance - treasuryBefore, 1 ether, "K5b FIXED: the 1 ETH came back");
        assertEq(address(seeder).balance - seederEthBefore, 0, "K5b FIXED: nothing left trapped");
        assertEq(seeder.primeBudget(), 0, "K5b FIXED: budget accounting cleared");
        assertEq(seeder.primeTo(), address(0), "K5b FIXED: recipient unpinned again");

        // --- FIXED (K5c): the break-glass hatch also works pre-campaign now. ---
        seeder.fundPrime{value: 0.5 ether}(TREASURY);
        assertEq(address(seeder).balance - seederEthBefore, 0.5 ether, "re-funded for the rescue leg");
        registry.armEmergency();
        bool rescueWorks = _tryRescue();
        assertTrue(rescueWorks, "K5c FIXED: registry.rescueSeeder() no longer reverts pre-campaign");
        assertEq(address(seeder).balance - seederEthBefore, 0, "K5c FIXED: rescue swept the ETH out");
    }

    function _tryRescue() internal returns (bool ok) {
        try registry.rescueSeeder() { ok = true; }
        catch { ok = false; }
    }

    receive() external payable {}
}

contract K5bGov is ICauldronGovernor {
    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external {}
    function winner() external pure returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Ethereal Spirit", symbol: "SPIRIT", mode: MetadataMode.BaseURI,
            baseURI: "ipfs://spirit/", renderer: address(0), website: "spirit.xyz",
            socials: "x.com/spirit", quote: address(0), nftSupply: 1000, volumePerNFT: 0, proposer: address(0xBEEF)
        });
        id = 1;
    }
}
