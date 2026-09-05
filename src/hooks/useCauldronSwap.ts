import { useCallback } from "react";
import { parseEther, maxUint256, type Address } from "viem";
import {
  useAccount,
  useSwitchChain,
  useWriteContract,
  useWaitForTransactionReceipt,
} from "wagmi";
import { CAULDRON, GACHA_ROUTER_ABI, ERC20_SWAP_ABI, COLLECTION_ABI } from "@/config/cauldron";

/** Generous gas limit for a hinted swap that may auto-liquidate a position
 *  (nested pool swaps + badge mint). The wallet's estimate can be far too low
 *  when the target is still healthy at submit time, so we force headroom. */
const LIQ_SWAP_GAS = 3_000_000n;

/**
 * useCauldronSwap — buy the current iteration's token with ETH.
 *
 * Routes through the CauldronGachaRouter's `play(tokenIn=0, minOut, 0, openMax)`
 * with `value = ethIn`. That single call:
 *   1. swaps ETH → token and delivers the token to the buyer,
 *   2. credits the swap volume (keeps the brew alive), and
 *   3. rolls the crystal gacha — a chance to forge a creature NFT.
 *
 * `minOut` is the caller's slippage floor (0 accepts any). `openMax=0` opens as
 * many crystals as the buy's volume earns.
 */
export function useCauldronSwap() {
  const { address, chainId } = useAccount();
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync, data: txHash, isPending, reset } = useWriteContract();
  const { isLoading: confirming, isSuccess: confirmed, data: receipt } =
    useWaitForTransactionReceipt({ hash: txHash, chainId: CAULDRON.chainId });

  /** Buy with `ethIn` ETH; `minOut` = minimum token out (wei); `openMax` crystals.
   *  `liqHint` (optional) is the id of a perp position to auto-liquidate if this
   *  buy tips it past the mark — a win mints YOU a Liquidatoor badge. 0 = none;
   *  a stale/healthy hint is a silent no-op, so it never risks the trade. */
  const buy = useCallback(
    async (ethIn: number, minOut: bigint = 0n, openMax = 0, liqHint: bigint = 0n): Promise<`0x${string}`> => {
      if (!address) throw new Error("Connect a wallet first");
      if (ethIn <= 0) throw new Error("Enter an amount");
      if (chainId !== CAULDRON.chainId) {
        await switchChainAsync({ chainId: CAULDRON.chainId });
      }
      const value = parseEther(ethIn.toFixed(18));
      liqHint; // LEGACY/IGNORED: the hook auto-liquidates on EVERY swap hint-free,
      //          so we never call the router's playLiq (its liqHint path reverts).
      // Force a generous gas limit: any buy can trigger an in-swap liquidation
      // (nested pool swaps) that the wallet's estimate — taken when the target was
      // still healthy — can't foresee, which would OOG. Unused gas is refunded.
      return writeContractAsync({
        address: CAULDRON.gachaRouter as Address, abi: GACHA_ROUTER_ABI,
        functionName: "play", args: [0n, minOut, 0n, BigInt(openMax)], value,
        gas: LIQ_SWAP_GAS,
      });
    },
    [address, chainId, switchChainAsync, writeContractAsync],
  );

  /** SPIN volume: churn `ethIn` ETH through `loops` Buy→Sell→Buy legs. Each leg
   *  is credited as Mana, so a small stake generates a multiple of itself in
   *  volume → more chances to summon a crystal. `openMax=0` opens all earned. */
  const spin = useCallback(
    async (ethIn: number, loops = 3, openMax = 0): Promise<`0x${string}`> => {
      if (!address) throw new Error("Connect a wallet first");
      if (ethIn <= 0) throw new Error("Enter an amount");
      if (chainId !== CAULDRON.chainId) {
        await switchChainAsync({ chainId: CAULDRON.chainId });
      }
      return writeContractAsync({
        address: CAULDRON.gachaRouter as Address,
        abi: GACHA_ROUTER_ABI,
        functionName: "playChurn",
        args: [BigInt(loops), BigInt(openMax)],
        value: parseEther(ethIn.toFixed(18)),
      });
    },
    [address, chainId, switchChainAsync, writeContractAsync],
  );

  /** Open a sealed crystal you own → reveals the creature inside. */
  const reveal = useCallback(
    async (collection: Address, tokenId: bigint): Promise<`0x${string}`> => {
      if (!address) throw new Error("Connect a wallet first");
      if (chainId !== CAULDRON.chainId) {
        await switchChainAsync({ chainId: CAULDRON.chainId });
      }
      return writeContractAsync({
        address: collection, abi: COLLECTION_ABI, functionName: "reveal", args: [tokenId],
      });
    },
    [address, chainId, switchChainAsync, writeContractAsync],
  );

  /**
   * Open MANY sealed crystals in one transaction.
   *
   * Revealing was per-token, so a wallet holding thirty crystals paid thirty
   * base fees to see what it already owned. The on-chain work per token is
   * identical; this just stops paying for a transaction over and over.
   *
   * The contract caps a batch at 50, so longer lists are chunked rather than
   * reverting — a holder should not have to know that limit exists.
   */
  const revealMany = useCallback(
    async (collection: Address, tokenIds: bigint[]): Promise<`0x${string}`[]> => {
      if (!address) throw new Error("Connect a wallet first");
      if (tokenIds.length === 0) return [];
      if (chainId !== CAULDRON.chainId) {
        await switchChainAsync({ chainId: CAULDRON.chainId });
      }
      const hashes: `0x${string}`[] = [];
      for (let i = 0; i < tokenIds.length; i += 50) {
        hashes.push(await writeContractAsync({
          address: collection,
          abi: COLLECTION_ABI,
          functionName: "revealBatch",
          args: [tokenIds.slice(i, i + 50)],
        }));
      }
      return hashes;
    },
    [address, chainId, switchChainAsync, writeContractAsync],
  );

  /** Crack open crystals from ALREADY-earned credit — no fresh buy. Commits the
   *  banked crystals (odds derived on-chain) + resolves matured tickets. */
  const openReady = useCallback(
    async (maxCount = 0): Promise<`0x${string}`> => {
      if (!address) throw new Error("Connect a wallet first");
      if (chainId !== CAULDRON.chainId) {
        await switchChainAsync({ chainId: CAULDRON.chainId });
      }
      return writeContractAsync({
        address: CAULDRON.gachaRouter as Address,
        abi: GACHA_ROUTER_ABI,
        functionName: "openReady",
        args: [BigInt(maxCount)],
      });
    },
    [address, chainId, switchChainAsync, writeContractAsync],
  );

  /** Approve the router to spend the iteration token (needed before selling). */
  const approveToken = useCallback(
    async (token: Address): Promise<`0x${string}`> => {
      if (!address) throw new Error("Connect a wallet first");
      if (chainId !== CAULDRON.chainId) {
        await switchChainAsync({ chainId: CAULDRON.chainId });
      }
      return writeContractAsync({
        address: token, abi: ERC20_SWAP_ABI, functionName: "approve",
        args: [CAULDRON.gachaRouter as Address, maxUint256],
      });
    },
    [address, chainId, switchChainAsync, writeContractAsync],
  );

  /** Sell `tokenIn` (human units) of the iteration token back to ETH via the
   *  router's sell leg. Requires a prior approval. `minEthOut` = slippage floor.
   *  `maxWei` (the wallet's exact on-chain balance) CAPS the amount — the human
   *  `tokenIn` is a lossy float for large balances, so "MAX" can compute slightly
   *  MORE than you hold and revert `transferFrom`; clamping to the raw balance
   *  fixes it and lets a true sell-all work exactly. */
  const sell = useCallback(
    async (tokenIn: number, minEthOut: bigint = 0n, openMax = 0, liqHint: bigint = 0n, maxWei?: bigint): Promise<`0x${string}`> => {
      if (!address) throw new Error("Connect a wallet first");
      if (tokenIn <= 0) throw new Error("Enter an amount");
      if (chainId !== CAULDRON.chainId) {
        await switchChainAsync({ chainId: CAULDRON.chainId });
      }
      let tokenInWei = parseEther(tokenIn.toFixed(18));
      if (maxWei != null && maxWei > 0n && tokenInWei > maxWei) tokenInWei = maxWei;
      liqHint; // LEGACY/IGNORED — hook auto-liquidates hint-free; never call playLiq.
      return writeContractAsync({
        address: CAULDRON.gachaRouter as Address, abi: GACHA_ROUTER_ABI,
        functionName: "play", args: [tokenInWei, 0n, minEthOut, BigInt(openMax)], value: 0n,
        gas: LIQ_SWAP_GAS,
      });
    },
    [address, chainId, switchChainAsync, writeContractAsync],
  );

  return { buy, sell, spin, reveal, revealMany, openReady, approveToken, txHash, receipt, isPending, confirming, confirmed, reset };
}
