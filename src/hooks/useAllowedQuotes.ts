import { useCallback, useEffect, useState } from "react";
import { usePublicClient } from "wagmi";
import type { Address } from "viem";
import { CAULDRON } from "@/config/cauldron";
import { KNOWN_QUOTES, NATIVE_QUOTE, type QuoteAsset } from "@/config/quotes";
import { usePoll } from "@/hooks/usePoll";

const ALLOWED_QUOTE_ABI = [{
  type: "function",
  name: "allowedQuote",
  stateMutability: "view",
  inputs: [{ type: "address" }],
  outputs: [{ type: "bool" }],
}] as const;

/**
 * The quote assets a proposal may name, filtered through the registry's
 * treasury-curated allowlist.
 *
 * The CHAIN decides what is selectable; {KNOWN_QUOTES} only supplies the label.
 * Offering something the registry has not approved would let a proposer submit a
 * transaction that reverts with QuoteNotAllowed at the very end of a long form —
 * so the list is filtered before it is ever shown.
 *
 * Native ETH is always included without a lookup: it is allowed at construction
 * and the registry refuses to remove it, so a brew can always launch against it
 * even if this read fails entirely.
 */
export function useAllowedQuotes(): { quotes: QuoteAsset[]; loading: boolean } {
  const pc = usePublicClient({ chainId: CAULDRON.chainId });
  const [quotes, setQuotes] = useState<QuoteAsset[]>([KNOWN_QUOTES[0]]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    if (!pc) return;
    try {
      const checks = await Promise.all(
        KNOWN_QUOTES.map(async (q) => {
          // ETH needs no lookup — it cannot be disallowed.
          if (q.address === NATIVE_QUOTE) return true;
          try {
            return (await pc.readContract({
              address: CAULDRON.registry,
              abi: ALLOWED_QUOTE_ABI,
              functionName: "allowedQuote",
              args: [q.address as Address],
            })) as boolean;
          } catch {
            // A registry that predates the allowlist has no such function.
            // Treat that as "not offered" rather than failing the whole list.
            return false;
          }
        }),
      );
      setQuotes(KNOWN_QUOTES.filter((_, i) => checks[i]));
    } catch {
      // Keep whatever we had; ETH is always in the initial state.
    } finally {
      setLoading(false);
    }
  }, [pc]);

  // The allowlist changes only by a governance transaction, so this is slow on
  // purpose — it costs one read per known quote and nothing here is urgent.
  usePoll(load, 60_000);

  return { quotes, loading };
}

/** What the LIVE generation is priced in, plus whether that is a FACT yet.
 *
 *  `resolved` is load-bearing: before the registry read lands, `quote` is the
 *  native placeholder, which is indistinguishable from a generation genuinely
 *  quoted in ETH. Anything that SIGNS must gate on `resolved`, because treating
 *  an unresolved quote as native prices a 6-decimal ERC20 generation at 18. */
export interface CurrentQuote {
  /** Safe to display. Native ETH while unresolved. */
  quote: Address;
  /** True only once the registry answered FOR THIS generation. */
  resolved: boolean;
}

export function useCurrentQuote(generation: number): CurrentQuote {
  const pc = usePublicClient({ chainId: CAULDRON.chainId });
  //  KEYED BY THE GENERATION IT DESCRIBES. A bare value would survive a
  //  generation flip and describe the previous brew's quote as this one's.
  const [state, setState] = useState<{ gen: number; quote: Address | null }>({ gen: 0, quote: null });

  const load = useCallback(async () => {
    if (!pc || !generation) return;
    try {
      const q = (await pc.readContract({
        address: CAULDRON.registry,
        abi: [{
          type: "function",
          name: "generationQuote",
          stateMutability: "view",
          inputs: [{ type: "uint256" }],
          outputs: [{ type: "address" }],
        }] as const,
        functionName: "generationQuote",
        args: [BigInt(generation)],
      })) as Address;
      setState({ gen: generation, quote: q });
    } catch {
      // Older registry, or an RPC blip: a generation with no recorded quote IS
      // native ETH, so this fallback is the correct answer rather than a guess.
      setState({ gen: generation, quote: NATIVE_QUOTE });
    }
  }, [pc, generation]);

  //  ── INVALIDATE, THEN RE-READ, WHEN THE KEY CHANGES ────────────────────────
  //  `usePoll`'s effect deps are [intervalMs, enabled] ONLY, so when `enabled`
  //  is already true a change in `load` never restarts it — the hook would keep
  //  serving the previous generation's answer for a whole poll period. This
  //  effect is what ties the read to its input.
  useEffect(() => {
    setState((s) => (s.gen === generation ? s : { gen: 0, quote: null }));
    void load();
  }, [load, generation]);

  usePoll(load, 120_000, !!generation);

  const resolved = state.gen === generation && state.quote !== null;
  return { quote: resolved ? (state.quote as Address) : NATIVE_QUOTE, resolved };
}

const ERC20_DECIMALS_ABI = [{
  type: "function",
  name: "decimals",
  stateMutability: "view",
  inputs: [],
  outputs: [{ type: "uint8" }],
}] as const;

/**
 * The live quote's decimals, READ FROM THE SAME PLACE THE ADDRESS CAME FROM.
 *
 *  ── WHY THIS HOOK EXISTS ──────────────────────────────────────────────────
 *  `useCurrentQuote` reads the generation's quote ADDRESS from the registry —
 *  on-chain — while its DECIMALS used to come from the bundled manifest, with a
 *  silent 18 for anything the manifest did not list. Those two sources drift by
 *  construction: any quote governance approves after the bundle was built (and
 *  EVERY quote on a manifest with no `quoteAssets` key) lands on the guess. A
 *  6-decimal quote guessed at 18 signs a sell floor 1e12 above anything the
 *  pool can pay — every sell reverts — while the screen renders a number that
 *  looks correct, so the revert is unexplainable from the UI.
 *
 *  `null` means NOT KNOWN YET (or the read failed), and it is deliberately not
 *  a number: callers that sign must refuse rather than substitute a default.
 *  Native ETH needs no read — it is 18 by definition of the pool's ETH side.
 */
export function useQuoteDecimals(quote?: Address | null): number | null {
  const pc = usePublicClient({ chainId: CAULDRON.chainId });
  //  "" = the caller does not have a quote to read yet. NOT the same as the
  //  native zero address, which IS a quote and IS 18 — that distinction is the
  //  whole hook: seeding 18 for an address nobody has read is a guess, and a
  //  guess here signs a slippage floor 10^(18-d) wrong in whichever direction
  //  hurts (a sell reverts; a BUY floor becomes effectively zero).
  const key = quote ? quote.toLowerCase() : "";
  const [state, setState] = useState<{ key: string; dec: number | null }>({ key: "", dec: null });

  const load = useCallback(async () => {
    if (!key) return;
    if (key === NATIVE_QUOTE) { setState({ key, dec: 18 }); return; }
    if (!pc) return;
    try {
      const d = (await pc.readContract({
        address: key as Address,
        abi: ERC20_DECIMALS_ABI,
        functionName: "decimals",
      })) as number;
      //  Validated, not trusted: a token reporting something absurd must not
      //  become a `parseUnits` argument.
      const n = Number(d);
      setState({ key, dec: Number.isSafeInteger(n) && n >= 0 && n <= 36 ? n : null });
    } catch {
      //  Unknown stays unknown. Returning 18 here would reintroduce the exact
      //  guess this hook exists to remove.
      setState({ key, dec: null });
    }
  }, [pc, key]);

  //  ── THE READ IS KEYED TO THE QUOTE IT READ ────────────────────────────────
  //  `usePoll` alone is not enough: its effect deps are [intervalMs, enabled],
  //  and `enabled` was already true, so when the quote resolved from the native
  //  placeholder to a real ERC20 the poll never restarted and the hook served a
  //  stale 18 for a full 300 s on every page load. This effect invalidates on
  //  the key and re-reads; the return below refuses to answer for a key it has
  //  not actually read.
  useEffect(() => {
    setState((s) => (s.key === key ? s : { key: "", dec: null }));
    void load();
  }, [load, key]);

  //  A token's decimals are immutable, so the poll is only a repair path.
  usePoll(load, 300_000, !!key);

  return key !== "" && state.key === key ? state.dec : null;
}
