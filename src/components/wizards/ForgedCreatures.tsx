import { useCallback, useEffect, useMemo, useState } from "react";
import { usePublicClient } from "wagmi";
import type { Address } from "viem";
import { useWallet } from "@/hooks/useWallet";
import { CAULDRON } from "@/config/cauldron";
import { fetchNftsFromIndexer } from "@/lib/cauldronOnchain";
import CreatureModal from "@/components/wizards/CreatureModal";
import FrenSprite from "@/components/shared/FrenSprite";
import { frenFromSeed } from "@/data/frens";

/**
 * ForgedCreatures — the iteration-token NFTs the connected wallet forged through
 * VOLUME (the crystal gacha), across every brew. These live in the per-iteration
 * creature collections (not the genesis MiFrens presale).
 *
 * The ownership LIST comes 100% from the Ponder indexer (no on-chain getLogs
 * scan). Only each token's ART is read on-chain, from its tokenURI.
 */

interface Creature {
  collection: Address;
  tokenId: number;
  /** Which iteration forged it — the indexer's /collections supplies this. */
  gen: number;
  rarity: number;
  revealed: boolean;
  image?: string;
  name?: string;
}

const RARITY = ["Common", "Uncommon", "Rare", "Epic", "Legendary"];
const RARITY_COLOR = ["#8A7BAA", "#4FA3E3", "#8B5CF6", "#E0851B", "#d5fd51"];

const TOKENURI_ABI = [
  { type: "function", name: "tokenURI", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "string" }] },
  { type: "function", name: "renderer", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
] as const;

// The GnomeRenderer: `render(id, ultra)` returns the on-chain data-URI art. On r31
// the collection's `tokenURI` → `renderer.tokenURI` REVERTS (a deployed-bytecode
// quirk), but `renderer.render(id, false)` works — so we resolve gnome art through
// render() directly. (r32 repoints via the new upgradable setMetadata.)
const RENDERER_ABI = [
  { type: "function", name: "render", stateMutability: "view", inputs: [{ type: "uint256" }, { type: "bool" }], outputs: [{ type: "string" }] },
] as const;

const ipfs = (u?: string) => (u && u.startsWith("ipfs://") ? u.replace("ipfs://", "https://ipfs.io/ipfs/") : u);

/** Resolve a token's art from its ERC-721 tokenURI. Handles on-chain data-URI
 *  JSON (revealed renderer output) AND hosted JSON metadata (an http/ipfs URI
 *  points at a METADATA document, not an image — we must fetch it and read
 *  `.image`, e.g. the shared sealed-crystal endpoint). */
async function resolveTokenArt(uri: string): Promise<{ image?: string; name?: string }> {
  try {
    if (uri.startsWith("data:application/json;base64,")) {
      const j = JSON.parse(atob(uri.slice("data:application/json;base64,".length)));
      return { image: ipfs(j.image), name: j.name };
    }
    if (uri.startsWith("data:application/json,")) {
      const j = JSON.parse(decodeURIComponent(uri.slice("data:application/json,".length)));
      return { image: ipfs(j.image), name: j.name };
    }
    if (uri.startsWith("http") || uri.startsWith("ipfs")) {
      const meta = await fetch(ipfs(uri) as string, { signal: AbortSignal.timeout(6000) }).then((r) => r.json());
      return { image: ipfs(meta.image), name: meta.name };
    }
  } catch { /* ignore */ }
  return {};
}

export default function ForgedCreatures() {
  const { isConnected, walletAddress } = useWallet();
  const pc = usePublicClient({ chainId: CAULDRON.chainId });
  const [creatures, setCreatures] = useState<Creature[]>([]);
  const [loading, setLoading] = useState(false);
  const [selected, setSelected] = useState<Creature | null>(null);

  const [err, setErr] = useState("");

  const load = useCallback(async () => {
    if (!isConnected || !walletAddress || !pc) { setCreatures([]); return; }
    setLoading(true);
    setErr("");
    // Hard ceiling so the panel can NEVER sit on "Summoning…" forever if the
    // indexer or an art fetch stalls.
    const timeout = new Promise<never>((_, rej) => setTimeout(() => rej(new Error("timeout")), 25_000));
    try {
      // Ownership straight from the Ponder indexer — NO on-chain scan. Volume-
      // forged = the per-iteration creature collections (genesis MiFrens show
      // elsewhere), so we skip the genesis set here.
      const owned = await Promise.race([
        fetchNftsFromIndexer(walletAddress as `0x${string}`, { includeGenesis: false }),
        timeout,
      ]);
      // Liquidatoor badges live in the same collections but show in their own
      // "OnChain Collectibles" section — drop them here.
      const forged = owned.filter((n) => !n.isLiquidatoor).slice(0, 60);

      // Resolve each token's art. Sealed crystals show the crystal directly
      // (their tokenURI is the shared unrevealed metadata); revealed creatures
      // resolve their real on-chain renderer art.
      // Cache the collection's renderer address (one read, reused for all tokens).
      const rendererCache = new Map<string, `0x${string}`>();
      const withArt = await Promise.all(
        forged.map(async (n): Promise<Creature> => {
          if (!n.revealed) return { ...n, image: "/crystal.png", name: `Sealed Crystal #${n.tokenId}` };
          // Resolve gnome art via the renderer's render(id,false) — the collection's
          // tokenURI reverts on r31, but render() works and returns the real art.
          try {
            let r = rendererCache.get(n.collection.toLowerCase());
            if (!r) {
              r = await pc.readContract({ address: n.collection, abi: TOKENURI_ABI, functionName: "renderer" }) as `0x${string}`;
              rendererCache.set(n.collection.toLowerCase(), r);
            }
            if (r && r !== "0x0000000000000000000000000000000000000000") {
              const uri = await pc.readContract({ address: r, abi: RENDERER_ABI, functionName: "render", args: [BigInt(n.tokenId), false] }) as string;
              return { ...n, ...(await resolveTokenArt(uri)) };
            }
            // No renderer (BaseURI collections) → fall back to the collection tokenURI.
            const uri = await pc.readContract({ address: n.collection, abi: TOKENURI_ABI, functionName: "tokenURI", args: [BigInt(n.tokenId)] }) as string;
            return { ...n, ...(await resolveTokenArt(uri)) };
          } catch {
            return { ...n };
          }
        }),
      );
      setCreatures(withArt);
    } catch (e) {
      const m = (e as Error)?.message;
      setErr(
        m === "no-indexer" ? "Indexer isn't configured — set VITE_CAULDRON_INDEXER."
        : m === "timeout" ? "Indexer was slow to respond — tap retry."
        : "Couldn't reach the indexer — tap retry.",
      );
      setCreatures([]);
    } finally {
      setLoading(false);
    }
  }, [isConnected, walletAddress, pc]);

  useEffect(() => { load(); }, [load]);

  // Bucket by iteration, newest first. `fetchNftsFromIndexer` already sorts by
  // gen desc, so this preserves that order and the within-gen rarity sort.
  const byGen = useMemo(() => {
    const m = new Map<number, Creature[]>();
    for (const c of creatures) {
      const g = m.get(c.gen);
      if (g) g.push(c); else m.set(c.gen, [c]);
    }
    return [...m.entries()].sort((a, b) => b[0] - a[0]);
  }, [creatures]);

  if (!isConnected) return null;

  return (
    <section className="fc">
      <style>{`
        .fc { margin: 44px 0 8px; padding-top: 30px; border-top: 1px solid rgba(255,255,255,0.06); }
        .fc__head { display: flex; align-items: baseline; justify-content: space-between; margin-bottom: 16px; flex-wrap: wrap; gap: 8px; }
        .fc__title { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 19px; color: #f5f0e8; margin: 0; display: flex; align-items: center; gap: 10px; }
        .fc__title span { font-family: "DM Mono", monospace; font-size: 11px; font-weight: 700; color: #17112f; background: #d5fd51; border-radius: var(--r-chip); padding: 3px 10px; }
        .fc__sub { font-family: "DM Sans", sans-serif; font-size: 13px; color: #8f83b8; margin: 4px 0 0; max-width: 540px; line-height: 1.5; }
        .fc__gen { margin-top: 18px; }
        .fc__gen:first-of-type { margin-top: 0; }
        .fc__gen-head { display: flex; align-items: baseline; gap: 8px; margin-bottom: 10px; }
        .fc__gen-label { font-family: "DM Mono", monospace; font-size: 10px; letter-spacing: 0.14em;
          text-transform: uppercase; color: #8f83b8; }
        .fc__gen-count { font-family: "DM Mono", monospace; font-size: 10px; color: #d5fd51;
          background: rgba(213,253,81,0.12); border-radius: var(--r-chip); padding: 1px 6px; }
        .fc__grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 14px; }
        .fc__card {
          display: block; width: 100%; padding: 0; text-align: left; cursor: pointer; font: inherit;
          border-radius: var(--r-sm); overflow: hidden; background: rgba(28,20,54,0.6);
          border: 1px solid rgba(255,255,255,0.06);
          transition: transform 0.2s cubic-bezier(.2,.9,.3,1), border-color 0.2s, box-shadow 0.2s;
        }
        .fc__card:hover { transform: translateY(-4px); border-color: rgba(213,253,81,0.4); box-shadow: 0 12px 34px rgba(0,0,0,0.45); }
        .fc__art { position: relative; aspect-ratio: 1; background: rgba(20,14,40,0.5); display: grid; place-items: center; overflow: hidden; }
        .fc__seal { position: absolute; top: 8px; left: 8px; font-family: "DM Mono", monospace; font-size: 8px; letter-spacing: 0.12em; color: #b8adcc; background: rgba(8,6,15,0.6); border: 1px solid rgba(255,255,255,0.12); border-radius: var(--r-chip); padding: 2px 7px; }
        .fc__art img { width: 100%; height: 100%; object-fit: contain; image-rendering: pixelated; }
        .fc__ph { font-size: 28px; color: rgba(245,240,232,0.16); }
        .fc__meta { padding: 9px 11px 11px; }
        .fc__id { font-family: "DM Sans", sans-serif; font-size: 13px; font-weight: 800; color: #f5f0e8; }
        .fc__rar { display: inline-flex; align-items: center; gap: 5px; font-family: "DM Mono", monospace; font-size: 10px; font-weight: 700; margin-top: 4px; letter-spacing: 0.03em; }
        .fc__dot { width: 6px; height: 6px; border-radius: 50%; box-shadow: 0 0 8px currentColor; }
        .fc__empty { padding: 26px; border-radius: var(--r-sm); background: radial-gradient(120% 120% at 50% 0%, rgba(124,92,252,0.08), transparent 60%), rgba(28,20,54,0.4); border: 1px dashed rgba(213,253,81,0.2); font-family: "DM Sans", sans-serif; font-size: 13px; color: #b8adcc; text-align: center; line-height: 1.6; }
        .fc__empty b { color: #d5fd51; }
        .fc__retry { margin-top: 12px; padding: 7px 16px; border-radius: var(--r-sm); background: rgba(213,253,81,0.12); border: 1px solid #d5fd51; color: #d5fd51; font-family: "Fredoka", sans-serif; font-weight: 600; font-size: 12px; cursor: pointer; }
        .fc__retry:hover { background: rgba(213,253,81,0.24); }
      `}</style>

      <div className="fc__head">
        <div>
          <h3 className="fc__title">
            Forged Creatures
            {creatures.length > 0 && <span>{creatures.length}</span>}
          </h3>
          <p className="fc__sub">
            NFTs you forged by <b style={{ color: "#d5fd51" }}>trading volume</b> on the iteration
            tokens — every buy rolls the crystal gacha.
          </p>
        </div>
      </div>

      {loading ? (
        <div className="fc__empty">Summoning your forged creatures…</div>
      ) : err ? (
        <div className="fc__empty">
          {err}<br />
          <button className="fc__retry" onClick={() => load()}>↻ Retry</button>
        </div>
      ) : creatures.length === 0 ? (
        <div className="fc__empty">
          No creatures yet. Head to <b>The Cauldron</b> and buy the live iteration token — every buy
          rolls the gacha for a chance to forge one.
        </div>
      ) : (
        byGen.map(([gen, group]) => (
          <div key={gen} className="fc__gen">
            <div className="fc__gen-head">
              <span className="fc__gen-label">{gen > 0 ? `Iteration #${gen}` : "Unassigned"}</span>
              <span className="fc__gen-count">{group.length}</span>
            </div>
            <div className="fc__grid">
          {group.map((c) => (
            <button key={`${c.collection}-${c.tokenId}`} className="fc__card" onClick={() => setSelected(c)}>
              <div className="fc__art">
                {c.image ? (
                  <img src={c.image} alt={c.name ?? `#${c.tokenId}`} />
                ) : c.revealed ? (
                  // On-chain renderer art missing/reverting → draw the creature
                  // DETERMINISTICALLY from its tokenId (same combo the app uses
                  // everywhere), so a revealed fren always shows its pixel art.
                  (() => { const f = frenFromSeed(c.tokenId); return (
                    <FrenSprite bodyFile={f.bodyFile} faceFile={f.faceFile} itemFile={f.itemFile}
                      bodyIdx={f.bodyIdx} faceIdx={f.faceIdx} itemIdx={f.itemIdx} alt={`#${c.tokenId}`} />
                  ); })()
                ) : <span className="fc__ph">◆</span>}
                {!c.revealed && <span className="fc__seal">SEALED</span>}
              </div>
              <div className="fc__meta">
                <div className="fc__id">#{c.tokenId}</div>
                <div className="fc__rar" style={{ color: RARITY_COLOR[c.rarity] ?? RARITY_COLOR[0] }}>
                  <span className="fc__dot" style={{ background: RARITY_COLOR[c.rarity] ?? RARITY_COLOR[0] }} />
                  {c.revealed ? (RARITY[c.rarity] ?? "Common") : "Tap to open"}
                </div>
              </div>
            </button>
          ))}
            </div>
          </div>
        ))
      )}

      {selected && (
        <CreatureModal
          creature={selected}
          onClose={() => setSelected(null)}
          onChanged={() => { load(); }}
        />
      )}
    </section>
  );
}
