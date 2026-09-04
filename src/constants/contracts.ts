import {
  ROBINHOOD_CHAIN_ID,
  ROBINHOOD_RPC_URL,
  ROBINHOOD_EXPLORER_URL,
} from "@/config/chains";

/**
 * Deployed contract addresses on Robinhood Chain, sourced from env so they can
 * be set after deployment without a code change.
 */
const ADDRESSES = {
  magicFrensPeg: (import.meta.env.VITE_MAGIC_FRENS_PEG_ADDRESS ?? "") as string,
  presale: (import.meta.env.VITE_PRESALE_ADDRESS ?? "") as string,
  treasury: (import.meta.env.VITE_TREASURY_ADDRESS ?? "") as string,
};

export type ContractName =
  | keyof typeof ADDRESSES
  // legacy Robinhood aliases — all resolve to magicFrensPeg
  | "miFrens"
  | "frenForge"
  | "frenMarket";

/**
 * Resolve a contract address by name. The optional second argument is ignored
 * (single-chain app) but kept for source-compatibility with old callers.
 */
export function getContractAddress(name: ContractName, _chain?: unknown): string {
  const key: keyof typeof ADDRESSES =
    name === "miFrens" || name === "frenForge" || name === "frenMarket"
      ? "magicFrensPeg"
      : (name as keyof typeof ADDRESSES);

  const address = ADDRESSES[key];
  if (!address) {
    throw new Error(
      `No ${name} address configured — set the matching VITE_*_ADDRESS env var`,
    );
  }
  return address;
}

export const MAGIC_FRENS_PEG_ADDRESS = ADDRESSES.magicFrensPeg;
export const PRESALE_ADDRESS = ADDRESSES.presale;
export const TREASURY_ADDRESS = ADDRESSES.treasury;

/** Max supply of the MagicFrensPeg collection (matches the Solidity MAX_SUPPLY). */
export const MAX_NFT_SUPPLY = 1111;

/** Commit fee in tokens (0.5 tokens, 18 decimals). */
export const COMMIT_FEE = "500000000000000000";

/** Unit per Fren (1 token = 1e18 wei). */
export const UNIT_PER_FREN = "1000000000000000000";

/** Price (in ETH) charged on buyFren(), if any. buyFren is payable; default 0. */
export const MINT_PRICE_ETH = (import.meta.env.VITE_MINT_PRICE_ETH ?? "0") as string;

/** Legacy export kept for source-compatibility (unused on EVM). */
export const DEFAULT_MINT_PRICE_SATS = 0n;

/** External DEX / token trading URL (env-driven; set once a pool exists). */
export const MOTOSWAP_URL = (import.meta.env.VITE_DEX_URL ?? "#") as string;

export const SUPPORTED_CHAINS = [
  {
    id: ROBINHOOD_CHAIN_ID,
    name: "Robinhood Chain",
    rpc: ROBINHOOD_RPC_URL,
    explorer: ROBINHOOD_EXPLORER_URL,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  },
] as const;
