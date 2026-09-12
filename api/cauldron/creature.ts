import type { VercelRequest, VercelResponse } from "@vercel/node";
import { createPublicClient, encodePacked, fallback, http, keccak256, type Address } from "viem";
import deployment from "../../indexer/deployments/round.json";
import {
  COMPRESSED_TRAITS,
  PALETTE_RGB_HEX,
  type CompressedTrait,
} from "../../compressed-traits/compressed-traits";

/**
 * /api/cauldron/creature/<rarity>/<tokenId>?col=<collection> — the REVEALED
 * creature's ERC-721 metadata, with the art composed here, from the same
 * compressed pixel blobs the on-chain renderer draws.
 *
 * WHY THIS ROUTE EXISTS. `CauldronCollection` resolves revealed art two ways
 * (`cauldron/CauldronCollection.sol:411-421`): an on-chain renderer, or
 * `_baseTokenURI + rarity + "/" + tokenId`. The renderer path was broken for
 * every token (the collection calls `tokenURI(uint256)`, the art renderer only
 * answers `tokenURI(uint256,uint8,uint8,uint8,uint8)`), and standing the
 * on-chain art stack up means uploading ~1.2 MB of trait blobs through SSTORE2.
 * This is the BaseURI arm of that same switch: real art, no art upload, and the
 * URL shape is copied from the contract, not invented — set the collection's
 * base URI to `https://www.mifrens.xyz/api/cauldron/creature/` and the contract
 * appends `<rarity>/<tokenId>` itself.
 *
 * THE TRAITS ARE NOT GUESSED. A Cauldron collection stores no trait indices —
 * `rarityOf` and `revealed` are its only per-token art state
 * (`cauldron/CauldronCollection.sol:104,115`). The canonical derivation is
 * defined once, in `cauldron/CauldronArtAdapter.sol`, and reimplemented here
 * byte-for-byte:
 *
 *     seed = keccak256(abi.encodePacked(collection, tokenId, rarity))
 *
 * so a collection flipped between Renderer mode and BaseURI mode shows the
 * holder the SAME creature. `rarity` is read FROM THE CHAIN, never from the URL
 * path — the path segment is what the contract happens to emit, not a trusted
 * input. If the chain cannot be read, this route returns metadata with NO image
 * and an `art_unavailable` reason rather than a plausible wrong creature.
 *
 * The SVG composition is a port of `render/FrenRenderer.renderSVG`
 * (`render/FrenRenderer.sol:66-88`): 120x120 canvas at 480px, the gradient
 * hashed from the trait indices, layers painted face -> body -> item as
 * run-length `<rect>`s. The image is a self-contained SVG data URI, like
 * `api/cauldron/liquidatoor.ts`, so it needs no second request.
 */

const RPCS = (process.env.API_RPC_URL ?? [
  "https://ethereum-sepolia-rpc.publicnode.com",
  "https://sepolia.drpc.org",
  "https://1rpc.io/sepolia",
].join(",")).split(",").map((s) => s.trim()).filter(Boolean);

const client = createPublicClient({
  transport: fallback(RPCS.map((u) => http(u, { retryCount: 2, retryDelay: 200 }))),
});

const COLLECTION_ABI = [
  { type: "function", name: "rarityOf", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint8" }] },
  { type: "function", name: "revealed", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "bool" }] },
] as const;

/* ── trait set ───────────────────────────────────────────────────────────── */

const LAYER_BODY = 0, LAYER_FACE = 1, LAYER_ITEM = 2;
const CLASS_NAMES = ["Wizard", "King", "Knight", "Apprentice", "Peasant", "Gnome", "Elf"];
const RARITY_NAMES = ["Common", "Rare", "Epic", "Legendary"];

/** layerType -> classIdx -> layerIdx -> blob bytes. Color batches are not traits. */
const TRAITS: Map<number, Uint8Array> = new Map();
const COUNTS: Map<number, number> = new Map(); // layerType*256 + classIdx -> layer count
const LABELS: Map<number, string> = new Map();

function hexToBytes(hex: string): Uint8Array {
  const h = hex.startsWith("0x") ? hex.slice(2) : hex;
  const out = new Uint8Array(h.length >> 1);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(h.substr(i * 2, 2), 16);
  return out;
}

for (const t of COMPRESSED_TRAITS as CompressedTrait[]) {
  if (t.isColorBatch) continue;
  TRAITS.set(t.traitKey, hexToBytes(t.blob));
  LABELS.set(t.traitKey, t.label);
  const ck = t.layerType * 256 + t.classIdx;
  COUNTS.set(ck, Math.max(COUNTS.get(ck) ?? 0, t.layerIdx + 1));
}
const PALETTE = hexToBytes(PALETTE_RGB_HEX);

const traitKey = (layerType: number, classIdx: number, layerIdx: number) =>
  layerType * 65536 + classIdx * 256 + layerIdx;
const count = (layerType: number, classIdx: number) => COUNTS.get(layerType * 256 + classIdx) ?? 0;

/** Faces exist only for the universal set (0), Gnome (5), Elf (6) — FrenRenderer.sol:257. */
const faceClass = (classIdx: number) => (classIdx === 5 ? 5 : classIdx === 6 ? 6 : 0);

/* ── the canonical trait derivation (mirrors CauldronArtAdapter.traitsOf) ─── */

export interface Traits { classIdx: number; bodyIdx: number; faceIdx: number; itemIdx: number }

export function deriveTraits(collection: Address, tokenId: bigint, rarity: number): Traits {
  const s = BigInt(keccak256(encodePacked(["address", "uint256", "uint8"], [collection, tokenId, rarity])));
  const classIdx = Number(s % 7n);
  const bodies = count(LAYER_BODY, classIdx) || 1;
  const items = count(LAYER_ITEM, classIdx) || 1;
  const faces = count(LAYER_FACE, faceClass(classIdx)) || 1;
  return {
    classIdx,
    bodyIdx: Number(((s >> 32n) % BigInt(bodies))),
    faceIdx: Number(((s >> 64n) % BigInt(faces))),
    itemIdx: Number(((s >> 96n) % BigInt(items))),
  };
}

/* ── SVG composition (port of FrenRenderer.renderSVG) ────────────────────── */

const hex2 = (v: number) => v.toString(16).padStart(2, "0").toUpperCase();
const clamp = (v: number) => (v < 0 ? 0 : v > 255 ? 255 : v);

/** FrenRenderer._gradient / FrenSprite.frenGradient. */
function gradient(bodyIdx: number, faceIdx: number, itemIdx: number): [string, string] {
  const hash = (bodyIdx * 7919 + faceIdx * 6271 + itemIdx * 4813) & 0xffff;
  const n0 = ((hash >> 0) & 0xf) - 8, n4 = ((hash >> 4) & 0xf) - 8, n8 = ((hash >> 8) & 0xf) - 8;
  const rgb = (r: number, g: number, b: number) => `${hex2(clamp(r))}${hex2(clamp(g))}${hex2(clamp(b))}`;
  return [rgb(0xf7 + n0, 0x93 + n4, 0x1a + n8), rgb(0x3d + n0, 0x24 + n4, 0x07 + n8)];
}

function colorAt(globalIdx: number): string {
  const p = globalIdx * 3;
  if (p + 2 >= PALETTE.length) return "#000000";
  return `#${hex2(PALETTE[p])}${hex2(PALETTE[p + 1])}${hex2(PALETTE[p + 2])}`;
}

/** One trait layer as run-length `<rect>`s. Empty when the blob is absent. */
function layerRects(layerType: number, classIdx: number, layerIdx: number): string {
  const blob = TRAITS.get(traitKey(layerType, classIdx, layerIdx));
  if (!blob || blob.length < 8) return "";
  const minX = blob[3], minY = blob[4], w = blob[5], h = blob[6], localSize = blob[7];
  const colors: string[] = ["transparent"];
  for (let i = 0; i < localSize; i++) colors.push(colorAt(blob[8 + i]));
  const pixOff = 8 + localSize;
  const nibble = (idx: number) => {
    const byte = blob[pixOff + (idx >> 1)];
    return byte === undefined ? 0 : (idx & 1) === 0 ? byte >> 4 : byte & 0x0f;
  };

  let out = "";
  for (let row = 0; row < h; row++) {
    const base = row * w;
    let col = 0;
    while (col < w) {
      const nib = nibble(base + col);
      if (nib === 0) { col++; continue; }
      let next = col + 1;
      while (next < w && nibble(base + next) === nib) next++;
      out += `<rect x="${minX + col}" y="${minY + row}" width="${next - col}" height="1" fill="${colors[nib] ?? "#000000"}"/>`;
      col = next;
    }
  }
  return out;
}

export function renderSVG(t: Traits): string {
  const [top, bot] = gradient(t.bodyIdx, t.faceIdx, t.itemIdx);
  // z-order: face (bottom), body, item (top) — FrenRenderer.sol:82-84.
  return `<svg xmlns="http://www.w3.org/2000/svg" width="480" height="480" viewBox="0 0 120 120" shape-rendering="crispEdges">`
    + `<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">`
    + `<stop offset="0" stop-color="#${top}"/><stop offset="1" stop-color="#${bot}"/>`
    + `</linearGradient></defs><rect width="120" height="120" fill="url(#g)"/>`
    + layerRects(LAYER_FACE, faceClass(t.classIdx), t.faceIdx)
    + layerRects(LAYER_BODY, t.classIdx, t.bodyIdx)
    + layerRects(LAYER_ITEM, t.classIdx, t.itemIdx)
    + `</svg>`;
}

/* ── handler ─────────────────────────────────────────────────────────────── */

/** The collection holding the token. `?col=` must name a collection we ship. */
function resolveCollection(colRaw: string): Address | null {
  const known = new Set(
    [deployment.contracts?.collection, ...(process.env.LIQUIDATOOR_COLLECTIONS || "").split(",")]
      .map((a) => (a ?? "").trim().toLowerCase())
      .filter((a) => /^0x[0-9a-f]{40}$/.test(a)),
  );
  if (!colRaw) return (deployment.contracts.collection as Address) ?? null;
  if (!known.has(colRaw.toLowerCase())) return null;
  return colRaw as Address;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader("Access-Control-Allow-Origin", "*");

  // Path is .../creature/<rarity>/<tokenId>; the query form is the flat fallback.
  const parts = (req.url ?? "").split("?")[0].split("/").filter(Boolean);
  const idRaw = (req.query.id ?? parts[parts.length - 1] ?? "").toString().replace(/[^0-9]/g, "");
  if (!idRaw) return res.status(400).json({ error: "missing token id" });
  const tokenId = BigInt(idRaw);

  const col = resolveCollection((req.query.col ?? "").toString());
  if (!col) return res.status(400).json({ error: "unknown collection" });

  // The chain is the authority on rarity and on whether the art exists yet. The
  // `<rarity>` path segment is echoed by the contract, not trusted here.
  let rarity: number | null = null;
  let reason = "";
  try {
    const read = client.readContract as unknown as (a: Record<string, unknown>) => Promise<unknown>;
    const isRevealed = (await read({ address: col, abi: COLLECTION_ABI, functionName: "revealed", args: [tokenId] })) as boolean;
    if (!isRevealed) {
      res.setHeader("Cache-Control", "public, s-maxage=15, stale-while-revalidate=60");
      return res.status(200).json({
        name: `Sealed Crystal #${idRaw}`,
        description: "This crystal has not been cracked yet. Open it to reveal the creature sealed inside.",
        image: "https://www.mifrens.xyz/crystal.png",
        external_url: "https://www.mifrens.xyz",
        attributes: [{ trait_type: "State", value: "Sealed" }],
      });
    }
    rarity = Number((await read({ address: col, abi: COLLECTION_ABI, functionName: "rarityOf", args: [tokenId] })) as number);
  } catch (e) {
    reason = (e as Error)?.message?.slice(0, 160) ?? "chain read failed";
  }

  if (rarity === null) {
    //  NO INVENTED CREATURE. Without the on-chain rarity the seed is unknown, and
    //  a guess would render a different fren than the one this token is. Say so,
    //  cache it briefly, and let the caller retry.
    res.setHeader("Cache-Control", "public, s-maxage=15, stale-while-revalidate=60");
    return res.status(200).json({
      name: `MagicFren #${idRaw}`,
      description: "Art temporarily unavailable: the creature's traits are derived from its on-chain rarity, which could not be read.",
      external_url: "https://www.mifrens.xyz",
      art_unavailable: reason || "rarity unreadable",
      attributes: [{ trait_type: "State", value: "Revealed" }],
    });
  }

  const t = deriveTraits(col, tokenId, rarity);
  const svg = renderSVG(t);
  const label = LABELS.get(traitKey(LAYER_BODY, t.classIdx, t.bodyIdx)) ?? CLASS_NAMES[t.classIdx];

  // The traits are a pure function of (collection, id, rarity), and rarity is
  // immutable once revealed — so this answer never changes. Cache it hard.
  res.setHeader("Cache-Control", "public, s-maxage=31536000, immutable");
  res.status(200).json({
    name: `MagicFren #${idRaw}`,
    description:
      "A creature summoned from the Cauldron's trading volume. Its traits are derived on-chain from the collection, the token id and the rarity rolled at reveal, and the pixels are the same trait set the on-chain renderer draws. Forged by Magic Internet Frens.",
    image: `data:image/svg+xml,${encodeURIComponent(svg)}`,
    external_url: "https://www.mifrens.xyz",
    attributes: [
      { trait_type: "Class", value: CLASS_NAMES[t.classIdx] ?? "Unknown" },
      { trait_type: "Rarity", value: RARITY_NAMES[rarity] ?? String(rarity) },
      { trait_type: "Body", value: label },
      { trait_type: "Face", value: t.faceIdx },
      { trait_type: "Item", value: t.itemIdx },
    ],
  });
}
