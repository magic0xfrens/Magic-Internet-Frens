// CauldronSeeder — the progressive launch stream + the tranched prime buy.
// Only the events the indexer turns into the live seeding feed.
export const SeederAbi = [
  {
    type: "event",
    name: "SeedStarted",
    inputs: [
      { name: "gen", type: "uint256", indexed: true },
      { name: "ethTotal", type: "uint256", indexed: false },
      { name: "tokenTotal", type: "uint256", indexed: false },
      { name: "window", type: "uint64", indexed: false },
    ],
  },
  {
    type: "event",
    name: "BasePlaced",
    inputs: [
      { name: "gen", type: "uint256", indexed: true },
      { name: "fullRangeLiquidity", type: "uint128", indexed: false },
    ],
  },
  {
    type: "event",
    name: "Poked",
    inputs: [
      { name: "fromWad", type: "uint256", indexed: false },
      { name: "toWad", type: "uint256", indexed: false },
      { name: "tick", type: "int24", indexed: false },
    ],
  },
  {
    type: "event",
    name: "SeedComplete",
    inputs: [{ name: "gen", type: "uint256", indexed: true }],
  },
  {
    type: "event",
    name: "PrimeFunded",
    inputs: [
      { name: "to", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
      { name: "budget", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "PrimeBought",
    inputs: [
      { name: "gen", type: "uint256", indexed: true },
      { name: "ethIn", type: "uint256", indexed: false },
      { name: "tokenOut", type: "uint256", indexed: false },
      { name: "spent", type: "uint256", indexed: false },
      { name: "budget", type: "uint256", indexed: false },
    ],
  },
] as const;
