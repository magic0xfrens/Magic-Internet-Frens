import { useEffect, useMemo, useRef, useState } from "react";
import { BODIES, FACES, GNOME_FACES, ELF_FACES, ITEMS, CLASS_ORDER } from "@/data/frens";
import { liquidatoorBadgeSVG, sampleLiquidatoorStats } from "@/lib/liquidatoorBadgeArt";

const FRENS_PATH = "/frens/";

// Build a random layered fren (face + body + item) for the "pop" collectibles.
// Avoids repeating the last class so the stream stays visibly varied.
let LAST_FREN_CLASS = "";
function randomFren() {
  let cls = CLASS_ORDER[Math.floor(Math.random() * CLASS_ORDER.length)];
  if (CLASS_ORDER.length > 1) {
    while (cls === LAST_FREN_CLASS) cls = CLASS_ORDER[Math.floor(Math.random() * CLASS_ORDER.length)];
  }
  LAST_FREN_CLASS = cls;
  const faces = cls === "Gnome" ? GNOME_FACES : cls === "Elf" ? ELF_FACES : FACES;
  return {
    face: faces[Math.floor(Math.random() * faces.length)].file,
    body: BODIES[cls][Math.floor(Math.random() * BODIES[cls].length)].file,
    item: ITEMS[cls][Math.floor(Math.random() * ITEMS[cls].length)].file,
  };
}

/**
 * ArchiveMachine — the MiFrens v4 "hook machine".
 *
 * A faithful port of the GnomeGacha hook-machine chrome (pink Uniswap-v4 tab,
 * cream notched card, side pill, crystal screen, segmented bar, pair chip),
 * stripped of all gacha game logic / portals / contracts so it's a pure,
 * self-contained showpiece. Recolored to the MiFrens palette and given a
 * quiet idle life: the crystal floats over a breathing glow, the dial sweeps,
 * the volume bar fills, and the pool LED pulses — so it reads "live" without a
 * wallet.
 *
 * The machine lives in a fixed 1148×1304 coordinate space (matching the
 * original artwork) and is scaled to fit its container via a ResizeObserver.
 */

const SCENE_W = 1148;
const SCENE_H = 1304;
const CROP_TOP = 108; // trim empty space above the pink tab
const CROP_BOTTOM = 44; // trim empty space below the card

// The notched card silhouette (rounded top corners + angled bottom-right cut +
// the little connector bumps on the left edge). Shared by the shadow + fill.
const CARD_PATH =
  "M63,0 L826,0 A63,63 0 0 1 889,63 L889,706 Q889,724 877,737 L696,926 Q684,939 666,939 " +
  "L63,939 A63,63 0 0 1 0,876 L0,242 A7,7 0 0 1 7,235 L9,235 A7,7 0 0 0 16,228 L16,214 " +
  "A7,7 0 0 0 9,207 L7,207 A7,7 0 0 1 0,200 L0,179 A7,7 0 0 1 7,172 L9,172 A7,7 0 0 0 16,165 " +
  "L16,151 A7,7 0 0 0 9,144 L7,144 A7,7 0 0 1 0,137 L0,119.5 A7,7 0 0 1 7,112.5 L9,112.5 " +
  "A7,7 0 0 0 16,105.5 L16,91.5 A7,7 0 0 0 9,84.5 L7,84.5 A7,7 0 0 1 0,77.5 L0,63 A63,63 0 0 1 63,0 Z";

const DOTS = [
  { left: 0, top: 0 },
  { left: 53, top: 0 },
  { left: 0, top: 62 },
  { left: 53, top: 62 },
  { left: 0, top: 124 },
  { left: 53, top: 124 },
];

const rand = (a: number, b: number) => a + Math.random() * (b - a);

// Weighted emission pool — mostly forged frens, rarely a liquidation badge.
const KIND_POOL = [
  "nft", "nft", "nft", "nft", "nft", "nft", "nft", "nft", "nft", "nft",
  "liqShort", "liqLong",
] as const;
type EmitKind = (typeof KIND_POOL)[number];

interface Particle {
  id: number;
  kind: EmitKind;
  fren?: ReturnType<typeof randomFren>;
  svg?: string;
  ax: number;   // apex x offset (peak of the launch arc)
  peak: number; // apex y (negative = up)
  fx: number;   // final x drift as it falls
  fall: number; // final y (positive = down, past the card bottom)
  rot: number;  // final rotation
  dur: number;  // seconds
  size: number; // px width scaler
}

let PARTICLE_ID = 0;

function makeParticle(): Particle {
  const kind = KIND_POOL[Math.floor(Math.random() * KIND_POOL.length)];
  const ax = rand(-260, 260);
  const p: Particle = {
    id: PARTICLE_ID++,
    kind,
    ax,
    peak: -rand(180, 360),
    fx: ax + rand(-180, 180),
    fall: rand(540, 760),
    rot: rand(-70, 70),
    dur: rand(3.8, 5.4),
    size: rand(0.85, 1.15),
  };
  if (kind === "nft") {
    p.fren = randomFren();
  } else {
    const side = kind === "liqShort" ? "short" : "long";
    p.svg = liquidatoorBadgeSVG(
      sampleLiquidatoorStats(side, 200 + Math.floor(Math.random() * 99), `/images/liq-${side}.webp`),
    );
  }
  return p;
}

export default function ArchiveMachine() {
  const boxRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(0.34);
  const [shaking, setShaking] = useState(false);
  const [visible, setVisible] = useState(false);
  const [particles, setParticles] = useState<Particle[]>([]);

  useEffect(() => {
    const el = boxRef.current;
    if (!el) return;
    const fit = () => setScale(Math.max(0.18, el.clientWidth / SCENE_W));
    fit();
    const ro = new ResizeObserver(fit);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // Only run the emitter while the machine is on screen.
  useEffect(() => {
    const el = boxRef.current;
    if (!el) return;
    const io = new IntersectionObserver(
      ([entry]) => setVisible(entry.isIntersecting),
      { threshold: 0.35 },
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);

  // Continuous stream: one collectible pops out at a random beat, arcs up, then
  // falls away under gravity and fades — so it's alive and never sits stale.
  useEffect(() => {
    if (!visible) { setParticles([]); return; }
    let spawnTimer: ReturnType<typeof setTimeout>;
    let shakeTimer: ReturnType<typeof setTimeout>;
    const spawn = () => {
      const p = makeParticle();
      setParticles((list) => [...list, p]);
      // the crystal jolts each time it spits one out
      setShaking(true);
      clearTimeout(shakeTimer);
      shakeTimer = setTimeout(() => setShaking(false), 420);
      // retire it once its arc finishes
      setTimeout(() => setParticles((list) => list.filter((x) => x.id !== p.id)), p.dur * 1000 + 200);
      spawnTimer = setTimeout(spawn, rand(650, 1400));
    };
    spawnTimer = setTimeout(spawn, 250);
    return () => { clearTimeout(spawnTimer); clearTimeout(shakeTimer); };
  }, [visible]);

  const viewH = (SCENE_H - CROP_TOP - CROP_BOTTOM) * scale;

  return (
    <div className="mifm" ref={boxRef}>
      <div className="mifm-fitbox" style={{ height: viewH }}>
        <div className="mifm-fit" style={{ transform: `scale(${scale})`, top: -CROP_TOP * scale }}>
          <div className="mifm-scene">
            {/* connector wires from the side pill into the card */}
            <svg className="mifm-wires" width={1148} height={1304} viewBox="0 0 1148 1304" fill="none">
              <g strokeLinecap="butt" strokeLinejoin="round" fill="none">
                <path d="M130,500 L130,433 Q130,406.5 157,406.5 L214,406.5" stroke="#2A1F54" strokeWidth={32} />
                <path d="M130,743 L130,810 Q130,836.5 157,836.5 L214,836.5" stroke="#2A1F54" strokeWidth={32} />
                <path d="M130,500 L130,433 Q130,406.5 157,406.5 L214,406.5" stroke="#efe7ff" strokeWidth={23} />
                <path d="M130,743 L130,810 Q130,836.5 157,836.5 L214,836.5" stroke="#efe7ff" strokeWidth={23} />
              </g>
            </svg>

            {/* pink Uniswap-v4 tab */}
            <div className="mifm-tabTop">
              <a className="mifm-hookLink" href="https://app.uniswap.org/explore" target="_blank" rel="noreferrer">
                <span className="mifm-uniMark" aria-hidden="true" />
                <span className="mifm-hookText">
                  <small>Powered by Uniswap v4</small>
                  CauldronHook.sol
                </span>
              </a>
              <div className="mifm-ops" aria-hidden="true">
                <span className="mifm-opbtn mifm-minus" />
                <span className="mifm-opsDiv" />
                <span className="mifm-opbtn mifm-plus" />
              </div>
            </div>
            {/* neck — plugs the tab into the card. Its walls flare outward with a
                concave cove at the TOP, so the tab bottom flows smoothly down into the
                vertical walls; the card (z5) meets the walls at the bottom. */}
            <svg className="mifm-neck" width={100} height={30} viewBox="0 0 100 30" fill="none">
              <path d="M18,24 L18,16 Q18,6 8,6 L8,0 L92,0 L92,6 Q82,6 82,16 L82,24 Z" fill="#D5FD51" />
              <path d="M18,24 L18,16 Q18,6 8,6" stroke="#2A1F54" strokeWidth={4.5} fill="none" />
              <path d="M82,24 L82,16 Q82,6 92,6" stroke="#2A1F54" strokeWidth={4.5} fill="none" />
            </svg>

            {/* side pill */}
            <div className="mifm-tabSide">
              <span>liquidate</span>
              <span>InSwap()</span>
            </div>

            {/* the card */}
            <div className="mifm-card">
              <svg width={910} height={955} viewBox="0 0 910 955">
                <path d={CARD_PATH} transform="translate(17.25,12.25)" fill="#2A1F54" />
                <path d={CARD_PATH} transform="translate(2.25,2.25)" fill="#F5EFE1" stroke="#2A1F54" strokeWidth={4.5} />
              </svg>

              <div className="mifm-face">
                <div className="mifm-dots" aria-hidden="true">
                  {DOTS.map((d, i) => (
                    <i key={i} style={{ left: d.left, top: d.top }} />
                  ))}
                </div>
                <div className="mifm-toggle mifm-on" aria-hidden="true">
                  <i />
                </div>
                <div className="mifm-dial" aria-hidden="true" />

                <div className="mifm-stage">
                  <span className="mifm-glow" aria-hidden="true" />
                  {/* animated WebP (348KB) with GIF fallback (2.2MB, old browsers only) */}
                  <picture>
                    <source srcSet="/images/crystal.webp" type="image/webp" />
                    <img
                      className={`mifm-crystal${shaking ? " mifm-crystal--shake" : ""}`}
                      src="/images/crystal.gif"
                      alt="An on-chain collectible forming inside the MiFrens hook"
                    />
                  </picture>

                  {/* eruption — collectibles pop out one at a time, arc up, then
                      fall away under gravity and fade (continuous, never stale) */}
                  {visible && (
                    <div className="mifm-emits" aria-hidden="true">
                      {particles.map((p) => (
                        <div
                          key={p.id}
                          className={`mifm-emit ${p.kind === "nft" ? "mifm-emit--fren" : "mifm-emit--badge"}`}
                          style={{
                            animationDuration: `${p.dur}s`,
                            ['--ax' as string]: `${p.ax}px`,
                            ['--peak' as string]: `${p.peak}px`,
                            ['--fx' as string]: `${p.fx}px`,
                            ['--fall' as string]: `${p.fall}px`,
                            ['--rot' as string]: `${p.rot}deg`,
                            ['--sz' as string]: `${p.size}`,
                          }}
                        >
                          {p.kind === "nft" ? (
                            <div className="mifm-emit-fren">
                              <img src={`${FRENS_PATH}${p.fren!.face}`} alt="" />
                              <img src={`${FRENS_PATH}${p.fren!.body}`} alt="" />
                              <img src={`${FRENS_PATH}${p.fren!.item}`} alt="" />
                            </div>
                          ) : (
                            <div className="mifm-emit-badge" dangerouslySetInnerHTML={{ __html: p.svg! }} />
                          )}
                        </div>
                      ))}
                    </div>
                  )}

                  <span className="mifm-live" aria-hidden="true">LIVE</span>
                </div>

                <div className="mifm-segbar" aria-hidden="true">
                  <i className="mifm-a" />
                  <i className="mifm-b" />
                </div>
                <div className="mifm-pool" aria-hidden="true">
                  <span className="mifm-pooldot" />
                  <span className="mifm-lbl">ETH / MIFRENS</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
      <style>{MACHINE_CSS}</style>
    </div>
  );
}

const MACHINE_CSS = `
  .mifm {
    --ink: #2A1F54;
    --paper: #ffffff;
    --cream: #F5EFE1;
    --pink: #f4b8fb;
    --lime: #D5FD51;
    --lilac: #7C5CFC;
    --orange: #ef8757;
    --unipink: #ff007a;
    --bw: 4.5px;
    width: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    color: var(--ink);
    font-family: "Fredoka", sans-serif;
  }
  .mifm-fitbox { position: relative; width: 100%; overflow: visible; }
  .mifm-fit {
    position: absolute;
    left: 0; top: 0;
    width: 1148px;
    transform-origin: top left;
  }
  .mifm-scene { position: relative; width: 1148px; height: 1304px; }

  /* pink tab */
  .mifm-tabTop {
    position: absolute;
    left: 181px; top: 116px;
    width: 658px; height: 182px;
    background: var(--lime);
    border: var(--bw) solid var(--ink);
    border-radius: var(--r-lg);
    box-shadow: 15px 15px 0 var(--ink);
    z-index: 3;
    padding: 0 34px;
    display: flex; align-items: center; justify-content: space-between; gap: 18px;
  }
  .mifm-neck { position: absolute; left: 234px; top: 290px; z-index: 4; }
  .mifm-hookLink {
    display: inline-flex; align-items: center; gap: 16px;
    text-decoration: none; color: var(--ink); min-width: 0;
  }
  .mifm-hookText {
    display: flex; flex-direction: column; line-height: 1.05;
    font-family: "DM Mono", ui-monospace, "SF Mono", monospace;
    font-size: 33px; font-weight: 500; letter-spacing: -0.02em; white-space: nowrap;
  }
  .mifm-hookText small {
    font-family: "DM Mono", monospace;
    font-size: 13px; font-weight: 500; letter-spacing: 0.05em;
    text-transform: uppercase; color: var(--ink); opacity: 0.6; margin-bottom: 6px;
  }
  .mifm-hookLink:hover .mifm-hookText { text-decoration: underline; text-underline-offset: 4px; }
  .mifm-uniMark {
    width: 64px; height: 64px; flex: none;
    border: var(--bw) solid var(--ink);
    border-radius: 50%;
    box-shadow: 4px 4px 0 var(--ink);
    background: var(--paper) url('/uniswap-logo.svg') center / 82% no-repeat;
  }
  .mifm-ops {
    display: flex; align-items: center; flex: none;
    background: var(--paper);
    border: var(--bw) solid var(--ink);
    border-radius: var(--r-chip);
    box-shadow: 4px 4px 0 var(--ink);
    overflow: hidden;
  }
  .mifm-opsDiv { width: 3px; align-self: stretch; background: var(--ink); }
  .mifm-opbtn { position: relative; width: 60px; height: 58px; }
  .mifm-opbtn::before {
    content: ''; position: absolute; left: 50%; top: 50%;
    width: 40%; height: 4.5px; border-radius: 3px; background: var(--ink);
    transform: translate(-50%, -50%);
  }
  .mifm-plus::after {
    content: ''; position: absolute; left: 50%; top: 50%;
    width: 4.5px; height: 40%; border-radius: 3px; background: var(--ink);
    transform: translate(-50%, -50%);
  }

  /* side pill */
  .mifm-tabSide {
    position: absolute;
    left: 71px; top: 438px;
    width: 103px; height: 367px;
    background: var(--lime);
    border: var(--bw) solid var(--ink);
    border-radius: var(--r-chip);
    box-shadow: -15px 0 0 var(--ink);
    z-index: 1;
    display: flex; flex-direction: column; align-items: center; justify-content: space-between;
    padding: 34px 0 32px;
    color: var(--ink);
  }
  .mifm-tabSide span {
    writing-mode: vertical-rl;
    font-family: "DM Mono", ui-monospace, "SF Mono", monospace;
    font-size: 30px; font-weight: 500; letter-spacing: -0.01em; line-height: 1;
  }

  .mifm-wires { position: absolute; left: 0; top: 0; z-index: 0; }

  /* card */
  .mifm-card { position: absolute; left: 191px; top: 308px; width: 910px; height: 955px; z-index: 5; }
  .mifm-card > svg { position: absolute; left: 0; top: 0; }
  .mifm-face { position: absolute; left: 0; top: 0; width: 889px; height: 939px; }

  .mifm-dots { position: absolute; left: 51px; top: 90.5px; }
  .mifm-dots i { position: absolute; width: 19px; height: 19px; border-radius: 50%; background: var(--ink); }

  .mifm-toggle {
    position: absolute; left: 565px; top: 63px;
    width: 142px; height: 78px;
    border: var(--bw) solid var(--ink); border-radius: var(--r-chip);
    background: var(--paper);
    display: flex; align-items: center; padding: 10px;
  }
  .mifm-toggle i { width: 51px; height: 51px; border-radius: 50%; background: var(--ink); transition: 0.2s; }
  .mifm-toggle.mifm-on { justify-content: flex-end; }

  .mifm-dial {
    position: absolute; left: 739px; top: 50px;
    width: 102px; height: 102px; border-radius: 50%; background: var(--ink);
  }
  .mifm-dial::after {
    content: ''; position: absolute; left: 50%; top: 14px;
    width: 6.5px; height: 37px; background: var(--paper);
    transform-origin: 50% 100%;
    transform: translateX(-50%) rotate(-45deg);
    animation: mifm-dial 6s ease-in-out infinite;
  }
  @keyframes mifm-dial {
    0%, 100% { transform: translateX(-50%) rotate(-42deg); }
    50%      { transform: translateX(-50%) rotate(120deg); }
  }

  /* crystal screen */
  .mifm-stage {
    position: absolute; left: 30px; top: 150px;
    width: 829px; height: 545px;
    display: grid; place-items: center;
    overflow: visible;
  }
  /* picture wrapper must not become the grid child — keep the img as the child */
  .mifm-stage picture { display: contents; }
  .mifm-glow {
    position: absolute; left: 50%; top: 54%;
    width: 560px; height: 560px; transform: translate(-50%, -50%);
    border-radius: 50%;
    background: radial-gradient(circle, rgba(124,92,252,0.42) 0%, rgba(213,253,81,0.10) 42%, transparent 68%);
    filter: blur(6px);
    animation: mifm-glow 3.6s ease-in-out infinite;
  }
  @keyframes mifm-glow {
    0%, 100% { opacity: 0.75; transform: translate(-50%, -50%) scale(0.96); }
    50%      { opacity: 1;    transform: translate(-50%, -50%) scale(1.06); }
  }
  .mifm-crystal {
    position: relative;
    width: 100%; height: 100%;
    object-fit: contain; object-position: bottom center;
    transform: translate(-52px, -90px) scale(1);
    transform-origin: 50% 100%;
    animation: mifm-float 5s ease-in-out infinite;
    filter: drop-shadow(0 18px 26px rgba(42,31,84,0.28));
  }
  @keyframes mifm-float {
    0%, 100% { transform: translate(-52px, -90px) scale(1); }
    50%      { transform: translate(-52px, -104px) scale(1); }
  }
  /* violent wiggle when the crystal erupts a batch */
  .mifm-crystal--shake { animation: mifm-shake 0.42s ease-in-out 3; }
  @keyframes mifm-shake {
    0%   { transform: translate(-52px, -90px) scale(1) rotate(0deg); }
    10%  { transform: translate(-72px, -98px) scale(1.08) rotate(-15deg); }
    24%  { transform: translate(-32px, -80px) scale(1.11) rotate(15deg); }
    40%  { transform: translate(-70px, -100px) scale(1.09) rotate(-12deg); }
    56%  { transform: translate(-36px, -82px) scale(1.08) rotate(12deg); }
    72%  { transform: translate(-62px, -94px) scale(1.05) rotate(-7deg); }
    88%  { transform: translate(-44px, -86px) scale(1.03) rotate(5deg); }
    100% { transform: translate(-52px, -90px) scale(1) rotate(0deg); }
  }

  /* ── eruption: collectibles launch up with energy, then fall away + fade ── */
  .mifm-emits {
    position: absolute; left: 50%; top: 44%;
    width: 0; height: 0; z-index: 3; pointer-events: none;
  }
  .mifm-emit {
    position: absolute; left: 0; top: 0;
    animation-name: mifm-emit;
    animation-fill-mode: both;
    will-change: transform, opacity;
  }
  /* liquidatoor trophy — the exact badge-lab poster, scaled down */
  .mifm-emit--badge { width: 240px; }
  .mifm-emit-badge svg {
    width: 100%; height: 100%; display: block; border-radius: var(--r-md);
    filter: drop-shadow(0 16px 22px rgba(10,7,24,0.55));
  }
  /* forged fren — bare pixel art, no card frame */
  .mifm-emit--fren { width: 210px; }
  .mifm-emit-fren {
    position: relative; width: 210px; height: 210px;
  }
  .mifm-emit-fren img {
    position: absolute; inset: 0; width: 100%; height: 100%;
    object-fit: contain; image-rendering: pixelated;
    filter: drop-shadow(0 12px 14px rgba(42,31,84,0.45));
  }
  /* launch decelerates up to the apex, then gravity accelerates the fall */
  @keyframes mifm-emit {
    0%   { opacity: 0;
           transform: translate(-50%, -50%) translate(0, 0) scale(calc(var(--sz) * 0.2)) rotate(0deg);
           animation-timing-function: cubic-bezier(0.12, 0.66, 0.28, 1); }
    8%   { opacity: 1; }
    38%  { transform: translate(-50%, -50%) translate(var(--ax), var(--peak)) scale(var(--sz)) rotate(calc(var(--rot) * 0.28));
           animation-timing-function: cubic-bezier(0.5, 0.02, 0.86, 0.4); }
    86%  { opacity: 1; }
    100% { opacity: 0;
           transform: translate(-50%, -50%) translate(var(--fx), var(--fall)) scale(calc(var(--sz) * 0.86)) rotate(var(--rot)); }
  }

  .mifm-live {
    position: absolute; top: 6px; right: 18px;
    display: inline-flex; align-items: center; gap: 9px;
    font-family: "DM Mono", monospace;
    font-size: 22px; font-weight: 500; letter-spacing: 0.14em;
    color: #b23c00;
  }
  .mifm-live::before {
    content: ''; width: 14px; height: 14px; border-radius: 50%;
    background: #ff4d2e; box-shadow: 0 0 0 0 rgba(255,77,46,0.6);
    animation: mifm-led 1.6s ease-out infinite;
  }
  @keyframes mifm-led {
    0%   { box-shadow: 0 0 0 0 rgba(255,77,46,0.55); }
    100% { box-shadow: 0 0 0 16px rgba(255,77,46,0); }
  }

  /* segmented volume bar */
  .mifm-segbar {
    position: absolute; left: 38px; top: 695px;
    width: 600px; height: 45px;
    border: var(--bw) solid var(--ink); border-radius: var(--r-chip);
    background: var(--paper);
    display: flex; align-items: center; gap: 12px; padding: 0 8.5px;
    overflow: hidden;
  }
  .mifm-segbar i { height: 19px; border-radius: var(--r-chip); }
  .mifm-segbar .mifm-a { background: var(--lilac); width: 150px; animation: mifm-fill 5.5s ease-in-out infinite; }
  .mifm-segbar .mifm-b { background: var(--orange); flex: 1; }
  @keyframes mifm-fill {
    0%, 100% { width: 120px; }
    50%      { width: 400px; }
  }

  /* pool / pair chip */
  .mifm-pool {
    position: absolute; left: 36px; top: 786px;
    width: 520px; height: 100px;
    border: var(--bw) solid var(--ink); border-radius: var(--r-md);
    background: var(--paper);
    display: flex; align-items: center; padding: 0 30px;
  }
  .mifm-pooldot {
    width: 26px; height: 26px; border-radius: 50%; flex: none;
    background: var(--lime); border: 3px solid var(--ink);
    box-shadow: 0 0 0 0 rgba(213,253,81,0.7);
    animation: mifm-poolled 2.2s ease-out infinite;
  }
  @keyframes mifm-poolled {
    0%   { box-shadow: 0 0 0 0 rgba(213,253,81,0.7); }
    100% { box-shadow: 0 0 0 14px rgba(213,253,81,0); }
  }
  .mifm-lbl {
    flex: 1; text-align: center;
    font-size: 50px; font-weight: 600; letter-spacing: -0.01em; line-height: 1;
    padding-left: 14px; white-space: nowrap; color: var(--ink);
  }

  @media (prefers-reduced-motion: reduce) {
    .mifm-dial::after, .mifm-glow, .mifm-crystal, .mifm-crystal--shake, .mifm-live::before,
    .mifm-segbar .mifm-a, .mifm-pooldot { animation: none; }
    .mifm-emits { display: none; }
  }
`;
