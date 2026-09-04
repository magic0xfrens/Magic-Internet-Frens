import { sepolia } from "viem/chains";
import type { Address } from "viem";

/**
 * Live Cauldron (Magic Internet Frens) deployment — the eternal launchpad.
 * Canonical Sepolia addresses from
 * contracts/solidity/deployments/sepolia-launch.json (v4, audited).
 * gen-1 GnomeLand is LIVE. Per-iteration addresses (token/collection/vault)
 * rotate on relaunch — read them live from the registry, don't pin.
 */
export const CAULDRON = {
  chainId: sepolia.id,
  // round-17 (CANONICAL): reserve-LP migration + 30% genesis bonus + presale
  // cancel/refund + batch genesis claim. 100% of supply lives in two V4 positions
  // (active 10% + out-of-range reserve 90%) → no whale FUD; claims release 1:1
  // from the reserve. Each fren reclaims 30% of mint value (B/A=0.30). Live at the
  // real 0.0222 mint price (24.66 ETH raised → FDV ~246 ETH). gen-1 GNOME LIVE.
  registry: "0x65Dd9Ba0eB1dA5C7CBcDA01d3d9218e804C7a54c" as Address,
  hook: "0x82FC4A9da3B9953b6BCF67Fb29F644C59d4bd0CC" as Address,
  gachaRouter: "0x0165F9A190B216bD410b6f8Ea538A7168DE90147" as Address,
  dividend: "0x96Bd816C9A5089b453BF7C56fBA716D4a6Cc32A2" as Address,
  governor: "0xf9730985C55D3deB26f070b45A65CD96F0E36D0E" as Address,
  mifrens: "0x4D180c050978F0037d030BaC455c3cfA70aAA8e1" as Address, // MiFrensGenesis (collection)
  poolManager: "0xE03A1074c86CFeDd5C142C4F04F1a1536e203543" as Address, // V4 (Sepolia)
  genesisSupply: 1111,
  deathThresholdEth: 0.05, // matches DEATH_THRESHOLD env on this deploy
  deployBlock: 11581000n, // round-14 launchpad deploy block — bound getLogs
};

/**
 * Cauldron price indexer (Ponder). Serves OHLC candles + volume per generation
 * at /candles/:gen. When unset/unreachable the chart falls back to on-chain
 * getLogs. Set VITE_CAULDRON_INDEXER to your deployed indexer URL.
 */
export const CAULDRON_INDEXER: string =
  (import.meta.env?.VITE_CAULDRON_INDEXER as string) || "";

/** MiFrensDividend — genesis holders claim a share of every iteration's fees. */
export const DIVIDEND_ABI = [
  { type: "function", name: "SHARES", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "pending", stateMutability: "view", inputs: [{ name: "tokenId", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "totalDeposited", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "totalClaimed", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "claim", stateMutability: "nonpayable", inputs: [{ name: "tokenId", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "claimMany", stateMutability: "nonpayable", inputs: [{ name: "tokenIds", type: "uint256[]" }], outputs: [{ type: "uint256" }] },
  // "cast the spell" — a genesis fren only earns once enchanted; transfer breaks it.
  { type: "function", name: "castSpell", stateMutability: "nonpayable", inputs: [{ name: "tokenId", type: "uint256" }], outputs: [] },
  { type: "function", name: "castMany", stateMutability: "nonpayable", inputs: [{ name: "tokenIds", type: "uint256[]" }], outputs: [] },
  { type: "function", name: "isEnchanted", stateMutability: "view", inputs: [{ name: "tokenId", type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "activeShares", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "owed", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "withdrawOwed", stateMutability: "nonpayable", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

/** CauldronRegistry — the eternal machine's lifecycle state (read-only surface). */
export const REGISTRY_ABI = [
  { type: "function", name: "currentGeneration", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "currentToken", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "generationToken", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] },
  { type: "function", name: "generationCollection", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] },
  { type: "function", name: "generationVault", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] },
  { type: "function", name: "generationPoolId", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "generationPositionId", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "relaunch", stateMutability: "nonpayable", inputs: [], outputs: [{ type: "address" }, { type: "bytes32" }] },
  { type: "function", name: "claimByBurn", stateMutability: "nonpayable", inputs: [{ type: "uint256" }, { type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "claimGenesis", stateMutability: "nonpayable", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  // Batch claim — one reserve removal for many frens (a 20-fren holder pays 1 tx).
  { type: "function", name: "claimGenesisMany", stateMutability: "nonpayable", inputs: [{ type: "uint256[]" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "genesisSharePerFren", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "genesisClaimed", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "summoned", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "lastSummonAt", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "minLifetime", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

/** V4 PoolManager extsload (read packed slot0 → current sqrtPriceX96). */
export const POOLMANAGER_ABI = [
  { type: "function", name: "extsload", stateMutability: "view", inputs: [{ type: "bytes32" }], outputs: [{ type: "bytes32" }] },
] as const;

/** V4 PositionManager — the LP position's liquidity. */
export const POSITION_MANAGER = "0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4" as Address;
export const POSITION_MANAGER_ABI = [
  { type: "function", name: "getPositionLiquidity", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint128" }] },
] as const;

/** CauldronHook — volume telemetry + death detection + the crystal gacha. */
export const HOOK_ABI = [
  { type: "function", name: "getVolume24h", stateMutability: "view", inputs: [{ name: "id", type: "bytes32" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "isDead", stateMutability: "view", inputs: [{ name: "id", type: "bytes32" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "deathThreshold", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "cumulativeVolume", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "relaunchETH", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "creditOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "crystalsReady", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "opened", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  // ── crystal gacha game reads ──
  { type: "function", name: "pendingOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "committedOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "missStreak", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "pityThreshold", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "oddsForPlay", stateMutability: "view", inputs: [{ name: "playWei", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "costOfNextCrystals", stateMutability: "view", inputs: [{ name: "count", type: "uint256" }], outputs: [{ type: "uint256" }] },
  // Mana progress toward the next crystal: (banked toward next, its price, whole ready).
  { type: "function", name: "progress", stateMutability: "view", inputs: [{ type: "address" }], outputs: [
    { name: "inCurrent", type: "uint256" }, { name: "threshold", type: "uint256" }, { name: "ready", type: "uint256" },
  ] },
  // A resolved crystal that WON → a sealed creature NFT was minted to `player`.
  { type: "event", name: "TicketWon", inputs: [
    { name: "player", type: "address", indexed: true },
    { name: "ticketId", type: "uint256", indexed: true },
    { name: "tokenId", type: "uint256", indexed: false },
  ] },
] as const;

/** CauldronGovernor — proposals + votes (for the governance panel). */
export const GOVERNOR_ABI = [
  { type: "function", name: "proposalCount", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "hasProposals", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  {
    type: "function", name: "getProposal", stateMutability: "view",
    inputs: [{ type: "uint256" }],
    outputs: [{
      type: "tuple",
      components: [
        { name: "name", type: "string" }, { name: "symbol", type: "string" },
        { name: "mode", type: "uint8" }, { name: "baseURI", type: "string" },
        { name: "renderer", type: "address" }, { name: "website", type: "string" },
        { name: "socials", type: "string" }, { name: "nftSupply", type: "uint256" },
        { name: "volumePerNFT", type: "uint256" },
        { name: "proposer", type: "address" }, { name: "votes", type: "uint256" },
        { name: "snapshot", type: "uint256" }, { name: "consumed", type: "bool" },
        { name: "exists", type: "bool" },
      ],
    }],
  },
  { type: "function", name: "vote", stateMutability: "nonpayable", inputs: [{ type: "uint256" }], outputs: [] },
  { type: "function", name: "hasVoted", stateMutability: "view", inputs: [{ type: "uint256" }, { type: "address" }], outputs: [{ type: "bool" }] },
  {
    type: "function", name: "propose", stateMutability: "nonpayable",
    inputs: [
      { name: "name", type: "string" }, { name: "symbol", type: "string" },
      { name: "mode", type: "uint8" }, { name: "baseURI", type: "string" },
      { name: "renderer", type: "address" }, { name: "website", type: "string" },
      { name: "socials", type: "string" }, { name: "nftSupply", type: "uint256" },
      { name: "volumePerNFT", type: "uint256" },
    ],
    outputs: [{ type: "uint256" }],
  },
] as const;

/** MiFrens NFT balanceOf — gate proposing to holders. */
export const MIFRENS_ERC721_ABI = [
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
] as const;

/** ERC20 read/approve — for selling the iteration token back through the router. */
export const ERC20_SWAP_ABI = [
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ type: "address" }, { type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "bool" }] },
] as const;

/** Per-brew collection (volume-minted NFTs). */
export const COLLECTION_ABI = [
  { type: "function", name: "totalMinted", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "maxSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "name", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  // Sealed-crystal reveal (mystery-box): owner opens a crystal → creature art.
  { type: "function", name: "reveal", stateMutability: "nonpayable", inputs: [{ name: "tokenId", type: "uint256" }], outputs: [] },
  { type: "function", name: "revealed", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "rarityOf", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint8" }] },
  { type: "function", name: "ownerOf", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] },
  { type: "function", name: "tokenURI", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "string" }] },
  { type: "function", name: "vault", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
] as const;

/** CauldronVault — burn an NFT to claim its equal share of the floor (ETH). */
export const VAULT_ABI = [
  { type: "function", name: "floorPerNFT", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "closed", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "redeem", stateMutability: "nonpayable", inputs: [{ name: "tokenId", type: "uint256" }], outputs: [{ type: "uint256" }] },
] as const;

/** ERC20 (the current creature token). */
export const TOKEN_ABI = [
  { type: "function", name: "name", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "totalSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "dead", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "isAlive", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
] as const;

/** CauldronGachaRouter — one-click buy. `play` with ETH value + gnomeIn=0 is a
 *  clean ETH→token buy (delivers the token to you) that also credits volume and
 *  rolls the crystal gacha (a chance to forge a creature NFT). */
export const GACHA_ROUTER_ABI = [
  {
    type: "function", name: "play", stateMutability: "payable",
    inputs: [
      { name: "gnomeIn", type: "uint256" },
      { name: "minGnomeOut", type: "uint256" },
      { name: "minEthOut", type: "uint256" },
      { name: "openMax", type: "uint256" },
    ],
    outputs: [{ name: "opened", type: "uint256" }],
  },
  // Open crystals from ALREADY-earned credit (no fresh buy needed).
  {
    type: "function", name: "openReady", stateMutability: "nonpayable",
    inputs: [{ name: "maxCount", type: "uint256" }],
    outputs: [{ name: "opened", type: "uint256" }],
  },
  // SPIN volume: Buy→Sell→Buy churn loops (each leg credited as Mana). More
  // loops = more volume from the same ETH = more chances to summon a crystal.
  {
    type: "function", name: "playChurn", stateMutability: "payable",
    inputs: [{ name: "loops", type: "uint256" }, { name: "openMax", type: "uint256" }],
    outputs: [{ name: "opened", type: "uint256" }],
  },
] as const;

/** V4 PoolManager Swap event — the source of the live price/volume chart. */
export const SWAP_EVENT =
  "event Swap(bytes32 indexed id, address indexed sender, int128 amount0, int128 amount1, uint160 sqrtPriceX96, uint128 liquidity, int24 tick, uint24 fee)" as const;
