// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronGovernor} from "../../cauldron/CauldronGovernor.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";

/// @dev 1 NFT = 1 vote; every caller may propose.
contract T9fVotes {
    function getVotes(address) external pure returns (uint256) { return 1; }
}

/// @dev The registry, as far as the governor is concerned: the quote allowlist and
///      the hook pointer both bounds walk through.
contract T9fRegistry {
    address public hook;
    constructor(address h) { hook = h; }
    function allowedQuote(address) external pure returns (bool) { return true; }
}

/**
 * @notice T9f — the `volumePerNFT` twin of audit Z-09 (red-team T-2).
 *
 *  THE BUG. `CauldronGovernor.propose` bounded `nftSupply` on BOTH sides after
 *  f96d42f, but `volumePerNFT` had no bound at all. That figure flows from the
 *  winning proposal through `CauldronRegistry.sol:1134` into
 *  `CauldronHook.setNftCurveFrom`, which writes `volumePerNFT = _base` and
 *  `nftPriceStep = 0` — a FLAT ladder. With no {MintCurvePolicy} wired,
 *  `nftPriceAt(k)` is then `volumePerNFT + k * 0`, i.e. the SAME price for every
 *  rung, so a proposal naming 1 wei mints the whole collection out — every
 *  dividend share and the entire claim on a floor funded by `floorBps` of that
 *  generation's fee revenue — for `nftSupply` wei of weighted buy credit.
 *
 *  THE FIX. `propose` refuses a non-zero `volumePerNFT` more than `CURVE_BAND`
 *  (1000x) either side of the LIVE ladder's base. The band is relative, not an
 *  absolute wei floor, because the credit it is compared against is re-denominated
 *  (`setDeathThreshold` restates the whole ladder into USD-at-1e18) and a
 *  generation may be quoted in a 6-decimal asset. 1000x is exactly the range an
 *  honest proposer needs to hold the mint-out TARGET constant across the full
 *  [100, 100_000] `nftSupply` range, and no wider.
 *
 *  Both halves are asserted: the damage is real on a REAL {CauldronHook}, and the
 *  proposal that causes it can no longer be made.
 */
contract T9fProposalMintCurveFloor is Test {
    CauldronHook internal hook;
    CauldronGovernor internal gov;
    T9fRegistry internal reg;

    function setUp() public {
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        // poolManager may be any address here: nothing in this test swaps, and the
        // BaseHook constructor only validates the permission bits of its own address.
        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(1)), uint256(1 ether), address(0), address(this), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(IPoolManager(address(1)), 1 ether, address(0), address(this), address(this));
        require(address(hook) == hookAddr, "hook addr");

        // This test contract plays the registry, so it can drive the exact call
        // `relaunch()` makes with the winning proposal's figure.
        hook.setRegistry(address(this));

        reg = new T9fRegistry(address(hook));
        gov = new CauldronGovernor(address(new T9fVotes()), 0);
        gov.setRegistry(address(reg));
    }

    function _propose(uint256 volumePerNFT) internal returns (uint256) {
        return gov.propose(
            "Brew", "BRW", MetadataMode.BaseURI, "ipfs://brew/", address(0),
            "", "", 0, volumePerNFT, address(0)
        );
    }

    /// @dev Total weighted buy credit needed to mint out a collection of `n` frens
    ///      on the hook's LIVE ladder — the real `nftPriceAt`, no mock.
    function _mintOutCost(uint256 n) internal view returns (uint256 t) {
        for (uint256 k; k < n; ++k) t += hook.nftPriceAt(k);
    }

    /**
     * @dev THE DAMAGE, on the real hook. `setNftCurveFrom` is exactly what
     *      `relaunch()` calls (CauldronRegistry.sol:1134) with the winning
     *      proposal's `volumePerNFT`. 1 wei flattens the whole ladder to 1 wei.
     */
    function test_ProposalMintCurveFloor() public {
        uint256 honestBase = hook.volumePerNFT();
        assertEq(honestBase, 0.02 ether, "the shipped ladder starts at 0.02 ether a fren");
        uint256 honestCost = _mintOutCost(1000);
        emit log_named_uint("mint-out cost, 1000 frens, shipped ladder (wei)", honestCost);
        assertGt(honestCost, 20 ether, "an honest 1000-fren collection costs >20 ETH of credit");

        // A winning proposal mandating 1 wei per fren.
        hook.setNftCurveFrom(1);
        assertEq(hook.volumePerNFT(), 1, "the hook took the mandate verbatim");
        assertEq(hook.nftPriceStep(), 0, "and flattened the ladder");
        uint256 attackedCost = _mintOutCost(1000);
        emit log_named_uint("mint-out cost, 1000 frens, 1-wei mandate  (wei)", attackedCost);
        assertEq(attackedCost, 1000, "ATTACK: the whole collection forges for 1000 wei of credit");

        // ── THE GATE: that mandate can no longer reach a vote. ───────────────
        // Read the band BEFORE arming expectRevert — an external getter call in an
        // argument position would be the "next call" the cheatcode matches.
        uint256 band = gov.CURVE_BAND();
        assertEq(band, 1000, "the band is 1000x either side of the live ladder");

        // Re-arm the honest ladder first: the attack above left `volumePerNFT == 1`
        // on the hook, and the band is measured against whatever the LIVE ladder
        // says. This is the state a real governor reads before a poisoned proposal.
        hook.setNftCurveFrom(honestBase);
        assertEq(hook.volumePerNFT(), honestBase, "ladder restored");

        vm.expectRevert(CauldronGovernor.CurveOutOfRange.selector);
        _propose(1);

        // Just under the floor, and just over the ceiling.
        vm.expectRevert(CauldronGovernor.CurveOutOfRange.selector);
        _propose(honestBase / band - 1);
        vm.expectRevert(CauldronGovernor.CurveOutOfRange.selector);
        _propose(honestBase * band + 1);

        // ── AND THE HONEST PATH IS UNTOUCHED. ───────────────────────────────
        assertEq(_propose(honestBase), 1, "the live base is proposable");
        assertEq(_propose(0), 2, "volumePerNFT == 0 keeps its meaning: leave the curve alone");
        assertEq(_propose(honestBase / band), 3, "the full 1000x DOWN is still allowed...");
        assertEq(_propose(honestBase * band), 4, "...and the full 1000x UP");
        // The move a proposer holding the $20k mint-out target across the whole
        // [100, 100_000] supply range actually needs.
        assertEq(_propose(honestBase / 50), 5, "a 50x cheaper fren for a 50x bigger collection");
    }

    /**
     * @dev The degradation path, which is what keeps every existing deployment and
     *      fixture working: a governor whose registry does not answer `hook()` (or
     *      whose hook has no `volumePerNFT`) leaves the figure UNCONSTRAINED rather
     *      than making {propose} unreachable. A governor that cannot take proposals
     *      is a dead machine, which is strictly worse than this bound being off.
     */
    function test_NoHookReachableLeavesTheCurveUnconstrained() public {
        CauldronGovernor bare = new CauldronGovernor(address(new T9fVotes()), 0);
        bare.setRegistry(address(new T9fRegistry(address(0))));
        uint256 id = bare.propose(
            "Brew", "BRW", MetadataMode.BaseURI, "ipfs://brew/", address(0),
            "", "", 0, 1, address(0)
        );
        assertEq(id, 1, "unreachable hook -> unconstrained, propose still works");
    }
}
