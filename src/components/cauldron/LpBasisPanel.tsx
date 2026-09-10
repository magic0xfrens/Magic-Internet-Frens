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
.tc-lpbasis__head h3 { margin: 0; font-size: 12px; letter-spacing: 0.08em; text-transform: uppercase; color: #9b93b5; }
.tc-lpbasis__basis { display: inline-flex; align-items: center; gap: 6px; font-family: "DM Mono", ui-monospace, monospace;
  font-size: 13px; color: #efe9dd; padding: 4px 10px; border-radius: 999px;
  background: rgba(213,253,81,0.08); border: 1px solid rgba(213,253,81,0.22); }
.tc-lpbasis__glyph { color: #d5fd51; }
.tc-lpbasis__blurb { margin: 8px 0 14px; font-size: 11px; line-height: 1.5; }
.tc-lpbasis__blurb strong { color: #efe9dd; font-weight: 500; }
.tc-lpbasis__skeleton, .tc-lpbasis__empty { font-size: 11px; padding: 10px 0; }
.tc-lpbasis__bar { display: flex; height: 10px; border-radius: 999px; overflow: hidden;
  background: rgba(255,255,255,0.05); margin-bottom: 12px; }
.tc-lpbasis__seg { height: 100%; transition: width 240ms ease; }
.tc-lpbasis__legend { list-style: none; margin: 0; padding: 0; display: grid; gap: 6px; }
.tc-lpbasis__row { display: grid; grid-template-columns: 10px 1fr auto auto; align-items: center; gap: 10px; font-size: 12px; }
.tc-lpbasis__dot { width: 8px; height: 8px; border-radius: 999px; }
.tc-lpbasis__sym { display: inline-flex; align-items: center; gap: 6px; color: #efe9dd; }
.tc-lpbasis__tag { font-style: normal; font-size: 9px; letter-spacing: 0.06em; text-transform: uppercase;
  color: #d5fd51; border: 1px solid rgba(213,253,81,0.3); border-radius: 999px; padding: 1px 5px; }
.tc-lpbasis__amt { font-size: 11px; text-align: right; }
.tc-lpbasis__lp { font-style: normal; font-size: 9px; letter-spacing: 0.06em; text-transform: uppercase;
  color: #22D3EE; border: 1px solid rgba(34,211,238,0.3); border-radius: 999px; padding: 1px 5px; margin-right: 6px; }
.tc-lpbasis__pct { min-width: 52px; text-align: right; color: #efe9dd; }
.tc-lpbasis__total { margin-top: 12px; padding-top: 10px; border-top: 1px solid rgba(255,255,255,0.06); font-size: 11px; text-align: right; }
.tc-lpbasis__warn { margin: 10px 0 0; font-size: 10px; line-height: 1.5; color: #f0b429; }
`;

/** A stable colour per asset, so the same quote keeps its colour across renders
 *  and between the bar and the legend. */
const SWATCH = ["#8B5CF6", "#22D3EE", "#F59E0B", "#EC4899", "#34D399", "#F87171"];
const swatchFor = (i: number) => SWATCH[i % SWATCH.length];

function pct(x: number) {
  return `${(x * 100).toFixed(x < 0.01 && x > 0 ? 2 : 1)}%`;
}

function amountLabel(h: QuoteHolding) {
  const a = h.amount;
  if (a === 0) return `0 ${h.asset.symbol}`;
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
  gen, basis, holdings, totalUsd, partial, loading,
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
        <div className="tc-lpbasis__empty tc-dim tc-mono">
          No live positions and nothing held in an allowed quote.
        </div>
      ) : (
        <>
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
                    {h.liquidity > 0n && <em className="tc-lpbasis__lp">in LP</em>}
                    {amountLabel(h)}
                  </span>
                  <span className="tc-lpbasis__pct tc-mono">
                    {h.share !== null ? pct(h.share) : <span className="tc-dim">unpriced</span>}
                  </span>
                </li>
              );
            })}
          </ul>

          {totalUsd > 0 && (
            <div className="tc-lpbasis__total tc-mono tc-dim">
              ≈ ${totalUsd.toLocaleString(undefined, { maximumFractionDigits: 0 })} priced
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
