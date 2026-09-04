import { useCallback } from "react";
import { parseEther } from "viem";
import {
  useAccount,
  useReadContract,
  useSwitchChain,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { PRESALE, PRESALE_ABI } from "@/config/presale";

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
    useWaitForTransactionReceipt({ hash: txHash });

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
    useWaitForTransactionReceipt({ hash: finalizeHash });

  const common = { address: PRESALE.address, abi: PRESALE_ABI, chainId: PRESALE.chainId } as const;

  // Poll every 5s so the UI reacts to a sellout even if the confirm/refetch
  // race misses (public RPCs can lag a block right after a tx).
  const { data: minted, refetch: refetchMinted } = useReadContract({
    ...common, functionName: "minted", query: { refetchInterval: 5000 },
  });
  const { data: soldOut, refetch: refetchSoldOut } = useReadContract({
    ...common, functionName: "soldOut", query: { refetchInterval: 5000 },
  });
  const { data: finalizedOnchain, refetch: refetchFinalized } = useReadContract({
    ...common, functionName: "finalized", query: { refetchInterval: 5000 },
  });
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
      const value = parseEther((PRESALE.priceEth * quantity).toFixed(18));
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
  };
}
