type Table = { name: string; [key: string]: unknown };
const table = (name: string): Table => new Proxy({ name }, {
  get(target, prop) { return prop in target ? target[prop as string] : `${name}.${String(prop)}`; },
});

export const pool = table("pool");
export const candle = table("candle");
export const swap = table("swap");
export const collection = table("collection");
export const nft = table("nft");
export const holder = table("holder");
export const gachaPlayer = table("gachaPlayer");
export const proposal = table("proposal");
export const vote = table("vote");
export const enchant = table("enchant");
export const dividendStat = table("dividendStat");
export const dividendAsset = table("dividendAsset");
export const iteration = table("iteration");
export const perpPosition = table("perpPosition");
export const perpStat = table("perpStat");
export const liquidator = table("liquidator");
export const genesisFloor = table("genesisFloor");
export const floorEvent = table("floorEvent");
export const collectionFloor = table("collectionFloor");
export const collectionFloorEvent = table("collectionFloorEvent");
export const proposerEarning = table("proposerEarning");
export const seedEvent = table("seedEvent");
export const seedState = table("seedState");
export const rotationProposal = table("rotationProposal");
export const rotationVote = table("rotationVote");
export const rotationSlice = table("rotationSlice");
export const ownedPosition = table("ownedPosition");

export default {
  pool, candle, swap, collection, nft, holder, gachaPlayer, proposal, vote,
  enchant, dividendStat, dividendAsset, iteration, perpPosition, perpStat,
  liquidator, genesisFloor, floorEvent, collectionFloor, collectionFloorEvent,
  proposerEarning, seedEvent, seedState, rotationProposal, rotationVote,
  rotationSlice, ownedPosition,
};
