import type { VercelRequest, VercelResponse } from "@vercel/node";
import { neon } from "@neondatabase/serverless";

/**
 * /api/fren-teach  — owner-only memory writer for the Cauldron Guide.
 *
 * POST { question, answer }  with header  x-fren-admin: <FREN_ADMIN_SECRET>
 *   → saves an AUTHORITATIVE correction that /api/fren-ask injects into future
 *     prompts (the "if the answer isn't what I want, add it to memory" loop).
 *
 * GET  (with the admin header)  → lists saved corrections (for review).
 * DELETE { id }  (with the admin header)  → removes one.
 *
 * Access: gated by a shared secret in the FREN_ADMIN_SECRET env var. Only you
 * (whoever holds the secret) can teach — random users can't poison the memory.
 */

const DB = process.env.DATABASE_URL || "";
const ADMIN_SECRET = process.env.FREN_ADMIN_SECRET || "";

function authed(req: VercelRequest): boolean {
  if (!ADMIN_SECRET) return false; // must be configured to enable teaching
  const provided = (req.headers["x-fren-admin"] as string) || "";
  return provided.length > 0 && provided === ADMIN_SECRET;
}

async function ensureTable(sql: ReturnType<typeof neon>) {
  await sql`
    CREATE TABLE IF NOT EXISTS fren_corrections (
      id SERIAL PRIMARY KEY,
      question TEXT NOT NULL,
      answer   TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT now()
    )
  `;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (!DB) {
    res.status(500).json({ error: "no_database" });
    return;
  }
  if (!ADMIN_SECRET) {
    res.status(503).json({ error: "teaching_disabled", hint: "set FREN_ADMIN_SECRET" });
    return;
  }
  if (!authed(req)) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }

  const sql = neon(DB);
  try {
    await ensureTable(sql);

    if (req.method === "GET") {
      const rows = await sql`
        SELECT id, question, answer, created_at FROM fren_corrections
        ORDER BY created_at DESC LIMIT 200
      `;
      res.status(200).json({ corrections: rows });
      return;
    }

    const body = typeof req.body === "string" ? JSON.parse(req.body || "{}") : req.body || {};

    if (req.method === "DELETE") {
      const id = Number(body.id);
      if (!id) {
        res.status(400).json({ error: "id required" });
        return;
      }
      await sql`DELETE FROM fren_corrections WHERE id = ${id}`;
      res.status(200).json({ ok: true });
      return;
    }

    if (req.method === "POST") {
      const question = String(body.question || "").slice(0, 800).trim();
      const answer = String(body.answer || "").slice(0, 4000).trim();
      if (!question || !answer) {
        res.status(400).json({ error: "question and answer required" });
        return;
      }
      const [row] = await sql`
        INSERT INTO fren_corrections (question, answer)
        VALUES (${question}, ${answer})
        RETURNING id
      `;
      res.status(200).json({ ok: true, id: (row as { id: number }).id });
      return;
    }

    res.status(405).json({ error: "method_not_allowed" });
  } catch (e) {
    res.status(500).json({ error: "db_error", detail: String((e as Error).message).slice(0, 200) });
  }
}
