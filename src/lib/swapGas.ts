export const SWAP_GAS_FLOOR = 8_000_000n;
export const SWAP_GAS_BUFFER_BPS = 2_000n; // 20% inclusion/state headroom

/** Buffer a successful estimate while retaining the existing liquidation floor. */
export function bufferedSwapGas(
  estimate: bigint,
  floor = SWAP_GAS_FLOOR,
  bufferBps = SWAP_GAS_BUFFER_BPS,
): bigint {
  if (estimate <= 0n) throw new Error("RPC returned an invalid swap gas estimate");
  const buffered = (estimate * (10_000n + bufferBps) + 9_999n) / 10_000n;
  return buffered > floor ? buffered : floor;
}

/**
 * Bind estimation to the intended chain and propagate RPC/simulation failures.
 * The callback contains the exact account + calldata + value request submitted
 * by the caller, so this helper cannot silently estimate a cheaper surrogate.
 */
export async function estimateBufferedSwapGas(
  clientChainId: number | undefined,
  expectedChainId: number,
  estimateExactRequest: () => Promise<bigint>,
): Promise<bigint> {
  if (clientChainId !== expectedChainId) {
    throw new Error("Swap RPC is unavailable on the configured chain");
  }
  return bufferedSwapGas(await estimateExactRequest());
}

/** Attach the identity and chain used for estimation to the wallet write. */
export function pinSwapWrite<T extends object, A extends string>(
  request: T, account: A, chainId: number, gas: bigint,
) {
  return { ...request, account, chainId, gas } as const;
}
