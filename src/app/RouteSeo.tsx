import { useEffect } from "react";
import { useLocation } from "react-router-dom";
import seo from "./seo-routes.json";

/**
 * Keeps `<title>`, the meta description and the canonical link in sync with the
 * current route.
 *
 * The build prerenders one HTML file per route with these already baked in
 * (see `scripts/prerender-seo.mjs`), which is what a crawler hitting the URL
 * cold actually reads. This handles the other half: a soft client navigation
 * never re-reads the document head, so without it every in-app click left the
 * landing page's title sitting in the tab — and in the history entry that the
 * browser later offers back as a bookmark suggestion.
 */

type SeoRoute = (typeof seo.routes)[number];

const BY_PATH = new Map<string, SeoRoute>(seo.routes.map((r) => [r.path, r]));
const NOINDEX = new Set<string>(seo.noindex);

function setMeta(selector: string, attr: "name" | "property", key: string, content: string) {
  let el = document.head.querySelector<HTMLMetaElement>(selector);
  if (!el) {
    el = document.createElement("meta");
    el.setAttribute(attr, key);
    document.head.appendChild(el);
  }
  el.setAttribute("content", content);
}

export function RouteSeo() {
  const { pathname } = useLocation();

  useEffect(() => {
    // Trailing slashes are equivalent for routing but not for a Map lookup;
    // "/" itself must survive the strip.
    const path = pathname.length > 1 ? pathname.replace(/\/+$/, "") : pathname;
    const route = BY_PATH.get(path);

    // Dev labs and the OAuth bounce have no public identity. Don't invent one —
    // and make sure a crawler that follows a stray link keeps them out of the
    // index rather than diluting the real pages.
    if (!route) {
      if (NOINDEX.has(path)) {
        setMeta('meta[name="robots"]', "name", "robots", "noindex, nofollow");
      }
      return;
    }

    setMeta('meta[name="robots"]', "name", "robots", "index, follow, max-image-preview:large");

    const url = `${seo.origin}${route.path}`;
    document.title = route.title;
    setMeta('meta[name="description"]', "name", "description", route.description);
    setMeta('meta[property="og:title"]', "property", "og:title", route.title);
    setMeta('meta[property="og:description"]', "property", "og:description", route.description);
    setMeta('meta[property="og:url"]', "property", "og:url", url);
    setMeta('meta[name="twitter:title"]', "name", "twitter:title", route.title);
    setMeta('meta[name="twitter:description"]', "name", "twitter:description", route.description);

    let canonical = document.head.querySelector<HTMLLinkElement>('link[rel="canonical"]');
    if (!canonical) {
      canonical = document.createElement("link");
      canonical.rel = "canonical";
      document.head.appendChild(canonical);
    }
    canonical.href = url;
  }, [pathname]);

  return null;
}
