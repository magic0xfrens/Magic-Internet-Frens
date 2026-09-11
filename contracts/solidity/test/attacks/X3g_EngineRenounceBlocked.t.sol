// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpMarkSource} from "../../cauldron/PerpMarkSource.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

contract X3gPM {
    // slot0 = (tick 0 << 160) | sqrtPriceX96 = 2**96 — a live 1:1 pool.
    bytes32 constant S0 = bytes32(uint256(79228162514264337593543950336));
    function extsload(bytes32) external pure returns (bytes32) { return S0; }
    function extsload(bytes32, uint256 n) external pure returns (bytes32[] memory r) { r = new bytes32[](n); }
    function extsload(bytes32[] calldata s) external pure returns (bytes32[] memory r) { r = new bytes32[](s.length); }
}

contract X3gRegistry {
    address public currentToken;
    uint256 public currentGeneration = 1;
    uint256 public lastSummonAt;
    mapping(uint256 => address) public generationQuote;
    constructor(address tok) { currentToken = tok; lastSummonAt = block.timestamp; }
}

/**
 * X3g — REGRESSION. {Ownable} ships `renounceOwnership()` live and unguarded.
 *
 * On PerpEngine that would permanently disable setRisk / setFees / setGuards /
 * setVault / setVaultLimits / setMinCollateral / setMarkSource / skimInsurance on
 * a contract holding trader collateral, LP principal, borrowed token inventory
 * and the insurance buffer — with no recovery.
 *
 * On PerpMarkSource the owner surface IS the mark configuration (setPrimary,
 * addPool, removePool), so a renounce pins the liquidation mark to whatever pools
 * were registered at that instant — including after a quote rotation has moved
 * the generation onto a different pool entirely.
 *
 * Both now revert, and ownership is unchanged afterwards.
 */
contract X3gRenounceBlocked is Test {
    PerpEngine perp;
    PerpMarkSource mark;
    address constant OWNER = address(0x0BEEF0);

    function setUp() public {
        X3gPM pm = new X3gPM();
        MockQuoteToken tok = new MockQuoteToken("Gen1", "G1", 18);
        X3gRegistry reg = new X3gRegistry(address(tok));
        perp = new PerpEngine(
            IPoolManager(address(pm)), address(this), address(reg),
            address(0xBEEF), address(0xD1D1), address(0x7E7E), OWNER
        );
        mark = new PerpMarkSource(IPoolManager(address(pm)), OWNER);
    }

    function _tryRenounce(address target) internal returns (bool ok) {
        vm.prank(OWNER);
        (ok, ) = target.call(abi.encodeWithSignature("renounceOwnership()"));
    }

    function test_OwnershipOfTheEngineAndMarkSourceCannotBeRenounced() public {
        address engineOwnerBefore = perp.owner();
        address markOwnerBefore = mark.owner();

        bool engineRenounced = _tryRenounce(address(perp));
        bool markRenounced = _tryRenounce(address(mark));

        assertEq(engineOwnerBefore, OWNER, "precondition: the engine has a real owner");
        assertEq(markOwnerBefore, OWNER, "precondition: the mark source has a real owner");

        assertFalse(engineRenounced, "PerpEngine.renounceOwnership() REVERTS");
        assertFalse(markRenounced, "PerpMarkSource.renounceOwnership() REVERTS");

        assertEq(perp.owner(), OWNER, "engine ownership unchanged - every setter still reachable");
        assertEq(mark.owner(), OWNER, "mark-source ownership unchanged - setPrimary still reachable");
    }
}
