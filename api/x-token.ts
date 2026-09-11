import type { VercelRequest, VercelResponse } from "@vercel/node";

/**
 * Serverless proxy for X OAuth 2.0 PKCE token exchange.
 * Needed because Twitter's token endpoint blocks browser CORS requests.
 *
 * It holds X_CLIENT_SECRET, and it took ANY `redirect_uri` from the request
 * body and forwarded it, unthrottled, with our client credentials attached.
 * Upstream validation plus PKCE keep that from minting a token for someone
 * else's app, but it still made this an open, unmetered exchange endpoint
 * running on our secret. `redirect_uri` is now checked against an allowlist
 * before the call is made, and the route is rate-limited per IP.
 */

/** Exact redirect URIs this deployment is registered for. */
const REDIRECT_ALLOWLIST = (process.env.X_REDIRECT_URIS || "")
  .split(",").map((s) => s.trim()).filter(Boolean);

const RL_WINDOW_MS = 60_000;
const RL_MAX = 10;
const hits = new Map<string, number[]>();

/** Never the LEFTMOST x-forwarded-for: a client sets its own headers and the
 *  proxy APPENDS, so the leftmost hop is attacker-chosen and rotating it hands
 *  every request a fresh bucket. Same reasoning as api/fren-teach.ts. */
function clientIp(req: VercelRequest): string {
  const real = (req.headers["x-real-ip"] as string) || "";
  if (real.trim()) return real.trim();
  const fwd = (req.headers["x-forwarded-for"] as string) || "";
  const hops = fwd.split(",").map((s) => s.trim()).filter(Boolean);
  return hops[hops.length - 1] || (req.socket?.remoteAddress ?? "unknown");
}

function rateLimited(req: VercelRequest): boolean {
  const ip = clientIp(req);
  const now = Date.now();
  const seen = (hits.get(ip) ?? []).filter((t) => now - t < RL_WINDOW_MS);
  seen.push(now);
  hits.set(ip, seen);
  if (hits.size > 5000) hits.forEach((v, k) => { if (v.every((t) => now - t >= RL_WINDOW_MS)) hits.delete(k); });
  return seen.length > RL_MAX;
}
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  if (rateLimited(req)) {
    res.setHeader("Retry-After", "60");
    return res.status(429).json({ error: "Too many token exchanges" });
  }

  const { code, code_verifier, redirect_uri } = req.body ?? {};

  if (!code || !code_verifier || !redirect_uri) {
    return res.status(400).json({ error: "Missing code, code_verifier, or redirect_uri" });
  }
  if (!REDIRECT_ALLOWLIST.length) {
    return res.status(503).json({ error: "Server misconfigured", hint: "set X_REDIRECT_URIS" });
  }
  if (!REDIRECT_ALLOWLIST.includes(String(redirect_uri))) {
    return res.status(400).json({ error: "redirect_uri not allowed" });
  }

  const clientId = process.env.VITE_X_CLIENT_ID;
  const clientSecret = process.env.X_CLIENT_SECRET;

  if (!clientId || !clientSecret) {
    return res.status(500).json({ error: "Server misconfigured" });
  }

  try {
    const tokenRes = await fetch("https://api.x.com/2/oauth2/token", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Authorization: `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString("base64")}`,
      },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        code,
        code_verifier,
        redirect_uri,
        client_id: clientId,
      }).toString(),
    });

    const data = await tokenRes.json();

    if (!tokenRes.ok) {
      return res.status(tokenRes.status).json(data);
    }

    // Fetch user profile
    const userRes = await fetch("https://api.x.com/2/users/me?user.fields=profile_image_url,username", {
      headers: { Authorization: `Bearer ${data.access_token}` },
    });

    const userData = await userRes.json();

    return res.status(200).json({
      access_token: data.access_token,
      user: userData.data ?? null,
    });
  } catch (err) {
    return res.status(500).json({ error: "Token exchange failed" });
  }
}
