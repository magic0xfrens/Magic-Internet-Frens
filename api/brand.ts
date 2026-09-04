import type { VercelRequest, VercelResponse } from "@vercel/node";
import { neon } from "@neondatabase/serverless";

/**
 * /api/brand — per-iteration PFP + banner (and website) for the Cauldron
 * profile card. Kept OUT of the Ponder indexer (which resets on reindex): this
 * is user content, stored in its own Neon table that persists.
 *
 *   GET  /api/brand?gen=1            → { logo, banner, website }
 *   POST /api/brand  { gen, logo, banner, website, sig? }
 *
 * `logo`/`banner` are data URLs (base64) or hosted URLs. Small PFP/banners fit
 * comfortably; for production you'd swap to a blob store + store the URL.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") return res.status(204).end();

  const dbUrl = process.env.DATABASE_URL;
  if (!dbUrl) return res.status(200).json({ logo: null, banner: null, website: null });
  const sql = neon(dbUrl);
  await sql`CREATE TABLE IF NOT EXISTS cauldron_brand (
    gen INT PRIMARY KEY, logo TEXT, banner TEXT, website TEXT, updated_at BIGINT
  )`;

  if (req.method === "GET") {
    const gen = Number((req.query.gen as string) ?? "0");
    res.setHeader("Cache-Control", "public, s-maxage=30, stale-while-revalidate=120");
    const rows = await sql`SELECT logo, banner, website FROM cauldron_brand WHERE gen = ${gen}`;
    const b = rows[0] as { logo?: string; banner?: string; website?: string } | undefined;
    return res.status(200).json({ logo: b?.logo ?? null, banner: b?.banner ?? null, website: b?.website ?? null });
  }

  if (req.method === "POST") {
    const { gen, logo, banner, website } = req.body ?? {};
    if (typeof gen !== "number") return res.status(400).json({ error: "gen required" });
    // basic size guard (data URLs): ~2.5MB each
    if ((logo && logo.length > 3_500_000) || (banner && banner.length > 3_500_000)) {
      return res.status(413).json({ error: "image too large (max ~2.5MB)" });
    }
    await sql`
      INSERT INTO cauldron_brand (gen, logo, banner, website, updated_at)
      VALUES (${gen}, ${logo ?? null}, ${banner ?? null}, ${website ?? null}, ${Date.now()})
      ON CONFLICT (gen) DO UPDATE SET
        logo = COALESCE(EXCLUDED.logo, cauldron_brand.logo),
        banner = COALESCE(EXCLUDED.banner, cauldron_brand.banner),
        website = COALESCE(EXCLUDED.website, cauldron_brand.website),
        updated_at = EXCLUDED.updated_at
    `;
    return res.status(200).json({ ok: true });
  }

  return res.status(405).json({ error: "method not allowed" });
}
