// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {PoolOps} from "../../cauldron/PoolOps.sol";

/// @notice 6-decimal quote stand-in (USDG in the live manifest).
contract StrandUSDG {
    string public name = "USDG";
    string public symbol = "USDG";
    uint8 public decimals = 6;
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 a) external { balanceOf[to] += a; }

    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }
}

/// @notice Stands in for CauldronHook's two relaunch-reserve release entrypoints.
///         Mirrors the real bodies: the counter is ZEROED and the value is pushed
///         to the caller (the registry).  CauldronHook.sol:1877-1887.
contract StrandHook {
    mapping(address => uint256) public relaunchAsset;
    uint256 public relaunchETH;

    error NoETHToRelease();

    function credit(address asset, uint256 a) external { relaunchAsset[asset] += a; }
    function creditEth() external payable { relaunchETH += msg.value; }

    function releaseRelaunchAsset(address asset) external returns (uint256 amount) {
        amount = relaunchAsset[asset];
        if (amount == 0) revert NoETHToRelease();
        relaunchAsset[asset] = 0;
        StrandUSDG(asset).transfer(msg.sender, amount);
    }

    function releaseRelaunchETH() external returns (uint256 amount) {
        amount = relaunchETH;
        if (amount == 0) revert NoETHToRelease();
        relaunchETH = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "send");
    }
}

/**
 * @title R4A — PoolOps.seedFunding pulls a reserve it then abandons
 *
 *  cauldron/PoolOps.sol:1172-1186
 *
 *      // 1. The proposal's choice, if value already exists in that denomination.
 *      if (wantQuote != address(0) && (recovered == 0 || oldQuote == wantQuote)) {
 *          uint256 p = (oldQuote == wantQuote ? recovered : 0) + _pullAsset(hookAddr, wantQuote);
 *          if (p >= MIN_SEED_UNITS) return (wantQuote, p, 0);
 *      }
 *      // 2. Native ...
 *      if (recovered == 0 || oldQuote == address(0)) {
 *          uint256 n = (oldQuote == address(0) ? recovered : 0) + vaultSwept + _pullEth(hookAddr);
 *          if (n >= MIN_SEED_UNITS) return (address(0), n, vaultSwept);
 *      }
 *
 *  `_pullAsset` is a STATE CHANGE (CauldronHook.releaseRelaunchAsset zeroes
 *  `relaunchAsset[asset]` and transfers the whole balance to the registry), but
 *  the branch's acceptance test runs AFTER it.  A short branch therefore moves
 *  the reserve out of the hook and then falls through to a different
 *  denomination, so the pulled amount is not part of `amount`, is not seeded,
 *  and (as PoolOps' own comment at :1128 says) "nothing in the normal cycle
 *  spends a loose registry balance".
 *
 *  MIN_SEED_UNITS = 777_000_000e18 >> 60 = 673,940,064 base units.  In an
 *  18-decimal asset that is dust; in the 6-decimal USDG this protocol
 *  allowlists it is 673.94 USDG.
 */
contract R4A_SeedFundingStrand is Test {
    /// @dev Mirrors PoolOps.MIN_SEED_UNITS (`777_000_000e18 >> 60`), which is
    ///      673_940_070 base units — 673.94007 USDG at 6 decimals.
    uint256 internal constant MIN_SEED = 777_000_000e18 >> 60;

    StrandUSDG internal usdg;
    StrandHook internal hook;

    receive() external payable {}

    function setUp() public {
        usdg = new StrandUSDG();
        hook = new StrandHook();
    }

    /// @dev Stage a hook reserve of `usdgAmount` USDG + `ethAmount` wei and run
    ///      seedFunding with USDG as the proposal's requested quote and a dead
    ///      pool that recovered nothing.
    function _run(uint256 usdgAmount, uint256 ethAmount)
        internal
        returns (address quoteUsed, uint256 amount, uint256 strandedUsdg, uint256 hookLeft)
    {
        usdg.mint(address(hook), usdgAmount);
        hook.credit(address(usdg), usdgAmount);
        hook.creditEth{value: ethAmount}();

        uint256 before = usdg.balanceOf(address(this));
        (quoteUsed, amount, ) = PoolOps.seedFunding(
            address(hook),
            address(usdg), // wantQuote  — the winning proposal's spec.quote
            address(0),    // oldQuote   — the dying generation launched on ether
            0,             // recovered  — dead pool returned nothing
            address(0)     // oldVault
        );
        strandedUsdg = usdg.balanceOf(address(this)) - before;
        hookLeft = hook.relaunchAsset(address(usdg));
    }

    /// @notice POSITIVE CONTROL: a reserve at or above MIN_SEED_UNITS is used,
    ///         nothing is abandoned.
    function test_positive_fundedQuoteIsUsed() public {
        uint256 amt = 800e6; // 800 USDG > 673.94
        (address q, uint256 seeded, uint256 stranded, uint256 left) = _run(amt, 10 ether);
        console2.log("positive: quoteUsed", q);
        console2.log("positive: seeded", seeded);
        assertEq(q, address(usdg), "quote should be the requested USDG");
        assertEq(seeded, amt, "the whole reserve funds the newborn");
        assertEq(stranded, amt, "pulled into the registry AND counted");
        assertEq(left, 0, "hook reserve drained into the seed");
    }

    /// @notice REGRESSION (was the attack): a reserve one unit BELOW the floor is
    ///         no longer pulled out of the hook.  The seed still falls through to
    ///         ether — that part is by design — but the USDG stays where a later
    ///         rebirth can still spend it, instead of becoming a loose registry
    ///         balance no cycle path reads.
    function test_attack_shortQuoteReserveIsPulledAndAbandoned() public {
        uint256 amt = 673_940_063; // MIN_SEED_UNITS - 1  (673.940063 USDG)
        (address q, uint256 seeded, uint256 stranded, uint256 left) = _run(amt, 10 ether);

        console2.log("regression: quoteUsed", q);
        console2.log("regression: seeded", seeded);
        console2.log("regression: usdg moved to registry", stranded);
        console2.log("regression: usdg left on hook", left);

        // The seed still uses ETHER — the short branch declines, as it always did.
        assertEq(q, address(0), "seed fell through to native");
        assertEq(seeded, 10 ether, "native branch answered");
        // ...and the hook's USDG reserve is UNTOUCHED.
        assertEq(stranded, 0, "nothing was pulled by the branch that declined");
        assertEq(left, amt, "hook reserve intact");
        assertEq(usdg.balanceOf(address(hook)), amt, "tokens never left the hook");
    }

    /// @notice The declined reserve is still live: once it grows past the floor the
    ///         very next rebirth funds in USDG out of the same balance.
    function test_attack_abandonedReserveIsNotRecoveredNextTime() public {
        uint256 amt = 673_940_063;
        _run(amt, 10 ether);

        // Second rebirth, same request, nothing new accrued: still declines, still
        // does not consume the reserve.
        (address q2, uint256 seeded2, ) = PoolOps.seedFunding(
            address(hook), address(usdg), address(0), 0, address(0)
        );
        uint256 heldByRegistry = usdg.balanceOf(address(this));
        console2.log("second run quote", q2);
        console2.log("second run seeded", seeded2);
        console2.log("registry-held USDG", heldByRegistry);

        assertEq(q2, address(0), "still cannot fund in USDG");
        assertEq(seeded2, 0, "hook ETH already spent, nothing left");
        assertEq(heldByRegistry, 0, "nothing was ever parked in the registry");
        assertEq(hook.relaunchAsset(address(usdg)), amt, "reserve preserved across rebirths");

        // A few more base units of fees arrive and the reserve becomes spendable.
        // MIN_SEED_UNITS = 777_000_000e18 >> 60 = 673_940_070 exactly (PoolOps.sol:220),
        // so `amt` above is seven base units short of the floor.
        uint256 top = MIN_SEED - amt;
        usdg.mint(address(hook), top);
        hook.credit(address(usdg), top);
        (address q3, uint256 seeded3, ) = PoolOps.seedFunding(
            address(hook), address(usdg), address(0), 0, address(0)
        );
        console2.log("third run quote", q3);
        console2.log("third run seeded", seeded3);
        assertEq(q3, address(usdg), "the preserved reserve funds the newborn");
        assertEq(seeded3, MIN_SEED, "whole reserve, nothing lost along the way");
        assertEq(usdg.balanceOf(address(this)), MIN_SEED, "and it reached the registry to be seeded");
    }
}
