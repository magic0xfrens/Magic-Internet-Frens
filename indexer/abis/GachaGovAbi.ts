// CauldronHook gacha events + registry CollectionDeployed + governor events.
export const HookGachaAbi = [
  { type: "event", name: "CrystalsCommitted", inputs: [
    { name: "player", type: "address", indexed: true },
    { name: "count", type: "uint256", indexed: false },
    { name: "oddsBps", type: "uint256", indexed: false },
  ], anonymous: false },
  { type: "event", name: "TicketWon", inputs: [
    { name: "player", type: "address", indexed: true },
    { name: "ticketId", type: "uint256", indexed: true },
    { name: "tokenId", type: "uint256", indexed: false },
  ], anonymous: false },
  { type: "event", name: "TicketLost", inputs: [
    { name: "player", type: "address", indexed: true },
    { name: "ticketId", type: "uint256", indexed: true },
  ], anonymous: false },
] as const;

export const RegistryCollAbi = [
  { type: "event", name: "CollectionDeployed", inputs: [
    { name: "generation", type: "uint256", indexed: true },
    { name: "collection", type: "address", indexed: false },
    { name: "mode", type: "uint8", indexed: false },
  ], anonymous: false },
] as const;

export const GovernorAbi = [
  { type: "event", name: "Proposed", inputs: [
    { name: "proposalId", type: "uint256", indexed: true },
    { name: "proposer", type: "address", indexed: true },
    { name: "name", type: "string", indexed: false },
    { name: "symbol", type: "string", indexed: false },
    { name: "mode", type: "uint8", indexed: false },
  ], anonymous: false },
  { type: "event", name: "Voted", inputs: [
    { name: "proposalId", type: "uint256", indexed: true },
    { name: "voter", type: "address", indexed: true },
    { name: "weight", type: "uint256", indexed: false },
    { name: "totalVotes", type: "uint256", indexed: false },
  ], anonymous: false },
] as const;
