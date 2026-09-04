// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMiFrensGenesisFinalize {
    function finalize() external returns (address token);
    function soldOut() external view returns (bool);
}

interface IRegistryCurrent {
    function currentToken() external view returns (address);
}

interface IGachaPlay {
    function play(uint256 gnomeIn, uint256 minGnomeOut, uint256 minEthOut, uint256 openMax)
        external payable returns (uint256);
}

/**
 * @title LaunchSniper
 * @notice Atomic, MEV-proof launch of iteration #1 + the deployer's funding buy.
 *
 *  In ONE transaction it:
 *    1. `finalize()`s the sold-out presale → the registry summons gen-1, deploys
 *       the token, and seeds the V4 LP pool.
 *    2. immediately buys $GNOME from that pool with the ETH sent to this call
 *       (routed through the gacha router, tagged as THIS contract's play), and
 *    3. forwards the bought $GNOME to `airdropWallet`.
 *
 *  Because it all happens atomically, NOTHING can execute between pool creation
 *  and the buy — no sandwich, no first-block front-run. This contract must be
 *  flagged fee-EXEMPT on the hook (`setTaxExempt(launchSniper, true)`) so the buy
 *  skips the base tax + anti-sniper surtax; every OTHER block-0 buyer still pays
 *  the ~99% launch surtax, so a competing snipe is unprofitable anyway.
 *
 *  Deploy → `hook.setTaxExempt(address(this), true)` → (mint 1111 to sell out) →
 *  `launch{value: fundingETH}(...)`.
 */
contract LaunchSniper is Ownable {
    error NotSoldOut();
    error NoValue();

    event Launched(address indexed token, uint256 ethIn, uint256 gnomeBought, address indexed to);

    constructor(address _owner) Ownable(_owner) {}

    /**
     * @param presale       MiFrensGenesis (must be sold out).
     * @param registry       CauldronRegistry (read the summoned token from it).
     * @param gachaRouter    CauldronGachaRouter (does the tax-exempt buy).
     * @param airdropWallet  where the bought $GNOME is forwarded (the distributor).
     * @param minGnomeOut    slippage floor on the buy (revert if below).
     * @param openMax        crystals to open (1 = minimal side-effect; the buy is
     *                       what we care about).
     */
    function launch(
        address presale,
        address registry,
        address gachaRouter,
        address airdropWallet,
        uint256 minGnomeOut,
        uint256 openMax
    ) external payable onlyOwner returns (address token, uint256 gnomeBought) {
        if (msg.value == 0) revert NoValue();
        if (!IMiFrensGenesisFinalize(presale).soldOut()) revert NotSoldOut();

        // 1. Ignite: summons gen-1 + seeds the LP pool (atomic with the buy below).
        IMiFrensGenesisFinalize(presale).finalize();
        token = IRegistryCurrent(registry).currentToken();

        // 2. Snipe the fresh pool tax-free (this contract is hook-exempt). The
        //    router tags the swap with this contract as the player, so exemption
        //    applies and the $GNOME lands here.
        IGachaPlay(gachaRouter).play{value: msg.value}(0, minGnomeOut, 0, openMax);

        // 3. Forward the bought $GNOME to the airdrop distributor.
        gnomeBought = IERC20(token).balanceOf(address(this));
        if (gnomeBought > 0) IERC20(token).transfer(airdropWallet, gnomeBought);

        emit Launched(token, msg.value, gnomeBought, airdropWallet);
    }

    /// @notice Recover any stray ETH/tokens (e.g. gacha router refund) to owner.
    function sweep(address tokenAddr) external onlyOwner {
        if (tokenAddr == address(0)) {
            (bool ok, ) = owner().call{value: address(this).balance}("");
            require(ok, "eth");
        } else {
            IERC20(tokenAddr).transfer(owner(), IERC20(tokenAddr).balanceOf(address(this)));
        }
    }

    receive() external payable {}
}
