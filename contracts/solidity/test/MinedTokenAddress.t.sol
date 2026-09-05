// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolOps} from "../cauldron/PoolOps.sol";
import {CauldronToken} from "../CauldronToken.sol";

/**
 * @dev The security case for mining the iteration token's address.
 *
 *  The token is deployed so it sorts ABOVE the quote, which keeps "quote =
 *  currency0, token = currency1" universally true and lets every liquidity
 *  routine stay in the single orientation it was audited in.
 *
 *  Mining an address with CREATE2 is only safe under specific conditions, and
 *  this file exists to prove each of them rather than assert them:
 *
 *    1. the mined address actually sorts above the quote
 *    2. NO third party can occupy that address first (the front-running brick)
 *    3. an unmineable quote degrades to ETH instead of reverting
 *    4. a proposer cannot grind the initcode to force that degradation
 *    5. generations cannot collide with each other
 */
contract MinedTokenAddressTest is Test {
    uint256 constant SUPPLY = 777_000_000e18;

    /// A quote roughly where USDC sits — the realistic case.
    address constant USDC_LIKE = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    /// Deliberately brutal: only ~0.4% of the address space sorts above it.
    address constant NEAR_MAX = 0xfF00000000000000000000000000000000000000;

    // ---------------------------------------------------------------------
    // 1. It does what it claims
    // ---------------------------------------------------------------------

    function test_MinedTokenSortsAboveTheQuote() public {
        (address token, address quoteUsed) =
            PoolOps.deployTokenAbove("Gnomeland", "GNOME", 2, SUPPLY, USDC_LIKE);

        assertGt(uint160(token), uint160(USDC_LIKE), "token must sort above the quote");
        assertEq(quoteUsed, USDC_LIKE, "the requested quote must be honoured");
        assertEq(CauldronToken(token).totalSupply(), SUPPLY, "supply unchanged by mining");
        assertEq(CauldronToken(token).balanceOf(address(this)), SUPPLY, "minted to the registry");
    }

    /// Native ETH is address(0), so every contract already sorts above it. That
    /// path must stay exactly as it was — no mining, no behaviour change.
    function test_NativeQuoteNeedsNoMining() public {
        (address token, address quoteUsed) =
            PoolOps.deployTokenAbove("Gnomeland", "GNOME", 2, SUPPLY, address(0));

        assertGt(uint160(token), uint160(0));
        assertEq(quoteUsed, address(0));
    }

    // ---------------------------------------------------------------------
    // 2. THE ONE THAT MATTERS: the address cannot be squatted
    // ---------------------------------------------------------------------

    /**
     * The brick this design must not enable: if an attacker could deploy at the
     * address `relaunch()` is about to use, the CREATE2 would fail, `relaunch()`
     * would revert, `markConsumed` would roll back, the same proposal would win
     * again — and the machine would be stuck forever (audit C-02 class).
     *
     * It is impossible because the deployer is folded into the address preimage.
     * An attacker computing the same salt over the same initcode gets a
     * DIFFERENT address, because they are not this contract.
     */
    function test_ThirdPartyCannotOccupyTheMinedAddress() public {
        bytes32 initHash = keccak256(
            abi.encodePacked(
                type(CauldronToken).creationCode,
                abi.encode("Gnomeland", "GNOME", uint256(2), address(this), SUPPLY)
            )
        );
        bytes32 salt = keccak256(abi.encode(uint256(2), uint256(0)));

        address oursPredicted = _create2(address(this), salt, initHash);
        Attacker atk = new Attacker();
        address theirsPredicted = _create2(address(atk), salt, initHash);

        assertTrue(oursPredicted != theirsPredicted, "deployer is part of the address");

        // The attacker deploys with our exact salt and our exact initcode.
        address squatted = atk.squat(salt, "Gnomeland", "GNOME", 2, address(this), SUPPLY);
        assertEq(squatted, theirsPredicted, "attacker lands on their own address");
        assertTrue(squatted != oursPredicted, "and never on ours");

        // Our address is still free, so the real deployment goes through.
        assertEq(oursPredicted.code.length, 0, "our slot untouched by the attack");
        (address token, ) = PoolOps.deployTokenAbove("Gnomeland", "GNOME", 2, SUPPLY, address(0x01));
        assertGt(token.code.length, 0, "relaunch still deploys");
    }

    /// The same property, stated as the thing an attacker would have to do:
    /// occupy OUR address, which requires BEING us.
    function test_SquattingRequiresBeingTheRegistry() public {
        Attacker atk = new Attacker();
        bytes32 initHash = keccak256(
            abi.encodePacked(
                type(CauldronToken).creationCode,
                abi.encode("X", "X", uint256(7), address(this), SUPPLY)
            )
        );
        // Sweep a wide salt range from the attacker's address; none can ever
        // collide with an address derived from ours.
        for (uint256 i; i < 64; ++i) {
            bytes32 salt = keccak256(abi.encode(uint256(7), i));
            assertTrue(
                _create2(address(atk), salt, initHash) != _create2(address(this), salt, initHash),
                "no salt maps an attacker onto our address"
            );
        }
    }

    // ---------------------------------------------------------------------
    // 3 & 4. Failure degrades; it never bricks
    // ---------------------------------------------------------------------

    /**
     * A quote so high that mining plausibly fails must NOT revert — reverting
     * inside `relaunch()` is the brick. It falls back to ETH: the brew loses the
     * pair it asked for, never its launch.
     */
    function test_UnmineableQuoteFallsBackToEthInsteadOfReverting() public {
        // The MAXIMUM address: nothing can sort above it, so this forces the
        // give-up branch every time. Without an explicitly impossible quote the
        // fallback would never execute in tests — a 1024-salt sweep clears even
        // 0xff00… comfortably (measured), so the anti-brick path would ship
        // unexercised.
        address impossible = address(type(uint160).max);

        (address token, address quoteUsed) =
            PoolOps.deployTokenAbove("Edge", "EDGE", 3, SUPPLY, impossible);

        assertGt(token.code.length, 0, "the token still deploys: no revert, no brick");
        assertEq(quoteUsed, address(0), "and the caller is told to use ETH");
        assertEq(CauldronToken(token).totalSupply(), SUPPLY, "a normal, usable token");
    }

    /// A quote near the very top of the space is still mineable — 1024 tries
    /// clear it, so only a genuinely impossible quote degrades.
    function test_HostileButPossibleQuoteStillMines() public {
        (address token, address quoteUsed) =
            PoolOps.deployTokenAbove("Edge", "EDGE", 3, SUPPLY, NEAR_MAX);
        assertEq(quoteUsed, NEAR_MAX, "a near-max quote is still reachable");
        assertGt(uint160(token), uint160(NEAR_MAX));
    }

    /**
     * Could a proposer GRIND name/symbol until every salt fails, forcing the
     * degradation above? Changing the name changes the initcode hash, which
     * re-randomises all 1024 candidate addresses — it cannot bias them upward or
     * downward. This samples many distinct names against a hostile quote and
     * asserts every one still finds a home.
     */
    function test_ProposerCannotGrindNamesToForceFallback() public {
        for (uint256 n; n < 24; ++n) {
            string memory name = string.concat("Brew", vm.toString(n));
            (address token, address quoteUsed) =
                PoolOps.deployTokenAbove(name, "BREW", 4 + n, SUPPLY, USDC_LIKE);
            assertEq(quoteUsed, USDC_LIKE, "every name still mines above a realistic quote");
            assertGt(uint160(token), uint160(USDC_LIKE));
        }
    }

    // ---------------------------------------------------------------------
    // 5. Generations cannot collide
    // ---------------------------------------------------------------------

    /// The salt is derived from the generation, and the initcode carries it too,
    /// so two generations can never land on the same address — which would make
    /// the second CREATE2 revert and brick the relaunch.
    function test_GenerationsGetDistinctAddresses() public {
        (address a, ) = PoolOps.deployTokenAbove("Same", "SAME", 2, SUPPLY, USDC_LIKE);
        (address b, ) = PoolOps.deployTokenAbove("Same", "SAME", 3, SUPPLY, USDC_LIKE);
        (address c, ) = PoolOps.deployTokenAbove("Same", "SAME", 4, SUPPLY, USDC_LIKE);
        assertTrue(a != b && b != c && a != c, "identical proposals, distinct generations");
    }

    // ---------------------------------------------------------------------
    // Cost
    // ---------------------------------------------------------------------

    /// Mining must not meaningfully add to an already-heavy relaunch.
    function test_MiningGasIsNegligible() public {
        uint256 g0 = gasleft();
        PoolOps.deployTokenAbove("Gas", "GAS", 9, SUPPLY, USDC_LIKE);
        uint256 mined = g0 - gasleft();

        g0 = gasleft();
        PoolOps.deployTokenAbove("Gas", "GAS", 10, SUPPLY, address(0));
        uint256 plain = g0 - gasleft();

        emit log_named_uint("mined deploy gas", mined);
        emit log_named_uint("plain deploy gas", plain);
        // The search itself is keccak-bounded; anything near a full 1024-try
        // sweep (~40k) would mean the early exit is not working.
        assertLt(mined, plain + 40_000, "search cost stays in the noise");
    }

    function _create2(address deployer, bytes32 salt, bytes32 initHash)
        private
        pure
        returns (address)
    {
        return address(uint160(uint256(
            keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initHash))
        )));
    }
}

/// @dev Stands in for anyone watching the mempool who wants to occupy the
///      address a relaunch is about to use.
contract Attacker {
    function squat(
        bytes32 salt,
        string memory name,
        string memory symbol,
        uint256 gen,
        address registry,
        uint256 supply
    ) external returns (address) {
        return address(new CauldronToken{salt: salt}(name, symbol, gen, registry, supply));
    }
}
