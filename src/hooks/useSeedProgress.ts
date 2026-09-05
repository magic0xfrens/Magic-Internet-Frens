import { useCallback, useState } from "react";
import { usePublicClient } from "wagmi";
import type { Address } from "viem";
import { CAULDRON } from "@/config/cauldron";
import { usePoll } from "@/hooks/usePoll";

const SEEDER_ABI = [
  { type: "function", name: "deployedWad", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "isComplete", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "seeding", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "rangeCount", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "window", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "startTs", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
] as const;

export interface SeedProgress {
  /** Fraction of the stream budget actually placed, 0..1. */
  placed: number;
  /** Where the schedule says it SHOULD be by now, 0..1. */
  target: number;
  active: boolean;
  complete: boolean;
  /** Mini-positions minted so far. */
  ranges: number;
  /** Seconds until the window closes, or 0. */
  remaining: number;
}

/**
 * Live progress of the progressive liquidity seed.
 *
 * A generation does not launch with all its depth at once: the seeder streams it
 * in over a window, in slivers placed by real swaps. Nothing on the page showed
 * that, so a fresh brew looked thin and broken rather than filling.
 *
 * `placed` and `target` are deliberately separate. The stream only advances when
 * someone POKES it, and the poke rides inside a swap — so on a quiet pool the
 * schedule runs ahead of what is actually deployed. Showing only one number
 * would hide that the pool is waiting on trade flow, which is the single most
 * useful thing to know while staring at a new launch.
 */
export function useSeedProgress(): SeedProgress {
  const pc = usePublicClient({ chainId: CAULDRON.chainId });
  const [s, setS] = useState<SeedProgress>({
    placed: 0, target: 0, active: false, complete: false, ranges: 0, remaining: 0,
  });

  const load = useCallback(async () => {
    const seeder = (CAULDRON as Record<string, unknown>).seeder as Address | undefined;
    if (!pc || !seeder) return;
    try {
      const base = { address: seeder, abi: SEEDER_ABI } as const;
      const [placedWad, complete, active, ranges, win, start] = await Promise.all([
        pc.readContract({ ...base, functionName: "deployedWad" }),
        pc.readContract({ ...base, functionName: "isComplete" }),
        pc.readContract({ ...base, functionName: "seeding" }),
        pc.readContract({ ...base, functionName: "rangeCount" }),
        pc.readContract({ ...base, functionName: "window" }),
        pc.readContract({ ...base, functionName: "startTs" }),
      ]);

      // The contract's own schedule: elapsed/window, clamped. Recomputed here
      // rather than read, because it changes every second and polling it would
      // be a request per tick for a number the client can derive.
      const now = Math.floor(Date.now() / 1000);
      const elapsed = Number(start) > 0 ? now - Number(start) : 0;
      const w = Number(win) || 1;
      const target = Math.min(1, Math.max(0, elapsed / w));

      setS({
        placed: Number(placedWad) / 1e18,
        target,
        active: active && !complete,
        complete,
        ranges: Number(ranges),
        remaining: Math.max(0, w - elapsed),
      });
    } catch {
      // A deployment without a seeder (atomic launch) simply has no progress.
    }
  }, [pc]);

  // 8s: slivers land on swaps, not on a timer, so faster polling would mostly
  // re-read an unchanged number.
  usePoll(load, 8_000);
  return s;
}
