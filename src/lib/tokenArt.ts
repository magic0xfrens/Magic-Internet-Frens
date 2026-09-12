/**
 * ERC-721 token art resolution — ONE implementation.
 *
 *  ── WHY THIS FILE EXISTS ───────────────────────────────────────────────────
 *  Three components resolved `tokenURI` into a picture, each with its own copy:
 *  {ForgedCreatures}, {CreatureModal} and {CrystalCauldronGame}. Two of them
 *  handled hosted metadata; the third did not, and that third is the one a
 *  player actually opens a crystal in. Its copy read:
 *
 *      if (uri.startsWith("http") || uri.startsWith("ipfs")) return { image: uri };
 *
 *  which is the bug in one line. `CauldronCollection.tokenURI` (:416) returns
 *  `baseURI + rarity + "/" + tokenId` in BaseURI mode — a URL addressing a
 *  METADATA DOCUMENT, not an image. Handing it straight to `<img src>` asks the
 *  browser to render a JSON file, so a freshly revealed GNOMELAND creature
 *  showed nothing at all: the reveal transaction succeeded, the vault tile
 *  flipped to "revealed", and the art was a broken image.
 *
 *  Renderer mode returns a `data:application/json;base64,…` document instead, so
 *  the two modes have to be handled together or the panel works on whichever
 *  collection the developer happened to test against.
 */

/** Public gateway for `ipfs://` — usable directly by `<img src>`. */
const IPFS_GATEWAY = "https://ipfs.io/ipfs/";

/** Rewrite an `ipfs://` URI to something a browser can actually load. */
export const ipfsToHttp = (u?: string): string | undefined =>
  u && u.startsWith("ipfs://") ? u.replace("ipfs://", IPFS_GATEWAY) : u;

/**
 * Resolve a token's art (and name) from its ERC-721 `tokenURI`.
 *
 *  Handles both metadata shapes the Cauldron's collections emit:
 *    • on-chain `data:application/json[;base64],…` — decoded in place, no network
 *    • hosted `http(s)://` or `ipfs://` — FETCHED, because the URI addresses the
 *      metadata document and the image lives at its `.image` key
 *
 *  Never throws: an unreachable host, a CORS refusal or malformed JSON returns
 *  an empty result, and the caller keeps whatever placeholder it was showing.
 *  A single unreadable token must not blank a grid of twelve.
 */
export async function resolveTokenArt(uri: string): Promise<{ image?: string; name?: string }> {
  try {
    if (uri.startsWith("data:application/json;base64,")) {
      const j = JSON.parse(atob(uri.slice("data:application/json;base64,".length)));
      return { image: ipfsToHttp(j.image), name: j.name };
    }
    if (uri.startsWith("data:application/json,")) {
      const j = JSON.parse(decodeURIComponent(uri.slice("data:application/json,".length)));
      return { image: ipfsToHttp(j.image), name: j.name };
    }
    if (uri.startsWith("http") || uri.startsWith("ipfs")) {
      const res = await fetch(ipfsToHttp(uri) as string, { signal: AbortSignal.timeout(6000) });
      if (!res.ok) return {};
      //  A baseURI that points straight AT the art rather than at metadata is a
      //  legal (if unusual) collection. Serving it to `<img>` is right in that
      //  case and is exactly what the broken copy did by accident — so keep the
      //  behaviour where it happens to be correct instead of showing nothing.
      const type = res.headers.get("content-type") ?? "";
      if (type.startsWith("image/")) return { image: ipfsToHttp(uri) };
      const meta = await res.json();
      return { image: ipfsToHttp(meta.image), name: meta.name };
    }
  } catch { /* unreachable / CORS / malformed — the caller keeps its placeholder */ }
  return {};
}
