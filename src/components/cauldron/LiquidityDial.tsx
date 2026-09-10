import { useCallback, useState } from "react";
import { CAULDRON_INDEXER } from "@/config/cauldron";
import { usePoll } from "@/hooks/usePoll";

const INDEXER = CAULDRON_INDEXER ? CAULDRON_INDEXER.replace(/\/$/, "") : "";

export interface LiqAsset {
  address: string;
  symbol: string;
  /** Quote-side amount, in the asset's own units. */
  amount: number;
  usd: number | null;
  share: number;
  isBasis: boolean;
}

export interface Liquidity {
  generation: number;
  /** Real depth, quote side only. */
  pool: number;
  assets: LiqAsset[];
  totalUsd: number | null;
  reserves: { hookReserve: number };
  /** Genesis redemption floor, in TOKENS per fren. The floors are not ether. */
  floorPerFren?: number;
  /** The same floor marked to spot, in the quote asset — so it can be shown in $. */
  floorEthPerFren?: number;
  floorTicker?: string;
  nextLaunch: number;
}

const EMPTY: Liquidity = {
  generation: 0, pool: 0, assets: [], totalUsd: null,
  reserves: { hookReserve: 0 }, nextLaunch: 0,
};

//  THE BASIS WEARS THE HERO ACCENT. Lime is this page's primary colour — the
//  wordmark, the price, every headline figure. Painting the basis asset violet
//  put a heavy violet ring around a lime numeral, so the one component that was
//  supposed to slot into the panel was the loudest thing on it. The asset you
//  are denominated in is lime; anything you have ROTATED INTO takes a secondary
//  hue, which is exactly the distinction the ring exists to draw.
const BASIS_HUE = "#d5fd51";
const ROTATED_HUES = ["#7c5cfc", "#3ddc84", "#f5c542", "#5cc8fc", "#ff8fa3"];
const hueFor = (a: { symbol: string; isBasis: boolean }, i: number) =>
  a.isBasis ? BASIS_HUE : ROTATED_HUES[i % ROTATED_HUES.length];

export function useLiquidity(refreshKey?: string | number): Liquidity {
  const [v, setV] = useState<Liquidity>(EMPTY);
  const load = useCallback(async () => {
    if (!INDEXER) return;
    try {
      const r = await fetch(`${INDEXER}/liquidity`, { signal: AbortSignal.timeout(10000) });
      if (!r.ok) return;
      const d = await r.json();
      if (!d || typeof d.pool !== "number") return;
      //  The genesis floor comes from /floor, which already computes it. Fetched
      //  here rather than duplicated into /liquidity so there is one definition
      //  of the floor in the system.
      let floorPerFren: number | undefined;
      let floorEth: number | undefined;
      let floorTicker: string | undefined;
      try {
        const fr = await fetch(`${INDEXER}/floor`, { signal: AbortSignal.timeout(8000) });
        if (fr.ok) {
          const fj = await fr.json();
          floorPerFren = typeof fj.floorPerFren === "number" ? fj.floorPerFren : undefined;
          floorEth = typeof fj.redeemFloorEth === "number" ? fj.redeemFloorEth : undefined;
          floorTicker = fj.ticker || undefined;
        }
      } catch { /* the ring is still correct without it */ }
      setV({ ...EMPTY, ...d, floorPerFren, floorEthPerFren: floorEth, floorTicker });
    } catch { /* keep the last good reading */ }
  }, []);
  usePoll(load, 12_000);
  return v;
}

const fmt = (n: number, d = 4) =>
  n >= 1000 ? n.toLocaleString(undefined, { maximumFractionDigits: 0 }) : n.toFixed(d);

/**
 * THE LIQUIDITY DIAL.
 *
 *  Replaces a single "available for next launch" figure, which had two problems.
 *  It understated the pool (it counted the fee reserve and the floor vault but
 *  not the LP), and a single number can say nothing about COMPOSITION — which is
 *  the whole point once the guild starts rotating its basis and the position is
 *  genuinely part ETH, part stable, part whatever it voted for.
 *
 *  ONLY THE QUOTE SIDE IS DRAWN. A pool holds two assets and one of them is the
 *  brew's own token; counting that is how a project claims a pool that is half
 *  its own paper. The ring measures what someone could actually take out.
 *
 *  Reserves sit UNDER the ring, never inside it: real value, seeds the next
 *  launch, but not depth anyone can trade against today.
 */
export default function LiquidityDial({ liq, glyph = "Ξ", ticker, ethUsd = 0 }: { liq: Liquidity; glyph?: string; ticker?: string; ethUsd?: number }) {
  const assets = liq.assets.length
    ? liq.assets
    : [{ address: "", symbol: glyph, amount: liq.pool, usd: null, share: 1, isBasis: true }];

  //  Geometry. A THIN arc over a wide inner field: the ring is an indicator, the
  //  numeral is the subject. The first cut inverted that — an 8px ring with a
  //  drop-shadow bloom read as a neon light with a number trapped inside it.
  const R = 51, C = 2 * Math.PI * R, GAP = assets.length > 1 ? 5 : 0;
  let offset = 0;

  //  Zeroes are noise. A fee reserve that has not accrued yet says nothing worth
  //  a row, and printing "0.0000 Ξ" invites the reader to wonder what broke.
  const showFee = liq.reserves.hookReserve > 0;
  const floorUnit = liq.floorTicker || ticker || "";
  //  The floor marked to spot, then to dollars. Null (not zero) when either
  //  input is missing — a floor of "$0.00" claims the reserve is worthless,
  //  which is a very different statement from "cannot price it right now".
  const floorUsd = liq.floorEthPerFren != null && ethUsd > 0
    ? liq.floorEthPerFren * ethUsd : null;

  return (
    <div className="lqd">
      <div className="lqd__ring">
        <svg viewBox="0 0 128 128" role="img" aria-label="Liquidity composition">
          <circle className="lqd__track" cx="64" cy="64" r={R} />
          {assets.map((a, i) => {
            const len = Math.max(0, a.share) * C;
            const dash = Math.max(0, len - GAP);
            const el = (
              <circle
                key={a.address || a.symbol}
                className="lqd__arc"
                cx="64" cy="64" r={R}
                stroke={hueFor(a, i)}
                strokeDasharray={`${dash} ${C - dash}`}
                strokeDashoffset={-offset}
                style={{ animationDelay: `${i * 110}ms` }}
              />
            );
            offset += len;
            return el;
          })}
          {/* Hairline that frames the numeral — the engraved bezel of an assay
              plate, which is what stops the middle reading as empty space. */}
          <circle className="lqd__bezel" cx="64" cy="64" r={R - 9} />
        </svg>
        <div className="lqd__centre">
          <span className="lqd__value">{fmt(liq.pool)}</span>
          <span className="lqd__unit">{assets.length === 1 ? assets[0].symbol : "in LP"}</span>
        </div>
      </div>

      <div className="lqd__side">
        <div className="lqd__head">
          <span className="lqd__label">Real liquidity</span>
          {liq.totalUsd != null && <span className="lqd__usd">${fmt(liq.totalUsd, 0)}</span>}
        </div>

        <ul className="lqd__legend">
          {assets.map((a, i) => (
            <li key={a.address || a.symbol}>
              <i style={{ background: hueFor(a, i) }} />
              <b>{a.symbol}</b>
              <em>{fmt(a.amount)}</em>
              <span>{Math.round(a.share * 100)}%</span>
            </li>
          ))}
        </ul>

        {(showFee || !!liq.floorPerFren) && (
          <div className="lqd__reserves">
            {showFee && (
              <span title="Swap fees held by the hook. Real ether, added to the pool at the next relaunch — but not depth anyone can trade against today.">
                <b>Fee reserve</b><em>{fmt(liq.reserves.hookReserve)} {glyph}</em>
              </span>
            )}
            {/*  The floors are TOKEN-denominated and deliberately not shown in
                 ether. The registry deploys the collection vault with
                 `hook.setVault(0)` under the comment "UNIFIED FLOOR: no ETH
                 vault", so an ether figure there is always zero — printing one
                 invited the reader to add a floor to the pool, which is the
                 wrong sum. What backs redemption is the out-of-range token
                 reserve. Label and value are one flex row so the unit can never
                 wrap onto its own line, which is how "GENESIS / FLOOR /
                 tok/fren" happened. */}
            {!!liq.floorPerFren && (
              <span title={`Genesis redemption floor: ${fmt(liq.floorPerFren, 0)}${floorUnit ? " " + floorUnit : " tokens"} per fren, claimed 1:1 by burning it. Backed in the brew's own token; the dollar figure marks that token to spot.`}>
                <b>Genesis floor</b>
                {/*  DOLLARS LEAD. "97,912 GNOME/fren" is only meaningful to
                     someone already carrying the token price in their head. The
                     token amount is what is actually owed, so it stays — as the
                     secondary reading. */}
                <em>
                  {floorUsd != null ? `$${floorUsd < 0.01 ? floorUsd.toFixed(4) : floorUsd.toFixed(2)}` : "—"}
                  <i> /fren</i>
                </em>
              </span>
            )}
          </div>
        )}
      </div>

      <style>{`
        /*  Wears the SAME shell as the panel it replaced (.tc-reserve): a faint
            lime wash under a lime hairline, so the dial reads as part of the
            page's furniture rather than a widget dropped onto it. */
        .lqd {
          width: 100%; display: flex; align-items: center; gap: 13px;
          padding: 13px; border-radius: var(--r-sm);
          background:
            radial-gradient(130% 150% at 0% 0%, rgba(213,253,81,0.06), transparent 60%),
            rgba(213,253,81,0.04);
          border: 1px solid rgba(213,253,81,0.12);
        }

        .lqd__ring { position: relative; flex: 0 0 94px; width: 94px; height: 94px; }
        .lqd__ring svg { position: relative; width: 100%; height: 100%; transform: rotate(-90deg); }

        /*  THIN. The ring is an indicator; the numeral is the subject. At 8px
            with a drop-shadow bloom this read as a neon light with a number
            trapped in the middle of it. */
        .lqd__track { fill: none; stroke: rgba(245,240,232,.055); stroke-width: 4.5; }
        .lqd__arc {
          fill: none; stroke-width: 4.5; stroke-linecap: round;
          opacity: .92;
          animation: lqd-sweep 1.1s cubic-bezier(.16,1,.3,1) both;
          transition: stroke-dasharray .8s cubic-bezier(.16,1,.3,1),
                      stroke-dashoffset .8s cubic-bezier(.16,1,.3,1);
        }
        .lqd__bezel { fill: none; stroke: rgba(213,253,81,.10); stroke-width: 1; }
        @keyframes lqd-sweep { from { stroke-dasharray: 0 999; opacity: 0; } }

        .lqd__centre {
          position: absolute; inset: 0; display: flex; flex-direction: column;
          align-items: center; justify-content: center; gap: 0; pointer-events: none;
        }
        /*  THE HERO NUMERAL, in the wordmark's own face. Every headline figure on
            this page is Cinzel Decorative 900 — the price, the brew name, and the
            "available for next launch" value this dial replaced. */
        .lqd__value {
          font-family: "Cinzel Decorative", serif; font-weight: 900;
          font-size: 18px; line-height: 1.05; color: #f5f0e8;
          letter-spacing: -.01em;
        }
        .lqd__unit {
          font: 400 7.5px/1 "DM Mono", ui-monospace, monospace; color: #8f83b8;
          text-transform: uppercase; letter-spacing: .16em; margin-top: 4px;
        }

        .lqd__side { display: flex; flex-direction: column; gap: 9px; min-width: 0; flex: 1; }
        .lqd__head { display: flex; align-items: baseline; justify-content: space-between; gap: 10px; }
        .lqd__label {
          font: 400 8.5px/1 "DM Mono", ui-monospace, monospace; color: #8f83b8;
          text-transform: uppercase; letter-spacing: .18em; white-space: nowrap;
        }
        .lqd__usd {
          font-family: "Cinzel Decorative", serif; font-weight: 900;
          font-size: 12px; color: #d5fd51; white-space: nowrap;
        }

        .lqd__legend { list-style: none; margin: 0; padding: 0; display: flex;
                       flex-direction: column; gap: 6px; }
        .lqd__legend li { display: flex; align-items: center; gap: 9px;
                          font: 400 10.5px/1 "DM Mono", ui-monospace, monospace; color: #b8adcc; }
        .lqd__legend i { width: 6px; height: 6px; border-radius: 50%; flex: 0 0 6px; }
        .lqd__legend b { color: #f5f0e8; font-weight: 500; letter-spacing: .02em; }
        .lqd__legend em { font-style: normal; margin-left: auto; color: #f5f0e8; }
        .lqd__legend span { color: #8f83b8; font-size: 10px; min-width: 34px; text-align: right; }

        .lqd__reserves { display: flex; flex-direction: column; gap: 4px;
                         padding-top: 9px; border-top: 1px solid rgba(213,253,81,.10); }
        /*  Label and value are ONE flex row with nowrap on both, so a long unit
            can never break onto its own line — which is how "GENESIS / FLOOR /
            tok/fren" ended up stacked three deep. */
        .lqd__reserves span { display: flex; align-items: baseline; justify-content: space-between;
                              gap: 10px; font: 400 9.5px/1.35 "DM Mono", ui-monospace, monospace; }
        .lqd__reserves b { font-weight: 400; color: #8f83b8; text-transform: uppercase;
                           letter-spacing: .1em; white-space: nowrap; }
        .lqd__reserves em { font-style: normal; color: #b8adcc; white-space: nowrap; }
        .lqd__reserves i { font-style: normal; color: #6f6690; }

        @media (max-width: 560px) {
          .lqd { flex-direction: column; gap: 14px; }
          .lqd__ring { align-self: center; }
          .lqd__side { width: 100%; }
        }
        @media (prefers-reduced-motion: reduce) {
          .lqd__arc { animation: none; transition: none; }
        }
      `}</style>
    </div>
  );
}
