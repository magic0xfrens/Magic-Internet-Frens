# vercel.json — why it looks like this

`vercel.json` is schema-validated and **rejects `"//"` comment keys at every
level, including the top level**. A `"//"` key anywhere in that file fails the
deploy outright with:

    Error: Invalid vercel.json - should NOT have additional property `//`

That is not cosmetic. A top-level `"//"` was introduced in `40ccfb2` and **every
production deployment failed from then until `a74cbf8`** — the site silently
stopped shipping while the repo looked healthy. Keep notes here instead.

## `cleanUrls` + `trailingSlash`

Keep exactly ONE spelling of each URL live: `/docs`, never `/docs/` or
`/docs/index.html`. Any second spelling that answers 200 is a duplicate of a page
we are trying to get indexed. Vercel checks the filesystem before applying
`rewrites`, so the prerendered `dist/docs/index.html` wins over the SPA
catch-all.

## Why the catch-all header rule excludes `/api/`

The catch-all applies `Cache-Control: no-cache, must-revalidate`. Its pattern
matched `/api/*` too — those paths have no file extension and are not under
`assets/` — so it **overrode the Cache-Control every API handler sets for
itself**. The NFT metadata routes were therefore uncacheable no matter what they
asked for: nothing in front could hold them, and every marketplace, wallet and
indexer fetch reached a serverless function. That is the shape of 2.1M edge
requests in a month against a site with no real visitors.

`/api/` now has its own rule carrying the same security headers (nosniff, DENY,
`frame-ancestors 'none'`, no-referrer) and **deliberately no Cache-Control** —
only the handler knows whether a body is immutable (a revealed creature's
traits) or transient (a chain read that failed).

## Why the handlers set `CDN-Cache-Control` as well

`s-maxage` is consumed by Vercel's own edge and does **not** survive downstream.
Measured live before the fix:

    curl -sI https://www.mifrens.xyz/api/cauldron/unrevealed
    cache-control: public          # bare — every directive gone
    cf-cache-status: DYNAMIC       # Cloudflare caching nothing

Cloudflare sits in FRONT of Vercel, so it saw a header with no freshness
information and passed every request through. Static assets were unaffected
because they carry a plain `max-age`, which does arrive intact — that is what
isolates the problem to `s-maxage`-only responses. The metadata routes whose
bodies cannot change now send an explicit `CDN-Cache-Control` plus a plain
`max-age`.
