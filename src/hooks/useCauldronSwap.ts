import { useCallback } from "react";
import { parseEther, parseUnits, maxUint256, type Address } from "viem";
import {
  useAccount,
  useSwitchChain,
  useWriteContract,
  useWaitForTransactionReceipt,
  usePublicClient,
} from "wagmi";
import { CAULDRON, GACHA_ROUTER_ABI, ERC20_SWAP_ABI, COLLECTION_ABI } from "@/config/cauldron";
import { NATIVE_QUOTE, isNativeQuote } from "@/config/quotes";

/** `MockQuoteToken.mint` — testnet quote faucet. Not present on a real asset. */
const MOCK_MINT_ABI = [{
  type: "function", name: "mint", stateMutability: "nonpayable",
  inputs: [{ type: "address" }, { type: "uint256" }], outputs: [],
}] as const;

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
  //  Needed to READ an allowance and to WAIT on the approval before `play`
  //  pulls the quote — an ERC20-quoted buy is two transactions, not one.
  const pc = usePublicClient({ chainId: CAULDRON.chainId });
  const {
    isLoading: confirming,
    isSuccess: mined,
    isError: waitFailed,
    error: waitError,
    data: receipt,
  } = useWaitForTransactionReceipt({
    hash: txHash,
    chainId: CAULDRON.chainId,
    //  NEVER SPIN FOREVER. With no timeout viem polls for a receipt
    //  indefinitely, so a dropped or replaced transaction — or one of the public
    //  RPCs in the rotation deciding to rate-limit `eth_getTransactionReceipt` —
    //  left the button reading "Buying..." with no end state and no way back
    //  except a page reload. Ten Sepolia blocks is long enough that a healthy
    //  transaction has landed, and the copy below says "may still land" rather
    //  than "failed", because a timeout is OUR ignorance, not a verdict.
    timeout: 120_000,
  });

  /**
   * A RECEIPT IS NOT A SUCCESS.
   *
   *  `useWaitForTransactionReceipt` resolves perfectly happily for a transaction
   *  that REVERTED — the receipt simply carries `status: "reverted"` — so
   *  `isSuccess` means "mined", not "worked". Passing it through as `confirmed`
   *  made the widget show "Done ✓" and refresh its telemetry after a buy that
   *  reverted on the slippage floor: the single most misleading thing a trading
   *  widget can say. {CrystalCauldronGame} already checked
   *  `rcpt.status === "reverted"` on its own direct call; this is the same check,
   *  moved to where every consumer of this hook inherits it.
   */
  const reverted = mined && receipt?.status === "reverted";
  const confirmed = mined && receipt?.status === "success";

  /** Why the last transaction did not confirm — "" while nothing is wrong.
   *  Distinguishes the two outcomes a caller must NOT conflate: the chain
   *  rejected the trade (actionable — raise the tolerance) versus we lost track
   *  of it (not actionable — go look). */
  const failReason = reverted
    ? "Reverted on-chain. The pool could not fill above your minimum \u2014 raise Max slippage (the gear) and try again."
    : waitFailed
      ? (/timed out|timeout/i.test(waitError?.message ?? "")
          ? "Could not confirm within 2 minutes. The transaction may still land \u2014 check the explorer before retrying."
          : "Lost track of the transaction (it may have been replaced or the RPC dropped it). Check the explorer before retrying.")
      : "";

  /** Buy with `ethIn` ETH; `minOut` = minimum token out (wei); `openMax` crystals.
   *  `liqHint` (optional) is the id of a perp position to auto-liquidate if this
   *  buy tips it past the mark — a win mints YOU a Liquidatoor badge. 0 = none;
   *  a stale/healthy hint is a silent no-op, so it never risks the trade. */
  const buy = useCallback(
    async (
      ethIn: number, minOut: bigint = 0n, openMax = 0, liqHint: bigint = 0n,
      quote: Address = NATIVE_QUOTE, quoteDecimals = 18,
    ): Promise<`0x${string}`> => {
      if (!address) throw new Error("Connect a wallet first");
      if (ethIn <= 0) throw new Error("Enter an amount");
      if (chainId !== CAULDRON.chainId) {
        await switchChainAsync({ chainId: CAULDRON.chainId });
      }

      //  ── AN ERC20-QUOTED GENERATION BUYS DIFFERENTLY ──────────────────────
      //  `CauldronGachaRouter._pullQuote` branches on the generation's quote:
      //  native takes `msg.value` and REVERTS on a non-zero `quoteIn`
      //  (`NativeQuoteTakesValue`); an ERC20 quote reverts on any value
      //  (`ErcQuoteTakesNoValue`) and `transferFrom`s `quoteIn` instead.
      //
      //  Only the native branch was ever implemented here. The comment below
      //  said so and nothing acted on it — so the first completed rotation, which
      //  legitimately flips `generationQuote` to USDG, made the buy button
      //  revert for everyone. Trading is not something a treasury vote may
      //  switch off.
      if (!isNativeQuote(quote)) {
        const amountIn = parseUnits(ethIn.toFixed(quoteDecimals), quoteDecimals);
        //  APPROVE ONLY WHAT IS MISSING. An unconditional approve costs an extra
        //  transaction on every buy; an infinite one leaves a standing allowance
        //  on a router that moves user funds. Read, then top up to exactly this
        //  trade if short.
        const current = (await pc!.readContract({
          address: quote, abi: ERC20_SWAP_ABI, functionName: "allowance",
          args: [address, CAULDRON.gachaRouter as Address],
        })) as bigint;
        if (current < amountIn) {
          const hash = await writeContractAsync({
            address: quote, abi: ERC20_SWAP_ABI, functionName: "approve",
            args: [CAULDRON.gachaRouter as Address, amountIn],
          });
          //  WAIT FOR IT. `play` would otherwise race its own approval and
          //  revert on `transferFrom` — a failure that reads like a bad trade.
          await pc!.waitForTransactionReceipt({ hash });
        }
        return writeContractAsync({
          address: CAULDRON.gachaRouter as Address, abi: GACHA_ROUTER_ABI,
          functionName: "play",
          args: [amountIn, 0n, minOut, 0n, BigInt(openMax)], value: 0n,
          gas: LIQ_SWAP_GAS,
        });
      }

      const value = parseEther(ethIn.toFixed(18));
      liqHint; // LEGACY/IGNORED: the hook auto-liquidates on EVERY swap hint-free,
      //          so we never call the router's playLiq (its liqHint path reverts).
      // Force a generous gas limit: any buy can trigger an in-swap liquidation
      // (nested pool swaps) that the wallet's estimate — taken when the target was
      // still healthy — can't foresee, which would OOG. Unused gas is refunded.
      return writeContractAsync({
        address: CAULDRON.gachaRouter as Address, abi: GACHA_ROUTER_ABI,
        functionName: "play",
        //  `quoteIn: 0n` — this path supplies the buy side as native `value`.
        //  Correct while the generation trades ETH; on a non-native generation
        //  the router reverts `ErcQuoteTakesNoValue` rather than stranding it
        //  (functional audit R-05). A USDG-denominated buy needs an approve +
        //  a non-zero `quoteIn` with no value.
        args: [0n, 0n, minOut, 0n, BigInt(openMax)], value,
        gas: LIQ_SWAP_GAS,
      });
    },
    [address, chainId, switchChainAsync, writeContractAsync, pc],
  );

  /**
   * TESTNET ONLY — mint yourself some of an ERC20 quote.
   *
   * `MockQuoteToken.mint` is public by design ("Anyone may mint. Testnet only").
   * A completed rotation can redenominate a generation into an asset no tester
   * holds, which leaves a buy button that cannot be used for a reason nothing on
   * screen explains. Callers must gate this on the chain id — the function will
   * simply revert against a real asset, which is the correct outcome but a poor
   * way to find out.
   */
  const mintTestQuote = useCallback(
    async (quote: Address, decimals = 18, amount = 10_000): Promise<`0x${string}`> => {
      if (!address) throw new Error("Connect a wallet first");
      if (chainId !== CAULDRON.chainId) await switchChainAsync({ chainId: CAULDRON.chainId });
      return writeContractAsync({
        address: quote, abi: MOCK_MINT_ABI, functionName: "mint",
        args: [address, parseUnits(String(amount), decimals)],
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
        //  See the note in `buy`: native value, so `quoteIn` is 0.
        args: [0n, BigInt(loops), BigInt(openMax)],
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
        //  A SELL supplies no buy side at all, so `quoteIn` is 0 and no value is
        //  sent — which is valid on a native AND an ERC20-quote generation. The
        //  proceeds come back in whatever the generation trades, so `minEthOut`
        //  is really a min-QUOTE-out (functional audit R-05).
        functionName: "play", args: [0n, tokenInWei, 0n, minEthOut, BigInt(openMax)], value: 0n,
        gas: LIQ_SWAP_GAS,
      });
    },
    [address, chainId, switchChainAsync, writeContractAsync],
  );

  return {
    buy, sell, spin, reveal, revealMany, openReady, approveToken, mintTestQuote,
    txHash, receipt, isPending, confirming, confirmed,
    //  Exposed so no caller has to re-derive "mined but reverted" and get it
    //  wrong the way this hook did.
    reverted, failed: reverted || waitFailed, failReason,
    reset,
  };
}
