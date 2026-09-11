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
  //  NO `UnclaimedBurned`. The event exists in no compiled artifact (verified
  //  against contracts/solidity/out: 333 events, none with this name), so the
  //  filter could never fire and `iteration.burned` was a permanent 0 served as
  //  an indexed statistic. A dead entry left "just in case" is the bug itself.
  
] as const;
