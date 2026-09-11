// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

/// Minimal PoolManager stand-in: PerpEngine only touches `extsload` on the paths
/// this PoC exercises (constructor + syncGeneration -> _currentTick -> getSlot0).
contract X3aPM {
    // slot0 = (tick 0 << 160) | sqrtPriceX96 = 2**96, i.e. a live 1:1 pool, so the
    // engine's `_quoteEth` (reached from skimInsurance) has a usable price.
    bytes32 constant S0 = bytes32(uint256(79228162514264337593543950336));
    function extsload(bytes32) external pure returns (bytes32) { return S0; }
    function extsload(bytes32, uint256 n) external pure returns (bytes32[] memory r) { r = new bytes32[](n); }
    function extsload(bytes32[] calldata s) external pure returns (bytes32[] memory r) { r = new bytes32[](s.length); }
}

/// Registry stand-in. `generationQuote` is what a TREASURY QUOTE ROTATION moves.
contract X3aRegistry {
    address public currentToken;
    uint256 public currentGeneration = 1;
    uint256 public lastSummonAt;
    mapping(uint256 => address) public generationQuote;

    constructor(address tok) { currentToken = tok; lastSummonAt = block.timestamp; }
    function rotateQuote(address q) external { generationQuote[currentGeneration] = q; }
}

/**
 * X3a — REGRESSION (was: a quote rotation re-denominated EVERY quote-denominated
 * counter the engine holds except `plv`, the only one `syncGeneration` guarded).
 *
 * The guard now enumerates the whole set — `plv | tokYieldEth | insuranceEth |
 * payoutOwedTotal` — and additionally asks the wired vault whether its own
 * quote-side (shares or a queued exit) is empty. A rotation is REFUSED while any
 * of them stands, and succeeds once they have been paid out in the asset they
 * were accrued in.
 *
 * The test contract plays the hook (so it may credit perp fees), the owner (so it
 * may wire the vault and skim insurance) AND the vault (so it may pull the
 * token-side yield pot). `syncGeneration` is called by an unrelated EOA — it is
 * permissionless, which is exactly why the guard has to be complete.
 */
contract X3aQuoteRotationRedenominates is Test {
    X3aPM pm;
    X3aRegistry reg;
    PerpEngine perp;
    MockQuoteToken tok;
    MockQuoteToken newQuote;      // 18-decimal ERC20 the treasury rotates into
    address attacker = address(0xA77ACC);

    /// This contract is also the VAULT; `quoteStake` is its {hasQuoteStake} answer.
    bool public quoteStake;
    function hasStakers() external pure returns (bool) { return false; }
    function hasQuoteStake() external view returns (bool) { return quoteStake; }

    function setUp() public {
        pm = new X3aPM();
        tok = new MockQuoteToken("Gen1", "G1", 18);
        reg = new X3aRegistry(address(tok));
        reg.rotateQuote(address(0));                 // gen-1 launched NATIVE
        perp = new PerpEngine(
            IPoolManager(address(pm)), address(this), address(reg),
            address(0xBEEF), address(0xD1D1), address(0x7E7E), address(this)
        );
        newQuote = new MockQuoteToken("USDG", "USDG", 18);
        vm.deal(address(this), 100 ether);
    }

    // The engine calls this on the hook inside _isDead(); answer honestly.
    function isDead(PoolId) external pure returns (bool) { return false; }

    // ── helpers (all conditional logic lives here, per the PoC rule) ──────────

    /// Accrue the two NATIVE counters the old guard did not consider.
    function _accrueNativeObligations() internal {
        perp.creditPerpFeeToken{value: 1 ether}();   // hook-only -> tokYieldEth
        perp.fundInsurance{value: 0.5 ether}(0.5 ether);
    }

    /// The treasury rotates the generation's quote, then ANYONE syncs.
    function _rotateAndSync() internal returns (bool ok) {
        reg.rotateQuote(address(newQuote));
        vm.prank(attacker);
        try perp.syncGeneration() { ok = true; } catch { ok = false; }
    }

    /// Honest ETH-side LP yield arriving in the NEW quote (the hook's ERC20 path).
    function _fundPlvInNewQuote(uint256 amount) internal {
        newQuote.mint(address(this), amount);
        newQuote.approve(address(perp), amount);
        perp.creditPerpFeeAsset(address(newQuote), amount);
    }

    /// The vault (this contract) pulling the token-side reward pot.
    function _pullTokYield(uint256 amount) internal returns (bool ok) {
        try perp.withdrawTokYieldTo(amount, attacker) { ok = true; } catch { ok = false; }
    }

    function test_QuoteRotation_RefusedWhileAnyQuoteCounterStands() public {
        perp.setVault(address(this));                // this contract plays the vault
        _accrueNativeObligations();
        uint256 nativeHeld   = address(perp).balance;
        uint256 tokYieldBefore = perp.tokYieldEth();
        uint256 insBefore      = perp.insuranceEth();
        address quoteBefore    = perp.quote();

        // ── 1. the rotation is REFUSED while 1.5 ETH of obligations stand ────
        bool syncedWithCounters = _rotateAndSync();
        address quoteAfterRefusal = perp.quote();

        // ── 2. they are payable in the asset they were accrued in ───────────
        uint256 attackerEthBefore = attacker.balance;
        bool pulledNative = _pullTokYield(1 ether);
        perp.skimInsurance(0.5 ether, attacker);
        uint256 attackerEthGained = attacker.balance - attackerEthBefore;

        // ── 3. still refused while the VAULT holds quote-side value (H-2) ───
        quoteStake = true;
        bool syncedWithVaultStake = _rotateAndSync();

        // ── 4. drained on both sides -> the rotation goes through ───────────
        quoteStake = false;
        bool syncedClean = _rotateAndSync();
        address quoteAfter = perp.quote();

        // ── 5. and no stale counter survives to claim the new asset ─────────
        _fundPlvInNewQuote(1_000 ether);
        bool stalePull = _pullTokYield(1 ether);
        uint256 stolen = newQuote.balanceOf(attacker);

        // ── assertions ───────────────────────────────────────────────────────
        assertEq(quoteBefore, address(0), "gen-1 launched native");
        assertEq(nativeHeld, 1.5 ether, "engine holds 1.5 ETH of native obligations");
        assertEq(tokYieldBefore, 1 ether, "tokYieldEth is native wei");
        assertEq(insBefore, 0.5 ether, "insuranceEth is native wei");

        assertFalse(syncedWithCounters, "H-1: rotation REFUSED while tokYield/insurance stand");
        assertEq(quoteAfterRefusal, address(0), "quote did NOT flip under the obligations");

        assertTrue(pulledNative, "the native counters stay payable in native");
        assertEq(attackerEthGained, 1.5 ether, "all 1.5 ETH paid out as ETH, not as USDG");
        assertEq(perp.tokYieldEth(), 0, "tokYieldEth drained");
        assertEq(perp.insuranceEth(), 0, "insuranceEth drained");
        assertEq(address(perp).balance, 0, "no native stranded behind the flip");

        assertFalse(syncedWithVaultStake, "H-2: rotation REFUSED while the vault has quote-side value");
        assertTrue(syncedClean, "a genuinely drained engine CAN still rotate - not bricked");
        assertEq(quoteAfter, address(newQuote), "quote adopted once nothing is owed in the old one");

        assertEq(perp.plv(), 1_000 ether, "plv now claims 1000 USDG");
        assertEq(newQuote.balanceOf(address(perp)), 1_000 ether, "and the engine holds 1000 USDG");
        assertFalse(stalePull, "no stale counter can pull the new asset");
        assertEq(stolen, 0, "attacker got zero USDG");
        assertGe(newQuote.balanceOf(address(perp)), perp.plv(), "ENGINE SOLVENT vs plv");
    }

    receive() external payable {}
}
