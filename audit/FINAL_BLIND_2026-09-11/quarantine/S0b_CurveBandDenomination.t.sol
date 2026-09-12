// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronGovernor} from "../../cauldron/CauldronGovernor.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";

contract S0bVotes {
    function getVotes(address) external pure returns (uint256) { return 1; }
}

contract S0bRegistry {
    address public hook;
    constructor(address h) { hook = h; }
    function allowedQuote(address) external pure returns (bool) { return true; }
}

/**
 * @notice S0b — `CURVE_BAND` is a ratio between two figures that are NOT in the same
 *         units, so it refuses the honest proposal and accepts the abusive one.
 *
 *  `propose` (CauldronGovernor.sol:466-469) compares the proposal's `volumePerNFT`
 *  against `_liveCurveBase()` = the LIVE hook's `volumePerNFT`. With no `quoteOracle`
 *  wired, `nftCredit` accrues in QUOTE-RAW units (CauldronHook.sol:836 `_toUsd`
 *  returns `raw` when `quoteOracle == address(0)`), so the correct base for a
 *  generation is denominated in ITS OWN quote's decimals. The proposal names the next
 *  generation's `quote`, but the band is measured against the base of the CURRENT
 *  one.
 *
 *  Both directions bite, and this test asserts both from the same live state.
 */
contract S0bCurveBandDenomination is Test {
    CauldronHook internal hook;
    CauldronGovernor internal gov;
    S0bRegistry internal reg;

    /// @dev A 6-decimal quote (USDC/USDG shape) the treasury has allowlisted.
    address internal constant USDC6 = address(0xA0b86991c6218B36C1D19D4A2E9EB0CE3606EB48);
    /// @dev What a 0.02 ETH fren costs in 6-decimal dollars at $3000/ETH: $60.
    uint256 internal constant HONEST_BASE_6DP = 60e6;

    function setUp() public {
        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(1)), uint256(1 ether), address(0), address(this), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(IPoolManager(address(1)), 1 ether, address(0), address(this), address(this));
        require(address(hook) == hookAddr, "hook addr");
        hook.setRegistry(address(this)); // this test plays the registry for setNftCurveFrom
        reg = new S0bRegistry(address(hook));
        gov = new CauldronGovernor(address(new S0bVotes()));
        gov.setRegistry(address(reg));
    }

    function _propose(uint256 volumePerNFT, address quote) internal returns (uint256) {
        return gov.propose(
            "Brew", "BRW", MetadataMode.BaseURI, "ipfs://brew/", address(0), "", "", 0, volumePerNFT, quote
        );
    }

    function _mintOutCost(uint256 n) internal view returns (uint256 t) {
        for (uint256 k; k < n; ++k) t += hook.nftPriceAt(k);
    }

    /// @dev Does a proposal for `base`/`quote` pass the band? Returns the outcome as a
    ///      value so the assertions stay in the top-level test.
    function _accepted(uint256 base, address quote) internal returns (bool) {
        try this.exposed_propose(base, quote) { return true; }
        catch { return false; }
    }

    function exposed_propose(uint256 base, address quote) external { _propose(base, quote); }

    // ── the two halves ──────────────────────────────────────────────────────

    function test_BandIsAcrossDenominationsSoItInverts() public {
        uint256 band = gov.CURVE_BAND();
        assertEq(band, 1000, "band as shipped");
        assertEq(hook.volumePerNFT(), 0.02 ether, "live ladder is ETH-denominated");

        // ── HALF 1: the honest 6-decimal proposal is REFUSED. ────────────────
        // The generation would be quoted in a 6-decimal dollar token; a fren worth
        // the same 0.02 ETH costs 60e6 of that token's raw credit.
        bool honest6dp = _accepted(HONEST_BASE_6DP, USDC6);
        // The cheapest base the band will accept, and what it prices a fren at in
        // 6-decimal dollars.
        uint256 cheapestAllowed = hook.volumePerNFT() / band; // 2e13
        uint256 dollarsPerFren = cheapestAllowed / 1e6;       // raw -> whole dollars
        emit log_named_uint("cheapest in-band base (raw)        ", cheapestAllowed);
        emit log_named_uint("...priced as 6dp dollars per fren  ", dollarsPerFren);
        assertFalse(honest6dp, "HALF 1: a correctly scaled 6-decimal base is refused");
        assertGt(dollarsPerFren, 19_000_000, "the cheapest in-band fren costs >$19M of credit");

        // ── HALF 2: the same band ACCEPTS the 1-wei-class proposal, and REFUSES
        //            the honest one, once the ladder has legitimately been restated
        //            for that 6-decimal quote (`setNftCurve`, the owner duty
        //            CauldronHook.sol:1781-1810 documents for a re-denomination).
        hook.setNftCurve(HONEST_BASE_6DP, 0);
        assertEq(hook.volumePerNFT(), HONEST_BASE_6DP, "ladder restated for the 6dp quote");

        uint256 abusive = HONEST_BASE_6DP * band; // 6e10 wei, the top of the band
        bool abusiveNative = _accepted(abusive, address(0));
        bool honestNative = _accepted(0.02 ether, address(0));
        emit log_named_uint("abusive native base accepted? (1=y)", abusiveNative ? 1 : 0);
        emit log_named_uint("honest native base accepted? (1=y)", honestNative ? 1 : 0);

        // Apply the accepted mandate exactly as relaunch does.
        hook.setNftCurveFrom(abusive);
        assertEq(hook.nftPriceStep(), 0, "flat ladder, as setNftCurveFrom always writes");
        uint256 cost = _mintOutCost(10_000);
        emit log_named_uint("mint-out cost, 10k frens (wei)     ", cost);

        assertTrue(abusiveNative, "HALF 2: the band ACCEPTS 6e10 wei a fren");
        assertFalse(honestNative, "HALF 2: and REFUSES the honest 0.02 ether base");
        assertLt(cost, 0.001 ether, "the whole 10k collection forges for <0.001 ETH of credit");
    }
}
