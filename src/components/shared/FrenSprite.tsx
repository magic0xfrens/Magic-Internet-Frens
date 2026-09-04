const FRENS_PATH = "/frens/";

/**
 * Robinhood-lime gradient (#d5fd51 family), seeded by the fren's traits so each
 * fren has a stable backdrop. Hue is LOCKED to the chartreuse-lime band (~66°–80°)
 * — only the angle and lightness drift a touch per fren, so every card reads as
 * the same bright brand lime, never generic green.
 */
function frenGradient(bodyIdx: number, faceIdx: number, itemIdx: number): string {
  const hash = (bodyIdx * 7919 + faceIdx * 6271 + itemIdx * 4813 + 101) >>> 0;
  const hue = 68 + (hash % 12);                 // 68°–79° — tight lime (d5fd51 ≈ 72°)
  const angle = 120 + ((hash >> 7) % 45);       // 120°–165°
  const lightTop = 64 + ((hash >> 5) % 8);      // 64–72% — bright lime (#d5fd51 ≈ 65%)
  const lightBot = 40 + ((hash >> 9) % 8);      // 40–48% — deeper lime, still vivid
  const top = `hsl(${hue} 96% ${lightTop}%)`;
  const bot = `hsl(${hue + 4} 88% ${lightBot}%)`;
  return `linear-gradient(${angle}deg, ${top}, ${bot})`;
}

interface FrenSpriteProps {
  bodyFile: string;
  faceFile: string;
  itemFile: string;
  bodyIdx: number;
  faceIdx: number;
  itemIdx: number;
  className?: string;
  alt?: string;
}

/**
 * Pixel-perfect layered NFT sprite renderer.
 * Renders face, body, and item SVGs as absolutely-positioned layers
 * over a deterministic gradient background.
 */
export default function FrenSprite({
  bodyFile,
  faceFile,
  itemFile,
  bodyIdx,
  faceIdx,
  itemIdx,
  className,
  alt,
}: FrenSpriteProps) {
  const bg = frenGradient(bodyIdx, faceIdx, itemIdx);

  return (
    <div
      className={className}
      style={{
        position: "relative",
        width: "100%",           // fill the container; aspect-ratio keeps it square
        aspectRatio: "1",
        background: bg,
        overflow: "hidden",
      }}
      role="img"
      aria-label={alt}
    >
      <img
        src={`${FRENS_PATH}${faceFile}`}
        alt=""
        style={layerStyle}
      />
      <img
        src={`${FRENS_PATH}${bodyFile}`}
        alt=""
        style={layerStyle}
      />
      <img
        src={`${FRENS_PATH}${itemFile}`}
        alt=""
        style={layerStyle}
      />
    </div>
  );
}

const layerStyle: React.CSSProperties = {
  position: "absolute",
  inset: 0,
  width: "100%",
  height: "100%",
  objectFit: "contain",
  imageRendering: "pixelated",
};
