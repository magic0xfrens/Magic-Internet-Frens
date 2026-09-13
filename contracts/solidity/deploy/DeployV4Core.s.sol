// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IPositionDescriptor} from "v4-periphery/src/interfaces/IPositionDescriptor.sol";
import {IWETH9} from "v4-periphery/src/interfaces/external/IWETH9.sol";

/**
 * @title DeployV4Core
 * @notice Stand up Uniswap v4 on a chain that does not have it yet.
 *
 *  ── WHY THIS EXISTS ──────────────────────────────────────────────────────
 *  The whole protocol IS a v4 hook: the NFT mint, the dividend routing, the
 *  perp mark and the keeper-free liquidation sweep all run inside v4's swap
 *  lifecycle. Porting to a chain without v4 therefore means deploying v4, not
 *  stubbing it — a mock router would execute none of the callbacks the design
 *  depends on, so it would prove nothing.
 *
 *  ── WHAT THE TARGET CHAIN MUST HAVE ──────────────────────────────────────
 *  Verified on Arc testnet (chainId 5042002) before writing this:
 *
 *    TRANSIENT STORAGE (EIP-1153)  the hard one. v4 settles every unlock
 *                                  through TSTORE/TLOAD, so a chain without it
 *                                  cannot run v4 at all. Probed with a raw
 *                                  eth_call running TSTORE/TLOAD: returned 42.
 *    CREATE2 factory               the hook's permission bits live in its
 *                                  ADDRESS, so it is mined with CREATE2.
 *    Permit2                       PositionManager pulls tokens through it.
 *    18-decimal native             `PoolOps._sqrtPrice` cannot represent a
 *                                  quote below TOTAL_SUPPLY/2^64; on a
 *                                  6-decimal native that is ~674 units and a
 *                                  small seed bricks the launch behind
 *                                  `markConsumed` (audit Z-01). Arc prices a
 *                                  21k-gas transfer at 4.5e14, i.e. 18dp.
 *
 *  Run:
 *    forge script deploy/DeployV4Core.s.sol --rpc-url $ARC --broadcast
 *  Then feed the two printed addresses to the launchpad deploy as
 *  POOL_MANAGER / POSITION_MANAGER.
 */
contract DeployV4Core is Script {
    /// @dev Permit2 is deployed at the same address on every chain that has it.
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /// @dev v4-periphery's own default. Bounds the gas a subscriber may burn
    ///      when a position unsubscribes, so a hostile subscriber cannot brick
    ///      the unsubscribe. Nothing in this protocol subscribes, but the
    ///      constructor requires a sane value rather than zero.
    uint256 internal constant UNSUBSCRIBE_GAS_LIMIT = 300_000;

    function run() external {
        uint256 pk = vm.envOr("PRIVATE_KEY", uint256(0));
        address deployer = pk != 0 ? vm.addr(pk) : msg.sender;

        //  REFUSE TO RUN WITHOUT PERMIT2. `PositionManager` takes it as an
        //  immutable, so a zero or codeless address produces a manager whose
        //  every mint reverts on the token pull — discovered only at the first
        //  seed, long after the deploy "succeeded".
        require(PERMIT2.code.length > 0, "permit2 not deployed on this chain");

        if (pk != 0) vm.startBroadcast(pk);
        else vm.startBroadcast();

        //  The PoolManager owner governs protocol FEES only — it cannot touch
        //  pools or positions. Held by the deployer here; on a real deployment
        //  hand it to the same timelock that owns the rest.
        PoolManager poolManager = new PoolManager(deployer);

        //  `tokenDescriptor` and `weth9` are both optional for this protocol:
        //  the descriptor only renders `tokenURI` for LP NFTs (which nothing
        //  here reads), and weth9 only serves the native-wrapping helpers,
        //  which this stack does not use — it settles native directly.
        PositionManager positionManager = new PositionManager(
            IPoolManager(address(poolManager)),
            IAllowanceTransfer(PERMIT2),
            UNSUBSCRIBE_GAS_LIMIT,
            IPositionDescriptor(address(0)),
            IWETH9(address(0))
        );

        vm.stopBroadcast();

        console2.log("chainId          :", block.chainid);
        console2.log("PoolManager      :", address(poolManager));
        console2.log("PositionManager  :", address(positionManager));
        console2.log("");
        console2.log("Feed these to the launchpad deploy:");
        console2.log("  export POOL_MANAGER=%s", address(poolManager));
        console2.log("  export POSITION_MANAGER=%s", address(positionManager));
    }
}
