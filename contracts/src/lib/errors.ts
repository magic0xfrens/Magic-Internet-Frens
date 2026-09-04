// ---------------------------------------------------------------------------
// Oracle Errors
// ---------------------------------------------------------------------------

export const ERR_ORACLE_NO_PRICE: string = 'Oracle: no price set';
export const ERR_ORACLE_STALE: string = 'Oracle: price is stale';
export const ERR_ORACLE_ZERO_PRICE: string = 'Oracle: price must be > 0';
export const ERR_ORACLE_NOT_ADMIN: string = 'Oracle: caller is not admin';
export const ERR_ORACLE_ZERO_ADDR: string = 'Oracle: zero address';
export const ERR_ORACLE_DEVIATION: string = 'Oracle: price change exceeds max deviation';

// ---------------------------------------------------------------------------
// MIF Token Errors
// ---------------------------------------------------------------------------

export const ERR_MIF_NOT_MINTER: string = 'MIF: caller is not a minter';
export const ERR_MIF_ZERO_AMOUNT: string = 'MIF: amount must be > 0';
export const ERR_MIF_NOT_OWNER: string = 'MIF: caller is not the owner';
export const ERR_MIF_ZERO_ADDR: string = 'MIF: zero address';
export const ERR_MIF_NOT_A_MINTER: string = 'MIF: address is not a minter';
export const ERR_MIF_NOT_BURNER: string = 'MIF: caller is not authorized burner';
export const ERR_MIF_NOT_A_BURNER: string = 'MIF: address is not a burner';

// ---------------------------------------------------------------------------
// FREN Token Errors
// ---------------------------------------------------------------------------

export const ERR_FREN_NOT_OWNER: string = 'FREN: caller is not the owner';
export const ERR_FREN_EXCEEDS_MAX: string = 'FREN: would exceed max supply';
export const ERR_FREN_ZERO_AMOUNT: string = 'FREN: amount must be > 0';
export const ERR_FREN_INSUFFICIENT: string = 'FREN: insufficient FREN balance';
export const ERR_FREN_ZERO_SFREN: string = 'FREN: stake amount too small';
export const ERR_FREN_SFREN_INSUFFICIENT: string = 'FREN: insufficient sFREN balance';
export const ERR_FREN_NO_STAKERS: string = 'FREN: no stakers to receive rewards';
export const ERR_FREN_NOT_DISTRIBUTOR: string = 'FREN: not authorized distributor';
export const ERR_FREN_ZERO_ADDR: string = 'FREN: zero address';
export const ERR_FREN_NO_PENDING: string = 'FREN: no pending unstake';
export const ERR_FREN_TIMELOCK: string = 'FREN: unstake still in timelock';
export const ERR_FREN_PENDING_EXISTS: string = 'FREN: pending unstake already exists';

// ---------------------------------------------------------------------------
// MiFrens NFT Errors
// ---------------------------------------------------------------------------

export const ERR_NFT_MAX_SUPPLY: string = 'MIFREN: max supply reached';
export const ERR_NFT_NOT_OWNER: string = 'MIFREN: caller is not the owner';
export const ERR_NFT_NOT_EXIST: string = 'MIFREN: token does not exist';
export const ERR_NFT_LOCKED: string = 'MIFREN: token is locked';
export const ERR_NFT_NOT_LOCKED: string = 'MIFREN: token is not locked';
export const ERR_NFT_NOT_CAULDRON: string = 'MIFREN: not authorized Cauldron';
export const ERR_NFT_ZERO_ADDR: string = 'MIFREN: zero address';
export const ERR_NFT_PAYMENT_REQUIRED: string = 'MIFREN: mint payment required';
export const ERR_NFT_TRAIT_ALREADY_INSCRIBED: string = 'MIFREN: trait already inscribed';
export const ERR_NFT_INVALID_MERKLE_PROOF: string = 'MIFREN: invalid Merkle proof';
export const ERR_NFT_MERKLE_ROOT_NOT_SET: string = 'MIFREN: Merkle root not set';
export const ERR_NFT_PALETTE_ALREADY_SET: string = 'MIFREN: palette already inscribed';
export const ERR_NFT_PALETTE_EMPTY: string = 'MIFREN: palette data empty';
export const ERR_NFT_TRAIT_DATA_EMPTY: string = 'MIFREN: trait data empty';
export const ERR_NFT_TRAIT_NOT_INSCRIBED: string = 'MIFREN: trait not inscribed';
export const ERR_NFT_NOT_ART_AUTH: string = 'MIFREN: not art authority';
export const ERR_NFT_BATCH_TOO_LARGE: string = 'MIFREN: batch size exceeds limit';
export const ERR_NFT_INVALID_PROOF_LEN: string = 'MIFREN: invalid proof length';
export const ERR_NFT_INVALID_LEAF_INDEX: string = 'MIFREN: leaf index out of range';
export const ERR_NFT_PALETTE_INVALID: string = 'MIFREN: palette data invalid';
export const ERR_NFT_MINT_CAP: string = 'MIFREN: address mint cap reached';
export const ERR_NFT_INVALID_CLASS: string = 'MIFREN: class not registered or disabled';
export const ERR_NFT_INVALID_TRAIT_IDX: string = 'MIFREN: trait index out of bounds';
export const ERR_NFT_MAX_CLASSES: string = 'MIFREN: max 16 classes reached';
export const ERR_NFT_CLASS_IDX_MISMATCH: string = 'MIFREN: classIdx must equal current count';
export const ERR_NFT_INVALID_CLASS_DEF: string = 'MIFREN: invalid class definition';
export const ERR_NFT_FORGE_CALL_FAILED: string = 'MIFREN: FrenForge tokenURI call failed';
export const ERR_NFT_COMBO_TAKEN: string = 'MIFREN: trait combo already taken';
export const ERR_NFT_COMBO_EXHAUSTED: string = 'MIFREN: no unique combo found after retries';
export const ERR_NFT_NOT_AUTHORIZED: string = 'MIFREN: not authorized caller';

// ---------------------------------------------------------------------------
// Cauldron Errors
// ---------------------------------------------------------------------------

export const ERR_CAULDRON_REENTRANT: string = 'Cauldron: reentrant call';
export const ERR_CAULDRON_PAUSED: string = 'Cauldron: contract is paused';
export const ERR_CAULDRON_NOT_ADMIN: string = 'Cauldron: not admin';
export const ERR_CAULDRON_ZERO_AMOUNT: string = 'Cauldron: amount must be > 0';
export const ERR_CAULDRON_NOT_NFT_OWNER: string = 'Cauldron: caller does not own NFT';
export const ERR_CAULDRON_EXCEEDS_LTV: string = 'Cauldron: exceeds LTV limit (75%)';
export const ERR_CAULDRON_EXCEEDS_BORROW_CAP: string = 'Cauldron: exceeds global borrow cap';
export const ERR_CAULDRON_NO_DEBT: string = 'Cauldron: no debt to repay';
export const ERR_CAULDRON_INSUFFICIENT_COL: string = 'Cauldron: insufficient collateral';
export const ERR_CAULDRON_HEALTHY: string = 'Cauldron: position is healthy';
export const ERR_CAULDRON_NO_COLLATERAL: string = 'Cauldron: no collateral';
export const ERR_CAULDRON_ZERO_ADDR: string = 'Cauldron: zero address';
export const ERR_CAULDRON_NO_FEES: string = 'Cauldron: no fees to distribute';
export const ERR_CAULDRON_BTC_NOT_VERIFIED: string = 'Cauldron: BTC deposit not verified in tx outputs';
export const ERR_CAULDRON_LIQUIDATOR_NO_MIF: string = 'Cauldron: liquidator must cover debt';
export const ERR_CAULDRON_NO_BTC_PENALTIES: string = 'Cauldron: no BTC penalties to distribute';
export const ERR_CAULDRON_PENDING_ADMIN_ZERO: string = 'Cauldron: pending admin is zero';
export const ERR_CAULDRON_NOT_PENDING_ADMIN: string = 'Cauldron: caller is not pending admin';
export const ERR_CAULDRON_TOKEN_REENTRANT: string = 'CauldronToken: reentrant call';
export const ERR_CAULDRON_TOKEN_ROUTER_ZERO: string = 'CauldronToken: router is zero';
export const ERR_CAULDRON_TOKEN_WBTC_ZERO: string = 'CauldronToken: WBTC is zero';
export const ERR_CAULDRON_TOKEN_THRESHOLD_ZERO: string = 'CauldronToken: threshold is zero';
export const ERR_CAULDRON_TOKEN_ALREADY_DEAD: string = 'CauldronToken: token already dead';
export const ERR_CAULDRON_TOKEN_ZERO_NFT: string = 'CauldronToken: nftContract is zero';
export const ERR_CAULDRON_TOKEN_ZERO_FEE_RECIPIENT: string = 'CauldronToken: feeRecipient is zero';

// ---------------------------------------------------------------------------
// CauldronV2 -- Algorithmic Stablecoin Errors
// ---------------------------------------------------------------------------

export const ERR_CAULDRON_CIRCUIT_BREAKER: string = 'CauldronV2: circuit breaker active';
export const ERR_CAULDRON_TCR_COOLDOWN: string = 'CauldronV2: TCR adjustment cooldown';
export const ERR_CAULDRON_TCR_DELTA_TOO_LARGE: string = 'CauldronV2: TCR delta exceeds daily max';
export const ERR_CAULDRON_TCR_BELOW_FLOOR: string = 'CauldronV2: TCR below floor (75%)';
export const ERR_CAULDRON_TCR_ABOVE_CEILING: string = 'CauldronV2: TCR above ceiling (100%)';
export const ERR_CAULDRON_FREN_MINT_CAP: string = 'CauldronV2: daily FREN mint cap exceeded';
export const ERR_CAULDRON_INSUFFICIENT_BTC: string = 'CauldronV2: insufficient BTC sent';
export const ERR_CAULDRON_INSUFFICIENT_FREN: string = 'CauldronV2: insufficient FREN balance';
export const ERR_CAULDRON_INSUFFICIENT_MIF: string = 'CauldronV2: insufficient MIF balance';
export const ERR_CAULDRON_FREN_PRICE_ZERO: string = 'CauldronV2: FREN price is zero';
export const ERR_CAULDRON_RESERVE_DEPLETED: string = 'CauldronV2: BTC reserve depleted';

// ---------------------------------------------------------------------------
// FREN Token -- Minter Errors
// ---------------------------------------------------------------------------

export const ERR_FREN_NOT_MINTER: string = 'FREN: caller is not a minter';
export const ERR_FREN_NOT_A_MINTER: string = 'FREN: address is not a minter';

// ---------------------------------------------------------------------------
// ElderCircle Errors
// ---------------------------------------------------------------------------

export const ERR_ELDER_NOT_ADMIN: string = 'ElderCircle: caller is not admin';
export const ERR_ELDER_ALREADY_CHECKED_IN: string = 'ElderCircle: already checked in this gen';
export const ERR_ELDER_NO_REWARDS: string = 'ElderCircle: no rewards to claim';
export const ERR_ELDER_NOT_AUTHORIZED: string = 'ElderCircle: caller not authorized token';
export const ERR_ELDER_NO_WEIGHT: string = 'ElderCircle: total weight is zero';
export const ERR_ELDER_REENTRANT: string = 'ElderCircle: reentrant call';
export const ERR_ELDER_NOT_SUMMONED: string = 'ElderCircle: registry not set';
export const ERR_ELDER_ZERO_ADDR: string = 'ElderCircle: zero address';
export const ERR_ELDER_ZERO_AMOUNT: string = 'ElderCircle: amount must be > 0';
export const ERR_ELDER_NOT_DEPOSITOR: string = 'ElderCircle: caller not authorized depositor';
export const ERR_ELDER_GEN_ZERO: string = 'ElderCircle: generation is zero';

// ---------------------------------------------------------------------------
// VolumeOracle Errors
// ---------------------------------------------------------------------------

export const ERR_VOLUME_NOT_KEEPER: string = 'VolumeOracle: caller not authorized keeper';

// ---------------------------------------------------------------------------
// FrenForge Errors
// ---------------------------------------------------------------------------

export const ERR_FORGE_NOT_ADMIN: string = 'FrenForge: caller is not admin';
export const ERR_FORGE_NOT_ART_AUTH: string = 'FrenForge: not art authority';
export const ERR_FORGE_NFT_NOT_SET: string = 'FrenForge: NFT contract not set';
export const ERR_FORGE_MERKLE_ROOT_NOT_SET: string = 'FrenForge: Merkle root not set';
export const ERR_FORGE_INVALID_MERKLE_PROOF: string = 'FrenForge: invalid Merkle proof';
export const ERR_FORGE_INVALID_PROOF_LEN: string = 'FrenForge: invalid proof length';
export const ERR_FORGE_INVALID_LEAF_INDEX: string = 'FrenForge: leaf index out of range';
export const ERR_FORGE_TRAIT_ALREADY_INSCRIBED: string = 'FrenForge: trait already inscribed';
export const ERR_FORGE_TRAIT_NOT_INSCRIBED: string = 'FrenForge: trait not inscribed';
export const ERR_FORGE_TRAIT_DATA_EMPTY: string = 'FrenForge: trait data empty';
export const ERR_FORGE_PALETTE_ALREADY_SET: string = 'FrenForge: palette already inscribed';
export const ERR_FORGE_PALETTE_EMPTY: string = 'FrenForge: palette data empty';
export const ERR_FORGE_PALETTE_INVALID: string = 'FrenForge: palette data invalid';
export const ERR_FORGE_PALETTE_NOT_SET: string = 'FrenForge: palette not inscribed';
export const ERR_FORGE_ZERO_ADDR: string = 'FrenForge: zero address';
export const ERR_FORGE_TOKEN_NOT_EXIST: string = 'FrenForge: token does not exist';
export const ERR_FORGE_MINT_FAILED: string = 'FrenForge: mint call failed';
export const ERR_FORGE_PAYMENT_REQUIRED: string = 'FrenForge: mint payment required';
export const ERR_FORGE_BATCH_EMPTY: string = 'FrenForge: batch data empty';
export const ERR_FORGE_OG_EMPTY: string = 'FrenForge: no token IDs provided';
export const ERR_FORGE_INVALID_PART: string = 'FrenForge: invalid SVG part index';
export const ERR_FORGE_REENTRANT: string = 'FrenForge: reentrant call';

// ---------------------------------------------------------------------------
// FrenMarket Errors
// ---------------------------------------------------------------------------

export const ERR_MARKET_NOT_ADMIN: string = 'FrenMarket: caller is not admin';
export const ERR_MARKET_ZERO_ADDR: string = 'FrenMarket: zero address';
export const ERR_MARKET_NFT_NOT_SET: string = 'FrenMarket: NFT contract not set';
export const ERR_MARKET_NOT_NFT_OWNER: string = 'FrenMarket: caller does not own token';
export const ERR_MARKET_ZERO_PRICE: string = 'FrenMarket: price must be > 0';
export const ERR_MARKET_ALREADY_LISTED: string = 'FrenMarket: token already listed';
export const ERR_MARKET_NOT_LISTED: string = 'FrenMarket: token not listed';
export const ERR_MARKET_NOT_SELLER: string = 'FrenMarket: caller is not the seller';
export const ERR_MARKET_PAYMENT_REQUIRED: string = 'FrenMarket: insufficient payment to seller';
export const ERR_MARKET_NFT_LOCKED: string = 'FrenMarket: token is locked in Cauldron';
export const ERR_MARKET_TRANSFER_FAILED: string = 'FrenMarket: NFT transfer failed';
export const ERR_MARKET_REENTRANT: string = 'FrenMarket: reentrant call';
export const ERR_MARKET_CANNOT_BUY_OWN: string = 'FrenMarket: cannot buy own listing';
export const ERR_MARKET_INDEX_OOB: string = 'FrenMarket: listing index out of bounds';
export const ERR_MARKET_FEE_TOO_HIGH: string = 'FrenMarket: fee exceeds 10% max';
export const ERR_MARKET_FEE_PAYMENT_REQUIRED: string = 'FrenMarket: insufficient fee payment';
export const ERR_MARKET_ALREADY_RESERVED: string = 'FrenMarket: listing already reserved';
export const ERR_MARKET_NOT_RESERVER: string = 'FrenMarket: caller is not the reserver';
export const ERR_MARKET_RESERVATION_EXPIRED: string = 'FrenMarket: reservation has expired';
export const ERR_MARKET_NO_RESERVATION: string = 'FrenMarket: no active reservation';
export const ERR_MARKET_HAS_ACTIVE_RESERVATION: string = 'FrenMarket: cannot cancel while reserved';
