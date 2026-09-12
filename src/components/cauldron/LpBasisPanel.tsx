import { useMemo } from "react";
import { useLpComposition, type QuoteHolding, type LpComposition } from "@/hooks/useLpComposition";
import { isNativeQuote } from "@/config/quotes";

/**
 * THE LP BASIS, and what the treasury is actually made of.
 *
 * Two facts the app never showed. What the live brew is PRICED IN — historically
 * always ETH, now a per-generation choice the guild votes on — and how the
 * treasury is spread across the assets it is allowed to hold, which is the thing
 * a rotation actually changes.
 *
 * ── ON REFUSING TO DRAW A BAR ─────────────────────────────────────────────
 * The share of each asset is a USD comparison, and USD needs a price. When an
 * asset is held but cannot be priced, this renders the AMOUNT and omits it from
 * the bar, with the omission stated. It does not fall back to comparing raw
 * balances: 10,000 USDG (6dp) against 10 ETH (18dp) would render ETH as 99.99%
 * of a treasury it is a minority of. That is precisely the bug `QuoteRotator`
 * was redesigned to avoid, and a wrong bar is more dangerous than a missing one
 * because it looks like data.
 */

/**
 * The panel carries its OWN styles.
 *
 * They started inside `TheCauldron`'s single `<style>` block, which is where the
 * rest of the page's CSS lives — and that made the panel unrenderable anywhere
 * else. The preview route mounted it and got unstyled bullet lists, which is
 * how this was noticed. Self-contained means the lab and the app show the same
 * thing, which is the entire point of having a lab.
 *
 * Palette values are inlined rather than interpolated from `TheCauldron`'s `C`
 * object, so mounting this does not drag the page's constants along with it.
 */
const CSS = `
/* .tc-mono / .tc-dim are page utilities defined in TheCauldron. Scope them to
   this panel too, so it looks the same mounted anywhere. */
.tc-lpbasis .tc-mono { font-family: "DM Mono", ui-monospace, monospace; }
.tc-lpbasis .tc-dim { color: #9b93b5; }
/* LP BASIS. What the live brew is priced in, and what the treasury is
   actually made of. The bar only ever renders PRICED assets — an unpriced
   holding is listed with its amount and named in the footnote, because a
   bar that silently drops an asset reads as data rather than as a gap. */
.tc-lpbasis { background: rgba(8,6,15,0.42); border: 1px solid rgba(255,255,255,0.06);
  border-radius: 14px; padding: 18px 20px; margin-bottom: 18px; }
.tc-lpbasis__head { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.tc-lpbasis__head h3 { margin: 0; font-size: 11px; letter-spacing: 0.13em; text-transform: uppercase; color: #7d7597; }
.tc-lpbasis__basis { display: inline-flex; align-items: center; gap: 6px; font-family: "DM Mono", ui-monospace, monospace;
  font-size: 13px; color: #efe9dd; padding: 4px 10px; border-radius: 999px;
  background: rgba(213,253,81,0.08); border: 1px solid rgba(213,253,81,0.22); }
.tc-lpbasis__glyph { color: #d5fd51; }
.tc-lpbasis__blurb { margin: 9px 0 15px; font-size: 11px; line-height: 1.55; max-width: 46ch; }
.tc-lpbasis__blurb strong { color: #efe9dd; font-weight: 500; }
.tc-lpbasis__skeleton, .tc-lpbasis__empty { font-size: 11px; padding: 10px 0; }
.tc-lpbasis__bar { display: flex; height: 10px; border-radius: 999px; overflow: hidden;
  background: rgba(255,255,255,0.05); margin-bottom: 12px; }
.tc-lpbasis__seg { height: 100%; transition: width 240ms ease; }
.tc-lpbasis__legend { list-style: none; margin: 0; padding: 0; display: grid; gap: 7px; }
.tc-lpbasis__row { display: grid; grid-template-columns: 8px 1fr auto auto; align-items: center;
  gap: 10px; font-size: 12px; padding: 1px 0; }
.tc-lpbasis__dot { width: 8px; height: 8px; border-radius: 999px; }
.tc-lpbasis__sym { display: inline-flex; align-items: center; gap: 6px; color: #efe9dd; }
.tc-lpbasis__tag { font-style: normal; font-size: 9px; letter-spacing: 0.06em; text-transform: uppercase;
  color: #d5fd51; border: 1px solid rgba(213,253,81,0.3); border-radius: 999px; padding: 1px 5px; }
.tc-lpbasis__amt { font-size: 11px; text-align: right; font-variant-numeric: tabular-nums; }
.tc-lpbasis__lp { font-style: normal; font-size: 9px; letter-spacing: 0.06em; text-transform: uppercase;
  color: #22D3EE; border: 1px solid rgba(34,211,238,0.3); border-radius: 999px; padding: 1px 5px; margin-right: 6px; }
.tc-lpbasis__pct { min-width: 52px; text-align: right; color: #efe9dd; font-variant-numeric: tabular-nums; }
.tc-lpbasis__total { margin-top: 13px; padding-top: 11px; border-top: 1px solid rgba(255,255,255,0.06);
  font-size: 11px; text-align: right; font-variant-numeric: tabular-nums; }
.tc-lpbasis__warn { margin: 10px 0 0; font-size: 10px; line-height: 1.5; color: #f0b429; }

/* ── THE COMPOSITION RING ──────────────────────────────────────────────────
   A donut reads a SPLIT better than a 10px bar does, and this panel's whole
   job is the split. The bar is kept for the priced-vs-unpriced nuance below;
   the ring is the at-a-glance figure, with the value in the hole so the two
   are never read apart. */
.tc-lpbasis__viz { display: flex; align-items: center; gap: 20px; margin: 2px 0 18px; }
/* The ring sits in a faint aura rather than on flat ground: this palette is
   candle-lit, and a hard-edged donut on a dark panel reads as a chart widget
   dropped in from another app. The glow is the same lime the basis chip uses,
   at an opacity you notice only once it is removed. */
.tc-lpbasis__ring { flex: 0 0 auto; position: relative; width: 124px; height: 124px; }
.tc-lpbasis__ring::before { content: ""; position: absolute; inset: -14px; border-radius: 50%;
  background: radial-gradient(circle at 50% 50%, rgba(213,253,81,0.07), transparent 68%);
  pointer-events: none; }
.tc-lpbasis__ring svg { transform: rotate(-90deg); display: block; }
.tc-lpbasis__ring-seg { transition: stroke-dasharray 320ms ease; }
.tc-lpbasis__hole { position: absolute; inset: 0; display: flex; flex-direction: column;
  align-items: center; justify-content: center; text-align: center; gap: 1px; }
.tc-lpbasis__hole b { font-family: "DM Mono", ui-monospace, monospace; font-size: 16px;
  color: #efe9dd; line-height: 1.05; letter-spacing: -0.015em; font-variant-numeric: tabular-nums; }
.tc-lpbasis__hole span { font-size: 8px; letter-spacing: 0.12em; text-transform: uppercase;
  color: #7d7597; margin-top: 3px; }
.tc-lpbasis__vizside { flex: 1 1 auto; min-width: 0; }
@media (max-width: 420px) {
  .tc-lpbasis__viz { flex-direction: column; align-items: stretch; gap: 12px; }
  .tc-lpbasis__ring { align-self: center; }
}
`;

/** A stable colour per asset, so the same quote keeps its colour across renders
 *  and between the bar and the legend. */
const SWATCH = ["#8B5CF6", "#22D3EE", "#F59E0B", "#EC4899", "#34D399", "#F87171"];
const swatchFor = (i: number) => SWATCH[i % SWATCH.length];

function pct(x: number) {
  return `${(x * 100).toFixed(x < 0.01 && x > 0 ? 2 : 1)}%`;
}

/**
 * USD for the ring's centre.
 *
 * `maximumFractionDigits: 0` is right for a treasury and wrong for a testnet:
 * it renders every value under fifty cents as "$0", which is what the panel was
 * doing — a live pool with real liquidity in it reported "≈ $0 priced" and read
 * as broken rather than as small. Small numbers get their significant digits.
 */
function money(n: number): string {
  if (n <= 0) return "$0";
  if (n >= 1000) return `$${(n / 1000).toLocaleString(undefined, { maximumFractionDigits: n >= 10_000 ? 0 : 1 })}k`;
  if (n >= 1) return `$${n.toLocaleString(undefined, { maximumFractionDigits: 0 })}`;
  if (n >= 0.01) return `$${n.toFixed(2)}`;
  return `<$0.01`;
}

/**
 * The composition ring.
 *
 * Draws ONLY priced assets, for the reason stated at the top of this file: a
 * ring is a proportion, a proportion needs a common unit, and comparing raw
 * balances across a 6-decimal and an 18-decimal asset produces a confident,
 * wrong picture. When nothing can be priced it draws one neutral track and says
 * so in the hole, which is a visibly different thing from a treasury that is
 * genuinely 100% one asset.
 */
function CompositionRing({ priced, totalUsd, basisSymbol, assetCount }: {
  priced: QuoteHolding[];
  totalUsd: number;
  basisSymbol: string;
  assetCount: number;
}) {
  const R = 52, SW = 13, C = 2 * Math.PI * R;
  const hasSplit = priced.length > 0 && totalUsd > 0;

  //  Segments are laid out by running offset so they abut exactly; rounding each
  //  independently would leave hairline gaps that read as missing assets.
  let offset = 0;
  const segs = priced.map((h, i) => {
    const frac = Math.max(0, Math.min(1, h.share ?? 0));
    const seg = { len: C * frac, off: C * offset, colour: swatchFor(i), h };
    offset += frac;
    return seg;
  });

  return (
    <div className="tc-lpbasis__ring">
      <svg width={124} height={124} viewBox="0 0 124 124" aria-hidden={hasSplit ? undefined : true}
           role={hasSplit ? "img" : undefined}
           aria-label={hasSplit
             ? `Treasury split: ${priced.map((h) => `${h.asset.symbol} ${pct(h.share!)}`).join(", ")}`
             : undefined}>
        <circle cx={62} cy={62} r={R} fill="none" strokeWidth={SW}
                stroke={hasSplit ? "rgba(255,255,255,0.05)" : "rgba(255,255,255,0.10)"}
                strokeDasharray={hasSplit ? undefined : "3 6"} />
        {segs.map((s) => (
          <circle
            key={s.h.asset.address}
            className="tc-lpbasis__ring-seg"
            cx={62} cy={62} r={R} fill="none"
            stroke={s.colour} strokeWidth={SW} strokeLinecap="butt"
            strokeDasharray={`${s.len} ${C - s.len}`}
            strokeDashoffset={-s.off}
          >
            <title>{`${s.h.asset.symbol} — ${pct(s.h.share!)}`}</title>
          </circle>
        ))}
      </svg>
      <div className="tc-lpbasis__hole">
        {hasSplit ? (
          <>
            <b>{money(totalUsd)}</b>
            <span>in pool</span>
          </>
        ) : (
          <>
            <b>{basisSymbol}</b>
            <span>{assetCount === 1 ? "unpriced" : `${assetCount} assets · unpriced`}</span>
          </>
        )}
      </div>
    </div>
  );
}

/**
 * The figure to put on a row: what this asset is worth to the treasury, idle
 * and deployed together.
 *
 * The row used to print the IDLE balance beside an "in LP" pill. Those are
 * different facts, and for a working treasury the idle one is dust —
 * `rotateSlice` removes, swaps and redeploys in a single transaction, so value
 * at rest is the exception. Measured on the live deployment: 321 wei idle
 * against a position worth ~0.5 ETH.
 */
function rowAmount(h: QuoteHolding) {
  return amountLabel(h, h.totalAmount);
}

function amountLabel(h: QuoteHolding, override?: number) {
  const a = override ?? h.amount;
  if (a === 0) return `0 ${h.asset.symbol}`;
  //  A FIXED 4dp CEILING RENDERS SMALL HOLDINGS AS ZERO.
  //  Testnet balances live well below 0.0001 ETH, so the panel printed "0 ETH"
  //  beside a row it had just decided was worth showing — the same "looks broken,
  //  is merely small" failure as the $0 total. Below the ceiling, fall back to
  //  significant digits so the figure is always distinguishable from nothing.
  if (a < 0.0001) return `${a.toPrecision(2)} ${h.asset.symbol}`;
  const dp = a < 1 ? 4 : a < 1000 ? 2 : 0;
  return `${a.toLocaleString(undefined, { maximumFractionDigits: dp })} ${h.asset.symbol}`;
}

export function LpBasisPanel({ gen }: { gen: number }) {
  // No allowlist read here: the indexer resolves the quote set and the basis
  // server-side, so the browser makes exactly one request for the whole panel.
  const data = useLpComposition(gen);
  return <LpBasisView gen={gen} {...data} />;
}

/**
 * The presentation half, taking the composition as props.
 *
 * Split out so the multi-asset render can be exercised without a treasury that
 * actually holds three assets — the live one holds none, and a component you
 * cannot see in its interesting state is a component you have not tested. The
 * wrapper above is the only caller in the app; {LpBasisPreview} drives this
 * same function with fixture data.
 */
export function LpBasisView({
  gen, basis, holdings, totalUsd, partial, loading, failed,
}: LpComposition & { gen: number }) {

  //  AN ASSET COUNTS IF IT IS IN THE LP **OR** HELD IDLE.
  //  Filtering on the idle balance alone would show an empty panel for a
  //  perfectly healthy treasury: `rotateSlice` removes, swaps and redeploys in
  //  one transaction, so the value lives in positions and the idle balance is
  //  ~0 by design.
  const held = useMemo(
    () => holdings
      .filter((h) => h.raw > 0n || h.liquidity > 0n)
      .sort((a, b) => (b.usd ?? 0) - (a.usd ?? 0)),
    [holdings],
  );
  const priced = held.filter((h) => h.share !== null);
  const unpriced = held.filter((h) => h.share === null);

  return (
    <section className="tc-lpbasis">
      <style>{CSS}</style>
      <header className="tc-lpbasis__head">
        <h3 className="tc-mono">LP basis</h3>
        <span className="tc-lpbasis__basis" title="The asset this iteration's token is priced in">
          <span className="tc-lpbasis__glyph">{basis.glyph || "◈"}</span>
          {basis.symbol}
        </span>
      </header>

      <p className="tc-lpbasis__blurb tc-dim">
        Generation {gen} trades against <strong>{basis.name}</strong>.{" "}
        {isNativeQuote(basis.address)
          ? "Deepest liquidity, and the only pair perps support."
          : "Perps stay ETH-only, so this generation trades spot."}
      </p>

      {loading && held.length === 0 ? (
        <div className="tc-lpbasis__skeleton tc-dim tc-mono">reading balances…</div>
      ) : held.length === 0 ? (
        //  SAY WHICH EMPTINESS THIS IS. "No live positions" is a claim about the
        //  treasury; a failed fetch is a claim about us. Rendering the second as
        //  the first told a guild holding two live positions that it held none.
        <div className="tc-lpbasis__empty tc-dim tc-mono">
          {failed
            ? "Could not reach the indexer — holdings unknown, not empty."
            : "No live positions and nothing held in an allowed quote."}
        </div>
      ) : (
        <>
          <div className="tc-lpbasis__viz">
            <CompositionRing
              priced={priced}
              totalUsd={totalUsd}
              basisSymbol={basis.symbol}
              assetCount={held.length}
            />
            <div className="tc-lpbasis__vizside">
              {priced.length > 0 && (
                <div
                  className="tc-lpbasis__bar"
                  role="img"
                  aria-label={`Treasury split: ${priced
                    .map((h) => `${h.asset.symbol} ${pct(h.share!)}`)
                    .join(", ")}`}
                >
                  {priced.map((h, i) => (
                    <div
                      key={h.asset.address}
                      className="tc-lpbasis__seg"
                      style={{ width: pct(h.share!), background: swatchFor(i) }}
                      title={`${h.asset.symbol} — ${pct(h.share!)}`}
                    />
                  ))}
                </div>
              )}

              <ul className="tc-lpbasis__legend">
                {held.map((h) => {
                  const i = priced.indexOf(h);
                  //  IDLE AMOUNT AND LP PRESENCE ARE DIFFERENT FACTS.
                  //  `amount` is the idle balance, which `rotateSlice` keeps at
                  //  ~0 by design, so pairing it with the "in LP" pill rendered
                  //  "in LP 0 ETH" for a pool holding real liquidity — the pill
                  //  saying the value is deployed and the number next to it
                  //  saying there is none. Show the idle figure only when there
                  //  is one to show.
                  const inLp = h.liquidity > 0n;
                  const shown = h.totalAmount;
                  return (
                    <li key={h.asset.address} className="tc-lpbasis__row">
                      <span
                        className="tc-lpbasis__dot"
                        style={{ background: i >= 0 ? swatchFor(i) : "transparent",
                                 border: i >= 0 ? "none" : "1px dashed currentColor" }}
                      />
                      <span className="tc-lpbasis__sym tc-mono">
                        {h.asset.symbol}
                        {h.isBasis && <em className="tc-lpbasis__tag">basis</em>}
                      </span>
                      <span className="tc-lpbasis__amt tc-mono tc-dim">
                        {inLp && <em className="tc-lpbasis__lp">in LP</em>}
                        {shown > 0 ? rowAmount(h) : `0 ${h.asset.symbol}`}
                      </span>
                      <span className="tc-lpbasis__pct tc-mono">
                        {h.share !== null ? pct(h.share) : <span className="tc-dim">unpriced</span>}
                      </span>
                    </li>
                  );
                })}
              </ul>
            </div>
          </div>

          {totalUsd > 0 && (
            <div className="tc-lpbasis__total tc-mono tc-dim">
              ≈ {money(totalUsd)} priced
            </div>
          )}

          {partial && (
            // Say what is missing rather than quietly drawing a bar that omits it.
            <p className="tc-lpbasis__warn tc-mono">
              {unpriced.map((h) => h.asset.symbol).join(", ")} held but not priceable —
              excluded from the split rather than guessed.
            </p>
          )}
        </>
      )}
    </section>
  );
}
