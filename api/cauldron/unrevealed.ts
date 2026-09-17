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
  //  This body is a CONSTANT — it has no token id, no chain read, and no state.
  //  It was cached for a day, which still let every CDN edge re-fetch it daily
  //  per region, per collection, forever. As the `tokenURI` of every unrevealed
  //  token in every brew it is fetched by every marketplace, wallet and indexer
  //  that ever sees one, with no user of ours involved: that billed 2.1M edge
  //  requests in a month against a site with no real visitors. A year with
  //  `immutable` is the honest TTL for a value that cannot change — and if the
  //  copy below ever needs to change, the answer is a new URI via
  //  {CauldronCollection.setUnrevealedURI}, not a short TTL on every request.
  res.setHeader("Cache-Control", "public, s-maxage=31536000, max-age=31536000, immutable");
  //  `s-maxage` is consumed by Vercel's own edge and does NOT survive downstream:
  //  measured live, this endpoint answered with a bare `cache-control: public`,
  //  which is why Cloudflare — sitting IN FRONT of Vercel — reported
  //  `cf-cache-status: DYNAMIC` and passed every request through. `max-age` above
  //  and this explicit CDN directive are what the layer in front actually reads,
  //  so the request stops at Cloudflare instead of reaching a function.
  res.setHeader("CDN-Cache-Control", "public, s-maxage=31536000, immutable");
  res.status(200).json({
    name: "Sealed Crystal",
    description:
      "A crystal summoned from the Cauldron's trading volume. Open it to reveal the creature sealed inside — or trade it unopened as a mystery box. Every sealed crystal is identical until cracked. Forged by Magic Internet Frens.",
    image: "https://www.mifrens.xyz/crystal.png",
    external_url: "https://www.mifrens.xyz",
    attributes: [
      { trait_type: "State", value: "Sealed" },
      { trait_type: "Contents", value: "Unknown creature" },
    ],
  });
}
