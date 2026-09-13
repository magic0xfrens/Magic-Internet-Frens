// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CauldronGovernor} from "../../cauldron/CauldronGovernor.sol";
import {MintCurvePolicy} from "../../cauldron/MintCurvePolicy.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";

/**
 * S0xB — the CURVE_BAND fix (CauldronGovernor.sol:487-492) is anchored to a number
 *        that prices nothing whenever a {MintCurvePolicy} is wired, and the SAME
 *        policy permanently freezes the collection size a proposal may name.
 *
 * CauldronGovernor.sol:487
 *     if (volumePerNFT != 0) {
 *         uint256 live = _liveCurveBase();
 *         if (live != 0 && (volumePerNFT < live / CURVE_BAND || volumePerNFT > live * CURVE_BAND))
 *             revert CurveOutOfRange();
 *     }
 * `_liveCurveBase()` (:403-409) reads `hook.volumePerNFT()`.
 *
 * MintCurvePolicy.sol:119
 *     function priceAt(uint256 k, uint256, uint256) external view returns (uint256) {
 *         return base + (spread * k * k) / (k + knee);
 *     }
 * The 2nd and 3rd parameters — the hook's `volumePerNFT` and `nftPriceStep` — are
 * UNNAMED AND UNUSED. CauldronHook.nftPriceAt (:2174-2183) prefers the policy, so
 * while a policy is wired the ladder is the policy's immutables and the winning
 * proposal's `volumePerNFT` mandate is dead. DeployLaunchpad.s.sol:328-329 wires one
 * on every deploy that has a quote oracle.
 *
 * And CauldronGovernor.sol:479-480
 *     uint256 calibrated = _calibratedSupply();
 *     if (calibrated != 0 && nftSupply != calibrated) revert SupplyOutOfRange();
 * `MintCurvePolicy.supply` is `immutable`, so after genesis no proposal may ever name
 * a different collection size again.
 */
contract S0xCurveBandInertUnderPolicy is Test {
    CauldronGovernor gov;
    MockVotes votes;
    MockRegistry reg;
    MockHook hook;
    MintCurvePolicy policy;

    uint256 constant CALIBRATED = 3333;

    function setUp() public {
        votes = new MockVotes();
        gov = new CauldronGovernor(address(votes), 0);
        // base = 8% of the mean of a $20k mint-out over 3333 frens, the shipped calc.
        policy = new MintCurvePolicy(0.48e18, 1e18, 300, CALIBRATED);
        hook = new MockHook(address(policy), 0.02 ether);
        reg = new MockRegistry(address(hook));
        gov.setRegistry(address(reg));
        votes.setVotes(address(this), 10);
        vm.roll(block.number + 1);
    }

    // ── helpers: every conditional lives here, the test body only asserts ────

    function _proposeSupply(uint256 nftSupply) internal returns (bool ok) {
        try gov.propose(
            "n", "N", MetadataMode.BaseURI, "ipfs://x", address(0), "", "", nftSupply, 0, address(0)
        ) returns (uint256) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _proposeBase(uint256 volumePerNFT) internal returns (bool ok) {
        try gov.propose(
            "n", "N", MetadataMode.BaseURI, "ipfs://x", address(0), "", "", 0, volumePerNFT, address(0)
        ) returns (uint256) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function test_CurveBandGuardsALadderThePolicyIgnores() public {
        // ── 1. the band ACCEPTS and REFUSES on `hook.volumePerNFT` ──────────
        bool acceptedInBand = _proposeBase(0.02 ether);       // == live
        bool refusedBelow = !_proposeBase(1);                  // 1 wei, the T-2 case
        bool refusedAbove = !_proposeBase(0.02 ether * 1001);  // outside CURVE_BAND

        // ── 2. but the LADDER THAT ACTUALLY PRICES A FREN ignores that number ─
        // priceAt's 2nd/3rd args are the hook's volumePerNFT / nftPriceStep.
        uint256 atOneWei = policy.priceAt(0, 1, 0);
        uint256 atLiveBase = policy.priceAt(0, 0.02 ether, 0.00002 ether);
        uint256 atAbsurd = policy.priceAt(0, type(uint128).max, type(uint128).max);
        uint256 k100_a = policy.priceAt(100, 1, 0);
        uint256 k100_b = policy.priceAt(100, type(uint128).max, type(uint128).max);

        // ── 3. and the collection SIZE is frozen at the policy's immutable ───
        bool sizeAtCalibrated = _proposeSupply(CALIBRATED);
        bool sizeRefusedOther = !_proposeSupply(1000);
        bool sizeRefusedOther2 = !_proposeSupply(10_000);

        emit log_named_uint("policy.priceAt(0, 1 wei base)      ", atOneWei);
        emit log_named_uint("policy.priceAt(0, live base)       ", atLiveBase);
        emit log_named_uint("policy.priceAt(0, uint128.max base)", atAbsurd);

        // The band does what it says it does...
        assertTrue(acceptedInBand, "in-band proposal accepted");
        assertTrue(refusedBelow, "1 wei base refused by CURVE_BAND");
        assertTrue(refusedAbove, "1000x base refused by CURVE_BAND");

        // ...to a number that has no effect on the mint price at all.
        assertEq(atOneWei, atLiveBase, "the ladder is identical at a 1-wei base");
        assertEq(atOneWei, atAbsurd, "and identical at an absurd base");
        assertEq(k100_a, k100_b, "and identical at k=100 too");

        // ...while the size a proposal may name is pinned to an immutable forever.
        assertTrue(sizeAtCalibrated, "only the calibrated size is proposable");
        assertTrue(sizeRefusedOther, "1000 frens refused");
        assertTrue(sizeRefusedOther2, "10000 frens refused");
    }
}

contract MockVotes {
    mapping(address => uint256) private _v;
    function setVotes(address a, uint256 n) external { _v[a] = n; }
    function getVotes(address a) external view returns (uint256) { return _v[a]; }
    function getPastVotes(address a, uint256) external view returns (uint256) { return _v[a]; }
}

contract MockHook {
    address public curvePolicy;
    uint256 public volumePerNFT;
    constructor(address p, uint256 b) { curvePolicy = p; volumePerNFT = b; }
}

contract MockRegistry {
    address public hook;
    constructor(address h) { hook = h; }
    function allowedQuote(address) external pure returns (bool) { return true; }
}
