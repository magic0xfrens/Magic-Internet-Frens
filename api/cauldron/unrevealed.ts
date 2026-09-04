import type { VercelRequest, VercelResponse } from "@vercel/node";

/**
 * /api/cauldron/unrevealed — the SHARED sealed-crystal metadata for EVERY brew.
 *
 * All Cauldron collections point their unrevealed tokens at this one URI (it's a
 * constant in `CauldronCollection`, not per-token), so every sealed crystal —
 * across every iteration — looks identical: the MiFrens Sealed Crystal. Once a
 * holder calls `reveal(tokenId)`, the token switches to its collection's own
 * revealed art (on-chain renderer or IPFS baseURI), so the reveal is unique per
 * brew while the sealed state is one universal, recognizable mystery box.
 *
 * Marketplaces (OpenSea/Blur) fetch this for any unopened crystal.
 */
export default function handler(_req: VercelRequest, res: VercelResponse) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Cache-Control", "public, s-maxage=86400, stale-while-revalidate=604800");
  res.status(200).json({
    name: "Sealed Crystal",
    description:
      "A crystal summoned from the Cauldron's trading volume. Open it to reveal the creature sealed inside — or trade it unopened as a mystery box. Every sealed crystal is identical until cracked. Forged by Magic Internet Frens.",
    image: "https://magicfrens.xyz/crystal.png",
    external_url: "https://magicfrens.xyz",
    attributes: [
      { trait_type: "State", value: "Sealed" },
      { trait_type: "Contents", value: "Unknown creature" },
    ],
  });
}
