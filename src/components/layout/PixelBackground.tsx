/**
 * PixelBackground -- Animated SVG grid of colored pixel blocks.
 *
 * Theme: Light Wizard -- warm parchment tones, muted purples,
 * gold/amber accents, lavender highlights.
 *
 * Pure SVG patterns + CSS animation -- no canvas, no JS frames.
 */
export function PixelBackground() {
  return (
    <div className="pixel-bg" aria-hidden="true">
      {/* Layer 1: Main pixel grid -- slow diagonal drift */}
      <svg
        className="pixel-bg__layer pixel-bg__layer--1"
        viewBox="0 0 256 256"
        preserveAspectRatio="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <defs>
          <pattern
            id="pxBlockGrid1"
            x="0"
            y="0"
            width="32"
            height="32"
            patternUnits="userSpaceOnUse"
          >
            {/* Row 0 */}
            <rect x="0"  y="0"  width="8" height="8" fill="#EDE8DE" />
            <rect x="8"  y="0"  width="8" height="8" fill="#F0EBE0" />
            <rect x="16" y="0"  width="8" height="8" fill="#ECE6DA" />
            <rect x="24" y="0"  width="8" height="8" fill="#EFE9DF" />
            {/* Row 1 */}
            <rect x="0"  y="8"  width="8" height="8" fill="#F1ECE2" />
            <rect x="8"  y="8"  width="8" height="8" fill="#EBE5D9" />
            <rect x="16" y="8"  width="8" height="8" fill="#EDE7DD" />
            <rect x="24" y="8"  width="8" height="8" fill="#F0EAE0" />
            {/* Row 2 */}
            <rect x="0"  y="16" width="8" height="8" fill="#ECE6DC" />
            <rect x="8"  y="16" width="8" height="8" fill="#F2ECE2" />
            <rect x="16" y="16" width="8" height="8" fill="#EEE8DE" />
            <rect x="24" y="16" width="8" height="8" fill="#EAE4DA" />
            {/* Row 3 */}
            <rect x="0"  y="24" width="8" height="8" fill="#F0EAE0" />
            <rect x="8"  y="24" width="8" height="8" fill="#ECE6DC" />
            <rect x="16" y="24" width="8" height="8" fill="#F1EBE1" />
            <rect x="24" y="24" width="8" height="8" fill="#EDE7DD" />

            {/* Accent blocks */}
            <rect x="8"  y="0"  width="8" height="8" fill="#D8D0C4" opacity="0.3" />
            <rect x="24" y="16" width="8" height="8" fill="#DDD5C9" opacity="0.25" />
          </pattern>
        </defs>
        <rect width="256" height="256" fill="url(#pxBlockGrid1)" />
      </svg>

      {/* Layer 2: Accent grid with gold/purple accents */}
      <svg
        className="pixel-bg__layer pixel-bg__layer--2"
        viewBox="0 0 256 256"
        preserveAspectRatio="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <defs>
          <pattern
            id="pxBlockGrid2"
            x="0"
            y="0"
            width="64"
            height="64"
            patternUnits="userSpaceOnUse"
          >
            {/* Purple accents */}
            <rect x="0"  y="0"  width="8" height="8" fill="#7C5CFC" opacity="0.04" />
            <rect x="24" y="8"  width="8" height="8" fill="#6d28d9" opacity="0.03" />
            <rect x="48" y="24" width="8" height="8" fill="#7C5CFC" opacity="0.03" />

            {/* Gold / Bitcoin orange accents */}
            <rect x="16" y="32" width="8" height="8" fill="#d5fd51" opacity="0.04" />
            <rect x="40" y="48" width="8" height="8" fill="#e8a340" opacity="0.03" />
            <rect x="56" y="0"  width="8" height="8" fill="#d5fd51" opacity="0.02" />

            {/* Warm amber */}
            <rect x="32" y="16" width="8" height="8" fill="#d4a050" opacity="0.03" />
            <rect x="8"  y="48" width="8" height="8" fill="#7C5CFC" opacity="0.02" />

            {/* Deep violet */}
            <rect x="48" y="56" width="8" height="8" fill="#8b5cf6" opacity="0.03" />

            {/* Warm red accent */}
            <rect x="0"  y="56" width="8" height="8" fill="#ff4d6d" opacity="0.02" />

            {/* Brighter highlights */}
            <rect x="16" y="16" width="8" height="8" fill="#7C5CFC" opacity="0.04" />
            <rect x="40" y="40" width="8" height="8" fill="#d5fd51" opacity="0.04" />
          </pattern>
        </defs>
        <rect width="256" height="256" fill="url(#pxBlockGrid2)" />
      </svg>

      {/* Layer 3: Sparse bright pixel highlights -- twinkle */}
      <svg
        className="pixel-bg__layer pixel-bg__layer--3"
        viewBox="0 0 512 512"
        preserveAspectRatio="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <defs>
          <pattern
            id="pxHighlights"
            x="0"
            y="0"
            width="128"
            height="128"
            patternUnits="userSpaceOnUse"
          >
            <rect x="12"  y="20"  width="8" height="8" fill="#d5fd51" opacity="0.06" />
            <rect x="60"  y="44"  width="8" height="8" fill="#7C5CFC" opacity="0.04" />
            <rect x="100" y="12"  width="8" height="8" fill="#e8a340" opacity="0.05" />
            <rect x="36"  y="84"  width="8" height="8" fill="#7c3aed" opacity="0.04" />
            <rect x="84"  y="100" width="8" height="8" fill="#d5fd51" opacity="0.04" />
            <rect x="116" y="68"  width="8" height="8" fill="#7C5CFC" opacity="0.04" />
            <rect x="52"  y="112" width="8" height="8" fill="#8b5cf6" opacity="0.03" />
            <rect x="4"   y="60"  width="8" height="8" fill="#d4a050" opacity="0.03" />
          </pattern>
        </defs>
        <rect width="512" height="512" fill="url(#pxHighlights)" />
      </svg>

      {/* Layer 4: Grid lines */}
      <svg
        className="pixel-bg__grid-lines"
        viewBox="0 0 64 64"
        preserveAspectRatio="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <defs>
          <pattern
            id="pxGridLines"
            x="0"
            y="0"
            width="8"
            height="8"
            patternUnits="userSpaceOnUse"
          >
            <rect
              x="0"
              y="0"
              width="8"
              height="8"
              fill="none"
              stroke="rgba(42,31,84,0.02)"
              strokeWidth="0.25"
            />
          </pattern>
        </defs>
        <rect width="64" height="64" fill="url(#pxGridLines)" />
      </svg>

      <style>{pixelBgStyles}</style>
    </div>
  );
}

const pixelBgStyles = `
  .pixel-bg {
    position: fixed;
    inset: 0;
    z-index: 0;
    pointer-events: none;
    overflow: hidden;
    background: #F5F0E8;
  }

  .pixel-bg__layer {
    position: absolute;
    image-rendering: pixelated;
    image-rendering: crisp-edges;
  }

  .pixel-bg__layer--1 {
    inset: -50%;
    width: 200%;
    height: 200%;
    animation: pxGridDrift1 80s linear infinite;
  }

  .pixel-bg__layer--2 {
    inset: -50%;
    width: 200%;
    height: 200%;
    animation: pxGridDrift2 60s linear infinite;
  }

  .pixel-bg__layer--3 {
    inset: -25%;
    width: 150%;
    height: 150%;
    animation: pxGridDrift3 100s linear infinite, pxPulse 8s ease-in-out infinite alternate;
  }

  .pixel-bg__grid-lines {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    opacity: 0.5;
    image-rendering: pixelated;
    image-rendering: crisp-edges;
  }

  @keyframes pxGridDrift1 {
    0%   { transform: translate(0, 0); }
    100% { transform: translate(-32px, -32px); }
  }

  @keyframes pxGridDrift2 {
    0%   { transform: translate(0, 0); }
    100% { transform: translate(64px, -64px); }
  }

  @keyframes pxGridDrift3 {
    0%   { transform: translate(0, 0); }
    100% { transform: translate(-128px, 128px); }
  }

  @keyframes pxPulse {
    0%   { opacity: 0.5; }
    100% { opacity: 1; }
  }

  @media (prefers-reduced-motion: reduce) {
    .pixel-bg__layer,
    .pixel-bg__layer--3 {
      animation: none !important;
    }
  }
`;
