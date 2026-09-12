// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {MintCurvePolicy} from "../../cauldron/MintCurvePolicy.sol";
import {CauldronGovernor} from "../../cauldron/CauldronGovernor.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";

/// @dev 1 NFT = 1 vote; every caller may propose.
contract Z9VotesMock {
    function getVotes(address) external pure returns (uint256) { return 1; }
}

/// @dev The hook, as far as the governor is concerned: it exposes the live curve
///      policy and nothing else.
contract Z9HookMock {
    address public curvePolicy;
    function setCurvePolicy(address p) external { curvePolicy = p; }
}

/// @dev The registry: the quote allowlist the governor already consulted, plus the
///      hook pointer the supply check walks through.
contract Z9RegistryMock {
    address public hook;
    constructor(address h) { hook = h; }
    function allowedQuote(address) external pure returns (bool) { return true; }
}

/**
 * Z9c/Z9d — MintCurvePolicy's calibration is frozen to ONE collection size, and
 * it ignores the per-generation curve the registry writes on every relaunch.
 *
 *   CauldronHook.sol:2175-2183 (nftPriceAt) PREFERS the policy:
 *       ICurvePolicy pol = curvePolicy;
 *       if (address(pol) != address(0)) {
 *           try pol.priceAt(k, volumePerNFT, nftPriceStep) returns (uint256 c) {
 *               if (c > 0) return c;
 *           } catch { }
 *       }
 *       return volumePerNFT + k * nftPriceStep;
 *
 *   MintCurvePolicy.sol:95 throws both arguments away:
 *       function priceAt(uint256 k, uint256, uint256) external view returns (uint256) {
 *           return base + (spread * k * k) / (k + knee);
 *       }
 *
 *   CauldronRegistry.sol:1098 believes it applied the winning proposal's target:
 *       hook.setNftCurveFrom(volPerNFT);
 *
 *   CauldronRegistry.sol:925-926 lets the proposer pick the collection SIZE:
 *       if (spec.nftSupply > 0) {
 *           nftSupply = spec.nftSupply > MAX_NFT_SUPPLY ? MAX_NFT_SUPPLY : spec.nftSupply;
 *       }
 *   MAX_NFT_SUPPLY = 100_000 (cauldron/CauldronBase.sol:167).
 */
contract Z9CurveSupplyMandate is Test {
    uint256 internal constant TARGET = 20_000e18; // MINT_OUT_TARGET_USD default
    uint256 internal constant KNEE   = 300;       // MINT_CURVE_KNEE default
    uint256 internal constant N_CAL  = 2222;      // MIFRENS_ART_CAP default

    /// Rebuild the ladder EXACTLY as deploy/DeployLaunchpad.s.sol:300-319 does.
    function _deployCalibrated() internal returns (MintCurvePolicy c) {
        uint256 curveBase = (TARGET / N_CAL) * 800 / 10_000;
        uint256 sum;
        for (uint256 k; k < N_CAL; ++k) sum += (k * k * 1e18) / (k + KNEE);
        uint256 spread = ((TARGET - N_CAL * curveBase) * 1e18) / sum;
        c = new MintCurvePolicy(curveBase, spread, KNEE, N_CAL);
    }

    function _ladderTotal(MintCurvePolicy c, uint256 n) internal view returns (uint256 t) {
        for (uint256 k; k < n; ++k) t += c.priceAt(k, 0, 0);
    }

    /// Z9c — the proposer's `volumePerNFT` mandate is inert while a policy is wired.
    function test_Z9c_PolicyIgnoresTheRegistrysPerGenerationCurve() public {
        MintCurvePolicy c = _deployCalibrated();

        // POSITIVE: the calibration it WAS built for is honoured.
        uint256 calTotal = c.totalToMintOut();
        assertApproxEqRel(calTotal, TARGET, 0.01e18, "calibrated ladder hits its target");

        // ATTACK: whatever the hook forwards from setNftCurveFrom is discarded.
        uint256 asIs   = c.priceAt(1000, 0, 0);
        uint256 withMandate = c.priceAt(1000, 1_000_000e18, 5_000e18); // a proposer's target
        assertEq(withMandate, asIs, "ATTACK: priceAt discards volumePerNFT AND nftPriceStep");
    }

    /// Z9d — the immutable `supply` calibration mis-prices every other collection size.
    function test_Z9d_CalibrationIsWrongForAnyOtherProposedSupply() public {
        MintCurvePolicy c = _deployCalibrated();
        uint256 calTotal = c.totalToMintOut();

        // (a) A proposer picks a SMALL collection: the whole thing forges for a
        //     rounding error of the intended mint-out volume.
        uint256 smallTotal = _ladderTotal(c, 100);

        // (b) A proposer picks a LARGE collection: mint-out becomes unreachable.
        uint256 bigTotal = _ladderTotal(c, 10_000);

        console2.log("calibrated total (usd) :", calTotal / 1e18);
        console2.log("100-fren total   (usd) :", smallTotal / 1e18);
        console2.log("10k-fren total   (usd) :", bigTotal / 1e18);
        console2.log("first fren (wei)       :", c.priceAt(0, 0, 0));

        assertLt(smallTotal * 50, calTotal,
            "WHY THE GATE EXISTS: a 100-fren collection would mint OUT for <2% of the target");
        assertGt(bigTotal, calTotal * 20,
            "WHY THE GATE EXISTS: a 10k-fren collection would need >20x the mint-out volume");
    }

    // ── Z-09 REGRESSION: the mismatch can no longer reach a vote ────────────

    Z9VotesMock internal votes;
    Z9HookMock internal hook;
    Z9RegistryMock internal reg;
    CauldronGovernor internal gov;

    function _wireGovernor() internal {
        votes = new Z9VotesMock();
        hook = new Z9HookMock();
        reg = new Z9RegistryMock(address(hook));
        gov = new CauldronGovernor(address(votes), 0);
        gov.setRegistry(address(reg));
    }

    function _propose(uint256 nftSupply) internal returns (uint256) {
        return gov.propose(
            "Brew", "BRW", MetadataMode.BaseURI, "ipfs://brew/", address(0),
            "", "", nftSupply, 1e18, address(0)
        );
    }

    /// The exploit was: propose a 100-fren collection, win, and mint the whole
    /// thing out for ~$80 of weighted buy credit — then hold 100% of the claim on
    /// a floor funded by the generation's entire fee revenue. It now cannot be
    /// PROPOSED while a calibrated ladder is wired.
    function test_Z9e_ProposalCannotMisSizeTheCollectionAgainstTheWiredLadder() public {
        _wireGovernor();
        MintCurvePolicy curve = _deployCalibrated();
        hook.setCurvePolicy(address(curve));
        assertEq(curve.supply(), N_CAL, "the ladder is calibrated for 2222 frens");

        // The attack size.
        vm.expectRevert(CauldronGovernor.SupplyOutOfRange.selector);
        _propose(100);

        // The other direction — the one that kills the forge outright.
        vm.expectRevert(CauldronGovernor.SupplyOutOfRange.selector);
        _propose(10_000);

        // Below the floor, and above the hard cap.
        vm.expectRevert(CauldronGovernor.SupplyOutOfRange.selector);
        _propose(1);
        vm.expectRevert(CauldronGovernor.SupplyOutOfRange.selector);
        _propose(100_001);

        // POSITIVE: the size the wired ladder actually prices is accepted...
        assertEq(_propose(N_CAL), 1, "a correctly sized proposal still goes through");
        // ...and so is "leave the size alone", which is what every ordinary
        // proposal passes (CauldronRegistry.sol:961 treats 0 as unchanged).
        assertEq(_propose(0), 2, "nftSupply == 0 keeps its meaning");
    }

    /// With NO policy wired the hook's own ladder is `volumePerNFT + k * step`,
    /// which scales with the collection size by construction — so only the flat
    /// [MIN, MAX] bound applies. This is the path every existing deployment and
    /// fixture takes, and it must not have become stricter than the finding needs.
    function test_Z9f_NoPolicyWiredLeavesTheSizeFreeWithinTheBounds() public {
        _wireGovernor(); // hook.curvePolicy() == address(0)

        // Read the bound BEFORE arming expectRevert: an external getter call in an
        // argument would be the "next call" the cheatcode matches against.
        uint256 min = gov.MIN_NFT_SUPPLY();
        assertEq(min, 100, "the floor is 100 frens");

        assertEq(_propose(500), 1, "any size within the bounds is fine with no policy");
        assertEq(_propose(100_000), 2, "up to the hard cap");
        assertEq(_propose(min), 3, "and down to the floor");

        vm.expectRevert(CauldronGovernor.SupplyOutOfRange.selector);
        _propose(min - 1);
    }
}
