import { sepolia } from "viem/chains";
import type { Address } from "viem";

/**
 * Live MiFrensPresale deployment (the genesis fundraise contract the UI mints
 * against). Update after each deploy. Canonical Sepolia address from
 * contracts/solidity/deployments/sepolia.json.
 */
export const PRESALE = {
  chainId: sepolia.id,
  address: "0x4D180c050978F0037d030BaC455c3cfA70aAA8e1" as Address, // round-17 MiFrensGenesis (cancel/refund + batch claim, 30% bonus)
  priceEth: 0.0222, // per MiFren — matches round-17 PRICE (live at real price)
  maxSupply: 1111,  // genesis (OG) tranche; art cap 2222 incl. volume mints
  maxPerWallet: 1200,
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
