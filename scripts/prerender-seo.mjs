#!/usr/bin/env node
/**
 * Post-build: turn the single-file SPA bundle into one real HTML document per
 * route, and regenerate the sitemap from the same table.
 *
 * Why this exists
 * ---------------
 * Vite emits exactly one `dist/index.html`. Vercel's SPA rewrite then serves
 * those same bytes for `/docs`, `/token`, `/cauldrons` — so every URL on the
 * domain answered with an identical `<title>` and description. Google treats
 * that as one page duplicated N times, collapses it to the canonical, and the
 * site ends up with a single indexed URL. A single indexed URL can never earn
 * sitelinks or a "More results from …" cluster, no matter how good the content
 * behind the fragment is.
 *
 * Googlebot does render JavaScript, so it would eventually *see* each route's
 * body. But rendering is a deferred second pass, and the title/description it
 * indexes on the first pass is whatever the raw HTML said. Baking the head in
 * removes that dependency entirely.
 *
 * Vercel checks the filesystem before applying `rewrites`, so `dist/docs/index.html`
 * wins over the catch-all and the client bundle still boots identically.
 */

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const DIST = join(ROOT, "dist");

const seo = JSON.parse(readFileSync(join(ROOT, "src/app/seo-routes.json"), "utf8"));
const { origin, ogImage, routes } = seo;

const shell = readFileSync(join(DIST, "index.html"), "utf8");

/**
 * The SPA catch-all in vercel.json carves out the prerendered routes by name.
 * If someone adds a route here and forgets that list, the catch-all swallows it
 * and the route silently ships the landing page's title again — the original
 * bug, reintroduced invisibly. Catch it at build time instead.
 */
function assertVercelExclusions() {
  const vercel = JSON.parse(readFileSync(join(ROOT, "vercel.json"), "utf8"));
  const spa = vercel.rewrites?.find((r) => r.destination === "/index.html");
  if (!spa) throw new Error("prerender: no SPA catch-all rewrite found in vercel.json");

  const expected = routes.filter((r) => r.path !== "/").map((r) => r.path.slice(1));
  const missing = expected.filter((seg) => !spa.source.includes(seg));
  if (missing.length) {
    throw new Error(
      `prerender: vercel.json SPA rewrite does not exclude ${missing.map((s) => `/${s}`).join(", ")}.\n` +
        `  Expected source to carve out: ${expected.join("|")}\n` +
        `  Actual source: ${spa.source}`,
    );
  }
}
assertVercelExclusions();

/** Replace a tag's attribute value, or fail loudly — a silent no-op here ships
 *  duplicate titles to production, which is the exact bug we are fixing. */
function must(html, re, replacement, label) {
  if (!re.test(html)) throw new Error(`prerender: could not find ${label} in dist/index.html`);
  return html.replace(re, replacement);
}

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");

function buildPage(route) {
  const url = `${origin}${route.path}`;
  const isHome = route.path === "/";
  let html = shell;

  html = must(html, /<title>[\s\S]*?<\/title>/, `<title>${esc(route.title)}</title>`, "<title>");
  html = must(
    html,
    /<meta name="description" content="[^"]*"\s*\/>/,
    `<meta name="description" content="${esc(route.description)}" />`,
    "meta description",
  );
  html = must(
    html,
    /<link rel="canonical" href="[^"]*"\s*\/>/,
    `<link rel="canonical" href="${url}" />`,
    "canonical",
  );

  for (const [attr, key, value] of [
    ["property", "og:title", route.title],
    ["property", "og:description", route.description],
    ["property", "og:url", url],
    ["name", "twitter:title", route.title],
    ["name", "twitter:description", route.description],
  ]) {
    html = must(
      html,
      new RegExp(`<meta ${attr}="${key}" content="[^"]*"\\s*/>`),
      `<meta ${attr}="${key}" content="${esc(value)}" />`,
      `${key}`,
    );
  }

  // The FAQ and app-listing markup describes the landing page specifically.
  // Repeating it on every sub-page would have five URLs all claiming to be the
  // same WebApplication, which muddies exactly the entity we want Google to
  // resolve cleanly.
  if (!isHome) {
    html = html.replace(
      /\s*<script type="application\/ld\+json" data-seo="home-only">[\s\S]*?<\/script>/,
      "",
    );
  }

  // A breadcrumb is the strongest structured hint that a URL is a *child* of
  // the site root rather than a peer of it — that parent/child shape is what a
  // sitelink cluster renders.
  if (!isHome) {
    const crumbs = {
      "@context": "https://schema.org",
      "@type": "BreadcrumbList",
      itemListElement: [
        { "@type": "ListItem", position: 1, name: seo.brand, item: `${origin}/` },
        { "@type": "ListItem", position: 2, name: route.name, item: url },
      ],
    };
    const page = {
      "@context": "https://schema.org",
      "@type": "WebPage",
      "@id": url,
      url,
      name: route.title,
      description: route.description,
      isPartOf: { "@id": `${origin}/#website` },
      about: { "@id": `${origin}/#org` },
      primaryImageOfPage: ogImage,
    };
    html = html.replace(
      "</head>",
      `  <script type="application/ld+json">${JSON.stringify(crumbs)}</script>\n` +
        `    <script type="application/ld+json">${JSON.stringify(page)}</script>\n  </head>`,
    );
  }

  return html;
}

let written = 0;
for (const route of routes) {
  const html = buildPage(route);
  const outs =
    route.path === "/"
      ? [join(DIST, "index.html")]
      : // Both spellings, because static hosts disagree about which one backs a
        // clean URL: Vercel's `cleanUrls` resolves /docs from `docs.html`, while
        // a plain directory-index server resolves it from `docs/index.html`.
        // Writing both means /docs is correct either way and never falls through
        // to the SPA shell. Only one of them is ever reachable as a 200 —
        // `trailingSlash: false` + `cleanUrls` collapse the rest into redirects.
        [join(DIST, `${route.path}.html`), join(DIST, route.path, "index.html")];

  for (const out of outs) {
    mkdirSync(dirname(out), { recursive: true });
    writeFileSync(out, html);
  }
  written++;
  console.log(
    `  ${route.path.padEnd(12)} → ${outs.map((o) => o.replace(DIST, "dist")).join(" + ")}  "${route.title}"`,
  );
}

// Sitemap is generated, not hand-maintained, so it cannot drift from the routes
// that actually exist. `lastmod` is the build date: these pages read live chain
// state, so every deploy genuinely changes what they say.
const lastmod = new Date().toISOString().slice(0, 10);
const sitemap = [
  '<?xml version="1.0" encoding="UTF-8"?>',
  '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
  ...routes.map(
    (r) =>
      `  <url><loc>${origin}${r.path}</loc><lastmod>${lastmod}</lastmod>` +
      `<changefreq>${r.changefreq}</changefreq><priority>${r.priority}</priority></url>`,
  ),
  "</urlset>",
  "",
].join("\n");

writeFileSync(join(DIST, "sitemap.xml"), sitemap);
writeFileSync(join(ROOT, "public/sitemap.xml"), sitemap);

console.log(`prerender-seo: ${written} routes, sitemap has ${routes.length} real URLs (no fragments)`);
