// MiFrensDividend — events the indexer needs for "cast the spell" + fee tracking.
export const DividendAbi = [
  {
    type: "event", name: "Deposited", inputs: [
      { name: "amount", type: "uint256", indexed: false },
      { name: "accPerShare", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event", name: "Claimed", inputs: [
      { name: "tokenId", type: "uint256", indexed: true },
      { name: "to", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event", name: "SpellCast", inputs: [
      { name: "tokenId", type: "uint256", indexed: true },
      { name: "fren", type: "address", indexed: true },
    ],
  },
  {
    type: "event", name: "SpellBroken", inputs: [
      { name: "tokenId", type: "uint256", indexed: true },
      { name: "wasFren", type: "address", indexed: true },
    ],
  },
  {
    type: "event", name: "TreasuryFunded", inputs: [
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
] as const;
