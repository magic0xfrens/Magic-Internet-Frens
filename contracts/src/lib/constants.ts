import { u256 } from '@btc-vision/as-bignum/assembly';

// ---------------------------------------------------------------------------
// Precision & BPS
// ---------------------------------------------------------------------------

/** Basis points denominator: 100% = 10,000 BPS */
export const BPS_PRECISION: u256 = u256.fromU64(10_000);

/** 18-decimal precision multiplier: 10^18 */
export const PRECISION_18: u256 = u256.fromString('1000000000000000000');

/** Satoshis per BTC: 10^8 */
export const SATS_PER_BTC: u256 = u256.fromU64(100_000_000);

// ---------------------------------------------------------------------------
// Oracle
// ---------------------------------------------------------------------------

/** Maximum allowed age of a price update before it is considered stale (seconds). */
export const STALENESS_THRESHOLD: u64 = 3600; // 1 hour

/** OPNet ~10min blocks: blocks per hour */
export const BLOCKS_PER_HOUR: u64 = 6;

/** Staleness threshold in blocks (replaces 3600s / ~1 hour) */
export const STALENESS_BLOCKS: u64 = 6;

/** Maximum oracle price deviation per update: 10% = 1000 BPS */
export const ORACLE_MAX_DEVIATION_BPS: u256 = u256.fromU64(1_000);

// ---------------------------------------------------------------------------
// Staking
// ---------------------------------------------------------------------------

/** 24-hour timelock for unstaking (in seconds) */
export const UNSTAKE_TIMELOCK: u64 = 86400; // 24 hours

/** 24-hour timelock for unstaking in blocks (~144 blocks at 10min/block) */
export const UNSTAKE_TIMELOCK_BLOCKS: u64 = 144;

// ---------------------------------------------------------------------------
// Lending -- Cauldron Parameters
// ---------------------------------------------------------------------------

/** LTV: 75% => 7500 BPS. Max debt/collateral value before borrow is denied. */
export const LTV_BPS: u256 = u256.fromU64(7_500);

/** Liquidation threshold: 80% => 8000 BPS. Positions above this are liquidatable. */
export const LIQUIDATION_BPS: u256 = u256.fromU64(8_000);

/** Liquidation penalty: 5% => 500 BPS. Deducted from collateral on liquidation. */
export const LIQUIDATION_PENALTY_BPS: u256 = u256.fromU64(500);

/** Borrow opening fee: 0.5% => 50 BPS. Charged on every new borrow. */
export const BORROW_FEE_BPS: u256 = u256.fromU64(50);

// ---------------------------------------------------------------------------
// NFT
// ---------------------------------------------------------------------------

/** Maximum MiFrens NFT supply - 777 Magic Internet Wizard Frens */
export const MAX_NFT_SUPPLY: u256 = u256.fromU64(777);

/** Maximum mints per address (soft cap — sybil-resistant UX, not security) */
export const MAX_MINTS_PER_ADDRESS: u256 = u256.fromU64(7);

/** Treasury reserve: pre-assigned at deployment (no payment, no enumeration) */
export const TREASURY_RESERVE: u64 = 77;

// ---------------------------------------------------------------------------
// Scattered Reserve Token IDs — 77 hand-picked memorable numbers in 1-777.
// Public mints skip these IDs; only the deployer can claim them via reserveBatch().
// Sorted ascending for binary search in _isReservedId().
//
// Distribution (~10% per 100-ID band):
//   1-100: 13 | 101-200: 9 | 201-300: 8 | 301-400: 9
//   401-500: 10 | 501-600: 10 | 601-700: 9 | 701-777: 9
// ---------------------------------------------------------------------------
// @ts-ignore: decorator
@inline
export const RESERVED_IDS: StaticArray<u16> = [
    //  1 - 100  (13 IDs: Fibonacci, lucky numbers, doubles)
    7, 11, 13, 21, 33, 42, 55, 69, 77, 88, 89, 99, 100,
    // 101 - 200  (9 IDs)
    111, 123, 133, 144, 155, 166, 177, 188, 200,
    // 201 - 300  (8 IDs)
    211, 222, 233, 250, 266, 277, 288, 300,
    // 301 - 400  (9 IDs)
    311, 321, 333, 343, 350, 369, 377, 388, 400,
    // 401 - 500  (10 IDs)
    404, 411, 420, 432, 444, 456, 466, 477, 488, 500,
    // 501 - 600  (10 IDs)
    505, 511, 525, 533, 543, 555, 567, 577, 588, 600,
    // 601 - 700  (9 IDs)
    610, 622, 633, 644, 655, 666, 677, 688, 700,
    // 701 - 777  (9 IDs)
    711, 722, 733, 744, 750, 755, 760, 770, 777,
];

/** Maximum number of character classes the registry supports */
export const MAX_NFT_CLASSES: u64 = 16;

/** Total unique inscribable leaves: 89 trait layers + 55 color batches (35×5 + 20×4 colors) */
export const TOTAL_TRAIT_LAYERS: u64 = 144;

/** Merkle tree depth for 144 leaves (next pow2 = 256, log2(256) = 8) */
export const MERKLE_TREE_DEPTH: u32 = 8;

/** Max colors per inscription batch (some batches use 4 for the last 20) */
export const COLORS_PER_BATCH: u32 = 5;

/** Bytes per u256 storage slot */
export const BYTES_PER_SLOT: u32 = 32;

// ---------------------------------------------------------------------------
// Cauldron - Eternal Creature Protocol
// ---------------------------------------------------------------------------

/** Cauldron death threshold: 0.01 BTC in 24h (creature's life force) */
export const CAULDRON_DEATH_THRESHOLD_SATS: u256 = u256.fromU64(1_000_000);

/** Initial Cauldron liquidity: 777 tokens (summoning power) */
export const CAULDRON_INITIAL_TOKENS: u256 = u256.fromString('777000000000000000000');

/** Initial Cauldron liquidity: 1 BTC */
export const CAULDRON_INITIAL_BTC_SATS: u256 = u256.fromU64(100_000_000);

/** Cauldron tax rate for non-spell-casters: 3% = 300 BPS */
export const CAULDRON_TAX_RATE_BPS: u256 = u256.fromU64(300);

// ---------------------------------------------------------------------------
// FREN Token
// ---------------------------------------------------------------------------

/** Maximum FREN supply: 1 billion with 18 decimals = 1e27 */
export const MAX_FREN_SUPPLY: u256 = u256.fromString('1000000000000000000000000000');

// ---------------------------------------------------------------------------
// Interest Rate Model
// ---------------------------------------------------------------------------

/** Seconds in a year (365.25 days) for interest calculations. */
export const SECONDS_PER_YEAR: u256 = u256.fromU64(31_557_600);

/** Base rate at 0% utilization: 1% APR = 100 BPS */
export const BASE_RATE: u256 = u256.fromU64(100);

/** Rate at kink utilization: 5% APR = 500 BPS */
export const KINK_RATE: u256 = u256.fromU64(500);

/** Utilization kink point: 80% = 8000 BPS */
export const KINK_UTILIZATION: u256 = u256.fromU64(8_000);

/** Maximum rate at 100% utilization: 50% APR = 5000 BPS */
export const MAX_RATE: u256 = u256.fromU64(5_000);

// ---------------------------------------------------------------------------
// NFT Class Weights (cumulative BPS out of 10,000)
// Proportional to unique trait combinations (body × face × item):
//   Wizard 480 (44%) → King 240 (22%) → Knight 192 (17.5%)
//   → Gnome 72 (6.6%) → Elf 48 (4.4%) → Apprentice 36 (3.3%) → Peasant 24 (2.2%)
// ---------------------------------------------------------------------------

/** Wizard: 0-4399 = 44% (8 bodies × 12 faces × 5 items = 480 combos) */
export const CLASS_WEIGHT_WIZARD: u64 = 4_400;

/** King: 4400-6599 = 22% (5 bodies × 12 faces × 4 items = 240 combos) */
export const CLASS_WEIGHT_KING: u64 = 6_600;

/** Knight: 6600-8349 = 17.5% (4 bodies × 12 faces × 4 items = 192 combos) */
export const CLASS_WEIGHT_KNIGHT: u64 = 8_350;

/** Apprentice: 8350-8679 = 3.3% (3 bodies × 12 faces × 1 item = 36 combos) */
export const CLASS_WEIGHT_APPRENTICE: u64 = 8_680;

/** Peasant: 8680-8899 = 2.2% (2 bodies × 12 faces × 3 items × 3 headgear = 216 combos) */
export const CLASS_WEIGHT_PEASANT: u64 = 8_900;

/** Gnome: 8900-9559 = 6.6% (2 bodies × 12 faces × 3 items = 72 combos) */
export const CLASS_WEIGHT_GNOME: u64 = 9_560;

// Elf: 9560-9999 = 4.4% (4 bodies × 12 faces × 1 item = 48 combos)

// ---------------------------------------------------------------------------
// Treasury Reserve Traits — 77 entries × 4 bytes: [classIdx, bodyIdx, faceIdx, itemIdx]
//
// Distribution:
//   65 Gnome(5)   — for airdrop to previous gnome holder project
//   12 Wizard(0)  — Manifestor robe (body=6) + Manifestor staff (item=4), all 12 faces
//
// Gnome: class=5, bodies 0-1, faces 0-11, items 0-2 (72 max unique combos)
// Wizard Manifest: class=0, body=6, faces 0-11, item=4
// ---------------------------------------------------------------------------
// @ts-ignore: decorator
@inline
export const RESERVE_TRAITS: StaticArray<u8> = [
    // --- Gnome body=0, face 0-11, item=0 (12 tokens) ---
    5, 0, 0, 0,   // token 1
    5, 0, 1, 0,   // token 2
    5, 0, 2, 0,   // token 3
    5, 0, 3, 0,   // token 4
    5, 0, 4, 0,   // token 5
    5, 0, 5, 0,   // token 6
    5, 0, 6, 0,   // token 7
    5, 0, 7, 0,   // token 8
    5, 0, 8, 0,   // token 9
    5, 0, 9, 0,   // token 10
    5, 0, 10, 0,  // token 11
    5, 0, 11, 0,  // token 12
    // --- Gnome body=0, face 0-11, item=1 (12 tokens) ---
    5, 0, 0, 1,   // token 13
    5, 0, 1, 1,   // token 14
    5, 0, 2, 1,   // token 15
    5, 0, 3, 1,   // token 16
    5, 0, 4, 1,   // token 17
    5, 0, 5, 1,   // token 18
    5, 0, 6, 1,   // token 19
    5, 0, 7, 1,   // token 20
    5, 0, 8, 1,   // token 21
    5, 0, 9, 1,   // token 22
    5, 0, 10, 1,  // token 23
    5, 0, 11, 1,  // token 24
    // --- Gnome body=0, face 0-11, item=2 (12 tokens) ---
    5, 0, 0, 2,   // token 25
    5, 0, 1, 2,   // token 26
    5, 0, 2, 2,   // token 27
    5, 0, 3, 2,   // token 28
    5, 0, 4, 2,   // token 29
    5, 0, 5, 2,   // token 30
    5, 0, 6, 2,   // token 31
    5, 0, 7, 2,   // token 32
    5, 0, 8, 2,   // token 33
    5, 0, 9, 2,   // token 34
    5, 0, 10, 2,  // token 35
    5, 0, 11, 2,  // token 36
    // --- Gnome body=1, face 0-11, item=0 (12 tokens) ---
    5, 1, 0, 0,   // token 37
    5, 1, 1, 0,   // token 38
    5, 1, 2, 0,   // token 39
    5, 1, 3, 0,   // token 40
    5, 1, 4, 0,   // token 41
    5, 1, 5, 0,   // token 42
    5, 1, 6, 0,   // token 43
    5, 1, 7, 0,   // token 44
    5, 1, 8, 0,   // token 45
    5, 1, 9, 0,   // token 46
    5, 1, 10, 0,  // token 47
    5, 1, 11, 0,  // token 48
    // --- Gnome body=1, face 0-11, item=1 (12 tokens) ---
    5, 1, 0, 1,   // token 49
    5, 1, 1, 1,   // token 50
    5, 1, 2, 1,   // token 51
    5, 1, 3, 1,   // token 52
    5, 1, 4, 1,   // token 53
    5, 1, 5, 1,   // token 54
    5, 1, 6, 1,   // token 55
    5, 1, 7, 1,   // token 56
    5, 1, 8, 1,   // token 57
    5, 1, 9, 1,   // token 58
    5, 1, 10, 1,  // token 59
    5, 1, 11, 1,  // token 60
    // --- Gnome body=1, face 0-4, item=2 (5 tokens to reach 65) ---
    5, 1, 0, 2,   // token 61
    5, 1, 1, 2,   // token 62
    5, 1, 2, 2,   // token 63
    5, 1, 3, 2,   // token 64
    5, 1, 4, 2,   // token 65
    // --- Wizard Manifest: body=6 (Manifest robe), item=4 (Manifest staff), all 12 faces ---
    0, 6, 0, 4,   // token 66
    0, 6, 1, 4,   // token 67
    0, 6, 2, 4,   // token 68
    0, 6, 3, 4,   // token 69
    0, 6, 4, 4,   // token 70
    0, 6, 5, 4,   // token 71
    0, 6, 6, 4,   // token 72
    0, 6, 7, 4,   // token 73
    0, 6, 8, 4,   // token 74
    0, 6, 9, 4,   // token 75
    0, 6, 10, 4,  // token 76
    0, 6, 11, 4,  // token 77
];

// ---------------------------------------------------------------------------
// Reentrancy Guard Values
// ---------------------------------------------------------------------------

export const REENTRANCY_UNLOCKED: u256 = u256.One;
export const REENTRANCY_LOCKED: u256 = u256.fromU64(2);

/** Reservation window: 6 blocks (~1 hour on Bitcoin) */
export const RESERVATION_BLOCKS: u64 = 6;

// ---------------------------------------------------------------------------
// Algorithmic Stablecoin -- TCR / ECR Parameters
// ---------------------------------------------------------------------------

/** Initial Target Collateral Ratio: 85% = 8500 BPS */
export const INITIAL_TCR_BPS: u256 = u256.fromU64(8_500);

/** TCR floor: 75% = 7500 BPS */
export const TCR_FLOOR_BPS: u256 = u256.fromU64(7_500);

/** TCR ceiling: 100% = 10000 BPS */
export const TCR_CEILING_BPS: u256 = u256.fromU64(10_000);

/** Maximum TCR adjustment per day: 0.5% = 50 BPS */
export const TCR_DAILY_MAX_DELTA_BPS: u256 = u256.fromU64(50);

/** Seconds in one day (for TCR rate-limiting) */
export const SECONDS_PER_DAY: u64 = 86_400;

/** Blocks per day (~144 blocks at 10min/block) */
export const BLOCKS_PER_DAY: u64 = 144;

/** Blocks per year (~52,560 blocks) for interest calculations */
export const BLOCKS_PER_YEAR: u256 = u256.fromU64(52_560);

// ---------------------------------------------------------------------------
// Circuit Breaker
// ---------------------------------------------------------------------------

/** FREN price drop threshold: 30% = 3000 BPS */
export const CIRCUIT_BREAKER_DROP_BPS: u256 = u256.fromU64(3_000);

/** Blocks before circuit breaker auto-resumes (~24h at 10min/block) */
export const CIRCUIT_BREAKER_RESUME_BLOCKS: u256 = u256.fromU64(144);

// ---------------------------------------------------------------------------
// FREN Daily Mint Cap
// ---------------------------------------------------------------------------

/** Max FREN minted per day via redemptions: 2% of supply = 200 BPS */
export const FREN_DAILY_MINT_CAP_BPS: u256 = u256.fromU64(200);

// ---------------------------------------------------------------------------
// Mint / Redeem Fee
// ---------------------------------------------------------------------------

/** Fee on both mint and redeem: 0.3% = 30 BPS */
export const MINT_REDEEM_FEE_BPS: u256 = u256.fromU64(30);

// ---------------------------------------------------------------------------
// ElderCircle
// ---------------------------------------------------------------------------

/** Minimum consecutive-generation streak required to earn rewards */
export const MIN_ELDER_STREAK: u256 = u256.One;

// ---------------------------------------------------------------------------
// CauldronToken -- Auto-Swap
// ---------------------------------------------------------------------------

/** Default swap threshold: 0.001 tokens (18 decimals) = 1e15 */
export const DEFAULT_SWAP_THRESHOLD: u256 = u256.fromString('1000000000000000');

// ---------------------------------------------------------------------------
// Batch Limits
// ---------------------------------------------------------------------------

/** Maximum number of tokens in a single setBatchTraits call */
export const MAX_BATCH_SIZE: u64 = 50;

/** Maximum palette colors (globalIdx is u8, buffer stores idx+1, max safe value is 255) */
export const MAX_PALETTE_COLORS: u32 = 255;

// ---------------------------------------------------------------------------
// Renderer
// ---------------------------------------------------------------------------

/** Multiplier to separate chunk indices within a trait key's storage space */
export const CHUNK_KEY_MULTIPLIER: u256 = u256.fromU64(1000);

/** Canvas dimension for pixel art (120x120 — matches source SVG resolution) */
export const CANVAS_SIDE: u32 = 120;

/** Crop dimension for tokenURI PNG (64x64 native pixels, 4-bit indexed) */
export const CROP_SIDE: u32 = 64;

/**
 * Per-class crop offsets (x, y) into the 120x120 canvas.
 * Determines the top-left corner of the 64x64 crop window.
 * [Wizard, King, Knight, Apprentice, Peasant, Gnome, Elf]
 */
// @ts-ignore: decorator
@lazy export const CROP_OFFSETS: StaticArray<u8> = [
    // classIdx 0: Wizard
    28, 28,
    // classIdx 1: King
    28, 28,
    // classIdx 2: Knight
    28, 28,
    // classIdx 3: Apprentice
    28, 28,
    // classIdx 4: Peasant
    28, 28,
    // classIdx 5: Gnome
    28, 28,
    // classIdx 6: Elf
    28, 28,
];
