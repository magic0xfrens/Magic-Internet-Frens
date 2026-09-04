export const ZERO_VALUE: bigint = 0n;
export const ONE_ETHER: bigint = 10n ** 18n;
export const MIF_PRICE: bigint = 10n ** 18n;
export const BIPS: number = 10_000;
export const SECONDS_PER_MINUTE: number = 60;
export const SECONDS_PER_DAY: number = 86400;
export const ONE_MILLISECOND: number = 1000;

// Removed ROBINHOOD_CHAIN_ID - now using standard chain IDs (1=Ethereum, 8453=Base, 56=BNB)

export const MAX_ALLOWANCE_VALUE: bigint =
  0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffn;

// DISABLED: Domain doesn't resolve - could trigger security warnings
// export const ANALYTICS_URL: string = "https://analytics.magicinternetfrens.xyz/api";

export const APR_KEY = "magicinternetfrensCauldronsApr";
export const ETHER_DECIMALS = 18;

export const LTV_BPS = 7500; // 75%
export const LIQUIDATION_BPS = 8000; // 80%
export const LIQUIDATION_PENALTY_BPS = 500; // 5%
export const BORROW_FEE_BPS = 50; // 0.5%

// Algorithmic Stablecoin Constants
export const INITIAL_TCR_BPS = 8500; // 85%
export const TCR_FLOOR_BPS = 7500; // 75%
export const TCR_CEILING_BPS = 10000; // 100%
export const MINT_REDEEM_FEE_BPS = 30; // 0.3%
export const FREN_DAILY_MINT_CAP_BPS = 200; // 2%
export const CIRCUIT_BREAKER_RESUME_BLOCKS = 6;
export const SATS_PER_BTC = 100_000_000n;
