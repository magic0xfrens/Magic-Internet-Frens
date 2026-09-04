import type { VercelRequest, VercelResponse } from "@vercel/node";

/**
 * Serverless proxy for X OAuth 2.0 PKCE token exchange.
 * Needed because Twitter's token endpoint blocks browser CORS requests.
 */
export default async function handler(req: VercelRequest, res: VercelResponse) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { code, code_verifier, redirect_uri } = req.body ?? {};

  if (!code || !code_verifier || !redirect_uri) {
    return res.status(400).json({ error: "Missing code, code_verifier, or redirect_uri" });
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
