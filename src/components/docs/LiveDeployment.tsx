import { useEffect, useMemo, useState } from "react";
import { usePublicClient } from "wagmi";
import type { Address } from "viem";
import { CAULDRON, REGISTRY_ABI } from "@/config/cauldron";
import {
  EXPLORER_BASE,
  IS_MAINNET,
  NETWORK_LABEL,
  explorerAddressUrl,
} from "@/config/chains";

/**
 * LiveDeployment — the docs page's address table, read from the SAME manifest the
 * app runs on plus live registry calls.
 *
 * WHY THIS EXISTS: the written docs used to hard-code a table of addresses, which
 * went stale the moment a new round shipped — and iteration-specific addresses
 * (token, collection, pool id) rotate on EVERY rebirth, so a static table is wrong
 * by construction. The core set comes from `CAULDRON` (backed by
 * indexer/deployments/round.json, the one file both the frontend and the indexer
 * read) and the rotating set is read live from the registry. Nothing here can
 * drift from what the app is actually pointed at.
 */

/** A row that never changes within a round. */
interface StaticRow {
  label: string;
  address?: Address;
  note: string;
}

/** A row read live off the registry, because it rotates at every rebirth. */
interface LiveRow {
  label: string;
  value?: string;
  note: string;
  isAddress: boolean;
}

const shorten = (a: string) =>
  a && a.length > 16 ? `${a.slice(0, 10)}…${a.slice(-8)}` : a;

/** Pre-summon, the registry returns the zero address / zero pool id for the
 *  rotating slots. Rendering that as a clickable "address" would be misleading. */
const isZero = (v?: string) => !v || /^0x0+$/i.test(v);

export default function LiveDeployment() {
  const publicClient = usePublicClient({ chainId: CAULDRON.chainId });
  const [live, setLive] = useState<{
    gen?: number;
    token?: Address;
    collection?: Address;
    poolId?: string;
  }>({});
  const [failed, setFailed] = useState(false);
  const [copied, setCopied] = useState<string | null>(null);

  // Read the rotating, per-iteration addresses straight from the registry. This
  // is the same call path the app uses, so the docs can never disagree with it.
  useEffect(() => {
    // No client for this chain (misconfigured wagmi) — degrade immediately rather
    // than leaving the rows spinning on "reading…" forever.
    if (!publicClient) {
      setFailed(true);
      return;
    }
    let cancelled = false;
    // Public RPCs rate-limit and occasionally just hang. Bound the wait so the
    // panel always resolves to either an address or an honest "read it yourself".
    const timer = window.setTimeout(() => {
      if (!cancelled) setFailed(true);
    }, 12_000);
    (async () => {
      try {
        const registry = { address: CAULDRON.registry, abi: REGISTRY_ABI } as const;
        const [gen, token] = await Promise.all([
          publicClient.readContract({ ...registry, functionName: "currentGeneration" }),
          publicClient.readContract({ ...registry, functionName: "currentToken" }),
        ]);
        const g = Number(gen as bigint);
        // These two are keyed by generation, so they need `gen` resolved first.
        const [collection, poolId] = await Promise.all([
          publicClient
            .readContract({
              ...registry,
              functionName: "generationCollection",
              args: [BigInt(g)],
            })
            .catch(() => undefined),
          publicClient
            .readContract({
              ...registry,
              functionName: "generationPoolId",
              args: [BigInt(g)],
            })
            .catch(() => undefined),
        ]);
        if (cancelled) return;
        window.clearTimeout(timer);
        setLive({
          gen: g,
          token: token as Address,
          collection: collection as Address | undefined,
          poolId: poolId as string | undefined,
        });
      } catch {
        // A dead RPC must degrade to "read it yourself", never to a wrong address.
        if (!cancelled) setFailed(true);
      }
    })();
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [publicClient]);

  const staticRows: StaticRow[] = useMemo(
    () => [
      { label: "CauldronRegistry", address: CAULDRON.registry, note: "Lifecycle, custody, migration" },
      { label: "CauldronHook", address: CAULDRON.hook, note: "Fees, volume, gacha, liquidations" },
      { label: "MiFrensGenesis", address: CAULDRON.mifrens, note: "The genesis collection + electorate" },
      { label: "MiFrensDividend", address: CAULDRON.dividend, note: "Perpetual genesis fee dividend" },
      { label: "CauldronGovernor", address: CAULDRON.governor, note: "Proposals + checkpointed voting" },
      { label: "CollectionLedger", address: CAULDRON.collectionLedger, note: "Per-collection floor cap table" },
      { label: "CauldronGachaRouter", address: CAULDRON.gachaRouter, note: "One-click play" },
      { label: "TimelockController", address: CAULDRON.timelock, note: "Owns hook + engine; emergency admin" },
      { label: "Uniswap v4 PoolManager", address: CAULDRON.poolManager, note: "External — Uniswap" },
    ],
    [],
  );

  const liveRows: LiveRow[] = useMemo(
    () => [
      {
        label: "Live token",
        value: live.token,
        note: "registry.currentToken()",
        isAddress: true,
      },
      {
        label: "Live collection",
        value: live.collection,
        note: "registry.generationCollection(gen)",
        isAddress: true,
      },
      {
        label: "Live pool id",
        value: live.poolId,
        note: "registry.generationPoolId(gen)",
        isAddress: false,
      },
    ],
    [live],
  );

  const copy = (value: string) => {
    navigator.clipboard?.writeText(value).then(
      () => {
        setCopied(value);
        window.setTimeout(() => setCopied((c) => (c === value ? null : c)), 1400);
      },
      () => {/* clipboard blocked (insecure context) — the address is still visible */},
    );
  };

  const renderAddress = (value: string, asLink: boolean) => (
    <span className="ld__addr-wrap">
      {asLink ? (
        <a
          className="ld__addr"
          href={explorerAddressUrl(value)}
          target="_blank"
          rel="noreferrer"
          title={value}
        >
          {shorten(value)}
        </a>
      ) : (
        <span className="ld__addr" title={value}>
          {shorten(value)}
        </span>
      )}
      <button
        type="button"
        className="ld__copy"
        onClick={() => copy(value)}
        aria-label={`Copy ${value}`}
        title="Copy"
      >
        {copied === value ? "✓" : "⧉"}
      </button>
    </span>
  );

  return (
    <section className="ld" id="live-deployment">
      <div className="ld__head">
        <div>
          <h2 className="ld__title">Live deployment</h2>
          <p className="ld__sub">
            Read from the same manifest the app runs on, plus live registry calls —
            so this table can never drift from the contracts you are actually
            trading against.
          </p>
        </div>
        <div className="ld__badges">
          <span className={`ld__pill ${IS_MAINNET ? "ld__pill--live" : "ld__pill--test"}`}>
            {IS_MAINNET ? "◉ MAINNET" : "◉ TESTNET"} · {NETWORK_LABEL}
          </span>
          <span className="ld__pill ld__pill--muted">chainId {CAULDRON.chainId}</span>
          {live.gen !== undefined && (
            <span className="ld__pill ld__pill--muted">iteration #{live.gen}</span>
          )}
        </div>
      </div>

      {/* Rotating, per-iteration — the reason a static table would be wrong. */}
      <div className="ld__group">
        <div className="ld__group-title">
          Rotates every rebirth
          <span className="ld__group-hint">read live from the registry</span>
        </div>
        <div className="ld__grid">
          {liveRows.map((r) => (
            <div className="ld__row" key={r.label}>
              <div className="ld__label">{r.label}</div>
              <div className="ld__value">
                {r.value && !isZero(r.value) ? (
                  renderAddress(r.value, r.isAddress)
                ) : r.value ? (
                  <span className="ld__dim">not summoned yet</span>
                ) : failed ? (
                  <span className="ld__dim">RPC unavailable — read it yourself</span>
                ) : (
                  <span className="ld__dim ld__dim--pulse">reading…</span>
                )}
              </div>
              <div className="ld__note">
                <code>{r.note}</code>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Fixed for the round. */}
      <div className="ld__group">
        <div className="ld__group-title">
          Fixed for this round
          <span className="ld__group-hint">indexer/deployments/round.json</span>
        </div>
        <div className="ld__grid">
          {staticRows.map((r) => (
            <div className="ld__row" key={r.label}>
              <div className="ld__label">{r.label}</div>
              <div className="ld__value">
                {r.address ? renderAddress(r.address, true) : <span className="ld__dim">not set</span>}
              </div>
              <div className="ld__note">{r.note}</div>
            </div>
          ))}
        </div>
      </div>

      <p className="ld__foot">
        Verify any address on{" "}
        <a href={EXPLORER_BASE} target="_blank" rel="noreferrer">
          the explorer
        </a>
        . The perp engine and vault addresses are in the same manifest; the
        iteration&apos;s NFT vault is read with{" "}
        <code>registry.generationVault(gen)</code>.
      </p>

      <style>{styles}</style>
    </section>
  );
}

const styles = `
  .ld {
    max-width: 1100px; margin: 0 auto; padding: 8px 24px 0;
    font-family: "DM Sans", sans-serif;
  }
  .ld__head {
    display: flex; flex-wrap: wrap; gap: 16px;
    align-items: flex-start; justify-content: space-between;
    padding-bottom: 18px; margin-bottom: 22px;
    border-bottom: 1px solid rgba(213,253,81,0.12);
  }
  .ld__title {
    font-family: "Cinzel", serif; font-size: 24px; color: #FFFFFF; margin: 0 0 8px;
  }
  .ld__sub {
    margin: 0; max-width: 560px; font-size: 14px; line-height: 1.6;
    color: rgba(231,225,245,0.62);
  }
  .ld__badges { display: flex; flex-wrap: wrap; gap: 8px; }
  .ld__pill {
    font-family: "Fredoka", sans-serif; font-size: 11px; font-weight: 600;
    letter-spacing: 0.06em; padding: 6px 12px; border-radius: var(--r-md);
    border: 1px solid rgba(124,92,252,0.3); color: #c9b8ff;
    background: rgba(124,92,252,0.1); white-space: nowrap;
  }
  .ld__pill--live { border-color: rgba(213,253,81,0.5); color: #d5fd51; background: rgba(213,253,81,0.1); }
  .ld__pill--test { border-color: rgba(255,180,84,0.45); color: #ffb454; background: rgba(255,180,84,0.09); }
  .ld__pill--muted { opacity: 0.75; }

  .ld__group { margin-bottom: 26px; }
  .ld__group-title {
    display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap;
    font-family: "Fredoka", sans-serif; font-size: 11px; letter-spacing: 0.16em;
    text-transform: uppercase; color: #8A7BAA; margin-bottom: 10px;
  }
  .ld__group-hint {
    font-family: ui-monospace, monospace; font-size: 10.5px;
    letter-spacing: 0; text-transform: none; color: rgba(231,225,245,0.34);
  }

  .ld__grid {
    border: 1px solid rgba(124,92,252,0.16); border-radius: var(--r-sm); overflow: hidden;
    background: rgba(124,92,252,0.04);
  }
  .ld__row {
    display: grid; grid-template-columns: 200px minmax(0,1fr) minmax(0,1fr);
    gap: 14px; align-items: center;
    padding: 11px 16px; border-bottom: 1px solid rgba(124,92,252,0.1);
  }
  .ld__row:last-child { border-bottom: none; }
  .ld__row:hover { background: rgba(124,92,252,0.06); }
  .ld__label {
    font-family: "Fredoka", sans-serif; font-size: 13px; color: #E9E3FB; font-weight: 500;
  }
  .ld__value { min-width: 0; }
  .ld__addr-wrap { display: inline-flex; align-items: center; gap: 6px; }
  .ld__addr {
    font-family: ui-monospace, "SF Mono", monospace; font-size: 12.5px;
    color: #d5fd51; text-decoration: none; word-break: break-all;
  }
  a.ld__addr:hover { text-decoration: underline; text-underline-offset: 3px; }
  .ld__copy {
    background: none; border: 1px solid rgba(213,253,81,0.22); border-radius: var(--r-chip);
    color: rgba(213,253,81,0.7); cursor: pointer; font-size: 11px;
    padding: 1px 6px; line-height: 1.5; transition: all .15s ease;
  }
  .ld__copy:hover { background: rgba(213,253,81,0.12); color: #d5fd51; }
  .ld__note { font-size: 12px; color: rgba(231,225,245,0.5); min-width: 0; }
  .ld__note code {
    font-family: ui-monospace, monospace; font-size: 11.5px;
    background: rgba(124,92,252,0.14); color: #c9b8ff;
    padding: 1px 5px; border-radius: 4px; word-break: break-word;
  }
  .ld__dim { font-size: 12.5px; color: rgba(231,225,245,0.4); }
  .ld__dim--pulse { animation: ldpulse 1.4s ease-in-out infinite; }
  @keyframes ldpulse { 0%,100% { opacity: .4 } 50% { opacity: .8 } }

  .ld__foot {
    font-size: 13px; line-height: 1.65; color: rgba(231,225,245,0.55); margin: 0;
  }
  .ld__foot a { color: #d5fd51; }
  .ld__foot code {
    font-family: ui-monospace, monospace; font-size: 12px;
    background: rgba(124,92,252,0.14); color: #c9b8ff;
    padding: 1px 5px; border-radius: 4px;
  }

  @media (max-width: 760px) {
    .ld__row { grid-template-columns: 1fr; gap: 4px; padding: 12px 14px; }
    .ld__note { font-size: 11.5px; }
  }
  @media (prefers-reduced-motion: reduce) {
    .ld__dim--pulse { animation: none; }
  }
`;
