// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

contract X9bPM {
    // slot0 = (tick 0 << 160) | sqrtPriceX96 = 2**96 — a live 1:1 pool.
    bytes32 constant S0 = bytes32(uint256(79228162514264337593543950336));
    function extsload(bytes32) external pure returns (bytes32) { return S0; }
    function extsload(bytes32, uint256 n) external pure returns (bytes32[] memory r) { r = new bytes32[](n); }
    function extsload(bytes32[] calldata s) external pure returns (bytes32[] memory r) { r = new bytes32[](s.length); }
}

contract X9bRegistry {
    address public currentToken;
    uint256 public currentGeneration = 1;
    uint256 public lastSummonAt;
    mapping(uint256 => address) public generationQuote;
    constructor(address tok) { currentToken = tok; lastSummonAt = block.timestamp; }
    function rotateQuote(address q) external { generationQuote[currentGeneration] = q; }
}

/**
 * X9b — REGRESSION for F-01.
 *
 * `syncGeneration`'s rotation guard asked {PerpVault.hasStakers}, which is
 * `(ethShares | tokShares | pendingEth | pendingTok) != 0` — BOTH sides of the
 * vault. The token side is not redenominated by a quote rotation and cannot be
 * cleared without its owner's cooperation, so a single dust `depositToken`
 * (≈ assetsTok()/1e6 — one share is enough) vetoed every future quote adoption.
 * `_isDead()` then read the divergence as death and leverage was off for the
 * whole generation with no governance escape: the X8-01 permanent-freeze shape,
 * re-entered through the token side at negligible attacker cost.
 *
 * The guard now asks {hasQuoteStake} — the question the vault's own header always
 * documented, and which had ZERO production callers. This test pins BOTH halves:
 * the dust token stake no longer blocks the flip, and genuine QUOTE-denominated
 * staker capital still does.
 *
 * The real {PerpVault} is used, not a mock, so the veto is produced by the same
 * share accounting an attacker would actually drive.
 */
contract X9bDustTokenStakeVetoesAdoption is Test {
    X9bPM pm;
    X9bRegistry reg;
    PerpEngine perp;
    PerpVault vault;
    MockQuoteToken tok;
    MockQuoteToken newQuote;

    address constant ATTACKER = address(0xA77ACC);
    address constant LP = address(0x11FE);
    address constant KEEPER = address(0xCEE9E4);

    function setUp() public {
        pm = new X9bPM();
        tok = new MockQuoteToken("Gen1", "G1", 18);
        reg = new X9bRegistry(address(tok));
        reg.rotateQuote(address(0));                  // gen-1 launched NATIVE
        perp = new PerpEngine(
            IPoolManager(address(pm)), address(this), address(reg),
            address(0xBEEF), address(0xD1D1), address(0x7E7E), address(this)
        );
        vault = new PerpVault(address(perp), address(reg));
        perp.setVault(address(vault));
        newQuote = new MockQuoteToken("USDG", "USDG", 18);
        vm.deal(LP, 10 ether);
    }

    // The engine asks the hook this inside _isDead(); answer honestly.
    function isDead(PoolId) external pure returns (bool) { return false; }

    // ── helpers (all branching lives here, per the PoC rule) ─────────────────

    /// One dust TOKEN-side deposit: the whole attack, at the cost of one share.
    function _dustTokenStake(uint256 amount) internal {
        tok.mint(ATTACKER, amount);
        vm.startPrank(ATTACKER);
        tok.approve(address(vault), amount);
        vault.depositToken(amount);
        vm.stopPrank();
    }

    /// Genuine QUOTE-denominated staker capital (the engine is native-quoted here).
    function _quoteStake(uint256 amount) internal {
        vm.prank(LP);
        vault.depositEth{value: amount}();
    }

    function _quoteUnstake() internal {
        //  Shares read BEFORE the prank: an argument expression is evaluated first
        //  and would consume it, leaving this contract as the caller.
        uint256 shares = vault.ethShareOf(LP);
        vm.prank(LP);
        vault.withdrawEth(shares);
    }

    function _sync() internal returns (bool ok) {
        vm.prank(KEEPER);                             // permissionless, by design
        try perp.syncGeneration() { ok = true; } catch { ok = false; }
    }

    function test_DustTokenStakeCannotVetoAdoptionButQuoteStakeStillDoes() public {
        _dustTokenStake(1e6);
        _quoteStake(1 ether);
        uint256 attackerShares = vault.tokShareOf(ATTACKER);
        uint256 principal = perp.plvToken();

        // The treasury rotates the generation's quote. The engine has not adopted
        // it yet, so it is DIVERGED (= `_isDead()`, = no new leverage) until it does.
        reg.rotateQuote(address(newQuote));

        // ── 1. QUOTE-side stake still refuses the flip ───────────────────────
        //  This is the property the guard exists for: `plv` is a bare counter of
        //  the quote asset and every payout of it goes through `_pushQuote`, which
        //  pays in whatever `quote` names TODAY — adopting underneath a staker
        //  redenominates their principal without moving a wei of it.
        bool syncedWithQuoteStake = _sync();
        address quoteAfterRefusal = perp.quote();

        // ── 2. the quote side exits; the DUST TOKEN STAKE remains ────────────
        _quoteUnstake();
        bool tokenSideStillStaked = vault.hasStakers();
        bool quoteSideStillStaked = vault.hasQuoteStake();
        bool syncedWithTokenStakeOnly = _sync();

        // ── assertions ───────────────────────────────────────────────────────
        assertGt(attackerShares, 0, "one dust depositToken mints the attacker a share");
        assertEq(principal, 1e6, "and the engine holds their token principal");
        assertFalse(syncedWithQuoteStake, "REAL quote-denominated stake still vetoes the flip");
        assertEq(quoteAfterRefusal, address(0), "so the engine stays on the old quote");

        assertTrue(tokenSideStillStaked, "hasStakers() is STILL true - the token side never left");
        assertFalse(quoteSideStillStaked, "but no quote-denominated value is at risk");
        assertTrue(syncedWithTokenStakeOnly, "the dust token stake no longer vetoes adoption");
        assertEq(perp.quote(), address(newQuote), "the engine follows its generation");

        // ...and the attacker's token PRINCIPAL is not confiscated by the flip:
        // a quote rotation does not redenominate it, which is the whole reason it
        // has no business gating here.
        assertEq(perp.plvToken(), 1e6, "token principal survives the rotation intact");
        assertEq(vault.tokShareOf(ATTACKER), attackerShares, "and so do their shares");
    }
}
