/**
 * liquidatoorBadgeArt — the on-chain Liquidatoor trophy artwork.
 *
 * A pure function that returns a self-contained SVG string, designed to map
 * 1:1 onto what the Solidity `tokenURI` renderer will eventually emit (so we
 * can perfect the look off-chain first, then port the exact markup on-chain).
 *
 * The art = a "hacker terminal" console window framing the sniper-scope image
 * (short = red bear, long = green bull), with the liquidation stats printed as
 * a terminal readout. Everything is drawn with primitives + a single <image>,
 * monospace type, scanlines and a CRT vignette so it reads like a kill-log.
 *
 * On-chain, `imageHref` becomes a base64 data-URI of the (downscaled) scope art
 * stored via SSTORE2; here it can just be a /public path for fast iteration.
 */

export interface LiquidatoorStats {
  side: "short" | "long";
  tokenId: number;
  /** victim wallet, already shortened e.g. "0x9f2a…8c1d" */
  victim: string;
  /** liquidator wallet, shortened */
  liquidator: string;
  /** position notional in ETH, e.g. "4.20" */
  sizeEth: string;
  /** leverage multiple, e.g. 15 */
  leverage: number;
  /** entry price, formatted e.g. "2,431.09" */
  entry: string;
  /** liquidation price, formatted e.g. "2,088.55" */
  liqPrice: string;
  /** realized pnl % for the victim, e.g. "-100.0" */
  pnlPct: string;
  /** liquidator bounty in ETH, e.g. "0.084" */
  bountyEth: string;
  /** block number, formatted e.g. "21,041,553" */
  block: string;
  /** base scope image — /public path (preview) or data-URI (on-chain) */
  imageHref: string;
}

const PALETTE = {
  short: {
    accent: "#ff3b46",
    accentDim: "#a11f27",
    glow: "#ff6b73",
    ink: "#ffd9dc",
    tintR: 255, tintG: 40, tintB: 55,
    word: "SHORT",
  },
  long: {
    accent: "#3ce072",
    accentDim: "#1c8a44",
    glow: "#7bffa6",
    ink: "#d6ffe2",
    tintR: 30, tintG: 210, tintB: 90,
    word: "LONG",
  },
} as const;

const pad4 = (n: number) => String(n).padStart(4, "0");

/** A single terminal stat line: "> LABEL        value" */
function statLine(y: number, label: string, value: string, accent: string, ink: string): string {
  return `
    <text x="56" y="${y}" font-family="'DM Mono','Courier New',monospace" font-size="25" fill="${accent}">&gt;</text>
    <text x="88" y="${y}" font-family="'DM Mono','Courier New',monospace" font-size="25" letter-spacing="1" fill="${accent}" opacity="0.7">${label}</text>
    <text x="360" y="${y}" font-family="'DM Mono','Courier New',monospace" font-size="25" font-weight="500" fill="${ink}">${value}</text>`;
}

export function liquidatoorBadgeSVG(s: LiquidatoorStats): string {
  const c = PALETTE[s.side];
  const idStr = pad4(s.tokenId);

  return `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1000" height="1000" viewBox="0 0 1000 1000">
  <defs>
    <linearGradient id="topShade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#05070a" stop-opacity="0.92"/>
      <stop offset="100%" stop-color="#05070a" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="botShade" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#05070a" stop-opacity="0"/>
      <stop offset="34%" stop-color="#05070a" stop-opacity="0.86"/>
      <stop offset="100%" stop-color="#05070a" stop-opacity="0.97"/>
    </linearGradient>
    <radialGradient id="vig" cx="50%" cy="42%" r="66%">
      <stop offset="50%" stop-color="#000000" stop-opacity="0"/>
      <stop offset="100%" stop-color="#000000" stop-opacity="0.7"/>
    </radialGradient>
    <pattern id="scan" width="4" height="4" patternUnits="userSpaceOnUse">
      <rect width="4" height="2" fill="#000000" opacity="0.16"/>
    </pattern>
    <clipPath id="frameClip"><rect x="24" y="24" width="952" height="952" rx="14"/></clipPath>
  </defs>

  <!-- terminal backdrop -->
  <rect width="1000" height="1000" fill="#05070a"/>

  <g clip-path="url(#frameClip)">
    <!-- ═══ IMAGE (top ~72%) — fills the full card width, whole NFT visible ═══ -->
    <rect x="24" y="24" width="952" height="724" fill="#0a0f14"/>
    <!-- width-constrained fit: the full landscape NFT spans edge-to-edge, no side bars -->
    <image xlink:href="${s.imageHref}" x="24" y="24" width="952" height="724" preserveAspectRatio="xMidYMid meet"/>
    <!-- light cinematic tint + soft vignette (kept subtle so the art reads) -->
    <rect x="24" y="24" width="952" height="724" fill="rgb(${c.tintR},${c.tintG},${c.tintB})" opacity="0.10"/>
    <rect x="24" y="24" width="952" height="724" fill="url(#vig)"/>
    <rect x="24" y="24" width="952" height="724" fill="url(#scan)"/>
    <!-- top readability shade for the prompt -->
    <rect x="24" y="24" width="952" height="150" fill="url(#topShade)"/>

    <!-- prompt + HUD over the top of the image -->
    <text x="56" y="78" font-family="'DM Mono','Courier New',monospace" font-size="24" fill="#c4d6cd">root@cauldron:~$ <tspan fill="#ffffff">liquidate --id ${idStr}</tspan></text>
    <text x="56" y="126" font-family="'DM Mono','Courier New',monospace" font-size="23" letter-spacing="3" fill="${c.glow}">&gt;&gt; TARGET LOCKED</text>
    <circle cx="884" cy="118" r="8" fill="${c.accent}"><animate attributeName="opacity" values="1;0.15;1" dur="1.1s" repeatCount="indefinite"/></circle>
    <text x="906" y="126" font-family="'DM Mono','Courier New',monospace" font-size="23" letter-spacing="2" fill="#ffffff">REC</text>

    <!-- targeting corner brackets around the viewport -->
    ${["M46,74 L46,46 L74,46", "M926,46 L954,46 L954,74", "M954,726 L954,748 L926,748", "M74,748 L46,748 L46,726"]
      .map((d) => `<path d="${d}" fill="none" stroke="${c.accent}" stroke-width="3" stroke-opacity="0.9"/>`).join("")}

    <!-- ═══ STATS STRIP (bottom ~28%) — solid, compact, nothing over the art ═══ -->
    <rect x="24" y="748" width="952" height="228" fill="#080c10"/>
    <rect x="24" y="748" width="952" height="4" fill="${c.accent}"/>

    <!-- headline -->
    <text x="56" y="812" font-family="'DM Mono','Courier New',monospace" font-size="42" font-weight="700" letter-spacing="1" fill="#ffffff">${c.word} <tspan fill="${c.accent}">LIQUIDATED</tspan></text>

    <!-- compact kill-log (left) -->
    ${statLine(858, "TARGET  ", `${s.victim} · ${s.leverage}x`, c.accent, c.ink)}
    ${statLine(894, "SIZE    ", `${s.sizeEth} Ξ · ${s.pnlPct}%`, c.accent, c.ink)}

    <!-- bounty highlight (right) -->
    <rect x="636" y="782" width="308" height="112" rx="12" fill="#0d141a" stroke="${c.accent}" stroke-opacity="0.55" stroke-width="2"/>
    <text x="660" y="818" font-family="'DM Mono','Courier New',monospace" font-size="19" letter-spacing="2" fill="${c.accent}" opacity="0.78">BOUNTY CLAIMED</text>
    <text x="660" y="872" font-family="'DM Mono','Courier New',monospace" font-size="42" font-weight="700" fill="${c.glow}">+${s.bountyEth} Ξ</text>

    <!-- footer -->
    <line x1="56" y1="924" x2="944" y2="924" stroke="${c.accent}" stroke-opacity="0.28" stroke-width="2"/>
    <text x="56" y="960" font-family="'DM Mono','Courier New',monospace" font-size="20" letter-spacing="1" fill="#8aa39a">BLOCK #${s.block}</text>
    <text x="500" y="960" text-anchor="middle" font-family="'DM Mono','Courier New',monospace" font-size="20" letter-spacing="2" fill="${c.accent}" opacity="0.85">SEALED ON-CHAIN</text>
    <text x="944" y="960" text-anchor="end" font-family="'DM Mono','Courier New',monospace" font-size="25" font-weight="700" fill="#ffffff">#${idStr}</text>
  </g>

  <!-- frame edge -->
  <rect x="24" y="24" width="952" height="952" rx="14" fill="none" stroke="${c.accent}" stroke-opacity="0.6" stroke-width="2"/>
</svg>`;
}

/** A sample stat set for previewing a given side. */
export function sampleLiquidatoorStats(side: "short" | "long", tokenId: number, imageHref: string): LiquidatoorStats {
  const rand = (min: number, max: number) => min + Math.random() * (max - min);
  const hex = () => Math.floor(Math.random() * 16).toString(16);
  const addr = () => `0x${hex()}${hex()}${hex()}${hex()}…${hex()}${hex()}${hex()}${hex()}`;
  const entryN = rand(1800, 3200);
  const drop = side === "short" ? rand(1.05, 1.3) : rand(0.7, 0.95);
  const fmt = (n: number) => n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return {
    side,
    tokenId,
    victim: addr(),
    liquidator: addr(),
    sizeEth: rand(0.4, 12).toFixed(2),
    leverage: Math.floor(rand(3, 25)),
    entry: fmt(entryN),
    liqPrice: fmt(entryN * drop),
    pnlPct: "-100.0",
    bountyEth: rand(0.01, 0.4).toFixed(3),
    block: Math.floor(rand(21_000_000, 21_400_000)).toLocaleString("en-US"),
    imageHref,
  };
}
