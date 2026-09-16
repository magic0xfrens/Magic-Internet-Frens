// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {YBase} from "./YBase.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";

interface IVotesMin {
    function getVotes(address) external view returns (uint256);
    function getPastVotes(address, uint256) external view returns (uint256);
    function getPastTotalSupply(uint256) external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
}

interface IHookColl {
    function setCollection(address) external;
    function collection() external view returns (address);
}

/// @notice E2A — is the ERC721Votes electorate farmable at ~gas cost by
///         self-liquidating dust perp positions? Real MiFrensGenesis wired.
contract V2A_VoteFarm is YBase {
    MiFrensGenesis internal gen;

    uint256 internal badgesMinted;
    uint256 internal votesAfter;
    uint256 internal netCostWei;
    uint256 internal killsAttempted;
    uint256 internal killsSucceeded;
    bool internal ran;

    function setUp() public {
        _boot(200 ether, 0);
        if (!active) return;
        _bootPerp(60 ether, 0);

        gen = new MiFrensGenesis("MiFrens", "MF", 1111, 10_000, 0.01 ether, 10, "ipfs://");
        // Registry-only wiring; _wireLiquidator points the badge minter at perp.
        vm.prank(address(registry));
        IHookColl(address(hook)).setCollection(address(gen));
        gen.setLiquidatorMinter(address(perp));
        assertEq(gen.liquidatorMinter(), address(perp), "badge minter not wired to engine");
    }

    /// @dev Open N dust 3x longs as `attacker`, crash spot by dumping token,
    ///      self-liquidate each, then buy back. Sets state; no early return
    ///      semantics leak into the test body.
    function _farm(uint256 n) internal {
        // ONE economic actor: this test contract does the swaps, tx.origin holds
        // the positions and receives the badges (the hook credits tx.origin).
        address atk = tx.origin;
        vm.deal(atk, 1_000 ether);
        uint256 start = address(this).balance + atk.balance;
        uint256 min = perp.minCollateral();

        // 1. PUMP with real ETH (real fees + real slippage).
        uint256 bought = _buy(80 ether, address(this));

        // 2. Open n dust 3x longs AT THE TOP.
        for (uint256 i; i < n; ++i) {
            vm.prank(atk);
            perp.openLong{value: min * 2}(3, 0, 0, min * 2);
        }
        uint256 openedAt = perp.openCount();

        // 3. Dump it all back -> in-swap sweep liquidates them, badges to tx.origin.
        uint256 ethBack = _sell(bought, address(this));
        console2.log("pump bought", bought);
        console2.log("dump ethBack", ethBack);
        console2.log("open before dump", openedAt);
        console2.log("open after dump", perp.openCount());

        // 4. Anything the sweep missed, self-liquidate directly (permissionless).
        for (uint256 i = 1; i <= n; ++i) {
            if (perp.openCount() == 0) break;
            killsAttempted++;
            vm.prank(atk, atk);
            try perp.liquidate(i) { killsSucceeded++; } catch {}
        }

        uint256 end = address(this).balance + atk.balance;
        netCostWei = start > end ? start - end : 0;
        badgesMinted = IVotesMin(address(gen)).balanceOf(atk);
        votesAfter = IVotesMin(address(gen)).getVotes(atk);
        killsSucceeded += gen.liquidatorMinted();
        ran = true;
    }

    function test_V2A_selfLiquidationFarmsVotes() public {
        _farm(64);

        console2.log("ran", ran);
        console2.log("kills attempted", killsAttempted);
        console2.log("kills succeeded", killsSucceeded);
        console2.log("badges minted", badgesMinted);
        console2.log("votes", votesAfter);
        console2.log("badgesOwed", perp.badgesOwed(tx.origin));
        console2.log("net cost wei", netCostWei);
        if (badgesMinted > 0) console2.log("wei per badge", netCostWei / badgesMinted);
        console2.log("SENTINEL: assertions below");

        assertTrue(ran, "farm loop did not run");
        assertGt(killsSucceeded, 0, "no self-liquidation succeeded");

        //  THE ATTACK STILL RUNS — badges are still earned and still owned. That
        //  behaviour is deliberately unchanged; a Liquidatoor badge is a real
        //  reward for real, capital-at-risk work.
        assertGt(badgesMinted, 0, "no badge minted to self-liquidator");

        //  IT JUST BUYS NOTHING. This asserted `votesAfter == badgesMinted` and
        //  measured 64 == 64: the electorate was for sale at roughly 0.0018 ETH
        //  a vote, on an id range with no ceiling, against a treasury governed by
        //  a 10%-of-supply quorum. `MiFrensGenesis._update` now routes only
        //  genesis ids (1..GENESIS_SUPPLY) through `ERC721Votes._update`, so a
        //  badge never receives a voting unit at all.
        assertEq(votesAfter, 0, "farmed badges must carry ZERO governance weight");
        assertEq(
            IVotesMin(address(gen)).getPastTotalSupply(vm.getBlockNumber() - 1),
            0,
            "and must not inflate the quorum denominator either"
        );
    }
}
