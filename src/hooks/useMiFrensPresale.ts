import { useCallback, useEffect, useState } from "react";
import { usePoll } from "@/hooks/usePoll";
import {
  useAccount,
  useReadContract,
  useSwitchChain,
  useWriteContract,
  useWaitForTransactionReceipt,
  usePublicClient,
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
/**
 * Turn a viem/wagmi failure into something a person can act on.
 *
 *  A raw revert surfaces as a wall of text ending in a bare selector, and a
 *  rejected signature surfaces as an error too - so treating every throw the
 *  same way either shouts at someone who simply changed their mind, or says
 *  nothing at all when a transaction was genuinely doomed. Returns null for a
 *  user rejection (nothing went wrong) and a sentence otherwise.
 */
function readableTxError(e: unknown): string | null {
  const err = e as { name?: string; shortMessage?: string; message?: string; cause?: unknown; walk?: (fn: (x: unknown) => boolean) => unknown };
  const text = `${err?.name ?? ""} ${err?.shortMessage ?? ""} ${err?.message ?? ""}`;
  if (/User rejected|User denied|rejected the request/i.test(text)) return null;

  // viem nests the decoded custom error; `walk` finds it wherever it sits.
  let name: string | undefined;
  try {
    const found = err?.walk?.((x) => (x as { name?: string })?.name === "ContractFunctionRevertedError");
    name = (found as { data?: { errorName?: string } })?.data?.errorName;
  } catch { /* fall through to text matching */ }
  if (!name) name = /custom error '?(\w+)/i.exec(text)?.[1];

  switch (name) {
    case "WrongPrice":       return "Price changed on-chain — reload the page and try again.";
    case "PerWalletCap":     return "That would exceed the per-wallet cap for this wallet.";
    case "ExceedsSupply":    return "Not enough left in the genesis tranche for that quantity.";
    case "PresaleOver":      return "The presale is already ignited.";
    case "AlreadyCancelled": return "The presale was cancelled.";
    case "NotSoldOut":       return "The tranche has to mint out before the Cauldron can be ignited.";
    case "NotAuthorized":    return "This wallet is not the designated igniter.";
    case "AlreadyFinalized": return "The Cauldron is already lit.";
    case "RegistryNotSet":   return "The presale is not wired to a registry yet.";
  }
  if (/insufficient funds/i.test(text)) return "Not enough ETH for the mint plus gas.";
  return err?.shortMessage || "Transaction failed. Nothing was spent.";
}

export function useMiFrensPresale() {
  const { address, chainId } = useAccount();
  const publicClient = usePublicClient({ chainId: PRESALE.chainId });
  const [txError, setTxError] = useState<string | null>(null);
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync, data: txHash, isPending, reset } = useWriteContract();
  const { isLoading: confirming, isSuccess: gotReceipt, data: receipt } =
    useWaitForTransactionReceipt({ hash: txHash, chainId: PRESALE.chainId });
  //  A RECEIPT IS NOT A SUCCESS. `isSuccess` here means "the receipt was
  //  fetched", which is equally true of a transaction that reverted - so the UI
  //  congratulated people on mints that had failed, and showed "Your MiFren #—"
  //  with no id because there was no Transfer log to read one from. The status
  //  field is the actual verdict.
  const reverted = gotReceipt && receipt?.status === "reverted";
  const confirmed = gotReceipt && receipt?.status === "success";

  // Separate write flow for finalize() — the summon that launches iteration #1
  // once the guild mints out. Kept independent so its status doesn't clobber
  // the mint tx state.
  const {
    writeContractAsync: finalizeAsync,
    data: finalizeHash,
    isPending: finalizePending,
    reset: resetFinalize,
  } = useWriteContract();
  const { isLoading: finalizing, isSuccess: gotIgniteReceipt, data: igniteReceipt } =
    useWaitForTransactionReceipt({ hash: finalizeHash, chainId: PRESALE.chainId });
  const igniteReverted = gotIgniteReceipt && igniteReceipt?.status === "reverted";
  const finalized = gotIgniteReceipt && igniteReceipt?.status === "success";

  const common = { address: PRESALE.address, abi: PRESALE_ABI, chainId: PRESALE.chainId } as const;

  //  A transaction can pass simulation and still revert on-chain - the state it
  //  was simulated against moves. Reverting silently is the worst outcome: the
  //  wallet shows a spent transaction and the page shows nothing at all.
  useEffect(() => {
    if (reverted) setTxError("The mint reverted on-chain. Nothing was minted; gas was spent.");
  }, [reverted]);
  useEffect(() => {
    if (igniteReverted) setTxError("Ignition reverted on-chain. The Cauldron was not lit.");
  }, [igniteReverted]);

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
    //  ALWAYS ENABLED, never `enabled: !INDEXER`. Disabling the chain read left
    //  the page with no floor under a slow, restarting or backfilling indexer —
    //  which is exactly how a sold-out 1111/1111 presale rendered as "0 / 1111".
    //  Polled slowly because the indexer is still the primary; this is a safety
    //  net, not a second poller.
    ...common, functionName: "minted", query: { refetchInterval: INDEXER ? 20000 : 5000 },
  });
  const { data: soldOutRpc, refetch: refetchSoldOut } = useReadContract({
    ...common, functionName: "soldOut", query: { refetchInterval: INDEXER ? 20000 : 5000 },
  });
  //  The live unit price, for DISPLAY and as the mint's starting point. Read from
  //  the contract rather than trusted from config, which is what went stale.
  const { data: priceWeiLive } = useReadContract({
    ...common, functionName: "PRICE", query: { staleTime: 60_000 },
  });
  const { data: finalizedRpc, refetch: refetchFinalized } = useReadContract({
    ...common, functionName: "finalized", query: { refetchInterval: INDEXER ? 20000 : 5000 },
  });
  //  MERGED BY MONOTONICITY, not by precedence.
  //
  //  "Ponder wins, chain is the fallback" reads sensibly and is wrong: a
  //  backfilling indexer returns minted:0, which is NOT null, so it beat the
  //  correct on-chain value and the page showed 0 / 1111 for a sold-out presale.
  //  A fallback that only applies when the primary is ABSENT is no fallback at
  //  all — the dangerous case is the primary being present and wrong.
  //
  //  These three values only ever move one way: mints accumulate, and soldOut
  //  and finalized latch true. So the larger/truer of the two sources is always
  //  the correct answer, whichever is momentarily behind. No staleness
  //  heuristics, no clock skew, nothing to tune.
  const mintedPonder = ponder.minted != null ? BigInt(ponder.minted) : 0n;
  const minted = mintedPonder > (mintedRpc ?? 0n) ? mintedPonder : (mintedRpc ?? 0n);
  const soldOut = Boolean(ponder.soldOut) || Boolean(soldOutRpc);
  const finalizedOnchain = Boolean(ponder.finalized) || Boolean(finalizedRpc);
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
    setTxError(null);
    //  Same pre-flight as the mint. Ignition is one shot and gated (sold out,
    //  and the designated finalizer if one is set), so a doomed attempt is very
    //  possible - and finding out by burning gas on the launch transaction is
    //  the worst moment for it.
    if (publicClient) {
      try {
        await publicClient.simulateContract({
          ...common, functionName: "igniteCauldron", args: [], account: address,
        });
      } catch (e) {
        const msg = readableTxError(e);
        setTxError(msg);
        throw new Error(msg ?? "Ignition would fail");
      }
    }
    try {
      return await finalizeAsync({ ...common, functionName: "igniteCauldron", args: [] });
    } catch (e) {
      setTxError(readableTxError(e));
      throw e;
    }
  }, [chainId, switchChainAsync, finalizeAsync, common, publicClient, address]);

  /** Mint `quantity` MiFrens with exact ETH payment. Returns the tx hash. */
  const mint = useCallback(
    async (quantity: number): Promise<`0x${string}`> => {
      if (!address) throw new Error("Connect a wallet first");
      if (chainId !== PRESALE.chainId) {
        await switchChainAsync({ chainId: PRESALE.chainId });
      }
      setTxError(null);

      //  READ THE PRICE FROM THE CONTRACT, EVERY TIME.
      //
      //  This used to multiply the hardcoded `PRESALE.priceWei`. A round that
      //  redeployed at a different price then made EVERY mint revert
      //  `WrongPrice` (msg.value must equal PRICE * quantity to the wei) while
      //  the UI still quoted the old figure - the failure looked like a wallet
      //  or network problem rather than a stale constant. The contract is the
      //  only authority on its own price.
      let unit = priceWeiLive ?? PRESALE.priceWei;
      if (publicClient) {
        try {
          unit = await publicClient.readContract({ ...common, functionName: "PRICE" }) as bigint;
        } catch { /* keep the last known price; the simulation below still guards */ }
      }
      const value = unit * BigInt(quantity);

      //  SIMULATE BEFORE ASKING FOR A SIGNATURE. Without this the first thing a
      //  user learns about a doomed transaction is a failed one on Etherscan -
      //  they have signed, waited, and paid gas to be told nothing. eth_call
      //  costs nothing and fails in the same way the real send would.
      if (publicClient) {
        try {
          await publicClient.simulateContract({
            ...common, functionName: "mint", args: [BigInt(quantity)], value, account: address,
          });
        } catch (e) {
          const msg = readableTxError(e);
          setTxError(msg);
          throw new Error(msg ?? "Mint would fail");
        }
      }

      try {
        return await writeContractAsync({
          ...common, functionName: "mint", args: [BigInt(quantity)], value,
        });
      } catch (e) {
        setTxError(readableTxError(e));
        throw e;
      }
    },
    [address, chainId, switchChainAsync, writeContractAsync, common, publicClient, priceWeiLive]
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
    /** Human-readable failure for the last mint/ignite attempt (null = fine). */
    txError,
    clearTxError: () => setTxError(null),
    reverted,
    igniteReverted,
    resetFinalize,
    minted: minted != null ? Number(minted) : undefined,
    soldOut: Boolean(soldOut),
    myBalance: myBalance != null ? Number(myBalance) : 0,
    maxSupply: PRESALE.maxSupply,
    //  Live from the contract, falling back to the config constant only until the
    //  first read resolves. The constant going stale is what made the page quote
    //  0.0062 at a contract charging 0.0005.
    priceEth: priceWeiLive != null ? Number(priceWeiLive) / 1e18 : PRESALE.priceEth,
    // genesis token airdrop per fren + the iteration-#1 ticker (from Ponder) — the
    // REAL gift each MiFren claims (e.g. 69,937 $GNOME), not a hardcoded "1000 $MIF".
    airdropPerFren: ponder.airdropPerFren ?? 0,
    airdropTicker: ponder.airdropTicker || "",
  };
}
