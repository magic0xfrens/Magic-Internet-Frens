import type { CSSProperties, FC } from "react";

interface LoadingSkeletonProps {
  width?: string;
  height?: string;
  borderRadius?: string;
  className?: string;
  style?: CSSProperties;
}

const pulseKeyframes = `
@keyframes mif-skeleton-pulse {
  0% { opacity: 0.4; }
  50% { opacity: 0.7; }
  100% { opacity: 0.4; }
}
`;

let styleInjected = false;
function injectPulseStyle() {
  if (styleInjected) return;
  const tag = document.createElement("style");
  tag.textContent = pulseKeyframes;
  document.head.appendChild(tag);
  styleInjected = true;
}

const LoadingSkeleton: FC<LoadingSkeletonProps> = ({
  width = "100%",
  height = "20px",
  borderRadius = "var(--r-sm)",
  className = "",
  style,
}) => {
  injectPulseStyle();

  return (
    <div
      className={`loading-skeleton ${className}`}
      style={{
        width,
        height,
        borderRadius,
        background: "rgba(255, 255, 255, 0.06)",
        animation: "mif-skeleton-pulse 1.5s ease-in-out infinite",
        ...style,
      }}
    />
  );
};

export default LoadingSkeleton;
