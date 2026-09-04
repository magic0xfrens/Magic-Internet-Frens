import type { VercelRequest, VercelResponse } from "@vercel/node";
import { createPublicClient, http, parseAbiItem, type Address } from "viem";
import { sepolia } from "viem/chains";

/**
 * /api/perp-heatmap  — the liquidation heatmap source for the price chart.
 *
 * Reads PerpEngine's Opened/Closed logs directly on-chain (bounded getLogs,
 * same self-contained pattern as /api/candles — no DB required), reconstructs
 * the set of OPEN positions, and returns each one's liquidation price + size so
 * the chart can render horizontal liquidation-density bands (long liq zones sit
 * BELOW price, short liq zones ABOVE — the walls the market hunts).
 *
 * liqPrice is derived from the event args (entryPrice = notionalEth / sizeToken)
 * + leverage + the maintenance margin, matching PerpEngine._underwater. Inert
 * (empty) until PERP_ENGINE is set to the deployed address.
 */

const CHAIN = sepolia;
const RPC = process.env.SEPOLIA_RPC || process.env.PONDER_RPC_URL || "https://ethereum-sepolia-rpc.publicnode.com";
const PERP_ENGINE = (process.env.PERP_ENGINE || "0x37A8F60924a9fE0F11ab60062F1Df34Cf055F7Ed") as Address;
const PERP_START = BigInt(process.env.PERP_START_BLOCK || "11590515");
const MAX_LOG_RANGE = 9000n;
const DEFAULT_M = Number(process.env.PERP_MAINTENANCE_BPS || "1500") / 1e4;

const OPENED = parseAbiItem(
  "event Opened(uint256 indexed id, address indexed trader, bool isLong, uint256 collateral, uint256 size, uint8 leverage)",
);
const CLOSED = parseAbiItem("event Closed(uint256 indexed id, address indexed trader, uint256 payout, int256 pnl)");
const ENGINE_ABI = [
  { type: "function", name: "maintenanceBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "plv", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

const client = createPublicClient({ chain: CHAIN, transport: http(RPC) });
const ZERO = "0x0000000000000000000000000000000000000000";

function liqPriceOf(entry: number, lev: number, isLong: boolean, m: number): number {
  if (lev <= 0) return entry;
  return isLong ? (entry * (lev - 1) * (1 + m)) / lev : (entry * (lev + 1) * (1 - m)) / lev;
}

type Pos = { id: string; isLong: boolean; leverage: number; entryPrice: number; liqPrice: number; notionalEth: number };

export default async function handler(req: VercelRequest, res: VercelResponse) {
  try {
    res.setHeader("Cache-Control", "public, s-maxage=15, stale-while-revalidate=60");

    if (PERP_ENGINE.toLowerCase() === ZERO) {
      return res.status(200).json({ live: false, positions: [], longOiEth: 0, shortOiEth: 0, plvEth: 0 });
    }

    const m = await client
      .readContract({ address: PERP_ENGINE, abi: ENGINE_ABI, functionName: "maintenanceBps" })
      .then((v) => Number(v) / 1e4)
      .catch(() => DEFAULT_M);
    const plvEth = await client
      .readContract({ address: PERP_ENGINE, abi: ENGINE_ABI, functionName: "plv" })
      .then((v) => Number(v) / 1e18)
      .catch(() => 0);

    const head = await client.getBlockNumber();
    const open = new Map<string, Pos>();
    const closed = new Set<string>();

    let from = PERP_START;
    while (from <= head) {
      const to = from + MAX_LOG_RANGE - 1n > head ? head : from + MAX_LOG_RANGE - 1n;
      const [opens, closes] = await Promise.all([
        client.getLogs({ address: PERP_ENGINE, event: OPENED, fromBlock: from, toBlock: to }),
        client.getLogs({ address: PERP_ENGINE, event: CLOSED, fromBlock: from, toBlock: to }),
      ]);
      for (const l of closes) closed.add(String(l.args.id));
      for (const l of opens) {
        const id = String(l.args.id);
        const lev = Number(l.args.leverage);
        const collateralEth = Number(l.args.collateral as bigint) / 1e18;
        const sizeTok = Number(l.args.size as bigint) / 1e18;
        const notionalEth = collateralEth * lev;
        const entryPrice = sizeTok > 0 ? notionalEth / sizeTok : 0;
        const isLong = l.args.isLong as boolean;
        open.set(id, { id, isLong, leverage: lev, entryPrice, notionalEth, liqPrice: liqPriceOf(entryPrice, lev, isLong, m) });
      }
      from = to + 1n;
    }

    let longOiEth = 0;
    let shortOiEth = 0;
    const positions: Pos[] = [];
    for (const [id, p] of open) {
      if (closed.has(id)) continue; // position was closed/liquidated
      if (!(p.liqPrice > 0) || !Number.isFinite(p.liqPrice)) continue;
      positions.push(p);
      if (p.isLong) longOiEth += p.notionalEth;
      else shortOiEth += p.notionalEth;
    }
    // Heaviest walls first; cap payload.
    positions.sort((a, b) => b.notionalEth - a.notionalEth);

    return res.status(200).json({
      live: true,
      positions: positions.slice(0, 500),
      longOiEth,
      shortOiEth,
      plvEth,
      openCount: positions.length,
    });
  } catch (e) {
    return res.status(200).json({ live: false, positions: [], longOiEth: 0, shortOiEth: 0, plvEth: 0, error: (e as Error).message });
  }
}
