// r30: redemption-floor + legacy-collection-floor events. Registered on the
// registry (RegistryFloorAbi) and the hook (HookFloorAbi) addresses so the
// indexer tracks the genesis recycle-ratchet floor (redeem / buy-2x / grow), the
// per-collection legacy floor (recycle / buy), and the proposer flywheel payouts.

export const RegistryFloorAbi = [
  // genesis fren RECYCLED for the live floor (paid from the reserve; NFT → treasury)
  { type: "event", name: "FrenRedeemed", inputs: [
    { name: "mifrenTokenId", type: "uint256", indexed: true },
    { name: "holder", type: "address", indexed: true },
    { name: "amount", type: "uint256", indexed: false },
    { name: "generation", type: "uint256", indexed: true },
  ], anonymous: false },
  // treasury fren BOUGHT for 2x floor (payment added to the reserve → floor grows)
  { type: "event", name: "FrenBought", inputs: [
    { name: "mifrenTokenId", type: "uint256", indexed: true },
    { name: "buyer", type: "address", indexed: true },
    { name: "paid", type: "uint256", indexed: false },
    { name: "generation", type: "uint256", indexed: true },
  ], anonymous: false },
  // floor RATCHET — reserve grew, new floor-per-fren
  { type: "event", name: "FloorGrew", inputs: [
    { name: "addedToReserve", type: "uint256", indexed: false },
    { name: "newReserve", type: "uint256", indexed: false },
    { name: "newFloorPerFren", type: "uint256", indexed: false },
  ], anonymous: false },
  // per-collection LEGACY floor: a dead collection's NFT recycled for its floor
  { type: "event", name: "CollectionRecycled", inputs: [
    { name: "gen", type: "uint256", indexed: true },
    { name: "tokenId", type: "uint256", indexed: true },
    { name: "holder", type: "address", indexed: true },
    { name: "payout", type: "uint256", indexed: false },
  ], anonymous: false },
  // per-collection LEGACY floor: a recycled NFT bought back for 2x (floor grows)
  { type: "event", name: "CollectionBought", inputs: [
    { name: "gen", type: "uint256", indexed: true },
    { name: "tokenId", type: "uint256", indexed: true },
    { name: "buyer", type: "address", indexed: true },
    { name: "paid", type: "uint256", indexed: false },
  ], anonymous: false },
] as const;

export const HookFloorAbi = [
  // proposer flywheel — a slice of the fee accrued to the iteration's proposer
  { type: "event", name: "ProposerFunded", inputs: [
    { name: "proposer", type: "address", indexed: true },
    { name: "amount", type: "uint256", indexed: false },
  ], anonymous: false },
] as const;
