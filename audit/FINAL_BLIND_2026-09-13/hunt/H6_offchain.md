# H6 — OFF-CHAIN (indexer / api / frontend / scripts)

Branch `redteam/2026-09-11`. PoC artifacts in `/tmp/blind-h6/` (not in the repo).

## 1. Model from code

**Serverless routes (`api/`), all Vercel, all unauthenticated unless noted**
- `POST /api/x-token` (`api/x-token.ts:44`) — OAuth2 PKCE exchange holding `X_CLIENT_SECRET`; `redirect_uri` allowlisted (`:62`), per-IP RL 10/60s keyed off `x-real-ip` then RIGHTMOST XFF (`:26-33`).
- `POST /api/fren-ask` (`api/fren-ask.ts:186`) — LLM (Groq/Gemini), no auth, RL 10/30s same keying; docs origin pinned to env/platform host, `redirect:"error"`, content-type + 200 kB bound (`:96-110`); docs framed as untrusted data (`:230`).
- `GET/POST/DELETE /api/fren-teach` — `x-fren-admin` shared secret, sha256+`timingSafeEqual` (`:33`), 5 failures/60s.
- `GET /api/brand?gen` — public, hits Neon **and runs `CREATE TABLE IF NOT EXISTS` per request** (`api/brand.ts:103`). `POST` — origin allowlist + EIP-191 signature from `BRAND_SIGNERS`, 10-min TTL, monotonic `ts` (`:117-181`).
- `GET /api/cauldron/{creature,liquidatoor,unrevealed}` — public metadata; `?col=` allowlisted against `round.json` (`liquidatoor.ts:216`); RPC reads via `API_RPC_URL` fallback list.

**Write hooks (frontend → chain)** — all `CAULDRON.chainId` from `indexer/deployments/round.json` (11155111).
- `useCauldronSwap.buy` → `CauldronGachaRouter.play(quoteIn,tokenIn,minTokenOut,minQuoteOut,openMax)`; native leg sends `value`, ERC20-quote leg does `zap` → `approve` → `play` (`src/hooks/useCauldronSwap.ts:139-243`). ABI matches `CauldronGachaRouter.sol:234`.
- `.sell` → same selector, `[0, tokenInWei, 0, minQuoteOut, openMax]` (`:378-388`); `.spin` → `playChurn`; `.openReady`, `.reveal/revealBatch`, `.approveToken` (max-uint approval to the router, `:356`).
- `useTreasuryRotation.rotateSlice(bps, minOut, route, fromLeg)`; `minOut` = on-chain `quoteSlice()` re-read × (1−slip) (`TreasuryRotation.tsx:479-487`).
- `usePerpEngine` open/close with slippage-derived floors (`src/config/perp.ts:68`).

**Slippage source** — SwapWidget's floors for BOTH legs derive from `spotPrice`, which is `d.spotPrice` from the indexer HTTP response (`useCauldronMachine.ts:261`), i.e. `pool.lastPrice` = `ethPerToken(sqrtPriceX96)` (`indexer/src/index.ts:27,292,321`).

**Indexer** — 53 `ponder.on` subscriptions; every one resolves to a declared contract event with matching arg types (checked, see Refutations). `pool.quote` recorded at registration (`index.ts:44-54`) and never used by the price/volume math.

## 2. Findings

```
id: T6A   severity: High   confidence: DERIVED (logic executed in a transcription harness)
subsystem: frontend write hook
file: src/hooks/useCauldronSwap.ts:181 / :215
  181:        let amountIn = (await bal()) as bigint;
  184:        if (quoteExpected > 0n && amountIn < quoteExpected) {
  215:          args: [amountIn, 0n, minOut, 0n, BigInt(openMax)], value: 0n,
title: On an ERC20-quoted generation the buy button spends the user's ENTIRE quote-token balance, not the amount typed, with a slippage floor sized for the typed amount.
precondition: generationQuote != address(0) (reachable today: a completed treasury rotation into USDG, which the product ships a panel for) and the buyer holds any quote balance >= quoteExpected (e.g. the 10,000 USDG the widget's own `mintTestQuote` button mints, src/components/cauldron/SwapWidget.tsx:496).
sequence:
  1. user types 0.01 ETH; SwapWidget computes quoteExpected ~25 USDG and minOut for 0.01 ETH of tokens (SwapWidget.tsx:193-199, :267)
  2. buy() reads the wallet's full USDG balance into `amountIn` (:181); the zap branch is skipped because balance >= quoteExpected (:184)
  3. approve(router, amountIn) then play(quoteIn = amountIn = 10,000 USDG, minTokenOut = floor for 25 USDG)
  4. CauldronGachaRouter._play swaps the whole `spend` (CauldronGachaRouter.sol:295) — nothing refunds the excess
attacker_cost: none — this is a self-inflicted loss the UI causes; a sandwicher pays only gas and can front-run because the floor covers 0.25% of the trade
damage: entire quote balance swapped at effectively unbounded slippage (measured overspend 400x, floor covering 0.250% of the executed size)
poc: /tmp/blind-h6/poc_a_full_balance.mjs   needs_fork: no
observed:
  typed  : 0.01 ETH  (~ 25 USDG )
  balance: 10000 USDG
  play(quoteIn= 10000 USDG , minTokenOut= 1000000000000000000 )
  OVERSPEND FACTOR: 400 x
  slippage floor covers only 0.250 % of the amount actually swapped
```

```
id: T6B   severity: High   confidence: DERIVED
subsystem: indexer price denomination -> frontend slippage floor
file: indexer/src/index.ts:27-31
  function ethPerToken(sqrtPriceX96: bigint): number {
    const s = Number(sqrtPriceX96) / Q96;
    const tokenPerEth = s * s;
    return tokenPerEth > 0 ? 1 / tokenPerEth : 0;
  }
file: indexer/src/index.ts:292 / :295 / :321
  const price = ethPerToken(event.args.sqrtPriceX96 as bigint);
  const amountEth = Math.abs(Number(amount0)) / 1e18;
  ...set({ lastPrice: price, ... volumeEth: p.volumeEth + amountEth ...})
file: src/components/cauldron/SwapWidget.tsx:186-199 ("`spotPrice` is ETH per token")
title: `lastPrice` is a RAW currency0/currency1 ratio labelled "ethPerToken"; on a 6-decimal quote it is 1e12 off and quote-denominated, so every ERC20-quoted BUY signs an unreachable minTokenOut and reverts *after* the zap has already converted the buyer's ETH.
precondition: a generation whose quote is not native and not 18-decimal. `round.json` ships USDG (6 dec) as an allowed quote asset; `PoolOps.sol:269` pins the quote as currency0, so amount0 and the ratio are both quote-side.
sequence:
  1. treasury rotation completes into USDG; the indexer keeps writing lastPrice = usdgRaw/tokenRaw = P x 1e-12
  2. SwapWidget reads it as ETH/token (useCauldronMachine.ts:261 -> SwapWidget spotPrice)
  3. buy: estTokensOut = netOfFee(ethIn)/spotPrice -> minOut overshoots the achievable fill by ~4e8x
  4. useCauldronSwap zaps ETH->USDG in tx1 (succeeds, irreversible), then play() in tx2 reverts on the floor
attacker_cost: 0 (no attacker needed; a passed rotation vote is the trigger)
damage: buying is bricked for the whole generation; each attempt burns the zap's swap fee + two gas payments and leaves the buyer holding a quote asset they did not want. Chart, candles, mcap/FDV and `volumeEth` are simultaneously wrong by 1e12 (volume reads ~0), and `priceUsd = spotPrice * ethUsd` is meaningless.
note: the SELL floor lands correctly only by coincidence — parseEther's 1e18 cancels the 1e-12 and the 6-dec unit. Nothing in the code intends that.
poc: /tmp/blind-h6/poc_b_quote_units.mjs   needs_fork: no
observed:
  indexer spotPrice      : 2.5e-18   (true ETH/token: 1e-9)  -> off by 4.0e8 x
  BUY reverts on floor   : true   overshoot 396000000 x
  SELL minQuoteOut signed: 24255000 raw = 24.255 USDG (fair 24.5) -> sane by accident
related: `buy(..., quoteDecimals = 18, ...)` (useCauldronSwap.ts:146) is accepted and never read — the denomination path is unfinished, not merely mis-scaled.
```

```
id: T6C   severity: Medium   confidence: DERIVED
subsystem: frontend slippage source
file: src/hooks/useCauldronMachine.ts:261
  spotPrice: d.spotPrice && d.spotPrice > 0 ? d.spotPrice : prev.spotPrice,
file: src/components/cauldron/SwapWidget.tsx:193-199 (minOutFor -> the signed floor)
title: Both slippage floors are derived from an unauthenticated HTTP number served by the Railway indexer, with no freshness or sanity gate at the signing site; a stale or wrong price silently becomes a zero-protection trade.
precondition: indexer lagging, restarted mid-reindex, or reporting a price inflated by any bug (T6B is one such bug). `useIndexerHealth` exists but only renders a banner (`src/components/shared/IndexerHealthBanner.tsx:26`); SwapWidget never consults it.
sequence: 1. indexer serves lastPrice 100x high  2. estTokensOut = netOfFee(eth)/spot -> 1/100 of fair  3. minOut = ~1% of fair output  4. the trade fills at any price a sandwicher likes.
attacker_cost: gas for a sandwich, plus whatever it takes to lag or skew the indexer (a public-RPC 429 storm does it for free)
damage: unbounded per-trade slippage on every user who trades during the window
poc: none runnable without the live indexer — the mechanism is exercised numerically by /tmp/blind-h6/poc_b_quote_units.mjs   needs_fork: no
fix direction: quote the floor from the pool (slot0/quoter) at sign time, as TreasuryRotation.tsx:479 already does for rotateSlice.
```

```
id: T6D   severity: Medium   confidence: DERIVED
subsystem: keeper script / multi-chain wiring
file: indexer/seed-keeper.mjs:74-76
  const manifest = JSON.parse(
    readFileSync(new URL("./deployments/round.json", import.meta.url), "utf8"),
  );
file: indexer/seed-keeper.mjs:37 / :90-91
  import { sepolia } from "viem/chains";
  const pub = createPublicClient({ chain: sepolia, transport: http(rpc) });
  const wallet = createWalletClient({ account, chain: sepolia, transport: http(rpc) });
title: The launch seed keeper hardcodes the Sepolia manifest and the Sepolia chain, so on the Arc deployment it pokes an address that holds no code, forever, and says only "poke skipped".
precondition: `DEPLOYMENT=arc` — the documented second deployment (`indexer/deployments/active.ts:29`, which every other consumer including `ponder.config.ts` respects).
sequence: 1. Railway starts the Arc indexer with PONDER_RPC_URL=arc  2. seed-keeper reads round.json (Sepolia seeder 0xc28b…)  3. readContract against Arc reverts, caught at :131, logged  4. `poke()` is never sent; the launch curve sits at seedFloorWad until a human intervenes.
attacker_cost: 0 (config, not an attack)   damage: launch liquidity deployment stalls on the Arc round; grief-free liveness failure, silently logged
poc: read-only (the import and the chain literal); no runnable artifact   needs_fork: no
```

```
id: T6E   severity: Low   confidence: DERIVED
subsystem: serverless cost
file: api/brand.ts:100-108
    const sql = neon(dbUrl);
    await sql`CREATE TABLE IF NOT EXISTS cauldron_brand (...)`;
    const gen = Number((req.query.gen as string) ?? "0");
    ...
    res.setHeader("Cache-Control", "public, s-maxage=30, ...");
title: The public GET path runs a DDL statement plus a query against Neon on every request and has no rate limit; the edge cache is keyed on the full URL, so `?gen=0&x=<random>` bypasses it.
sequence: `for i in $(seq 1 100000); do curl -s "https://<host>/api/brand?gen=0&x=$i" >/dev/null; done`
attacker_cost: bandwidth   damage: Neon compute-seconds + Vercel invocations; no funds at risk
poc: curl loop above (NOT run against production, per brief)   needs_fork: no
```

```
id: T6F   severity: Low   confidence: DERIVED
subsystem: frontend chain selection
file: src/config/deployments.ts:63-66
    const fromUrl = Number(new URLSearchParams(window.location.search).get("chain"));
    if (Number.isSafeInteger(fromUrl) && isDeployChain(fromUrl)) return fromUrl;
title: A link parameter chooses which deployment manifest the whole app reads, ahead of the stored choice, and persists visually with no confirmation.
damage: a shared link silently points a user's UI (addresses, indexer, quote list) at the other deployment. Bounded today because both entries are testnets and each manifest is internally consistent (`src/config/cauldron.ts:25` logs a mismatch).
poc: open `http://localhost:5173/?chain=5042002`   needs_fork: no
```

## 3. Refutations (attacked hard, held)

1. **Bundle secrets.** `grep -rlIE "gsk_…|AIzaSy…|sk-…|-----BEGIN|postgres://|npg_" dist/` — zero hits. Only `VITE_CAULDRON_INDEXER, VITE_CHAIN_*, VITE_NETWORK, VITE_PERP_ENGINE, VITE_RPC_URL, VITE_EXPLORER_*` reach the bundle; all public config. `npm run type-check` passes clean.
2. **Indexer/contract event surface.** 53 `ponder.on` subscriptions; all 42 protocol event names are declared in the Solidity tree (only `Transfer`/`Swap` come from libs), and an arg-type diff of every event present in both `indexer/abis/*.ts` and the sources produced one apparent mismatch (`Claimed`) that resolved to name-shadowing between `MigrationVesting.sol:139` and `MiFrensDividend.sol:160` — the ABI matches the dividend contract exactly. Script: `/tmp/blind-h6/cmp2.mjs`.
3. **`/api/x-token`.** PKCE + `state` compared in `useXAuth.ts:70`, `redirect_uri` allowlisted server-side, access token never persisted (only the profile lands in localStorage). No open-exchange, no token leak found.
4. **`/api/fren-teach` / `/api/fren-ask`.** Constant-time fixed-width digest compare, failure throttle, and both routes key the limiter on `x-real-ip` then the RIGHTMOST XFF hop — the leftmost-hop bypass does not work here. `fren-ask`'s docs fetch takes no request header, refuses redirects, checks content-type and truncates: no SSRF, no header-driven prompt injection.
5. **`/api/cauldron/liquidatoor`.** `?col=` is allowlisted against the manifest (`:216`) before any `readContract`, so the "render my own contract's liqStats as a badge" path is closed; the decode is typed.
6. **My own first hypothesis — "ERC20-quoted sells always revert".** Refuted: `PoolOps.sol:269` ("Always currency0: the token is deployed to sort above it") pins the orientation, and the 1e18/1e-12 errors cancel, so the sell floor is numerically right (see T6B note). Only the buy leg breaks.

## 4. Leads (HYPOTHESIS — next step named)

- **L1** `p.website` from an on-chain proposal is rendered as `href={`https://${p.website…}`}` (`src/components/cauldron/TheCauldron.tsx:1773`, `:1826`). Scheme injection is blocked by the literal prefix, but anyone who can post a proposal (gas only) gets a clickable link inside the app UI. Next step: check whether the proposal string is length/charset-bounded on-chain and whether the modal shows the proposer.
- **L2** `x-real-ip` is assumed platform-set and unforgeable in three routes. Next step: send `-H 'x-real-ip: 1.2.3.4'` to a `vercel dev` instance and to a preview deployment and observe whether the bucket rotates; if Vercel forwards a client-supplied `x-real-ip`, every RL in `api/` is bypassable with one header.
- **L3** `/api/cauldron/creature` performs unauthenticated RPC reads with no limiter (`api/cauldron/creature.ts:190-227`, 15 s cache). Same cache-key bypass as T6E, but it burns the shared `API_RPC_URL` quota rather than DB time. Next step: measure reads per request and whether a miss storm exhausts the fallback list.
- **L4** `useCauldronMachine.ts:261` keeps `prev.spotPrice` forever when the indexer returns 0/absent. Next step: kill the indexer mid-session and confirm the widget still signs floors off the frozen price.
