/**
 * TREASURY ROTATION governance + execution events.
 *
 * Distinct from `GovernorAbi`, which is the BREW governor (CauldronGovernor —
 * "what is the next iteration called"). This one governs what the LP is
 * denominated in, and it was indexed nowhere: proposals, votes and executed
 * rotations existed only on chain, so the app could show a "Propose" button and
 * then nothing that resulted from pressing it.
 *
 * Every signature below was checked against a real Sepolia log rather than read
 * off the source — `SliceRotated`'s second parameter is an `address` (the quote
 * rotated FROM), which is easy to mistake for the leg index it sits next to in
 * the call.
 */
export const TreasuryGovAbi = [
  { type: "event", name: "Proposed", inputs: [
    { name: "id", type: "uint256", indexed: true },
    { name: "proposer", type: "address", indexed: true },
    { name: "quote", type: "address", indexed: false },
    { name: "maxTotalBps", type: "uint16", indexed: false },
  ], anonymous: false },
  { type: "event", name: "Voted", inputs: [
    { name: "id", type: "uint256", indexed: true },
    { name: "voter", type: "address", indexed: true },
    { name: "support", type: "bool", indexed: false },
    { name: "weight", type: "uint256", indexed: false },
  ], anonymous: false },
  { type: "event", name: "Executed", inputs: [
    { name: "id", type: "uint256", indexed: true },
    { name: "quote", type: "address", indexed: false },
    { name: "maxTotalBps", type: "uint16", indexed: false },
    { name: "expiry", type: "uint64", indexed: false },
  ], anonymous: false },
  { type: "event", name: "Cancelled", inputs: [
    { name: "id", type: "uint256", indexed: true },
    { name: "by", type: "address", indexed: false },
  ], anonymous: false },
  { type: "event", name: "EnvelopeConsumed", inputs: [
    { name: "bps", type: "uint16", indexed: false },
    { name: "movedTotal", type: "uint16", indexed: false },
  ], anonymous: false },
] as const;

/** Rotation EXECUTION, emitted by RedemptionExt through the registry. */
export const RotationExecAbi = [
  { type: "event", name: "SliceRotated", inputs: [
    { name: "gen", type: "uint256", indexed: true },
    { name: "from", type: "address", indexed: true },
    { name: "to", type: "address", indexed: true },
    { name: "quoteIn", type: "uint256", indexed: false },
    { name: "quoteOut", type: "uint256", indexed: false },
    { name: "sliceBps", type: "uint16", indexed: false },
  ], anonymous: false },
  { type: "event", name: "LegOpened", inputs: [
    { name: "gen", type: "uint256", indexed: true },
    { name: "quote", type: "address", indexed: true },
    { name: "positionId", type: "uint256", indexed: false },
  ], anonymous: false },
  { type: "event", name: "GenerationRequoted", inputs: [
    { name: "gen", type: "uint256", indexed: true },
    { name: "from", type: "address", indexed: true },
    { name: "to", type: "address", indexed: true },
  ], anonymous: false },
] as const;

/** ERC721 Transfer, for tracking which LP positions the registry OWNS. */
export const Erc721TransferAbi = [
  { type: "event", name: "Transfer", inputs: [
    { name: "from", type: "address", indexed: true },
    { name: "to", type: "address", indexed: true },
    { name: "tokenId", type: "uint256", indexed: true },
  ], anonymous: false },
] as const;
