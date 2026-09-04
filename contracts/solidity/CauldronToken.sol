// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title CauldronToken
 * @notice A generation-bound ERC20 with a FIXED, non-mintable supply.
 *
 *  Each generation is a fresh deployment. Its ENTIRE supply is minted ONCE, in
 *  the constructor, to the registry — there is no `mint()` function, no owner,
 *  and no role that can ever increase supply. Distribution (LP seed, genesis
 *  bonus, 1:1 migration) happens purely by TRANSFER of these pre-minted tokens.
 *  The only supply-changing action is `burn()` (registry-only), which can only
 *  ever DECREASE supply — so the token is provably non-inflationary and analytics
 *  scanners see it as fixed-supply, not "mintable".
 *
 *  NOT FREEZABLE. There is no death-freeze: when a generation's pool is retired,
 *  its token stays fully transferable forever. Holders who prefer an old
 *  iteration simply keep (or trade) it; migrating to the live iteration is
 *  OPTIONAL, done by burning the old token 1:1 for the new via the registry.
 *
 *  NO transfer tax — V4 flash accounting breaks fee-on-transfer tokens. Swap
 *  fees are collected by the CauldronHook via afterSwap return deltas instead.
 */
contract CauldronToken is ERC20 {
    error NotRegistry();

    uint256 public constant TOTAL_SUPPLY = 777_000_000e18; // 777M tokens

    uint256 public immutable generation;
    uint256 public immutable birthBlock;
    address public immutable registry;

    /// @param _initialSupply Full fixed supply, minted once to the registry.
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _generation,
        address _registry,
        uint256 _initialSupply
    ) ERC20(_name, _symbol) {
        generation = _generation;
        birthBlock = block.number;
        registry = _registry;
        _mint(_registry, _initialSupply); // one-time; supply is fixed forever
    }

    modifier onlyRegistry() {
        if (msg.sender != registry) revert NotRegistry();
        _;
    }

    /// @notice Burn `amount` from `from`. Registry-only — used to burn recovered
    ///         dead-pool LP tokens, to burn a holder's previous-generation tokens
    ///         when they migrate 1:1, and to burn unclaimed migration leftovers.
    ///         Burning only ever REDUCES supply; there is no minting counterpart.
    function burn(address from, uint256 amount) external onlyRegistry {
        _burn(from, amount);
    }
}
