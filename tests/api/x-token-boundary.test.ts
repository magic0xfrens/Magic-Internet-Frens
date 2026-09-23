import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { VercelRequest, VercelResponse } from "@vercel/node";

const redirect = "https://app.invalid/callback";
function response() {
  const res = { status: vi.fn(), json: vi.fn(), setHeader: vi.fn() };
  res.status.mockReturnValue(res);
  res.json.mockReturnValue(res);
  return res;
}
function request(overrides = {}) {
  return {
    method: "POST", headers: { "x-real-ip": "192.0.2.1" },
    body: { code: "synthetic-code", code_verifier: "synthetic-verifier", redirect_uri: redirect },
    ...overrides,
  } as unknown as VercelRequest;
}

describe("X token exchange local trust boundary", () => {
  beforeEach(() => {
    vi.resetModules();
    vi.stubEnv("X_REDIRECT_URIS", redirect);
    vi.stubEnv("VITE_X_CLIENT_ID", "synthetic-client");
    vi.stubEnv("X_CLIENT_SECRET", "synthetic-secret");
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("unexpected local fetch")));
  });
  afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });

  it("rejects unsupported methods without using provider credentials", async () => {
    const { default: handler } = await import("../../api/x-token");
    const res = response();
    await handler(request({ method: "GET" }), res as unknown as VercelResponse);
    expect(res.status).toHaveBeenCalledWith(405);
    expect(fetch).not.toHaveBeenCalled();
  });

  it("requires an exact allowed redirect before contacting the provider", async () => {
    const { default: handler } = await import("../../api/x-token");
    const res = response();
    await handler(request({ body: { code: "c", code_verifier: "v", redirect_uri: `${redirect}.evil.invalid` } }), res as unknown as VercelResponse);
    expect(res.status).toHaveBeenCalledWith(400);
    expect(fetch).not.toHaveBeenCalled();
  });

  it("fails closed when no redirects are configured", async () => {
    vi.stubEnv("X_REDIRECT_URIS", "");
    const { default: handler } = await import("../../api/x-token");
    const res = response();
    await handler(request(), res as unknown as VercelResponse);
    expect(res.status).toHaveBeenCalledWith(503);
    expect(fetch).not.toHaveBeenCalled();
  });

  it("uses the configured credentials only at the fixed token endpoint", async () => {
    vi.mocked(fetch).mockResolvedValueOnce(new Response(JSON.stringify({ access_token: "synthetic-token" })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ data: { id: "synthetic-user" } })));
    const { default: handler } = await import("../../api/x-token");
    const res = response();
    await handler(request(), res as unknown as VercelResponse);
    expect(fetch).toHaveBeenCalledTimes(2);
    expect(vi.mocked(fetch).mock.calls[0][0]).toBe("https://api.x.com/2/oauth2/token");
    const init = vi.mocked(fetch).mock.calls[0][1]!;
    expect(new URLSearchParams(init.body as string).get("redirect_uri")).toBe(redirect);
    expect(new Headers(init.headers).get("Authorization")).toBe(`Basic ${Buffer.from("synthetic-client:synthetic-secret").toString("base64")}`);
    expect(res.json).toHaveBeenCalledWith({ access_token: "synthetic-token", user: { id: "synthetic-user" } });
  });

  it("does not give rotated leftmost forwarding headers fresh rate-limit buckets", async () => {
    const { default: handler } = await import("../../api/x-token");
    for (let i = 0; i < 11; i++) {
      const res = response();
      await handler(request({ headers: { "x-forwarded-for": `198.51.100.${i}, 192.0.2.2` }, body: {} }), res as unknown as VercelResponse);
      expect(res.status).toHaveBeenCalledWith(i < 10 ? 400 : 429);
      if (i === 10) expect(res.setHeader).toHaveBeenCalledWith("Retry-After", "60");
    }
    expect(fetch).not.toHaveBeenCalled();
  });
});
