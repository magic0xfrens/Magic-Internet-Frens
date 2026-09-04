import type { VercelRequest, VercelResponse } from "@vercel/node";
import { createPublicClient, fallback, http, formatEther, type Address } from "viem";
import deployment from "../../indexer/deployments/round.json";

/**
 * /api/cauldron/liquidatoor?id=<tokenId>&col=<collection> — metadata for a
 * LIQUIDATOOR badge, the trophy struck when a fren's trade liquidates a
 * leveraged position on the perp engine.
 *
 * The badge's facts are read from the CHAIN, not invented here. Each collection
 * records a `LiqStats` struct at mint (victim, side, leverage, collateral,
 * bounty, block, entry and liquidation price), so this route renders what
 * actually happened. Previously it derived the artwork from the tokenId alone,
 * which produced a plausible-looking badge that described no real liquidation.
 *
 * The `image` is a self-contained SVG data URI, so it renders on marketplaces
 * with no second request and no external asset to keep alive.
 *
 * This route is the hosted path. The same badge can be served with no server at
 * all by wiring `LiquidatoorRenderer` via `setLiquidatorRenderer` — the contract
 * prefers that when set and falls back to this URI otherwise.
 */

const ZERO = "0x0000000000000000000000000000000000000000";

/** Badge ids start here; below it is regular collection art. */
const LIQUIDATOR_ID_BASE = 1_000_000n;

const RPCS = (process.env.API_RPC_URL ?? [
  "https://ethereum-sepolia-rpc.publicnode.com",
  "https://sepolia.drpc.org",
  "https://1rpc.io/sepolia",
].join(",")).split(",").map((s) => s.trim()).filter(Boolean);

const client = createPublicClient({
  transport: fallback(RPCS.map((u) => http(u, { retryCount: 2, retryDelay: 200 }))),
});

const LIQ_STATS_ABI = [{
  type: "function",
  name: "liqStats",
  stateMutability: "view",
  inputs: [{ type: "uint256" }],
  outputs: [{
    type: "tuple",
    components: [
      { name: "victim", type: "address" },
      { name: "wasLong", type: "bool" },
      { name: "leverage", type: "uint8" },
      { name: "collateralWei", type: "uint96" },
      { name: "bountyWei", type: "uint96" },
      { name: "blockNo", type: "uint64" },
      { name: "entryPrice", type: "uint128" },
      { name: "liqPrice", type: "uint128" },
    ],
  }],
}] as const;

interface Stats {
  victim: Address;
  wasLong: boolean;
  leverage: number;
  collateralWei: bigint;
  bountyWei: bigint;
  blockNo: bigint;
  entryPrice: bigint;
  liqPrice: bigint;
}

/**
 * Read the kill this badge commemorates.
 *
 * `col` names the collection holding the badge; without it the genesis
 * collection is assumed, which is where badges land today. Returns null when
 * the collection predates on-chain stats or the read fails — the badge still
 * renders, it just carries no readout, which is honest about not knowing rather
 * than printing zeroes that look like data.
 */
async function readStats(col: Address, tokenId: bigint): Promise<Stats | null> {
  try {
    // Cast through unknown: this viem version's ReadContractParameters demands
    // an `authorizationList` field that only applies to EIP-7702 writes, so a
    // plain view call does not typecheck against it. The ABI above still pins
    // the decoded shape, which is what matters here.
    const s = (await (client.readContract as unknown as (
      a: Record<string, unknown>,
    ) => Promise<unknown>)({
      address: col, abi: LIQ_STATS_ABI, functionName: "liqStats", args: [tokenId],
    })) as Stats;
    return s.victim && s.victim.toLowerCase() !== ZERO ? s : null;
  } catch {
    return null;
  }
}

const short = (a: string) => `${a.slice(0, 6)}...${a.slice(-4)}`;
/** Iteration tokens trade near 1e-9 ETH, so prices read in gwei. */
const gwei = (v: bigint) => `${(Number(v) / 1e9).toFixed(4)} gwei`;
const eth = (v: bigint) => `${Number(formatEther(v)).toFixed(4)}`;

const esc = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

function statLine(y: number, label: string, value: string, accent: string, ink: string) {
  return `<text x="56" y="${y}" font-family="'DM Mono',monospace" font-size="19" fill="${accent}">&gt;</text>`
    + `<text x="88" y="${y}" font-family="'DM Mono',monospace" font-size="19" fill="#7d8f88">${esc(label)}</text>`
    + `<text x="944" y="${y}" font-family="'DM Mono',monospace" font-size="19" fill="${ink}" text-anchor="end">${esc(value)}</text>`;
}

function badgeSVG(id: string, s: Stats | null): string {
  const pad = (id || "0").padStart(4, "0");
  const long = s?.wasLong ?? true;
  const accent = long ? "#3ce072" : "#ff3b46";
  const glow = long ? "#7bffa6" : "#ff6b73";
  const ink = long ? "#d6ffe2" : "#ffd9dc";
  const tint = long ? "30,210,90" : "255,40,55";

  const readout = s
    ? [
        statLine(812, "VICTIM", short(s.victim), accent, ink),
        statLine(838, "SIDE", s.wasLong ? "LONG" : "SHORT", accent, ink),
        statLine(864, "SIZE", `${eth(s.collateralWei * BigInt(s.leverage))} Ξ`, accent, ink),
        statLine(890, "LEVERAGE", `${s.leverage}x`, accent, ink),
        statLine(916, "ENTRY", gwei(s.entryPrice), accent, ink),
        statLine(942, "LIQ", gwei(s.liqPrice), accent, ink),
        statLine(968, "BOUNTY", `${eth(s.bountyWei)} Ξ`, accent, ink),
      ].join("")
    : `<text x="500" y="885" font-family="'DM Mono',monospace" font-size="22" fill="${ink}" text-anchor="middle">KILL RECORD UNAVAILABLE</text>`;

  // Scope reticle drawn as primitives — self-contained, so the badge needs no
  // second request and cannot break if an asset path changes.
  const ticks = Array.from({ length: 12 }, (_, i) => {
    const a = (i * Math.PI) / 6;
    return `<line x1="${(Math.cos(a) * 200).toFixed(1)}" y1="${(Math.sin(a) * 200).toFixed(1)}" x2="${(Math.cos(a) * 185).toFixed(1)}" y2="${(Math.sin(a) * 185).toFixed(1)}" stroke="${accent}" stroke-width="2" opacity="0.7"/>`;
  }).join("");

  return `<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 1000 1000">
  <defs>
    <radialGradient id="bg" cx="50%" cy="42%" r="75%"><stop offset="0%" stop-color="#141021"/><stop offset="100%" stop-color="#05070a"/></radialGradient>
    <radialGradient id="vig" cx="50%" cy="42%" r="66%"><stop offset="50%" stop-color="#000" stop-opacity="0"/><stop offset="100%" stop-color="#000" stop-opacity="0.7"/></radialGradient>
    <pattern id="scan" width="4" height="4" patternUnits="userSpaceOnUse"><rect width="4" height="2" fill="#000" opacity="0.16"/></pattern>
    <filter id="glow"><feGaussianBlur stdDeviation="6" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
    <clipPath id="fc"><rect x="24" y="24" width="952" height="952" rx="14"/></clipPath>
  </defs>
  <rect width="1000" height="1000" fill="#05070a"/>
  <g clip-path="url(#fc)">
    <rect x="24" y="24" width="952" height="724" fill="url(#bg)"/>
    <g transform="translate(500,400)" filter="url(#glow)">
      <circle r="210" fill="none" stroke="${accent}" stroke-width="3"/>
      <circle r="150" fill="none" stroke="${glow}" stroke-width="1.5" opacity="0.6"/>
      <circle r="70" fill="none" stroke="${accent}" stroke-width="1.5" opacity="0.5"/>
      <line x1="-260" y1="0" x2="-90" y2="0" stroke="${accent}" stroke-width="3"/>
      <line x1="90" y1="0" x2="260" y2="0" stroke="${accent}" stroke-width="3"/>
      <line x1="0" y1="-260" x2="0" y2="-90" stroke="${accent}" stroke-width="3"/>
      <line x1="0" y1="90" x2="0" y2="260" stroke="${accent}" stroke-width="3"/>
      <circle r="8" fill="${accent}"/>
      ${ticks}
    </g>
    <rect x="24" y="24" width="952" height="724" fill="rgb(${tint})" opacity="0.08"/>
    <rect x="24" y="24" width="952" height="724" fill="url(#vig)"/>
    <rect x="24" y="24" width="952" height="724" fill="url(#scan)"/>
    <text x="56" y="78" font-family="'DM Mono',monospace" font-size="24" fill="#c4d6cd">root@cauldron:~$ <tspan fill="#fff">liquidate --id ${esc(pad)}</tspan></text>
    <text x="56" y="126" font-family="'DM Mono',monospace" font-size="23" letter-spacing="3" fill="${glow}">&gt;&gt; TARGET LOCKED</text>
    <circle cx="884" cy="118" r="8" fill="${accent}"/>
    <text x="944" y="126" font-family="'DM Mono',monospace" font-size="23" fill="#fff" text-anchor="end">REC</text>
    <text x="500" y="690" text-anchor="middle" font-family="'DM Mono',monospace" font-weight="700" font-size="58" letter-spacing="8" fill="${accent}">LIQUIDATOOR</text>
    <rect x="24" y="770" width="952" height="206" fill="#070b10"/>
    ${readout}
  </g>
  <rect x="24" y="24" width="952" height="952" rx="14" fill="none" stroke="${accent}" stroke-width="3" opacity="0.55"/>
</svg>`;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader("Access-Control-Allow-Origin", "*");

  // Path is .../liquidatoor/<id>; fall back to the query for flat routing.
  const raw = (req.query.id ?? req.url?.split("/").pop() ?? "").toString();
  const id = raw.replace(/[^0-9]/g, "");
  const tokenId = id ? BigInt(id) : 0n;

  // Which collection holds it. Defaults to the genesis collection, where badges
  // land today; per-iteration collections pass ?col=.
  const colRaw = (req.query.col ?? "").toString();
  const col = (/^0x[0-9a-fA-F]{40}$/.test(colRaw)
    ? colRaw
    : deployment.contracts.presale) as Address;

  const stats = tokenId >= LIQUIDATOR_ID_BASE ? await readStats(col, tokenId) : null;

  // Cache a resolved badge hard — the kill it records is immutable. Cache an
  // unresolved one briefly, so a badge minted seconds ago is not pinned to
  // "unavailable" for a day because of one slow RPC read.
  res.setHeader(
    "Cache-Control",
    stats
      ? "public, s-maxage=31536000, immutable"
      : "public, s-maxage=30, stale-while-revalidate=300",
  );

  const attributes: Array<{ trait_type: string; value: string | number }> = [
    { trait_type: "Type", value: "Liquidatoor" },
    { trait_type: "Origin", value: "Perp Liquidation" },
  ];
  if (stats) {
    attributes.push(
      { trait_type: "Side", value: stats.wasLong ? "Long" : "Short" },
      { trait_type: "Leverage", value: stats.leverage },
      { trait_type: "Victim", value: short(stats.victim) },
      { trait_type: "Bounty ETH", value: eth(stats.bountyWei) },
      { trait_type: "Block", value: Number(stats.blockNo) },
    );
  }

  res.status(200).json({
    name: id ? `Liquidatoor #${id}` : "Liquidatoor",
    description:
      "A proof-of-kill trophy from the Cauldron perp engine. This badge was struck on-chain to the fren whose buy or sell liquidated a leveraged position past its TWAP mark. Not bought — earned. Forged by Magic Internet Frens.",
    image: `data:image/svg+xml,${encodeURIComponent(badgeSVG(id, stats))}`,
    external_url: "https://www.mifrens.xyz",
    attributes,
  });
}
