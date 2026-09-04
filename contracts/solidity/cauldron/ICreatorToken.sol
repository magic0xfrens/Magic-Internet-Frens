// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice The transfer validator a creator token defers to. A market that
///         doesn't pay the royalty isn't on the validator's allowlist, so its
///         transfer reverts here — that's what makes the fee unavoidable.
interface ITransferValidator {
    function validateTransfer(address caller, address from, address to, uint256 tokenId) external view;
}

/// @notice The ERC-721C creator-token surface OpenSea (and other markets)
///         recognize to discover + honor a collection's transfer validator.
interface ICreatorToken {
    event TransferValidatorUpdated(address oldValidator, address newValidator);

    function getTransferValidator() external view returns (address);
    function getTransferValidationFunction() external view returns (bytes4 functionSignature, bool isViewFunction);
    function setTransferValidator(address validator) external;
}
