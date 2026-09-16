import { defineChain, http, fallback } from "viem";
import { sepolia } from "viem/chains";
import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { injectedWallet, walletConnectWallet } from "@rainbow-me/rainbowkit/wallets";
import { SELECTED_CHAIN_ID, DEPLOY_CHAIN_IDS } from "./deployments";

/**
 * THE DEPLOYMENT TARGET CHAIN — defined entirely from env, named by no vendor.
 *
 *  This used to be a single hardcoded vendor chain. It is generic now because the
 *  protocol is genuinely chain-agnostic and had started to look otherwise: the
 *  only hard requirement is EIP-1153 transient storage (Uniswap v4 settles every
 *  `unlock` through TSTORE/TLOAD) plus a CREATE2 factory, since the hook's
 *  permission bits live in its ADDRESS and so it must be mined. Anything meeting
 *  those two runs this stack unmodified — Arc testnet was brought up by setting
 *  the five variables below and nothing else.
 *
 *  NATIVE CURRENCY IS PART OF THAT, not decoration. It is NOT safe to assume
 *  "ETH, 18 decimals": Arc's gas token is USD-denominated, and a chain with a
 *  6-decimal native would misprice every wei-denominated figure in the app by
 *  1e12. So symbol/name/decimals are env-driven too, and the decimals are
 *  validated rather than trusted.
 */
//  NO HARDCODED CHAIN ID HERE ANY MORE. `SELECTED_CHAIN_ID` is resolved in
//  deployments.ts from the MANIFEST'S OWN `chainId` (and VITE_CHAIN_ID is
//  validated against the bundled set there, fatally). A second, independent
//  default here — it used to be 5042002, Arc testnet — is exactly how a
//  Robinhood build ended up describing itself as Arc: `targetChain` said one
//  chain while the addresses came from another.
//
//  `targetChain` is the NON-Sepolia chain the app offers. When the selection is
//  itself non-Sepolia that is the selection; when Sepolia is selected it is the
//  other bundled manifest, so the switcher has somewhere to switch TO. Never an
//  env guess.
const OTHER_CHAIN_ID = DEPLOY_CHAIN_IDS.find((id) => id !== sepolia.id) ?? sepolia.id;
const CHAIN_ID = SELECTED_CHAIN_ID !== sepolia.id ? SELECTED_CHAIN_ID : OTHER_CHAIN_ID;

/** Empty-string-safe env read: Vercel sets declared-but-blank vars to "". */
const env = (key: string, fallbackValue: string) => {
  const raw = (import.meta.env[key as keyof ImportMetaEnv] as string | undefined)?.trim();
  return raw ? raw : fallbackValue;
};

/**
 *  Per-chain metadata defaults, keyed by chain id.
 *
 *  A single flat default ("Arc Testnet", the Arc RPC) is wrong for every chain
 *  but one, and wrong SILENTLY: an unset `VITE_RPC_URL` on chain 4663 used to
 *  point a mainnet app at a testnet RPC. Keying by the chain the app actually
 *  resolved to means the unset case is at worst incomplete, never misdirected —
 *  and for a chain not listed here, `RPC_URL` below refuses rather than guesses.
 */
const CHAIN_DEFAULTS: Record<
  number,
  { name: string; rpc: string; explorer: string; explorerName: string; currency: string; currencyName: string; decimals: number; testnet: boolean }
> = {
  5042002: { name: "Arc Testnet", rpc: "https://rpc.testnet.arc.network", explorer: "https://testnet.arcscan.app", explorerName: "Arcscan", currency: "USD", currencyName: "US Dollar", decimals: 18, testnet: true },
  //  VERIFIED against the live chain and ethereum-lists/chains eip155-4663:
  //  id 4663, native ETH/18, rpc.MAINNET.chain.robinhood.com. The host
  //  `rpc.chain.robinhood.com` that our docs used to carry does not exist — it
  //  refuses TLS from every client — so it must never appear as a default.
  4663: { name: "Robinhood Chain", rpc: "https://rpc.mainnet.chain.robinhood.com", explorer: "https://robinhoodchain.blockscout.com", explorerName: "Blockscout", currency: "ETH", currencyName: "Ether", decimals: 18, testnet: false },
  46630: { name: "Robinhood testnet", rpc: "https://rpc.testnet.chain.robinhood.com", explorer: "https://robinhoodchain.blockscout.com", explorerName: "Blockscout", currency: "ETH", currencyName: "Ether", decimals: 18, testnet: true },
  11155111: { name: "Sepolia", rpc: "https://ethereum-sepolia-rpc.publicnode.com", explorer: "https://sepolia.etherscan.io", explorerName: "Etherscan", currency: "ETH", currencyName: "Ether", decimals: 18, testnet: true },
};

const D = CHAIN_DEFAULTS[CHAIN_ID];

const CHAIN_NAME = env("VITE_CHAIN_NAME", D?.name ?? `Chain ${CHAIN_ID}`);
//  An RPC is the one value with no safe guess. Unknown chain + unset env = stop.
const RPC_URL = (() => {
  const u = env("VITE_RPC_URL", D?.rpc ?? "");
  if (!u) {
    throw new Error(
      `[cauldron] NO RPC FOR CHAIN ${CHAIN_ID} — set VITE_RPC_URL, or add the chain to CHAIN_DEFAULTS ` +
        `in src/config/chains.ts. Refusing to fall back to another chain's RPC.`,
    );
  }
  return u;
})();
const EXPLORER_URL = env("VITE_EXPLORER_URL", D?.explorer ?? "");

/** Additional VERIFIED endpoints per chain, used only as ordered failover
 *  BEHIND `RPC_URL`. Sourced from CHAIN_PROFILE.md §8 — two independent nodes
 *  that agreed on the same block hash at a fixed height. Nothing unverified
 *  goes in here: a hostile RPC chooses the prices a user signs against. */
const BACKUP_RPCS: Record<number, string[]> = {
  4663: ["https://robinhood-rpc.publicnode.com"],
};
/** `VITE_RPC_URL` may itself be a COMMA-SEPARATED list, same as the Sepolia
 *  one — several keys multiply the effective rate limit. */
const TARGET_RPCS: string[] = [
  ...RPC_URL.split(",").map((u) => u.trim()).filter(Boolean),
  ...(BACKUP_RPCS[CHAIN_ID] ?? []),
].filter((u, i, a) => a.indexOf(u) === i);

const EXPLORER_NAME = env("VITE_EXPLORER_NAME", D?.explorerName ?? "Explorer");

//  Decimals are VALIDATED, not trusted. A bad value here would not throw — it
//  would silently shift every balance the UI formats by orders of magnitude,
//  which is the kind of bug that gets read as a pricing error rather than a
//  config error. Anything outside 0..36 falls back to 18.
const RAW_DECIMALS = Number(import.meta.env.VITE_CHAIN_DECIMALS);
const CHAIN_DECIMALS =
  Number.isSafeInteger(RAW_DECIMALS) && RAW_DECIMALS >= 0 && RAW_DECIMALS <= 36
    ? RAW_DECIMALS
    : (D?.decimals ?? 18);

export const targetChain = defineChain({
  id: CHAIN_ID,
  name: CHAIN_NAME,
  nativeCurrency: {
    name: env("VITE_CHAIN_CURRENCY_NAME", D?.currencyName ?? "Ether"),
    symbol: env("VITE_CHAIN_CURRENCY", D?.currency ?? "ETH"),
    decimals: CHAIN_DECIMALS,
  },
  rpcUrls: {
    default: { http: TARGET_RPCS },
    public: { http: TARGET_RPCS },
  },
  blockExplorers: {
    default: { name: EXPLORER_NAME, url: EXPLORER_URL },
  },
  //  Declared, not inferred from the id — the previous `=== 46646` check was a
  //  single hardcoded chain's testnet id and read `false` for every other chain.
  testnet: env("VITE_CHAIN_IS_TESTNET", D ? String(D.testnet) : "true") !== "false",
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

// ── SINGLE NETWORK SWITCH ───────────────────────────────────────────────────
// The app targets ONE chain at a time, and the user picks which from the wallet
// card. Everything — config chainIds, wallet switch, explorer links, copy —
// reads from ACTIVE_* / IS_TARGET / NETWORK_LABEL below, so there is no
// per-file drift. Declared ABOVE wagmiConfig because the chain order depends
// on it.
//
//  ONE RESOLUTION ORDER, NOT TWO. `SELECTED_CHAIN_ID` already folds
//  in the env default, the `?chain=` param and the persisted choice, so deriving
//  from it here keeps ONE resolution order for the whole app — two independent
//  ones would eventually disagree, and the symptom would be a header naming one
//  chain while the addresses came from the other.
export const IS_TARGET = SELECTED_CHAIN_ID !== sepolia.id;
/** @deprecated Prefer {@link IS_TARGET} — the target chain need not be a mainnet. */
export const IS_MAINNET = IS_TARGET;
export const IS_TESTNET = !IS_TARGET;

export const wagmiConfig = getDefaultConfig({
  appName: "Magic Internet Frens",
  projectId: WALLETCONNECT_PROJECT_ID,
  // Sepolia is included so the genesis presale can mint against the live
  // MiFrensPresale during testnet; `targetChain` is the cut-over target.
  // ORDER MATTERS: wagmi seeds `state.chainId` from `chains[0]`, so the ACTIVE
  // network must lead — otherwise a testnet build boots pointed at the target
  // chain and every read hook defaults to a chain the deployment doesn't use.
  chains: IS_TARGET ? [targetChain, sepoliaFixed] : [sepoliaFixed, targetChain],
  transports: {
    // Batch JSON-RPC calls within a ~24ms window into ONE HTTP request (fewer
    // requests → far less rate-limiting on public nodes), and roll over to the
    // next node on a 429/error. A dedicated VITE_SEPOLIA_RPC_URL is tried first.
    [sepolia.id]: fallback(
      SEPOLIA_RPCS.map((u) => http(u, { batch: { wait: 24 }, retryCount: 2, retryDelay: 250 })),
      { retryCount: 2, retryDelay: 300 },
    ),
    //  ── THE TARGET CHAIN GETS FAILOVER TOO ──────────────────────────────
    //  This was a single `http(RPC_URL)`: one endpoint, no retry, no failover,
    //  while Sepolia kept a four-way fallback. On chain 4663 there are only TWO
    //  working public endpoints and no free archive, so an RPC error is normal
    //  rather than exceptional — and because the quote/decimals reads poll on a
    //  300 s cadence, ONE 429 left the trade panel unpriceable for five minutes.
    //  Ordered (`rank: false`), never latency-shuffled, so the configured
    //  primary stays primary.
    //  ONLY endpoints verified in audit/RH_MAINNET_2026-09-16/CHAIN_PROFILE.md
    //  §8 appear here: two independent nodes agreed on the same block hash at a
    //  fixed height. Lookalike/phishing RPC hosts exist for this chain (one
    //  serves HTML, another prunes), so do NOT add an endpoint that document has
    //  not verified — a hostile RPC picks the prices a user signs against.
    [targetChain.id]: fallback(
      TARGET_RPCS.map((u) => http(u, { batch: { wait: 24 }, retryCount: 2, retryDelay: 250 })),
      { rank: false, retryCount: 1, retryDelay: 300 },
    ),
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

export const CHAIN = targetChain;
export const TARGET_CHAIN_ID = CHAIN_ID;
export const TARGET_CHAIN_NAME = CHAIN_NAME;
export const TARGET_RPC_URL = RPC_URL;
export const TARGET_EXPLORER_URL = EXPLORER_URL;
/** Native gas-token symbol of the ACTIVE chain. Not always "ETH" — see above. */

// ── ACTIVE NETWORK (switch itself lives above wagmiConfig) ──────────────────
export const ACTIVE_CHAIN = IS_TARGET ? targetChain : sepoliaFixed;
export const ACTIVE_CHAIN_ID = ACTIVE_CHAIN.id;

//  Read off the ACTIVE chain, not re-derived from IS_TARGET: the old form
//  hardcoded ETH/18 for the whole non-target branch, which silently discarded
//  VITE_CHAIN_DECIMALS/VITE_CHAIN_CURRENCY on any build where IS_TARGET was
//  false for the wrong reason.
export const NATIVE_SYMBOL = ACTIVE_CHAIN.nativeCurrency.symbol;
export const NATIVE_DECIMALS = ACTIVE_CHAIN.nativeCurrency.decimals;
export const NETWORK_LABEL = IS_TARGET ? CHAIN_NAME : "Sepolia testnet";
//  First word of the chain name, so a rename needs no second edit here.
export const NETWORK_SHORT = IS_TARGET ? (CHAIN_NAME.split(/\s+/)[0] || CHAIN_NAME) : "Sepolia";

/** Block-explorer base for the active chain. */
export const EXPLORER_BASE = IS_TARGET ? EXPLORER_URL : "https://sepolia.etherscan.io";
export const explorerTxUrl = (hash: string) => `${EXPLORER_BASE}/tx/${hash}`;
export const explorerAddressUrl = (addr: string) => `${EXPLORER_BASE}/address/${addr}`;

/** Where to "view an NFT": the chain's own explorer token page on the target
 *  chain, OpenSea on Sepolia (which has a real NFT marketplace and most target
 *  chains will not). Blockscout-style `/token/<addr>/instance/<id>` paths are
 *  the common shape; override with VITE_EXPLORER_URL if a chain differs. */
export const nftCollectionUrl = (addr: string) =>
  IS_TARGET ? `${EXPLORER_URL}/token/${addr}` : `https://testnets.opensea.io/assets/sepolia/${addr}`;
export const nftTokenUrl = (addr: string, tokenId: string | number) =>
  IS_TARGET ? `${EXPLORER_URL}/token/${addr}/instance/${tokenId}` : `https://testnets.opensea.io/assets/sepolia/${addr}/${tokenId}`;
