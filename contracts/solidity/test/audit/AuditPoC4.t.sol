// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {CauldronCollection} from "../../cauldron/CauldronCollection.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../../cauldron/ICauldron.sol";
import {CauldronGovernor} from "../../cauldron/CauldronGovernor.sol";

/// A ROGUE governor whose winning proposal carries an out-of-range `nftSupply`.
/// The real {CauldronGovernor} now rejects this at `propose` time, so this mock
/// stands in for "a governor swapped in later, or any future governor with a bug".
/// The registry must survive it regardless — which is why the fix CLAMPS in
/// `relaunch` rather than trusting the governor. (Audit C-02.)
contract PoisonGov is ICauldronGovernor {
    uint256 public supply;
    bool public consumed;
    constructor(uint256 s) { supply = s; }
    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external { consumed = true; }
    function winner() external view returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Poison", symbol: "PSN", mode: MetadataMode.BaseURI,
            baseURI: "ipfs://p/", renderer: address(0), website: "", socials: "",
            nftSupply: supply, volumePerNFT: 0, proposer: address(0xBEEF)
        });
        id = 1;
    }
}

// ───────────────────────────────────────────────────────────────────────────────
// PoC 12 / REGRESSION — a winning BrewSpec with `nftSupply >= 1_000_000` used to
//          make `relaunch()` revert FOREVER: the collection constructor rejected
//          it, and because `markConsumed` ran in the same transaction the poisoned
//          proposal was rolled back too and won again every time. `setGovernor` is
//          `onlyOwner`, and the deploy script hands ownership to the presale
//          contract — which exposes no call to it — so the freeze was
//          unrecoverable short of a full V2 migration.          (audit C-02)
//          FIXED on two independent layers: the governor bounds `nftSupply` at
//          `propose` time, and `relaunch` CLAMPS it defensively so even a rogue
//          governor cannot freeze the machine.
// ───────────────────────────────────────────────────────────────────────────────
contract PoC_PoisonProposalBricksRelaunch is Test {
    CauldronHook hook;
    CauldronRegistry registry;
    IPoolManager pm;
    address token;
    bool active;

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
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(IPoolManager(poolManager), 1 ether, address(0), address(this), address(this));
        require(address(hook) == hookAddr, "hook addr");

        registry = new CauldronRegistry(poolManager, positionManager, address(hook), address(0), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));

        vm.deal(address(this), 100 ether);
        (token,) = registry.summon{value: 2 ether}();
    }

    function test_Fixed_OversizedNftSupplyCannotBrickRelaunch() public {
        if (!active) return;

        PoisonGov gov = new PoisonGov(1_000_000); // == LIQUIDATOR_ID_BASE
        registry.setGovernor(address(gov));

        // Kill gen-1 the normal way.
        hook.setDeathThreshold(1 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        assertTrue(hook.isDead(registry.generationPoolId(1)), "gen-1 dead");

        // FIXED: relaunch CLAMPS the hostile supply instead of reverting, so the
        // machine keeps turning even against a rogue governor.
        registry.relaunch();
        assertEq(registry.currentGeneration(), 2, "FIXED: rebirth succeeded");
        assertTrue(gov.consumed(), "FIXED: the proposal was actually retired");

        address col = registry.generationCollection(2);
        assertEq(
            CauldronCollection(col).maxSupply(), registry.MAX_NFT_SUPPLY(),
            "FIXED: clamped to the safe ceiling"
        );
        assertLt(
            CauldronCollection(col).maxSupply(), CauldronCollection(col).LIQUIDATOR_ID_BASE(),
            "art ids can never collide with badge ids"
        );
    }

    /// The other half of the fix: the REAL governor refuses to record such a
    /// proposal at all, so the clamp is a second line of defence rather than the
    /// only one.
    function test_Fixed_GovernorRejectsOversizedProposal() public {
        if (!active) return;
        MiniVotes votes = new MiniVotes();
        CauldronGovernor real = new CauldronGovernor(address(votes));
        vm.expectRevert(CauldronGovernor.SupplyOutOfRange.selector);
        real.propose("X", "X", MetadataMode.BaseURI, "ipfs://x/", address(0), "", "", 1_000_000, 0);
        // ...and accepts anything within the bound.
        real.propose("X", "X", MetadataMode.BaseURI, "ipfs://x/", address(0), "", "", 3333, 0);
    }

    receive() external payable {}
}

/// Minimal IVotes stand-in so the real governor's proposer gate passes.
contract MiniVotes {
    function getVotes(address) external pure returns (uint256) { return 1; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1; }
    function delegates(address) external pure returns (address) { return address(0); }
}

contract SaneGov is ICauldronGovernor {
    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external {}
    function winner() external pure returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Sane", symbol: "SANE", mode: MetadataMode.BaseURI,
            baseURI: "ipfs://s/", renderer: address(0), website: "", socials: "",
            nftSupply: 1000, volumePerNFT: 0, proposer: address(0xBEEF)
        });
        id = 1;
    }
}
