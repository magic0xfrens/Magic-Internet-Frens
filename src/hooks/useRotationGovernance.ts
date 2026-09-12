import { useState, useCallback } from "react";
import type { Address } from "viem";
import { CAULDRON_INDEXER } from "@/config/cauldron";
import { usePoll } from "@/hooks/usePoll";

/**
 * LIVE TREASURY-ROTATION PROPOSALS, from the indexer.
 *
 * The app could file a proposal and then show nothing that came of it. There
 * was no tally, no way to vote AGAINST, and no record of an executed rotation —
 * all of it emitted on chain and indexed nowhere. `TreasuryGovernor` emits
 * `Proposed`/`Voted`/`Executed`/`Cancelled`, and `RedemptionExt` emits
 * `SliceRotated`; Ponder now serves them at `/rotation/governance`.
 *
 * ── PROPOSALS ARE CONCURRENT ──────────────────────────────────────────────
 * Not one at a time. `propose` refuses only while an envelope is live or inside
 * its cooldown, because serialising the queue handed a permanent veto to
 * whoever filed junk fastest — anyone over the 5-MiFren threshold could block
 * treasury governance for the price of gas. Competing destinations resolve by
 * vote, winner-takes-all, so this is a LIST with a leader, not a singleton.
 *
 * Read from Ponder rather than the chain, like every other read in this app: a
 * per-tab RPC scan of governor logs competes with the indexer's own sync for
 * the same public nodes and earns a 429 exactly when the app is busiest.
 */

const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

export interface RotationProposal {
  id: string;
  proposer: Address;
  quote: Address;
  maxTotalBps: number;
  forVotes: bigint;
  againstVotes: bigint;
  voters: number;
  executed: boolean;
  cancelled: boolean;
  expiry: number;
  createdTs: number;
  /** Unix seconds the vote closes; null when the governor's clock is unknown. */
  endsAt: number | null;
  execUntil: number | null;
  /** True while the vote is open, false once closed, null when unknown. */
  open: boolean | null;
  /** Closed, un-executed, still inside the execution window. */
  executable: boolean;
  txHash: string;
}

export interface RotationSliceRow {
  id: string;
  generation: number;
  fromQuote: Address;
  toQuote: Address;
  amountIn: number;
  amountOut: number;
  sliceBps: number;
  ts: number;
  txHash: string;
}

export interface RotationGovernance {
  proposals: RotationProposal[];
  slices: RotationSliceRow[];
  /** The open proposal currently winning, or null when tied/none/behind. */
  leader: string | null;
  loading: boolean;
  /** True when the indexer could not be reached — so the UI can say "unknown"
   *  rather than render an empty list as "no proposals". */
  failed: boolean;
}

const EMPTY: RotationGovernance = {
  proposals: [], slices: [], leader: null, loading: true, failed: false,
};

export function useRotationGovernance(): RotationGovernance {
  const [state, setState] = useState<RotationGovernance>(EMPTY);

  const load = useCallback(async () => {
    if (!INDEXER) { setState((s) => ({ ...s, loading: false, failed: true })); return; }
    try {
      const r = await fetch(`${INDEXER}/rotation/governance`);
      if (!r.ok) throw new Error(String(r.status));
      const j = await r.json();
      setState({
        proposals: (j.proposals ?? []).map((p: Record<string, unknown>) => ({
          ...p,
          forVotes: BigInt((p.forVotes as string) ?? "0"),
          againstVotes: BigInt((p.againstVotes as string) ?? "0"),
        })) as RotationProposal[],
        slices: (j.slices ?? []) as RotationSliceRow[],
        leader: j.leader ?? null,
        loading: false,
        failed: false,
      });
    } catch {
      //  AN EMPTY LIST AND A FAILED FETCH ARE DIFFERENT ANSWERS.
      //  Reporting the failure as "no proposals" is the silent-substitution
      //  shape this codebase keeps finding: nothing errors, and the screen
      //  states something untrue. Keep the last good data and flag the failure.
      setState((s) => ({ ...s, loading: false, failed: true }));
    }
  }, []);

  //  Votes land within a voting period that can be minutes on a testnet, so a
  //  30s poll would show a stale tally for most of the window.
  usePoll(load, 10_000);

  return state;
}
