import { describe, expect, test, vi } from "vitest";
import { bufferedSwapGas, estimateBufferedSwapGas, pinSwapWrite, SWAP_GAS_FLOOR } from "./swapGas";

describe("swap gas selection", () => {
  test("retains the eight million floor for ordinary estimates", () => {
    expect(bufferedSwapGas(5_000_000n)).toBe(SWAP_GAS_FLOOR);
  });

  test("buffers a large-book estimate instead of clipping it to the old limit", () => {
    expect(bufferedSwapGas(10_000_001n)).toBe(12_000_002n);
  });

  test("estimates the supplied exact request once and propagates simulation failure", async () => {
    const ok = vi.fn(async () => 12_000_000n);
    await expect(estimateBufferedSwapGas(11155111, 11155111, ok)).resolves.toBe(14_400_000n);
    expect(ok).toHaveBeenCalledOnce();

    const failed = vi.fn(async () => { throw new Error("execution reverted"); });
    await expect(estimateBufferedSwapGas(11155111, 11155111, failed)).rejects.toThrow("execution reverted");
  });

  test("rejects the wrong RPC chain without making an estimate", async () => {
    const estimate = vi.fn(async () => 1n);
    await expect(estimateBufferedSwapGas(1, 11155111, estimate)).rejects.toThrow("configured chain");
    expect(estimate).not.toHaveBeenCalled();
  });

  test("pins the estimated account and chain onto the wallet request", () => {
    const request = { functionName: "play" as const, value: 3n };
    expect(pinSwapWrite(request, "0xabc", 11155111, 12_000_000n)).toEqual({
      functionName: "play", value: 3n, account: "0xabc", chainId: 11155111, gas: 12_000_000n,
    });
  });
});
