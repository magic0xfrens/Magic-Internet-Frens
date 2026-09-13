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
  //  ── THE ERC20 BASKET (audit FG-1) ────────────────────────────────────
  //  Decoding only the ether events made every "dividends paid" figure
  //  undercount by the whole non-native basket — which on a rotated generation
  //  is the entire guild slice. Shapes taken from the compiled artifact
  //  (out/MiFrensDividend.sol/MiFrensDividend.json), not written by hand.
  {
    type: "event", name: "TokenDeposited", inputs: [
      { name: "asset", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event", name: "TokenClaimed", inputs: [
      { name: "tokenId", type: "uint256", indexed: true },
      { name: "asset", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event", name: "TokenWithdrawn", inputs: [
      { name: "to", type: "address", indexed: true },
      { name: "asset", type: "address", indexed: true },
      { name: "amount", type: "uint256", indexed: false },
    ],
  },
] as const;
