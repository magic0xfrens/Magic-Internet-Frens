import { useCallback, useEffect, useRef, useState } from "react";
import { parseEther, maxUint256, type Address } from "viem";
import { useAccount, useSwitchChain, useWriteContract, useReadContract } from "wagmi";
import { PERP, PERP_VAULT_ABI } from "@/config/perp";
import { CAULDRON, ERC20_SWAP_ABI, CAULDRON_INDEXER } from "@/config/cauldron";

// Use the shared config constant (has the public Railway default) so the vault
// reads don't silently break when the Vercel env is empty.
const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

export interface VaultState {
  assetsEth: number; assetsTok: number;
  ethShares: number; tokShares: number;
  ethSharePrice: number; tokSharePrice: number;
}
export interface VaultPosition { redeemable: number; instant: number; pending: number; shares: bigint; ethReward: number }

const EMPTY_VAULT: VaultState = { assetsEth: 0, assetsTok: 0, ethShares: 0, tokShares: 0, ethSharePrice: 1, tokSharePrice: 1 };
const EMPTY_POS: VaultPosition = { redeemable: 0, instant: 0, pending: 0, shares: 0n, ethReward: 0 };

/**
 * usePerpVault — the Community PLV staking brain. READS (vault totals, your
 * position) come from Ponder (/perp-vault/:user), so the browser stays RPC-free.
 * Writes (deposit/withdraw/claim) go straight to the wallet. Your token balance +
 * allowance are the only light on-chain reads (needed for the approve flow).
 */
export function usePerpVault(token?: Address) {
  const { address, chainId } = useAccount();
  const { switchChainAsync } = useSwitchChain();
  const { writeContractAsync, data: txHash, isPending, reset } = useWriteContract();

  const [vault, setVault] = useState<VaultState>(EMPTY_VAULT);
  const [ethPos, setEthPos] = useState<VaultPosition>(EMPTY_POS);
  const [tokPos, setTokPos] = useState<VaultPosition>(EMPTY_POS);
  const [pendingAction, setPendingAction] = useState<string | null>(null);

  // token balance + allowance for the deposit-token approve flow (light reads)
  const { data: tokBal, refetch: refetchBal } = useReadContract({
    address: token, abi: ERC20_SWAP_ABI, functionName: "balanceOf",
    args: address ? [address] : undefined, chainId: CAULDRON.chainId, query: { enabled: !!address && !!token },
  });
  const { data: allowance, refetch: refetchAllow } = useReadContract({
    address: token, abi: ERC20_SWAP_ABI, functionName: "allowance",
    args: address ? [address, PERP.vault] : undefined, chainId: CAULDRON.chainId, query: { enabled: !!address && !!token },
  });

  // ── Ponder reads (vault state + your position) ──
  const addrRef = useRef(address); addrRef.current = address;
  useEffect(() => {
    if (!INDEXER) return;
    let alive = true;
    const load = async () => {
      try {
        const a = addrRef.current;
        const url = a ? `${INDEXER}/perp-vault/${a}` : `${INDEXER}/perp-vault`;
        const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
        if (!res.ok) return;
        type RawPos = Omit<VaultPosition, "shares" | "ethReward"> & { shares?: string; ethReward?: number };
        const d = await res.json() as { vault?: VaultState; eth?: RawPos; token?: RawPos };
        if (!alive) return;
        const pos = (p?: RawPos): VaultPosition =>
          ({ redeemable: p?.redeemable ?? 0, instant: p?.instant ?? 0, pending: p?.pending ?? 0, shares: BigInt(p?.shares ?? "0"), ethReward: p?.ethReward ?? 0 });
        if (d.vault) setVault(d.vault);
        if (d.eth) setEthPos(pos(d.eth));
        if (d.token) setTokPos(pos(d.token));
      } catch { /* keep last */ }
    };
    load();
    // Pause while the tab is backgrounded, refresh on return: an idle tab
    // should cost nothing. Mirrors usePoll.
    let t: ReturnType<typeof setInterval> | null = setInterval(load, pendingAction ? 1500 : 6000);
    const onVis = () => {
      if (document.hidden) { if (t) { clearInterval(t); t = null; } }
      else if (!t) { load(); t = setInterval(load, pendingAction ? 1500 : 6000); }
    };
    document.addEventListener("visibilitychange", onVis);
    return () => {
      alive = false;
      if (t) clearInterval(t);
      document.removeEventListener("visibilitychange", onVis);
    };
  }, [address, pendingAction]);

  const ensureChain = useCallback(async () => {
    reset();
    if (chainId !== PERP.chainId) await switchChainAsync({ chainId: PERP.chainId });
  }, [chainId, switchChainAsync, reset]);

  const depositEth = useCallback(async (eth: number) => {
    if (!address) throw new Error("Connect a wallet first");
    await ensureChain(); setPendingAction("deposit-eth");
    return writeContractAsync({ address: PERP.vault, abi: PERP_VAULT_ABI, functionName: "depositEth", value: parseEther(eth.toFixed(18)) });
  }, [address, ensureChain, writeContractAsync]);

  const withdrawEthShares = useCallback(async (shares: bigint) => {
    await ensureChain(); setPendingAction("withdraw-eth");
    return writeContractAsync({ address: PERP.vault, abi: PERP_VAULT_ABI, functionName: "withdrawEth", args: [shares] });
  }, [ensureChain, writeContractAsync]);

  const needsTokenApproval = (amount: bigint) => (allowance == null || (allowance as bigint) < amount);
  const approveToken = useCallback(async () => {
    if (!token) throw new Error("No token");
    await ensureChain(); setPendingAction("approve");
    return writeContractAsync({ address: token, abi: ERC20_SWAP_ABI, functionName: "approve", args: [PERP.vault, maxUint256] });
  }, [token, ensureChain, writeContractAsync]);

  const depositToken = useCallback(async (amount: bigint) => {
    await ensureChain(); setPendingAction("deposit-token");
    return writeContractAsync({ address: PERP.vault, abi: PERP_VAULT_ABI, functionName: "depositToken", args: [amount] });
  }, [ensureChain, writeContractAsync]);

  const withdrawTokenShares = useCallback(async (shares: bigint) => {
    await ensureChain(); setPendingAction("withdraw-token");
    return writeContractAsync({ address: PERP.vault, abi: PERP_VAULT_ABI, functionName: "withdrawToken", args: [shares] });
  }, [ensureChain, writeContractAsync]);

  const claimEth = useCallback(async () => {
    await ensureChain(); setPendingAction("claim-eth");
    return writeContractAsync({ address: PERP.vault, abi: PERP_VAULT_ABI, functionName: "claimPendingEth" });
  }, [ensureChain, writeContractAsync]);

  const claimToken = useCallback(async () => {
    await ensureChain(); setPendingAction("claim-token");
    return writeContractAsync({ address: PERP.vault, abi: PERP_VAULT_ABI, functionName: "claimPendingToken" });
  }, [ensureChain, writeContractAsync]);

  // claim the token-side ETH reward (short-attributed fees)
  const claimTokYield = useCallback(async () => {
    await ensureChain(); setPendingAction("claim-tokyield");
    return writeContractAsync({ address: PERP.vault, abi: PERP_VAULT_ABI, functionName: "claimTokYield" });
  }, [ensureChain, writeContractAsync]);

  // clear pending after ~14s (Ponder reflects the state) + refresh token reads
  useEffect(() => {
    if (!pendingAction) return;
    const t = setTimeout(() => { setPendingAction(null); refetchBal(); refetchAllow(); }, 14000);
    return () => clearTimeout(t);
  }, [pendingAction, txHash, refetchBal, refetchAllow]);

  return {
    vault, ethPos, tokPos, pendingAction, isPending, txHash,
    tokenBalance: (tokBal as bigint) ?? 0n, needsTokenApproval,
    depositEth, withdrawEthShares, approveToken, depositToken, withdrawTokenShares, claimEth, claimToken, claimTokYield,
    // share balances for withdraw-all
    ethShareOf: async () => 0n, // reserved
  };
}
