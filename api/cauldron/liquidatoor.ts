import type { VercelRequest, VercelResponse } from "@vercel/node";

/**
 * /api/cauldron/liquidatoor/:id — metadata for a LIQUIDATOOR badge, the OnChain
 * Collectible struck when a fren is responsible for a perp liquidation on the
 * hook. Every Cauldron collection points its badge id range at this one URI
 * (a constant `liquidatorURI` + tokenId on-chain), so a badge looks the same
 * across every iteration: proof-of-kill, minted to the liquidator.
 *
 * The `image` is a SELF-CONTAINED SVG data-URI (no external file dependency) so it
 * renders everywhere — localhost, prod, and marketplaces (OpenSea/Blur) — the
 * instant a badge is minted. A "sniper-scope kill-log" motif drawn purely with
 * vector primitives + monospace type; deterministic per tokenId.
 */

/** Deterministic self-contained badge artwork (pure vector, no external assets). */
function badgeSVG(id: string): string {
  const pad = (id || "0").padStart(4, "0");
  const scanlines = Array.from({ length: 62 }, (_, i) => `<rect y="${i * 16}" width="1000" height="1"/>`).join("");
  const ticks = Array.from({ length: 12 }, (_, i) => {
    const a = (i * Math.PI) / 6;
    return `<line x1="${(Math.cos(a) * 200).toFixed(1)}" y1="${(Math.sin(a) * 200).toFixed(1)}" x2="${(Math.cos(a) * 185).toFixed(1)}" y2="${(Math.sin(a) * 185).toFixed(1)}" stroke="#d5fd51" stroke-width="2" opacity="0.7"/>`;
  }).join("");
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="1000" viewBox="0 0 1000 1000">
  <defs>
    <radialGradient id="bg" cx="50%" cy="42%" r="75%"><stop offset="0%" stop-color="#141021"/><stop offset="100%" stop-color="#080610"/></radialGradient>
    <linearGradient id="lime" x1="0" y1="0" x2="1" y2="1"><stop offset="0%" stop-color="#d5fd51"/><stop offset="100%" stop-color="#3ce072"/></linearGradient>
    <filter id="glow"><feGaussianBlur stdDeviation="6" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  </defs>
  <rect width="1000" height="1000" fill="url(#bg)"/>
  <g opacity="0.06" fill="#ffffff">${scanlines}</g>
  <rect x="60" y="60" width="880" height="880" rx="18" fill="none" stroke="url(#lime)" stroke-width="2" opacity="0.85"/>
  <rect x="60" y="60" width="880" height="70" rx="18" fill="#d5fd51" opacity="0.10"/>
  <circle cx="98" cy="95" r="7" fill="#ff5470"/><circle cx="126" cy="95" r="7" fill="#f6c86a"/><circle cx="154" cy="95" r="7" fill="#3ce072"/>
  <text x="500" y="103" text-anchor="middle" font-family="'DM Mono',monospace" font-size="26" letter-spacing="6" fill="#d5fd51">KILL-LOG // CAULDRON PERP</text>
  <g transform="translate(500,470)" filter="url(#glow)">
    <circle r="210" fill="none" stroke="url(#lime)" stroke-width="3"/>
    <circle r="150" fill="none" stroke="#3ce072" stroke-width="1.5" opacity="0.6"/>
    <circle r="70" fill="none" stroke="#d5fd51" stroke-width="1.5" opacity="0.5"/>
    <line x1="-260" y1="0" x2="-90" y2="0" stroke="url(#lime)" stroke-width="3"/>
    <line x1="90" y1="0" x2="260" y2="0" stroke="url(#lime)" stroke-width="3"/>
    <line x1="0" y1="-260" x2="0" y2="-90" stroke="url(#lime)" stroke-width="3"/>
    <line x1="0" y1="90" x2="0" y2="260" stroke="url(#lime)" stroke-width="3"/>
    <circle r="8" fill="#ff5470"/>
    ${ticks}
  </g>
  <text x="500" y="792" text-anchor="middle" font-family="'DM Mono',monospace" font-weight="700" font-size="72" letter-spacing="10" fill="url(#lime)">LIQUIDATOOR</text>
  <text x="500" y="838" text-anchor="middle" font-family="'DM Mono',monospace" font-size="26" letter-spacing="8" fill="#8f83b8">&gt; PROOF OF KILL</text>
  <text x="500" y="892" text-anchor="middle" font-family="'DM Mono',monospace" font-size="30" letter-spacing="4" fill="#f5f0e8">BADGE #${pad}</text>
</svg>`;
}

export default function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Cache-Control", "public, s-maxage=86400, stale-while-revalidate=604800");

  // Path is .../liquidatoor/<id>; fall back to the query for flat routing.
  const raw = (req.query.id ?? req.url?.split("/").pop() ?? "").toString();
  const id = raw.replace(/[^0-9]/g, "");
  const image = `data:image/svg+xml,${encodeURIComponent(badgeSVG(id))}`;

  res.status(200).json({
    name: id ? `Liquidatoor #${id}` : "Liquidatoor",
    description:
      "A proof-of-kill trophy from the Cauldron perp engine. This badge was struck on-chain to the fren whose buy or sell liquidated a leveraged position past its TWAP mark. Not bought — earned. Forged by Magic Internet Frens.",
    image,
    external_url: "https://magicfrens.xyz",
    attributes: [
      { trait_type: "Type", value: "Liquidatoor" },
      { trait_type: "Origin", value: "Perp Liquidation" },
      { trait_type: "isLiquidatoor", value: "true" },
    ],
  });
}
