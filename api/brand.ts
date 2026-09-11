import type { VercelRequest, VercelResponse } from "@vercel/node";
import { neon } from "@neondatabase/serverless";
import { createHash } from "node:crypto";
import { recoverMessageAddress, isAddress, type Hex } from "viem";
import round from "../indexer/deployments/round.json";

/**
 * /api/brand — per-iteration PFP + banner (and website) for the Cauldron
 * profile card. Kept OUT of the Ponder indexer (which resets on reindex): this
 * is user content, stored in its own Neon table that persists.
 *
 *   GET  /api/brand?gen=1            → { logo, banner, website }
 *   POST /api/brand  { gen, logo, banner, website, ts, sig }
 *
 * ── WHY THE POST IS SIGNED ───────────────────────────────────────────────────
 * This row IS the live page's profile image and banner. The route previously
 * documented a `sig` field and never read it: the POST destructured only
 * `{ gen, logo, banner, website }`, so ANY stranger could rewrite the live
 * branding, and any `gen` at all minted a fresh row — unbounded, from the open
 * internet, with `Access-Control-Allow-Origin: *` on the write.
 *
 * The write now carries an EIP-191 signature from an address on BRAND_SIGNERS.
 * The signed message COMMITS TO THE CONTENT (sha256 of each image) and to the
 * generation and a timestamp, so a captured signature cannot be replayed onto a
 * different image, a different iteration, or an older state:
 *
 *   Cauldron brand update
 *   gen: <gen>
 *   logo: <sha256|none>
 *   banner: <sha256|none>
 *   website: <website|none>
 *   issued: <unix ms>
 *
 * Fails CLOSED: with no BRAND_SIGNERS configured there is no write path at all.
 *
 * `logo`/`banner` are data URLs (base64) or hosted URLs. Small PFP/banners fit
 * comfortably; for production you'd swap to a blob store + store the URL.
 */

const SIGNERS = (process.env.BRAND_SIGNERS || "")
  .split(",")
  .map((s) => s.trim().toLowerCase())
  .filter((s) => isAddress(s));

/** Origins allowed to POST. A browser request carrying any other Origin is
 *  refused outright, and no CORS header is ever emitted on the write path, so
 *  a cross-site page can neither send a credentialed write nor read the reply. */
const ALLOWED_ORIGINS = (process.env.BRAND_ALLOWED_ORIGINS || "")
  .split(",")
  .map((s) => s.trim().toLowerCase())
  .filter(Boolean);

/** A signature older than this is refused even if it is otherwise valid. */
const SIG_TTL_MS = 10 * 60 * 1000;
/** Row-creation bound: an accepted signer still cannot mint unbounded rows. */
const MAX_ROWS = Number(process.env.BRAND_MAX_ROWS || 256);
/** Known generations: the shipped round, plus headroom for the next few. An
 *  arbitrary `gen` is not "unknown but harmless" — it is a free table row. */
const MAX_GEN = Number(round.round ?? 1) + 16;

const digest = (v: unknown): string =>
  typeof v === "string" && v.length > 0
    ? createHash("sha256").update(v).digest("hex")
    : "none";

function validGen(gen: unknown): gen is number {
  return typeof gen === "number" && Number.isSafeInteger(gen) && gen >= 0 && gen <= MAX_GEN;
}

function brandMessage(
  gen: number,
  logo: unknown,
  banner: unknown,
  website: unknown,
  ts: number,
): string {
  return [
    "Cauldron brand update",
    `gen: ${gen}`,
    `logo: ${digest(logo)}`,
    `banner: ${digest(banner)}`,
    `website: ${typeof website === "string" && website ? website : "none"}`,
    `issued: ${ts}`,
  ].join("\n");
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method === "OPTIONS") {
    // Reads are public; writes are same-origin + signed, so the preflight
    // advertises GET only. There is deliberately no wildcard on the write.
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET,OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");
    return res.status(204).end();
  }

  const dbUrl = process.env.DATABASE_URL;

  if (req.method === "GET") {
    res.setHeader("Access-Control-Allow-Origin", "*");
    if (!dbUrl) return res.status(200).json({ logo: null, banner: null, website: null });
    const sql = neon(dbUrl);
    await sql`CREATE TABLE IF NOT EXISTS cauldron_brand (
      gen INT PRIMARY KEY, logo TEXT, banner TEXT, website TEXT, updated_at BIGINT
    )`;
    const gen = Number((req.query.gen as string) ?? "0");
    if (!validGen(gen)) return res.status(400).json({ error: "unknown gen" });
    res.setHeader("Cache-Control", "public, s-maxage=30, stale-while-revalidate=120");
    const rows = await sql`SELECT logo, banner, website FROM cauldron_brand WHERE gen = ${gen}`;
    const b = rows[0] as { logo?: string; banner?: string; website?: string } | undefined;
    return res.status(200).json({ logo: b?.logo ?? null, banner: b?.banner ?? null, website: b?.website ?? null });
  }

  if (req.method !== "POST") return res.status(405).json({ error: "method not allowed" });

  // ── write path: no CORS header, and a foreign Origin is refused ──
  const origin = (req.headers.origin as string | undefined)?.toLowerCase();
  if (origin && !ALLOWED_ORIGINS.includes(origin)) {
    return res.status(403).json({ error: "cross-origin write refused" });
  }
  if (!SIGNERS.length) {
    return res.status(503).json({ error: "branding_disabled", hint: "set BRAND_SIGNERS" });
  }
  if (!dbUrl) return res.status(500).json({ error: "no_database" });

  const body = typeof req.body === "string" ? JSON.parse(req.body || "{}") : req.body ?? {};
  const { gen, logo, banner, website, ts, sig } = body as {
    gen?: unknown; logo?: unknown; banner?: unknown; website?: unknown; ts?: unknown; sig?: unknown;
  };

  if (!validGen(gen)) return res.status(400).json({ error: "unknown gen" });
  if (typeof ts !== "number" || !Number.isSafeInteger(ts)) {
    return res.status(400).json({ error: "ts required" });
  }
  if (Math.abs(Date.now() - ts) > SIG_TTL_MS) {
    return res.status(401).json({ error: "signature expired" });
  }
  if (typeof sig !== "string" || !/^0x[0-9a-fA-F]{130}$/.test(sig)) {
    return res.status(401).json({ error: "sig required" });
  }
  // basic size guard (data URLs): ~2.5MB each
  if (
    (logo !== undefined && typeof logo !== "string") ||
    (banner !== undefined && typeof banner !== "string") ||
    (website !== undefined && typeof website !== "string")
  ) {
    return res.status(400).json({ error: "logo/banner/website must be strings" });
  }
  if (
    ((logo as string)?.length ?? 0) > 3_500_000 ||
    ((banner as string)?.length ?? 0) > 3_500_000
  ) {
    return res.status(413).json({ error: "image too large (max ~2.5MB)" });
  }

  let signer: string;
  try {
    signer = (
      await recoverMessageAddress({ message: brandMessage(gen, logo, banner, website, ts), signature: sig as Hex })
    ).toLowerCase();
  } catch {
    return res.status(401).json({ error: "bad signature" });
  }
  if (!SIGNERS.includes(signer)) return res.status(403).json({ error: "not a brand signer" });

  const sql = neon(dbUrl);
  await sql`CREATE TABLE IF NOT EXISTS cauldron_brand (
    gen INT PRIMARY KEY, logo TEXT, banner TEXT, website TEXT, updated_at BIGINT
  )`;

  // Monotonic `ts` per row: a captured payload cannot be replayed to roll the
  // branding back to an earlier state.
  const existing = (await sql`SELECT updated_at FROM cauldron_brand WHERE gen = ${gen}`)[0] as
    | { updated_at?: string | number }
    | undefined;
  if (existing) {
    if (Number(existing.updated_at ?? 0) >= ts) return res.status(409).json({ error: "stale update" });
  } else {
    const [{ n }] = (await sql`SELECT COUNT(*)::int AS n FROM cauldron_brand`) as Array<{ n: number }>;
    if (n >= MAX_ROWS) return res.status(507).json({ error: "brand table full" });
  }

  await sql`
    INSERT INTO cauldron_brand (gen, logo, banner, website, updated_at)
    VALUES (${gen}, ${(logo as string) ?? null}, ${(banner as string) ?? null}, ${(website as string) ?? null}, ${ts})
    ON CONFLICT (gen) DO UPDATE SET
      logo = COALESCE(EXCLUDED.logo, cauldron_brand.logo),
      banner = COALESCE(EXCLUDED.banner, cauldron_brand.banner),
      website = COALESCE(EXCLUDED.website, cauldron_brand.website),
      updated_at = EXCLUDED.updated_at
    WHERE cauldron_brand.updated_at < EXCLUDED.updated_at
  `;
  return res.status(200).json({ ok: true });
}
