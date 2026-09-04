import { formatEther } from "viem";
import { useMiFrensDividend } from "@/hooks/useMiFrensDividend";

/**
 * DividendPanel — the eternal reward for holding a GENESIS MiFren. Each fren must
 * "cast the spell" to draw fees; fewer casters means the ones who did earn more.
 * Shows enchant status + claimable ETH across all your genesis frens, with
 * one-click cast-all / claim-all / withdraw.
 *
 * Accepts the shared `div` instance from the parent so the enchant count stays in
 * sync with the stat strip (calling the hook twice made two instances that drifted:
 * casting here refetched the panel but not the parent's "Enchanted" stat).
 */
export default function DividendPanel({ div }: { div: ReturnType<typeof useMiFrensDividend> }) {
  const {
    ownedGenesis, enchanted, totalPending, owed, unenchantedIds, loading, error,
    claimAll, castAll, withdrawOwed, isPending, confirming,
  } = div;

  if (!loading && ownedGenesis.length === 0) {
    return (
      <div className="dvd dvd--empty">
        <span className="dvd__label">Genesis dividend</span>
        <span className="dvd__sub">Hold a genesis MiFren (#1–1111) to earn a share of every iteration's fees.</span>
        <style>{css}</style>
      </div>
    );
  }

  const busy = isPending || confirming;
  const activeCount = enchanted.filter(Boolean).length;
  const total = ownedGenesis.length;
  const pretty = (wei: bigint) => Number(formatEther(wei)).toLocaleString(undefined, { maximumFractionDigits: 6 });
  const hasClaim = totalPending > 0n;
  const hasOwed = owed > 0n;
  const allCast = unenchantedIds.length === 0;

  const run = (fn: () => Promise<unknown>) => fn().catch(() => {});

  return (
    <div className="dvd">
      <div className="dvd__top">
        <div className="dvd__left">
          <span className="dvd__label">Genesis dividend</span>
          <span className="dvd__eth">{loading ? "…" : pretty(totalPending)} <em>ETH</em></span>
          <span className="dvd__sub">
            claimable across {total} genesis fren{total !== 1 ? "s" : ""}
            {hasOwed && ` · ${pretty(owed)} ETH settled`}
          </span>
          {error && <span className="dvd__err">{error}</span>}
        </div>
        <button className="dvd__btn" disabled={!hasClaim || busy} onClick={() => run(claimAll)}>
          {confirming ? "Claiming…" : "Claim ETH"}
        </button>
      </div>

      {/* enchant strip */}
      <div className="dvd__spell">
        <div className="dvd__spell-info">
          <span className="dvd__spell-title"><span className="dvd__rune">✦</span> Cast the Spell</span>
          <span className="dvd__spell-sub">
            {activeCount}/{total} enchanted · {allCast
              ? "all your frens are drawing fees"
              : `${unenchantedIds.length} fren${unenchantedIds.length !== 1 ? "s aren't" : " isn't"} earning yet`}
          </span>
        </div>
        <div className="dvd__spell-actions">
          {!allCast && (
            <button className="dvd__btn dvd__btn--spell" disabled={busy} onClick={() => run(castAll)}>
              Enchant {unenchantedIds.length}
            </button>
          )}
          {hasOwed && (
            <button className="dvd__btn dvd__btn--ghost" disabled={busy} onClick={() => run(withdrawOwed)}>
              Withdraw {pretty(owed)} ETH
            </button>
          )}
        </div>
      </div>

      {/* per-fren chips */}
      <div className="dvd__frens">
        {ownedGenesis.slice(0, 40).map((id, i) => (
          <span key={id.toString()} className={`dvd__chip ${enchanted[i] ? "dvd__chip--on" : ""}`}
            title={enchanted[i] ? "enchanted — earning fees" : "not enchanted — cast the spell"}>
            #{id.toString()}{enchanted[i] ? " ✦" : ""}
          </span>
        ))}
        {ownedGenesis.length > 40 && <span className="dvd__chip dvd__chip--more">+{ownedGenesis.length - 40}</span>}
      </div>

      <style>{css}</style>
    </div>
  );
}

const css = `
  .dvd {
    margin: 0 0 22px; padding: 18px 22px; border-radius: var(--r-md);
    border: 1px solid rgba(213, 253, 81, 0.28);
    background:
      radial-gradient(120% 140% at 0% 0%, rgba(213,253,81,0.10), transparent 55%),
      linear-gradient(160deg, #221a45 0%, #17112f 100%);
    box-shadow: 0 8px 30px rgba(12, 10, 26, 0.28);
  }
  .dvd--empty { display: flex; flex-direction: column; gap: 4px; }
  .dvd__top { display: flex; align-items: center; justify-content: space-between; gap: 20px; }
  .dvd__left { display: flex; flex-direction: column; gap: 3px; min-width: 0; }
  .dvd__label { font-family: "DM Mono", monospace; font-size: 10px; letter-spacing: 0.18em; text-transform: uppercase; color: #d5fd51; }
  .dvd__eth { font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: 30px; line-height: 1.05; color: #F5F0E8; }
  .dvd__eth em { font-style: normal; font-size: 15px; color: rgba(245,240,232,0.6); font-family: "DM Mono", monospace; }
  .dvd__sub { font-family: "DM Sans", sans-serif; font-size: 12.5px; color: rgba(231,225,245,0.6); }
  .dvd__err { font-family: "DM Mono", monospace; font-size: 11px; color: #ff8a7a; }
  .dvd__btn {
    flex-shrink: 0; font-family: "DM Mono", monospace; font-size: 13px; font-weight: 700; letter-spacing: 0.04em;
    color: #17112f; background: #d5fd51; border: none; border-radius: var(--r-sm);
    padding: 13px 22px; cursor: pointer; box-shadow: 0 5px 0 #a9cc2f; transition: transform .15s, box-shadow .15s, opacity .2s;
  }
  .dvd__btn:hover:not(:disabled) { transform: translateY(-1px); box-shadow: 0 6px 0 #a9cc2f; }
  .dvd__btn:disabled { opacity: 0.45; cursor: not-allowed; box-shadow: 0 5px 0 #6f8420; }
  .dvd__btn--spell { background: #b98cff; box-shadow: 0 5px 0 #7c5cfc; color: #16112b; }
  .dvd__btn--spell:hover:not(:disabled) { box-shadow: 0 6px 0 #7c5cfc; }
  .dvd__btn--ghost { background: transparent; color: #d5fd51; border: 1px solid rgba(213,253,81,0.4); box-shadow: none; padding: 12px 18px; }
  .dvd__btn--ghost:hover:not(:disabled) { background: rgba(213,253,81,0.08); transform: none; }
  .dvd__spell {
    display: flex; align-items: center; justify-content: space-between; gap: 16px; flex-wrap: wrap;
    margin-top: 16px; padding: 14px 16px; border-radius: var(--r-sm);
    background: rgba(124,92,252,0.10); border: 1px solid rgba(124,92,252,0.28);
  }
  .dvd__spell-info { display: flex; flex-direction: column; gap: 2px; }
  .dvd__spell-title { font-family: "DM Sans", sans-serif; font-weight: 800; font-size: 14px; color: #F5F0E8; display: flex; align-items: center; gap: 7px; }
  .dvd__rune { color: #b98cff; }
  .dvd__spell-sub { font-family: "DM Sans", sans-serif; font-size: 12px; color: rgba(231,225,245,0.62); }
  .dvd__spell-actions { display: flex; gap: 10px; flex-wrap: wrap; }
  .dvd__frens { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 14px; }
  .dvd__chip {
    font-family: "DM Mono", monospace; font-size: 10.5px; padding: 4px 8px; border-radius: var(--r-sm);
    color: rgba(231,225,245,0.55); background: rgba(255,255,255,0.04); border: 1px solid rgba(255,255,255,0.06);
  }
  .dvd__chip--on { color: #d5fd51; background: rgba(213,253,81,0.10); border-color: rgba(213,253,81,0.32); }
  .dvd__chip--more { color: rgba(231,225,245,0.4); }
`;
