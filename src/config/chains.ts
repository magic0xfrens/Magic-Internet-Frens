import { defineChain, http, fallback } from "viem";
import { sepolia } from "viem/chains";
import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { injectedWallet, walletConnectWallet } from "@rainbow-me/rainbowkit/wallets";

/**
 * Robinhood Chain — EVM Layer-2 on Arbitrum Orbit, native gas token ETH.
 *
 * All network values are env-driven so the exact chainId / RPC can be corrected
 * without a code change. Confirm the mainnet chainId at
 * https://docs.robinhood.com/chain/connecting (sources have shown 4663 for
 * mainnet vs 46646 for testnet — do NOT trust a hardcoded value blindly).
 */
const CHAIN_ID = Number(import.meta.env.VITE_ROBINHOOD_CHAIN_ID ?? 4663);

const RPC_URL =
  import.meta.env.VITE_ROBINHOOD_RPC_URL ?? "https://rpc.chain.robinhood.com";

const EXPLORER_URL =
  import.meta.env.VITE_ROBINHOOD_EXPLORER ?? "https://robinhoodchain.blockscout.com";

export const robinhoodChain = defineChain({
  id: CHAIN_ID,
  name: "Robinhood Chain",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: [RPC_URL] },
    public: { http: [RPC_URL] },
  },
  blockExplorers: {
    default: { name: "Blockscout", url: EXPLORER_URL },
  },
  testnet: CHAIN_ID === 46646,
});

/** WalletConnect Cloud project id (required by RainbowKit for WC transports). */
const WALLETCONNECT_PROJECT_ID =
  import.meta.env.VITE_WALLETCONNECT_PROJECT_ID ?? "REPLACE_WITH_WALLETCONNECT_PROJECT_ID";

/** Only wire WalletConnect when a real projectId exists — the connector throws
 *  at construction with the placeholder, which would crash WagmiProvider. */
const hasWalletConnect =
  !!WALLETCONNECT_PROJECT_ID && WALLETCONNECT_PROJECT_ID !== "REPLACE_WITH_WALLETCONNECT_PROJECT_ID";

/** Sepolia RPCs — must be BROWSER-CORS-friendly (many public nodes block
 *  cross-origin fetch, which surfaces as CORS/ERR_FAILED and kills every read).
 *  Verified CORS-enabled endpoints, in a viem fallback chain (it retries the next
 *  on failure/429), so a rate-limited node rolls over instead of failing. Removed
 *  rpc.sepolia.org (no CORS header) + sepolia.drpc.org (free-plan blocked).
 *  Override the primary with VITE_SEPOLIA_RPC_URL for a dedicated endpoint. */
const SEPOLIA_RPCS = [
  import.meta.env.VITE_SEPOLIA_RPC_URL as string | undefined,
  "https://ethereum-sepolia-rpc.publicnode.com",
  "https://sepolia.gateway.tenderly.co",
  "https://1rpc.io/sepolia",
  "https://rpc.ankr.com/eth_sepolia",
].filter(Boolean) as string[];

/** Sepolia with its default rpcUrls OVERRIDDEN to our CORS-friendly list. viem's
 *  stock `sepolia` defaults to rpc.sepolia.org (no CORS header) — any code path
 *  that hits the chain default instead of the transport would spam failing
 *  requests. Pinning the chain's own rpcUrls kills that at the source. */
const sepoliaFixed = {
  ...sepolia,
  rpcUrls: {
    default: { http: SEPOLIA_RPCS },
    public: { http: SEPOLIA_RPCS },
  },
} as const;

export const wagmiConfig = getDefaultConfig({
  appName: "Magic Internet Frens",
  projectId: WALLETCONNECT_PROJECT_ID,
  // Sepolia is included so the genesis presale can mint against the live
  // MiFrensPresale during testnet; Robinhood is the mainnet target.
  chains: [robinhoodChain, sepoliaFixed],
  transports: {
    [sepolia.id]: fallback(SEPOLIA_RPCS.map((u) => http(u, { batch: true }))),
    [robinhoodChain.id]: http(RPC_URL),
  },
  // Curated connectors. `injectedWallet` (all browser-extension wallets via
  // window.ethereum) needs NO projectId, so it's always safe. WalletConnect is
  // only added when a REAL projectId is configured — constructing the WC
  // connector with the placeholder id throws at init and blanks the whole app.
  wallets: [
    {
      groupName: "Recommended",
      wallets: hasWalletConnect ? [injectedWallet, walletConnectWallet] : [injectedWallet],
    },
  ],
  ssr: false,
});

export const CHAIN = robinhoodChain;
export const ROBINHOOD_CHAIN_ID = CHAIN_ID;
export const ROBINHOOD_RPC_URL = RPC_URL;
export const ROBINHOOD_EXPLORER_URL = EXPLORER_URL;
