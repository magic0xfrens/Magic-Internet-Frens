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

import { timingSafeEqual, createHash } from "node:crypto";

const DB = process.env.DATABASE_URL || "";
const ADMIN_SECRET = process.env.FREN_ADMIN_SECRET || "";

/**
 * Compare in constant time, over fixed-width digests.
 *
 * `===` on the raw strings leaks length and first-difference position through
 * timing, and `timingSafeEqual` throws when the buffers differ in length — which
 * would leak the length by itself. Hashing both sides first gives two 32-byte
 * buffers whatever the input, so the comparison is total and constant-time.
 */
function secretMatches(provided: string): boolean {
  const a = createHash("sha256").update(provided).digest();
  const b = createHash("sha256").update(ADMIN_SECRET).digest();
  return timingSafeEqual(a, b);
}

/**
 * Throttle failed attempts per IP. This is an unauthenticated brute-force
 * surface — the only thing standing in front of a write path that feeds
 * AUTHORITATIVE CORRECTIONS straight into the Guide's system prompt — and it
 * previously had no rate limit at all.
 *
 * In-memory, so per warm instance rather than global; that is honest about what
 * a serverless function can enforce alone, and it still turns an unbounded
 * guessing loop into a slow one. Real distributed limiting belongs in the WAF.
 */
const FAIL_WINDOW_MS = 60_000;
const FAIL_MAX = 5;
const failures = new Map<string, number[]>();

function clientIp(req: VercelRequest): string {
  //  DO NOT trust the LEFTMOST x-forwarded-for value (audit Q-06). A client sets
  //  the request headers, and platform proxies APPEND their observation rather
  //  than replace it — so `x-forwarded-for.split(",")[0]` is attacker-chosen and
  //  rotating it per request gives every guess a fresh throttle bucket, defeating
  //  the rate limit entirely. Prefer the platform-set `x-real-ip` (which the edge
  //  overwrites and the client cannot forge); fall back to the RIGHTMOST
  //  x-forwarded-for hop (the one our own proxy added), never the leftmost.
  const real = (req.headers["x-real-ip"] as string) || "";
  if (real.trim()) return real.trim();
  const fwd = (req.headers["x-forwarded-for"] as string) || "";
  const hops = fwd.split(",").map((s) => s.trim()).filter(Boolean);
  return hops[hops.length - 1] || (req.socket?.remoteAddress ?? "unknown");
}

function throttled(ip: string): boolean {
  const now = Date.now();
  const hits = (failures.get(ip) ?? []).filter((t) => now - t < FAIL_WINDOW_MS);
  failures.set(ip, hits);
  if (failures.size > 5000) {
    failures.forEach((v, k) => {
      if (v.every((t) => now - t >= FAIL_WINDOW_MS)) failures.delete(k);
    });
  }
  return hits.length >= FAIL_MAX;
}

function noteFailure(ip: string) {
  const now = Date.now();
  const hits = (failures.get(ip) ?? []).filter((t) => now - t < FAIL_WINDOW_MS);
  hits.push(now);
  failures.set(ip, hits);
}

function authed(req: VercelRequest): boolean {
  if (!ADMIN_SECRET) return false; // must be configured to enable teaching
  const provided = (req.headers["x-fren-admin"] as string) || "";
  return provided.length > 0 && secretMatches(provided);
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
  const ip = clientIp(req);
  if (throttled(ip)) {
    res.setHeader("Retry-After", "60");
    res.status(429).json({ error: "too_many_attempts" });
    return;
  }
  if (!authed(req)) {
    noteFailure(ip);
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
