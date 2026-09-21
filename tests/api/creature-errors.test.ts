import { beforeEach, describe, expect, it, vi } from "vitest";
import type { VercelRequest, VercelResponse } from "@vercel/node";
import { HttpRequestError } from "viem";

const { readContract } = vi.hoisted(() => ({ readContract: vi.fn() }));
vi.mock("viem", async (original) => ({
  ...await original<typeof import("viem")>(),
  createPublicClient: () => ({ readContract }),
}));
import handler from "../../api/cauldron/creature";

function response() {
  const res = { setHeader: vi.fn(), status: vi.fn(), json: vi.fn() };
  res.status.mockReturnValue(res);
  res.json.mockReturnValue(res);
  return res;
}

describe("public creature metadata error boundary", () => {
  beforeEach(() => { readContract.mockReset(); });

  it("does not publish RPC URLs or embedded credentials", async () => {
    // The actual pinned viem error class preserves path/query API keys.
    // This is a synthetic credential and no network request occurs.
    const error = new HttpRequestError({
      url: "https://rpc.invalid/SYNTHETIC_API_KEY",
      status: 503,
      details: "local transport fixture",
    });
    expect(error.message.slice(0, 160)).toContain("SYNTHETIC_API_KEY");
    readContract.mockRejectedValue(error);
    const res = response();
    await handler({ url: "/api/cauldron/creature/0/1", query: {} } as VercelRequest, res as unknown as VercelResponse);
    expect(readContract).toHaveBeenCalledTimes(1);
    expect(res.status).toHaveBeenCalledWith(200);
    const body = res.json.mock.calls[0][0];
    expect(body.art_unavailable).toBe("chain read failed");
    expect(JSON.stringify(body)).not.toContain("SYNTHETIC_API_KEY");
    expect(JSON.stringify(body)).not.toContain("rpc.invalid");
    expect(body.image).toBeUndefined();
  });

  it("preserves the ordinary sealed-token response", async () => {
    readContract.mockResolvedValue(false);
    const res = response();
    await handler({ url: "/api/cauldron/creature/0/1", query: {} } as VercelRequest, res as unknown as VercelResponse);
    expect(readContract).toHaveBeenCalledTimes(1);
    expect(res.json.mock.calls[0][0].name).toBe("Sealed Crystal #1");
    expect(res.json.mock.calls[0][0].art_unavailable).toBeUndefined();
  });
});
