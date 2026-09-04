/** Human-readable ABI (ethers-style signature strings), consumed by the legacy
 *  ethers.Contract hooks. Typed locally so this file doesn't import ethers. */
type InterfaceAbi = string[];

/**
 * ABIs for the EVM (Robinhood Chain) contracts, in ethers human-readable form.
 *
 * The primary on-chain contract is MagicFrensPeg — a combined ERC20 + ERC721
 * bonded token/NFT (buy/sell/commit Frens with on-chain random traits).
 * See contracts/solidity/MagicFrensPeg.sol.
 */
export const MagicFrensPegAbi: InterfaceAbi = [
  // --- Buy / Sell / Commit ---
  "function buyFren() payable",
  "function sellFren()",
  "function commitFren()",
  "function transferCommittedFren(address to, uint256 tokenId)",

  // --- Traits & ownership views ---
  "function getTraits(uint256 tokenId) view returns (uint8 classIdx, uint8 bodyIdx, uint8 faceIdx, uint8 itemIdx)",
  "function traitData(uint256 tokenId) view returns (uint256)",
  "function committed(uint256 tokenId) view returns (bool)",
  "function ownerToTokenId(address owner) view returns (uint256)",
  "function hasFren(address owner) view returns (bool)",
  "function getFrenId(address owner) view returns (uint256)",
  "function treasury() view returns (address)",
  "function tokenURI(uint256 tokenId) view returns (string)",

  // --- Constants ---
  "function MAX_SUPPLY() view returns (uint256)",
  "function COMMIT_FEE() view returns (uint256)",
  "function UNIT_PER_FREN() view returns (uint256)",

  // --- ERC721Enumerable ---
  "function balanceOf(address owner) view returns (uint256)",
  "function ownerOf(uint256 tokenId) view returns (address)",
  "function totalSupply() view returns (uint256)",
  "function tokenByIndex(uint256 index) view returns (uint256)",
  "function tokenOfOwnerByIndex(address owner, uint256 index) view returns (uint256)",
  "function isApprovedForAll(address owner, address operator) view returns (bool)",
  "function setApprovalForAll(address operator, bool approved)",

  // --- ERC20 surface ---
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",

  // --- Events ---
  "event FrenMinted(address indexed owner, uint256 indexed tokenId, uint256 packedTraits)",
  "event FrenBurned(address indexed owner, uint256 indexed tokenId)",
  "event FrenCommitted(address indexed owner, uint256 indexed tokenId)",
  "event FrenTransferred(address indexed from, address indexed to, uint256 indexed tokenId)",
];

/**
 * MagicFrensPresale ABI. See contracts/solidity/MagicFrensPresale.sol.
 */
export const PresaleAbi: InterfaceAbi = [
  "function contribute() payable",
  "function claimTokens()",
  "function getContribution(address contributor) view returns (uint256 amount, uint256 tokens, bool hasClaimed)",
  "function getPresaleStats() view returns (uint256 raised, uint256 sold, uint256 remaining, bool active, bool isPaused)",
  "event Contribution(address indexed contributor, uint256 amount, uint256 tokens)",
];

/**
 * Back-compat aliases for the former Robinhood ABI export names. The old FrenForge /
 * FrenMarket Robinhood contracts have no EVM equivalent yet — the marketplace is a
 * phase-2 item, so FrenMarketAbi is an empty stub.
 */
export const MiFrensAbi: InterfaceAbi = MagicFrensPegAbi;
export const FrenForgeAbi: InterfaceAbi = MagicFrensPegAbi;
export const FrenMarketAbi: InterfaceAbi = [];
