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

    /// This contract is also the VAULT. The engine's rotation guard asks
    /// {hasStakers} — which covers the TOKEN side too, and that is exactly what
    /// makes zeroing `tokYieldEth` at the flip a redenomination rather than a
    /// confiscation. `hasQuoteStake` is kept for the vault's own callers.
    bool public vaultStake;
    function hasStakers() external view returns (bool) { return vaultStake; }
    function hasQuoteStake() external view returns (bool) { return vaultStake; }

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

    function test_QuoteRotation_RedenominatesEveryCounterAndNeverStrandsOne() public {
        perp.setVault(address(this));                // this contract plays the vault
        _accrueNativeObligations();
        uint256 nativeHeld     = address(perp).balance;
        uint256 tokYieldBefore = perp.tokYieldEth();
        uint256 insBefore      = perp.insuranceEth();
        address quoteBefore    = perp.quote();
        uint256 treBefore      = address(0x7E7E).balance;   // the engine's treasury

        // ── 1. still REFUSED while the vault holds someone's value ──────────
        vaultStake = true;
        bool syncedWithVaultStake = _rotateAndSync();
        address quoteAfterRefusal = perp.quote();

        // ── 2. nobody owns them -> the flip REDENOMINATES rather than freezing.
        //  The old guard demanded these counters be ZERO, which `insuranceEth`
        //  can never be once the deploy arms its floor (red-team X8-01), so a
        //  healthy engine could never adopt a rotated quote and the book froze.
        //  They are now swept to the treasury IN THE OLD ASSET and zeroed.
        vaultStake = false;
        bool syncedClean = _rotateAndSync();
        address quoteAfter = perp.quote();
        uint256 treGained = address(0x7E7E).balance - treBefore;

        // ── 3. and no stale counter survives to claim the NEW asset ─────────
        _fundPlvInNewQuote(1_000 ether);
        bool stalePull = _pullTokYield(1 ether);
        uint256 stolen = newQuote.balanceOf(attacker);

        // ── assertions ───────────────────────────────────────────────────────
        assertEq(quoteBefore, address(0), "gen-1 launched native");
        assertEq(nativeHeld, 1.5 ether, "engine holds 1.5 ETH of native obligations");
        assertEq(tokYieldBefore, 1 ether, "tokYieldEth is native wei");
        assertEq(insBefore, 0.5 ether, "insuranceEth is native wei");

        assertFalse(syncedWithVaultStake, "H-2: no flip while the vault holds value");
        assertEq(quoteAfterRefusal, address(0), "quote did NOT move under the stakers");

        assertTrue(syncedClean, "X8-01: a healthy engine CAN adopt the rotated quote");
        assertEq(quoteAfter, address(newQuote), "quote adopted");
        assertEq(treGained, 1.5 ether, "all 1.5 ETH swept to the treasury AS ETH, its own unit");
        assertEq(perp.tokYieldEth(), 0, "no old-unit tokYieldEth survives the flip");
        assertEq(perp.insuranceEth(), 0, "no old-unit insuranceEth survives the flip");
        assertEq(perp.plv(), 1_000 ether, "plv counts ONLY the new asset");
        assertEq(address(perp).balance, 0, "and not one wei of the old asset is stranded");

        assertEq(newQuote.balanceOf(address(perp)), 1_000 ether, "engine holds 1000 USDG");
        assertFalse(stalePull, "no stale counter can pull the new asset");
        assertEq(stolen, 0, "attacker got zero USDG");
        assertGe(newQuote.balanceOf(address(perp)), perp.plv(), "ENGINE SOLVENT vs plv");
    }

    receive() external payable {}
}
