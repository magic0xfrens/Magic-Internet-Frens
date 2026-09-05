// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronFactory} from "../cauldron/CauldronFactory.sol";
import {CauldronCollection} from "../cauldron/CauldronCollection.sol";
import {MetadataMode} from "../cauldron/ICauldron.sol";

/**
 * @dev The factory's badge-renderer wiring.
 *
 *  THIS IS THE TEST THAT DID NOT EXIST, and its absence took down a live
 *  ignition. CauldronFactory only calls setLiquidatorRenderer when its own
 *  renderer is non-zero, and every existing test constructed the factory fresh
 *  with a ZERO renderer — so that branch was dead in all 409 of them. It first
 *  executed on Sepolia, where DeployLaunchpad does set a renderer, and reverted
 *  OnlyMinter: `deployer` on a collection is the REGISTRY (audit H-01), not the
 *  factory, so the factory could not configure the collection it had just
 *  deployed. The whole summon reverted with it.
 */
contract FactoryBadgeWiringTest is Test {
    CauldronFactory factory;

    address constant REGISTRY = address(0x9E6);
    address constant HOOK     = address(0x8001);
    address constant RENDERER = address(0xBADE);

    function setUp() public {
        factory = new CauldronFactory();
    }

    function _cfg() internal pure returns (CauldronFactory.Config memory) {
        return CauldronFactory.Config({
            name: "Gnomeland",
            symbol: "GNOME",
            hook: HOOK,
            registry: REGISTRY,
            maxSupply: 3333,
            mode: MetadataMode.BaseURI,
            baseURI: "ipfs://gnome/",
            renderer: address(0),
            royaltyReceiver: address(0xD19),
            royaltyBps: 500
        });
    }

    /// The live failure, reproduced: a factory WITH a renderer must still be
    /// able to deploy a brew. This reverted OnlyMinter before the guard fix.
    function test_DeployBrewSucceedsWithARendererSet() public {
        factory.setLiquidatorRenderer(RENDERER);
        (address col, ) = factory.deployBrew(_cfg());

        assertEq(
            CauldronCollection(col).liquidatorRenderer(), RENDERER,
            "the factory must be able to wire the renderer it was given"
        );
    }

    /// The path every previous test took, kept so the zero case stays covered.
    function test_DeployBrewStillWorksWithNoRenderer() public {
        (address col, ) = factory.deployBrew(_cfg());
        assertEq(CauldronCollection(col).liquidatorRenderer(), address(0), "no renderer, no wiring");
    }

    /// Every iteration deploys a FRESH collection, so the renderer has to be
    /// applied each time — otherwise only the first brew renders badges
    /// on-chain and every later one silently falls back to a hosted URI.
    function test_EveryBrewGetsTheRenderer() public {
        factory.setLiquidatorRenderer(RENDERER);
        for (uint256 i; i < 3; ++i) {
            (address col, ) = factory.deployBrew(_cfg());
            assertEq(CauldronCollection(col).liquidatorRenderer(), RENDERER, "every brew, not just the first");
        }
    }

    /// The factory may configure a collection it deployed; nobody else may.
    function test_StrangerCannotRepointTheRenderer() public {
        factory.setLiquidatorRenderer(RENDERER);
        (address col, ) = factory.deployBrew(_cfg());

        vm.prank(address(0xBAD));
        vm.expectRevert(CauldronCollection.OnlyMinter.selector);
        CauldronCollection(col).setLiquidatorRenderer(address(0xE711));
    }
}
