import { useEffect, useState, useMemo } from "react";
import { useSearchParams } from "react-router-dom";
import { formatEther } from "viem";
import { useWallet } from "@/hooks/useWallet";
import { useUserNFTs, type OwnedNFT } from "@/hooks/useUserNFTs";
import { useMiFrensDividend } from "@/hooks/useMiFrensDividend";
import { BODIES, FACES, GNOME_FACES, ELF_FACES, ITEMS, CLASS_ORDER, isGenesisFren } from "@/data/frens";
import { traitSummary } from "@/data/traitResolver";
import FrenSprite from "@/components/shared/FrenSprite";
import FrenDetailModal from "./FrenDetailModal";
import DividendPanel from "./DividendPanel";
import ForgedCreatures from "./ForgedCreatures";
import LiquidatoorBadges from "./LiquidatoorBadges";
import ListModal from "@/components/marketplace/ListModal";
import { useMarketplace } from "@/hooks/useMarketplace";
import { useAppStore } from "@/store/useAppStore";
import { fetchNftsFromIndexer } from "@/lib/cauldronOnchain";
import CollectionFloorPanel from "@/components/cauldron/CollectionFloorPanel";

const FRENS_PATH = "/frens/";

/** The vault's views. Mirrors the MI FRENS sub-items in `layout/navItems.ts`. */
const VAULT_VIEWS = ["frens", "collectibles", "floors"] as const;
type VaultView = (typeof VAULT_VIEWS)[number];

/**
 * How many on-chain collectibles the wallet holds (forged creatures + Liquidatoor
 * badges) — just for the rail's badge. Shares the coalesced indexer request with
 * the two grids that render them, so this costs no extra round-trip.
 */
function useCollectibleCount(): number {
  const { isConnected, walletAddress } = useWallet();
  const [n, setN] = useState(0);
  useEffect(() => {
    if (!isConnected || !walletAddress) { setN(0); return; }
    let alive = true;
    fetchNftsFromIndexer(walletAddress as `0x${string}`, { includeGenesis: false })
      .then((rows) => { if (alive) setN(rows.length); })
      .catch(() => { if (alive) setN(0); });
    return () => { alive = false; };
  }, [isConnected, walletAddress]);
  return n;
}
const PAGE = 48; // cards rendered per chunk (1110 frens → paginate)

const CLASS_NAMES: Record<number, string> = {
  0: "Wizard", 1: "King", 2: "Knight", 3: "Apprentice", 4: "Peasant", 5: "Gnome", 6: "Elf",
};
const RARITY = ["Common", "Rare", "Epic", "Ultra"];
const RARITY_COLOR = ["#8f83b8", "#7c5cfc", "#f5c542", "#d5fd51"];

const GRID_SEEDS = [3, 11, 19, 29, 37, 43, 53, 61, 71];

/** On-chain image with fallback to the local layered sprite. */
function OnChainFrenImage({ nft }: { nft: OwnedNFT }) {
  const [failed, setFailed] = useState(false);
  if (failed || !nft.imageUri) {
    return nft.bodyFile ? (
      <FrenSprite
        bodyFile={nft.bodyFile} faceFile={nft.faceFile} itemFile={nft.itemFile}
        bodyIdx={nft.bodyIdx} faceIdx={nft.faceIdx} itemIdx={nft.itemIdx}
        alt={`MiFren #${nft.tokenId}`}
      />
    ) : null;
  }
  return (
    <img src={nft.imageUri} alt={`MiFren #${nft.tokenId}`} onError={() => setFailed(true)}
      style={{ width: "100%", height: "100%", objectFit: "contain", imageRendering: "pixelated" }} />
  );
}

/** Cycling preview for pending/confirming cards. */
function PendingFrenCycle({ tokenId }: { tokenId: string }) {
  const [tick, setTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setTick((n) => n + 1), 1500);
    return () => clearInterval(id);
  }, []);
  const cells = GRID_SEEDS.map((seed) => {
    const idx = tick + seed;
    const cls = CLASS_ORDER[idx % CLASS_ORDER.length];
    const faces = cls === "Gnome" ? GNOME_FACES : cls === "Elf" ? ELF_FACES : FACES;
    return {
      face: faces[(idx * 5 + 2) % faces.length],
      body: BODIES[cls][(idx * 3) % BODIES[cls].length],
      item: ITEMS[cls][(idx * 11 + 1) % ITEMS[cls].length],
    };
  });
  return (
    <div className="pfc">
      <div className="pfc__grid">
        {cells.map((c, i) => (
          <div key={i} className="pfc__cell" style={{ animationDelay: `${i * 0.1}s` }}>
            <img src={`${FRENS_PATH}${c.face.file}`} alt="" className="pfc__layer" />
            <img src={`${FRENS_PATH}${c.body.file}`} alt="" className="pfc__layer" />
            <img src={`${FRENS_PATH}${c.item.file}`} alt="" className="pfc__layer" />
          </div>
        ))}
      </div>
      <div className="pfc__overlay">
        <span className="pfc__id">#{tokenId}</span>
        <span className="pfc__label">Summoning…</span>
      </div>
    </div>
  );
}

function Stat({ label, value, accent }: { label: string; value: string; accent?: boolean }) {
  return (
    <div className="mif__stat">
      <span className="mif__stat-label">{label}</span>
      <span className="mif__stat-value" style={accent ? { color: "#d5fd51" } : undefined}>{value}</span>
    </div>
  );
}

export default function MyWizards() {
  const { isConnected, walletAddress, openConnectModal } = useWallet();
  const { nfts, loading, error, refresh, count, pendingCount } = useUserNFTs();
  const div = useMiFrensDividend();
  const {
    listNFT, approvalStatus, checkApproval, approveMarketplace,
  } = useMarketplace();
  const [selectedNft, setSelectedNft] = useState<OwnedNFT | null>(null);
  const [listTokenId, setListTokenId] = useState<bigint | null>(null);
  const [visible, setVisible] = useState(PAGE);

  const genesisCount = useMemo(
    () => nfts.filter((n) => !n.isPending && isGenesisFren(n.tokenId)).length,
    [nfts],
  );
  const enchantedCount = div.enchanted.filter(Boolean).length;
  const claimable = Number(formatEther(div.totalPending)).toLocaleString(undefined, { maximumFractionDigits: 4 });

  const shown = nfts.slice(0, visible);

  // The vault is split into three views driven by `?v=` — the left rail owns
  // the switcher, same contract as the Cauldron console.
  const [searchParams] = useSearchParams();
  const rawView = searchParams.get("v");
  const view: VaultView = (VAULT_VIEWS as readonly string[]).includes(rawView ?? "")
    ? (rawView as VaultView)
    : "frens";

  // Publish the counts the rail shows as badges.
  const setMifrensNav = useAppStore((s) => s.setMifrensNav);
  const collectibleCount = useCollectibleCount();
  useEffect(() => {
    setMifrensNav({ frens: count, collectibles: collectibleCount });
  }, [count, collectibleCount, setMifrensNav]);

  return (
    <div className="mif">
      <div className="mif__embers" aria-hidden>
        {Array.from({ length: 10 }).map((_, i) => (
          <span key={i} className="mif__ember" style={{ left: `${(i * 11 + 5) % 100}%`, animationDelay: `${(i * 1.1) % 8}s`, animationDuration: `${8 + (i % 4)}s` }} />
        ))}
      </div>

      {/* ── masthead ── */}
      <header className="mif__top">
        <div className="mif__top-left">
          <span className="mif__eyebrow">The Founding Guild</span>
          <h1 className="mif__title">My MiFrens</h1>
          <p className="mif__sub">
            {!isConnected
              ? "Connect your wallet to open the vault."
              : view === "collectibles"
              ? "Earned, not bought — creatures forged by trading volume and badges struck by your liquidations."
              : view === "floors"
              ? "What every collection is worth on its own — the value its volume and royalties earned, kept forever."
              : "Your genesis relics — each one draws from every iteration's fees, forever."}
          </p>
        </div>
        {isConnected && (
          <div className="mif__top-right">
            <span className="mif__addr">{walletAddress?.slice(0, 6)}…{walletAddress?.slice(-4)}</span>
            <button className="mif__refresh" onClick={refresh} disabled={loading} title="Refresh" aria-label="Refresh">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 12a9 9 0 1 1-2.64-6.36" /><path d="M21 3v6h-6" /></svg>
            </button>
          </div>
        )}
      </header>

      {/* ── stat strip ── */}
      {isConnected && (
        <div className="mif__stats">
          <Stat label="Frens Owned" value={loading && !count ? "…" : `${count}${pendingCount ? ` +${pendingCount}` : ""}`} />
          <Stat label="Genesis" value={String(genesisCount)} accent />
          <Stat label="Enchanted" value={div.ownedGenesis.length ? `${enchantedCount}/${div.ownedGenesis.length}` : "—"} />
          <Stat label="Claimable" value={`${claimable} Ξ`} accent />
        </div>
      )}

      {/* Genesis Redemption Floor moved INTO each fren's detail modal (per-fren
         Recycle + live OG/collection floor) — the batch panel was removed. */}

      {/* ── cast the spell / dividend ── lives in the Frens view because it does
           NOT self-hide: non-genesis holders get an empty-state card, which would
           be a permanent ad if it were pinned above every view. ── */}
      {isConnected && view === "frens" && <DividendPanel div={div} />}

      {error && view === "frens" && (
        <div className="mif__error" role="alert">
          <span>Couldn't load your frens: {error}</span>
          <button className="mif__retry" onClick={refresh}>Retry</button>
        </div>
      )}

      {/* ══ FRENS — the genesis MiFrens collection (OG #1-1111 + volume-minted) ══ */}
      {view === "frens" && (!isConnected ? (
        <div className="mif__empty">
          <div className="mif__sigil" aria-hidden>✦</div>
          <p className="mif__empty-title">The Vault Is Sealed</p>
          <p className="mif__empty-sub">Connect your wallet to reveal your fren collection.</p>
          <button className="mif__cta" onClick={openConnectModal}>Connect Wallet</button>
        </div>
      ) : loading && nfts.length === 0 ? (
        <div className="mif__empty">
          <div className="mif__spinner" />
          <p className="mif__empty-title">Reading the Grimoire</p>
          <p className="mif__empty-sub">Gathering your frens from the chain…</p>
        </div>
      ) : nfts.length === 0 && !loading ? (
        <div className="mif__empty">
          <div className="mif__sigil" aria-hidden>✦</div>
          <p className="mif__empty-title">No Frens Yet</p>
          <p className="mif__empty-sub">Mint a genesis MiFren to join the founding guild.</p>
          <a href="#/" className="mif__cta mif__cta--ghost">Go to Mint</a>
        </div>
      ) : (
        <section className="mif__section">
          <div className="mif__section-head">
            <h2 className="mif__section-title">Your Collection</h2>
            <span className="mif__section-count">{count} fren{count !== 1 ? "s" : ""}</span>
          </div>

          <div className="mif__grid">
            {shown.map((nft, i) => {
              const genesis = !nft.isPending && isGenesisFren(nft.tokenId);
              const rar = nft.rarity ?? 0;
              return (
                <button
                  key={`${nft.isPending ? "pending-" : ""}${nft.tokenId.toString()}`}
                  className={`mif__card${nft.isPending ? " mif__card--pending" : ""}`}
                  style={{ animationDelay: `${Math.min(i, 24) * 0.03}s` }}
                  onClick={() => !nft.isPending && setSelectedNft(nft)}
                  disabled={nft.isPending}
                >
                  <div className="mif__art">
                    <div className="mif__art-fill">
                      {nft.isPending ? (
                        <PendingFrenCycle tokenId={nft.tokenId.toString()} />
                      ) : (nft.imageUri || nft.bodyFile) ? (
                        <OnChainFrenImage nft={nft} />
                      ) : (
                        <div className="mif__art-ph">#{nft.tokenId.toString()}</div>
                      )}
                    </div>

                    {genesis && (
                      <span className="mif__badge mif__badge--genesis" title="Genesis Founder — earns from every iteration">◆ GENESIS</span>
                    )}
                    {nft.isPending && <span className="mif__badge mif__badge--pending">PENDING</span>}
                    {!nft.isPending && (
                      <span className="mif__view">View<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12h14M13 6l6 6-6 6" /></svg></span>
                    )}
                  </div>

                  <div className="mif__info">
                    <div className="mif__info-top">
                      <span className="mif__id">#{nft.tokenId.toString()}</span>
                      <span className="mif__class">{nft.isPending ? "Unconfirmed" : (CLASS_NAMES[nft.classIdx] ?? "—")}</span>
                    </div>
                    <div className="mif__info-bot">
                      <span className="mif__traits">
                        {nft.isPending ? "Waiting for confirmation" : traitSummary(nft.classIdx, nft.bodyIdx, nft.faceIdx, nft.itemIdx)}
                      </span>
                      {!nft.isPending && (
                        <span className="mif__rarity" style={{ color: RARITY_COLOR[rar] }} title={`${RARITY[rar]} rarity`}>
                          <i style={{ background: RARITY_COLOR[rar] }} />{RARITY[rar]}
                        </span>
                      )}
                    </div>
                  </div>
                </button>
              );
            })}
          </div>

          {visible < nfts.length && (
            <div className="mif__more">
              <button className="mif__more-btn" onClick={() => setVisible((v) => v + PAGE)}>
                Load more <em>({nfts.length - visible} left)</em>
              </button>
            </div>
          )}
        </section>
      ))}

      {/* ══ COLLECTIBLES — receipts of real on-chain events ══ */}
      {view === "collectibles" && isConnected && (
        <section className="mif__oc">
          <div className="mif__oc-head">
            <span className="mif__eyebrow">Receipts of On-Chain Events</span>
            <h2 className="mif__oc-title">OnChain Collectibles</h2>
            <p className="mif__oc-sub">
              NFTs minted by what you actually <em>did</em> on-chain — creatures forged from the
              <b> trading volume</b> that grows the collection, and <b>Liquidatoor</b> badges struck when
              your buy or sell <b>liquidated a leveraged position</b> on the hook. Not bought — earned.
            </p>
          </div>
          <ForgedCreatures />
          <LiquidatoorBadges />
        </section>
      )}

      {/* ══ FLOORS — the Collection Legacy Floor. Moved off the Cauldron, where it
             rendered ABOVE the tab switch and so appeared on three unrelated
             views. It belongs with the NFTs whose value it backs. ══ */}
      {view === "floors" && isConnected && (
        <section className="mif__oc">
          <div className="mif__oc-head">
            <span className="mif__eyebrow">Value your collection keeps, forever</span>
            <h2 className="mif__oc-title">Collection Floors</h2>
            <p className="mif__oc-sub">
              Every collection keeps the value its own <b>volume + royalties</b> earned. Trading fees
              market-buy the live token to back the live collection's floor; at death it crystallizes
              into a <b>per-NFT floor</b> that moons with the machine.
            </p>
          </div>
          <CollectionFloorPanel />
        </section>
      )}

      {/* Both new views need the same locked-vault prompt the fren grid has. */}
      {view !== "frens" && !isConnected && (
        <div className="mif__empty">
          <div className="mif__sigil" aria-hidden>✦</div>
          <p className="mif__empty-title">The Vault Is Sealed</p>
          <p className="mif__empty-sub">Connect your wallet to open it.</p>
          <button className="mif__cta" onClick={openConnectModal}>Connect Wallet</button>
        </div>
      )}

      <FrenDetailModal
        nft={selectedNft}
        onClose={() => setSelectedNft(null)}
        onListForSale={(tokenId) => { setSelectedNft(null); setListTokenId(tokenId); }}
      />
      <ListModal
        open={listTokenId !== null}
        tokenId={listTokenId}
        approvalStatus={approvalStatus}
        onClose={() => setListTokenId(null)}
        onCheckApproval={checkApproval}
        onApprove={approveMarketplace}
        onConfirm={listNFT}
      />

      <style>{css}</style>
    </div>
  );
}

const css = `
  .mif {
    position: relative;
    /* The shell owns the horizontal gutter (it has to clear the left rail). */
    padding: 32px 0 96px;
    min-height: 100vh;
    overflow: visible;
    color: #f5f0e8;
    font-family: "DM Sans", sans-serif;
    background:
      radial-gradient(1100px 620px at 50% -8%, rgba(213,253,81,0.06), transparent 60%),
      radial-gradient(900px 700px at 80% 20%, rgba(124,92,252,0.10), transparent 55%),
      #0E0A1A;
  }
  /* Atmosphere. Film grain lives on the shell (.shell__grain) so it covers
     the rail too; only the embers are page-local. */
  .mif__embers { position: fixed; inset: 0; pointer-events: none; z-index: 0; overflow: hidden; }
  .mif__ember { position: absolute; bottom: -10px; width: 3px; height: 3px; border-radius: 50%;
    background: #d5fd51; opacity: 0; filter: blur(0.5px);
    animation-name: mif-rise; animation-iteration-count: infinite; animation-timing-function: ease-out; }
  @keyframes mif-rise { 0% { transform: translateY(0) scale(1); opacity: 0; } 12% { opacity: 0.6; } 100% { transform: translateY(-80vh) scale(0.3); opacity: 0; } }
  .mif > *:not(.mif__embers) { position: relative; z-index: 1; max-width: 1240px; margin-left: auto; margin-right: auto; }

  /* masthead */
  .mif__top { display: flex; align-items: flex-end; justify-content: space-between; gap: 24px; flex-wrap: wrap; margin-bottom: 30px; }
  .mif__eyebrow { font-family: "DM Mono", monospace; font-size: 10.5px; letter-spacing: 0.22em; text-transform: uppercase; color: #7c5cfc; }
  .mif__title { font-family: "Cinzel Decorative", serif; font-weight: 900; font-size: clamp(34px, 6vw, 52px); line-height: 1; color: #f5f0e8; margin: 8px 0 10px;
    text-shadow: 0 0 40px rgba(213,253,81,0.12); }
  .mif__sub { font-size: 14px; color: #b8adcc; max-width: 52ch; line-height: 1.5; }
  .mif__top-right { display: flex; align-items: center; gap: 10px; }
  .mif__addr { font-family: "DM Mono", monospace; font-size: 12px; color: #b8adcc; padding: 8px 14px; border-radius: var(--r-md);
    background: rgba(28,20,54,0.6); border: 1px solid rgba(213,253,81,0.14); }
  .mif__refresh { width: 36px; height: 36px; display: grid; place-items: center; border-radius: var(--r-sm); cursor: pointer; color: #8f83b8;
    background: rgba(28,20,54,0.6); border: 1px solid rgba(213,253,81,0.14); transition: all .2s; }
  .mif__refresh:hover:not(:disabled) { color: #d5fd51; border-color: rgba(213,253,81,0.4); transform: rotate(-90deg); }
  .mif__refresh:disabled { opacity: 0.4; cursor: default; }

  /* stat strip */
  .mif__stats { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 22px; }
  .mif__stat { padding: 16px 18px; border-radius: var(--r-sm); display: flex; flex-direction: column; gap: 5px;
    background: rgba(28,20,54,0.55); border: 1px solid rgba(255,255,255,0.05); }
  .mif__stat-label { font-family: "DM Mono", monospace; font-size: 10px; letter-spacing: 0.14em; text-transform: uppercase; color: #8f83b8; }
  .mif__stat-value { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 24px; line-height: 1; color: #f5f0e8; }

  /* error */
  .mif__error { display: flex; align-items: center; justify-content: space-between; gap: 14px; flex-wrap: wrap;
    padding: 13px 18px; margin-bottom: 20px; border-radius: var(--r-sm); font-size: 13px; color: #ff4d6d;
    background: rgba(255,77,109,0.06); border: 1px solid rgba(255,77,109,0.22); }
  .mif__retry { padding: 7px 16px; border-radius: var(--r-md); font: 600 11px/1 "DM Mono", monospace; letter-spacing: 0.06em; cursor: pointer;
    color: #ff4d6d; background: transparent; border: 1px solid #ff4d6d; }
  .mif__retry:hover { background: #ff4d6d; color: #17112f; }

  /* empty / loading */
  .mif__empty { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 12px; text-align: center;
    min-height: 340px; padding: 48px; border-radius: var(--r-md);
    background: radial-gradient(120% 120% at 50% 0%, rgba(124,92,252,0.08), transparent 60%), rgba(28,20,54,0.4);
    border: 1px dashed rgba(213,253,81,0.2); }
  .mif__sigil { font-size: 40px; color: #7c5cfc; opacity: 0.7; text-shadow: 0 0 24px rgba(124,92,252,0.5); }
  .mif__empty-title { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 20px; color: #f5f0e8; letter-spacing: 0.03em; }
  .mif__empty-sub { font-size: 13.5px; color: #b8adcc; max-width: 34ch; line-height: 1.6; }
  .mif__spinner { width: 30px; height: 30px; border: 3px solid rgba(213,253,81,0.15); border-top-color: #d5fd51; border-radius: 50%; animation: mif-spin .8s linear infinite; }
  @keyframes mif-spin { to { transform: rotate(360deg); } }
  .mif__cta { margin-top: 10px; padding: 13px 30px; border-radius: var(--r-md); font: 700 13px/1 "DM Sans", sans-serif; letter-spacing: 0.03em; cursor: pointer; text-decoration: none;
    color: #17112f; background: #d5fd51; border: none; box-shadow: 0 6px 0 #a9cc2f; transition: transform .15s, box-shadow .15s; }
  .mif__cta:hover { transform: translateY(-2px); box-shadow: 0 8px 0 #a9cc2f; }
  .mif__cta--ghost { color: #d5fd51; background: transparent; border: 1px solid rgba(213,253,81,0.5); box-shadow: none; }
  .mif__cta--ghost:hover { background: rgba(213,253,81,0.08); box-shadow: none; }

  /* OnChain Collectibles wrapper */
  .mif__oc { margin-top: 44px; padding-top: 30px; border-top: 1px solid rgba(255,255,255,0.06); }
  .mif__oc-head { margin-bottom: 8px; }
  .mif__oc-title { font-family: "Cinzel Decorative", serif; font-weight: 800; font-size: clamp(22px, 4vw, 30px); color: #f5f0e8; margin: 6px 0 8px;
    text-shadow: 0 0 30px rgba(213,253,81,0.1); }
  .mif__oc-sub { font-family: "DM Sans", sans-serif; font-size: 13.5px; color: #b8adcc; max-width: 62ch; line-height: 1.6; margin: 0 0 6px; }
  .mif__oc-sub b { color: #d5fd51; font-weight: 700; }
  .mif__oc-sub em { color: #f5f0e8; font-style: italic; }

  /* section */
  .mif__section { margin-top: 26px; }
  .mif__section-head { display: flex; align-items: baseline; gap: 12px; margin-bottom: 18px; padding-bottom: 12px; border-bottom: 1px solid rgba(255,255,255,0.06); }
  .mif__section-title { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 19px; color: #f5f0e8; }
  .mif__section-count { font-family: "DM Mono", monospace; font-size: 12px; color: #8f83b8; }

  /* grid + cards */
  .mif__grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); gap: 16px; }
  .mif__card { text-align: left; padding: 0; overflow: hidden; border-radius: var(--r-md); cursor: pointer;
    background: rgba(28,20,54,0.6); border: 1px solid rgba(255,255,255,0.06);
    transition: transform .22s cubic-bezier(.2,.9,.3,1), border-color .22s, box-shadow .22s;
    animation: mif-card-in .5s both cubic-bezier(.2,.9,.3,1); }
  @keyframes mif-card-in { from { opacity: 0; transform: translateY(14px); } to { opacity: 1; transform: translateY(0); } }
  .mif__card:hover { transform: translateY(-5px); border-color: rgba(213,253,81,0.45); box-shadow: 0 14px 40px rgba(0,0,0,0.45), 0 0 0 1px rgba(213,253,81,0.15); }
  .mif__card:focus-visible { outline: 2px solid #7c5cfc; outline-offset: 3px; }
  .mif__card:disabled { cursor: default; }

  .mif__art { position: relative; aspect-ratio: 1; overflow: hidden; }
  .mif__art-fill { position: absolute; inset: 0; }
  .mif__art-fill > * { width: 100%; height: 100%; }
  .mif__art-ph { display: grid; place-items: center; width: 100%; height: 100%; font-family: "Cinzel Decorative", serif; font-size: 26px; color: rgba(245,240,232,0.14); }

  .mif__badge { position: absolute; top: 9px; padding: 4px 9px; border-radius: var(--r-md); font: 700 9px/1 "DM Mono", monospace; letter-spacing: 0.1em; }
  .mif__badge--genesis { left: 9px; color: #17112f; background: linear-gradient(90deg, #d5fd51, #f5c542); box-shadow: 0 2px 12px rgba(213,253,81,0.5); }
  .mif__badge--pending { right: 9px; color: #17112f; background: #f5c542; }

  .mif__view { position: absolute; bottom: 9px; right: 9px; display: inline-flex; align-items: center; gap: 4px;
    padding: 5px 11px; border-radius: var(--r-md); font: 700 10px/1 "DM Mono", monospace; letter-spacing: 0.06em;
    color: #17112f; background: #d5fd51; opacity: 0; transform: translateY(6px); transition: opacity .2s, transform .2s; }
  .mif__card:hover .mif__view { opacity: 1; transform: translateY(0); }

  .mif__info { padding: 12px 13px 13px; display: flex; flex-direction: column; gap: 7px; }
  .mif__info-top { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
  .mif__id { font-family: "DM Sans", sans-serif; font-weight: 800; font-size: 14px; color: #f5f0e8; }
  .mif__class { font: 600 9.5px/1 "DM Mono", monospace; letter-spacing: 0.06em; text-transform: uppercase; color: #b8adcc;
    padding: 4px 8px; border-radius: var(--r-md); border: 1px solid rgba(255,255,255,0.1); }
  .mif__info-bot { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
  .mif__traits { font-size: 11px; color: #8f83b8; line-height: 1.35; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; flex: 1; }
  .mif__rarity { display: inline-flex; align-items: center; gap: 5px; font: 700 9.5px/1 "DM Mono", monospace; letter-spacing: 0.04em; flex-shrink: 0; }
  .mif__rarity i { width: 6px; height: 6px; border-radius: 50%; box-shadow: 0 0 8px currentColor; }

  .mif__card--pending { border-color: rgba(245,197,66,0.3); animation: mif-pend 2.4s ease-in-out infinite; }
  @keyframes mif-pend { 0%,100% { border-color: rgba(245,197,66,0.18); } 50% { border-color: rgba(245,197,66,0.5); } }

  .mif__more { display: flex; justify-content: center; margin-top: 28px; }
  .mif__more-btn { padding: 12px 26px; border-radius: var(--r-md); cursor: pointer; font: 700 13px/1 "DM Sans", sans-serif;
    color: #f5f0e8; background: rgba(28,20,54,0.7); border: 1px solid rgba(213,253,81,0.3); transition: all .2s; }
  .mif__more-btn em { font-style: normal; color: #8f83b8; font-weight: 500; }
  .mif__more-btn:hover { border-color: #d5fd51; color: #d5fd51; }

  /* pending cycle */
  .pfc { position: relative; width: 100%; height: 100%; overflow: hidden; background: rgba(20,14,40,0.6); }
  .pfc__grid { position: absolute; inset: 0; display: grid; grid-template-columns: repeat(3, 1fr); grid-template-rows: repeat(3, 1fr); gap: 2px; padding: 4px; }
  .pfc__cell { position: relative; image-rendering: pixelated; opacity: 0.1; filter: saturate(0.4) hue-rotate(40deg); animation: pfc-flick 0.9s ease-in-out infinite alternate; }
  @keyframes pfc-flick { 0% { opacity: 0.05; } 100% { opacity: 0.14; } }
  .pfc__layer { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: contain; image-rendering: pixelated; }
  .pfc__overlay { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 6px; z-index: 2;
    background: radial-gradient(ellipse 70% 60% at 50% 50%, rgba(20,14,40,0.55) 0%, transparent 100%); }
  .pfc__id { font-family: "Cinzel Decorative", serif; font-weight: 700; font-size: 26px; color: rgba(245,240,232,0.25); }
  .pfc__label { font: 600 10px/1 "DM Mono", monospace; letter-spacing: 0.1em; color: #d5fd51; animation: pfc-pulse 2s ease-in-out infinite; }
  @keyframes pfc-pulse { 0%,100% { opacity: 0.5; } 50% { opacity: 1; } }

  @media (max-width: 720px) {
    .mif__stats { grid-template-columns: repeat(2, 1fr); }
    .mif__grid { grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 12px; }
  }
  @media (prefers-reduced-motion: reduce) {
    .mif__card, .mif__ember, .mif__card--pending, .pfc__cell, .pfc__label, .mif__spinner { animation: none !important; }
    .mif__card:hover { transform: none; }
  }
`;
