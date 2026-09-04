// Events emitted by contracts/solidity/cauldron/PerpEngine.sol (Phase 2).
// Only what the indexer needs to reconstruct open positions + OI.
export const PerpEngineAbi = [
  {
    type: "event",
    name: "Opened",
    inputs: [
      { name: "id", type: "uint256", indexed: true },
      { name: "trader", type: "address", indexed: true },
      { name: "isLong", type: "bool", indexed: false },
      { name: "collateral", type: "uint256", indexed: false },
      { name: "size", type: "uint256", indexed: false },
      { name: "leverage", type: "uint8", indexed: false },
    ],
  },
  {
    type: "event",
    name: "Closed",
    inputs: [
      { name: "id", type: "uint256", indexed: true },
      { name: "trader", type: "address", indexed: true },
      { name: "payout", type: "uint256", indexed: false },
      { name: "pnl", type: "int256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "Liquidated",
    inputs: [
      { name: "id", type: "uint256", indexed: true },
      { name: "keeper", type: "address", indexed: true },
      { name: "penalty", type: "uint256", indexed: false },
    ],
  },
  {
    // A Liquidatoor badge was awarded to `to` for liquidating position `id`.
    // badgeId 0 = collection wasn't wired for badges.
    type: "event",
    name: "LiquidatoorAwarded",
    inputs: [
      { name: "id", type: "uint256", indexed: true },
      { name: "to", type: "address", indexed: true },
      { name: "badgeId", type: "uint256", indexed: false },
    ],
  },
  // read used to scope a position to the live generation at open time
  { type: "function", name: "maintenanceBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

// Minimal registry read for the current generation (RegistryAbi is events-only).
export const RegistryGenReadAbi = [
  { type: "function", name: "currentGeneration", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "generationPoolId", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "bytes32" }] },
] as const;
