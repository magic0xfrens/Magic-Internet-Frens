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
  //  DISPLAY FALLBACK ONLY, and it is the LAST resort.
  //
  //  This said "the mint reads PRICE() on-chain before sending" and the mint did
  //  not: it multiplied a hardcoded `priceWei`. When a round redeployed at a
  //  different price, every mint sent the old value and reverted `WrongPrice` —
  //  with the UI still cheerfully quoting the old number. The hook now reads
  //  PRICE() from the contract at send time AND for display; this constant is
  //  only what renders before that first read resolves.
  priceEth: 0.1111,
  /** EXACT wei, so value = priceWei * quantity cannot drift into WrongPrice. */
  priceWei: 111100000000000000n,
  maxSupply: round.genesisSupply ?? 1111,
  /**
   *  ── THERE IS NO EFFECTIVE ANTI-WHALE CAP ON THE DEPLOYED CONTRACT ────────
   *  This used to read `maxPerWallet: 100` with a comment saying the contract
   *  enforced it. VERIFIED by `cast call` against the live genesis contract
   *  (0xfd488978…92ba): `MAX_PER_WALLET() = 1111 = GENESIS_SUPPLY()`, so the
   *  cap at MiFrensGenesis.sol:268 can never bind — one wallet could hold the
   *  entire genesis supply, and with it `getVotes = 1111`.
   *
   *  `MAX_PER_WALLET` is `immutable` (MiFrensGenesis.sol:119, set once at :243)
   *  with no setter, so this is NOT fixable in code on a deployed contract: it
   *  is a constructor argument, chosen at deploy time. The honest thing the app
   *  can do is stop asserting a limit that does not exist.
   *
   *  `null` = no cap the UI may claim. Anything rendering a per-wallet limit
   *  must read `MAX_PER_WALLET()` from the chain and show THAT, or show nothing.
   */
  maxPerWallet: null as number | null,
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
  //  RENAMED ON-CHAIN: `finalize` -> `igniteCauldron`. The storage flag and the
  //  `Finalized` event deliberately KEPT their old names (the indexer and
  //  /presale read them), so only the call changes. An ABI left on `finalize`
  //  does not fail loudly - the selector simply does not exist on the contract
  //  and the ignition button reverts.
  { type: "function", name: "igniteCauldron", stateMutability: "nonpayable", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "finalized", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  // Stalled-presale safety valve: deployer cancels, minters reclaim their ETH.
  { type: "function", name: "cancelled", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "cancelPresale", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "refund", stateMutability: "nonpayable", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "paid", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  //  The frenlist: (wallet, allowance) at a tenth of PRICE. Proofs live at
  //  /frenlist/<discountRoot>.json (see scripts/frenlist).
  {
    type: "function", name: "mintDiscounted", stateMutability: "payable",
    inputs: [
      { name: "quantity", type: "uint256" },
      { name: "allowance", type: "uint256" },
      { name: "proof", type: "bytes32[]" },
    ],
    outputs: [],
  },
  { type: "function", name: "DISCOUNT_PRICE", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "discountRoot", stateMutability: "view", inputs: [], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "discountMinted", stateMutability: "view", inputs: [{ name: "wallet", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "error", name: "NoDiscount", inputs: [] },
  //  THE CUSTOM ERRORS. Without these in the ABI a revert decodes to nothing but
  //  a bare selector (`0xf7760f25`), which is what a user was shown when a stale
  //  hardcoded price made every mint revert with WrongPrice. With them, viem
  //  resolves `errorName` and the UI can say what actually went wrong.
  { type: "error", name: "WrongPrice", inputs: [] },
  { type: "error", name: "PerWalletCap", inputs: [] },
  { type: "error", name: "ExceedsSupply", inputs: [] },
  { type: "error", name: "PresaleOver", inputs: [] },
  { type: "error", name: "AlreadyCancelled", inputs: [] },
  { type: "error", name: "NotSoldOut", inputs: [] },
  { type: "error", name: "NotAuthorized", inputs: [] },
  { type: "error", name: "RegistryNotSet", inputs: [] },
  { type: "error", name: "AlreadyFinalized", inputs: [] },
] as const;
