// Minimal CauldronRegistry ABI — the lifecycle events the indexer needs to learn
// each generation's pool (PoolId is bytes32).
export const RegistryAbi = [
  {
    type: "event",
    name: "CauldronSummoned",
    inputs: [
      { name: "generation", type: "uint256", indexed: true },
      { name: "token", type: "address", indexed: true },
      { name: "poolId", type: "bytes32", indexed: false },
      { name: "name", type: "string", indexed: false },
      { name: "symbol", type: "string", indexed: false },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "CauldronReborn",
    inputs: [
      { name: "generation", type: "uint256", indexed: true },
      { name: "token", type: "address", indexed: true },
      { name: "poolId", type: "bytes32", indexed: false },
      { name: "name", type: "string", indexed: false },
      { name: "symbol", type: "string", indexed: false },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "CauldronDied",
    inputs: [
      { name: "generation", type: "uint256", indexed: true },
      { name: "token", type: "address", indexed: true },
      { name: "deathBlock", type: "uint256", indexed: false },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "HolderClaimed", // migration via claimByBurn (fromGen → current)
    inputs: [
      { name: "generation", type: "uint256", indexed: true },
      { name: "holder", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "AutoMigrated", // keeper-executed opt-in migration
    inputs: [
      { name: "fromGen", type: "uint256", indexed: true },
      { name: "holder", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "UnclaimedBurned", // burnUnclaimed — deflation of a superseded gen
    inputs: [
      { name: "gen", type: "uint256", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
    anonymous: false,
  },
] as const;
