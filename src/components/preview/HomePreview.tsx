import { useEffect, useMemo, useState, useRef, useCallback } from "react";
import { useWallet } from "@/hooks/useWallet";
import { useXAuth } from "@/hooks/useXAuth";
import { BODIES, FACES, GNOME_FACES, ELF_FACES, ITEMS, CLASS_ORDER, type TraitLayer } from "@/data/frens";
import EasterEggModal from "@/components/home/EasterEggModal";
import ManifrenstoModal from "@/components/preview/ManifrenstoModal";
import PresaleModal from "@/components/presale/PresaleModal";
import { PRESALE } from "@/config/presale";
import { useMiFrensPresale } from "@/hooks/useMiFrensPresale";
import cauldronImg from "@/assets/images/mif/cauldron.webp";


const FRENS_PATH = "/frens/";

/* ── Scroll-reveal hook (IntersectionObserver) ── */
function useScrollReveal() {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const root = ref.current;
    if (!root) return;

    const els = root.querySelectorAll<HTMLElement>("[data-reveal]");
    if (!els.length) return;

    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            const el = entry.target as HTMLElement;
            const delay = el.dataset.revealDelay ?? "0";
            el.style.transitionDelay = `${delay}ms`;
            el.classList.add("revealed");
            io.unobserve(el);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -40px 0px" },
    );

    els.forEach((el) => io.observe(el));
    return () => io.disconnect();
  }, []);

  return ref;
}


/* ── Arrow-in-circle button (Pudgy Penguins style) ── */
function ArrowBtn({ href, label, dark = false }: { href?: string; label: string; dark?: boolean }) {
  const inner = (
    <>
      <span>{label}</span>
      <span className={`pp__arrow-circle ${dark ? "pp__arrow-circle--dark" : ""}`}>
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
          <path d="M3 8H13M13 8L9 4M13 8L9 12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      </span>
    </>
  );
  if (href) return <a href={href} target="_blank" rel="noopener noreferrer" className={`pp__arrow-btn ${dark ? "pp__arrow-btn--dark" : ""}`}>{inner}</a>;
  return <button className={`pp__arrow-btn ${dark ? "pp__arrow-btn--dark" : ""}`}>{inner}</button>;
}

/* ── FAQ Accordion ── */
function FAQItem({ q, a }: { q: string; a: string }) {
  const [open, setOpen] = useState(false);
  return (
    <div className={`pp__faq-item ${open ? "pp__faq-item--open" : ""}`}>
      <button className="pp__faq-q" onClick={() => setOpen(!open)}>
        <span>{q}</span>
        <span className="pp__faq-arrow">{open ? "\u2212" : "+"}</span>
      </button>
      <div className="pp__faq-a" style={{ maxHeight: open ? "500px" : "0px" }}>
        <p>{a}</p>
      </div>
    </div>
  );
}

function HomePreview() {
  const { isConnected, openConnectModal } = useWallet();
  const { xUser, connectX, disconnectX } = useXAuth();

  // Live genesis-fundraise stats for the card (the real Cauldron presale, not
  // the legacy peg NFT above).
  const genesis = useMiFrensPresale();
  const gMinted = genesis.minted ?? 0;
  const gLoading = genesis.minted === undefined;
  const gRemaining = Math.max(0, genesis.maxSupply - gMinted);
  const gProgress = genesis.maxSupply > 0 ? (gMinted / genesis.maxSupply) * 100 : 0;
  const gSoldOut = genesis.soldOut;

  const [showPresale, setShowPresale] = useState(false);
  const [hatLifted, setHatLifted] = useState(false);
  const [eggHover, setEggHover] = useState(false);
  const [showEggModal, setShowEggModal] = useState(false);
  const [showManifrensto, setShowManifrensto] = useState(false);
  const revealRef = useScrollReveal();


  /* ── Hero crew — ALL 7 classes ── */
  const CREW_CLASSES: (keyof typeof BODIES)[] = [
    "Elf", "Peasant", "Apprentice", "Wizard", "King", "Knight", "Gnome"
  ];
  const [crew, setCrew] = useState(() =>
    CREW_CLASSES.map((cls) => ({ face: 0, body: 0, item: 0, cls })),
  );

  useEffect(() => {
    const id = setInterval(() => {
      if (frenEditor) return; // pause randomization in edit mode
      setCrew((prev) =>
        prev.map(({ cls }) => {
          const faces = cls === "Gnome" ? GNOME_FACES : cls === "Elf" ? ELF_FACES : FACES;
          return {
            face: Math.floor(Math.random() * faces.length),
            body: Math.floor(Math.random() * BODIES[cls].length),
            item: Math.floor(Math.random() * ITEMS[cls].length),
            cls,
          };
        }),
      );
    }, 600);
    return () => clearInterval(id);
  }, []);

  /* ── FREN EDITOR MODE ── drag, resize, flip frens visually ── */
  const [frenEditor, setFrenEditor] = useState(false);
  const [frenState, setFrenState] = useState(() =>
    Array.from({ length: 7 }, (_, i) => ({
      x: 0,       // offset from default position
      y: 0,
      size: 0,    // delta from base CSS size
      flipped: false,
    })),
  );
  const dragRef = useRef<{ idx: number; startX: number; startY: number; origX: number; origY: number } | null>(null);
  const lineupRef = useRef<HTMLDivElement>(null);

  const handleFrenMouseDown = useCallback((e: React.MouseEvent, idx: number) => {
    if (!frenEditor) return;
    e.preventDefault();
    dragRef.current = { idx, startX: e.clientX, startY: e.clientY, origX: frenState[idx].x, origY: frenState[idx].y };
    const onMove = (ev: MouseEvent) => {
      if (!dragRef.current) return;
      const dx = ev.clientX - dragRef.current.startX;
      const dy = ev.clientY - dragRef.current.startY;
      setFrenState((prev) => prev.map((f, i) => i === dragRef.current!.idx ? { ...f, x: dragRef.current!.origX + dx, y: dragRef.current!.origY + dy } : f));
    };
    const onUp = () => { dragRef.current = null; window.removeEventListener("mousemove", onMove); window.removeEventListener("mouseup", onUp); };
    window.addEventListener("mousemove", onMove);
    window.addEventListener("mouseup", onUp);
  }, [frenEditor, frenState]);

  const handleFrenWheel = useCallback((e: React.WheelEvent, idx: number) => {
    if (!frenEditor) return;
    e.preventDefault();
    const delta = e.deltaY > 0 ? -10 : 10;
    setFrenState((prev) => prev.map((f, i) => i === idx ? { ...f, size: f.size + delta } : f));
  }, [frenEditor]);

  const handleFrenFlip = useCallback((idx: number) => {
    if (!frenEditor) return;
    setFrenState((prev) => prev.map((f, i) => i === idx ? { ...f, flipped: !f.flipped } : f));
  }, [frenEditor]);

  // Base sizes from CSS (must match)
  const BASE_SIZES = [340, 380, 420, 470, 420, 380, 340];

  const editorCSS = useMemo(() => {
    if (!frenEditor) return "";
    return frenState.map((f, i) => {
      const sz = BASE_SIZES[i] + f.size;
      const side = i < 3 ? "right" : i > 3 ? "left" : "";
      const flipStr = f.flipped ? " transform: scaleX(-1);" : "";
      const marginStr = side ? ` margin-${side}: ${side === "right" ? f.x - 185 - (i === 1 ? 10 : i === 2 ? 15 : 0) : f.x - 185 - (i === 5 ? 10 : i === 4 ? 15 : 0)}px;` : "";
      return `.pp__lineup-fren--${i} { width: ${sz}px; height: ${sz}px;${flipStr} }`;
    }).join("\n  ");
  }, [frenEditor, frenState]);

  /* ── Collection grid — 8 combos ── */
  /* ── Marquee rows ── */
  const frensMarquee = useMemo(() => {
    const primes = [7, 11, 13, 17, 19];
    const offsets = [0, 5, 3, 9, 6];
    const rows: { body: TraitLayer; face: TraitLayer; item: TraitLayer; id: number; cls: string }[][] = [];
    for (let r = 0; r < 20; r++) {
      const row: typeof rows[0] = [];
      for (let i = 0; i < 14; i++) {
        const seed = r * 14 + i;
        const cls = CLASS_ORDER[(seed * primes[r % 5]) % CLASS_ORDER.length];
        const bodies = BODIES[cls];
        const items = ITEMS[cls];
        const faces = cls === "Gnome" ? GNOME_FACES : cls === "Elf" ? ELF_FACES : FACES;
        row.push({
          body: bodies[(seed * primes[(r + 1) % 5] + offsets[r % 5]) % bodies.length],
          face: faces[(seed * primes[(r + 2) % 5] + offsets[(r + 1) % 5]) % faces.length],
          item: items[(seed * primes[(r + 3) % 5] + offsets[(r + 2) % 5]) % items.length],
          id: seed, cls,
        });
      }
      rows.push(row);
    }
    return rows;
  }, []);

  /* ── Featured cards for the two-column section ── */
  const featuredFren = useMemo(() => {
    const cls = "Wizard";
    return {
      body: BODIES[cls][0],
      face: FACES[0],
      item: ITEMS[cls][0],
    };
  }, []);

  /* ── Magical sparkles (floating stars, wisps, runes) ── */
  const sparkles = useMemo(() =>
    Array.from({ length: 28 }, (_, i) => ({
      id: i,
      left: `${Math.random() * 100}%`,
      delay: `${Math.random() * 10}s`,
      duration: `${8 + Math.random() * 12}s`,
      size: 6 + Math.random() * 14,
      kind: i % 3, // 0 = 4-point star, 1 = glowing orb, 2 = sparkle cross
      drift: (Math.random() - 0.5) * 60, // horizontal sway in px
    })), []);

  /* ── Fast random combo cycler for "Become a Fren" ── */
  const randomCombo = useCallback(() => {
    const cls = CLASS_ORDER[Math.floor(Math.random() * CLASS_ORDER.length)];
    const faces = cls === "Gnome" ? GNOME_FACES : cls === "Elf" ? ELF_FACES : FACES;
    return {
      face: faces[Math.floor(Math.random() * faces.length)].file,
      body: BODIES[cls][Math.floor(Math.random() * BODIES[cls].length)].file,
      item: ITEMS[cls][Math.floor(Math.random() * ITEMS[cls].length)].file,
    };
  }, []);

  const [combo, setCombo] = useState(() => randomCombo());
  useEffect(() => {
    const id = setInterval(() => setCombo(randomCombo()), 180);
    return () => clearInterval(id);
  }, [randomCombo]);

  // Easter egg console hint
  useEffect(() => {
    console.log("%c\u{1F9D9} The runes are etched in the bones of the manifesto...", "color: #d5fd51; font-size: 14px;");
  }, []);


  const tweetText = encodeURIComponent(
    `\u{1F9D9}\u200D\u2642\uFE0F Magic Internet Frens \u2014 minting on Robinhood\n\n2222 on-chain wizards. No bridges. Pure magic.\n\n@magic0xfrens \u00B7 mifrens.xyz\n\n`
  );
  const tweetUrl = `https://x.com/compose/post?text=${tweetText}`;

  return (
    <div className="pp" ref={revealRef}>
      {/* ── EASTER EGG MODAL ── */}
      <EasterEggModal
        open={showEggModal}
        onClose={() => setShowEggModal(false)}
      />

      {/* ── MANIFRENSTO PARCHMENT MODAL ── */}
      <ManifrenstoModal
        open={showManifrensto}
        onClose={() => setShowManifrensto(false)}
        onSpread={() => window.open(tweetUrl, "_blank")}
      />

      {/* ── PRESALE MODAL (shared genesis mint) ── */}
      <PresaleModal isOpen={showPresale} onClose={() => setShowPresale(false)} />

      {/* ══════ 2. HERO — Sky gradient + huge title + 7 characters ══════ */}
      <section className="pp__hero">
        {/* Magical sparkles */}
        <div className="pp__sparkles-field">
          {sparkles.map((s) => (
            <div
              key={s.id}
              className={`pp__sparkle-float pp__sparkle-float--${s.kind}`}
              style={{
                left: s.left,
                animationDelay: s.delay,
                animationDuration: s.duration,
                ['--drift' as string]: `${s.drift}px`,
              }}
            >
              {s.kind === 0 ? (
                <svg width={s.size} height={s.size} viewBox="0 0 24 24" fill="none">
                  <path d="M12 0L14.59 9.41L24 12L14.59 14.59L12 24L9.41 14.59L0 12L9.41 9.41L12 0Z" fill="currentColor" />
                </svg>
              ) : s.kind === 1 ? (
                <span className="pp__wisp" style={{ width: s.size, height: s.size }} />
              ) : (
                <svg width={s.size} height={s.size} viewBox="0 0 16 16" fill="none">
                  <path d="M8 0V16M0 8H16M2.34 2.34L13.66 13.66M13.66 2.34L2.34 13.66" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
                </svg>
              )}
            </div>
          ))}
        </div>

        {/* Big bold title */}
        <h1 className="pp__hero-title">
          <span className="pp__hero-title-line1">Magic Internet</span>
          <span className="pp__hero-title-line2">Frens</span>
        </h1>

        <p className="pp__hero-sub">
          2222 magic internet frens, fully on-chain on Robinhood
        </p>

        {/* Editor toggle */}
        {frenEditor && (
          <div className="pp__editor-panel">
            <strong>FREN EDITOR</strong>
            <span style={{fontSize:11,opacity:0.7}}>Drag=move &middot; Scroll=resize &middot; DblClick=flip</span>
            <div className="pp__editor-values">
              {frenState.map((f, i) => {
                const sz = BASE_SIZES[i] + f.size;
                return <div key={i} style={{fontSize:11,fontFamily:"monospace"}}>{CREW_CLASSES[i]}: {sz}px x:{f.x} y:{f.y}{f.flipped ? " FLIP":""}</div>;
              })}
            </div>
            <button className="pp__editor-copy" onClick={() => {
              const css = frenState.map((f, i) => {
                const sz = BASE_SIZES[i] + f.size;
                const flip = f.flipped ? " transform: scaleX(-1);" : "";
                return `  .pp__lineup-fren--${i} { width: ${sz}px; height: ${sz}px;${flip} /* x:${f.x} y:${f.y} */ }`;
              }).join("\n");
              const lineup = `  .pp__lineup { margin-bottom: ${-70 + frenState[3].y}px; }`;
              navigator.clipboard.writeText(lineup + "\n" + css);
              alert("CSS copied to clipboard!");
            }}>Copy CSS</button>
            <button className="pp__editor-copy" onClick={() => setFrenState(Array.from({length:7}, () => ({x:0,y:0,size:0,flipped:false})))}>Reset</button>
            <button className="pp__editor-copy" style={{background:"#ff4d6d"}} onClick={() => setFrenEditor(false)}>Close Editor</button>
          </div>
        )}

        {/* 7-character lineup */}
        <div className="pp__lineup" ref={lineupRef}>
          {crew.map((w, i) => {
            const faces = w.cls === "Gnome" ? GNOME_FACES : w.cls === "Elf" ? ELF_FACES : FACES;
            const f = frenState[i];
            const editorStyle = frenEditor ? {
              transform: `translate(${f.x}px, ${f.y}px)${f.flipped ? " scaleX(-1)" : ""}`,
              width: BASE_SIZES[i] + f.size,
              height: BASE_SIZES[i] + f.size,
              cursor: "grab",
              outline: "2px dashed rgba(247,147,26,0.6)",
              zIndex: 10 + i,
            } : undefined;
            return (
              <div
                key={i}
                className={`pp__lineup-fren pp__lineup-fren--${i}`}
                style={editorStyle}
                onMouseDown={(e) => handleFrenMouseDown(e, i)}
                onWheel={(e) => handleFrenWheel(e, i)}
                onDoubleClick={() => handleFrenFlip(i)}
              >
                <img src={`${FRENS_PATH}${faces[w.face].file}`} alt="" className="pp__lineup-layer" />
                <img src={`${FRENS_PATH}${BODIES[w.cls][w.body].file}`} alt="" className="pp__lineup-layer" />
                <img src={`${FRENS_PATH}${ITEMS[w.cls][w.item].file}`} alt="" className="pp__lineup-layer" />

              </div>
            );
          })}
        </div>

        {/* ══════ TICKER BAR — inside hero at bottom ══════ */}
        <div className="pp__ticker">
          <div className="pp__ticker-track">
            {Array.from({ length: 16 }).map((_, i) => {
              const cls = CLASS_ORDER[i % CLASS_ORDER.length];
              const faces = cls === "Gnome" ? GNOME_FACES : cls === "Elf" ? ELF_FACES : FACES;
              return (
                <span key={i} className="pp__ticker-item">
                  <span className="pp__ticker-fren">
                    <img src={`${FRENS_PATH}${faces[(i * 3) % faces.length].file}`} alt="" className="pp__ticker-fren-layer" />
                    <img src={`${FRENS_PATH}${BODIES[cls][(i * 2) % BODIES[cls].length].file}`} alt="" className="pp__ticker-fren-layer" />
                    <img src={`${FRENS_PATH}${ITEMS[cls][i % ITEMS[cls].length].file}`} alt="" className="pp__ticker-fren-layer" />
                  </span>
                  ON ROBINHOOD &middot; MINTING SOON &middot; 2222 MAGIC INTERNET FRENS &middot;&nbsp;
                </span>
              );
            })}
          </div>
        </div>
      </section>

      {/* ══════ 3. CORAL ABOUT SECTION ══════ */}
      <section className="pp__about" data-reveal="fade-up">
        <div className="pp__about-inner">
          <div className="pp__about-left">
            <h2 className="pp__about-title" data-reveal="fade-up" data-reveal-delay="0">
              <span className="pp__about-title-line1">Mi</span><span className="pp__about-title-line2">Frens</span>
            </h2>
            <p className="pp__about-text" data-reveal="fade-up" data-reveal-delay="100">
              gm fren. welcome to the realm of Magic Internet Frens &mdash; a band of 2222 pixel wizards,
              knights, gnomes and degens summoned fully on-chain on Robinhood. 1111 genesis frens,
              the rest forged by trading volume. pure on-chain magic. every fren is inscribed forever. wagmi.
            </p>

            <div className="pp__about-stats" data-reveal="fade-up" data-reveal-delay="200">
              <div className="pp__about-stat">
                <span className="pp__about-stat-value">2222</span>
                <span className="pp__about-stat-label">SUPPLY</span>
              </div>
              <div className="pp__about-stat-divider" />
              <div className="pp__about-stat">
                <span className="pp__about-stat-value">7</span>
                <span className="pp__about-stat-label">CLASSES</span>
              </div>
              <div className="pp__about-stat-divider" />
              <div className="pp__about-stat">
                <span className="pp__about-stat-value">100%</span>
                <span className="pp__about-stat-label">ON-CHAIN</span>
              </div>
            </div>
            <p className="pp__about-sub">Fixed supply. No inflation. Ever. All art lives fully on-chain.</p>

            <div className="pp__about-bottom-row">
              <div className="pp__about-contract">
                <span className="pp__about-contract-label">CONTRACT</span>
                <button
                  className="pp__about-contract-addr"
                  onClick={() => { navigator.clipboard?.writeText("opt1sqr9qrx9l6gkezpeaq424cd2ar5s0aejlayvd38eu"); }}
                  title="Copy contract address"
                >
                  opt1sqr9...vd38eu
                </button>
              </div>
              {/* Deployed on Robinhood */}
            </div>
          </div>
          <div className="pp__about-right">
            <img src="/images/wizard-cooking.png" alt="Wizard Fren cooking" className="pp__about-img" />
          </div>
        </div>
      </section>

      {/* ══════ MINT / CONNECT SECTION ══════ */}
      <section className="pp__claim" data-reveal="fade-up">
        <div className="pp__claim-card">
          <div className="pp__claim-left">
            <div className="pp__claim-cycle">
              <div className="pp__claim-cycle-fren">
                <img src={`${FRENS_PATH}${combo.face}`} alt="" className="pp__claim-cycle-layer" />
                <img src={`${FRENS_PATH}${combo.body}`} alt="" className="pp__claim-cycle-layer" />
                <img src={`${FRENS_PATH}${combo.item}`} alt="" className="pp__claim-cycle-layer" />
              </div>
            </div>
          </div>
          <div className="pp__claim-right">
            <h3 className="pp__claim-heading">Mint a Fren</h3>
            <p className="pp__claim-desc">
              A unique, <strong>fully on-chain</strong> pixel-art MiFren &mdash; and a seat in the
              founding guild. Your mint seeds the treasury that launches iteration #1
              and votes on every future brew.
            </p>
            <div className="pp__claim-bonus">
              <span className="pp__claim-bonus-tag">GENESIS PERKS</span>
              <p>
                Airdrop of iteration #1's token + a share of all future hook fees &amp; royalties.
                The airdrop is a <strong>bonus, not a promise</strong> &mdash; you're here for the art.
              </p>
            </div>
            <div className="pp__claim-stats">
              <div className="pp__claim-stat">
                <span className="pp__claim-stat-label">Minted</span>
                <span className="pp__claim-stat-value">{gLoading ? "\u2014" : gMinted} / {genesis.maxSupply}</span>
              </div>
              <div className="pp__claim-progress-bar">
                <div className="pp__claim-progress-fill" style={{ width: `${Math.max(gProgress, 1)}%` }} />
              </div>
              <div className="pp__claim-stat">
                <span className="pp__claim-stat-label">Price</span>
                <span className="pp__claim-stat-value">{PRESALE.priceEth} ETH</span>
              </div>
              <div className="pp__claim-stat">
                <span className="pp__claim-stat-label">Remaining</span>
                <span className="pp__claim-stat-value pp__claim-stat-value--hl">{gLoading ? "\u2014" : gRemaining}</span>
              </div>
            </div>
            <button
              className={`pp__btn pp__btn--wide ${genesis.finalized ? "pp__btn--live" : "pp__btn--primary"}`}
              onClick={() => {
                if (genesis.finalized) { window.location.hash = "#/cauldrons"; return; }
                setShowPresale(true);
              }}
            >
              {genesis.finalized
                ? <>🔥 Iteration #1 is live &mdash; enter the Cauldron <span className="pp__btn-arrow">→</span></>
                : gSoldOut
                ? "🚀 Launch iteration #1"
                : "Mint a Fren"}
            </button>
          </div>
        </div>
      </section>

      {/* ══════ 4. SECONDARY HERO — "THE CAULDRON" (like Lil Pudgys) ══════ */}
      <section className="pp__cauldron-section" id="cauldron" data-reveal="fade-up">
        {/* Rolling frens background — same as the FAQ, softly cut out by a blurred
            central circle so the title, copy and cauldron read cleanly while the
            frens keep drifting seamlessly around the edges. */}
        <div className="pp__cauldron-frens" aria-hidden="true">
          {frensMarquee.map((row, ri) => (
            <div
              key={`cbg-${ri}`}
              className="pp__marquee-row"
              style={{
                animationDirection: ri % 2 === 0 ? "normal" : "reverse",
                animationDuration: `${45 + ri * 8}s`,
              }}
            >
              {[...row, ...row].map((f, fi) => (
                <div key={fi} className="pp__marquee-fren">
                  <img src={`${FRENS_PATH}${f.face.file}`} alt="" className="pp__marquee-layer" loading="lazy" />
                  <img src={`${FRENS_PATH}${f.body.file}`} alt="" className="pp__marquee-layer" loading="lazy" />
                  <img src={`${FRENS_PATH}${f.item.file}`} alt="" className="pp__marquee-layer" loading="lazy" />
                </div>
              ))}
            </div>
          ))}
        </div>
        <h2 className="pp__cauldron-title" data-reveal="fade-up">THE CAULDRON</h2>
        <p className="pp__cauldron-sub" data-reveal="fade-up" data-reveal-delay="100">
          Once all 1111 genesis frens are minted, they summon an ERC-20 token through the Cauldron &mdash;
          liquidity is seeded from the mint treasury and trading begins. If trading volume drops
          for a week, the token dies. Holders claim their proportional share of
          the liquidity pool, then vote on the next token to summon. A new token launches,
          and the cycle repeats &mdash; eternally.
        </p>

        {/* Sticker cycle orbiting the cauldron */}
        <div className="pp__orbit" data-reveal="fade-up" data-reveal-delay="200">
          {/* Curved arrows between phases */}
          {/* TRADE→DEATH */}
          <svg className="pp__orbit-arrow pp__orbit-arrow--0" viewBox="0 0 2400 2979" xmlns="http://www.w3.org/2000/svg">
            <path d="M799.66 2634.57 c-58.97 -55.60 -94.66 -101.38 -128.02 -164.74 -44.48 -84.31 -73.71 -199.91 -88.97 -351.72 -5.69 -57.16 -6.47 -251.64 -1.29 -302.59 8.02 -78.88 18.62 -140.17 38.02 -217.76 32.59 -130.34 78.62 -234.05 151.55 -340.86 52.76 -77.33 118.19 -148.71 229.91 -251.12 29.48 -27.16 155.69 -138.88 178.97 -158.79 l12.41 -10.34 -60.26 0 c-50.17 0 -62.59 -0.78 -75.26 -4.66 -28.45 -8.79 -52.24 -39.57 -70.34 -92.07 -11.38 -32.84 -21.72 -77.84 -21.72 -94.91 l0 -13.19 35.69 -1.55 c86.38 -4.14 217.76 -19.91 391.03 -46.29 118.97 -18.36 120.78 -18.62 171.98 -18.62 45.26 0 54.31 0.78 72.41 5.69 33.62 9.31 46.55 17.07 60 35.17 24.57 33.36 50.69 96.98 58.71 143.79 4.91 28.19 8.02 74.48 5.69 86.38 -1.03 4.91 -12.93 27.41 -26.64 49.91 -41.12 67.50 -46.81 77.59 -76.29 130.09 -93.10 166.55 -193.45 403.45 -246.47 582.67 -5.17 17.33 -9.83 33.10 -10.60 34.91 -0.52 1.81 -4.91 3.10 -10.34 3.10 -8.28 0 -11.12 -2.07 -24.05 -15.78 -58.19 -63.10 -91.81 -141.21 -97.50 -226.03 -3.62 -55.34 10.34 -122.84 55.60 -268.97 6.98 -22.76 12.67 -41.64 12.16 -41.90 -1.03 -1.29 -66.47 47.59 -88.19 65.95 -93.10 78.36 -185.43 185.43 -263.02 304.40 -109.91 168.62 -175.60 339.31 -198.88 516.47 -8.02 60.26 -9.57 176.12 -3.62 244.91 10.09 119.48 37.76 242.84 78.62 354.57 8.79 23.28 15.78 46.81 15.78 51.72 0 8.79 -0.78 9.57 -19.40 18.88 -29.22 14.48 -35.95 13.71 -57.67 -6.72z" fill="#E8DCC8"/>
          </svg>
          {/* DEATH→CLAIM */}
          <svg className="pp__orbit-arrow pp__orbit-arrow--1" viewBox="0 0 2400 2979" xmlns="http://www.w3.org/2000/svg">
            <path d="M799.66 2634.57 c-58.97 -55.60 -94.66 -101.38 -128.02 -164.74 -44.48 -84.31 -73.71 -199.91 -88.97 -351.72 -5.69 -57.16 -6.47 -251.64 -1.29 -302.59 8.02 -78.88 18.62 -140.17 38.02 -217.76 32.59 -130.34 78.62 -234.05 151.55 -340.86 52.76 -77.33 118.19 -148.71 229.91 -251.12 29.48 -27.16 155.69 -138.88 178.97 -158.79 l12.41 -10.34 -60.26 0 c-50.17 0 -62.59 -0.78 -75.26 -4.66 -28.45 -8.79 -52.24 -39.57 -70.34 -92.07 -11.38 -32.84 -21.72 -77.84 -21.72 -94.91 l0 -13.19 35.69 -1.55 c86.38 -4.14 217.76 -19.91 391.03 -46.29 118.97 -18.36 120.78 -18.62 171.98 -18.62 45.26 0 54.31 0.78 72.41 5.69 33.62 9.31 46.55 17.07 60 35.17 24.57 33.36 50.69 96.98 58.71 143.79 4.91 28.19 8.02 74.48 5.69 86.38 -1.03 4.91 -12.93 27.41 -26.64 49.91 -41.12 67.50 -46.81 77.59 -76.29 130.09 -93.10 166.55 -193.45 403.45 -246.47 582.67 -5.17 17.33 -9.83 33.10 -10.60 34.91 -0.52 1.81 -4.91 3.10 -10.34 3.10 -8.28 0 -11.12 -2.07 -24.05 -15.78 -58.19 -63.10 -91.81 -141.21 -97.50 -226.03 -3.62 -55.34 10.34 -122.84 55.60 -268.97 6.98 -22.76 12.67 -41.64 12.16 -41.90 -1.03 -1.29 -66.47 47.59 -88.19 65.95 -93.10 78.36 -185.43 185.43 -263.02 304.40 -109.91 168.62 -175.60 339.31 -198.88 516.47 -8.02 60.26 -9.57 176.12 -3.62 244.91 10.09 119.48 37.76 242.84 78.62 354.57 8.79 23.28 15.78 46.81 15.78 51.72 0 8.79 -0.78 9.57 -19.40 18.88 -29.22 14.48 -35.95 13.71 -57.67 -6.72z" fill="#E8DCC8"/>
          </svg>
          {/* CLAIM→VOTE */}
          <svg className="pp__orbit-arrow pp__orbit-arrow--2" viewBox="0 0 2400 2979" xmlns="http://www.w3.org/2000/svg">
            <path d="M799.66 2634.57 c-58.97 -55.60 -94.66 -101.38 -128.02 -164.74 -44.48 -84.31 -73.71 -199.91 -88.97 -351.72 -5.69 -57.16 -6.47 -251.64 -1.29 -302.59 8.02 -78.88 18.62 -140.17 38.02 -217.76 32.59 -130.34 78.62 -234.05 151.55 -340.86 52.76 -77.33 118.19 -148.71 229.91 -251.12 29.48 -27.16 155.69 -138.88 178.97 -158.79 l12.41 -10.34 -60.26 0 c-50.17 0 -62.59 -0.78 -75.26 -4.66 -28.45 -8.79 -52.24 -39.57 -70.34 -92.07 -11.38 -32.84 -21.72 -77.84 -21.72 -94.91 l0 -13.19 35.69 -1.55 c86.38 -4.14 217.76 -19.91 391.03 -46.29 118.97 -18.36 120.78 -18.62 171.98 -18.62 45.26 0 54.31 0.78 72.41 5.69 33.62 9.31 46.55 17.07 60 35.17 24.57 33.36 50.69 96.98 58.71 143.79 4.91 28.19 8.02 74.48 5.69 86.38 -1.03 4.91 -12.93 27.41 -26.64 49.91 -41.12 67.50 -46.81 77.59 -76.29 130.09 -93.10 166.55 -193.45 403.45 -246.47 582.67 -5.17 17.33 -9.83 33.10 -10.60 34.91 -0.52 1.81 -4.91 3.10 -10.34 3.10 -8.28 0 -11.12 -2.07 -24.05 -15.78 -58.19 -63.10 -91.81 -141.21 -97.50 -226.03 -3.62 -55.34 10.34 -122.84 55.60 -268.97 6.98 -22.76 12.67 -41.64 12.16 -41.90 -1.03 -1.29 -66.47 47.59 -88.19 65.95 -93.10 78.36 -185.43 185.43 -263.02 304.40 -109.91 168.62 -175.60 339.31 -198.88 516.47 -8.02 60.26 -9.57 176.12 -3.62 244.91 10.09 119.48 37.76 242.84 78.62 354.57 8.79 23.28 15.78 46.81 15.78 51.72 0 8.79 -0.78 9.57 -19.40 18.88 -29.22 14.48 -35.95 13.71 -57.67 -6.72z" fill="#E8DCC8"/>
          </svg>
          {/* VOTE→RELAUNCH */}
          <svg className="pp__orbit-arrow pp__orbit-arrow--3" viewBox="0 0 2400 2979" xmlns="http://www.w3.org/2000/svg">
            <path d="M799.66 2634.57 c-58.97 -55.60 -94.66 -101.38 -128.02 -164.74 -44.48 -84.31 -73.71 -199.91 -88.97 -351.72 -5.69 -57.16 -6.47 -251.64 -1.29 -302.59 8.02 -78.88 18.62 -140.17 38.02 -217.76 32.59 -130.34 78.62 -234.05 151.55 -340.86 52.76 -77.33 118.19 -148.71 229.91 -251.12 29.48 -27.16 155.69 -138.88 178.97 -158.79 l12.41 -10.34 -60.26 0 c-50.17 0 -62.59 -0.78 -75.26 -4.66 -28.45 -8.79 -52.24 -39.57 -70.34 -92.07 -11.38 -32.84 -21.72 -77.84 -21.72 -94.91 l0 -13.19 35.69 -1.55 c86.38 -4.14 217.76 -19.91 391.03 -46.29 118.97 -18.36 120.78 -18.62 171.98 -18.62 45.26 0 54.31 0.78 72.41 5.69 33.62 9.31 46.55 17.07 60 35.17 24.57 33.36 50.69 96.98 58.71 143.79 4.91 28.19 8.02 74.48 5.69 86.38 -1.03 4.91 -12.93 27.41 -26.64 49.91 -41.12 67.50 -46.81 77.59 -76.29 130.09 -93.10 166.55 -193.45 403.45 -246.47 582.67 -5.17 17.33 -9.83 33.10 -10.60 34.91 -0.52 1.81 -4.91 3.10 -10.34 3.10 -8.28 0 -11.12 -2.07 -24.05 -15.78 -58.19 -63.10 -91.81 -141.21 -97.50 -226.03 -3.62 -55.34 10.34 -122.84 55.60 -268.97 6.98 -22.76 12.67 -41.64 12.16 -41.90 -1.03 -1.29 -66.47 47.59 -88.19 65.95 -93.10 78.36 -185.43 185.43 -263.02 304.40 -109.91 168.62 -175.60 339.31 -198.88 516.47 -8.02 60.26 -9.57 176.12 -3.62 244.91 10.09 119.48 37.76 242.84 78.62 354.57 8.79 23.28 15.78 46.81 15.78 51.72 0 8.79 -0.78 9.57 -19.40 18.88 -29.22 14.48 -35.95 13.71 -57.67 -6.72z" fill="#E8DCC8"/>
          </svg>
          {/* RELAUNCH→TRADE */}
          <svg className="pp__orbit-arrow pp__orbit-arrow--4" viewBox="0 0 2400 2979" xmlns="http://www.w3.org/2000/svg">
            <path d="M799.66 2634.57 c-58.97 -55.60 -94.66 -101.38 -128.02 -164.74 -44.48 -84.31 -73.71 -199.91 -88.97 -351.72 -5.69 -57.16 -6.47 -251.64 -1.29 -302.59 8.02 -78.88 18.62 -140.17 38.02 -217.76 32.59 -130.34 78.62 -234.05 151.55 -340.86 52.76 -77.33 118.19 -148.71 229.91 -251.12 29.48 -27.16 155.69 -138.88 178.97 -158.79 l12.41 -10.34 -60.26 0 c-50.17 0 -62.59 -0.78 -75.26 -4.66 -28.45 -8.79 -52.24 -39.57 -70.34 -92.07 -11.38 -32.84 -21.72 -77.84 -21.72 -94.91 l0 -13.19 35.69 -1.55 c86.38 -4.14 217.76 -19.91 391.03 -46.29 118.97 -18.36 120.78 -18.62 171.98 -18.62 45.26 0 54.31 0.78 72.41 5.69 33.62 9.31 46.55 17.07 60 35.17 24.57 33.36 50.69 96.98 58.71 143.79 4.91 28.19 8.02 74.48 5.69 86.38 -1.03 4.91 -12.93 27.41 -26.64 49.91 -41.12 67.50 -46.81 77.59 -76.29 130.09 -93.10 166.55 -193.45 403.45 -246.47 582.67 -5.17 17.33 -9.83 33.10 -10.60 34.91 -0.52 1.81 -4.91 3.10 -10.34 3.10 -8.28 0 -11.12 -2.07 -24.05 -15.78 -58.19 -63.10 -91.81 -141.21 -97.50 -226.03 -3.62 -55.34 10.34 -122.84 55.60 -268.97 6.98 -22.76 12.67 -41.64 12.16 -41.90 -1.03 -1.29 -66.47 47.59 -88.19 65.95 -93.10 78.36 -185.43 185.43 -263.02 304.40 -109.91 168.62 -175.60 339.31 -198.88 516.47 -8.02 60.26 -9.57 176.12 -3.62 244.91 10.09 119.48 37.76 242.84 78.62 354.57 8.79 23.28 15.78 46.81 15.78 51.72 0 8.79 -0.78 9.57 -19.40 18.88 -29.22 14.48 -35.95 13.71 -57.67 -6.72z" fill="#E8DCC8"/>
          </svg>

          {/* Big cauldron in center */}
          <div className="pp__orbit-center">
            <img src="/images/wizard-cauldron.png" alt="The Cauldron" className="pp__orbit-cauldron" />
          </div>

          {/* Sticker nodes — pentagon positions */}
          {[
            { img: '/stickers/trade.png',    label: 'TRADE',    desc: 'Buy & sell',        pos: 0 },
            { img: '/stickers/death.png',     label: 'DEATH',    desc: 'Volume dies',       pos: 1 },
            { img: '/stickers/claim.png',     label: 'CLAIM',    desc: 'Get your share',    pos: 2 },
            { img: '/stickers/vote.png',      label: 'VOTE',     desc: 'Choose next token', pos: 3 },
            { img: '/stickers/relaunch.png',  label: 'RELAUNCH', desc: 'New cycle begins',  pos: 4 },
          ].map((step) => (
            <div className={`pp__orbit-node pp__orbit-node--${step.pos}`} key={step.label}>
              <img src={step.img} alt={step.label} className="pp__orbit-sticker" />
              <span className="pp__orbit-label">{step.label}</span>
              <span className="pp__orbit-desc">{step.desc}</span>
            </div>
          ))}
        </div>
      </section>

      {/* ══════ 5. TWO-COLUMN FEATURE CARDS ══════ */}
      <section className="pp__features" data-reveal="fade-up">
        <div className="pp__features-grid">
          {/* Card 1: Marketplace — tan/cream */}
          <div className="pp__feature-card pp__feature-card--cream" data-reveal="fade-up" data-reveal-delay="0">
            <div className="pp__feature-content">
              <span className="pp__feature-tag">MARKETPLACE</span>
              <h3 className="pp__feature-heading">Trade frens<br/>peer-to-peer</h3>
              <p className="pp__feature-desc">
                Buy and sell frens directly on Robinhood Chain. No middlemen, no bridges &mdash;
                just trustless swaps between wallets. Browse listings or put yours up for sale.
              </p>
              <ArrowBtn label="BROWSE" href="#/marketplace" />
            </div>
            <div className="pp__feature-art">
              <img src="/images/wizard-market.png" alt="Wizard Market" className="pp__feature-mascot" />
            </div>
          </div>

          {/* Card 2: Governance — lavender */}
          <div className="pp__feature-card pp__feature-card--pink" data-reveal="fade-up" data-reveal-delay="150">
            <div className="pp__feature-content">
              <span className="pp__feature-tag">FREN POWER</span>
              <h3 className="pp__feature-heading">You decide<br/>what lives</h3>
              <p className="pp__feature-desc">
                Each fren is a vote. When a token dies, holders choose the next creature
                to summon from the Cauldron. Genesis frens earn a share of every iteration's
                trading fees, forever.
              </p>
              <ArrowBtn label="LEARN MORE" href="#cauldron" />
            </div>
            <div className="pp__feature-art">
              <img src="/images/wizard-wine.png" alt="Wizard Fren" className="pp__feature-mascot pp__feature-mascot--sm" />
            </div>
          </div>
        </div>
      </section>

      {/* ══════ 6. SCROLLING TEXT MARQUEE (Pudgy style between sections) ══════ */}
      <div className="pp__text-marquee">
        <div className="pp__text-marquee-track">
          {Array.from({ length: 10 }).map((_, i) => (
            <span key={i} className="pp__text-marquee-item">
              MAGIC INTERNET FRENS &middot; ON ROBINHOOD &middot; 2222 SUPPLY &middot; ON-CHAIN FOREVER &middot; THE CAULDRON &middot; ETERNAL CYCLE &middot;&nbsp;
            </span>
          ))}
        </div>
      </div>

      {/* ══════ LINED-BG WRAPPER: media + kindness + FAQ ══════ */}
      <div className="pp__lined-wrap">
        <div className="pp__lined-bg">
          {frensMarquee.map((row, ri) => (
            <div
              key={`bg-${ri}`}
              className="pp__marquee-row"
              style={{
                animationDirection: ri % 2 === 0 ? "normal" : "reverse",
                animationDuration: `${45 + ri * 8}s`,
              }}
            >
              {[...row, ...row].map((f, fi) => (
                <div key={fi} className="pp__marquee-fren">
                  <img src={`${FRENS_PATH}${f.face.file}`} alt="" className="pp__marquee-layer" loading="lazy" />
                  <img src={`${FRENS_PATH}${f.body.file}`} alt="" className="pp__marquee-layer" loading="lazy" />
                  <img src={`${FRENS_PATH}${f.item.file}`} alt="" className="pp__marquee-layer" loading="lazy" />
                </div>
              ))}
            </div>
          ))}
        </div>

      {/* ══════ 8. SIDE-BY-SIDE MEDIA CARDS (Pudgy Media / Discord style) ══════ */}
      <section className="pp__media-section" data-reveal="fade-up">
        <div className="pp__media-grid">
          <div className="pp__media-card pp__media-card--cream" data-reveal="fade-up" data-reveal-delay="0">
            <div className="pp__media-card-content">
              <span className="pp__media-tag">COMMUNITY</span>
              <h3 className="pp__media-heading">Fren Hub</h3>
              <p className="pp__media-desc">
                Join the community of magic internet frens. Share memes, discuss strategy,
                and vote on the next creature to summon from the Cauldron.
              </p>
              <ArrowBtn label="JOIN" href="https://x.com/magic0xfrens" />
            </div>
            <div className="pp__media-card-deco">
              <img src="/images/wizard-staff.png" alt="Wizard Fren" className="pp__media-mascot" />
            </div>
          </div>
          <div className="pp__media-card pp__media-card--white" data-reveal="fade-up" data-reveal-delay="150">
            <div className="pp__media-card-content">
              <span className="pp__media-tag">FOLLOW</span>
              <h3 className="pp__media-heading">Fren Updates</h3>
              <p className="pp__media-desc">
                Follow us on X for the latest news, announcements, and sneak peeks
                at upcoming features and events.
              </p>
              <ArrowBtn label="FOLLOW" href="https://x.com/magic0xfrens" />
            </div>
            <div className="pp__media-card-deco">
              <img src="/images/wizard-scythe.png" alt="Wizard Fren" className="pp__media-mascot" />
            </div>
          </div>
        </div>
      </section>

      {/* ══════ 9. BIG FEATURED CARD — "FREN KINDNESS" (like Pengu Kindness) ══════ */}
      <section className="pp__kindness" data-reveal="fade-up" data-rune="f7e7">
        <div className="pp__kindness-card" data-reveal="fade-up">
          <div className="pp__kindness-content">
            <h2 className="pp__kindness-title">The Magic<br/>MANIFRENSTO</h2>
            <p className="pp__kindness-desc">
              Countless moons have passed and the art of wizardry has faded from the minds
              of many. The blockchain grew cold, and the magic was forgotten.
              We wish to reignite the spark. We will build the Fren Village.
            </p>
            <button
              className="pp__btn pp__btn--kindness"
              onClick={() => setShowManifrensto(true)}
            >
              SPREAD THE MAGIC
            </button>
          </div>
          <div className="pp__kindness-art">
            <div className="pp__egg-scene">
              <img
                src={!hatLifted ? "/images/wizard-scroll.png" : eggHover ? "/images/wizard-scroll-egghover.png" : "/images/wizard-scroll-hatlifted.png"}
                alt="Wizard reading scroll"
                className={`pp__kindness-mascot${hatLifted ? " pp__kindness-mascot--lifted" : ""}`}
              />
              {/* Invisible hat click zone */}
              {!hatLifted && (
                <div
                  className="pp__hat-clickzone"
                  onClick={() => setHatLifted(true)}
                  role="button"
                  tabIndex={-1}
                  aria-label="Lift the hat"
                />
              )}
              {/* Egg click zone — egg is already in the hatlifted image */}
              {hatLifted && (
                <div
                  className="pp__egg-clickzone"
                  onClick={() => setShowEggModal(true)}
                  onMouseEnter={() => setEggHover(true)}
                  onMouseLeave={() => setEggHover(false)}
                  role="button"
                  tabIndex={0}
                  aria-label="Open the magic egg"
                />
              )}
            </div>
          </div>
        </div>
      </section>


      {/* ══════ 14. FAQ ══════ */}
      <section className="pp__faq-section" data-reveal="fade-up">
        <div className="pp__faq-content">
          <h2 className="pp__faq-title" data-reveal="fade-up">FAQ</h2>
          <div className="pp__faq" data-reveal="fade-up" data-reveal-delay="100">
          <FAQItem
            q="What are Magic Internet Frens?"
            a="2222 unique pixel-art NFTs deployed fully on-chain on Robinhood — 1111 genesis frens minted at launch, the other 1111 forged through trading volume in the Cauldron. Each fren is composed of layered traits (class, body, face, equipment) stored fully on-chain. 7 classes: Wizard, King, Knight, Apprentice, Peasant, Gnome, and Elf."
          />
          <FAQItem
            q="How does minting work?"
            a="Connect your Web3 wallet (MetaMask, Rabby, etc.), pay the mint price in ETH, and a random fren is minted to your address. Your fren's class and traits are assigned on-chain at confirmation."
          />
          <FAQItem
            q="What is the Eternal Cycle?"
            a="After all 1111 genesis frens are minted, holders summon an ERC-20 token via the Cauldron. When trading volume drops for a week, the token dies. Holders claim their share, vote on a new token, and the cycle repeats eternally."
          />
          <FAQItem
            q="What benefits do holders get?"
            a="A perpetual share of every iteration's trading fees (the genesis dividend), governance voting rights to choose new summoned tokens, and full protocol access. Only 2222 frens will ever exist (1111 genesis + 1111 volume-forged)."
          />
          </div>
        </div>
      </section>
      </div>{/* end pp__lined-wrap */}

      {/* ══════ 15. DARK FOOTER (Pudgy dark navy footer) ══════ */}
      <footer className="pp__footer">
        {/* Footer marquee */}
        <div className="pp__footer-marquee">
          <div className="pp__footer-marquee-track">
            {Array.from({ length: 10 }).map((_, i) => (
              <span key={i} className="pp__footer-marquee-item">
                MAGIC INTERNET FRENS &middot; ON ROBINHOOD &middot; 2222 SUPPLY &middot; ON-CHAIN FOREVER &middot;&nbsp;
              </span>
            ))}
          </div>
        </div>

        <div className="pp__footer-inner">
          {/* Footer links grid (Pudgy style) */}
          <div className="pp__footer-grid">
            <div className="pp__footer-col">
              <h4 className="pp__footer-col-title">EXPLORE</h4>
              <a href="#" className="pp__footer-link">The Collection</a>
              <a href="#cauldron" className="pp__footer-link">The Cauldron</a>
              <a href="#" className="pp__footer-link">The Ritual</a>
              <a href="#" className="pp__footer-link">FAQ</a>
            </div>
            <div className="pp__footer-col">
              <h4 className="pp__footer-col-title">COMMUNITY</h4>
              <a href="https://x.com/magic0xfrens" target="_blank" rel="noopener noreferrer" className="pp__footer-link">Follow on X</a>
              <a href={tweetUrl} target="_blank" rel="noopener noreferrer" className="pp__footer-link">Spread the Magic</a>
            </div>
            <div className="pp__footer-col">
              <h4 className="pp__footer-col-title">BUILD</h4>
              <a href="https://ethereum.org" target="_blank" rel="noopener noreferrer" className="pp__footer-link">Ethereum</a>
              <a href="#" className="pp__footer-link">Documentation</a>
            </div>
          </div>

          {/* Social icons row */}
          <div className="pp__footer-socials">
            <a href="https://x.com/magic0xfrens" target="_blank" rel="noopener noreferrer" className="pp__footer-social">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>
            </a>
            {xUser ? (
              <div className="pp__footer-xuser">
                {xUser.profile_image_url && <img src={xUser.profile_image_url} alt="" className="pp__footer-avatar" />}
                <span>@{xUser.username}</span>
                <button className="pp__footer-disconnect" onClick={disconnectX}>disconnect</button>
              </div>
            ) : (
              <button className="pp__btn pp__btn--footer" onClick={connectX}>CONNECT WITH X</button>
            )}
          </div>

          {/* Mascot + copyright */}
          <div className="pp__footer-bottom">
            <div className="pp__footer-mascot">
              <img src="/mifrens-logo.svg" alt="MiFrens" className="pp__footer-guild" />
            </div>
            <p className="pp__footer-copy">Magic Internet Frens &middot; On-Chain NFT &middot; 2025-2026</p>
            <p className="pp__footer-legal">All rights reserved. Fully on-chain, on Robinhood.</p>
            <div className="pp__footer-robinhood">
              <span className="pp__footer-robinhood-label">Powered by</span>
              <img src="/robinhood-feather.svg" alt="Robinhood" className="pp__footer-robinhood-logo" />
              <span>Robinhood</span>
            </div>
          </div>
        </div>
      </footer>

      <style>{styles}</style>
    </div>
  );
}

export default HomePreview;

/* ═══════════════════════════════════════════════════════════════
 * PUDGY PENGUINS INSPIRED DESIGN — Wizard / Bitcoin themed
 *
 * Design patterns from Pudgy Penguins site:
 * - Different colored background per section
 * - Very bold condensed white titles with dark text-stroke
 * - Rounded cards with thick borders
 * - Arrow-in-circle CTA buttons
 * - Character decorations in every section
 * - Scrolling text marquees (top + footer)
 * - Two-column colored feature cards
 * - Two-panel claim/connect card
 * - Dark navy footer with links grid + social icons + mascot
 *
 * Palette (Refined Arcane — one lime accent, unified purples, gold warmth):
 *   Enchanted Cream: #F5F0E8 (warm off-white base + text on dark)
 *   Parchment:       #FBF7F0 (lightest bg for cards/panels)
 *   Robinhood Lime:  #d5fd51 (THE accent — CTAs, glows, highlights)
 *   Amber Glow:      #F0D8A0 (kindness/manifesto card)
 *   Ancient Parchment:#EDE0C8 (feature card warm)
 *   Wizard Purple:   #2A1F54 (dark section bgs + text + borders — ONE purple)
 *   Warm Gold:       #f6c86a (about-section warmth / rarity)
 *   Violet Accent:   #7c5cfc (secondary accent, nebula glows)
 *   Muted Purple:    #8a7baa (secondary text on light)
 *   Hero:            twilight void→purple (dark magic, warms as it falls)
 *
 * Fonts:
 *   Display: "Fredoka" (bubbly rounded)
 *   Body:    "DM Sans" (clean modern)
 * ═══════════════════════════════════════════════════════════════ */

const styles = `
  .pp {
    position: relative;
    background: #F5F0E8;
    color: #2A1F54;
    font-family: "DM Sans", "Inter", sans-serif;
    overflow-x: hidden;
  }

  /* Skip rendering the below-the-fold sections until they're near the viewport
     — the browser reserves their space (contain-intrinsic-size) but avoids the
     layout/paint cost on initial load. Big time-to-interactive win on a long page. */
  .pp__about, .pp__cauldron-section, .pp__features,
  .pp__media-section, .pp__kindness, .pp__faq-section {
    content-visibility: auto;
    contain-intrinsic-size: 1px 800px;
  }

  /* ── Shared ── */
  .pp__hl { color: #d5fd51; }
  .pp__hl-box {
    background: #d5fd51;
    color: #FFFFFF;
    padding: 2px 10px;
    border-radius: 6px;
    font-weight: 700;
  }
  .pp__error {
    font-size: 13px;
    color: #D32F2F;
    margin-top: 12px;
    font-weight: 500;
  }

  /* ── Arrow button (Pudgy circle-arrow CTA) ── */
  .pp__arrow-btn {
    display: inline-flex;
    align-items: center;
    gap: 12px;
    font-family: "Fredoka", sans-serif;
    font-weight: 600;
    font-size: 14px;
    color: #2A1F54;
    text-decoration: none;
    cursor: pointer;
    background: none;
    border: none;
    padding: 0;
    transition: gap 0.2s ease;
  }
  .pp__arrow-btn:hover { gap: 16px; }
  .pp__arrow-circle {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    border-radius: 50%;
    background: #d5fd51;
    color: #17112f;
    transition: transform 0.2s ease;
  }
  .pp__arrow-btn:hover .pp__arrow-circle { transform: translateX(2px); }
  .pp__arrow-btn--dark { color: #FFFFFF; }
  .pp__arrow-circle--dark { background: #FFFFFF; color: #2A1F54; }

  /* ── Buttons ── */
  .pp__btn {
    font-family: "Fredoka", sans-serif;
    font-weight: 600;
    font-size: 15px;
    padding: 14px 32px;
    border-radius: 14px;
    cursor: pointer;
    transition: all 0.2s ease;
    border: 2px solid transparent;
    text-decoration: none;
    display: inline-block;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }
  .pp__btn--primary {
    background: #d5fd51;
    color: #2A1F54;
    border-color: #d5fd51;
    box-shadow: 0 4px 0 #a9cc2f;
  }
  .pp__btn--primary:hover:not(:disabled) {
    transform: translateY(-2px);
    box-shadow: 0 6px 0 #a9cc2f;
  }
  .pp__btn--primary:disabled {
    opacity: 0.4;
    cursor: not-allowed;
    box-shadow: 0 4px 0 #999;
  }
  /* iteration #1 live → enter the Cauldron (deep purple, stands out, clickable) */
  .pp__btn--live {
    background: #2A1F54;
    color: #f5f0e8;
    border-color: #2A1F54;
    box-shadow: 0 4px 0 #180f36;
    text-transform: none;
    letter-spacing: 0;
  }
  .pp__btn--live:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 0 #180f36, 0 0 24px rgba(213,253,81,0.35);
    border-color: #d5fd51;
  }
  .pp__btn-arrow { display: inline-block; transition: transform 0.2s ease; margin-left: 2px; }
  .pp__btn--live:hover .pp__btn-arrow { transform: translateX(4px); }
  .pp__btn--wide { width: 100%; text-align: center; }
  .pp__btn--nav {
    background: #FFFFFF;
    color: #2A1F54;
    border: 2px solid #2A1F54;
    padding: 8px 20px;
    font-size: 13px;
    border-radius: 10px;
    box-shadow: 0 3px 0 #2A1F54;
  }
  .pp__btn--nav:hover { transform: translateY(-1px); box-shadow: 0 4px 0 #2A1F54; }
  .pp__btn--kindness {
    background: #2A1F54;
    color: #f6c86a;
    box-shadow: 0 3px 0 #b8863b, 0 8px 20px rgba(42, 31, 84, 0.35);
    letter-spacing: 0.04em;
  }
  .pp__btn--kindness:hover { transform: translateY(-2px); box-shadow: 0 5px 0 #b8863b, 0 12px 26px rgba(42, 31, 84, 0.45); }
  .pp__btn--footer {
    background: transparent;
    color: #FFFFFF;
    border: 1px solid rgba(255,255,255,0.3);
    font-size: 12px;
    padding: 8px 18px;
    border-radius: 8px;
  }
  .pp__btn--footer:hover { border-color: #FFFFFF; }

  /* ═══════ 1. TICKER BAR ═══════ */
  .pp__ticker {
    background: #d5fd51;
    border-top: 1px solid rgba(42,31,84,0.28);
    border-bottom: 1px solid rgba(42,31,84,0.16);
    overflow-x: clip;
    overflow-y: visible;
    white-space: nowrap;
    padding: 11px 0;
    position: relative;
    z-index: 10;
    /* Full-bleed the hero WITHOUT the buggy 100vw hack (which overshoots by the
       scrollbar width, leaving the right edge short). Stretch to the hero's
       content box, then cancel its 24px side padding so it spans edge-to-edge. */
    align-self: stretch;
    margin-left: -24px;
    margin-right: -24px;
    flex-shrink: 0;
  }
  .pp__ticker-track {
    display: inline-flex;
    animation: pp-ticker 25s linear infinite reverse;
  }
  .pp__ticker-item {
    font-family: "DM Mono", monospace;
    font-weight: 600;
    font-size: 12px;
    color: #2A1F54;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    white-space: nowrap;
    display: inline-flex;
    align-items: center;
    gap: 0;
  }
  .pp__ticker-fren {
    display: inline-block;
    width: 48px;
    height: 0;
    position: relative;
    image-rendering: pixelated;
    margin: 0 6px;
    flex-shrink: 0;
  }
  .pp__ticker-fren-layer {
    position: absolute;
    bottom: -22px;
    left: 0;
    width: 48px;
    height: 48px;
    object-fit: contain;
    image-rendering: pixelated;
  }
  @keyframes pp-ticker {
    0% { transform: translateX(0); }
    100% { transform: translateX(-50%); }
  }

  /* ═══════ 2. HERO ═══════ */
  .pp__hero {
    position: relative;
    /* Enchanted Twilight — a magical night that WARMS as it falls: near-void up
       top (lime glow), deep violet through the middle, blooming into the wizard
       purple / periwinkle at the base. Keeps the dark magic without going flat
       black, and hands the purple off to the ticker + gold about below. */
    background:
      radial-gradient(1200px 640px at 50% -10%, rgba(213,253,81,0.13), transparent 56%),
      radial-gradient(1000px 700px at 84% 30%, rgba(124,92,252,0.28), transparent 58%),
      radial-gradient(1100px 560px at 16% 96%, rgba(184,168,216,0.30), transparent 62%),
      linear-gradient(180deg, #120C22 0%, #241a45 46%, #4a3a7a 82%, #6b5aa0 100%);
    text-align: center;
    padding: 0 24px;
    overflow: hidden;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    align-items: center;
  }
  .pp__hero::before {
    content: ""; position: absolute; inset: 0; pointer-events: none; opacity: 0.05; z-index: 0;
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='120' height='120'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.8' numOctaves='3'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
  }

  /* Magical sparkles */
  .pp__sparkles-field { position: absolute; inset: 0; pointer-events: none; z-index: 1; overflow: hidden; }
  .pp__sparkle-float {
    position: absolute;
    top: -20px;
    animation: pp-sparkle-rise linear infinite;
    color: rgba(255, 255, 255, 0.5);
    filter: drop-shadow(0 0 4px rgba(247, 147, 26, 0.3));
  }
  .pp__sparkle-float--0 { color: rgba(213, 253, 81, 0.7); filter: drop-shadow(0 0 6px rgba(213, 253, 81, 0.5)); }
  .pp__sparkle-float--1 { color: rgba(246, 200, 106, 0.5); }
  .pp__sparkle-float--2 { color: rgba(213, 253, 81, 0.4); filter: drop-shadow(0 0 6px rgba(213, 253, 81, 0.45)); }

  .pp__wisp {
    display: block;
    border-radius: 50%;
    background: radial-gradient(circle, rgba(213, 253, 81, 0.55) 0%, rgba(246, 200, 106, 0.18) 50%, transparent 70%);
    animation: pp-wisp-pulse 3s ease-in-out infinite alternate;
  }

  @keyframes pp-sparkle-rise {
    0% { transform: translateY(800px) translateX(0) rotate(0deg) scale(0); opacity: 0; }
    8% { opacity: 1; transform: translateY(700px) translateX(calc(var(--drift) * 0.1)) rotate(30deg) scale(1); }
    50% { opacity: 0.8; transform: translateY(400px) translateX(var(--drift)) rotate(180deg) scale(0.8); }
    85% { opacity: 0.4; transform: translateY(100px) translateX(calc(var(--drift) * 0.5)) rotate(300deg) scale(0.6); }
    100% { transform: translateY(-40px) translateX(0) rotate(360deg) scale(0); opacity: 0; }
  }

  @keyframes pp-wisp-pulse {
    0% { transform: scale(0.8); opacity: 0.3; }
    100% { transform: scale(1.3); opacity: 0.7; }
  }

  .pp__robinhood-inline {
    width: 16px;
    height: 16px;
    vertical-align: middle;
    margin: 0 2px;
  }

  /* Title — pushed down from top */
  .pp__hero-title {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0;
    margin-top: clamp(100px, 14vh, 180px);
    margin-bottom: 4px;
    position: relative;
    z-index: 2;
  }
  .pp__hero-title-line1 {
    font-family: "Cinzel Decorative", "Cinzel", serif;
    font-weight: 700;
    font-size: clamp(26px, 4.6vw, 52px);
    color: #F5F0E8;
    line-height: 1.1;
    text-shadow: 0 0 34px rgba(213, 253, 81, 0.22);
    letter-spacing: 0.14em;
    text-transform: uppercase;
    opacity: 0.92;
  }
  .pp__hero-title-line2 {
    font-family: "Cinzel Decorative", "Cinzel", serif;
    font-weight: 900;
    font-size: clamp(58px, 11.5vw, 150px);
    line-height: 0.82;
    letter-spacing: 0.01em;
    /* Clean cream fill with a soft lime magical halo — the hero word. */
    background: linear-gradient(180deg, #ffffff 0%, #f5f0e8 55%, #e8e0d0 100%);
    -webkit-background-clip: text; background-clip: text;
    -webkit-text-fill-color: transparent; color: transparent;
    filter: drop-shadow(0 0 40px rgba(213, 253, 81, 0.35)) drop-shadow(0 6px 16px rgba(0, 0, 0, 0.5));
  }

  .pp__hero-sub {
    font-family: "DM Mono", monospace;
    font-size: 13px;
    font-weight: 500;
    color: #d5fd51;
    opacity: 0.85;
    text-transform: uppercase;
    letter-spacing: 0.24em;
    margin-bottom: 0;
    position: relative;
    z-index: 2;
    max-width: 600px;
    margin-left: auto;
    margin-right: auto;
  }

  /* 7-character lineup — wizard gang, heavily overlapping */
  .pp__lineup {
    display: flex;
    justify-content: center;
    align-items: flex-end;
    gap: 0;
    position: relative;
    z-index: 3;
    max-width: 1400px;
    width: 100%;
    margin-top: auto;
    margin-bottom: -100px;
  }
  .pp__lineup-fren {
    position: relative;
    image-rendering: pixelated;
    transition: transform 0.3s ease;
    flex-shrink: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    /* Lift the pixel frens off the dark void with a soft glow + grounding shadow. */
    filter: drop-shadow(0 6px 18px rgba(0, 0, 0, 0.55)) drop-shadow(0 0 22px rgba(213, 253, 81, 0.12));
  }

  /* 7 slots — editor-tuned positions, scaled up */
  .pp__lineup-fren--0 { width: 400px; height: 400px; margin-right: -242px; z-index: 1; }
  .pp__lineup-fren--1 { width: 445px; height: 445px; margin-right: -260px; z-index: 2; transform: translateY(-6px); }
  .pp__lineup-fren--2 { width: 490px; height: 490px; margin-right: -290px; z-index: 3; transform: translateY(-20px); }
  .pp__lineup-fren--3 { width: 550px; height: 550px; z-index: 7; transform: translateY(-15px); filter: drop-shadow(0 6px 32px rgba(42, 31, 84, 0.5)); }
  .pp__lineup-fren--4 { width: 490px; height: 490px; margin-left: -264px; z-index: 3; transform: translateY(-8px); }
  .pp__lineup-fren--5 { width: 445px; height: 445px; margin-left: -274px; z-index: 2; }
  .pp__lineup-fren--6 { width: 400px; height: 400px; margin-left: -256px; z-index: 1; }

  .pp__lineup-layer {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: contain;
    image-rendering: pixelated;
  }

  /* ── Fren Editor ── */
  .pp__editor-toggle {
    position: absolute;
    bottom: 20px;
    right: 20px;
    z-index: 50;
    background: #d5fd51;
    color: #fff;
    border: none;
    border-radius: 50%;
    width: 44px;
    height: 44px;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    box-shadow: 0 2px 12px rgba(0,0,0,0.3);
    transition: transform 0.2s;
  }
  .pp__editor-toggle:hover { transform: scale(1.1); }
  .pp__editor-panel {
    position: absolute;
    top: 60px;
    right: 20px;
    z-index: 50;
    background: rgba(0,0,0,0.88);
    color: #fff;
    padding: 14px 16px;
    border-radius: 12px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    font-family: "DM Sans", sans-serif;
    font-size: 13px;
    min-width: 240px;
    box-shadow: 0 4px 24px rgba(0,0,0,0.5);
    backdrop-filter: blur(8px);
  }
  .pp__editor-values {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 6px 0;
    border-top: 1px solid rgba(255,255,255,0.15);
    border-bottom: 1px solid rgba(255,255,255,0.15);
  }
  .pp__editor-copy {
    background: #d5fd51;
    color: #fff;
    border: none;
    border-radius: 6px;
    padding: 6px 12px;
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
    text-align: center;
  }
  .pp__editor-copy:hover { opacity: 0.85; }

  /* ═══════ 3. ABOUT (coral) ═══════ */
  .pp__about {
    background:
      radial-gradient(ellipse 85% 70% at 100% 0%, #f9d488 0%, transparent 62%),
      radial-gradient(ellipse 70% 70% at 4% 96%, #eab94f 0%, transparent 60%),
      radial-gradient(ellipse 90% 90% at 48% 40%, #f8ce77 0%, transparent 70%),
      #f6c86a;
    padding: 48px 0 0 0;
    position: relative;
    overflow: hidden;
  }
  .pp__about-inner {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 0;
    align-items: end;
  }
  .pp__about-title {
    display: flex;
    flex-direction: row;
    align-items: baseline;
    margin-bottom: 24px;
  }
  .pp__about-title-line1 {
    font-family: "Fredoka", sans-serif;
    font-weight: 700;
    font-size: clamp(28px, 5vw, 48px);
    color: #2A1F54;
    line-height: 1;
    letter-spacing: -0.01em;
  }
  .pp__about-title-line2 {
    font-family: "Fredoka", sans-serif;
    font-weight: 700;
    font-size: clamp(48px, 9vw, 96px);
    color: #2A1F54;
    line-height: 0.9;
    letter-spacing: -0.02em;
  }
  .pp__about-text {
    font-family: "DM Sans", sans-serif;
    font-size: 15px;
    font-weight: 500;
    line-height: 1.6;
    color: rgba(42,31,84,0.85);
    margin-bottom: 16px;
    max-width: 420px;
  }
  .pp__about-left { padding: 0 24px 40px max(24px, calc((100vw - 1100px) / 2)); }
  .pp__about-stats {
    display: flex;
    align-items: center;
    gap: 28px;
    margin: 32px 0 16px;
  }
  .pp__about-stat {
    display: flex;
    flex-direction: column;
    align-items: center;
  }
  .pp__about-stat-value {
    font-family: "Fredoka", sans-serif;
    font-weight: 700;
    font-size: 42px;
    color: #2A1F54;
    line-height: 1;
  }
  .pp__about-stat-label {
    font-family: "Fredoka", sans-serif;
    font-weight: 600;
    font-size: 11px;
    color: rgba(42,31,84,0.65);
    letter-spacing: 0.14em;
    text-transform: uppercase;
    margin-top: 4px;
  }
  .pp__about-stat-divider {
    width: 1px;
    height: 40px;
    background: rgba(42,31,84,0.25);
  }
  .pp__about-sub {
    font-family: "DM Sans", sans-serif;
    font-size: 14px;
    color: rgba(42,31,84,0.6);
    margin-bottom: 28px;
  }
  .pp__about-bottom-row {
    display: flex;
    align-items: flex-end;
    gap: 32px;
    margin-top: 4px;
  }
  .pp__about-contract {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .pp__about-contract-label {
    font-family: "DM Sans", sans-serif;
    font-weight: 500;
    font-size: 11px;
    color: rgba(42,31,84,0.55);
    letter-spacing: 0.1em;
    text-transform: uppercase;
  }
  .pp__about-contract-addr {
    font-family: "DM Mono", "Fira Code", monospace;
    font-size: 13px;
    color: rgba(42,31,84,0.85);
    background: rgba(42,31,84,0.08);
    border: 1px solid rgba(42,31,84,0.18);
    border-radius: 6px;
    padding: 4px 10px;
    cursor: pointer;
    transition: all 0.15s ease;
    letter-spacing: 0.02em;
  }
  .pp__about-contract-addr:hover {
    color: #2A1F54;
    border-color: #d5fd51;
    background: #d5fd51;
  }
  .pp__about-contract-addr:active {
    transform: scale(0.97);
  }
  .pp__about-robinhood {
    display: inline-flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 6px;
    text-decoration: none;
    transition: opacity 0.2s;
  }
  .pp__about-robinhood:hover { opacity: 0.8; }
  .pp__about-robinhood-label {
    font-family: "DM Sans", sans-serif;
    font-weight: 500;
    font-size: 14px;
    color: rgba(255,255,255,0.55);
    letter-spacing: 0.04em;
  }
  .pp__about-robinhood-logo { width: 120px; height: auto; filter: brightness(0) invert(1); }
  .pp__about-right { display: flex; align-items: flex-end; justify-content: flex-end; }
  .pp__about-img {
    display: block;
    height: auto;
    max-height: 420px;
    width: auto;
    max-width: 100%;
    border-radius: 0;
    margin-bottom: -4px;
  }
  @keyframes pp-bob {
    0%, 100% { transform: translateY(0); }
    50% { transform: translateY(-8px); }
  }

  /* ═══════ 4. FEATURE CARDS (two-column) ═══════ */
  .pp__features {
    padding: 60px 24px;
    background: #F5F0E8;
  }
  .pp__features-grid {
    max-width: 1100px;
    margin: 0 auto;
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 24px;
  }
  .pp__feature-card {
    border-radius: 24px;
    border: 3px solid #2A1F54;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    transition: transform 0.3s ease;
    position: relative;
    color: #2A1F54;
  }
  .pp__feature-card:hover { transform: translateY(-4px); }
  .pp__feature-card--cream {
    background:
      radial-gradient(ellipse 62% 96% at 108% 60%, rgba(213,253,81,0.24), transparent 60%),
      linear-gradient(135deg, #f4e6c6 0%, #ecd9b4 100%);
  }
  .pp__feature-card--pink {
    background:
      radial-gradient(ellipse 62% 96% at 108% 60%, rgba(124,92,252,0.22), transparent 60%),
      linear-gradient(135deg, #efe9fb 0%, #e2d8f4 100%);
  }
  .pp__feature-content {
    padding: 32px 28px 24px;
    flex: 1;
  }
  .pp__feature-tag {
    font-family: "Fredoka", sans-serif;
    font-size: 11px;
    font-weight: 600;
    color: #8a7baa;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    opacity: 0.7;
    display: block;
    margin-bottom: 12px;
  }
  .pp__feature-heading {
    font-family: "Fredoka", sans-serif;
    font-weight: 700;
    font-size: 28px;
    color: #2A1F54;
    line-height: 1.1;
    margin-bottom: 12px;
  }
  .pp__feature-desc {
    font-family: "DM Sans", sans-serif;
    font-size: 14px;
    line-height: 1.6;
    color: rgba(42,31,84,0.7);
    opacity: 1;
    margin-bottom: 20px;
  }
  .pp__feature-art {
    display: flex;
    align-items: flex-end;
    justify-content: center;
    padding: 0 20px;
    min-height: 180px;
  }
  .pp__feature-cauldron {
    width: 140px;
    height: auto;
    image-rendering: pixelated;
    filter: drop-shadow(0 4px 16px rgba(42, 31, 84, 0.3));
  }
  .pp__feature-mascot {
    width: 100%;
    max-width: 420px;
    height: auto;
    object-fit: contain;
    filter: drop-shadow(0 4px 16px rgba(42, 31, 84, 0.15));
    margin-bottom: -100px;
    margin-top: -60px;
    position: relative;
    z-index: 1;
  }
  .pp__feature-mascot--sm {
    max-width: 380px;
    position: absolute;
    bottom: -40px;
    right: -20px;
    margin: 0;
    z-index: 2;
  }
  .pp__feature-art--fren { min-height: 200px; }
  .pp__feature-fren {
    width: 160px;
    height: 160px;
    position: relative;
    image-rendering: pixelated;
  }
  .pp__feature-fren-layer {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: contain;
    image-rendering: pixelated;
  }

  /* ═══════ 5. CAULDRON SECTION (periwinkle) ═══════ */
  .pp__cauldron-section {
    /* Robinhood-lime glow behind the cauldron. Two mistakes made it look white:
       low-opacity bright lime over dark purple washes pale, and fading to
       transparent interpolates through grey. Fix: a tight SATURATED lime core
       that fades to transparent-LIME (same rgb, 0 alpha, no graying), a soft mid
       halo, and only a faint violet at the far edges so it cannot desaturate. */
    background:
      radial-gradient(260px 220px at 50% 60%, rgba(213,253,81,0.32) 0%, rgba(213,253,81,0.12) 45%, rgba(213,253,81,0) 72%),
      radial-gradient(900px 640px at 50% 50%, rgba(124,92,252,0.16) 0%, rgba(124,92,252,0) 66%),
      #241a45;
    padding: 80px 24px;
    text-align: center;
    position: relative;
    overflow: hidden;
  }
  /* Rolling frens behind the cauldron, faded out through a soft blurred circle in
     the centre so the copy + cauldron stay fully legible. The two radial stops
     (transparent core → opaque ring) give the "undefined circle with blurred
     edges" the frens dissolve into. */
  .pp__cauldron-frens {
    position: absolute;
    inset: 0;
    z-index: 0;
    display: flex;
    flex-direction: column;
    justify-content: center;
    gap: 0px;
    overflow: hidden;
    opacity: 0.16;
    pointer-events: none;
    /* Two soft clear zones, intersected so frens show only where BOTH are opaque:
       (1) a centred ellipse over the "THE CAULDRON" title + copy column — narrow
       enough (40% wide) that frens keep drifting to its LEFT and RIGHT, and
       (2) a wider circle for the orbit/cauldron below. */
    -webkit-mask-image:
      radial-gradient(ellipse 40% 22% at 50% 16%, transparent 0%, transparent 44%, #000 100%),
      radial-gradient(ellipse 52% 40% at 50% 64%, transparent 0%, transparent 34%, #000 72%);
            mask-image:
      radial-gradient(ellipse 40% 22% at 50% 16%, transparent 0%, transparent 44%, #000 100%),
      radial-gradient(ellipse 52% 40% at 50% 64%, transparent 0%, transparent 34%, #000 72%);
    -webkit-mask-composite: source-in;
            mask-composite: intersect;
  }
  .pp__cauldron-frens .pp__marquee-fren {
    width: 88px;
    height: 88px;
    margin-top: -12px;
  }
  /* Keep the actual content above the drifting frens. */
  .pp__cauldron-title,
  .pp__cauldron-sub,
  .pp__orbit {
    position: relative;
    z-index: 1;
  }
  .pp__cauldron-title {
    font-family: "Cinzel Decorative", "Cinzel", serif;
    font-weight: 700;
    font-size: clamp(48px, 9vw, 90px);
    color: #FFFFFF;
    -webkit-text-stroke: 1px #2A1F54;
    text-shadow: 2px 2px 0 rgba(42, 31, 84, 0.2), 0 0 44px rgba(213,253,81,0.35);
    text-transform: uppercase;
    line-height: 0.9;
    margin-bottom: 20px;
  }
  .pp__cauldron-sub {
    font-family: "DM Sans", sans-serif;
    font-size: 16px;
    line-height: 1.7;
    color: rgba(255,255,255,0.85);
    max-width: 700px;
    margin: 0 auto 48px;
    opacity: 1;
  }

  /* Phase flow diagrams */
  /* ═══ Ritual flow: Genesis → Pentagon ═══ */
  /* ── Orbit cycle (oval path) ── */
  .pp__orbit {
    position: relative;
    width: 800px;
    height: 560px;
    margin: 20px auto 0;
  }
  .pp__orbit-center {
    position: absolute;
    left: 50%;
    top: 50%;
    transform: translate(-50%, -58%);
    width: 420px;
    z-index: 2;
  }
  .pp__orbit-cauldron {
    width: 100%;
    height: auto;
    object-fit: contain;
    /* Tighter + higher-alpha inner lime ring reads as SATURATED lime, not a pale
       white haze; a wider soft one adds bloom. */
    filter: drop-shadow(0 0 12px rgba(213,253,81,0.55)) drop-shadow(0 0 34px rgba(124,92,252,0.35));
  }
  .pp__orbit-arrow {
    position: absolute;
    width: 50px;
    height: 62px;
    z-index: 1;
    pointer-events: none;
    opacity: 0.45;
  }
  .pp__orbit-arrow--0 { left: 68%; top: 12%; transform: rotate(100deg); }  /* TRADE→DEATH */
  .pp__orbit-arrow--1 { left: 87%; top: 59%; transform: rotate(170deg); }  /* DEATH→CLAIM */
  .pp__orbit-arrow--2 { left: 49%; top: 95%; transform: rotate(250deg); }  /* CLAIM→VOTE */
  .pp__orbit-arrow--3 { left: 11%; top: 58%; transform: rotate(330deg); }  /* VOTE→RELAUNCH */
  .pp__orbit-arrow--4 { left: 26%; top: 10%; transform: rotate(30deg); }   /* RELAUNCH→TRADE */
  .pp__orbit-node {
    position: absolute;
    display: flex;
    flex-direction: column;
    align-items: center;
    z-index: 3;
    transform: translate(-50%, -50%);
  }
  .pp__orbit-node--0 { left: 50%; top: 8%;  }  /* TRADE — top center */
  .pp__orbit-node--1 { left: 88%; top: 34%; }  /* DEATH — right */
  .pp__orbit-node--2 { left: 78%; top: 90%; }  /* CLAIM — bottom-right */
  .pp__orbit-node--3 { left: 24%; top: 90%; }  /* VOTE — bottom-left */
  .pp__orbit-node--4 { left: 14%; top: 34%; }  /* RELAUNCH — left */

  .pp__orbit-sticker {
    width: 120px;
    height: 120px;
    object-fit: contain;
    filter: drop-shadow(0 4px 12px rgba(0,0,0,0.4));
    transition: filter 0.25s ease;
  }
  .pp__orbit-sticker:hover {
    filter: drop-shadow(0 0 26px rgba(213,253,81,0.4));
  }
  .pp__orbit-label {
    font-family: "Fredoka", sans-serif;
    font-size: 14px;
    font-weight: 700;
    letter-spacing: 0.12em;
    color: #FFFFFF;
    margin-top: 6px;
    text-shadow: 0 2px 8px rgba(0,0,0,0.5);
  }
  .pp__orbit-desc {
    font-family: "DM Sans", sans-serif;
    font-size: 11px;
    color: rgba(255,255,255,0.45);
    text-shadow: 0 1px 4px rgba(0,0,0,0.4);
  }

  @media (max-width: 860px) {
    .pp__orbit { width: 580px; height: 420px; }
    .pp__orbit-center { width: 300px; }
    .pp__orbit-sticker { width: 90px; height: 90px; }
    .pp__orbit-label { font-size: 11px; }
    .pp__orbit-desc { font-size: 9px; }
  }
  @media (max-width: 620px) {
    .pp__orbit { width: 380px; height: 300px; }
    .pp__orbit-center { width: 220px; }
    .pp__orbit-sticker { width: 62px; height: 62px; }
    .pp__orbit-label { font-size: 9px; }
    .pp__orbit-desc { display: none; }
  }

  /* ═══════ 6. CLAIM / MINT SECTION ═══════ */
  .pp__claim {
    background: #F5F0E8;
    padding: 60px 24px;
  }
  .pp__claim-card {
    max-width: 1000px;
    margin: 0 auto;
    display: grid;
    grid-template-columns: 1fr 1fr;
    border: 3px solid #2A1F54;
    border-radius: 24px;
    overflow: hidden;
    /* Clean warm parchment for the mint side (lime visual sits on the left). */
    background:
      radial-gradient(120% 120% at 100% 0%, #fbf7ef, transparent 60%),
      linear-gradient(135deg, #f6efe1 0%, #efe7d8 100%);
    box-shadow: 0 20px 50px rgba(42,31,84,0.10);
  }
  .pp__claim-left {
    position: relative;
    overflow: hidden;
    background: #d5fd51;
    display: flex;
    align-items: stretch;   /* image fills the card top-to-bottom */
    justify-content: center;
  }
  .pp__claim-cycle {
    position: relative;
    width: 100%;
    background: #d5fd51;
    overflow: hidden;       /* fills the cell height — matches the right column */
  }
  .pp__claim-cycle-fren {
    position: absolute;
    image-rendering: pixelated;
    width: 187.5%;
    height: 187.5%;
    top: -43.75%;
    left: -43.75%;
  }
  .pp__claim-cycle-layer {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: contain;
    image-rendering: pixelated;
  }
  .pp__claim-right { padding: 26px 30px; display: flex; flex-direction: column; }
  .pp__claim-eyebrow {
    display: inline-block;
    font-family: "DM Mono", monospace;
    font-size: 11px;
    letter-spacing: 0.16em;
    color: #6a8f00;
    background: rgba(213,253,81,0.22);
    border: 1px solid rgba(169,204,47,0.5);
    padding: 4px 10px;
    border-radius: 999px;
    margin-bottom: 12px;
  }
  .pp__claim-heading {
    font-family: "Fredoka", sans-serif;
    font-weight: 700;
    font-size: 32px;
    color: #2A1F54;
    margin-bottom: 12px;
  }
  .pp__claim-desc {
    font-family: "DM Sans", sans-serif;
    font-size: 14px;
    line-height: 1.6;
    color: rgba(42,31,84,0.7);
    opacity: 1;
    margin-bottom: 16px;
  }
  .pp__claim-desc strong { color: #2A1F54; }
  .pp__claim-desc em { color: #6a8f00; font-style: normal; font-weight: 600; }
  .pp__claim-bonus {
    display: flex;
    align-items: flex-start;
    gap: 10px;
    background: rgba(213,253,81,0.12);
    border: 1px solid rgba(169,204,47,0.4);
    border-radius: 12px;
    padding: 12px 14px;
    margin-bottom: 14px;
  }
  .pp__claim-bonus-tag {
    flex-shrink: 0;
    font-family: "DM Mono", monospace;
    font-size: 9px;
    font-weight: 700;
    letter-spacing: 0.1em;
    color: #4a7a00;
    background: rgba(213,253,81,0.5);
    padding: 3px 8px;
    border-radius: 6px;
    margin-top: 1px;
  }
  .pp__claim-bonus p { margin: 0; font-size: 13px; line-height: 1.5; color: rgba(42,31,84,0.8); }
  .pp__claim-bonus strong { color: #2A1F54; }
  .pp__claim-fineprint {
    font-family: "DM Sans", sans-serif;
    font-size: 12px;
    line-height: 1.55;
    color: rgba(42,31,84,0.55);
    background: rgba(42,31,84,0.04);
    border-left: 3px solid rgba(255,92,77,0.55);
    padding: 10px 12px;
    border-radius: 0 8px 8px 0;
    margin-bottom: 20px;
  }
  .pp__claim-fineprint strong { color: #b3402f; }
  .pp__claim-stats {
    background: rgba(42,31,84,0.05);
    border: 2px solid rgba(42,31,84,0.1);
    border-radius: 14px;
    padding: 16px 20px;
    margin-bottom: 20px;
  }
  .pp__claim-stat {
    display: flex;
    justify-content: space-between;
    padding: 6px 0;
  }
  .pp__claim-stat-label {
    font-family: "DM Sans", sans-serif;
    font-size: 13px;
    color: #8a7baa;
    opacity: 0.7;
  }
  .pp__claim-stat-value {
    font-family: "Fredoka", sans-serif;
    font-size: 14px;
    font-weight: 600;
    color: #2A1F54;
  }
  .pp__claim-stat-value--hl { color: #6a8f00; } /* dark lime — readable on cream */
  .pp__claim-progress-bar {
    height: 6px;
    background: rgba(42,31,84,0.12);
    border-radius: 3px;
    overflow: hidden;
    margin: 8px 0;
  }
  .pp__claim-progress-fill {
    height: 100%;
    background: linear-gradient(90deg, #d5fd51, #f6c86a);
    border-radius: 3px;
    transition: width 0.6s ease;
  }

  /* ═══════ 7. TEXT MARQUEE ═══════ */
  .pp__text-marquee {
    background: #2A1F54;
    overflow: hidden;
    white-space: nowrap;
    padding: 14px 0;
  }
  .pp__text-marquee-track {
    display: inline-flex;
    animation: pp-ticker 40s linear infinite;
  }
  .pp__text-marquee-item {
    font-family: "Fredoka", sans-serif;
    font-weight: 600;
    font-size: 14px;
    color: #FFFFFF;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    white-space: nowrap;
    opacity: 0.7;
  }

  /* ═══════ LINED WRAPPER (media + kindness + FAQ) ═══════ */
  .pp__lined-wrap {
    position: relative;
    background: #F5F0E8;
    overflow: hidden;
  }
  .pp__lined-bg {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    justify-content: flex-start;
    gap: 0px;
    overflow: hidden;
    opacity: 0.18;
    pointer-events: none;
    mask-image: linear-gradient(to right, transparent 0%, black 5%, black 95%, transparent 100%);
    -webkit-mask-image: linear-gradient(to right, transparent 0%, black 5%, black 95%, transparent 100%);
  }
  .pp__lined-bg .pp__marquee-fren {
    width: 80px;
    height: 80px;
    margin-top: -12px;
  }

  /* ═══════ 8. MEDIA CARDS ═══════ */
  .pp__media-section {
    position: relative;
    z-index: 1;
    padding: 60px 24px;
  }
  .pp__media-grid {
    max-width: 1100px;
    margin: 0 auto;
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 24px;
  }
  .pp__media-card {
    border: 3px solid #2A1F54;
    border-radius: 24px;
    overflow: hidden;
    display: grid;
    grid-template-columns: 1fr auto;
    transition: transform 0.3s ease;
  }
  .pp__media-card:hover { transform: translateY(-4px); }
  /* COMMUNITY card — warm gold with a lime spotlight behind the mascot. */
  .pp__media-card--cream {
    background:
      radial-gradient(ellipse 62% 96% at 108% 55%, rgba(213,253,81,0.28), transparent 60%),
      radial-gradient(130% 130% at 0% 0%, #fbf1da, transparent 62%),
      linear-gradient(135deg, #f4e6c6 0%, #ecd9b4 100%);
  }
  /* FOLLOW card — cool cream with a violet spotlight behind the mascot. */
  .pp__media-card--white {
    background:
      radial-gradient(ellipse 62% 96% at 108% 55%, rgba(124,92,252,0.22), transparent 60%),
      radial-gradient(130% 130% at 0% 0%, #ffffff, transparent 60%),
      linear-gradient(135deg, #fbf7ef 0%, #efe8db 100%);
  }
  .pp__media-card-content { padding: 28px 24px; }
  .pp__media-tag {
    font-family: "DM Mono", monospace;
    font-size: 10px;
    font-weight: 600;
    color: #2A1F54;
    text-transform: uppercase;
    letter-spacing: 0.18em;
    opacity: 0.9;
    display: inline-block;
    margin-bottom: 12px;
    padding: 4px 10px;
    border-radius: 20px;
    background: rgba(42,31,84,0.08);
    border: 1px solid rgba(42,31,84,0.14);
  }
  .pp__media-heading {
    font-family: "Fredoka", sans-serif;
    font-weight: 700;
    font-size: 24px;
    color: #2A1F54;
    margin-bottom: 8px;
  }
  .pp__media-desc {
    font-family: "DM Sans", sans-serif;
    font-size: 13px;
    line-height: 1.6;
    color: rgba(42,31,84,0.7);
    opacity: 1;
    margin-bottom: 16px;
  }
  .pp__media-card-deco {
    display: flex;
    align-items: flex-end;
    padding: 12px 16px 0;
  }
  .pp__media-mascot {
    width: 120px;
    height: auto;
    object-fit: contain;
    filter: drop-shadow(0 4px 12px rgba(42, 31, 84, 0.15));
    animation: pp-bob 3s ease-in-out infinite;
  }
  .pp__media-fren {
    width: 100px;
    height: 100px;
    position: relative;
    image-rendering: pixelated;
    animation: pp-bob 3s ease-in-out infinite;
  }
  .pp__media-fren-layer {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: contain;
    image-rendering: pixelated;
  }

  /* ═══════ 9. KINDNESS / MANIFESTO ═══════ */
  .pp__kindness {
    position: relative;
    z-index: 1;
    padding: 0 24px 60px;
  }
  .pp__kindness-card {
    max-width: 1100px;
    margin: 0 auto;
    /* Rich gold "spellbook" with a lime spark top-left and a violet glow behind
       the wizard — depth instead of a flat amber slab. */
    background:
      radial-gradient(760px 460px at 10% 8%, rgba(213,253,81,0.20), transparent 55%),
      radial-gradient(680px 620px at 96% 96%, rgba(124,92,252,0.24), transparent 55%),
      linear-gradient(150deg, #f8dc94 0%, #f0c869 55%, #e6b348 100%);
    border: 3px solid #2A1F54;
    border-radius: 24px;
    display: grid;
    grid-template-columns: 1fr 1fr;
    overflow: hidden;
    min-height: 380px;
  }
  .pp__kindness-content {
    padding: 48px 40px;
    display: flex;
    flex-direction: column;
    justify-content: center;
  }
  .pp__kindness-title {
    font-family: "Cinzel Decorative", "Fredoka", serif;
    font-weight: 900;
    font-size: 46px;
    color: #2A1F54;
    line-height: 1;
    text-transform: uppercase;
    letter-spacing: 0.01em;
    margin-bottom: 16px;
    text-shadow: 0 2px 0 rgba(255,255,255,0.25), 0 0 30px rgba(213,253,81,0.3);
  }
  .pp__kindness-desc {
    font-family: "DM Sans", sans-serif;
    font-size: 15px;
    line-height: 1.7;
    color: rgba(42,31,84,0.7);
    opacity: 1;
    margin-bottom: 24px;
  }
  .pp__kindness-art {
    display: flex;
    align-items: flex-end;
    justify-content: flex-end;
    padding: 0;
  }
  .pp__kindness-mascot {
    max-width: 320px;
    width: 100%;
    height: auto;
    object-fit: contain;
    filter: drop-shadow(0 4px 20px rgba(42, 31, 84, 0.2));
    display: block;
  }

  /* ── Easter egg scene ── */
  .pp__egg-scene {
    position: relative;
    display: inline-block;
  }
  .pp__kindness-mascot--lifted {
    margin-top: -60px;
  }
  .pp__egg-scene:has(.pp__egg-clickzone:hover) .pp__kindness-mascot--lifted {
    transform: translate(-1px, 1px);
  }
  .pp__hat-clickzone {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 40%;
    z-index: 10;
    cursor: pointer;
  }
  .pp__egg-clickzone {
    position: absolute;
    top: 15%;
    left: 20%;
    width: 60%;
    height: 25%;
    z-index: 10;
    cursor: pointer;
  }
  .pp__kindness-fren {
    width: 260px;
    height: 260px;
    position: relative;
    image-rendering: pixelated;
    animation: pp-bob 4s ease-in-out infinite;
  }
  .pp__kindness-fren-layer {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: contain;
    image-rendering: pixelated;
  }

  /* ═══════ 10. COLLECTION ═══════ */

  /* ═══════ 11. CHARACTER MARQUEE ═══════ */
  /* pp__faq-bg removed — now using pp__lined-bg wrapper */
  .pp__marquee-row {
    display: flex;
    gap: 0px;
    animation: pp-marquee 45s linear infinite;
    width: max-content;
  }
  .pp__marquee-row:hover { animation-play-state: paused; }
  .pp__marquee-fren {
    width: 130px;
    height: 130px;
    position: relative;
    flex-shrink: 0;
    image-rendering: pixelated;
    background: none;
    border: none;
    border-radius: 0;
    overflow: hidden;
    transition: transform 0.25s ease;
  }
  .pp__marquee-fren:hover { transform: scale(1.08); }
  .pp__marquee-layer {
    position: absolute;
    inset: 8%;
    width: 84%;
    height: 84%;
    object-fit: contain;
    image-rendering: pixelated;
  }
  @keyframes pp-marquee {
    0% { transform: translateX(0); }
    100% { transform: translateX(-50%); }
  }

  /* ═══════ 12. NEWS ═══════ */


  /* ═══════ 14. FAQ ═══════ */
  .pp__faq-section {
    position: relative;
    z-index: 1;
    padding: 60px 24px 100px;
    text-align: center;
  }
  .pp__faq-content {
    position: relative;
    z-index: 2;
  }
  .pp__faq-title {
    font-family: "Fredoka", sans-serif;
    font-weight: 700;
    font-size: 48px;
    color: #2A1F54;
    margin-bottom: 32px;
    text-transform: uppercase;
  }
  .pp__faq {
    max-width: 680px;
    margin: 0 auto;
    text-align: left;
    border: 2px solid #2A1F54;
    border-radius: 18px;
    overflow: hidden;
    background: #FBF7F0;
  }
  .pp__faq-item { border-bottom: 2px solid rgba(42,31,84,0.1); }
  .pp__faq-item:last-child { border-bottom: none; }
  .pp__faq-q {
    display: flex;
    justify-content: space-between;
    align-items: center;
    width: 100%;
    padding: 20px 24px;
    background: none;
    border: none;
    color: #2A1F54;
    font-family: "Fredoka", sans-serif;
    font-size: 16px;
    font-weight: 600;
    text-align: left;
    cursor: pointer;
    transition: color 0.15s ease;
  }
  .pp__faq-q:hover { color: #d5fd51; }
  .pp__faq-arrow {
    font-size: 22px;
    color: #d5fd51;
    flex-shrink: 0;
    margin-left: 16px;
    font-weight: 700;
  }
  .pp__faq-a {
    overflow: hidden;
    transition: max-height 0.3s ease;
  }
  .pp__faq-a p {
    padding: 0 24px 20px;
    font-family: "DM Sans", sans-serif;
    font-size: 14px;
    line-height: 1.8;
    color: rgba(42,31,84,0.7);
    opacity: 1;
  }

  /* ═══════ 15. FOOTER (dark navy) ═══════ */
  .pp__footer {
    background: #2A1F54;
    color: #FFFFFF;
  }

  /* Footer marquee */
  .pp__footer-marquee {
    overflow: hidden;
    white-space: nowrap;
    padding: 12px 0;
    border-bottom: 1px solid rgba(255,255,255,0.1);
  }
  .pp__footer-marquee-track {
    display: inline-flex;
    animation: pp-ticker 35s linear infinite;
  }
  .pp__footer-marquee-item {
    font-family: "Fredoka", sans-serif;
    font-weight: 600;
    font-size: 13px;
    color: #FFFFFF;
    opacity: 0.3;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    white-space: nowrap;
  }

  .pp__footer-inner {
    max-width: 1100px;
    margin: 0 auto;
    padding: 48px 24px 32px;
  }

  /* Footer links grid */
  .pp__footer-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 32px;
    margin-bottom: 40px;
  }
  .pp__footer-col-title {
    font-family: "Fredoka", sans-serif;
    font-size: 12px;
    font-weight: 600;
    color: #FFFFFF;
    opacity: 0.4;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    margin-bottom: 16px;
  }
  .pp__footer-col a.pp__footer-link {
    display: block;
    font-family: "DM Sans", sans-serif;
    font-size: 14px;
    font-weight: 500;
    color: #FFFFFF;
    text-decoration: none;
    padding: 4px 0;
    opacity: 0.7;
    transition: opacity 0.2s ease;
  }
  .pp__footer-col a.pp__footer-link:hover { opacity: 1; }

  /* Social icons */
  .pp__footer-socials {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 20px 0;
    border-top: 1px solid rgba(255,255,255,0.1);
    border-bottom: 1px solid rgba(255,255,255,0.1);
    margin-bottom: 32px;
    flex-wrap: wrap;
  }
  .pp__footer-social {
    color: #FFFFFF;
    opacity: 0.6;
    transition: opacity 0.2s ease;
    display: inline-flex;
  }
  .pp__footer-social:hover { opacity: 1; }
  .pp__footer-xuser {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    color: #FFFFFF;
    font-family: "DM Sans", sans-serif;
    font-size: 13px;
    opacity: 0.7;
  }
  .pp__footer-avatar { width: 24px; height: 24px; border-radius: 50%; }
  .pp__footer-disconnect {
    background: none;
    border: none;
    color: #d5fd51;
    font-family: "DM Sans", sans-serif;
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
  }

  /* Footer bottom */
  .pp__footer-bottom {
    display: flex;
    align-items: center;
    gap: 16px;
    flex-wrap: wrap;
  }
  .pp__footer-mascot {
    flex-shrink: 0;
  }
  .pp__footer-guild {
    width: 64px;
    height: 64px;
    object-fit: contain;
    border-radius: 50%;
    filter: drop-shadow(0 2px 8px rgba(0,0,0,0.3));
  }
  .pp__footer-powered {
    display: flex;
    align-items: center;
    gap: 8px;
    font-family: "DM Sans", sans-serif;
    font-size: 12px;
    color: rgba(255, 255, 255, 0.5);
  }
  .pp__footer-robinhood {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    margin-top: 10px;
    color: #d5fd51;
    text-decoration: none;
    font-family: "DM Sans", sans-serif;
    font-size: 12px;
    font-weight: 700;
    letter-spacing: 0.02em;
    transition: opacity 0.2s;
  }
  .pp__footer-robinhood:hover { opacity: 0.8; }
  .pp__footer-robinhood-label {
    color: rgba(255, 255, 255, 0.45);
    font-weight: 500;
  }
  .pp__footer-robinhood-logo {
    width: 18px;
    height: 18px;
    /* Recolor the green feather to Robinhood-lime #d5fd51 to match the brand. */
    filter: brightness(0) saturate(100%) invert(93%) sepia(38%) saturate(1090%) hue-rotate(20deg) brightness(104%) contrast(98%);
  }
  .pp__footer-copy {
    font-family: "DM Sans", sans-serif;
    font-size: 13px;
    color: #FFFFFF;
    opacity: 0.5;
  }
  .pp__footer-legal {
    font-family: "DM Sans", sans-serif;
    font-size: 11px;
    color: #FFFFFF;
    opacity: 0.25;
    margin-left: auto;
  }

  /* ═══════ SCROLL REVEAL ANIMATIONS ═══════ */
  [data-reveal] {
    opacity: 0;
    transform: translateY(48px);
    transition: opacity 0.7s cubic-bezier(0.16, 1, 0.3, 1),
                transform 0.7s cubic-bezier(0.16, 1, 0.3, 1);
    will-change: opacity, transform;
  }
  [data-reveal].revealed {
    opacity: 1;
    transform: translateY(0);
  }

  /* ═══════ RESPONSIVE ═══════ */
  @media (max-width: 1000px) {
    .pp__features-grid,
    .pp__media-grid {
      grid-template-columns: 1fr;
    }
    .pp__kindness-card {
      grid-template-columns: 1fr;
    }
    .pp__kindness-art { padding: 0 24px 24px; }
    .pp__claim-card { grid-template-columns: 1fr; }
    .pp__claim-left { min-height: 200px; }
  }

  @media (max-width: 900px) {
    .pp__about-inner { grid-template-columns: 1fr; gap: 0; }
    .pp__about-left { padding: 0 24px 32px 24px; }
    .pp__hero-title-line1 { -webkit-text-stroke: 1px #2A1F54; }
    .pp__hero-title-line2 { -webkit-text-stroke: 3px #2A1F54; text-shadow: 4px 4px 0 rgba(42, 31, 84, 0.3); }
    .pp__footer-grid { grid-template-columns: 1fr; gap: 24px; }

    /* Lineup — tight overlap on tablet */
    .pp__lineup { margin-bottom: -55px; }
    .pp__lineup-fren--0 { width: 210px; height: 210px; margin-right: -128px; }
    .pp__lineup-fren--1 { width: 235px; height: 235px; margin-right: -138px; }
    .pp__lineup-fren--2 { width: 260px; height: 260px; margin-right: -154px; }
    .pp__lineup-fren--3 { width: 290px; height: 290px; }
    .pp__lineup-fren--4 { width: 260px; height: 260px; margin-left: -140px; }
    .pp__lineup-fren--5 { width: 235px; height: 235px; margin-left: -145px; }
    .pp__lineup-fren--6 { width: 210px; height: 210px; margin-left: -135px; }
  }

  @media (max-width: 560px) {
    .pp__hero {
      padding: 0 16px;
      min-height: auto;
      padding-bottom: 0;
    }

    .pp__hero-title-line1 {
      font-size: 32px !important;
      -webkit-text-stroke: 0.5px #2A1F54;
      letter-spacing: 0.02em;
    }

    .pp__hero-title-line2 {
      font-size: 72px !important;
      -webkit-text-stroke: 2px #2A1F54;
      text-shadow: 3px 3px 0 rgba(42, 31, 84, 0.3);
    }

    .pp__hero-sub {
      font-size: 12px;
      letter-spacing: 0.06em;
      margin-bottom: 0;
    }

    .pp__lineup {
      margin-top: 20px;
    }

    .pp__lineup { margin-bottom: -35px; }
    .pp__lineup-fren--0 { width: 135px; height: 135px; margin-right: -82px; }
    .pp__lineup-fren--1 { width: 150px; height: 150px; margin-right: -90px; }
    .pp__lineup-fren--2 { width: 168px; height: 168px; margin-right: -100px; }
    .pp__lineup-fren--3 { width: 185px; height: 185px; }
    .pp__lineup-fren--4 { width: 168px; height: 168px; margin-left: -92px; }
    .pp__lineup-fren--5 { width: 150px; height: 150px; margin-left: -95px; }
    .pp__lineup-fren--6 { width: 135px; height: 135px; margin-left: -88px; }

    .pp__about { padding: 48px 0 0 0; }
    .pp__about-inner { grid-template-columns: 1fr; }
    .pp__about-left { padding: 0 16px 32px 16px; }
    .pp__about-title-line1 { font-size: 18px; }
    .pp__about-title-line2 { font-size: 32px; }
    .pp__about-text { font-size: 14px; }
    .pp__about-img { max-height: 280px; max-width: 85%; margin: 0 auto; object-fit: contain; }

    .pp__features { padding: 40px 16px; }
    .pp__feature-heading { font-size: 22px; }

    .pp__cauldron-section { padding: 60px 16px; }
    .pp__cauldron-visual { height: auto; }
    .pp__cauldron-hero-img { max-width: 340px; }

    .pp__claim { padding: 40px 16px; }
    .pp__claim-right { padding: 24px 20px; }
    .pp__claim-heading { font-size: 24px; }

    .pp__media-section { padding: 40px 16px; }
    .pp__media-card { grid-template-columns: 1fr; }
    .pp__media-card-deco { justify-content: center; padding: 0 16px 16px; }

    .pp__kindness { padding: 0 16px 40px; }
    .pp__kindness-title { font-size: 32px; }
    .pp__kindness-fren { width: 180px; height: 180px; }


    .pp__marquee-fren { width: 70px; height: 70px; }



    .pp__faq-section { padding: 40px 16px 60px; }
    .pp__faq-title { font-size: 32px; }
    .pp__faq-q { font-size: 14px; padding: 16px 18px; }

    .pp__footer-inner { padding: 32px 16px 24px; }

    .pp__ticker {
      padding: 8px 0;
      margin-left: -16px;  /* match the hero's 16px mobile padding */
      margin-right: -16px;
    }

    .pp__ticker-item {
      font-size: 11px;
      letter-spacing: 0.06em;
    }

    .pp__ticker-fren {
      width: 40px;
      margin: 0 5px;
    }

    .pp__ticker-fren-layer {
      width: 40px;
      height: 40px;
      bottom: -18px;
    }

    .pp__text-marquee-item {
      font-size: 11px;
    }

    .pp__footer-marquee-item {
      font-size: 10px;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .pp__ticker-track,
    .pp__text-marquee-track,
    .pp__footer-marquee-track,
    .pp__sparkle-float,
    .pp__wisp,
    .pp__marquee-row,
    .pp__media-fren,
    .pp__kindness-fren,
    .pp__cauldron-glow,
    .pp__cauldron-hero-img {
      animation: none !important;
    }
  }
`;
