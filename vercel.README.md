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

## Why the HTML catch-all is `max-age=0, must-revalidate` + a CDN TTL

The overage that prompted all of this was **2.1M edge requests against a site
with no real visitors**, and the arithmetic in the dashboard says where they went:

    3.84 GB / 2.1M requests  = ~1,963 bytes average  -> small text, not images
    2m20s CPU / 2.1M requests = ~0.067 ms each       -> almost NONE ran a function

A serverless invocation cannot complete in 0.067 ms, so the overwhelming majority
of those 2.1M were **not** API calls. They were requests for the SPA shell. `/`
and `/index.html` were the top two paths in the dashboard, and both were served
with `Cache-Control: no-cache, must-revalidate`, which forces a round trip to the
origin on **every** request — including every crawler hit, forever.

`no-cache` was not wrong in intent: an SPA shell must not be pinned, or users
never see a new build. But it is enforced in the wrong place. The split is:

* `Cache-Control: public, max-age=0, must-revalidate` — the BROWSER still
  revalidates every time, so a user never runs a stale build.
* `CDN-Cache-Control: public, s-maxage=300, stale-while-revalidate=86400` — the
  CDN may answer from cache for 5 minutes and refresh in the background, so bots
  and repeat hits stop reaching the origin. Hashed asset filenames make a
  5-minute-old shell safe: the assets it references are immutable and still
  present, and Vercel purges its edge cache on deploy.

### This is only half the fix — the other half is not in this repo

Cloudflare sits in FRONT of Vercel, and its default Cache Level caches **by file
extension only**. Measured:

    /crystal.png              -> cf-cache-status: HIT,     HIT
    /api/cauldron/unrevealed  -> cf-cache-status: DYNAMIC, DYNAMIC
    /                         -> cf-cache-status: DYNAMIC, DYNAMIC

Extensionless paths are never cached no matter what headers they carry, so these
headers alone will NOT reduce the request count. It also means Vercel still
counts an edge request even when its own cache would serve it — the only way the
number falls is for the request never to arrive. That requires a dashboard rule:

> **Rules → Cache Rules → Create.**
> Match: `URI Path` **starts with** `/api/cauldron/`  → Eligible for cache, Edge TTL: respect origin.
> Match: `URI Path` equals `/` or starts with `/docs`, `/cauldrons`, `/mi-frens`, `/token` → Eligible for cache, Edge TTL: respect origin.

Verify with `curl -sI <url> | grep cf-cache-status` — it must reach `HIT` on a
second request, not `DYNAMIC`.
