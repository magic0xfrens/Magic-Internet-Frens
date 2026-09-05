import type { Address } from "viem";
import { CAULDRON } from "@/config/cauldron";
import round from "../../indexer/deployments/round.json";

/**
 * The live MiFrensGenesis deployment the mint UI talks to.
 *
 * ADDRESS AND CHAIN COME FROM THE MANIFEST, never from a literal here. This file
 * used to hardcode its own address, which silently went stale two deployments
 * ago: the manifest pointed at the current contract while the mint modal still
 * read a round-31 one, so a sold-out presale rendered as "0 / 1111".
 *
 * Nothing about a deployment should be written twice. Everything below that CAN
 * be read from the chain is; only display defaults remain, and they are marked.
 */
export const PRESALE = {
  chainId: CAULDRON.chainId,
  address: CAULDRON.mifrens as Address,
  /** Display default only — the mint reads PRICE() on-chain before sending. */
  priceEth: 0.0062,
  /** EXACT wei, so value = priceWei * quantity cannot drift into WrongPrice. */
  priceWei: 6200000000000000n,
  maxSupply: round.genesisSupply ?? 1111,
  /** Contract enforces MAX_PER_WALLET; this is only a UI hint. */
  maxPerWallet: 100,
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
