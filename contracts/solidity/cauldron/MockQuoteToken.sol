// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockQuoteToken
 * @notice A TESTNET stand-in for a quote asset (USDG, a tokenized equity).
 *
 *  Freely mintable on purpose: a rotation cannot be demonstrated end to end
 *  without a supply of the asset being rotated into, and no real USDG or
 *  tokenized-equity contract exists on Sepolia to point at.
 *
 *  NEVER deploy this to mainnet. On mainnet the registry allowlists the real
 *  asset's address and no mock is involved.
 */
contract MockQuoteToken is ERC20 {
    uint8 private immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 dec_) ERC20(name_, symbol_) {
        _decimals = dec_;
    }

    function decimals() public view override returns (uint8) { return _decimals; }

    /// @notice Anyone may mint. Testnet only — see the contract notice.
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}
