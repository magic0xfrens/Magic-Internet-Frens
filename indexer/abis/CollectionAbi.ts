// Per-brew NFT collection (CauldronCollection + MiFrensPresale share these).
export const CollectionAbi = [
  { type: "event", name: "Transfer", inputs: [
    { name: "from", type: "address", indexed: true },
    { name: "to", type: "address", indexed: true },
    { name: "tokenId", type: "uint256", indexed: true },
  ], anonymous: false },
  { type: "event", name: "Minted", inputs: [
    { name: "to", type: "address", indexed: true },
    { name: "tokenId", type: "uint256", indexed: true },
    { name: "rarity", type: "uint8", indexed: false },
  ], anonymous: false },
  { type: "event", name: "VolumeMinted", inputs: [
    { name: "to", type: "address", indexed: true },
    { name: "tokenId", type: "uint256", indexed: true },
    { name: "rarity", type: "uint8", indexed: false },
  ], anonymous: false },
  { type: "event", name: "Revealed", inputs: [
    { name: "tokenId", type: "uint256", indexed: true },
    { name: "rarity", type: "uint8", indexed: false },
  ], anonymous: false },
] as const;
