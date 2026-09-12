import { LpBasisView } from "@/components/cauldron/LpBasisPanel";
import type { LpComposition, QuoteHolding } from "@/hooks/useLpComposition";
import { KNOWN_QUOTES, quoteMeta, NATIVE_QUOTE } from "@/config/quotes";
import type { Address } from "viem";

/**
 * LP BASIS LAB — every state of the basis panel, side by side.
 *
 * The live treasury holds none of the allowed quotes (measured: registry,
 * rotator and hook all hold 0 USDG and 0 xNVDA), so the interesting renders —
 * a three-way split, a non-ETH basis, a held-but-unpriceable asset — cannot be
 * reached by looking at the deployment. A panel whose interesting state nobody
 * has ever seen is a panel that has not been reviewed.
 *
 * This drives {LpBasisView}, the SAME function the app renders, with fixture
 * data. It is not a copy of the component: if the real panel breaks, this
 * breaks with it.
 */

const meta = (i: number) => KNOWN_QUOTES[i] ?? quoteMeta(NATIVE_QUOTE);

/** A holding in `asset`, worth `usd`, with `amount` in the asset's own units. */
function hold(assetIdx: number, amount: number, usd: number | null, isBasis = false): QuoteHolding {
  const asset = meta(assetIdx);
  return {
    asset,
    raw: BigInt(Math.round(amount * 10 ** Math.min(asset.decimals, 9))),
    amount,
    usd,
    share: null, // recomputed below, exactly as the hook does
    // Fixtures represent a treasury whose value is deployed, which is the
    // normal state — `rotateSlice` never leaves it idle for long. So the whole
    // amount sits on the LP side and the idle balance is the dust, matching
    // what the live endpoint reports.
    liquidity: amount > 0 ? 1n : 0n,
    lpRaw: BigInt(Math.round(amount * 10 ** Math.min(asset.decimals, 9))),
    lpAmount: amount,
    totalAmount: amount,
    isBasis,
  };
}

/** Mirror the hook's own share maths so the preview cannot drift from it. */
function compose(holdings: QuoteHolding[], basisAddr: Address): LpComposition {
  const totalUsd = holdings.reduce((a, h) => a + (h.usd ?? 0), 0);
  return {
    basis: quoteMeta(basisAddr),
    holdings: holdings.map((h) => ({
      ...h,
      share: h.usd !== null && totalUsd > 0 ? h.usd / totalUsd : null,
    })),
    totalUsd,
    partial: holdings.some((h) => h.usd === null && h.raw > 0n),
    loading: false,
  };
}

const ETH = NATIVE_QUOTE;
const USDG = (KNOWN_QUOTES[1]?.address ?? NATIVE_QUOTE) as Address;
const XNVDA = (KNOWN_QUOTES[2]?.address ?? NATIVE_QUOTE) as Address;

const CASES: { title: string; note: string; data: LpComposition; gen: number }[] = [
  {
    title: "Three-way split",
    note: "The case the feature exists for: ETH, a stable and an equity, each priced, shares summing to 100%.",
    gen: 7,
    data: compose(
      [hold(0, 9, 30_000, true), hold(1, 30_000, 30_000), hold(2, 40, 30_000)],
      ETH,
    ),
  },
  {
    title: "Non-ETH basis",
    note: "The brew is priced in USDG. The basis chip and the perp caveat both follow the basis, not ETH.",
    gen: 8,
    data: compose(
      [hold(1, 48_000, 48_000, true), hold(0, 2.5, 8_300)],
      USDG,
    ),
  },
  {
    title: "Held but unpriceable",
    note: "xNVDA has no usable feed. It is listed with its amount, excluded from the bar, and named in the footnote — never folded in at a guessed rate.",
    gen: 9,
    data: compose(
      [hold(0, 6, 20_000, true), hold(1, 12_000, 12_000), hold(2, 40, null)],
      ETH,
    ),
  },
  {
    title: "Single asset",
    note: "One holding is 100% of the bar. The common case today.",
    gen: 1,
    data: compose([hold(0, 6.8882, 22_900, true)], ETH),
  },
  {
    title: "Empty treasury",
    note: "What the live deployment actually shows right now.",
    gen: 1,
    data: compose([], ETH),
  },
  {
    title: "Nothing priceable",
    note: "Assets held, no oracle wired. Amounts still render; the bar does not.",
    gen: 4,
    data: compose([hold(0, 3, null, true), hold(1, 5_000, null)], ETH),
  },
];

export default function LpBasisLab() {
  return (
    <div style={{ minHeight: "100vh", background: "#08060f", color: "#efe9dd", padding: "40px 24px" }}>
      <div style={{ maxWidth: 900, margin: "0 auto" }}>
        <h1 style={{ fontFamily: '"Cinzel", serif', fontSize: 28, margin: "0 0 6px" }}>
          LP basis lab
        </h1>
        <p style={{ fontFamily: '"DM Mono", monospace', fontSize: 12, opacity: 0.6, margin: "0 0 32px" }}>
          Every state of the basis panel, rendered through the real component.
        </p>

        {CASES.map((c) => (
          <section key={c.title} style={{ marginBottom: 34 }}>
            <h2
              style={{
                fontFamily: '"DM Mono", monospace', fontSize: 12, letterSpacing: "0.08em",
                textTransform: "uppercase", color: "#d5fd51", margin: "0 0 4px",
              }}
            >
              {c.title}
            </h2>
            <p style={{ fontFamily: '"DM Sans", sans-serif', fontSize: 12, opacity: 0.55, margin: "0 0 12px", lineHeight: 1.5 }}>
              {c.note}
            </p>
            <LpBasisView gen={c.gen} {...c.data} />
          </section>
        ))}
      </div>
    </div>
  );
}
