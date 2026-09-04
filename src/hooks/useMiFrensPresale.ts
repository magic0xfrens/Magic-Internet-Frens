import { useCallback, useEffect, useState } from "react";
import { usePoll } from "@/hooks/usePoll";
import {
  useAccount,
  useReadContract,
  useSwitchChain,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { PRESALE, PRESALE_ABI } from "@/config/presale";
import { CAULDRON_INDEXER } from "@/config/cauldron";

const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

/**
 * useMiFrensPresale — mint genesis MiFrens against the live MiFrensPresale.
 *
 *  Handles chain-switch to Sepolia, exact payment (quantity * PRICE), and
 *  surfaces the on-chain minted/remaining counts so the UI reflects reality.
 */
export function useMiFrensPresale() {
  const { address, chainId } = useAccount();
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync, data: txHash, isPending, reset } = useWriteContract();
  const { isLoading: confirming, isSuccess: confirmed, data: receipt } =
    useWaitForTransactionReceipt({ hash: txHash, chainId: PRESALE.chainId });

  // Separate write flow for finalize() — the summon that launches iteration #1
  // once the guild mints out. Kept independent so its status doesn't clobber
  // the mint tx state.
  const {
    writeContractAsync: finalizeAsync,
    data: finalizeHash,
    isPending: finalizePending,
    reset: resetFinalize,
  } = useWriteContract();
  const { isLoading: finalizing, isSuccess: finalized } =
    useWaitForTransactionReceipt({ hash: finalizeHash, chainId: PRESALE.chainId });

  const common = { address: PRESALE.address, abi: PRESALE_ABI, chainId: PRESALE.chainId } as const;

  // PRIMARY: read minted/soldOut/finalized from PONDER (server-side reads with
  // rotated keys) so the homepage hero NEVER depends on the browser's flaky
  // public Sepolia RPC — that dependency was showing "0 / 1111" + hiding the
  // summon button whenever the public nodes rate-limited. Polls fast.
  const [ponder, setPonder] = useState<{ minted?: number; soldOut?: boolean; finalized?: boolean; airdropPerFren?: number; airdropTicker?: string }>({});
  const loadPresale = useCallback(async () => {
    try {
      const r = await fetch(`${INDEXER}/presale`, { signal: AbortSignal.timeout(8000) });
      if (!r.ok) return;
      setPonder(await r.json() as { minted?: number; soldOut?: boolean; finalized?: boolean; airdropPerFren?: number; airdropTicker?: string });
    } catch { /* keep last */ }
  }, []);
  // 5s -> 10s: mint counts move on human timescales, not block timescales.
  usePoll(loadPresale, 10_000, !!INDEXER);

  // FALLBACK: the direct contract reads (used only if the indexer is unset/down).
  const { data: mintedRpc, refetch: refetchMinted } = useReadContract({
    ...common, functionName: "minted", query: { refetchInterval: 5000, enabled: !INDEXER },
  });
  const { data: soldOutRpc, refetch: refetchSoldOut } = useReadContract({
    ...common, functionName: "soldOut", query: { refetchInterval: 5000, enabled: !INDEXER },
  });
  const { data: finalizedRpc, refetch: refetchFinalized } = useReadContract({
    ...common, functionName: "finalized", query: { refetchInterval: 5000, enabled: !INDEXER },
  });
  // Ponder wins; contract read is the fallback.
  const minted = ponder.minted != null ? BigInt(ponder.minted) : mintedRpc;
  const soldOut = ponder.soldOut != null ? ponder.soldOut : soldOutRpc;
  const finalizedOnchain = ponder.finalized != null ? ponder.finalized : finalizedRpc;
  const { data: myBalance, refetch: refetchBalance } = useReadContract({
    ...common,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 8000 },
  });

  /** Re-read on-chain counts (call after a mint confirms). */
  const refresh = useCallback(() => {
    refetchMinted();
    refetchSoldOut();
    refetchFinalized();
    refetchBalance();
  }, [refetchMinted, refetchSoldOut, refetchFinalized, refetchBalance]);

  /** Summon iteration #1: forward the treasury → registry.summon(). Callable by
   *  anyone once the genesis tranche is sold out. Returns the tx hash. */
  const finalize = useCallback(async (): Promise<`0x${string}`> => {
    if (chainId !== PRESALE.chainId) {
      await switchChainAsync({ chainId: PRESALE.chainId });
    }
    return finalizeAsync({ ...common, functionName: "finalize", args: [] });
  }, [chainId, switchChainAsync, finalizeAsync, common]);

  /** Mint `quantity` MiFrens with exact ETH payment. Returns the tx hash. */
  const mint = useCallback(
    async (quantity: number): Promise<`0x${string}`> => {
      if (!address) throw new Error("Connect a wallet first");
      if (chainId !== PRESALE.chainId) {
        await switchChainAsync({ chainId: PRESALE.chainId });
      }
      // EXACT bigint payment — the contract requires msg.value == PRICE * quantity
      // to the wei, so float math (parseEther(priceEth*qty)) can drift a few wei
      // and revert WrongPrice. Multiply the exact wei price by the quantity.
      const value = PRESALE.priceWei * BigInt(quantity);
      return writeContractAsync({
        ...common,
        functionName: "mint",
        args: [BigInt(quantity)],
        value,
      });
    },
    [address, chainId, switchChainAsync, writeContractAsync, common]
  );

  return {
    mint,
    txHash,
    isPending,       // wallet signing
    confirming,      // waiting for on-chain confirmation
    confirmed,       // mined successfully
    receipt,         // mined tx receipt (for parsing the minted tokenId)
    reset,
    refresh,
    // finalize / summon (auto-launch iteration #1 after mint-out)
    finalize,
    finalizeHash,
    finalizePending, // wallet signing the summon
    finalizing,      // waiting for summon confirmation
    // launched: either our summon tx confirmed, or the chain already reports it
    finalized: finalized || Boolean(finalizedOnchain),
    resetFinalize,
    minted: minted != null ? Number(minted) : undefined,
    soldOut: Boolean(soldOut),
    myBalance: myBalance != null ? Number(myBalance) : 0,
    maxSupply: PRESALE.maxSupply,
    priceEth: PRESALE.priceEth,
    // genesis token airdrop per fren + the iteration-#1 ticker (from Ponder) — the
    // REAL gift each MiFren claims (e.g. 69,937 $GNOME), not a hardcoded "1000 $MIF".
    airdropPerFren: ponder.airdropPerFren ?? 0,
    airdropTicker: ponder.airdropTicker || "",
  };
}
