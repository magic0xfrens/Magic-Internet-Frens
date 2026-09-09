import DOMPurify from "dompurify";

/**
 * Sanitize an SVG string before it reaches `dangerouslySetInnerHTML`.
 *
 * ── Why this exists, given the badge art is generated locally ──────────────
 * Every current caller builds its markup client-side from typed values —
 * addresses and numbers decoded by viem, never a `tokenURI` and never a free
 * text field — so none of them is exploitable today. That is a property of the
 * callers, not of the sink, and it is exactly the kind of property that quietly
 * stops holding: the first change that pipes a collection name, a trait string
 * or a hosted `image` field into badge art turns five inert call sites into
 * stored XSS, with nothing in between to catch it.
 *
 * SVG is a live document, not a picture. `<script>`, `on*` handlers,
 * `<foreignObject>` and `javascript:` hrefs all execute inside an inlined SVG,
 * which is why the docs renderer already sanitizes and these did not.
 *
 * `USE_PROFILES: { svg: true, svgFilters: true }` keeps the gradients, filters
 * and patterns the Liquidatoor artwork actually uses while dropping scripting.
 * `<image>` is kept because the badge composes same-origin `/images/liq-*.png`;
 * `href` is therefore allowed, but the URI policy blocks `javascript:` and any
 * other active scheme.
 *
 * ── `<animate>` is re-admitted, carefully ─────────────────────────────────
 * DOMPurify strips SMIL animation by default, and verifying that against the
 * real artwork is how this was caught: the badge's pulsing reticle uses
 * `<animate>`, so sanitizing without it would have silently shipped a dead
 * badge. It is stripped for a real reason, though —
 * `<animate attributeName="href" to="javascript:…">` mutates a static attribute
 * into an active one AFTER sanitization, which is the one attack a static
 * allowlist cannot see. So animation elements are allowed, and the hook below
 * removes any whose `attributeName` aims at a link or event attribute. That
 * keeps the motion and closes the hole the blanket ban was protecting.
 */

/** Attribute targets an animation must never be allowed to rewrite. */
const ANIMATABLE_DENY = /^(href|xlink:href|src|style|on\w+)$/i;

let hookInstalled = false;
function installHook() {
  if (hookInstalled) return;
  hookInstalled = true;
  DOMPurify.addHook("uponSanitizeElement", (node, data) => {
    if (data.tagName !== "animate" && data.tagName !== "set" && data.tagName !== "animatetransform") {
      return;
    }
    const target = (node as Element).getAttribute?.("attributeName") ?? "";
    if (ANIMATABLE_DENY.test(target)) node.parentNode?.removeChild(node);
  });
}

export function safeSvg(svg: string | undefined | null): string {
  if (!svg) return "";
  installHook();
  return DOMPurify.sanitize(svg, {
    USE_PROFILES: { svg: true, svgFilters: true },
    ADD_TAGS: ["image", "animate", "set", "animateTransform"],
    ADD_ATTR: [
      "href", "xlink:href",
      "attributeName", "values", "dur", "repeatCount", "begin", "keyTimes", "calcMode",
    ],
    FORBID_TAGS: ["script", "foreignObject", "iframe", "a"],
    FORBID_ATTR: ["onload", "onerror", "onclick", "onmouseover"],
  });
}
