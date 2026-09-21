import type { Address } from "viem";

export interface RotationLegLike {
  index: number;
  quote: Address;
}

export interface RotationRouteKey {
  currency0: Address;
  currency1: Address;
  fee: number;
  tickSpacing: number;
  hooks: Address;
}

/**
 * The allowance's remainder is the envelope liveness signal. The quote cannot
 * be used as a sentinel because address(0) is the native-asset destination.
 */
export function isIdleRotationAllowance(
  allowance: readonly [Address, number],
): boolean {
  return allowance[1] === 0;
}

/**
 * Build the venue key from the selected source leg, not from the generation's
 * current denomination. Missing legs and self-routes are deliberately refused.
 */
export function routeForRotationLeg(
  legs: readonly RotationLegLike[],
  fromLeg: number,
  destination: Address | null | undefined,
  nativeAddress: Address,
): RotationRouteKey | null {
  if (!destination) return null;
  const source = legs.find((leg) => leg.index === fromLeg)?.quote;
  if (!source) return null;

  const from = source.toLowerCase() as Address;
  const to = destination.toLowerCase() as Address;
  if (from === to) return null;

  const [currency0, currency1] = from < to ? [from, to] : [to, from];
  return {
    currency0,
    currency1,
    fee: 3000,
    tickSpacing: 60,
    hooks: nativeAddress,
  };
}
