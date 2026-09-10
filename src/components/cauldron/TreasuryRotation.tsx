import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { usePublicClient } from "wagmi";
import { parseUnits, type Address } from "viem";
import { CAULDRON } from "@/config/cauldron";
import { NATIVE_QUOTE, quoteMeta, isNativeQuote } from "@/config/quotes";
import { useAllowedQuotes, useCurrentQuote } from "@/hooks/useAllowedQuotes";
import {
  useTreasuryRotation, SLICE_BPS, ENVELOPE_BPS, SLICES_PER_ENVELOPE,
  remainingAfter, type RouteKey,
} from "@/hooks/useTreasuryRotation";

/**
 * THE TREASURY DESK — govern a rotation, then execute it.
 *
 * ── WHY THIS IS TWO SURFACES AND NOT THREE STEPS ──────────────────────────
 * The previous version drove `beginRotation` → `setPlan` → `completeRotation`
 * as a wizard. Two of those three are not callable: `beginRotation` does not
 * exist in any contract, and `completeRotation` lives in `RedemptionExt` behind
 * a registry that forwards only six selectors and has no fallback. The flow
 * could never have worked against any deployment.
 *
 * The real shape of the thing is not a wizard. `RedemptionExt.rotateSlice` does
 * remove → swap → redeploy in ONE transaction, so there is no multi-step state
 * to walk a user through. What there IS is two different jobs with two different
 * audiences:
 *
 *   GOVERN   the guild votes an envelope: a destination and a budget. Gated on
 *            holding MiFrens, runs on a 3-day clock.
 *   EXECUTE  anyone sends slices against that envelope. Permissionless by
 *            design — an owner who can refuse to execute an approved rotation
 *            holds the same veto as one who can execute an unapproved one.
 *
 * Presenting them as one wizard implied the same person does both, which is
 * exactly backwards for the permissionless half.
 */

/**
 * A themed asset picker.
 *
 * Replaces a native <select>, which paints OS chrome — a system focus ring and
 * the platform's own dropdown — straight through the app's styling. No amount of
 * CSS fixes that: the popup is drawn by the browser, not the page.
 *
 * Built as a listbox rather than a styled input so it scales past a handful of
 * assets: rows carry a symbol, a name and the reason you would pick it, and the
 * list scrolls. Keyboard support is the part a custom control usually loses, so
 * arrows/Home/End/Escape/Enter are all handled explicitly.
 */
function AssetPicker({ options, value, onChange, fromSymbol }: {
  options: { address: string; symbol: string; name: string; blurb: string }[];
  value: string;
  onChange: (a: string) => void;
  fromSymbol: string;
}) {
  const [open, setOpen] = useState(false);
  const [cursor, setCursor] = useState(0);
  const boxRef = useRef<HTMLDivElement | null>(null);
  const chosen = options.find((o) => o.address === value);

  // Close on an outside click; a popover that traps you is worse than a select.
  useEffect(() => {
    if (!open) return;
    const away = (e: MouseEvent) => {
      if (boxRef.current && !boxRef.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", away);
    return () => document.removeEventListener("mousedown", away);
  }, [open]);

  const keys = (e: React.KeyboardEvent) => {
    if (e.key === "Escape") { setOpen(false); return; }
    if (!open && (e.key === "Enter" || e.key === " " || e.key === "ArrowDown")) {
      e.preventDefault(); setOpen(true); return;
    }
    if (!open) return;
    if (e.key === "ArrowDown") { e.preventDefault(); setCursor((c) => Math.min(options.length - 1, c + 1)); }
    if (e.key === "ArrowUp") { e.preventDefault(); setCursor((c) => Math.max(0, c - 1)); }
    if (e.key === "Home") { e.preventDefault(); setCursor(0); }
    if (e.key === "End") { e.preventDefault(); setCursor(options.length - 1); }
    if (e.key === "Enter") {
      e.preventDefault();
      const o = options[cursor];
      if (o) { onChange(o.address); setOpen(false); }
    }
  };

  if (options.length === 0) {
    return <div className="tr-pick tr-pick--empty">No other quote asset is approved yet.</div>;
  }

  return (
    <div className="tr-pick" ref={boxRef}>
      <button
        type="button"
        className={`tr-pick__trigger ${open ? "is-open" : ""}`}
        onClick={() => setOpen((v) => !v)}
        onKeyDown={keys}
        aria-haspopup="listbox"
        aria-expanded={open}
      >
        {chosen ? (
          <>
            <span className="tr-pick__sigil">{chosen.symbol.slice(0, 2)}</span>
            <span className="tr-pick__pair">
              <b>{fromSymbol} → {chosen.symbol}</b>
              <i>{chosen.name}</i>
            </span>
          </>
        ) : (
          <>
            <span className="tr-pick__sigil tr-pick__sigil--none">?</span>
            <span className="tr-pick__pair"><b>Choose a destination</b><i>{options.length} approved</i></span>
          </>
        )}
        <svg className="tr-pick__chev" viewBox="0 0 16 16" width="12" height="12" aria-hidden>
          <path d="M4 6l4 4 4-4" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      {open && (
        <ul className="tr-pick__list" role="listbox" onKeyDown={keys} tabIndex={-1}>
          {options.map((o, i) => (
            <li key={o.address}>
              <button
                type="button"
                role="option"
                aria-selected={o.address === value}
                className={`tr-pick__opt ${i === cursor ? "is-cursor" : ""} ${o.address === value ? "is-sel" : ""}`}
                onMouseEnter={() => setCursor(i)}
                onClick={() => { onChange(o.address); setOpen(false); }}
              >
                <span className="tr-pick__sigil">{o.symbol.slice(0, 2)}</span>
                <span className="tr-pick__opt-body">
                  <b>{fromSymbol} → {o.symbol}</b>
                  <i>{o.blurb}</i>
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
/** Seconds → a short human string. */
function since(s: number): string {
  if (s <= 0) return "now";
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600);
  if (d > 0) return `${d}d ${h}h`;
  const m = Math.floor((s % 3600) / 60);
  return h > 0 ? `${h}h ${m}m` : `${m}m`;
}

export function TreasuryRotation({ gen, col }: { gen: number; col: string }) {
  const pc = usePublicClient({ chainId: CAULDRON.chainId });
  const { quotes } = useAllowedQuotes();
  const liveQuote = useCurrentQuote(gen);
  const from = quoteMeta(liveQuote);
  const { env, refresh, checkVenue, rotateSlice, proposeEnvelope } = useTreasuryRotation();

  const [target, setTarget] = useState<string>("");
  const [maxSlip, setMaxSlip] = useState(1);
  const [busy, setBusy] = useState<string | null>(null);
  const [log, setLog] = useState<string[]>([]);
  const [venueOk, setVenueOk] = useState<boolean | null>(null);

  const to = quoteMeta((target || NATIVE_QUOTE) as Address);
  const targets = quotes.filter(
    (q) => q.address.toLowerCase() !== (liveQuote || NATIVE_QUOTE).toLowerCase(),
  );
  const say = (m: string) => setLog((l) => [m, ...l].slice(0, 4));

  // The destination is the ENVELOPE's, once one is live: a slice cannot go
  // anywhere else, so showing a picker would imply a choice the caller does not
  // have.
  const dest = env.idle ? (target as Address) : env.quote;
  const destMeta = quoteMeta(dest || NATIVE_QUOTE);

  /** The venue `rotateSlice` will route through: the live quote against `dest`. */
  const route: RouteKey | null = useMemo(() => {
    if (!dest || dest === NATIVE_QUOTE ? !dest : false) return null;
    const a = (liveQuote || NATIVE_QUOTE).toLowerCase();
    const b = (dest || NATIVE_QUOTE).toLowerCase();
    if (a === b) return null;
    // currency0 is the lower address; v4 PoolKeys are sorted.
    const [c0, c1] = a < b ? [a, b] : [b, a];
    return {
      currency0: c0 as Address, currency1: c1 as Address,
      fee: 3000, tickSpacing: 60, hooks: NATIVE_QUOTE as Address,
    };
  }, [liveQuote, dest]);

  // A curated venue is a precondition, not a detail: the allowlist FAILS CLOSED,
  // so an unlisted pool reverts `NoRoute` however deep it is. Check before the
  // button is pressed rather than surfacing a revert.
  useEffect(() => {
    let live = true;
    if (!route) { setVenueOk(null); return; }
    void checkVenue(route).then((ok) => { if (live) setVenueOk(ok); });
    return () => { live = false; };
  }, [route, checkVenue]);

  //  HOW MUCH TO CONVERT. The contract has always taken any `maxTotalBps` up to
  //  MAX_ENVELOPE_BPS; the UI hardcoded the maximum, so every proposal was a
  //  near-total rotation and "move 30% into stables" was simply not expressible.
  //
  //  The presets are stated as CONVERSION targets, not envelope sizes, because
  //  those are different numbers and only one of them is a thing a voter wants.
  //  A slice takes its share of what REMAINS, so the position decays
  //  geometrically: an envelope of E bps at S bps a slice converts
  //  1 - (1-S)^(E/S), which is why 30000 bps of envelope converts 96.8% rather
  //  than 300%.
  const PRESETS = [
    { label: "30%", bps: 3_000 },
    { label: "50%", bps: 5_000 },
    { label: "75%", bps: 10_000 },
    { label: "Max", bps: ENVELOPE_BPS },
  ] as const;
  const [envBps, setEnvBps] = useState<number>(ENVELOPE_BPS);
  const slicesFor = (bps: number) => Math.floor(bps / SLICE_BPS);
  const conversionFor = (bps: number) => 1 - remainingAfter(slicesFor(bps));

  const conversion = conversionFor(envBps);
  const slicesDone = Math.floor(env.movedBps / SLICE_BPS);
  const convertedSoFar = 1 - remainingAfter(slicesDone);

  async function govern() {
    if (!target) { say("Pick a destination first."); return; }
    setBusy("govern");
    try {
      await proposeEnvelope(target as Address, envBps);
      say(`Proposed a rotation into ${to.symbol}. Voting runs 3 days.`);
      await refresh();
    } catch (e) { say(`Proposal failed: ${(e as Error).message.slice(0, 90)}`); }
    finally { setBusy(null); }
  }

  async function slice() {
    if (!route) { say("No route for this pair."); return; }
    setBusy("slice");
    try {
      //  minOut is the caller's ONLY protection, and it must not be read from
      //  the pool at execution time — a price read in the same transaction is a
      //  price the caller's own swap can move. Derived from the slippage the
      //  operator sets here, applied to the slice.
      //
      //  0 would execute at any price. That is never the right default on a
      //  permissionless entrypoint, so the field has no "off".
      const minOut = parseUnits(String(Math.max(0, 1 - maxSlip / 100)), destMeta.decimals);
      await rotateSlice(SLICE_BPS, minOut, route);
      say(`Moved one ${(SLICE_BPS / 100).toFixed(0)}% slice into ${destMeta.symbol}.`);
      await refresh();
    } catch (e) { say(`Slice failed: ${(e as Error).message.slice(0, 90)}`); }
    finally { setBusy(null); }
  }

  const noGovernor = !env.loading && !env.governor;

  return (
    <section className="tc-rot">
      <header className="tr-head">
        <div className="tc-card__eyebrow" style={{ color: col }}>
          TREASURY DESK · GENERATION {gen}
        </div>
        <h2 className="tr-title">What backs the pool</h2>
      </header>

      {noGovernor ? (
        <p className="tr-note tc-mono">
          No treasury governor wired on this deployment — rotation is unavailable
          until <code>setRotationWiring</code> has been called.
        </p>
      ) : env.idle ? (
        <>
          <p className="tr-note">
            The LP is denominated in <strong>{from.symbol}</strong>. A rotation is
            voted, not executed on a whim: pick a destination, and the guild has
            three days to agree.
          </p>

          <label className="tc-mono tc-dim tr-label">Rotate into</label>
          <AssetPicker
            options={targets}
            value={target}
            onChange={setTarget}
            fromSymbol={from.symbol}
          />

          <label className="tc-mono tc-dim tr-label">How much of the LP</label>
          <div className="tr-sizes">
            {PRESETS.map((pr) => (
              <button
                key={pr.bps}
                className={`tr-size ${envBps === pr.bps ? "on" : ""}`}
                onClick={() => setEnvBps(pr.bps)}
                title={`Converts ~${(conversionFor(pr.bps) * 100).toFixed(1)}% over ${slicesFor(pr.bps)} slices`}
              >
                {pr.label}
                <em>{(conversionFor(pr.bps) * 100).toFixed(0)}%</em>
              </button>
            ))}
          </div>

          <div className="tr-projection">
            <div className="tr-proj__row">
              <span className="tc-dim">One envelope converts</span>
              <b>{(conversion * 100).toFixed(1)}%</b>
            </div>
            <div className="tr-proj__row">
              <span className="tc-dim">Slices to get there</span>
              <b>{slicesFor(envBps)} × {(SLICE_BPS / 100).toFixed(0)}%</b>
            </div>
            <div className="tr-proj__row">
              <span className="tc-dim">Earliest completion</span>
              <b>~4 days</b>
            </div>
            <p className="tr-proj__note tc-dim">
              Each slice takes its share of what REMAINS, so the position decays
              geometrically and never reaches exactly zero. A second envelope,
              after the {since(Number(env.cooldownLeft) || 604800)} cooldown,
              takes it past 99%.
            </p>
          </div>

          <button
            className="tc-btn tc-btn--ritual"
            disabled={!target || !!busy}
            onClick={govern}
          >
            {busy === "govern" ? "Proposing…" : `Propose rotation into ${to.symbol}`}
          </button>
        </>
      ) : (
        <>
          <div className="tr-envelope">
            <div className="tr-env__head">
              <span className="tc-mono tc-dim">APPROVED ROTATION</span>
              <span className="tr-env__pair tc-mono">
                {from.symbol} → {destMeta.symbol}
              </span>
            </div>
            <div className="tr-env__bar">
              <div
                className="tr-env__fill"
                style={{ width: `${Math.min(100, convertedSoFar * 100)}%`, background: col }}
              />
            </div>
            <div className="tr-env__stats tc-mono">
              <span>{(convertedSoFar * 100).toFixed(1)}% converted</span>
              <span className="tc-dim">{env.slicesLeft} slices left</span>
              <span className="tc-dim">expires {since(env.expiry - Math.floor(Date.now() / 1000))}</span>
            </div>
          </div>

          <label className="tc-mono tc-dim tr-label">
            Max slippage per slice
            <input
              className="tr-slip"
              value={maxSlip}
              onChange={(e) => setMaxSlip(Number(e.target.value.replace(/[^0-9.]/g, "")) || 0)}
              inputMode="decimal"
            />
            %
          </label>

          {venueOk === false && (
            <p className="tr-warn tc-mono">
              The {from.symbol}/{destMeta.symbol} venue is not curated on the
              rotator. Slices will revert <code>NoRoute</code> until the treasury
              calls <code>setVenue</code> — the allowlist fails closed on purpose,
              so an uncurated pool cannot be used to fill at the floor price.
            </p>
          )}

          <button
            className="tc-btn tc-btn--ritual"
            disabled={!!busy || env.slicesLeft === 0 || venueOk === false}
            onClick={slice}
          >
            {busy === "slice"
              ? "Rotating…"
              : env.slicesLeft === 0
                ? "Envelope spent"
                : `Move one ${(SLICE_BPS / 100).toFixed(0)}% slice`}
          </button>
          <p className="tr-note tc-dim">
            Permissionless: the destination and the ceiling came from the vote, so
            a caller chooses only the timing — and the slippage bound above is
            what limits the cost of bad timing.
          </p>
        </>
      )}

      {log.length > 0 && (
        <ul className="tr-log tc-mono">
          {log.map((l, i) => <li key={i}>{l}</li>)}
        </ul>
      )}
    </section>
  );
}
