/**
 * The app used to run on `HashRouter`, so every URL we ever shipped looks like
 * `https://www.mifrens.xyz/#/cauldrons`. Google never indexes past the `#`, so
 * the whole site was a single crawlable URL — no sub-pages, no sitelinks. The
 * router now uses real paths.
 *
 * Those old links are still out there: bookmarks, X posts, Discord, and the
 * X OAuth callback registered on the developer app. This rewrites them to the
 * real path in place, BEFORE React mounts, so the router sees the right
 * location on its very first render and nothing flashes the home page first.
 *
 * `replaceState` (not `assign`) — no extra history entry, no reload, and the
 * back button still lands where the user expects.
 */
export function rewriteLegacyHashUrl(): void {
  if (typeof window === "undefined") return;

  const { hash } = window.location;
  // Only our own router hashes. A bare `#section` anchor (the docs page uses
  // them for deep-linked headings) must be left completely alone.
  if (!hash.startsWith("#/")) return;

  // `#/x-callback?code=…&state=…` → path `/x-callback`, search `?code=…&state=…`.
  // The OAuth params live inside the hash, so they have to come along or
  // `useSearchParams` reads an empty callback and bounces the user home.
  const target = hash.slice(1);
  if (!target.startsWith("/")) return;

  window.history.replaceState(window.history.state, "", target);
}
