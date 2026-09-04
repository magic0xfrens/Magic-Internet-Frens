/**
 * The single definition of site navigation, shared by the landing top bar
 * (`AppHeader`) and the app left rail (`AppSidebar`) so the two can never
 * drift out of sync.
 */

/** Which live counter, if any, a sub-item shows next to its label. */
export type BadgeKey = "perps" | "proposals" | "gen" | "frens" | "collectibles";

export interface SubNavItem {
  label: string;
  /** Value of the `?v=` search param this item selects. */
  view: string;
  badge?: BadgeKey;
  /** Renders the label in lime when its counter is non-zero. */
  hot?: boolean;
  /** Hidden until a generation is summoned — the view is empty before that. */
  needsSummoned?: boolean;
}

export interface NavItem {
  label: string;
  path: string;
  /** Rendered nested under the item while its route is active. */
  children?: SubNavItem[];
}

export const NAV_ITEMS: NavItem[] = [
  { label: "HOME", path: "/" },
  {
    label: "MI FRENS",
    path: "/mi-frens",
    children: [
      { label: "Frens", view: "frens", badge: "frens" },
      { label: "Collectibles", view: "collectibles", badge: "collectibles" },
      { label: "Floors", view: "floors" },
    ],
  },
  {
    label: "THE CAULDRON",
    path: "/cauldrons",
    children: [
      { label: "The Brew", view: "reactor" },
      { label: "Leverage", view: "leverage", badge: "perps", hot: true, needsSummoned: true },
      // Staking funds the perps, so it sits next to Leverage — but it is a
      // different intent (passive yield, not opening a position) and was
      // previously buried below the position form where nobody scrolled to it.
      { label: "Stake", view: "stake", needsSummoned: true },
      { label: "Governance", view: "governance", badge: "proposals" },
      { label: "Lineage", view: "lineage", badge: "gen" },
    ],
  },
  { label: "DOCS", path: "/docs" },
];

/**
 * Route chunk prefetchers — fired on nav hover/focus so the lazy chunk is
 * already in cache by the time the user clicks (navigation feels instant).
 * Vite dedupes the dynamic import, so calling it early just warms the cache.
 */
const PREFETCH: Record<string, () => Promise<unknown>> = {
  "/": () => import("@/components/preview/HomePreview"),
  "/mi-frens": () => import("@/components/wizards/MyWizards"),
  "/cauldrons": () => import("@/components/cauldron/TheCauldron"),
  "/token": () => import("@/components/token/Token"),
  "/docs": () => import("@/components/docs/Docs"),
};

const prefetched = new Set<string>();

export function prefetchRoute(path: string) {
  if (prefetched.has(path)) return;
  prefetched.add(path);
  PREFETCH[path]?.().catch(() => prefetched.delete(path));
}

export function truncateAddress(addr: string): string {
  if (!addr || addr.length < 12) return addr;
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

/**
 * Routes that render the app shell (left rail) instead of the landing header.
 * Deliberately just the three dark product surfaces — `/token` is a light page
 * and `/badge-lab` is a standalone dev lab with its own full-screen layout, so
 * both keep the top bar.
 */
export const APP_ROUTES = ["/mi-frens", "/cauldrons", "/docs"];

export function isAppRoute(pathname: string): boolean {
  return APP_ROUTES.some((p) => pathname.startsWith(p));
}
