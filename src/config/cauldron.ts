import type { Address } from "viem";
import { ACTIVE_CHAIN_ID } from "@/config/chains";
// ── SINGLE SOURCE OF TRUTH ──────────────────────────────────────────────────
// The live deployment's addresses/blocks come from ONE manifest shared with the
// indexer: indexer/deployments/round.json. It physically lives in indexer/ because
// `railway up` only uploads that dir; the frontend reaches into it so both sides
// can NEVER drift (that drift served r29 data as r31). To ship a round: edit that
// file + run scripts/deploy-round.mjs. Per-iteration token/collection/vault rotate
// on relaunch — read those live from the registry, don't pin them here.
//  ONE MANIFEST PER CHAIN, picked by the user's selection. `ACTIVE_ROUND` is
//  `round.json` for Sepolia and `round.arc.json` for Arc — see
//  src/config/deployments.ts for why switching reloads rather than re-rendering.
import { ACTIVE_ROUND as round } from "./deployments";

//  ── THE MANIFEST AND THE SELECTED CHAIN MUST AGREE ──────────────────────────
//  Both now derive from `SELECTED_CHAIN_ID`, so this should be unreachable. It
//  stays as an assertion precisely BECAUSE it should be: the failure it catches
//  is a UI talking to one chain using another chain's addresses, which hold no
//  code there — so reads come back empty and the app renders a plausible
//  "nothing has happened yet" rather than an error. Silent and expensive to
//  diagnose, trivial to detect.
//
//  FATAL, not logged. This used to be a `console.error` and "loud but
//  non-fatal" — which in practice meant a user on the wrong chain saw an empty
//  but plausible UI, clicked Buy, and had their wallet force-switched to
//  `CAULDRON.chainId` before signing calldata addressed to the OTHER chain.
//  A blank page with this message in the console is strictly better than a
//  value-bearing signature aimed at a chain the addresses do not live on.
if (round.chainId !== ACTIVE_CHAIN_ID) {
  throw new Error(
    `[cauldron] MANIFEST/CHAIN MISMATCH — the app is on chain ${ACTIVE_CHAIN_ID}, but the ` +
      `selected manifest pins chain ${round.chainId}. Every address below belongs to ` +
      `${round.chainId} and has no code on ${ACTIVE_CHAIN_ID}: reads will come back empty ` +
      `rather than failing. Check DEPLOYMENTS in src/config/deployments.ts.`,
  );
}

export const CAULDRON = {
  chainId: ACTIVE_CHAIN_ID,
  registry: round.contracts.registry as Address,
  hook: round.contracts.hook as Address,
  gachaRouter: round.contracts.gachaRouter as Address,
  dividend: round.contracts.dividend as Address,
  governor: round.contracts.governor as Address,
  mifrens: round.contracts.presale as Address, // MiFrensGenesis (presale/collection)
  // Treasury rotation. Optional: a deployment predating the rotator omits it,
  // and the UI hides the panel rather than rendering a dead button.
  quoteRotator: (round.contracts as Record<string, string>).quoteRotator as Address | undefined,
  //  NativeQuoteZap — lets a buyer pay in ether on a generation that has rotated
  //  into an ERC20 quote. Optional: rounds deployed before it simply have none,
  //  and the UI falls back to asking for the quote directly.
  nativeZap: ((round.contracts as Record<string, string>).nativeZap || undefined) as Address | undefined,
  // `CauldronBase.treasuryGovernor` is `internal` (:345) and the registry has 62
  // bytes of EIP-170 margin, so it cannot be given a getter — the manifest is
  // the handle, same as every other contract here.
  treasuryGovernor: ((round.contracts as Record<string, string>).treasuryGovernor || undefined) as Address | undefined,
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

/**
 * The hook's trading fee, in bps — skimmed off the ETH side of EVERY swap
 * (`CauldronHook._takeEthFee`) and routed to the floor vault / genesis dividend /
 * relaunch reserve.
 *
 *  ── WHY A CONSTANT AND NOT A READ ─────────────────────────────────────────
 *  `CauldronHook.defaultTaxBps` and `nftContract` are both `internal` (:234,
 *  :237) and the hook is against the EIP-170 ceiling, so there is no getter to
 *  read and no room to add one. 300 is the deployed value.
 *
 *  ── WHY ANY QUOTE MUST SUBTRACT IT ────────────────────────────────────────
 *  The swap widget used to estimate output as `ethIn / spotPrice` — pure mid
 *  price. On a buy the hook consumes this fee off the input in `beforeSwap`, so
 *  only (1 - fee) of the ETH ever reaches the pool; the estimate was ~3% high
 *  before price impact even entered. `minOut` derived from it therefore sat
 *  ABOVE anything the pool could deliver, and the router's own `Slippage()`
 *  guard (CauldronGachaRouter.sol:429) reverted every buy at the 0.5% and 1%
 *  presets — measured on Sepolia r40: 0.05 ETH quoted 49.55M $GNOME, filled
 *  47.61M, a 3.9% gap from fee + 1.9 ticks of impact.
 *
 *  NOT included here: the decaying anti-sniper surtax (`snipeSurtaxBps`), which
 *  is zero outside a fresh pool's launch window and can reach ~99% inside it.
 *  A trade in that window is meant to be punitive; the slippage tolerance is the
 *  only thing standing between the trader and it, by design.
 */
export const TRADE_FEE_BPS = 300;

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
  //  ── THE ERC20 BASKET (audit FG-1) ────────────────────────────────────
  //  A generation whose quote is not ether pays the ENTIRE guild slice through
  //  `fundToken`, so on a rotated generation this rail is 100% of the dividend.
  //  Declaring only the ether rail made the panel render a flat 0 with no claim
  //  button while the money accrued on-chain.
  { type: "function", name: "assetCount", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "assets", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] },
  { type: "function", name: "knownAsset", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "accountedOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "pendingToken", stateMutability: "view", inputs: [{ name: "tokenId", type: "uint256" }, { name: "asset", type: "address" }], outputs: [{ type: "uint256" }] },
  //  Claims EVERY basket asset for one tokenId — there is no `claimTokensMany`,
  //  so the hook signs one per owned fren.
  { type: "function", name: "claimTokens", stateMutability: "nonpayable", inputs: [{ name: "tokenId", type: "uint256" }], outputs: [] },
  { type: "function", name: "owedAsset", stateMutability: "view", inputs: [{ type: "address" }, { type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "withdrawOwedToken", stateMutability: "nonpayable", inputs: [{ name: "asset", type: "address" }], outputs: [{ name: "amount", type: "uint256" }] },
  //  Permissionless once the asset is known: books a balance that arrived by a
  //  bare transfer (e.g. a RoyaltyRouter sweep) into the per-share accumulator.
  { type: "function", name: "adopt", stateMutability: "nonpayable", inputs: [{ name: "asset", type: "address" }], outputs: [{ name: "delta", type: "uint256" }] },
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
  { type: "function", name: "genesisReserveOutstanding", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "genesisShares", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  // Protection circuit-breaker: redemption is paused. Included so viem decodes the
  // revert to a friendly name.
  { type: "error", name: "RedemptionPaused", inputs: [] },
  // COLLECTION LEGACY FLOOR (r28): recycle a dead collection's NFT for its live-token
  // floor (NFT → treasury), or buy a treasury-held one for 2× floor (grows the floor).
  { type: "function", name: "recycleCollectionNFT", stateMutability: "nonpayable", inputs: [{ type: "uint256" }, { type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "buyCollectionNFT", stateMutability: "nonpayable", inputs: [{ type: "uint256" }, { type: "uint256" }], outputs: [{ type: "uint256" }] },
  // Quote asset per generation + the treasury-curated allowlist (0 = native ETH).
  { type: "function", name: "generationQuote", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] },
  { type: "function", name: "allowedQuote", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "bool" }] },
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
  //  ── ERRORS ───────────────────────────────────────────────────────────
  //  The PRE-TRADE liquidation sweep (CauldronHook.sol:835) reverts this when
  //  the swap did not supply enough gas to fund the sweep AND the perp book is
  //  non-empty — skipping it would leave realized bad debt on PLV stakers. It
  //  needs ~1.05M gas; every path in this app pins 8,000,000, so only a wallet
  //  or aggregator that CAPS gas can trip it. Declared here so viem decodes it
  //  by name instead of handing the user a raw selector; the human text is
  //  PERP_ERROR_HELP.LiqGasStarved (src/config/perp.ts).
  { type: "error", name: "LiqGasStarved", inputs: [] },
] as const;

/** CollectionLedger — the per-collection legacy-floor cap table (r28). Each past
 *  volume collection keeps a token entitlement, redeemable from the shared reserve,
 *  that moons with the machine. floorPerNFT rises via 2× buybacks + live buyback. */
//  RE-SYNCED against contracts/solidity/out. `floorPerNFT(uint256)` and
//  `outstanding(uint256)` were removed: the ledger implements the TWO-argument
//  forms (`floorPerNFT(uint256,uint256)` = 0x269f17ef,
//  `outstanding(uint256,uint256)` = 0x7a605f78) and nothing called the one-arg
//  shapes. A declared selector nothing implements is how the perp opens stayed
//  broken for a whole release.
export const LEDGER_ABI = [
  { type: "function", name: "entitledTokens", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "crystallized", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "bool" }] },
  // Live-buyback accumulator for the CURRENT collection (folds into its floor at death).
  { type: "function", name: "pending", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "totalEntitled", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

/** Hook reads for the live buyback progress bar. */
export const HOOK_LEGACY_ABI = [
  { type: "function", name: "legacyBuffer", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

/** CauldronGovernor — proposals + votes (for the governance panel). */
export const GOVERNOR_ABI = [
  { type: "function", name: "proposalCount", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "hasProposals", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  {
    type: "function", name: "getProposal", stateMutability: "view",
    inputs: [{ type: "uint256" }],
    //  ── THIS TUPLE MUST MATCH THE STRUCT EXACTLY, FIELD FOR FIELD ──────────
    //  viem decodes a tuple POSITIONALLY against whatever components are
    //  declared here, so a missing field does not error — it silently shifts
    //  every field after it and returns confident nonsense. This list was short
    //  by two (`quote` and `votingEndsAt`) and, measured against the live r43
    //  governor, that made `getProposal(1)` decode as nftSupply 0 (really 3333),
    //  proposer 0x0 (really 0xC944...) and votes 1.149e48 (really 1111). The
    //  proposal cards were rendering that. `loadProposals` wraps the read in
    //  `.catch(() => null)`, so there was nothing in the console either.
    //
    //  If you add a field to `Proposal` in CauldronGovernor.sol, add it here in
    //  the same position, and check it against:
    //    forge inspect CauldronGovernor abi | jq '.[]|select(.name=="getProposal")'
    outputs: [{
      type: "tuple",
      components: [
        { name: "name", type: "string" }, { name: "symbol", type: "string" },
        { name: "mode", type: "uint8" }, { name: "baseURI", type: "string" },
        { name: "renderer", type: "address" }, { name: "website", type: "string" },
        { name: "socials", type: "string" },
        { name: "logo", type: "string" }, { name: "banner", type: "string" },
        { name: "quote", type: "address" },
        { name: "nftSupply", type: "uint256" },
        { name: "volumePerNFT", type: "uint256" },
        { name: "proposer", type: "address" }, { name: "votes", type: "uint256" },
        { name: "snapshot", type: "uint256" }, { name: "votingEndsAt", type: "uint256" },
        { name: "consumed", type: "bool" },
        { name: "exists", type: "bool" },
      ],
    }],
  },
  { type: "function", name: "vote", stateMutability: "nonpayable", inputs: [{ type: "uint256" }], outputs: [] },
  { type: "function", name: "hasVoted", stateMutability: "view", inputs: [{ type: "uint256" }, { type: "address" }], outputs: [{ type: "bool" }] },
  {
    // The PRE-QUOTE signature, kept as an OVERLOAD so the app still works
    // against a governor deployed before the quote work. viem picks between the
    // two by argument count; useCauldronMachine decides which to send from a
    // capability probe against the live registry.
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
  {
    type: "function", name: "propose", stateMutability: "nonpayable",
    inputs: [
      { name: "name", type: "string" }, { name: "symbol", type: "string" },
      { name: "mode", type: "uint8" }, { name: "baseURI", type: "string" },
      { name: "renderer", type: "address" }, { name: "website", type: "string" },
      { name: "socials", type: "string" }, { name: "nftSupply", type: "uint256" },
      { name: "volumePerNFT", type: "uint256" },
      // The asset this brew's token is PRICED IN (0 = native ETH). Validated
      // against the registry's allowlist on-chain, at propose AND at relaunch.
      { name: "quote", type: "address" },
    ],
    outputs: [{ type: "uint256" }],
  },
  {
    // WITH BREW ART. Third overload; viem still picks by argument count. `logo`
    // and `banner` are display-only — they are stored on the proposal and never
    // reach `BrewSpec`, so they cannot change what `relaunch()` constructs.
    type: "function", name: "propose", stateMutability: "nonpayable",
    inputs: [
      { name: "name", type: "string" }, { name: "symbol", type: "string" },
      { name: "mode", type: "uint8" }, { name: "baseURI", type: "string" },
      { name: "renderer", type: "address" }, { name: "website", type: "string" },
      { name: "socials", type: "string" },
      { name: "logo", type: "string" }, { name: "banner", type: "string" },
      { name: "nftSupply", type: "uint256" },
      { name: "volumePerNFT", type: "uint256" },
      { name: "quote", type: "address" },
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
  //  Labelling an asset from the chain rather than a hardcoded table: the
  //  dividend basket can grow by governance `adopt` at any time (audit FG-1).
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "decimals", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
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
  // Reveal many in ONE transaction. Revealing was per-token, so a wallet with
  // thirty crystals paid thirty base fees to see what it already owned.
  { type: "function", name: "revealBatch", stateMutability: "nonpayable", inputs: [{ name: "tokenIds", type: "uint256[]" }], outputs: [] },
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
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
] as const;

/** CauldronGachaRouter — one-click buy. `play` with the generation's QUOTE +
 *  tokenIn=0 is a clean quote→token buy (delivers the token to you) that also
 *  credits volume and rolls the crystal gacha (a chance to forge a creature NFT).
 *
 *  ── `quoteIn` (functional audit R-05) ──────────────────────────────────────
 *  The router no longer assumes every generation trades native ETH — a
 *  generation can launch on a non-ETH quote, or rotate into one mid-life. The
 *  buy side is supplied one of two ways, and the contract rejects the wrong one
 *  rather than stranding it:
 *
 *    • native generation  → send `value`, pass `quoteIn: 0n`
 *    • ERC20 quote (USDG) → send NO value, approve the router, pass `quoteIn`
 *
 *  Read the live quote from `registry.generationQuote(currentGeneration)` to
 *  decide which. `address(0)` means native. */
export const GACHA_ROUTER_ABI = [
  {
    type: "function", name: "play", stateMutability: "payable",
    inputs: [
      { name: "quoteIn", type: "uint256" },
      { name: "tokenIn", type: "uint256" },
      { name: "minTokenOut", type: "uint256" },
      { name: "minQuoteOut", type: "uint256" },
      { name: "openMax", type: "uint256" },
    ],
    outputs: [{ name: "opened", type: "uint256" }],
  },
  // Same as play, but tags the swap with perp `liqHints` — any of those
  // positions that is underwater at the mark is auto-liquidated inside the swap,
  // minting the swapper a Liquidatoor badge each. Stale/healthy hints are silent
  // no-ops. NOTE: this is an ARRAY (`uint256[]`); the previous entry here
  // declared a bare `uint256`, which is why `useCauldronSwap` avoided it.
  {
    type: "function", name: "playLiq", stateMutability: "payable",
    inputs: [
      { name: "quoteIn", type: "uint256" },
      { name: "tokenIn", type: "uint256" },
      { name: "minTokenOut", type: "uint256" },
      { name: "minQuoteOut", type: "uint256" },
      { name: "openMax", type: "uint256" },
      { name: "liqHints", type: "uint256[]" },
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
  // loops = more volume from the same spend = more chances to summon a crystal.
  {
    type: "function", name: "playChurn", stateMutability: "payable",
    inputs: [
      { name: "quoteIn", type: "uint256" },
      { name: "loops", type: "uint256" },
      //  THE FLOOR (audit K4c). Every churn leg swaps at the extreme tick, so
      //  without this a sandwicher could take essentially the whole stake and
      //  the caller had no parameter to refuse it. Sized on the tokens the final
      //  buy leg leaves you holding, exactly like `play`'s `minTokenOut`.
      { name: "minTokenOut", type: "uint256" },
      { name: "openMax", type: "uint256" },
    ],
    outputs: [{ name: "opened", type: "uint256" }],
  },
  //  ── THE CURVE'S OWN UNITS (audit B-2) ────────────────────────────────
  //  `oddsForPlay` is a function of the play measured in CURVE units, and the
  //  router converts a raw quote notional into them with `_playInCurveUnits`
  //  (CauldronGachaRouter.sol:120,136-145). The UI was passing the raw wei
  //  straight to `oddsForPlay`, which agrees with the chain ONLY while the
  //  router's `oracle()` is 0x0 — a coincidence that dies the moment setOracle
  //  is called, which the USDG path requires. Route the display through this so
  //  it tracks the chain instead of happening to match it.
  { type: "function", name: "playInCurveUnits", stateMutability: "view", inputs: [{ name: "playWei", type: "uint256" }], outputs: [{ type: "uint256" }] },
] as const;

/** V4 PoolManager Swap event — the source of the live price/volume chart. */
export const SWAP_EVENT =
  "event Swap(bytes32 indexed id, address indexed sender, int128 amount0, int128 amount1, uint160 sqrtPriceX96, uint128 liquidity, int24 tick, uint24 fee)" as const;
