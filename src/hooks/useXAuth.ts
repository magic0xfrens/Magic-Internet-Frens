import { useState, useCallback, useEffect } from "react";

interface XUser {
  id: string;
  name: string;
  username: string;
  profile_image_url?: string;
}

const X_CLIENT_ID = import.meta.env.VITE_X_CLIENT_ID ?? "";
const STORAGE_KEY = "mifrens_x_user";

function generateRandom(len: number): string {
  const arr = new Uint8Array(len);
  crypto.getRandomValues(arr);
  return Array.from(arr, (b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256(plain: string): Promise<string> {
  const data = new TextEncoder().encode(plain);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return btoa(String.fromCharCode(...new Uint8Array(hash)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

export function useXAuth() {
  const [xUser, setXUser] = useState<XUser | null>(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      return stored ? JSON.parse(stored) : null;
    } catch {
      return null;
    }
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const redirectUri = `${window.location.origin}/x-callback`;

  /** Start OAuth 2.0 PKCE flow */
  const connectX = useCallback(async () => {
    const state = generateRandom(16);
    const codeVerifier = generateRandom(64);
    const codeChallenge = await sha256(codeVerifier);

    // Store for callback
    sessionStorage.setItem("x_state", state);
    sessionStorage.setItem("x_code_verifier", codeVerifier);

    const params = new URLSearchParams({
      response_type: "code",
      client_id: X_CLIENT_ID,
      redirect_uri: redirectUri,
      scope: "tweet.read users.read offline.access",
      state,
      code_challenge: codeChallenge,
      code_challenge_method: "S256",
    });

    window.location.href = `https://twitter.com/i/oauth2/authorize?${params}`;
  }, [redirectUri]);

  /** Exchange auth code for token (called from callback page) */
  const handleCallback = useCallback(
    async (code: string, state: string) => {
      setLoading(true);
      setError(null);

      const savedState = sessionStorage.getItem("x_state");
      const codeVerifier = sessionStorage.getItem("x_code_verifier");

      if (state !== savedState) {
        setError("State mismatch — possible CSRF. Try again.");
        setLoading(false);
        return;
      }

      if (!codeVerifier) {
        setError("Missing code verifier. Try connecting again.");
        setLoading(false);
        return;
      }

      try {
        const res = await fetch("/api/x-token", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            code,
            code_verifier: codeVerifier,
            redirect_uri: redirectUri,
          }),
        });

        const data = await res.json();

        if (!res.ok) {
          setError(data.error ?? "Failed to connect");
          setLoading(false);
          return;
        }

        if (data.user) {
          setXUser(data.user);
          localStorage.setItem(STORAGE_KEY, JSON.stringify(data.user));
        }
      } catch {
        setError("Network error");
      } finally {
        sessionStorage.removeItem("x_state");
        sessionStorage.removeItem("x_code_verifier");
        setLoading(false);
      }
    },
    [redirectUri],
  );

  const disconnectX = useCallback(() => {
    setXUser(null);
    localStorage.removeItem(STORAGE_KEY);
  }, []);

  return { xUser, loading, error, connectX, handleCallback, disconnectX };
}
