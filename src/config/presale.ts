import type { Address } from "viem";
import { ACTIVE_CHAIN_ID } from "@/config/chains";

/**
 * Live MiFrensPresale deployment (the genesis fundraise contract the UI mints
 * against). Update after each deploy. Address is per-deployment; chainId follows
 * the active network (VITE_NETWORK).
 */
export const PRESALE = {
  chainId: ACTIVE_CHAIN_ID,
  address: "0x648604e8fe6ebda37acd58906347b9531799a1a7" as Address, // round-31 MiFrensGenesis (SOLD OUT + summoned)
  priceEth: 0.0062,   // per MiFren (round-31 thin-LP rehearsal) — display only
  priceWei: 6200000000000000n, // EXACT on-chain PRICE; value = priceWei * quantity (no float drift → no WrongPrice revert)
  maxSupply: 1111,     // genesis (OG) tranche; art cap 2222 incl. volume mints
  maxPerWallet: 1200,  // per-wallet cap this round (deployer minted the bulk)
};

/** Minimal ABI — only what the mint UI needs. */
export const PRESALE_ABI = [
  { type: "function", name: "mint", stateMutability: "payable", inputs: [{ name: "quantity", type: "uint256" }], outputs: [] },
  { type: "function", name: "minted", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "MAX_SUPPLY", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "PRICE", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "MAX_PER_WALLET", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "soldOut", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "remaining", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ name: "owner", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "finalize", stateMutability: "nonpayable", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "finalized", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  // Stalled-presale safety valve: deployer cancels, minters reclaim their ETH.
  { type: "function", name: "cancelled", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "cancelPresale", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "refund", stateMutability: "nonpayable", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "paid", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
] as const;
