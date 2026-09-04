export type ContractInfo = {
  address: string;
  abi: unknown;
};

export type RouteParams = {
  chainId?: string;
  cauldronId?: string;
};

export interface TokenInfo {
  name: string;
  symbol: string;
  decimals: number;
  address: string;
  icon?: string;
}

export interface CauldronConfig {
  id: number;
  name: string;
  icon: string;
  chainId: number;
  collateralInfo: TokenInfo & { abi: unknown };
  mimInfo: TokenInfo & { abi: unknown };
  contract: ContractInfo & { name: string };
  liquidationFee: number;
  interest: number;
  mcr: number;
  borrowFee: number;
  version: number;
  cauldronSettings: CauldronSettings;
}

export interface CauldronSettings {
  isSwappersActive: boolean;
  isDegenBox: boolean;
  strategyLink: boolean | string;
  isDepreciated: boolean;
  acceptUseDefaultBalance: boolean;
  healthMultiplier: number;
  hasAccountBorrowLimit: boolean;
  hasWithdrawableLimit: boolean;
  localBorrowAmountLimit: boolean;
  hasCrvClaimLogic: boolean;
  isNew: boolean;
  weight: number;
}

export interface ProtocolStats {
  tcrBps: bigint;
  ecrBps: bigint;
  totalBTCReserve: bigint;
  totalMIFSupply: bigint;
  frenPrice: bigint;
  btcPrice: bigint;
  circuitBreakerActive: boolean;
  dailyFrenMinted: bigint;
  dailyFrenCap: bigint;
  mintRedeemFees: bigint;
}

export interface MintQuote {
  btcNeeded: bigint;
  frenNeeded: bigint;
  fee: bigint;
}

export interface RedeemQuote {
  btcOut: bigint;
  frenOut: bigint;
  fee: bigint;
}

/**
 * Format a bigint token amount for display.
 * Example: formatTokenAmount(1500000000000000000n, 18) => "1.5"
 */
export function formatTokenAmount(
  amount: bigint,
  decimals: number,
  displayDecimals = 4,
): string {
  const divisor = 10n ** BigInt(decimals);
  const whole = amount / divisor;
  const fractional = amount % divisor;

  if (fractional === 0n) return whole.toString();

  const fracStr = fractional.toString().padStart(decimals, "0");
  const trimmed = fracStr.slice(0, displayDecimals).replace(/0+$/, "");

  if (!trimmed) return whole.toString();
  return `${whole}.${trimmed}`;
}
