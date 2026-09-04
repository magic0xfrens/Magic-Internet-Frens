import { useEffect, useRef, useState } from "react";
import { usePublicClient } from "wagmi";
import { parseEventLogs } from "viem";
import { useWallet } from "@/hooks/useWallet";
import { PERP, PERP_ABI } from "@/config/perp";
import { CAULDRON } from "@/config/cauldron";

export interface LiquidatoorHit {
  positionId: string;
  badgeId: string; // "0" if the collection wasn't wired for badges
}

/**
 * useLiquidatoorWatch — after ANY trade tx (a spot buy/sell that carried a
 * liqHint, or a leveraged open), fetches the receipt and checks whether it
 * liquidated someone and awarded YOU a Liquidatoor badge (`LiquidatoorAwarded`
 * emitted by the PerpEngine, `to == you`). If so, returns the hit so the UI can
 * pop the "Congrats Liquidatoor!" modal. Each txHash is inspected once.
 */
export function useLiquidatoorWatch(txHash?: `0x${string}`): { hit: LiquidatoorHit | null; ack: () => void } {
  const { walletAddress } = useWallet();
  const pc = usePublicClient({ chainId: CAULDRON.chainId });
  const [hit, setHit] = useState<LiquidatoorHit | null>(null);
  const seen = useRef<Set<string>>(new Set());

  useEffect(() => {
    if (!txHash || !pc || !walletAddress) return;
    if (seen.current.has(txHash)) return;
    seen.current.add(txHash);
    let alive = true;
    (async () => {
      try {
        const receipt = await pc.waitForTransactionReceipt({ hash: txHash, timeout: 60_000 });
        if (!alive) return;
        const logs = parseEventLogs({
          abi: PERP_ABI,
          eventName: "LiquidatoorAwarded",
          logs: receipt.logs,
        }) as Array<{ address: string; args: { id: bigint; to: string; badgeId: bigint } }>;
        const me = walletAddress.toLowerCase();
        // Only our engine's awards, credited to us.
        const mine = logs.find(
          (l) => l.address.toLowerCase() === PERP.engine.toLowerCase() && l.args.to.toLowerCase() === me,
        );
        if (mine) {
          setHit({ positionId: mine.args.id.toString(), badgeId: mine.args.badgeId.toString() });
        }
      } catch { /* receipt unavailable → skip silently */ }
    })();
    return () => { alive = false; };
  }, [txHash, pc, walletAddress]);

  return { hit, ack: () => setHit(null) };
}
