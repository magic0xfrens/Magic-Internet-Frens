import { useCallback, useState } from "react";
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

/** The quote the LIVE generation is priced in (`address(0)` = native ETH). */
export function useCurrentQuote(generation: number): Address {
  const pc = usePublicClient({ chainId: CAULDRON.chainId });
  const [quote, setQuote] = useState<Address>(NATIVE_QUOTE);

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
      setQuote(q);
    } catch {
      // Older registry, or an RPC blip: a generation with no recorded quote IS
      // native ETH, so this fallback is the correct answer rather than a guess.
      setQuote(NATIVE_QUOTE);
    }
  }, [pc, generation]);

  // A generation's quote is fixed at summon and never changes, so this only
  // needs to survive a generation flip.
  usePoll(load, 120_000, !!generation);

  return quote;
}
