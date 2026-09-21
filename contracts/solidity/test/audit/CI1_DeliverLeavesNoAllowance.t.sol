// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {FeeRouteLib} from "../../cauldron/FeeRouteLib.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  CI-1 — {FeeRouteLib.deliver} MUST LEAVE NO STANDING ALLOWANCE
 *  (core-immutable audit 2026-09-21, FINDING-3)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  `deliver` approves `amount` and asks the recipient to pull. Its comment has
 *  always promised to "leave no standing allowance behind", but the revoke ran
 *  under `if (!ok)` — only when the pull FAILED. That is sound exactly while
 *  every pull entrypoint consumes the whole approval, which every wired
 *  recipient does today ({MiFrensDividend.fundToken} pulls exactly `amount`).
 *
 *  A recipient whose pull SUCCEEDS having taken less leaves the remainder
 *  approved, and nothing afterwards ever revokes it. Not a live bug — it is
 *  unreachable on the current wiring — but {FeeRouteLib} is a LINKED library
 *  whose address is baked into {CauldronHook} at link time, so a future call
 *  site cannot be handed the guard later. Pinned here so it cannot regress.
 *
 *  Run:
 *    FOUNDRY_PROFILE=cauldron forge test --match-contract CI1_DeliverLeavesNoAllowance -vv
 */

/// @dev Minimal ERC20 with a real allowance ledger. No OZ import: this suite
///      must stay compilable in isolation from the rest of the tree.
contract MiniToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 a) external { balanceOf[to] += a; }

    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a;
        return true;
    }

    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        uint256 al = allowance[f][msg.sender];
        require(al >= a, "allowance");
        require(balanceOf[f] >= a, "balance");
        allowance[f][msg.sender] = al - a;
        balanceOf[f] -= a;
        balanceOf[t] += a;
        return true;
    }
}

/// @dev A recipient that pulls only PART of what it was approved and still
///      returns success — the exact shape the old `if (!ok)` revoke missed.
contract PartialPuller {
    uint256 public immutable numerator;
    uint256 public immutable denominator;

    constructor(uint256 n, uint256 d) { numerator = n; denominator = d; }

    /// @notice Same shape as {MiFrensDividend.fundToken}: `sel(asset, amount)`.
    function fundToken(address asset, uint256 amount) external {
        uint256 take = (amount * numerator) / denominator;
        if (take != 0) MiniToken(asset).transferFrom(msg.sender, address(this), take);
        // returns normally => `ok == true`
    }
}

/// @dev A recipient that consumes the whole approval, like every wired one.
contract FullPuller {
    function fundToken(address asset, uint256 amount) external {
        MiniToken(asset).transferFrom(msg.sender, address(this), amount);
    }
}

/// @dev A recipient whose pull reverts — the path the old code already covered.
contract RevertingPuller {
    function fundToken(address, uint256) external pure { revert("nope"); }
}

/**
 * @dev `deliver` is `external` on a linked library, so it must be reached by a
 *      real call from a caller that holds the funds. This stand-in plays the
 *      hook: it owns the tokens and delegates nothing, so `msg.sender` at the
 *      token is THIS contract and the allowance under test is its own.
 */
contract Router {
    function go(address asset, address to, uint256 amount, bytes4 sel) external returns (bool) {
        return FeeRouteLib.deliver(asset, to, amount, bytes4(0), sel);
    }
}

contract CI1_DeliverLeavesNoAllowance is Test {
    MiniToken tok;
    Router router;

    bytes4 constant FUND_SEL = bytes4(keccak256("fundToken(address,uint256)"));

    function setUp() public {
        tok = new MiniToken();
        router = new Router();
        tok.mint(address(router), 1_000 ether);
    }

    /// THE REGRESSION. A partial pull that SUCCEEDS must not leave the
    /// remainder standing. Against the pre-fix library this asserts 40 ether.
    function test_CI1_partialPullLeavesNoStandingAllowance() public {
        PartialPuller sink = new PartialPuller(60, 100); // takes 60%
        uint256 amount = 100 ether;

        bool ok = router.go(address(tok), address(sink), amount, FUND_SEL);

        assertTrue(ok, "precondition: the partial pull must report success");
        assertEq(tok.balanceOf(address(sink)), 60 ether, "precondition: it took only 60%");
        assertEq(
            tok.allowance(address(router), address(sink)),
            0,
            "STANDING ALLOWANCE: the unpulled 40% is still approved to the recipient"
        );
    }

    /// The happy path must be unchanged: full pull, nothing left approved.
    function test_CI1_fullPullStillDeliversAndLeavesNothing() public {
        FullPuller sink = new FullPuller();
        uint256 amount = 100 ether;

        bool ok = router.go(address(tok), address(sink), amount, FUND_SEL);

        assertTrue(ok, "a full pull still reports delivered");
        assertEq(tok.balanceOf(address(sink)), amount, "it took everything");
        assertEq(tok.allowance(address(router), address(sink)), 0, "nothing left approved");
    }

    /// The path the old code DID cover must keep working: a reverting pull
    /// reports false and revokes.
    function test_CI1_revertingPullReportsFalseAndRevokes() public {
        RevertingPuller sink = new RevertingPuller();

        bool ok = router.go(address(tok), address(sink), 100 ether, FUND_SEL);

        assertFalse(ok, "a reverting pull must report false so the caller buffers it");
        assertEq(tok.balanceOf(address(sink)), 0, "nothing moved");
        assertEq(tok.allowance(address(router), address(sink)), 0, "and nothing left approved");
    }

    /// A codeless recipient is not a delivery (red-team X4e) — pinned so the
    /// unconditional revoke added above cannot be mistaken for the guard.
    function test_CI1_codelessRecipientStillReportsFalse() public {
        address nobody = address(0xBEEF);
        assertEq(nobody.code.length, 0, "precondition: recipient has no code");

        bool ok = router.go(address(tok), nobody, 100 ether, FUND_SEL);

        assertFalse(ok, "codeless recipient must never report delivered");
        assertEq(tok.allowance(address(router), nobody), 0, "and must never be approved");
    }
}
