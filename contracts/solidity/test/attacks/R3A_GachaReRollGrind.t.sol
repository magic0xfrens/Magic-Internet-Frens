// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {FinalAuditBase} from "../final/FinalAuditBase.sol";

/// @dev Minimal ICauldronCollection the hook can drive.
contract R3MockCol {
    uint256 public totalMinted;
    uint256 public maxSupply = 1000;
    mapping(uint256 => address) public ownerOf;

    function mint(address to) external returns (uint256 id) {
        totalMinted += 1;
        id = totalMinted;
        ownerOf[id] = to;
    }

    // swallow the hook's best-effort badge wiring
    fallback() external {}
}

/// @notice R3A — REGRESSION. The gacha win/lose roll used to be re-rollable an
///         UNLIMITED number of times by simply not resolving a losing batch for
///         256 blocks (measured: 20 free re-anchors, a 900-bps ticket ground into
///         a mint). GachaLib now caps the re-anchor at ONE per batch, matching
///         CauldronCollection.sol:253 and MiFrensGenesis.sol:559.
contract R3A_GachaReRollGrind is FinalAuditBase {
    using stdStorage for StdStorage;

    R3MockCol internal col;
    address internal attacker = address(0xA11CE);

    uint256 internal constant PLAY_WEI = 0.05 ether; // a realistic 0.05 ETH play -> 900 bps (9%)

    function setUp() public {
        _deployOffchain(address(0xBEEF));
        col = new R3MockCol();
        vm.prank(address(registry));
        hook.setCollection(address(col));
        hook.setOpener(address(this), true);
        uint256 epoch = hook.creditEpoch();
        stdstore.target(address(hook)).sig("nftCredit(uint256,address)").with_key(epoch).with_key(attacker)
            .checked_write(uint256(1000 ether));
    }

    // ---------------------------------------------------------------- helpers

    /// @dev Grind the single queued crystal: peek at the seed, resolve only on a
    ///      win, otherwise wait out the 256-block window and re-stamp.
    function _grind(uint256 maxTries)
        internal
        returns (uint256 reanchors, bool won, uint256 tries)
    {
        for (uint256 i = 0; i < maxTries; ++i) {
            (,, uint48 cb, uint16 odds,,) = hook.batches(0);
            if (vm.getBlockNumber() <= cb) vm.roll(uint256(cb) + 1);
            bytes32 bh = blockhash(cb);
            if (bh != bytes32(0)) {
                uint256 roll =
                    uint256(keccak256(abi.encodePacked(bh, attacker, uint256(0), uint256(0)))) % 10_000;
                if (roll < odds) {
                    hook.resolveTickets(1);
                    won = true;
                    tries = i + 1;
                    break;
                }
                // LOSING SEED: do not resolve. Wait out the blockhash window.
                vm.roll(vm.getBlockNumber() + 257);
            }
            // The seed has aged out: one gas-only call re-stamps the batch to a
            // fresh, still-unknown block => a brand new draw.
            hook.resolveTickets(1);
            (,, uint48 cb2,,,) = hook.batches(0);
            if (cb2 > cb) reanchors += 1;
            tries = i + 1;
        }
    }

    // ------------------------------------------------------------------- test

    function test_R3A_LosingCrystalCanBeReRolledForever() public {
        // Commit ONE crystal at the smallest play size: 1 bps win chance.
        uint256 n = hook.commitCrystals(attacker, 1, PLAY_WEI);
        (,,, uint16 odds, uint16 count,) = hook.batches(0);

        (uint256 reanchors, bool won, uint256 tries) = _grind(300);

        console2.log("odds bps", odds);
        console2.log("re-anchors used", reanchors);
        console2.log("tries", tries);
        console2.log("minted", col.totalMinted());

        assertEq(n, 1, "one crystal committed");
        assertEq(count, 1, "batch of one");
        assertLe(uint256(odds), 900, "a 9% ticket");
        // REGRESSION (was: assertGt(reanchors, 1) / assertTrue(won) / minted == 1).
        // Before the fix this grind used 20 free re-anchors and turned a 900-bps
        // ticket into a mint. GachaLib now caps the re-anchor at ONE per batch,
        // so the grind gets exactly one honest second draw and, on declining it,
        // the batch commits its base outcome (a loss) and can never be re-rolled.
        assertLe(reanchors, 1, "at most ONE re-anchor per batch");
        assertFalse(won, "the ticket can no longer be ground into a win");
        assertEq(col.totalMinted(), 0, "no NFT minted from a re-rolled ticket");
        // And the crystal is not left stranded: the batch resolved.
        (,,,,, uint16 resolvedNow) = hook.batches(0);
        assertEq(resolvedNow, count, "the forfeited batch still resolves (no wedge)");
        assertEq(hook.pendingOf(attacker), 0, "player has no stuck crystal");
    }
}
