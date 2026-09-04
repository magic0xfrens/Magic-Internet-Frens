import { useCallback, useMemo, useRef, useState } from "react";
import { parseEther, parseEventLogs, type Address } from "viem";
import { useAccount, useReadContract, usePublicClient } from "wagmi";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { useCauldronSwap } from "@/hooks/useCauldronSwap";
import { CAULDRON, HOOK_ABI, COLLECTION_ABI } from "@/config/cauldron";

/* ══════════════════════════════════════════════════════════════════
 * CRYSTAL CAULDRON — spin volume, summon crystals, open them.
 *
 *   SPIN   Buy▸Sell▸Buy churn loops (pick how many) → earns Mana. More
 *          loops = more volume from the same ETH = more chances.
 *   SUMMON lucky → a SEALED CRYSTAL NFT is minted to you (a real ERC-721
 *          you can open OR flip on OpenSea unopened). Unlucky → not enough
 *          Mana, spin again.
 *   OPEN   crack a sealed crystal → reveal the creature inside (rarity roll).
 *
 * All on-chain, commit-reveal & grind-resistant: a crystal is summoned in
 * one block and its contents are sealed by a future blockhash, so nobody
 * can foresee or re-roll what's inside.
 * ════════════════════════════════════════════════════════════════════ */

const STAKES = [0.01, 0.03, 0.05, 0.1];
const LOOPS = [1, 3, 5, 8];
const RARITY = ["Common", "Rare", "Epic", "Ultra"];
const RARITY_COL = ["#8f83b8", "#5ac8fa", "#c07cff", "#f5c542"];

/** A summoned crystal. Sealed shows the crystal art; once opened, `image` holds
 *  the creature's REAL on-chain art (from the collection's tokenURI). */
type Crystal = { tokenId: bigint; revealed: boolean; image?: string; name?: string; rarity?: number };

/** Pull the image (+name) out of an ERC-721 tokenURI (on-chain data-URI or URL). */
function imageFromTokenURI(uri: string): { image?: string; name?: string } {
  try {
    if (uri.startsWith("data:application/json;base64,")) {
      const j = JSON.parse(atob(uri.slice("data:application/json;base64,".length)));
      return { image: j.image, name: j.name };
    }
    if (uri.startsWith("data:application/json,")) {
      const j = JSON.parse(decodeURIComponent(uri.slice("data:application/json,".length)));
      return { image: j.image, name: j.name };
    }
    if (uri.startsWith("http") || uri.startsWith("ipfs")) return { image: uri };
  } catch { /* ignore */ }
  return {};
}

/** Renders a creature's real on-chain art (falls back to the crystal while the
 *  tokenURI image loads). */
function CreatureTile({ image, size = 64 }: { image?: string; size?: number }) {
  return (
    <div className="ccg-tile" style={{ width: size, height: size }}>
      <img src={image || "/crystal.png"} alt="" />
    </div>
  );
}

type Phase = "idle" | "spinning" | "summoned" | "forged" | "fizzle" | "opening" | "opened";
type SpinResult = { forged: number; won: number; lost: number };

interface Props {
  ticker: string;
  token?: Address;
  collection?: Address;
  spotPrice: number;
  ethUsd: number;
  col: string;
  nftMinted: number;
  nftMax: number;
  onBought?: () => void;
}

export default function CrystalCauldronGame({ collection, ethUsd, col, nftMinted, nftMax, onBought }: Props) {
  const { address, isConnected } = useAccount();
  const { openConnectModal } = useConnectModal();
  const pub = usePublicClient({ chainId: CAULDRON.chainId });
  const { spin, reveal, isPending, reset } = useCauldronSwap();

  const [stake, setStake] = useState(0.03);
  const [loops, setLoops] = useState(3);
  const [phase, setPhase] = useState<Phase>("idle");
  const [vault, setVault] = useState<Crystal[]>([]);
  const [flash, setFlash] = useState<{ image?: string; name?: string } | null>(null); // last opened creature, for the burst
  const [result, setResult] = useState<SpinResult | null>(null); // this spin's outcome (for the resolution card)
  const [err, setErr] = useState("");

  const action = useRef<"spin" | "open" | null>(null);
  const openingId = useRef<bigint | null>(null);

  const soldOut = nftMax > 0 && nftMinted >= nftMax;
  const rd = { chainId: CAULDRON.chainId } as const;
  const hook = { address: CAULDRON.hook, abi: HOOK_ABI, ...rd } as const;
  const qEnabled = { query: { enabled: !!address } };

  const { data: opened, refetch: refOpened } = useReadContract({ ...hook, functionName: "opened", args: address ? [address] : undefined, ...qEnabled });
  const { data: miss, refetch: refMiss } = useReadContract({ ...hook, functionName: "missStreak", args: address ? [address] : undefined, ...qEnabled });
  const { data: pity } = useReadContract({ ...hook, functionName: "pityThreshold" });
  const { data: prog, refetch: refProg } = useReadContract({ ...hook, functionName: "progress", args: address ? [address] : undefined, ...qEnabled });
  const spinWei = parseEther((stake * loops).toFixed(18));
  const { data: oddsBps } = useReadContract({ ...hook, functionName: "oddsForPlay", args: [spinWei], query: { placeholderData: (p) => p } });

  const openedN = opened != null ? Number(opened as bigint) : 0;
  const missN = miss != null ? Number(miss as bigint) : 0;
  const pityN = pity != null ? Number(pity as bigint) : 8;
  const winPct = oddsBps != null ? Number(oddsBps as bigint) / 100 : 0;
  const pityLeft = Math.max(pityN - missN, 0);
  const [inMana, manaThreshold] = (prog as [bigint, bigint, bigint] | undefined) ?? [0n, 0n, 0n];
  const manaPct = manaThreshold > 0n ? Math.min(100, Number((inMana * 100n) / manaThreshold)) : 0;

  const sealed = vault.filter((c) => !c.revealed);
  const busy = isPending || phase === "spinning" || phase === "opening";

  const friendlyErr = (e: unknown, fallback: string) => {
    const m = e as { shortMessage?: string; message?: string };
    const raw = m?.shortMessage || m?.message || fallback;
    return raw.length > 140 ? raw.slice(0, 140) + "…" : raw;
  };

  const doSpin = useCallback(async () => {
    setErr("");
    if (!isConnected) { openConnectModal?.(); return; }
    if (soldOut) { setErr("Collection minted out — no crystals left."); return; }
    if (!pub) { setErr("No RPC client"); return; }
    action.current = "spin";
    setResult(null);
    setPhase("spinning");
    try {
      const hash = await spin(stake, loops, 0);
      // Drive resolution from the tx receipt DIRECTLY (not the reactive hook, which
      // can hang if the app's RPC lags the wallet's). Detect revert explicitly.
      const rcpt = await pub.waitForTransactionReceipt({ hash, timeout: 90_000 });
      if (rcpt.status === "reverted") {
        setErr("Spin reverted on-chain. Is the brew summoned & live?");
        setPhase("idle");
        return;
      }
      const mine = (l: { args: { player?: string } }) => l.args.player?.toLowerCase() === address?.toLowerCase();
      // Three outcomes in one tx (commit-reveal): crystals FORGED this spin
      // (CrystalsCommitted), and PRIOR crystals RESOLVING now as wins (TicketWon)
      // or misses (TicketLost).
      let forged = 0, wonIds: bigint[] = [], lost = 0;
      try {
        const cm = parseEventLogs({ abi: HOOK_ABI, logs: rcpt.logs, eventName: "CrystalsCommitted" });
        forged = cm.filter(mine).reduce((s, l) => s + Number((l.args as { count: bigint }).count), 0);
      } catch { /* none */ }
      try {
        const won = parseEventLogs({ abi: HOOK_ABI, logs: rcpt.logs, eventName: "TicketWon" });
        wonIds = won.filter(mine).map((l) => (l.args as { tokenId: bigint }).tokenId);
      } catch { /* none */ }
      try {
        const ls = parseEventLogs({ abi: HOOK_ABI, logs: rcpt.logs, eventName: "TicketLost" });
        lost = ls.filter(mine).length;
      } catch { /* none */ }

      // Add won crystals (sealed NFTs) to the vault.
      if (wonIds.length > 0) {
        setVault((v) => {
          const have = new Set(v.map((c) => c.tokenId.toString()));
          const add = wonIds.filter((id) => !have.has(id.toString())).map((id) => ({ tokenId: id, revealed: false }));
          return [...add, ...v];
        });
      }
      // Record the outcome for the resolution card, then pick the phase:
      // a WIN if crystals were summoned; else FORGED (you sealed some, resolve next
      // spin); else FIZZLE (not enough mana).
      setResult({ forged, won: wonIds.length, lost });
      setPhase(wonIds.length > 0 ? "summoned" : forged > 0 ? "forged" : "fizzle");
      Promise.all([refOpened(), refMiss(), refProg()]).then(() => onBought?.()).catch(() => {});
    } catch (e: unknown) {
      setErr(friendlyErr(e, "Spin failed"));
      setPhase("idle");
    } finally {
      reset();
    }
  }, [isConnected, openConnectModal, soldOut, pub, spin, stake, loops, address, refOpened, refMiss, refProg, onBought, reset]);

  const doOpen = useCallback(async (id: bigint) => {
    setErr("");
    if (!collection) { setErr("No collection yet"); return; }
    if (!pub) { setErr("No RPC client"); return; }
    action.current = "open";
    openingId.current = id;
    setPhase("opening");
    try {
      const hash = await reveal(collection, id);
      const rcpt = await pub.waitForTransactionReceipt({ hash, timeout: 90_000 });
      if (rcpt.status === "reverted") {
        setErr("Open reverted on-chain.");
        setPhase("idle");
        return;
      }
      setVault((v) => v.map((c) => (c.tokenId === id ? { ...c, revealed: true } : c)));
      setPhase("opened");
      // Pull the creature's REAL on-chain art (tokenURI) + rarity badge.
      pub.readContract({ address: collection, abi: COLLECTION_ABI, functionName: "tokenURI", args: [id] })
        .then((uri) => {
          const { image, name } = imageFromTokenURI(uri as string);
          setVault((v) => v.map((c) => (c.tokenId === id ? { ...c, image, name } : c)));
          setFlash({ image, name });
        })
        .catch(() => {});
      pub.readContract({ address: collection, abi: COLLECTION_ABI, functionName: "rarityOf", args: [id] })
        .then((r) => setVault((v) => v.map((c) => (c.tokenId === id ? { ...c, rarity: Number(r) } : c))))
        .catch(() => {});
      onBought?.();
    } catch (e: unknown) {
      setErr(friendlyErr(e, "Open failed"));
      setPhase("idle");
    } finally {
      reset();
    }
  }, [collection, pub, reveal, onBought, reset]);

  const spinCost = (stake * ethUsd).toFixed(2);

  const status = useMemo(() => {
    if (isPending) return action.current === "open" ? "Confirm the crack in your wallet…" : "Confirm the spin in your wallet…";
    if (phase === "spinning") return "Churning volume… summoning…";
    if (phase === "opening") return "Cracking the crystal…";
    if (phase === "summoned") return result?.won ? `✦ ${result.won} crystal${result.won > 1 ? "s" : ""} summoned! Open below.` : "✦ Crystal summoned! Open it below.";
    if (phase === "forged") return `🔮 ${result?.forged ?? 0} crystal${(result?.forged ?? 0) > 1 ? "s" : ""} forged — resolves on your next spin.`;
    if (phase === "fizzle") return "Not enough Mana yet — spin again.";
    if (phase === "opened") return flash?.name ? `${flash.name} revealed!` : "Creature revealed!";
    return "Spin volume to summon a crystal.";
  }, [isPending, phase, flash, result]);

  return (
    <section className="ccg">
      <style>{css(col)}</style>

      <div className="ccg-head">
        <div className="ccg-eyebrow" style={{ color: col }}>◆ Crystal gacha · summon from volume</div>
        <div className="ccg-mint">{nftMax > 0 ? `${nftMinted}/${nftMax}` : nftMinted} forged</div>
      </div>
      <h3 className="ccg-title">Summon Crystals</h3>

      {/* ── the brewing wizard (the machine) ── */}
      <div className={`ccg-stage ccg-stage--${phase}`}>
        <div className={`ccg-glow ${busy ? "ccg-glow--hot" : ""}`} aria-hidden />
        <img
          className={`ccg-hero ${phase === "spinning" ? "ccg-hero--brew" : ""} ${phase === "summoned" || phase === "opened" ? "ccg-hero--win" : ""}`}
          src="/brew-crystals.png" alt="A wizard fren brewing crystals" draggable={false}
        />
        {phase === "opened" && (
          <div className="ccg-prize">
            <div className="ccg-prize-burst" aria-hidden />
            <CreatureTile image={flash?.image} size={78} />
            <div className="ccg-prize-label">{flash?.name ?? "Creature"} revealed!</div>
          </div>
        )}

        {/* ── spin RESOLUTION card — WIN (crystals summoned), FORGED (sealed,
            resolve next spin), or FIZZLE (not enough mana) ── */}
        {phase === "summoned" && result && (
          <div className="ccg-resolve ccg-resolve--win">
            <div className="ccg-prize-burst" aria-hidden />
            <div className="ccg-resolve-crystals">
              {Array.from({ length: Math.min(result.won, 5) }).map((_, i) => (
                <img key={i} className="ccg-resolve-crystal" src="/crystal.png" alt="" style={{ animationDelay: `${i * 90}ms` }} />
              ))}
            </div>
            <div className="ccg-resolve-big">+{result.won} 🔮</div>
            <div className="ccg-resolve-sub">{result.won > 1 ? "crystals summoned!" : "crystal summoned!"}{result.lost > 0 ? ` · ${result.lost} fizzled` : ""}</div>
          </div>
        )}
        {phase === "forged" && result && (
          <div className="ccg-resolve ccg-resolve--forged">
            <div className="ccg-resolve-big" style={{ color: col }}>{result.forged} sealed</div>
            <div className="ccg-resolve-sub">🔮 forged — reveal on your next spin</div>
          </div>
        )}
        {phase === "fizzle" && (
          <div className="ccg-resolve ccg-resolve--fizzle">
            <div className="ccg-resolve-big">✨</div>
            <div className="ccg-resolve-sub">Not enough Mana — spin again to summon</div>
          </div>
        )}
      </div>

      <div className={`ccg-status ccg-status--${phase}`}>{status}</div>

      {/* ── Mana bar ── */}
      <div className="ccg-mana">
        <div className="ccg-mana-top"><span>✦ Mana</span><span>{manaPct}% to next crystal</span></div>
        <div className="ccg-mana-bar"><div style={{ width: `${manaPct}%`, background: col }} /></div>
      </div>

      {/* ── compact controls: labeled pill rows (loops + stake) ── */}
      <div className="ccg-ctrl">
        <span className="ccg-ctrl-lbl">Loops</span>
        <div className="ccg-pills">
          {LOOPS.map((l) => (
            <button key={l} className={`ccg-pill ${loops === l ? "on" : ""}`} disabled={busy} onClick={() => setLoops(l)}>{l}×</button>
          ))}
        </div>
      </div>
      <div className="ccg-ctrl">
        <span className="ccg-ctrl-lbl">Stake</span>
        <div className="ccg-pills">
          {STAKES.map((s) => (
            <button key={s} className={`ccg-pill ${stake === s ? "on" : ""}`} disabled={busy} onClick={() => setStake(s)}>{s}<i>Ξ</i></button>
          ))}
        </div>
      </div>

      {/* ── odds: one tight line (chance + bar + context) ── */}
      <div className="ccg-odds">
        <div className="ccg-odds-row">
          <span>Summon chance</span>
          <span className="ccg-odds-v" style={{ color: col }}>{winPct > 0 ? `${winPct.toFixed(0)}%` : "—"}</span>
        </div>
        <div className="ccg-odds-bar"><div style={{ width: `${Math.min(winPct, 100)}%`, background: col }} /></div>
        <div className="ccg-odds-sub">≈ ${spinCost} · {loops}× volume{winPct > 0 ? ` · ${winPct.toFixed(0)}% to summon` : " · grind Mana"}</div>
      </div>

      <button className="ccg-cta" onClick={doSpin} disabled={busy || soldOut}>
        {busy && action.current === "spin" && <span className="ccg-spin" />}
        {!isConnected ? "Connect wallet" : soldOut ? "Minted out"
          : isPending && action.current === "spin" ? "Confirm in wallet…"
          : phase === "spinning" ? "Spinning…"
          : `🌀 Spin ${loops}× · ${stake} Ξ`}
      </button>

      {err && <div className="ccg-err">{err}</div>}

      {/* ── crystal vault ── */}
      <div className="ccg-vault">
        <div className="ccg-vault-head">
          <span>Your crystals</span>
          <span className="ccg-vault-n">{sealed.length} sealed</span>
        </div>
        {vault.length === 0 ? (
          <div className="ccg-vault-empty">No crystals yet — spin to summon your first.</div>
        ) : (
          <div className="ccg-vault-grid">
            {vault.slice(0, 12).map((c) => (
              <div key={c.tokenId.toString()} className={`ccg-cry ${c.revealed ? "ccg-cry--open" : ""}`}>
                {c.revealed ? (
                  <>
                    <CreatureTile image={c.image} size={62} />
                    {c.rarity != null && <span className="ccg-rar" style={{ color: RARITY_COL[c.rarity], borderColor: `${RARITY_COL[c.rarity]}66` }}>{RARITY[c.rarity]}</span>}
                  </>
                ) : (
                  <>
                    <img className="ccg-cry-img" src="/crystal.png" alt="Sealed crystal" />
                    <button className="ccg-open" disabled={busy} onClick={() => doOpen(c.tokenId)}>
                      {phase === "opening" && openingId.current === c.tokenId ? "Opening…" : "Open"}
                    </button>
                  </>
                )}
                <span className="ccg-cry-id">#{c.tokenId.toString()}</span>
              </div>
            ))}
          </div>
        )}
        {sealed.length > 0 && <div className="ccg-vault-tip">Open a crystal to reveal the creature — or flip it sealed on OpenSea.</div>}
      </div>

      {/* ── pity ── */}
      <div className="ccg-pity">
        <div className="ccg-pity-top"><span>Pity meter</span><span className="ccg-pity-v">{pityLeft === 0 ? "GUARANTEED next" : `${pityLeft} until guaranteed`}</span></div>
        <div className="ccg-pity-pips">
          {Array.from({ length: pityN }).map((_, i) => (
            <span key={i} className={`ccg-pip ${i < missN ? "on" : ""}`} style={i < missN ? { background: col } : undefined} />
          ))}
        </div>
        <div className="ccg-foot">Summoned lifetime: {openedN} · commit-reveal · a sealed crystal is a real NFT you can open or trade</div>
      </div>
    </section>
  );
}

const C = { void: "#0E0A1A", cream: "#f5f0e8", mute: "#8f83b8", red: "#ff4d6d", amber: "#f5c542" };

const css = (col: string) => `
  .ccg { position: relative; border-radius: var(--r-md); padding: 18px 16px 16px;
    background: radial-gradient(120% 90% at 50% -10%, ${col}0e, transparent 60%), rgba(20, 14, 40, 0.55);
    border: 1px solid ${col}26; overflow: hidden; }
  .ccg-head { display: flex; align-items: baseline; justify-content: space-between; }
  .ccg-eyebrow { font-family: "DM Mono", monospace; font-size: 9px; letter-spacing: 0.15em; text-transform: uppercase; }
  .ccg-mint { font-family: "DM Mono", monospace; font-size: 9px; color: ${C.mute}; }
  .ccg-title { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 20px; color: ${C.cream}; margin: 2px 0 12px; }

  .ccg-stage { position: relative; height: 250px; display: grid; place-items: center; margin-bottom: 8px; border-radius: var(--r-sm); overflow: hidden; }
  .ccg-glow { position: absolute; inset: 0; background: radial-gradient(58% 52% at 60% 60%, ${col}22, transparent 70%); transition: opacity 0.4s; }
  .ccg-glow--hot { animation: ccg-glowpulse 0.9s ease-in-out infinite; }
  .ccg-hero { position: relative; z-index: 2; max-width: 76%; max-height: 84%; object-fit: contain; object-position: top; margin-top: -22px;
    filter: drop-shadow(0 6px 22px rgba(0,0,0,0.5)); transition: filter 0.3s ease, transform 0.3s ease;
    animation: ccg-float 5.5s ease-in-out infinite; will-change: transform; }
  .ccg-hero--brew { animation: ccg-brew 0.5s ease-in-out infinite; filter: drop-shadow(0 0 26px ${col}) saturate(1.22) brightness(1.07); }
  .ccg-hero--win { animation: none; transform: scale(1.03); filter: drop-shadow(0 0 42px ${col}) saturate(1.3) brightness(1.12); }
  .ccg-tile { position: relative; border-radius: var(--r-sm); overflow: hidden; }
  .ccg-tile img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: contain; image-rendering: pixelated; }

  .ccg-prize { position: absolute; z-index: 3; bottom: 8px; display: flex; flex-direction: column; align-items: center; gap: 6px; animation: ccg-pop 0.5s cubic-bezier(.2,1.5,.4,1); }
  .ccg-prize-burst { position: absolute; inset: -35% 15% 0; z-index: -1; border-radius: 50%; background: radial-gradient(circle, ${col}55, transparent 65%); animation: ccg-flash 0.7s ease-out; }
  .ccg-prize-tiles .ccg-tile, .ccg-prize .ccg-tile { box-shadow: 0 0 18px ${col}99, 0 4px 10px rgba(0,0,0,0.5); }
  .ccg-prize-label { font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 13px; color: ${col}; background: rgba(8,6,15,0.72); padding: 3px 12px; border-radius: var(--r-chip); border: 1px solid ${col}66; text-shadow: 0 0 10px ${col}; }

  /* spin resolution card */
  .ccg-resolve { position: absolute; z-index: 4; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px;
    background: radial-gradient(70% 60% at 50% 45%, rgba(8,6,15,0.55), rgba(8,6,15,0.86)); animation: ccg-pop 0.45s cubic-bezier(.2,1.5,.4,1); }
  .ccg-resolve-crystals { display: flex; gap: 6px; margin-bottom: 2px; }
  .ccg-resolve-crystal { width: 44px; height: 44px; object-fit: contain; filter: drop-shadow(0 0 12px ${col}); animation: ccg-crystal-in 0.5s cubic-bezier(.2,1.6,.4,1) both; }
  .ccg-resolve-big { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 34px; color: ${col}; text-shadow: 0 0 24px ${col}88; line-height: 1; }
  .ccg-resolve--fizzle .ccg-resolve-big { color: ${C.mute}; text-shadow: none; font-size: 40px; }
  .ccg-resolve-sub { font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 13px; color: ${C.cream}; opacity: 0.92; text-align: center; padding: 0 16px; }
  @keyframes ccg-crystal-in { from { opacity: 0; transform: translateY(14px) scale(0.5) rotate(-12deg); } to { opacity: 1; transform: none; } }

  .ccg-status { text-align: center; font-family: "DM Sans", sans-serif; font-size: 12px; min-height: 17px; color: ${C.mute}; margin-bottom: 12px; }
  .ccg-status--summoned, .ccg-status--opened { color: ${col}; font-weight: 700; }
  .ccg-status--fizzle { color: ${C.amber}; }

  .ccg-mana { margin-bottom: 12px; }
  .ccg-mana-top { display: flex; justify-content: space-between; font-family: "DM Mono", monospace; font-size: 9.5px; color: ${C.mute}; margin-bottom: 5px; }
  .ccg-mana-bar { height: 6px; border-radius: 3px; background: rgba(255,255,255,0.06); overflow: hidden; }
  .ccg-mana-bar > div { height: 100%; border-radius: 3px; transition: width 0.4s ease; box-shadow: 0 0 10px ${col}; }

  /* compact labeled pill rows */
  .ccg-ctrl { display: flex; align-items: center; gap: 10px; margin-bottom: 7px; }
  .ccg-ctrl-lbl { flex: 0 0 42px; font-family: "DM Mono", monospace; font-size: 9px; letter-spacing: 0.08em; text-transform: uppercase; color: ${C.mute}; opacity: 0.85; }
  .ccg-pills { display: flex; gap: 5px; flex: 1; }
  .ccg-pill { flex: 1; padding: 6px 0; border-radius: var(--r-sm); background: rgba(255,255,255,0.03); border: 1px solid rgba(255,255,255,0.07); color: ${C.cream}; cursor: pointer; transition: all 0.15s; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 12.5px; line-height: 1; }
  .ccg-pill i { font-style: normal; font-size: 9px; opacity: 0.6; margin-left: 1px; }
  .ccg-pill:hover:not(:disabled) { border-color: ${col}66; }
  .ccg-pill.on { background: ${col}18; border-color: ${col}; color: ${col}; }
  .ccg-pill:disabled { opacity: 0.5; cursor: default; }

  .ccg-odds { margin: 11px 0 12px; }
  .ccg-odds-row { display: flex; justify-content: space-between; align-items: baseline; font-family: "DM Mono", monospace; font-size: 10px; color: ${C.mute}; margin-bottom: 5px; }
  .ccg-odds-v { font-size: 15px; font-weight: 700; }
  .ccg-odds-bar { height: 5px; border-radius: 3px; background: rgba(255,255,255,0.06); overflow: hidden; }
  .ccg-odds-bar > div { height: 100%; border-radius: 3px; transition: width 0.3s ease; box-shadow: 0 0 10px ${col}; }
  .ccg-odds-sub { font-family: "DM Mono", monospace; font-size: 8.5px; color: ${C.mute}; margin-top: 5px; opacity: 0.8; }

  .ccg-cta { width: 100%; padding: 13px; border-radius: var(--r-sm); border: 1px solid ${col}; background: ${col}1c; color: ${col}; cursor: pointer; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 15px; letter-spacing: 0.02em; display: flex; align-items: center; justify-content: center; gap: 8px; transition: background 0.15s, box-shadow 0.15s; }
  .ccg-cta:hover:not(:disabled) { background: ${col}30; box-shadow: 0 0 24px ${col}44; }
  .ccg-cta:disabled { opacity: 0.55; cursor: default; }
  .ccg-err { margin-top: 8px; font-family: "DM Sans", sans-serif; font-size: 10.5px; color: ${C.red}; text-align: center; }

  .ccg-vault { margin: 14px 0 12px; border-top: 1px solid rgba(255,255,255,0.06); padding-top: 12px; }
  .ccg-vault-head { display: flex; justify-content: space-between; align-items: baseline; font-family: "DM Mono", monospace; font-size: 10px; color: ${C.cream}; margin-bottom: 9px; }
  .ccg-vault-n { color: ${col}; }
  .ccg-vault-empty { font-family: "DM Sans", sans-serif; font-size: 11px; color: ${C.mute}; text-align: center; padding: 10px 0; opacity: 0.8; }
  .ccg-vault-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }
  .ccg-cry { position: relative; border-radius: var(--r-sm); padding: 7px; background: rgba(8,6,15,0.45); border: 1px solid rgba(255,255,255,0.06); display: flex; flex-direction: column; align-items: center; gap: 5px; }
  .ccg-cry--open { border-color: ${col}55; }
  .ccg-cry-img { width: 100%; height: 62px; object-fit: contain; filter: drop-shadow(0 0 8px ${col}55); animation: ccg-float 4s ease-in-out infinite; }
  .ccg-open { width: 100%; padding: 4px 0; border-radius: var(--r-sm); border: 1px solid ${col}; background: ${col}1c; color: ${col}; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 11px; cursor: pointer; transition: background 0.15s; }
  .ccg-open:hover:not(:disabled) { background: ${col}33; }
  .ccg-open:disabled { opacity: 0.5; cursor: default; }
  .ccg-rar { font-family: "DM Mono", monospace; font-size: 8px; letter-spacing: 0.06em; text-transform: uppercase; padding: 1px 6px; border-radius: var(--r-chip); border: 1px solid; }
  .ccg-cry-id { font-family: "DM Mono", monospace; font-size: 8px; color: ${C.mute}; opacity: 0.7; }
  .ccg-vault-tip { font-family: "DM Sans", sans-serif; font-size: 9px; color: ${C.mute}; opacity: 0.7; margin-top: 9px; text-align: center; }

  .ccg-pity { border-top: 1px solid rgba(255,255,255,0.06); padding-top: 11px; }
  .ccg-pity-top { display: flex; justify-content: space-between; font-family: "DM Mono", monospace; font-size: 9.5px; color: ${C.mute}; margin-bottom: 6px; }
  .ccg-pity-v { color: ${C.amber}; }
  .ccg-pity-pips { display: flex; gap: 3px; }
  .ccg-pip { flex: 1; height: 5px; border-radius: 2px; background: rgba(255,255,255,0.08); transition: background 0.3s; }
  .ccg-foot { font-family: "DM Mono", monospace; font-size: 8px; color: ${C.mute}; opacity: 0.6; margin-top: 10px; line-height: 1.5; text-align: center; }

  .ccg-spin { width: 13px; height: 13px; border-radius: 50%; border: 2px solid ${col}44; border-top-color: ${col}; animation: ccg-rot 0.7s linear infinite; }

  @keyframes ccg-rot { to { transform: rotate(360deg); } }
  @keyframes ccg-float { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-6px); } }
  @keyframes ccg-brew { 0%,100% { transform: translateY(0) rotate(-0.6deg); } 50% { transform: translateY(-3px) rotate(0.6deg); } }
  @keyframes ccg-glowpulse { 0%,100% { opacity: 0.6; } 50% { opacity: 1; } }
  @keyframes ccg-pop { 0% { transform: scale(0.7); } 60% { transform: scale(1.12); } 100% { transform: scale(1); } }
  @keyframes ccg-flash { from { opacity: 1; transform: scale(0.5); } to { opacity: 0; transform: scale(1.4); } }
  @media (prefers-reduced-motion: reduce) {
    .ccg-hero, .ccg-hero--brew, .ccg-glow--hot, .ccg-spin, .ccg-cry-img { animation: none !important; }
  }
`;
