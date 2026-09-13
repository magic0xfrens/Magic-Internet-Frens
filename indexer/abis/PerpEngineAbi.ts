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
  //  ── PARTIAL DEATH-BAND FILLS (audit C-4) ─────────────────────────────
  //  The dead path no longer reverts outside the mark band: it fills what the
  //  pool can supply inside it and rebooks the rest, which on a thin pool is now
  //  the NORMAL outcome. Without these two the indexer kept the position's
  //  pre-close size and the pre-close open count forever. Shapes from
  //  out/PerpEngine.sol/PerpEngine.json.
  {
    type: "event", name: "PartiallyClosed", inputs: [
      { name: "id", type: "uint256", indexed: true },
      { name: "bought", type: "uint256", indexed: false },
      { name: "cost", type: "uint256", indexed: false },
      { name: "remaining", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event", name: "TokenDebtWrittenOff", inputs: [
      { name: "id", type: "uint256", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  //  Distinguishes a PARKED engine from a dead token (audit C-1): nothing read
  //  this, so off-chain there was no way to tell the two apart.
  {
    type: "event", name: "GenerationSynced", inputs: [
      { name: "fromGen", type: "uint256", indexed: true },
      { name: "toGen", type: "uint256", indexed: true },
      { name: "migratedIn", type: "uint256", indexed: false },
      { name: "newInventory", type: "uint256", indexed: false },
    ],
  },
] as const;

// Minimal registry read for the current generation (RegistryAbi is events-only).
export const RegistryGenReadAbi = [
  { type: "function", name: "currentGeneration", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "generationPoolId", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "bytes32" }] },
  // The asset a generation's token is PRICED IN (0 = native ETH). Recorded at
  // rebirth and fixed for that generation's whole life, so one read per pool
  // registration is enough.
  { type: "function", name: "generationQuote", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] },
] as const;
