// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

/// slot0 = (tick 0 << 160) | sqrtPriceX96 = 2**96 — a live 1:1 pool.
contract X8aPM {
    bytes32 constant S0 = bytes32(uint256(79228162514264337593543950336));
    function extsload(bytes32) external pure returns (bytes32) { return S0; }
    function extsload(bytes32, uint256 n) external pure returns (bytes32[] memory r) { r = new bytes32[](n); }
    function extsload(bytes32[] calldata s) external pure returns (bytes32[] memory r) { r = new bytes32[](s.length); }
}

contract X8aRegistry {
    address public currentToken;
    uint256 public currentGeneration = 1;
    uint256 public lastSummonAt;
    mapping(uint256 => address) public generationQuote;
    constructor(address tok) { currentToken = tok; lastSummonAt = block.timestamp; }
    /// A completed treasury rotation is what moves this (RedemptionExt.sol:487).
    function setGenerationQuote(uint256 g, address q) external { generationQuote[g] = q; }
}

contract X8aInsuranceFloorFreezesRotation is Test {
    X8aPM pm;
    MockQuoteToken usdg;
    address constant OWNER = address(0x0BEEF0);
    address constant STRANGER = address(0x5721A6);

    function setUp() public {
        pm = new X8aPM();
        usdg = new MockQuoteToken("USDG", "USDG", 6);
    }

    function _deploy() internal returns (PerpEngine perp, X8aRegistry reg) {
        MockQuoteToken tok = new MockQuoteToken("Gen1", "G1", 18);
        reg = new X8aRegistry(address(tok));
        perp = new PerpEngine(
            IPoolManager(address(pm)), address(this), address(reg),
            address(0xBEEF), address(0xD1D1), address(0x7E7E), OWNER
        );
    }

    function _trySync(PerpEngine perp) internal returns (bool ok, bytes4 sel) {
        bytes memory err;
        (ok, err) = address(perp).call(abi.encodeWithSignature("syncGeneration()"));
        if (err.length >= 4) {
            sel = bytes4(err[0]) | (bytes4(err[1]) >> 8) | (bytes4(err[2]) >> 16) | (bytes4(err[3]) >> 24);
        }
    }

    function _trySkim(PerpEngine perp, uint256 amount) internal returns (bool ok) {
        vm.prank(OWNER);
        (ok, ) = address(perp).call(
            abi.encodeWithSignature("skimInsurance(uint256,address)", amount, OWNER)
        );
    }

    /// X8a-1 — the shipped configuration can NEVER follow a quote rotation.
    function test_TheDeployedInsuranceFloorPermanentlyBlocksQuoteAdoption() public {
        (PerpEngine perp, X8aRegistry reg) = _deploy();

        // Armed EXACTLY as deploy/DeployPerp.s.sol:94-97 does it.
        vm.prank(OWNER);
        perp.setVaultLimits(8_000, 0.05 ether);

        // The buffer MUST hold at least the floor or every open reverts
        // InsurancePaused (PerpEngine.sol:839, :877). `fundInsurance` is
        // permissionless (PerpEngine.sol:1637), so anyone may top it up.
        vm.deal(STRANGER, 1 ether);
        vm.prank(STRANGER);
        perp.fundInsurance{value: 0.05 ether}(0.05 ether);

        uint256 buffered = perp.insuranceEth();
        address quoteBefore = perp.quote();

        // The treasury completes a live rotation: gen 1 is now USDG-quoted.
        reg.setGenerationQuote(1, address(usdg));

        (bool syncOk, bytes4 syncSel) = _trySync(perp);

        // `skimInsurance` (PerpEngine.sol:1877) is the ONLY writer that lowers
        // `insuranceEth`, at any privilege level. Whole, then one wei.
        bool skimAll = _trySkim(perp, buffered);
        bool skimOne = _trySkim(perp, 1);

        (bool syncAgain, ) = _trySync(perp);

        assertEq(quoteBefore, address(0), "precondition: engine is native-quoted");
        assertEq(buffered, 0.05 ether, "precondition: buffer armed at the deploy floor");
        // REGRESSION (red-team X8-01). The guard no longer demands a zero it cannot
        // get: `insuranceEth` is SWEPT to the treasury in the OLD asset at the flip
        // and zeroed, so no old-unit figure survives AND nothing is frozen.
        assertTrue(syncOk, "the rotated quote IS adopted, armed deploy floor and all");
        assertEq(syncSel, bytes4(0), "no revert at all");
        assertEq(perp.insuranceEth(), 0, "the old-asset buffer was swept, not stranded");
        assertEq(address(0x7E7E).balance, buffered, "and the treasury received it IN ETH, the asset it was counted in");
        assertFalse(skimAll, "nothing left to skim afterwards");
        assertFalse(skimOne, "...not even one wei");
        assertFalse(syncAgain, "a second sync is AlreadySynced - because the first one WORKED");
        assertEq(perp.quote(), address(usdg), "the engine adopted the generation's quote");
        assertEq(perp.quote(), reg.generationQuote(1), "_isDead() reads FALSE - engine and generation agree");
    }

    /// X8a-2 — CONTROL + the 1-wei grief. Same fixture, floor left at the
    /// contract default (0): an empty buffer rotates fine, and one wei of
    /// permissionless `fundInsurance` from a stranger is enough to stop it.
    function test_ControlEmptyBufferRotatesAndOneStrangerWeiStopsIt() public {
        (PerpEngine control, X8aRegistry cReg) = _deploy();
        (PerpEngine griefed, X8aRegistry gReg) = _deploy();

        uint256 emptyBuffer = control.insuranceEth();
        cReg.setGenerationQuote(1, address(usdg));
        (bool controlOk, ) = _trySync(control);
        address adopted = control.quote();

        vm.deal(STRANGER, 1 ether);
        vm.prank(STRANGER);
        griefed.fundInsurance{value: 1}(1);
        gReg.setGenerationQuote(1, address(usdg));
        (bool griefOk, bytes4 griefSel) = _trySync(griefed);

        // With the floor at 0 the owner CAN clear it — which is what makes X8a-1
        // the permanent one.
        bool skimmed = _trySkim(griefed, 1);
        (bool afterSkim, ) = _trySync(griefed);

        assertEq(emptyBuffer, 0, "precondition: empty insurance buffer");
        assertTrue(controlOk, "an empty buffer CAN follow the rotation");
        assertEq(adopted, address(usdg), "the control engine adopted the rotated quote");
        assertTrue(griefOk, "one stranger wei no longer blocks it - it is swept with the rest");
        assertEq(griefSel, bytes4(0), "no revert");
        assertEq(griefed.insuranceEth(), 0, "the griefing wei went to the treasury, not into a veto");
        assertFalse(skimmed, "nothing is left to skim");
        assertFalse(afterSkim, "and re-syncing is AlreadySynced, not a retry of a failure");
    }
}
