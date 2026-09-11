import type { Address } from "viem";
import { ACTIVE_CHAIN_ID } from "@/config/chains";
// SINGLE SOURCE OF TRUTH — same manifest as the indexer (see cauldron.ts). The
// VITE_PERP_* env vars remain only as a LOCAL-DEV escape hatch; production reads
// the manifest so the frontend + indexer can never point at different engines.
import round from "../../indexer/deployments/round.json";

/**
 * PerpEngine — hook-native leveraged longs/shorts on the current Cauldron token.
 * Addresses come from the shared round manifest; the zero-address default keeps
 * the UI in a graceful "activates on deploy" state if unset.
 */
export const PERP = {
  chainId: ACTIVE_CHAIN_ID,
  // Straight from the manifest, with no env override. These are deployment
  // identity, and an env var that disagrees points the UI at a different engine
  // than the one the indexer reports on — which surfaces as empty panels rather
  // than an error. Change the manifest to change the deployment.
  engine: round.contracts.perpEngine as Address,
  // Engine deploy block — bounds getLogs so position discovery stays a couple of
  // RPC calls (not a 200k-block scan that trips public-RPC rate limits).
  startBlock: BigInt(round.blocks.perp),
  // The Community PLV vault (LP-for-perps): stake ETH/token, earn perp fees.
  vault: round.contracts.perpVault as Address,
};

/**
 * Slippage the UI signs on a perp open or close, in bps.
 *
 * Every one of these was 0 — `minTokenOut`/`minEthOut` on an open and `minOut`
 * on a close — which tells the engine "fill me at any price at all". `close`
 * really is reachable today, so real closes really did sign a zero floor.
 */
export const PERP_SLIPPAGE_BPS = 100; // 1%

export const PERP_LIVE = PERP.engine.toLowerCase() !== "0x0000000000000000000000000000000000000000";

/** Minimal ABI — reads + the trader actions the UI needs. */
export const PERP_ABI = [
  //  ── actions ──
  //  THE FOUR-ARGUMENT OPENS ARE THE ONLY ONES THAT EXIST.
  //  `forge inspect PerpEngine methodIdentifiers` lists exactly two openers:
  //      openLong(uint8,uint256,uint256,uint256)  = 0x79588b97
  //      openShort(uint8,uint256,uint256,uint256) = 0x9e4a4754
  //  and PerpEngine has no `fallback()` (only `receive()`), so an unknown
  //  selector reverts. This ABI previously declared 2- and 3-argument shapes,
  //  which encoded 0x1cff5d47 / 0x95dd8fe9 — selectors the engine does not
  //  implement. EVERY perp open reverted.
  //
  //  The 4th argument is the COLLATERAL AMOUNT (`PerpEngine.sol:792`,
  //  `_pullQuote(msg.sender, amount)`): on a native book it must equal the ETH
  //  sent with the call. `liqHint` names a position to liquidate on open — if
  //  it is underwater at the mark your open rekts it and mints you a Liquidatoor
  //  badge; a stale/healthy/zero hint is a silent no-op.
  { type: "function", name: "openLong", stateMutability: "payable", inputs: [{ name: "leverage", type: "uint8" }, { name: "minTokenOut", type: "uint256" }, { name: "liqHint", type: "uint256" }, { name: "amount", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "openShort", stateMutability: "payable", inputs: [{ name: "leverage", type: "uint8" }, { name: "minEthOut", type: "uint256" }, { name: "liqHint", type: "uint256" }, { name: "amount", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "close", stateMutability: "nonpayable", inputs: [{ name: "id", type: "uint256" }, { name: "minOut", type: "uint256" }], outputs: [] },
  { type: "function", name: "liquidate", stateMutability: "nonpayable", inputs: [{ name: "id", type: "uint256" }], outputs: [] },
  { type: "function", name: "forceCloseDead", stateMutability: "nonpayable", inputs: [{ name: "id", type: "uint256" }], outputs: [] },
  { type: "function", name: "poke", stateMutability: "nonpayable", inputs: [], outputs: [] },
  // Hybrid Liquidatoor badge: usually auto-minted in-swap; when a swap was too
  // gas-tight it credits `badgesOwed`, claimed later via `claimLiquidatorBadges`.
  { type: "function", name: "badgesOwed", stateMutability: "view", inputs: [{ name: "who", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "claimLiquidatorBadges", stateMutability: "nonpayable", inputs: [{ name: "n", type: "uint256" }], outputs: [] },
  // event: a Liquidatoor badge was awarded to `to` for liquidating position `id`
  // (badgeId 0 = the collection wasn't wired for badges). Parsed from a trade's
  // receipt to pop the "Congrats Liquidatoor!" modal.
  { type: "event", name: "LiquidatoorAwarded", inputs: [
    { name: "id", type: "uint256", indexed: true },
    { name: "to", type: "address", indexed: true },
    { name: "badgeId", type: "uint256", indexed: false },
  ] },
  //  reads — RE-SYNCED against contracts/solidity/out. `openFeeBps()`,
  //  `ogDiscountBps()` and `stats()` were declared here but exist on no compiled
  //  contract; nothing called them (every stat comes from Ponder), so they were
  //  dead selectors waiting to be wired up by someone who trusted the ABI.
  // reads
  { type: "function", name: "maxLeverage", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  { type: "function", name: "activeEthDepth", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "warmup", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "plv", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "plvToken", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  {
    type: "function", name: "positions", stateMutability: "view", inputs: [{ type: "uint256" }],
    outputs: [
      { name: "trader", type: "address" }, { name: "isLong", type: "bool" },
      { name: "collateral", type: "uint128" }, { name: "size", type: "uint256" },
      { name: "principal", type: "uint256" }, { name: "openedAt", type: "uint64" },
      { name: "leverage", type: "uint8" }, { name: "entryFunding", type: "int256" },
    ],
  },
  {
    type: "function", name: "positionHealth", stateMutability: "view", inputs: [{ type: "uint256" }],
    outputs: [
      { name: "isLong", type: "bool" }, { name: "markValueEth", type: "uint256" },
      { name: "debtOrBackingEth", type: "uint256" }, { name: "liquidatable", type: "bool" },
    ],
  },
  { type: "function", name: "isLiquidatable", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "bool" }] },
  // events (position discovery)
  { type: "event", name: "Opened", inputs: [
    { name: "id", type: "uint256", indexed: true }, { name: "trader", type: "address", indexed: true },
    { name: "isLong", type: "bool", indexed: false }, { name: "collateral", type: "uint256", indexed: false },
    { name: "size", type: "uint256", indexed: false }, { name: "leverage", type: "uint8", indexed: false },
  ] },
  // custom errors → so viem decodes reverts to a name the UI can explain.
  { type: "error", name: "NotWarm", inputs: [] },
  { type: "error", name: "BadLeverage", inputs: [] },
  { type: "error", name: "PlvInsufficient", inputs: [] },
  { type: "error", name: "OiCapped", inputs: [] },
  { type: "error", name: "NotTrader", inputs: [] },
  { type: "error", name: "NotOpen", inputs: [] },
  { type: "error", name: "Healthy", inputs: [] },
  { type: "error", name: "Slippage", inputs: [] },
  { type: "error", name: "EthSend", inputs: [] },
  { type: "error", name: "ZeroValue", inputs: [] },
  { type: "error", name: "TokenDead", inputs: [] },
  { type: "error", name: "NotDead", inputs: [] },
  { type: "error", name: "LiqCapped", inputs: [] },
  { type: "error", name: "AlreadySynced", inputs: [] },
  { type: "error", name: "PositionsOpen", inputs: [] },
  { type: "error", name: "OnlyHook", inputs: [] },
  { type: "error", name: "Reentrant", inputs: [] },
  { type: "error", name: "NotVault", inputs: [] },
  { type: "error", name: "UtilCapped", inputs: [] },
  { type: "error", name: "InsurancePaused", inputs: [] },
  { type: "error", name: "DustPosition", inputs: [] },
] as const;

/** Community PLV vault (staking) — deposit/withdraw ETH + token for perp-fee yield. */
export const PERP_VAULT_ABI = [
  { type: "function", name: "depositEth", stateMutability: "payable", inputs: [], outputs: [{ type: "uint256" }] },
  //  THE QUOTE-AGNOSTIC DEPOSIT. `depositEth()` is a native-only convenience
  //  wrapper; `deposit(amount)` is what PerpVault actually implements — it reads
  //  the engine's quote and either takes msg.value (native) or pulls the ERC20.
  //  The frontend only ever called the wrapper, which is why staking looked
  //  ETH-only even though the vault has handled any quote for some time.
  { type: "function", name: "deposit", stateMutability: "payable", inputs: [{ name: "amount", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "withdrawEth", stateMutability: "nonpayable", inputs: [{ name: "shares", type: "uint256" }], outputs: [{ type: "uint256" }, { type: "uint256" }] },
  { type: "function", name: "claimPendingEth", stateMutability: "nonpayable", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "depositToken", stateMutability: "nonpayable", inputs: [{ name: "amount", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "withdrawToken", stateMutability: "nonpayable", inputs: [{ name: "shares", type: "uint256" }], outputs: [{ type: "uint256" }, { type: "uint256" }] },
  { type: "function", name: "claimPendingToken", stateMutability: "nonpayable", inputs: [], outputs: [{ type: "uint256" }] },
  // side-attributed: token stakers earn ETH from short-side fees
  { type: "function", name: "claimTokYield", stateMutability: "nonpayable", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "pendingTokYield", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "ethShareOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "tokShareOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
] as const;

/** Human-readable explanations for the engine's revert reasons. */
export const PERP_ERROR_HELP: Record<string, string> = {
  NotWarm: "The market is still warming up (a short delay after launch before leverage opens). Try again shortly.",
  BadLeverage: "That leverage is too high for the current pool depth, or the position is too large for the market. Lower the size or leverage.",
  PlvInsufficient: "The liquidity vault doesn't have enough to front this leverage right now. Try a smaller size.",
  OiCapped: "Open interest on this side is at its cap. Try the other side or a smaller size.",
  TokenDead: "This token is dead (volume below the death floor). Perps are paused until it revives.",
  UtilCapped: "The vault is near full utilization — a slice stays reserved for depositors. Try a smaller size.",
  InsurancePaused: "Trading is briefly paused by the insurance circuit-breaker. Try again shortly.",
  DustPosition: "Position too small — increase the collateral.",
  Slippage: "Price moved past your limit. Try again.",
  Healthy: "This position isn't liquidatable.",
  ZeroValue: "Enter a collateral amount.",
};

/** Map any error (viem decoded name or message) → a friendly explanation. */
export function explainPerpError(e: unknown): string {
  const m = e as { name?: string; shortMessage?: string; message?: string; cause?: { name?: string } };
  const name = m?.name || m?.cause?.name || "";
  for (const key of Object.keys(PERP_ERROR_HELP)) {
    if (name === key || (m?.message ?? "").includes(key) || (m?.shortMessage ?? "").includes(key)) return PERP_ERROR_HELP[key];
  }
  const raw = m?.shortMessage || m?.message || "";
  if (/user rejected|denied|rejected the request/i.test(raw)) return "You rejected the transaction in your wallet.";
  if (/insufficient funds/i.test(raw)) return "Insufficient ETH for this trade + gas.";
  return raw ? raw.split("\n")[0].slice(0, 140) : "Transaction failed.";
}
