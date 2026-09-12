// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

contract X9fPM {
    bytes32 constant S0 = bytes32(uint256(79228162514264337593543950336));
    function extsload(bytes32) external pure returns (bytes32) { return S0; }
    function extsload(bytes32, uint256 n) external pure returns (bytes32[] memory r) { r = new bytes32[](n); }
    function extsload(bytes32[] calldata s) external pure returns (bytes32[] memory r) { r = new bytes32[](s.length); }
}

contract X9fRegistry {
    address public currentToken;
    uint256 public currentGeneration = 1;
    uint256 public lastSummonAt;
    mapping(uint256 => address) public generationQuote;
    constructor(address tok) { currentToken = tok; lastSummonAt = block.timestamp; }
    function rotateQuote(address q) external { generationQuote[currentGeneration] = q; }
}

/**
 * X9f — REGRESSION for F-05.
 *
 * On a QUOTE ROTATION the generation does not change, so `fromGen < gen` is false,
 * `migrateInventory` never runs and `migratedIn` stays 0 — because the token is the
 * SAME token and there was nothing to move, not because a move fell short. The
 * shortfall bookkeeping could not tell those apart, so it booked the ENTIRE live
 * `plvToken` to `strandedToken[syncedToken]` and announced it with
 * `TokenInventoryStranded`, one line before `plvToken` was re-set to the same real
 * balance. The books then claimed the engine held its token inventory twice.
 *
 * `strandedToken` has no reader today, so nothing was mispaid — but it exists to
 * be a recovery basis, and a double-count is exactly what would be spent from it.
 */
contract X9fRotationFalseStranded is Test {
    X9fPM pm;
    X9fRegistry reg;
    PerpEngine perp;
    MockQuoteToken tok;
    MockQuoteToken newQuote;

    uint256 constant INVENTORY = 500 ether;

    function setUp() public {
        pm = new X9fPM();
        tok = new MockQuoteToken("Gen1", "G1", 18);
        reg = new X9fRegistry(address(tok));
        reg.rotateQuote(address(0));                  // gen-1 launched NATIVE
        perp = new PerpEngine(
            IPoolManager(address(pm)), address(this), address(reg),
            address(0xBEEF), address(0xD1D1), address(0x7E7E), address(this)
        );
        newQuote = new MockQuoteToken("USDG", "USDG", 18);
    }

    function isDead(PoolId) external pure returns (bool) { return false; }

    // ── helpers ──────────────────────────────────────────────────────────────
    function _seedInventory(uint256 amount) internal {
        tok.mint(address(this), amount);
        tok.approve(address(perp), amount);
        perp.fundPlvToken(amount);
    }

    function _rotateAndSync() internal {
        reg.rotateQuote(address(newQuote));
        vm.prank(address(0xCEE9E4));                  // permissionless
        perp.syncGeneration();
    }

    function test_QuoteRotationDoesNotBookLiveInventoryAsStranded() public {
        _seedInventory(INVENTORY);
        uint256 heldBefore = perp.plvToken();

        vm.recordLogs();
        _rotateAndSync();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool announcedStranded;
        bytes32 topic = keccak256("TokenInventoryStranded(address,uint256,uint256)");
        for (uint256 i; i < logs.length; i++) {
            announcedStranded = announcedStranded || (logs[i].topics.length != 0 && logs[i].topics[0] == topic);
        }

        assertEq(heldBefore, INVENTORY, "the engine really holds the generation's token inventory");
        assertEq(perp.quote(), address(newQuote), "the rotation was adopted");
        assertEq(perp.plvToken(), INVENTORY, "and the inventory is still counted once");
        assertEq(perp.strandedToken(address(tok)), 0, "nothing was stranded - the token never changed");
        assertFalse(announcedStranded, "and no TokenInventoryStranded was announced to operators");
    }
}
