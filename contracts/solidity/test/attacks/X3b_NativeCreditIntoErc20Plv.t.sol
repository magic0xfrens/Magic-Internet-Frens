// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

contract X3bPM {
    function extsload(bytes32) external pure returns (bytes32) { return bytes32(0); }
    function extsload(bytes32, uint256 n) external pure returns (bytes32[] memory r) { r = new bytes32[](n); }
    function extsload(bytes32[] calldata s) external pure returns (bytes32[] memory r) { r = new bytes32[](s.length); }
}

contract X3bRegistry {
    address public currentToken;
    uint256 public currentGeneration = 1;
    uint256 public lastSummonAt;
    mapping(uint256 => address) public generationQuote;
    constructor(address tok) { currentToken = tok; lastSummonAt = block.timestamp; }
    function rotateQuote(address q) external { generationQuote[currentGeneration] = q; }
}

/**
 * X3b — `_creditPerp` is the ONE native ingress with no `_quoteIsNative()` test.
 * Every other funding entrypoint (fundPlv / fundInsurance / fundFromVault) goes
 * through `_pullQuote`, which rejects `msg.value != 0` on an ERC20 book, and the
 * ERC20 twin `creditPerpFeeAsset` rejects any asset that is not the live quote.
 * `creditPerpFee` / `creditPerpFeeToken` credit `msg.value` straight into the
 * quote-denominated counters, so on an ERC20 book they inflate `plv` with wei
 * the engine can never pay out.
 */
contract X3bNativeCreditIntoErc20Plv is Test {
    X3bPM pm;
    X3bRegistry reg;
    PerpEngine perp;
    MockQuoteToken tok;
    MockQuoteToken usdg;      // 6-decimal ERC20 quote

    function setUp() public {
        pm = new X3bPM();
        tok = new MockQuoteToken("Gen1", "G1", 18);
        reg = new X3bRegistry(address(tok));
        reg.rotateQuote(address(0));
        perp = new PerpEngine(
            IPoolManager(address(pm)), address(this), address(reg),
            address(0xBEEF), address(0xD1D1), address(0x7E7E), address(this)
        );
        usdg = new MockQuoteToken("USDG", "USDG", 6);
        vm.deal(address(this), 100 ether);
    }

    function isDead(PoolId) external pure returns (bool) { return false; }

    function _adoptErc20Quote() internal { reg.rotateQuote(address(usdg)); perp.syncGeneration(); }

    /// The guarded ingresses: every one of these must refuse native value.
    function _fundPlvWithValue() internal returns (bool ok) {
        try perp.fundPlv{value: 1 ether}(1 ether) { ok = true; } catch { ok = false; }
    }
    function _fundInsuranceWithValue() internal returns (bool ok) {
        try perp.fundInsurance{value: 1 ether}(1 ether) { ok = true; } catch { ok = false; }
    }
    /// The unguarded one.
    function _creditPerpFeeWithValue() internal returns (bool ok) {
        try perp.creditPerpFee{value: 1 ether}() { ok = true; } catch { ok = false; }
    }
    function _creditPerpFeeTokenWithValue() internal returns (bool ok) {
        try perp.creditPerpFeeToken{value: 1 ether}() { ok = true; } catch { ok = false; }
    }
    /// The ERC20 twin refuses a mismatched asset.
    function _creditWrongAsset() internal returns (bool ok) {
        tok.mint(address(this), 1 ether); tok.approve(address(perp), 1 ether);
        try perp.creditPerpFeeAsset(address(tok), 1 ether) { ok = true; } catch { ok = false; }
    }

    function test_NativeValueInflatesAnErc20DenominatedPlv() public {
        _adoptErc20Quote();
        assertEq(perp.quote(), address(usdg), "book is ERC20-denominated");

        bool plvTookValue        = _fundPlvWithValue();
        bool insTookValue        = _fundInsuranceWithValue();
        bool wrongAssetAccepted  = _creditWrongAsset();

        uint256 plvBefore  = perp.plv();
        uint256 yieldBefore = perp.tokYieldEth();
        bool feeTookValue      = _creditPerpFeeWithValue();
        bool feeTokTookValue   = _creditPerpFeeTokenWithValue();
        uint256 plvAfter   = perp.plv();
        uint256 yieldAfter = perp.tokYieldEth();
        uint256 usdgHeld   = usdg.balanceOf(address(perp));
        uint256 nativeHeld = address(perp).balance;

        assertFalse(plvTookValue, "fundPlv rejects native on an ERC20 book");
        assertFalse(insTookValue, "fundInsurance rejects native on an ERC20 book");
        assertFalse(wrongAssetAccepted, "creditPerpFeeAsset rejects a non-quote asset");

        // REGRESSION (red-team H-3): `_creditPerp` was the ONLY native ingress
        // without a `_quoteIsNative()` test. It now reverts like its siblings.
        assertFalse(feeTookValue, "creditPerpFee now REJECTS native on an ERC20 book");
        assertFalse(feeTokTookValue, "creditPerpFeeToken now REJECTS native on an ERC20 book");
        assertEq(plvAfter - plvBefore, 0, "plv not inflated by a single wei");
        assertEq(yieldAfter - yieldBefore, 0, "tokYieldEth not inflated by a single wei");
        assertEq(usdgHeld, 0, "engine still holds no USDG - because nothing was credited");
        assertEq(nativeHeld, 0, "and no untracked native wei was kept either");
        assertLe(plvAfter, usdgHeld, "plv never claims USDG the engine does not hold");
    }

    receive() external payable {}
}
