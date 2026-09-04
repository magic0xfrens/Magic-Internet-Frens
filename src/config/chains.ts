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
 *  Verified CORS-enabled endpoints, in a viem fallback chain (it rolls over to the
 *  next on failure/429), so a rate-limited node fails over instead of erroring.
 *
 *  IMPORTANT: public Sepolia nodes rate-limit HARD under any polling dApp (you'll
 *  see "rate limit exceeded" on sends). For a smooth experience set a DEDICATED
 *  endpoint via VITE_SEPOLIA_RPC_URL (free Alchemy/Infura key) — it's tried first.
 *  Tenderly's gateway is the flakiest under load, so it's LAST here. */
// VITE_SEPOLIA_RPC_URL may be a COMMA-SEPARATED list (e.g. several free Alchemy
// keys). They're all added to the fallback so viem rolls over to the next on a
// 429 — rotating keys multiplies the effective rate limit.
const DEDICATED_RPCS = ((import.meta.env.VITE_SEPOLIA_RPC_URL as string) || "")
  .split(",").map((s) => s.trim()).filter(Boolean);
const SEPOLIA_RPCS = [
  ...DEDICATED_RPCS,
  "https://ethereum-sepolia-rpc.publicnode.com",
  "https://1rpc.io/sepolia",
  "https://rpc.ankr.com/eth_sepolia",
  "https://sepolia.gateway.tenderly.co",
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
    // Batch JSON-RPC calls within a ~24ms window into ONE HTTP request (fewer
    // requests → far less rate-limiting on public nodes), and roll over to the
    // next node on a 429/error. A dedicated VITE_SEPOLIA_RPC_URL is tried first.
    [sepolia.id]: fallback(
      SEPOLIA_RPCS.map((u) => http(u, { batch: { wait: 24 }, retryCount: 2, retryDelay: 250 })),
      { retryCount: 2, retryDelay: 300 },
    ),
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

// ── SINGLE NETWORK SWITCH ───────────────────────────────────────────────────
// The whole app targets ONE chain, chosen by VITE_NETWORK. Default "testnet" so
// the live Sepolia site keeps working; set VITE_NETWORK=mainnet (once Robinhood
// contracts + indexer exist) to cut over in ONE env change. Everything —
// config chainIds, wallet switch, explorer/marketplace links, copy — reads from
// ACTIVE_* / IS_MAINNET / NETWORK_LABEL below so there's no per-file drift.
const NETWORK = ((import.meta.env.VITE_NETWORK as string) ?? "testnet").trim().toLowerCase();
export const IS_MAINNET = NETWORK === "mainnet" || NETWORK === "robinhood";
export const IS_TESTNET = !IS_MAINNET;
export const ACTIVE_CHAIN = IS_MAINNET ? robinhoodChain : sepoliaFixed;
export const ACTIVE_CHAIN_ID = ACTIVE_CHAIN.id;
export const NETWORK_LABEL = IS_MAINNET ? "Robinhood Chain" : "Sepolia testnet";
export const NETWORK_SHORT = IS_MAINNET ? "Robinhood" : "Sepolia";

/** Block-explorer base for the active chain. */
export const EXPLORER_BASE = IS_MAINNET ? EXPLORER_URL : "https://sepolia.etherscan.io";
export const explorerTxUrl = (hash: string) => `${EXPLORER_BASE}/tx/${hash}`;
export const explorerAddressUrl = (addr: string) => `${EXPLORER_BASE}/address/${addr}`;

/** Where to "view an NFT": Blockscout token page on Robinhood, OpenSea on Sepolia. */
export const nftCollectionUrl = (addr: string) =>
  IS_MAINNET ? `${EXPLORER_URL}/token/${addr}` : `https://testnets.opensea.io/assets/sepolia/${addr}`;
export const nftTokenUrl = (addr: string, tokenId: string | number) =>
  IS_MAINNET ? `${EXPLORER_URL}/token/${addr}/instance/${tokenId}` : `https://testnets.opensea.io/assets/sepolia/${addr}/${tokenId}`;
