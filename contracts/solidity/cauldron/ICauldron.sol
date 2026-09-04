// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice How a brew's NFT collection resolves tokenURI.
enum MetadataMode {
    BaseURI,  // tokenURI = baseURI + tokenId  (off-chain / IPFS)
    Renderer  // tokenURI delegated to an on-chain renderer contract
}

/// @notice On-chain renderer a proposer may point their collection at.
interface ICollectionRenderer {
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

/// @notice The winning proposal the registry consumes on relaunch.
/// @dev The public display name is always `name` + " by Magic Internet Frens"
///      (the suffix is hardcoded on-chain in {LaunchLib.displayName}, never
///      supplied by the proposer).
struct BrewSpec {
    string name;          // token + collection name  ("Gnomeland")
    string symbol;        // ticker                    ("GNOME")
    MetadataMode mode;    // BaseURI or Renderer
    string baseURI;       // used when mode == BaseURI
    address renderer;     // used when mode == Renderer
    string website;       // proposer's site           ("gnomeland.xyz")
    string socials;       // community/X link           ("x.com/…")
    address quote;        // asset the token is PRICED IN (0 = native ETH)
    uint256 nftSupply;    // proposer-chosen NFT collection max supply
    uint256 volumePerNFT; // credit (≈ETH) volume to forge each NFT (0 = hook default)
    address proposer;     // who authored it (paid the relaunch bounty)
}

/// @notice Hardcoded branding shared across every brew the Cauldron summons.
library LaunchLib {
    string internal constant GUILD_SUFFIX = " by Magic Internet Frens";

    /// @return The public display name: "<name> by Magic Internet Frens".
    function displayName(string memory name) internal pure returns (string memory) {
        return string.concat(name, GUILD_SUFFIX);
    }
}

/// @notice Minimal governor surface the registry reads on relaunch.
interface ICauldronGovernor {
    function winner() external view returns (uint256 proposalId, BrewSpec memory spec);
    function markConsumed(uint256 proposalId) external;
    function hasProposals() external view returns (bool);
}

/// @notice Minimal collection surface the volume hook mints through.
interface ICauldronCollection {
    function mint(address to) external returns (uint256 tokenId);
    function totalMinted() external view returns (uint256);
    function maxSupply() external view returns (uint256);
}
