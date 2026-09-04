import type { Address } from "viem";
import { ACTIVE_CHAIN_ID } from "@/config/chains";
// ── SINGLE SOURCE OF TRUTH ──────────────────────────────────────────────────
// The live deployment's addresses/blocks come from ONE manifest shared with the
// indexer: indexer/deployments/round.json. It physically lives in indexer/ because
// `railway up` only uploads that dir; the frontend reaches into it so both sides
// can NEVER drift (that drift served r29 data as r31). To ship a round: edit that
// file + run scripts/deploy-round.mjs. Per-iteration token/collection/vault rotate
// on relaunch — read those live from the registry, don't pin them here.
import round from "../../indexer/deployments/round.json";

export const CAULDRON = {
  chainId: ACTIVE_CHAIN_ID,
  registry: round.contracts.registry as Address,
  hook: round.contracts.hook as Address,
  gachaRouter: round.contracts.gachaRouter as Address,
  dividend: round.contracts.dividend as Address,
  governor: round.contracts.governor as Address,
  mifrens: round.contracts.presale as Address, // MiFrensGenesis (presale/collection)
  timelock: round.contracts.timelock as Address, // owns hook+engine; registry emergencyAdmin
  collectionLedger: round.contracts.collectionLedger as Address, // legacy-floor cap table
  poolManager: round.contracts.poolManager as Address, // V4 (Sepolia)
  genesisSupply: round.genesisSupply,
  deathThresholdEth: round.deathThresholdEth, // 0 post-summon so the fresh pool trades
  deployBlock: BigInt(round.blocks.deploy), // launchpad deploy block — bounds getLogs
};

/**
 * Cauldron indexer (Ponder). Serves OHLC candles, volume, NFTs, floors and perp
 * state — the app's entire read layer.
 */
// Straight from the manifest. There is deliberately NO env override: the URL is
// a public read API rather than a secret, so nothing is gained by moving it to
// hosting config — and plenty is lost. An empty or malformed value made every
// `${INDEXER}/…` fetch resolve to a RELATIVE path, which the SPA rewrite answers
// with index.html (HTTP 200), so JSON.parse failed and ~10 pollers retried
// forever: a melted UI and a large edge-request bill, with no error anywhere
// saying the URL was wrong. Change the manifest to change the indexer.
export const CAULDRON_INDEXER: string = round.indexerUrl.replace(/\/+$/, "");

/** Liquidatoor badges (OnChain Collectibles) mint into this id range on every
 *  collection, kept separate from the art tranche. A tokenId at/above this is a
 *  Liquidatoor trophy, not a creature. Mirrors LIQUIDATOR_ID_BASE on-chain. */
export const LIQUIDATOR_ID_BASE = 1_000_000;
export const isLiquidatoorId = (tokenId: number | bigint) =>
  BigInt(tokenId) >= BigInt(LIQUIDATOR_ID_BASE);

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
  // RECYCLE-REDEMPTION FLOOR (v2): redeem a genesis fren → receive floorPerFren of
  // the LIVE token (from the reserve); the NFT moves to the TREASURY (not burned).
  { type: "function", name: "redeemOgFren", stateMutability: "nonpayable", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  // Buy a treasury-held (recycled) fren for 2× floor → payment grows the reserve.
  { type: "function", name: "buyTreasuryOgFren", stateMutability: "nonpayable", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  // Permissionlessly grow the floor by donating current token into the reserve.
  { type: "function", name: "donateToReserve", stateMutability: "nonpayable", inputs: [{ type: "uint256" }], outputs: [] },
  // DYNAMIC floor: tokens redeemable per fren right now (ratchets up over time).
  { type: "function", name: "floorPerFren", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  // Re-enchant fee for a MOVED fren (= enchantFeeMultBps × floor). OGs are free.
  { type: "function", name: "enchantFee", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "genesisSharePerFren", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "genesisReserveOutstanding", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "genesisShares", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  // Protection circuit-breaker: redemption is paused. Included so viem decodes the
  // revert to a friendly name.
  { type: "error", name: "RedemptionPaused", inputs: [] },
  // COLLECTION LEGACY FLOOR (r28): recycle a dead collection's NFT for its live-token
  // floor (NFT → treasury), or buy a treasury-held one for 2× floor (grows the floor).
  { type: "function", name: "recycleCollectionNFT", stateMutability: "nonpayable", inputs: [{ type: "uint256" }, { type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "buyCollectionNFT", stateMutability: "nonpayable", inputs: [{ type: "uint256" }, { type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "collectionLedger", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "generationToken", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] },
  { type: "function", name: "summoned", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "lastSummonAt", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "minLifetime", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

/** V4 PoolManager extsload (read packed slot0 → current sqrtPriceX96). */
export const POOLMANAGER_ABI = [
  { type: "function", name: "extsload", stateMutability: "view", inputs: [{ type: "bytes32" }], outputs: [{ type: "bytes32" }] },
] as const;

/** V4 PositionManager — the LP position's liquidity. */
export const POSITION_MANAGER = round.contracts.positionManager as Address;
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
  // Crystals FORGED this spin (committed; resolve on a later spin — commit-reveal).
  { type: "event", name: "CrystalsCommitted", inputs: [
    { name: "player", type: "address", indexed: true },
    { name: "count", type: "uint256", indexed: false },
    { name: "oddsBps", type: "uint256", indexed: false },
  ] },
  // A resolved crystal that LOST (built the pity counter).
  { type: "event", name: "TicketLost", inputs: [
    { name: "player", type: "address", indexed: true },
    { name: "ticketId", type: "uint256", indexed: true },
  ] },
] as const;

/** CollectionLedger — the per-collection legacy-floor cap table (r28). Each past
 *  volume collection keeps a token entitlement, redeemable from the shared reserve,
 *  that moons with the machine. floorPerNFT rises via 2× buybacks + live buyback. */
export const LEDGER_ABI = [
  { type: "function", name: "floorPerNFT", stateMutability: "view", inputs: [{ name: "gen", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "entitledTokens", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "outstanding", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "crystallized", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "bool" }] },
  // Live-buyback accumulator for the CURRENT collection (folds into its floor at death).
  { type: "function", name: "pending", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "totalEntitled", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

/** Hook reads for the live buyback progress bar. */
export const HOOK_LEGACY_ABI = [
  { type: "function", name: "legacyBuffer", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "legacyThreshold", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "legacyBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
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

/** MiFrens NFT reads — holder gating + recycle-floor UI (grandfather + treasury). */
export const MIFRENS_ERC721_ABI = [
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "ownerOf", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] },
  // everMoved: false = original OG (free enchant), true = moved (paid re-enchant).
  { type: "function", name: "everMoved", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "bool" }] },
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
  // Liquidatoor badges (OnChain Collectibles). Struck when a fren is responsible
  // for a perp liquidation; live in the LIQUIDATOR_ID_BASE id range, uncapped.
  { type: "function", name: "isLiquidatoor", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "liquidatorMinted", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "LIQUIDATOR_ID_BASE", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "event", name: "LiquidatoorMinted", inputs: [
    { name: "to", type: "address", indexed: true },
    { name: "tokenId", type: "uint256", indexed: true },
  ] },
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

/** CauldronGachaRouter — one-click buy. `play` with ETH value + tokenIn=0 is a
 *  clean ETH→token buy (delivers the token to you) that also credits volume and
 *  rolls the crystal gacha (a chance to forge a creature NFT). */
export const GACHA_ROUTER_ABI = [
  {
    type: "function", name: "play", stateMutability: "payable",
    inputs: [
      { name: "tokenIn", type: "uint256" },
      { name: "minTokenOut", type: "uint256" },
      { name: "minEthOut", type: "uint256" },
      { name: "openMax", type: "uint256" },
    ],
    outputs: [{ name: "opened", type: "uint256" }],
  },
  // Same as play, but tags the swap with a perp `liqHint` — if that position is
  // underwater at the mark, the swap auto-liquidates it and mints the swapper a
  // Liquidatoor badge. A stale/healthy hint is a silent no-op.
  {
    type: "function", name: "playLiq", stateMutability: "payable",
    inputs: [
      { name: "tokenIn", type: "uint256" },
      { name: "minTokenOut", type: "uint256" },
      { name: "minEthOut", type: "uint256" },
      { name: "openMax", type: "uint256" },
      { name: "liqHint", type: "uint256" },
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
