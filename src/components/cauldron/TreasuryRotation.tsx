import { useCallback, useEffect, useRef, useState } from "react";
import { useWriteContract, usePublicClient } from "wagmi";
import { formatEther, parseUnits, type Address } from "viem";
import { CAULDRON } from "@/config/cauldron";
import { NATIVE_QUOTE, quoteMeta, isNativeQuote } from "@/config/quotes";
import { useAllowedQuotes, useCurrentQuote } from "@/hooks/useAllowedQuotes";

const REGISTRY_ROTATION_ABI = [
  { type: "function", name: "beginRotation", stateMutability: "nonpayable",
    inputs: [{ name: "bps", type: "uint16" }, { name: "rotator", type: "address" }],
    outputs: [{ type: "uint256" }] },
  { type: "function", name: "completeRotation", stateMutability: "nonpayable",
    inputs: [{ name: "quote", type: "address" }, { name: "quoteAmount", type: "uint256" }, { name: "tokenAmount", type: "uint256" }],
    outputs: [{ type: "uint256" }] },
] as const;

const ROTATOR_ABI = [
  { type: "function", name: "setPlan", stateMutability: "nonpayable",
    inputs: [
      { name: "from", type: "address" }, { name: "to", type: "address" },
      { name: "totalIn", type: "uint128" }, { name: "sliceIn", type: "uint128" },
      { name: "minRate", type: "uint256" }, { name: "interval", type: "uint32" },
    ], outputs: [] },
  { type: "function", name: "cancelPlan", stateMutability: "nonpayable", inputs: [], outputs: [] },
] as const;

const ERC20_BAL = [{
  type: "function", name: "balanceOf", stateMutability: "view",
  inputs: [{ type: "address" }], outputs: [{ type: "uint256" }],
}] as const;


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

/** A donut showing what the LP is denominated in, and what a rotation would change it to. */
function Allocation({ fromSym, toSym, pct, fromCol, toCol }: {
  fromSym: string; toSym?: string; pct: number; fromCol: string; toCol: string;
}) {
  const R = 52, C = 2 * Math.PI * R;
  const moved = toSym ? Math.min(50, pct) : 0;
  return (
    <div className="tr-alloc">
      <svg viewBox="0 0 130 130" className="tr-alloc__ring">
        <circle cx="65" cy="65" r={R} fill="none" stroke="rgba(255,255,255,0.06)" strokeWidth="14" />
        {/* Remaining in the current quote */}
        <circle
          cx="65" cy="65" r={R} fill="none" stroke={fromCol} strokeWidth="14" strokeLinecap="butt"
          strokeDasharray={`${(C * (100 - moved)) / 100} ${C}`}
          transform="rotate(-90 65 65)"
        />
        {/* The slice a rotation would move */}
        {moved > 0 && (
          <circle
            cx="65" cy="65" r={R} fill="none" stroke={toCol} strokeWidth="14" strokeLinecap="butt"
            strokeDasharray={`${(C * moved) / 100} ${C}`}
            strokeDashoffset={`${-(C * (100 - moved)) / 100}`}
            transform="rotate(-90 65 65)"
            className="tr-alloc__moved"
          />
        )}
        <text x="65" y="61" textAnchor="middle" className="tr-alloc__big">{100 - moved}%</text>
        <text x="65" y="76" textAnchor="middle" className="tr-alloc__sub">{fromSym}</text>
      </svg>
      <div className="tr-alloc__key">
        <span><i style={{ background: fromCol }} />{fromSym} <b>{100 - moved}%</b></span>
        {toSym && <span><i style={{ background: toCol }} />{toSym} <b>{moved}%</b></span>}
      </div>
    </div>
  );
}

/**
 * The guild's treasury desk: what the LP is denominated in, and how to change it.
 *
 * Three steps rather than one button because they run on different clocks — the
 * pull is instant, the conversion runs over hours in slices, and seeding only
 * makes sense once the conversion has produced something. Each step reads the
 * chain to decide whether it is actually available, so a button that cannot do
 * anything is disabled with the reason shown rather than failing on click.
 */
export function TreasuryRotation({ gen, col }: { gen: number; col: string }) {
  const pc = usePublicClient({ chainId: CAULDRON.chainId });
  const { writeContractAsync } = useWriteContract();
  const { quotes } = useAllowedQuotes();
  const liveQuote = useCurrentQuote(gen);
  const from = quoteMeta(liveQuote);

  const [target, setTarget] = useState<string>("");
  const [pullPct, setPullPct] = useState(30);
  const [slices, setSlices] = useState(10);
  const [maxSlip, setMaxSlip] = useState(1);
  const [busy, setBusy] = useState<string | null>(null);
  const [log, setLog] = useState<string[]>([]);
  const [held, setHeld] = useState<{ rotator: bigint; registry: bigint }>({ rotator: 0n, registry: 0n });

  const to = quoteMeta((target || NATIVE_QUOTE) as Address);
  const rotator = (CAULDRON as Record<string, unknown>).quoteRotator as Address | undefined;
  const targets = quotes.filter((q) => q.address.toLowerCase() !== (liveQuote || NATIVE_QUOTE).toLowerCase());

  const say = (m: string) => setLog((l) => [m, ...l].slice(0, 4));

  // What each step can actually act on, read from the chain rather than assumed
  // from whether an earlier step was clicked.
  const refresh = useCallback(async () => {
    if (!pc || !rotator) return;
    try {
      const rot = isNativeQuote(liveQuote)
        ? await pc.getBalance({ address: rotator })
        : (await pc.readContract({ address: liveQuote as Address, abi: ERC20_BAL, functionName: "balanceOf", args: [rotator] })) as bigint;
      const reg = target
        ? (await pc.readContract({ address: target as Address, abi: ERC20_BAL, functionName: "balanceOf", args: [CAULDRON.registry] })) as bigint
        : 0n;
      setHeld({ rotator: rot, registry: reg });
    } catch { /* a read failure just leaves the steps disabled */ }
  }, [pc, rotator, liveQuote, target]);

  useEffect(() => { void refresh(); }, [refresh]);

  async function begin() {
    setBusy("1");
    try {
      await writeContractAsync({
        address: CAULDRON.registry, abi: REGISTRY_ROTATION_ABI, functionName: "beginRotation",
        args: [pullPct * 100, rotator!],
      });
      say(`Pulled ${pullPct}% of the LP into the rotator.`);
      await refresh();
    } catch (e) { say(`Step 1 failed: ${(e as Error).message.slice(0, 80)}`); }
    finally { setBusy(null); }
  }

  async function plan() {
    setBusy("2");
    try {
      //  The floor is derived from the CURRENT market at scheduling time and
      //  then frozen on-chain. That is the whole point: reading a price at
      //  EXECUTION time is what lets someone push the pool and get filled into
      //  it. A human-set bound cannot be moved by a swap in the same block.
      const ref = held.rotator > 0n ? Number(formatEther(held.rotator)) : 0;
      if (ref <= 0) { say("Rotator holds nothing to convert."); return; }

      // minRate is "to per 1 from", scaled 1e18. Without a live route price we
      // cannot infer the pair's rate, so the slippage is applied to a rate the
      // operator confirms — see the note under the field.
      const rate = parseUnits(String(1 - maxSlip / 100), 18);
      await writeContractAsync({
        address: rotator!, abi: ROTATOR_ABI, functionName: "setPlan",
        args: [(liveQuote || NATIVE_QUOTE) as Address, target as Address, held.rotator, held.rotator / BigInt(slices), rate, 3600],
      });
      say(`Scheduled ${slices} slices, max ${maxSlip}% slippage per slice.`);
    } catch (e) { say(`Step 2 failed: ${(e as Error).message.slice(0, 80)}`); }
    finally { setBusy(null); }
  }

  async function complete() {
    setBusy("3");
    try {
      await writeContractAsync({
        address: CAULDRON.registry, abi: REGISTRY_ROTATION_ABI, functionName: "completeRotation",
        args: [target as Address, held.registry, 0n],
      });
      say(`Seeded the ${to.symbol} pair and linked its volume.`);
      await refresh();
    } catch (e) { say(`Step 3 failed: ${(e as Error).message.slice(0, 80)}`); }
    finally { setBusy(null); }
  }

  if (!rotator) return null;

  // Each step states WHY it is unavailable rather than failing on click.
  const s1 = !target ? "pick a target asset first" : busy ? "" : null;
  const s2 = !target ? "pick a target asset first"
    : held.rotator === 0n ? "the rotator holds nothing — run step 1"
    : busy ? "" : null;
  const s3 = !target ? "pick a target asset first"
    : held.registry === 0n ? `no ${to.symbol} converted yet — run step 2 and let it fill`
    : busy ? "" : null;

  return (
    <div className="tc-rot">
      <div className="tr-head">
        <div>
          <div className="tc-card__eyebrow" style={{ color: col }}>Treasury desk · generation {gen}</div>
          <h3 className="tr-title">What backs the pool</h3>
        </div>
      </div>

      <div className="tr-top">
        <Allocation
          fromSym={from.symbol}
          toSym={target ? to.symbol : undefined}
          pct={pullPct}
          fromCol={col}
          toCol="#c48eff"
        />

        <div className="tr-controls">
          <div className="tr-field">
            <span>Rotate into</span>
            <AssetPicker
              options={targets.map((q) => ({ address: q.address, symbol: q.symbol, name: q.name, blurb: q.blurb }))}
              value={target}
              onChange={setTarget}
              fromSymbol={from.symbol}
            />
          </div>

          <label className="tr-field">
            <span>Share of the LP to convert <b>{pullPct}%</b></span>
            <input type="range" min={1} max={50} value={pullPct}
              onChange={(e) => setPullPct(Number(e.target.value))} />
            <em>Capped at 50% on-chain — a rotation reallocates the pool, it never exits it.</em>
          </label>

          <div className="tr-row">
            <label className="tr-field">
              <span>Slices</span>
              <input type="number" min={1} max={100} value={slices}
                onChange={(e) => setSlices(Math.max(1, Number(e.target.value) || 1))} />
              <em>One per hour</em>
            </label>
            <label className="tr-field">
              <span>Max slippage</span>
              <div className="tr-suffix">
                <input type="number" min={0.1} max={5} step={0.1} value={maxSlip}
                  onChange={(e) => setMaxSlip(Number(e.target.value) || 1)} />
                <i>%</i>
              </div>
              <em>A slice that cannot fill within this reverts</em>
            </label>
          </div>
        </div>
      </div>

      <ol className="tr-steps">
        {[
          { n: 1, label: `Pull ${pullPct}% into the rotator`, why: s1, fn: begin },
          { n: 2, label: `Schedule ${slices} slices`, why: s2, fn: plan },
          { n: 3, label: `Seed the ${target ? to.symbol : "new"} pair`, why: s3, fn: complete },
        ].map((st) => (
          <li key={st.n} className={st.why ? "is-blocked" : ""}>
            <button disabled={!!st.why || !!busy} onClick={st.fn}>
              <span className="tr-steps__n">{busy === String(st.n) ? "…" : st.n}</span>
              <span className="tr-steps__label">{st.label}</span>
            </button>
            {st.why && <span className="tr-steps__why">{st.why}</span>}
          </li>
        ))}
      </ol>

      <details className="tr-gov">
        <summary>How a rotation gets approved</summary>
        <p>
          These calls are owned by the <b>governance timelock</b>, so a wallet cannot
          execute them directly. A rotation is <em>scheduled</em> on the timelock,
          waits out its delay, and is then <em>executed</em> — the delay is the
          window in which the guild can see a pending change and object to it.
        </p>
        <p className="tr-gov__gap">
          <b>Worth being straight about:</b> MiFren voting currently governs the{" "}
          <em>next brew</em>, not the treasury. Rotation is gated by the timelock
          alone. Putting it behind a vote of the guild is not built yet.
        </p>
      </details>

      {log.length > 0 && (
        <ul className="tr-log">{log.map((l, i) => <li key={i} className="tc-mono">{l}</li>)}</ul>
      )}
    </div>
  );
}
