import { useCallback, useState } from "react";
import { usePublicClient, useWriteContract } from "wagmi";
import type { Address } from "viem";
import { CAULDRON } from "@/config/cauldron";
import { NATIVE_QUOTE } from "@/config/quotes";
import { usePoll } from "@/hooks/usePoll";

/**
 * THE TREASURY ROTATION, against the API the contracts actually expose.
 *
 * ── WHAT THIS REPLACES ────────────────────────────────────────────────────
 * The previous UI drove a three-step flow — `registry.beginRotation`, then
 * `rotator.setPlan`, then `registry.completeRotation`. Two of those three do not
 * exist as callable entrypoints:
 *
 *   • `beginRotation` is not defined in any contract in the repo.
 *   • `completeRotation` exists in `RedemptionExt` but the registry forwards
 *     only six selectors (`rotateSlice`, `setRotationWiring`, `redeemOgFren`,
 *     `buyTreasuryOgFren`, `donateToReserve`, `materializeLegacyReserve`) and
 *     has no catch-all fallback, so `registry.completeRotation(...)` reverts.
 *
 * The real entrypoint is `registry.rotateSlice(sliceBps, minOut, route)`, which
 * does the whole thing in ONE transaction: remove a slice of the live pair, swap
 * the quote side, and redeploy it into the destination pair
 * (`RedemptionExt.rotateSlice`). The treasury never holds the asset idle between
 * those steps — which is also why a balance-based view of it reads ~0.
 *
 * ── THE CAPS ──────────────────────────────────────────────────────────────
 * Three stacked constants, none of them settable — "a governor that can vote to
 * weaken its own limits does not have limits":
 *
 *   MAX_SLICE_BPS     2500  (25%)  one `rotateSlice` call
 *   MAX_ROTATION_BPS  5000  (50%)  hard floor-protection in `removePartial`
 *   MAX_ENVELOPE_BPS 30000         cumulative SLICE BUDGET per envelope
 *
 * The envelope is a SPEND COUNTER, not a position fraction: `consume(sliceBps)`
 * books the nominal slice while `removePartial` takes that share of CURRENT
 * liquidity, so the position decays geometrically and the budget needed to
 * convert most of it exceeds 100%. 30,000 buys 12 slices of 25%, which converts
 * 1 - 0.75^12 = 96.85% — a complete de-risking rotation inside ONE vote, about
 * four days end to end.
 *
 * Use {conversionFor} rather than showing `maxTotalBps` raw: "30,000" is not
 * 300% of anything, and a voter who has to do a geometric series by hand will
 * not do it.
 *
 * The per-call floor guard did NOT move. `MAX_ROTATION_BPS` still caps any one
 * call at 50% of the live position, so no single transaction can empty the pair,
 * and every slice keeps its own `minOut`. A rotation is a reallocation, not an
 * exit.
 */

const GOVERNOR_ABI = [
  { type: "function", name: "allowance", stateMutability: "view", inputs: [],
    outputs: [{ type: "address" }, { type: "uint16" }] },
  { type: "function", name: "envelope", stateMutability: "view", inputs: [],
    outputs: [
      { name: "quote", type: "address" }, { name: "maxTotalBps", type: "uint16" },
      { name: "movedBps", type: "uint16" }, { name: "expiry", type: "uint64" },
      { name: "active", type: "bool" },
    ] },
  { type: "function", name: "lastEnvelopeAt", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "MAX_ENVELOPE_BPS", stateMutability: "view", inputs: [], outputs: [{ type: "uint16" }] },
  { type: "function", name: "COOLDOWN", stateMutability: "view", inputs: [], outputs: [{ type: "uint64" }] },
  { type: "function", name: "propose", stateMutability: "nonpayable",
    inputs: [{ type: "address" }, { type: "uint16" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "vote", stateMutability: "nonpayable",
    inputs: [{ type: "uint256" }, { type: "bool" }], outputs: [] },
  { type: "function", name: "execute", stateMutability: "nonpayable",
    inputs: [{ type: "uint256" }], outputs: [] },
] as const;

/** `rotateSlice` takes the venue as a full PoolKey, so the tuple must match. */
const REGISTRY_GEN_ABI = [
  { type: "function", name: "currentGeneration", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

export const REGISTRY_ROTATE_ABI = [
  { type: "function", name: "rotateSlice", stateMutability: "nonpayable",
    inputs: [
      { name: "sliceBps", type: "uint16" },
      { name: "minOut", type: "uint256" },
      { name: "route", type: "tuple", components: [
        { name: "currency0", type: "address" }, { name: "currency1", type: "address" },
        { name: "fee", type: "uint24" }, { name: "tickSpacing", type: "int24" },
        { name: "hooks", type: "address" },
      ] },
    ],
    outputs: [{ type: "uint256" }, { type: "uint256" }] },
  //  ROTATE FROM A CHOSEN LEG. `rotateSlice` is the fromLeg=0 shorthand; the
  //  treasury used to be one-directional because that was the only entry point,
  //  so it could go ETH -> USDG but never USDG -> anything, and could not
  //  rebalance between destinations or merge a split back together.
  { type: "function", name: "rotateSliceFrom", stateMutability: "nonpayable",
    inputs: [
      { name: "fromLeg", type: "uint8" },
      { name: "sliceBps", type: "uint16" },
      { name: "minOut", type: "uint256" },
      { name: "route", type: "tuple", components: [
        { name: "currency0", type: "address" }, { name: "currency1", type: "address" },
        { name: "fee", type: "uint24" }, { name: "tickSpacing", type: "int24" },
        { name: "hooks", type: "address" },
      ] },
    ],
    outputs: [{ type: "uint256" }, { type: "uint256" }] },
  //  The legs themselves. Both live on RedemptionExt and are reached through the
  //  registry's fallback, so they are called at the REGISTRY's address.
  { type: "function", name: "legCount", stateMutability: "view",
    inputs: [{ name: "gen", type: "uint256" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "legAt", stateMutability: "view",
    inputs: [{ name: "gen", type: "uint256" }, { name: "i", type: "uint256" }],
    outputs: [
      { name: "quote", type: "address" }, { name: "positionId", type: "uint256" },
      { name: "key", type: "tuple", components: [
        { name: "currency0", type: "address" }, { name: "currency1", type: "address" },
        { name: "fee", type: "uint24" }, { name: "tickSpacing", type: "int24" },
        { name: "hooks", type: "address" },
      ] },
    ] },
] as const;

const ROTATOR_VENUE_ABI = [
  { type: "function", name: "isVenueAllowed", stateMutability: "view",
    inputs: [{ name: "route", type: "tuple", components: [
      { name: "currency0", type: "address" }, { name: "currency1", type: "address" },
      { name: "fee", type: "uint24" }, { name: "tickSpacing", type: "int24" },
      { name: "hooks", type: "address" },
    ] }],
    outputs: [{ type: "bool" }] },
] as const;

export interface RouteKey {
  currency0: Address; currency1: Address; fee: number; tickSpacing: number; hooks: Address;
}

export interface EnvelopeState {
  /** No envelope approved, or it expired / is exhausted. */
  idle: boolean;
  quote: Address;
  maxTotalBps: number;
  movedBps: number;
  /** Slices still callable under this envelope (remaining budget / SLICE_BPS). */
  slicesLeft: number;
  expiry: number;
  /** Seconds until a NEW envelope may be proposed, 0 if now. */
  cooldownLeft: number;
  governor: Address | null;
  loading: boolean;
  /**
   * Every pool this generation holds liquidity in. Index 0 is the PRIMARY
   * (the original quote); the rest are legs opened by rotation.
   *
   * The panel could not previously show this because the contract did not
   * record it — rotation opened a destination position and discarded the id.
   * Now that the legs are tracked, the UI can show the treasury as the several
   * pools it actually is, and let a rotation pick which one to draw from.
   */
  legs: TreasuryLeg[];
}

export interface TreasuryLeg {
  /** Index to pass as `fromLeg`. 0 = primary. */
  index: number;
  quote: Address;
  positionId: bigint;
  isPrimary: boolean;
}

/** MAX_SLICE_BPS in RedemptionExt. Mirrored so the UI can size a slice. */
export const SLICE_BPS = 2500;
/** MAX_ENVELOPE_BPS in TreasuryGovernor — a spend budget, not a fraction. */
export const ENVELOPE_BPS = 30_000;

/**
 * Fraction of the ORIGINAL position still in the source quote after `n` slices.
 *
 * Each slice removes `SLICE_BPS` of what REMAINS, so the series is geometric.
 * That is why no finite number of rotations reaches exactly zero, and why the
 * envelope's spend budget has to exceed 100% to convert most of a position.
 */
export function remainingAfter(slices: number): number {
  return Math.pow(1 - SLICE_BPS / 10_000, slices);
}

/** Slices affordable under a full envelope. */
export const SLICES_PER_ENVELOPE = Math.floor(ENVELOPE_BPS / SLICE_BPS);

/** Envelopes needed to get the source quote under `target` (0..1). */
export function envelopesToReach(target: number): number {
  if (target <= 0 || target >= 1) return 0;
  const slices = Math.log(target) / Math.log(1 - SLICE_BPS / 10_000);
  return Math.ceil(slices / SLICES_PER_ENVELOPE);
}

export function useTreasuryRotation() {
  const pc = usePublicClient({ chainId: CAULDRON.chainId });
  const { writeContractAsync } = useWriteContract();
  const [env, setEnv] = useState<EnvelopeState>({
    idle: true, quote: NATIVE_QUOTE, maxTotalBps: 0, movedBps: 0, slicesLeft: 0,
    expiry: 0, cooldownLeft: 0, governor: null, loading: true, legs: [],
  });

  const load = useCallback(async () => {
    if (!pc) return;
    try {
      //  FROM THE MANIFEST, not from the registry. `CauldronBase.treasuryGovernor`
      //  is `internal` (:345), and the registry sits 62 bytes under EIP-170 so it
      //  cannot afford a getter. Reading it off-chain would have reverted — this
      //  is the same handle the app uses for every other contract.
      const governor = CAULDRON.treasuryGovernor ?? null;
      if (!governor || governor === NATIVE_QUOTE) {
        setEnv((s) => ({ ...s, governor: null, loading: false }));
        return;
      }

      const [allow, envelope, lastAt, cooldown] = await Promise.all([
        pc.readContract({ address: governor, abi: GOVERNOR_ABI, functionName: "allowance" }) as Promise<readonly [Address, number]>,
        pc.readContract({ address: governor, abi: GOVERNOR_ABI, functionName: "envelope" }) as Promise<readonly [Address, number, number, bigint, boolean]>,
        pc.readContract({ address: governor, abi: GOVERNOR_ABI, functionName: "lastEnvelopeAt" }).catch(() => 0n) as Promise<bigint>,
        pc.readContract({ address: governor, abi: GOVERNOR_ABI, functionName: "COOLDOWN" }).catch(() => 0n) as Promise<bigint>,
      ]);

      //  ── READ THE LEGS ──────────────────────────────────────────────────
      //  `legCount`/`legAt` live on RedemptionExt and are reached through the
      //  registry's fallback, so they are called at the REGISTRY's address. A
      //  deployment predating leg tracking simply reverts, which is caught here
      //  and reported as "primary only" — the truth for such a deployment.
      const gen = await pc.readContract({
        address: CAULDRON.registry, abi: REGISTRY_GEN_ABI, functionName: "currentGeneration",
      }).catch(() => 0n) as bigint;

      const legs: TreasuryLeg[] = [
        { index: 0, quote: envelope[0], positionId: 0n, isPrimary: true },
      ];
      try {
        const n = await pc.readContract({
          address: CAULDRON.registry, abi: REGISTRY_ROTATE_ABI,
          functionName: "legCount", args: [gen],
        }) as bigint;
        for (let i = 0n; i < n; i++) {
          const [q, pid] = await pc.readContract({
            address: CAULDRON.registry, abi: REGISTRY_ROTATE_ABI,
            functionName: "legAt", args: [gen, i],
          }) as readonly [Address, bigint, unknown];
          legs.push({ index: Number(i) + 1, quote: q, positionId: pid, isPrimary: false });
        }
      } catch { /* pre-leg deployment: the primary is the whole treasury */ }

      const now = Math.floor(Date.now() / 1000);
      const readyAt = Number(lastAt) + Number(cooldown);
      setEnv({
        idle: allow[0] === NATIVE_QUOTE,
        quote: envelope[0],
        maxTotalBps: envelope[1],
        movedBps: envelope[2],
        // `allowance()` already accounts for expiry and exhaustion.
        slicesLeft: Math.floor(allow[1] / SLICE_BPS),
        expiry: Number(envelope[3]),
        cooldownLeft: Math.max(0, readyAt - now),
        legs,
        governor,
        loading: false,
      });
    } catch {
      setEnv((s) => ({ ...s, loading: false }));
    }
  }, [pc]);

  // Envelope state only changes on a governance action or a slice.
  usePoll(load, 30_000);

  /** Is this venue curated on the rotator? Unlisted venues revert `NoRoute`. */
  const checkVenue = useCallback(async (route: RouteKey) => {
    if (!pc || !CAULDRON.quoteRotator) return false;
    return (await pc.readContract({
      address: CAULDRON.quoteRotator, abi: ROTATOR_VENUE_ABI,
      functionName: "isVenueAllowed", args: [route],
    }).catch(() => false)) as boolean;
  }, [pc]);

  /**
   * WHAT ONE SLICE WOULD ACTUALLY RETURN — asked of the contract, not guessed.
   *
   * `rotateSliceFrom` returns `moved`, which is the destination-side OUTPUT of
   * the swap (`RedemptionExt` :398 assigns it from `IQuoteRotator.swapOnce`,
   * whose return is `out`). Simulating the real call with `minOut = 0` therefore
   * yields this slice's expected output at current state, in the destination
   * asset's own units — including the slice's size, the leg it comes from and
   * the pool's depth, none of which the UI can infer on its own.
   *
   * This is the number a slippage percentage has to be a percentage OF. The
   * panel used to sign `1 - maxSlip` DESTINATION TOKENS flat, which is not a
   * function of the slice at all: ~0.99 whether the slice was worth 0.25 ETH or
   * 25 ETH.
   *
   * Returns null when the call cannot be simulated (no envelope, uncurated
   * venue, oracle floor unmet). The caller must then refuse to sign rather than
   * substitute a floor of its own.
   */
  const quoteSlice = useCallback(
    async (sliceBps: number, route: RouteKey, fromLeg = 0, account?: Address): Promise<bigint | null> => {
      if (!pc) return null;
      try {
        const { result } = await pc.simulateContract({
          address: CAULDRON.registry, abi: REGISTRY_ROTATE_ABI, functionName: "rotateSliceFrom",
          args: [fromLeg, sliceBps, 0n, route],
          ...(account ? { account } : {}),
        });
        const out = (result as readonly [bigint, bigint])[0];
        return out > 0n ? out : null;
      } catch {
        return null;
      }
    },
    [pc],
  );

  /**
   * Move ONE slice. Permissionless within the approved envelope: the
   * destination and the ceiling come from the vote, so the caller chooses only
   * the timing, and `minOut` bounds what bad timing can cost.
   */
  const rotateSlice = useCallback(async (sliceBps: number, minOut: bigint, route: RouteKey, fromLeg = 0) => {
    //  fromLeg 0 is the primary pool and is the historical behaviour, so the
    //  default call is byte-for-byte what it always was.
    return writeContractAsync({
      address: CAULDRON.registry, abi: REGISTRY_ROTATE_ABI, functionName: "rotateSliceFrom",
      args: [fromLeg, sliceBps, minOut, route],
    });
  }, [writeContractAsync]);

  const proposeEnvelope = useCallback(async (quote: Address, maxTotalBps: number) => {
    if (!env.governor) throw new Error("no treasury governor wired");
    return writeContractAsync({
      address: env.governor, abi: GOVERNOR_ABI, functionName: "propose",
      args: [quote, maxTotalBps],
    });
  }, [writeContractAsync, env.governor]);

  const voteEnvelope = useCallback(async (id: bigint, support: boolean) => {
    if (!env.governor) throw new Error("no treasury governor wired");
    return writeContractAsync({
      address: env.governor, abi: GOVERNOR_ABI, functionName: "vote", args: [id, support],
    });
  }, [writeContractAsync, env.governor]);

  const executeEnvelope = useCallback(async (id: bigint) => {
    if (!env.governor) throw new Error("no treasury governor wired");
    return writeContractAsync({
      address: env.governor, abi: GOVERNOR_ABI, functionName: "execute", args: [id],
    });
  }, [writeContractAsync, env.governor]);

  return { env, refresh: load, checkVenue, quoteSlice, rotateSlice, proposeEnvelope, voteEnvelope, executeEnvelope };
}
