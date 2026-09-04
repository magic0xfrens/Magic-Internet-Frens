import { useMemo } from "react";
import {
  useAccount,
  useBalance,
  useChainId,
  useDisconnect,
  useSwitchChain,
} from "wagmi";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { formatEther } from "viem";
import { ROBINHOOD_CHAIN_ID, robinhoodChain } from "@/config/chains";

/**
 * EVM wallet hook (wagmi + RainbowKit). Kept free of ethers so the eager app
 * path stays lean — legacy code that needs an ethers signer uses the dedicated
 * `useEthersSigner()` (lazy-loaded); new code uses wagmi's `useWriteContract`.
 *
 * - `address` / `walletAddress` are the connected 0x address string.
 * - `network` is the active viem chain (has `.id` / chainId).
 */
export function useWallet() {
  const { address, isConnected, isConnecting } = useAccount();
  const chainId = useChainId();
  const { data: balance } = useBalance({ address });
  const { openConnectModal } = useConnectModal();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();

  const walletBalance = useMemo(
    () => (balance ? formatEther(balance.value) : null),
    [balance],
  );

  return {
    isConnected,
    walletAddress: address ?? null,
    address: address ?? null,
    publicKey: address ?? null,
    network: robinhoodChain,
    chainId,
    isCorrectNetwork: chainId === ROBINHOOD_CHAIN_ID,
    walletBalance,
    connecting: isConnecting,

    openConnectModal: openConnectModal ?? (() => {}),
    connectToWallet: openConnectModal ?? (() => {}),
    disconnect,
    switchToRobinhood: () => switchChain({ chainId: ROBINHOOD_CHAIN_ID }),
  };
}
