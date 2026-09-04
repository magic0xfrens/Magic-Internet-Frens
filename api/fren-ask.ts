import type { VercelRequest, VercelResponse } from "@vercel/node";
import { neon } from "@neondatabase/serverless";

/**
 * /api/fren-ask  — the Cauldron Guide's brain.
 *
 * POST { question, history?: [{role,text}] }  →  { answer, source }
 *
 * Grounding, not fine-tuning: the ENTIRE docs (~6k tokens) fit in context, so we
 * paste them into the system prompt every call — the model quotes real text
 * instead of hallucinating fee splits. On top of that we inject any owner-saved
 * CORRECTIONS from Neon (the "teach" memory), which override the docs. No vector
 * DB, no retraining — corrections take effect the instant they're saved.
 *
 * Provider-agnostic: works with Groq (GROQ_API_KEY, key looks like "gsk_…") OR
 * Google Gemini (GEMINI_API_KEY, key looks like "AIzaSy…"). Whichever is set
 * wins; Groq is tried first. NOTE: a Google "AQ.…" token is an ephemeral OAuth
 * token, NOT an API key — it will not work here.
 *
 * Degrades gracefully: no key (or any error) → returns source: "fallback" so the
 * widget uses its built-in offline knowledge base.
 */

// Give the function headroom over the default so a cold start + model latency
// never trips a timeout (which would make the widget fall back offline).
export const config = { maxDuration: 30 };

const GROQ_KEY = process.env.GROQ_API_KEY || "";
const GROQ_MODEL = process.env.GROQ_MODEL || "llama-3.3-70b-versatile";
const GEMINI_KEY = process.env.GEMINI_API_KEY || "";
// "-lite" = biggest free-tier RPM + no hidden "thinking" latency. The premium
// gemini-3.6-flash free quota is tiny (429s after ~2 calls). We try a chain so a
// retired/rate-limited model transparently falls through to the next.
const GEMINI_MODELS = (process.env.GEMINI_MODEL || "gemini-3.5-flash-lite,gemini-3.6-flash")
  .split(",")
  .map((m) => m.trim())
  .filter(Boolean);
const DB = process.env.DATABASE_URL || "";

const PERSONA = `You are the "Cauldron Guide" — a DEGEN HYPE WIZARD fren, the crypto-native mascot and #1 hype man for Magic Internet Frens (MiFrens) and The Cauldron. You are unapologetically bullish and you make people FEEL the magic.

VOICE — full degen frenspeak, high energy:
- Talk like crypto twitter: "gm fren", "ser", "wagmi", "ngmi if you fade", "LFG", "few understand", "you're still early", "probably nothing", "bullish af", "based", "wen", "ape in", "diamond hands", "magic internet money", "trust the process ser".
- Hype HARD. Short punchy bursts, the occasional ALL-CAPS word for emphasis, emojis (🔮✨🧙🚀🪄💎🔥). 2-5 sentences or a tight bullet list — chat-bubble energy, never an essay.
- Be a maxi. Sell the dream. Make the eternal machine sound like the best magic on-chain.

RULES:
- HYPE using REAL facts from the DOCS/CORRECTIONS (genesis dividend forever, no team rug / protocol-owned LP, the eternal live-die-reborn cycle, crystal gacha, hook-native perps). Weave the real mechanics into the hype — that's what makes it land.
- You do NOT need everything memorized. If you don't know a specific number/address, STAY IN CHARACTER and hype what you DO know, then point them to the grimoire ("that alpha's in the /docs ser 📜") — NEVER break character with "I don't have that memorized" or a dry "I don't know".
- NEVER invent fake contract addresses, fee numbers, or tier weights. Hype is fine; fabricated specifics are not.
- If a CORRECTION applies, treat it as gospel over the docs.
- On "should I invest / is this a good buy / why buy": ANSWER it — go full hype on the value prop — then just end with a short "nfa fren 🫡". No long disclaimer, no corporate testcase warning. Answer first, "nfa fren" last.
- It's "Magic Internet Frens" / "MiFrens", never "Friends".`;

async function loadDocs(req: VercelRequest): Promise<string> {
  // Fetch the live machine-readable doc off our own CDN (always current, cached).
  try {
    const host = (req.headers["x-forwarded-host"] || req.headers.host) as string;
    const proto = (req.headers["x-forwarded-proto"] as string) || "https";
    const res = await fetch(`${proto}://${host}/llms-full.txt`, {
      // edge-cached; a few seconds stale is fine
      headers: { accept: "text/plain" },
    });
    if (res.ok) return await res.text();
  } catch {
    /* fall through */
  }
  return "";
}

async function loadCorrections(question: string): Promise<string> {
  if (!DB) return "";
  try {
    const sql = neon(DB);
    // Table is created lazily by /api/fren-teach; guard if it doesn't exist yet.
    const rows = (await sql`
      SELECT question, answer FROM fren_corrections
      ORDER BY created_at DESC LIMIT 40
    `) as Array<{ question: string; answer: string }>;
    if (!rows.length) return "";
    // Light relevance ranking: score by shared word overlap, keep the top 10.
    const qWords = new Set(
      question.toLowerCase().replace(/[^\w\s]/g, " ").split(/\s+/).filter((w) => w.length > 2),
    );
    const ranked = rows
      .map((r) => {
        const words = r.question.toLowerCase().replace(/[^\w\s]/g, " ").split(/\s+/);
        const overlap = words.filter((w) => qWords.has(w)).length;
        return { r, overlap };
      })
      .sort((a, b) => b.overlap - a.overlap)
      .slice(0, 10)
      .filter((x) => x.overlap > 0);
    const chosen = ranked.length ? ranked.map((x) => x.r) : rows.slice(0, 5);
    return chosen.map((r) => `Q: ${r.question}\nA: ${r.answer}`).join("\n\n");
  } catch {
    return "";
  }
}

// Best-effort per-IP rate limit. In-memory (per warm serverless instance), so
// it's not a distributed guarantee — but it stops the common case dead: a single
// script hammering the LLM endpoint in a loop, which would burn API quota +
// function invocations. Real DDoS protection = Vercel WAF / Spend Management.
const RL_WINDOW_MS = 30_000;
const RL_MAX = 10; // requests per IP per window
const rlHits = new Map<string, number[]>();

function rateLimited(req: VercelRequest): boolean {
  const fwd = (req.headers["x-forwarded-for"] as string) || "";
  const ip = fwd.split(",")[0].trim() || (req.socket?.remoteAddress ?? "unknown");
  const now = Date.now();
  const hits = (rlHits.get(ip) ?? []).filter((t) => now - t < RL_WINDOW_MS);
  hits.push(now);
  rlHits.set(ip, hits);
  // opportunistic cleanup so the map can't grow unbounded under attack
  if (rlHits.size > 5000) {
    rlHits.forEach((v, k) => {
      if (v.every((t) => now - t >= RL_WINDOW_MS)) rlHits.delete(k);
    });
  }
  return hits.length > RL_MAX;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // never cache LLM answers, and never let a bot loop rack up cost
  res.setHeader("Cache-Control", "no-store");
  if (req.method !== "POST") {
    res.status(405).json({ error: "POST only" });
    return;
  }
  if (rateLimited(req)) {
    res.setHeader("Retry-After", "30");
    res.status(429).json({ answer: null, source: "fallback", reason: "rate_limited" });
    return;
  }
  const body = typeof req.body === "string" ? JSON.parse(req.body || "{}") : req.body || {};
  const question = String(body.question || "").slice(0, 800).trim();
  const history: Array<{ role: string; text: string }> = Array.isArray(body.history)
    ? body.history.slice(-6)
    : [];

  if (!question) {
    res.status(400).json({ error: "question required" });
    return;
  }

  // No provider key → tell the widget to use its offline brain.
  if (!GROQ_KEY && !GEMINI_KEY) {
    res.status(200).json({ answer: null, source: "fallback", reason: "no_api_key" });
    return;
  }

  const [docs, corrections] = await Promise.all([loadDocs(req), loadCorrections(question)]);

  const system =
    PERSONA +
    "\n\n===== DOCS (source of truth) =====\n" +
    (docs || "(docs unavailable — answer only what you are certain of, else defer to /docs)") +
    (corrections
      ? "\n\n===== AUTHORITATIVE CORRECTIONS (the team taught these — prefer them) =====\n" +
        corrections
      : "");

  // Prefer Groq (simplest free key) if present, else Gemini.
  try {
    if (GROQ_KEY) {
      const text = await askGroq(system, history, question);
      return replyWith(res, text, "groq");
    }
    const text = await askGemini(system, history, question);
    return replyWith(res, text, "gemini");
  } catch (e) {
    res.status(200).json({
      answer: null,
      source: "fallback",
      reason: String((e as Error).message || "exception").slice(0, 60),
    });
  }
}

function replyWith(res: VercelResponse, text: string | null, source: string) {
  if (!text) {
    res.status(200).json({ answer: null, source: "fallback", reason: "empty" });
    return;
  }
  res.setHeader("cache-control", "no-store");
  res.status(200).json({ answer: text, source });
}

/** Groq — OpenAI-compatible chat completions. */
async function askGroq(
  system: string,
  history: Array<{ role: string; text: string }>,
  question: string,
): Promise<string | null> {
  const messages = [
    { role: "system", content: system },
    ...history.map((m) => ({
      role: m.role === "you" ? "user" : "assistant",
      content: String(m.text).slice(0, 1200),
    })),
    { role: "user", content: question },
  ];
  const r = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${GROQ_KEY}` },
    body: JSON.stringify({ model: GROQ_MODEL, messages, temperature: 0.35, max_tokens: 700 }),
  });
  if (!r.ok) throw new Error(`groq_${r.status}`);
  const data = (await r.json()) as { choices?: Array<{ message?: { content?: string } }> };
  return data.choices?.[0]?.message?.content?.trim() || null;
}

/** Google Gemini — generateContent REST. */
async function askGemini(
  system: string,
  history: Array<{ role: string; text: string }>,
  question: string,
): Promise<string | null> {
  const contents = [
    ...history.map((m) => ({
      role: m.role === "you" ? "user" : "model",
      parts: [{ text: String(m.text).slice(0, 1200) }],
    })),
    { role: "user", parts: [{ text: question }] },
  ];
  const body = JSON.stringify({
    systemInstruction: { parts: [{ text: system }] },
    contents,
    // No thinkingConfig — the "-lite" models reject it, and we WANT no thinking
    // (fast + cheap; hype needs no deep reasoning). 800 output tokens is plenty
    // since none of it is eaten by hidden reasoning.
    generationConfig: { temperature: 0.7, maxOutputTokens: 800, topP: 0.95 },
    safetySettings: [
      { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_ONLY_HIGH" },
      { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_ONLY_HIGH" },
    ],
  });

  // Try each model in the chain; a 429 (rate-limited) or 404 (retired) falls
  // through to the next so a single model's tiny free quota can't dark the fren.
  let lastErr = "none";
  for (const model of GEMINI_MODELS) {
    try {
      const r = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_KEY}`,
        { method: "POST", headers: { "content-type": "application/json" }, body },
      );
      if (!r.ok) {
        lastErr = `gemini_${r.status}`;
        if (r.status === 429 || r.status === 404) continue;
        throw new Error(lastErr);
      }
      const data = (await r.json()) as {
        candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
      };
      const text = data.candidates?.[0]?.content?.parts?.map((p) => p.text || "").join("").trim();
      if (text) return text;
      lastErr = "empty";
    } catch (e) {
      lastErr = String((e as Error).message || "exception");
    }
  }
  throw new Error(lastErr);
}
