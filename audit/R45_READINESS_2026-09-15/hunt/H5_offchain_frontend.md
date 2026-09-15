# H5 — Off-chain & frontend hunt (round-45 readiness)

Working tree: `/Users/0x0010110/Documents/GitHub/Magic Internet Frens`, branch `redteam/2026-09-13`, uncommitted frontend changes included.
Manifest under review: `indexer/deployments/round.json` — `round: 44`, `schema: cauldron_r44d`, `chainId: 11155111`.

---

## 1. MODEL FROM CODE

**Serverless routes (`api/`, Vercel).**
`api/fren-ask.ts` — POST only, no auth, in-memory per-IP limit 10/30s keyed on `x-real-ip` then the *rightmost* `x-forwarded-for` hop (`api/fren-ask.ts:170-176`). Holds `GROQ_API_KEY`/`GEMINI_API_KEY`/`DATABASE_URL`; returns only model text. Docs origin pinned to `CAULDRON_DOCS_ORIGIN`/`VERCEL_*_URL`, `redirect: "error"`, content-type checked, 200 kB cap.
`api/fren-teach.ts` — GET/POST/DELETE gated on `x-fren-admin` vs `FREN_ADMIN_SECRET`, sha256+`timingSafeEqual`, 5 failures/60 s per IP. Writes the `fren_corrections` rows that `fren-ask` injects as "AUTHORITATIVE CORRECTIONS".
`api/x-token.ts` — POST, holds `X_CLIENT_SECRET`; `redirect_uri` checked against `X_REDIRECT_URIS`; 10/60 s per IP; returns `access_token` + profile to the browser.
`api/cauldron/liquidatoor.ts` — public GET; reads `liqStats` over a viem `fallback()` of three public Sepolia RPCs; `?col=` allow-listed against `round.json.contracts.collection` + `LIQUIDATOOR_COLLECTIONS`. `api/cauldron/unrevealed.ts`, `api/brand.ts`, `api/cauldron/creature.ts` — static/derived, no secrets.

**Frontend.** All addresses come from `round.json` via `src/config/cauldron.ts:36-55` and `src/config/deployments.ts`; `node scripts/verify-manifest.mjs` reports "no hardcoded addresses, no env overrides". Chain selection: `?chain=` → localStorage → `VITE_NETWORK` (`src/config/deployments.ts:74-77`). Sepolia transport is a viem `fallback()` of `VITE_SEPOLIA_RPC_URL` (comma-split) plus four public nodes (`src/config/chains.ts:92-104,141-145`). Reads: `src/lib/cauldronIndexer.ts` (base = `round.indexerUrl`) + wagmi `useReadContract`. Writes: see §5.

**Indexer (`indexer/`).** `start.mjs` derives the Postgres schema from `round.json`, starts the in-process seed keeper (`SEED_KEEPER_PK`) and execs `ponder start`. `ponder.config.ts:105-121` builds the RPC list (env list, else a 5-provider default). `src/api/index.ts` serves ~30 read-only Hono routes (all `db.select()` with `.limit()`), plus `/freshness` (divergence beacon) and an in-process watchdog that `process.exit(1)`s after ~9 min of sustained divergence. `railway.json`: healthcheck `/health` (Ponder's own always-200 liveness), `ON_FAILURE`, `restartPolicyMaxRetries: 10`.

**Operator scripts.** `keeper.sh` (signer via `scripts/lib/signer.sh`, keystore preferred; liquidate/materialize/royalty sweeps), `seed-keeper.mjs` (hot key, `poke()`), `deploy-round.mjs` (`railway up` + `/freshness` poll), `apply-deployment.mjs` (reads Foundry `broadcast/run-latest.json`), `verify-manifest.mjs` (runs on `prebuild` and in CI), `verify-selectors.mjs` (**called by nothing**).

---

## 2. FINDINGS

```
id: R5A   severity: High   confidence: DERIVED (static reproduction VERIFIED)
subsystem: gacha spin → CauldronGachaRouter
file:line: src/components/cauldron/CrystalCauldronGame.tsx:206
    const hash = await spin(stake, loops, 0, spinFloor);
file:line: src/hooks/useCauldronSwap.ts:342-347 (signature)
    const spin = useCallback(
      async (
        ethIn: number, loops = 3, openMax = 0, minTokenOut: bigint = 0n,
        quote: Address = NATIVE_QUOTE, quoteExpected: bigint = 0n, quoteSymbol = "the quote",
file:line: src/hooks/useCauldronSwap.ts:431-441 (the branch it therefore always takes)
      const canChurnNative = await routerHasChurn(pc!, CAULDRON.gachaRouter as Address);
      return writeContractAsync({ ... functionName: canChurnNative ? "playChurn" : "play",
        args: canChurnNative ? [0n, BigInt(loops), minTokenOut, BigInt(openMax)] : [...],
        value: parseEther(ethIn.toFixed(18)), gas: LIQ_SWAP_GAS, });
file:line: src/components/cauldron/TheCauldron.tsx:1018-1020 vs :1028-1036
      quote={liveQuoteAddr} quoteSymbol={liveQuote.symbol} quoteDecimals={liveQuote.decimals}   // SwapWidget
      <CrystalCauldronGame ticker=... token=... collection=... spotPrice=... />                  // no quote at all
title: after a completed quote rotation the crystal gacha spin reverts for every user, because the only call site never passes the live quote and `spin` falls back to its native default.
precondition: `generationQuote` is a non-native asset. Reachable through the shipped governance UI (`src/hooks/useTreasuryRotation.ts:432-447` propose/vote/execute, `rotateSliceFrom` at :424) and `round.json` ships two ERC20 quotes (USDG 6-dec, xNVDA 18-dec). No attacker required.
sequence:
  1. Treasury governance completes a rotation to USDG; `useCurrentQuote` (TheCauldron.tsx:494) reports USDG, and SwapWidget correctly switches to the zap+approve path.
  2. A user clicks SPIN. `CrystalCauldronGame.tsx:206` passes 4 of 7 arguments, so `quote = NATIVE_QUOTE`.
  3. `isNativeQuote(quote)` is true → the ERC20 branch (:376-429, zap + approve + `quoteIn`) is skipped.
  4. The tx is signed with `value = parseEther(stake)` and `quoteIn = 0`; the router's `_pullQuote` ERC20 branch rejects any value.
  5. Secondary defect on the same path: `spinFloor = (stake / spotPrice) * …` (CrystalCauldronGame.tsx:157-164) divides an ETHER stake by a QUOTE-per-token price — the exact 1e12/2533x unit mix `SwapWidget.tsx:189-197` was fixed for — so even if (3) were fixed the floor is wrong by the ETH/quote ratio.
attacker_cost / trigger: one governance rotation (a legitimate protocol feature); zero attacker cost.
damage: the crystal gacha — the protocol's NFT mint and a headline feature — is dead for every user until the quote is rotated back; each attempt burns a full `LIQ_SWAP_GAS`-limited revert (gas only, ~30-60k actually consumed on an early revert, but the wallet prompts for 8M).
poc: audit/R45_READINESS_2026-09-15/hunt/h5-poc/r5a-spin-quote-unaware.mjs   needs_fork: no
```
Observed output (`node …/r5a-spin-quote-unaware.mjs`):
```
spin signature: (ethIn: number, loops = 3, openMax = 0, minTokenOut: bigint = 0n, quote: Address = NATIVE_QUOTE, …)
call site  CrystalCauldronGame.tsx:206: const hash = await spin(stake, loops, 0, spinFloor);
args passed: 4
CrystalCauldronGame Props keys: ticker, token, collection, spotPrice, ethUsd, col, nftMinted, nftMax, onBought
TheCauldron passes quote to SwapWidget: true
TheCauldron passes quote to CrystalCauldronGame: false
```

```
id: R5B   severity: High   confidence: VERIFIED (arithmetic) / DERIVED (on-chain effect)
subsystem: Community PLV staking (PerpVault)
file:line: src/components/cauldron/StakePanel.tsx:84-92
          let raw = parseEther(amount.toFixed(18));
          if (v.quoteIsErc20) {
            if (raw > v.quoteBalance) raw = v.quoteBalance;
            if (raw <= 0n) { … }
            if (v.needsQuoteApproval(raw)) { … const ah = await v.approveQuote(); … }
          }
          hash = await v.depositQuote(raw);
file:line: src/hooks/usePerpVault.ts:154-157 (the approval it grants first)
    return writeContractAsync({ address: quoteToken, abi: ERC20_SWAP_ABI, functionName: "approve", args: [PERP.vault, maxUint256] });
file:line: src/components/cauldron/StakePanel.tsx:10-20 (Props carry no decimals) and TheCauldron.tsx:1126
    <StakePanel ticker={m.ticker} token={m.token} spotPrice={livePerpPrice} ethUsd={m.ethUsd ?? 0} col={col} quote={liveQuoteAddr} quoteSymbol={liveQuote.symbol} />
title: on a 6-decimal quote, a user who types "1" stakes their ENTIRE quote balance, after the panel has first granted the vault an infinite approval.
precondition: `generationQuote` is an ERC20 with fewer than 18 decimals — `round.json.quoteAssets[1]` is USDG at 6. Same reachability as R5A. SwapWidget receives `quoteDecimals` (TheCauldron.tsx:1020); StakePanel is not given it and imports only `parseEther`/`formatEther` (StakePanel.tsx:2).
sequence:
  1. Quote is USDG (6 dec). User holds 10,000 USDG and types "1" into Stake.
  2. `parseEther("1.000…")` = 1e18 raw units = 1e12 USDG.
  3. `needsQuoteApproval(1e18)` is true → `approveQuote()` signs `approve(vault, 2^256-1)`.
  4. The clamp `if (raw > v.quoteBalance) raw = v.quoteBalance` silently rewrites the amount to the full 10,000 USDG balance.
  5. `depositQuote(10_000_000_000)` is signed and succeeds — nothing reverts, the toast says "Deposited ✓".
  The withdraw side mirrors it: `frac = amount / pos.redeemable` (StakePanel.tsx:124) with `pos.redeemable` formatted through `formatEther`, so any typed amount clamps to `frac = 1` → full exit.
attacker_cost / trigger: none — a user mis-click with a UI that shows no warning.
damage: the user's entire quote balance enters an LP vault that absorbs trader PnL; exit is by shares and the part traders have borrowed is *queued* until they close (`StakePanel.tsx:133-140`). Unbounded in the user's balance; 10,000x in the PoC. Plus a standing infinite allowance to the vault.
poc: audit/R45_READINESS_2026-09-15/hunt/h5-poc/r5b-stakepanel-decimals.mjs   needs_fork: no
```
Observed output:
```
typed            : 1 USDG
intended raw     : 1000000  (1 USDG)
parseEther raw   : 1000000000000000000  (1e12x too large)
after clamp      : 10000000000  (10000 USDG)
RESULT: a "stake 1 USDG" click signs deposit(10000000000) = the WHOLE 10,000 USDG balance.
Overspend factor: 10000x
```

```
id: R5C   severity: High   confidence: DERIVED (deployed env NOT VERIFIABLE)
subsystem: Ponder indexer RPC configuration + restart policy
file:line: indexer/ponder.config.ts:87-121
    //  ── A REORG CAN TAKE THIS SERVICE DOWN, AND IT DID ──────────────────
    //  Sepolia forked at block 11704817 … Ponder refuses to index when a log's
    //  `blockHash` disagrees with the block it fetched … and treats it as FATAL,
    //  so it crash-looped and the whole API served 502s.
    //  So order this list by what survived that test, and pin PONDER_RPC_URL
    //  to a single provider when it happens again — a comma-separated list
    //  makes Ponder round-robin, which only widens the window for two
    //  providers to disagree. Recovery: set PONDER_RPC_URL, `railway up`.
        const SEPOLIA = [ "https://sepolia.gateway.tenderly.co", …five entries… ];
        const list = env.length > 0 ? env : DEFAULTS;
        return list.length > 1 ? list : list[0];
file:line: indexer/railway.json:4-9
    "healthcheckPath": "/health", "restartPolicyType": "ON_FAILURE", "restartPolicyMaxRetries": 10
title: the committed default configuration is exactly the round-robin-across-five-providers setup the file itself names as the cause of a fatal reorg crash-loop, and Railway stops restarting after 10 failures — so a routine Sepolia reorg takes the entire read layer down until a human redeploys.
precondition: `PONDER_RPC_URL` unset or set to more than one URL in the Railway environment. I cannot read Railway env vars: **NOT VERIFIABLE** — the exact variable to check is `PONDER_RPC_URL` on the indexer service (it must hold exactly one URL).
sequence:
  1. A reorg produces a height where one provider serves the orphan block and another serves canonical logs.
  2. Ponder's log/blockHash consistency check fails → fatal exit.
  3. Railway restarts; the round-robin re-selects providers at random, so the restart lands in the same condition → crash loop.
  4. After `restartPolicyMaxRetries: 10` the container stays down. `/health` (Ponder's liveness) is gone with it, so every indexer-backed surface — candles, tape, heatmap, floors, presale counts, proposals, dividends — is empty.
attacker_cost / trigger: routine chain behaviour; free. (Also note the frontend polls the *same* five public providers via `src/config/chains.ts:96-104`, but those are per-request and tolerate divergence.)
damage: total read-layer outage, manual recovery only (set `PONDER_RPC_URL` to one provider, `railway up`). The recent tree state shows this has already happened once.
poc: no executable PoC (would require forcing a reorg). Evidence is the quoted comment, the quoted default, and `railway.json`. Live state at the time of the hunt was healthy — `curl -s https://indexer-production-102c.up.railway.app/freshness` → `{"ok":true,…,"warmingUp":false}` HTTP 200.   needs_fork: no
```

```
id: R5D   severity: Medium   confidence: VERIFIED
subsystem: deploy pipeline
file:line: scripts/verify-selectors.mjs:16
    //  Run after every deploy:  node scripts/verify-selectors.mjs
file:line: package.json:10
    "prebuild": "node scripts/verify-manifest.mjs && node scripts/sync-llms.mjs",
title: the only guard that compares the app's ABI against the DEPLOYED bytecode is wired into nothing, and the drift it exists to catch has already shipped twice.
precondition: none — this is the state of the tree.
sequence:
  1. `grep -rn "verify-selectors" --include=*.sh --include=*.mjs --include=*.json --include=*.yml .` (excluding node_modules/audit) returns exactly ONE hit: the comment inside the script itself. No `package.json` script, no `.github/workflows/deploy.yml` step, no `deploy-round.mjs`/`auto-deploy.sh` call.
  2. The consequence is already documented in shipped code — `src/hooks/useCauldronSwap.ts:69-80`: "Rounds 43 and 44 both shipped a router whose runtime is 8,580 bytes while the source compiles to 8,814 — the 234-byte gap is `playChurn`, so the selector is missing from the dispatcher and the call reverts with EMPTY data". The app carries a runtime `eth_getCode` workaround (`routerHasChurn`, :86-100) instead.
  3. Contributing cause: no `forge clean` and no `--force` anywhere in `scripts/` (`grep -rn "forge clean|--force" scripts/` → no hits; `auto-deploy.sh:72,77` sets `FOUNDRY_PROFILE=cauldron` then plain `forge build`), so a stale `out/` cache can be broadcast.
attacker_cost / trigger: routine deploy.
damage: a whole function can be missing from the deployed round with no signal; the failure surfaces to users as an empty-data revert. Bounded because the app now probes at runtime — but only for `playChurn`.
poc: grep above; reproduce with `grep -rn "verify-selectors" --include="*.sh" --include="*.mjs" --include="*.json" --include="*.yml" . | grep -v node_modules`   needs_fork: no
```

```
id: R5E   severity: Medium   confidence: DERIVED
subsystem: indexer health beacon
file:line: indexer/src/api/index.ts:1254-1258
    const ok = !diverged || !everHealthy || persistedMs <= HEALTH_GRACE_MS;
file:line: indexer/src/api/index.ts:1294-1305
    if (!ok && everHealthy && divergingSince && Date.now() - divergingSince > WATCHDOG_KILL_MS) { … process.exit(1); }
title: a container that boots straight into divergence never reports unhealthy and never self-restarts — `/freshness` returns ok:true forever and the app shows a confident, wrong, empty page.
precondition: the indexer starts while already diverged (wrong manifest, pool it cannot index, a schema bump into a chain state it never catches up to). `everHealthy` is in-memory and resets on every restart, so the R5C crash-loop and the R5D watchdog restart both land here.
sequence:
  1. Process starts; `everHealthy = false`.
  2. Divergence is detected on every evaluation, but `ok = … || !everHealthy` → `true`, so `/freshness` answers 200.
  3. `src/hooks/useIndexerHealth.ts:60-70` reads `ok:true` and sets state `"ok"`, so the UI shows no degraded banner. (The pool-mismatch branch at :53-57 does still catch that particular case from the body fields — but `missedLaunch`/`missedOpens` divergence is invisible.)
  4. The watchdog's `everHealthy` guard means it never fires, and Railway's `/health` is Ponder's always-200 liveness.
attacker_cost / trigger: routine; any restart into a bad state.
damage: indefinite silent staleness — the exact failure mode the file's own header says it exists to prevent.
poc: none run (would need a diverged deployment). Next step in §4.   needs_fork: no
```

```
id: R5F   severity: Low   confidence: VERIFIED
subsystem: indexer public API
file:line: indexer/src/api/index.ts:1010
    const gen = Number(c.req.param("generation"));
title: a non-numeric path parameter produces a 500 that leaks the container's internal filesystem path.
sequence: `curl -s "https://indexer-production-102c.up.railway.app/candles/abc"` →
  `HTTP 500` … `error: invalid input syntax for type integer: "NaN" occurred in '/app/node_modules/pg-pool…`
attacker_cost / trigger: one GET.   damage: information disclosure only; the route recovers, the process survives, and every other route I probed (`/recent/1?limit=999999`, `/nfts/notanaddress`, `/perp-positions/0x0`) answered 200 with bounded, parameterised results.
poc: the curl above.   needs_fork: no
```

```
id: R5G   severity: Low   confidence: DERIVED
subsystem: keeper
file:line: scripts/keeper.sh:63-66
  for (( id=1; id<next; id++ )); do
    local trader; trader=$(cast call "$PERP" 'positions(uint256)(…)' "$id" --rpc-url "$RPC" …)
    [[ "$trader" =~ ^0x0000 ]] && continue
title: the keeper's sweep is a linear scan over every position id ever created, at two RPC calls each, on an 8-second loop — anyone can grow `nextId` with open/close pairs until a sweep can no longer finish inside its interval.
attacker_cost / trigger: gas for N open+close pairs on testnet-cheap Sepolia.
damage: the *operator* keeper degrades; on-chain in-swap liquidation is unaffected, so this is grief, not loss. Also note `cast send … >/dev/null 2>&1` swallows every send error (`:57`, `:74`, `:110`), so a failing keeper reports nothing.
poc: none run.   needs_fork: no
```


```
id: R5H   severity: Low   confidence: VERIFIED
subsystem: sell path approval
file:line: src/hooks/useCauldronSwap.ts:512-521
  const approveToken = useCallback(
    ...
        address: token, abi: ERC20_SWAP_ABI, functionName: "approve",
        args: [CAULDRON.gachaRouter as Address, maxUint256],
title: the SELL button grants the gacha router an unlimited allowance on the iteration token, contradicting the buy path's own stated policy.
precondition: none — every seller hits it (`SwapWidget.tsx` calls `approveToken(token)` before the first sell).
sequence: 1. user clicks Sell with no allowance; 2. the app signs `approve(gachaRouter, 2^256-1)`; 3. the allowance survives every future round.
attacker_cost / trigger: requires the router to be compromised or replaced; not exploitable on its own.
damage: bounded by the wallet's token balance, but permanent and silent. The ERC20-quote buy path deliberately does the opposite — `useCauldronSwap.ts:288-292`: "BOUNDED TO `spend`. Never an infinite approval, and never the whole balance: the allowance is the last line of defence if the calldata is ever wrong again." The same hook violates that rule three hundred lines later. `usePerpVault.ts:156, 172` also approve `maxUint256`.
poc: grep -n "maxUint256" src/hooks/useCauldronSwap.ts src/hooks/usePerpVault.ts   needs_fork: no
```

---

## 3. REFUTATIONS

- **Bundle secrets.** `npm run build` (exit 0, 103 MB `dist/`). Grepped `dist/` for `sk-`, `ghp_`, `gsk_`, `AIzaSy`, JWT-shaped and 32-byte hex patterns: only Uniswap/viem constants and pool ids. No Alchemy-shaped URL. `git check-ignore -v` confirms `dist`, `.env.local`, `.env.recovery`, `.env.vercel-backup` are all ignored (`.gitignore:61 .env*`, `:18 dist`); `git ls-files | grep ^\.env` returns only `.env.example`, whose sole non-placeholder value is `VITE_NETWORK=testnet`. `.env.recovery` exists on disk (mode 600, ignored) defining `RECOVERY_PK`; `.env.vercel-backup` defines `FREN_ADMIN_SECRET`, `GEMINI_API_KEY`, `X_CLIENT_SECRET`, `VITE_CAULDRON_INDEXER`, `VITE_X_CLIENT_ID` — neither is tracked. Caveat for the deploy: `VITE_SEPOLIA_RPC_URL` is inlined into the bundle by design, so whatever key it holds is public — domain-restrict it.
- **Vite dynamic env access.** `src/config/chains.ts:39-42` reads `import.meta.env[key]` dynamically; I checked the built chunk and Vite emits `sS={BASE_URL:"/",DEV:!1,MODE:"production",PROD:!0,SSR:!1}` as the whole-object replacement, into which build-time `VITE_*` values are folded. The pattern works; the Arc-flavoured fallbacks (`"Arc Testnet"`, chain 5042002) only apply when the vars are genuinely unset.
- **Rate-limiter header spoofing.** Attacked the leftmost-`x-forwarded-for` bypass on all three limited routes. All three prefer `x-real-ip` and otherwise take the *rightmost* hop: `api/fren-ask.ts:170-176`, `api/fren-teach.ts:52-63`, `api/x-token.ts:27-33`. No client-supplied bucket. Limits are per warm instance (honest, documented); the stores are bounded at 5000 keys with opportunistic sweep.
- **LLM prompt injection.** The docs block is fetched from a pinned origin with `redirect: "error"` and a content-type check (`api/fren-ask.ts:76-114`), and is framed as untrusted data (`:246-256`). The only *authoritative* channel is `fren_corrections`, and the writer is secret-gated with constant-time comparison and failure throttling (`api/fren-teach.ts:31-35,86-90`). I could not find an unauthenticated write into the prompt.
- **`x-token` OAuth.** `redirect_uri` is allow-listed against `X_REDIRECT_URIS` before the client secret is used, and the route 503s when the allowlist is unset (`api/x-token.ts:65-71`). No open-redirect, no unmetered secret use.
- **`liquidatoor` SSRF / forged badges.** `?col=` must be in the manifest-derived allowlist (`api/cauldron/liquidatoor.ts:203-213`); an attacker-deployed contract is rejected with 400. The allowlist regex is lowercase-only, which is safe here because `round.json.contracts.collection` is lowercase — but see Leads.
- **Address sourcing / case sensitivity.** `node scripts/verify-manifest.mjs` → "✓ manifest OK … no hardcoded addresses, no env overrides". `round.json.contracts.perpEngine` is mixed-case (`0xaD0b8d…`); every comparison I found lowercases first (`keeper.sh:40,45-48` via `lc()`; `indexer/src/api/index.ts` health check via `.toLowerCase()`; `useIndexerHealth.ts:52-54`). No case-sensitive address comparison found.
- **Indexer query surface.** Every route I read uses drizzle `eq()` with bound parameters and a `Math.min(...)`-capped `limit`; `/recent/1?limit=999999` returned a bounded 12 kB response. No injection, no unbounded scan.
- **Type check.** `npx tsc -p tsconfig.app.json --noEmit` → exit 0. (Note: it therefore does NOT catch R5A — the extra `spin` parameters are optional.)

---

## 4. LEADS (HYPOTHESIS)

1. **Rotation slippage source.** `src/hooks/useTreasuryRotation.ts:397-405` derives `minOut` by simulating `rotateSliceFrom(fromLeg, sliceBps, 0n, route)` and then applying `maxSlip`. That floor is a function of *live pool state read seconds before the send*. Next step: check the panel's `maxSlip` default and maximum (`TreasuryRotation.tsx:672` clamps to 5000 bps = 50%) and whether the on-chain oracle floor binds tighter than a 50%-slack user-chosen floor.
2. **R5E confirmation.** Next step: run the indexer locally against `round.json` with `schema` bumped and `PONDER_RPC_URL` pointed at a node lagging the tip, then `curl /freshness` before it ever reaches parity and assert `ok:true` with `missedOpens:true`.
3. **Deployed env.** NOT VERIFIABLE from the tree; three variables decide R5C and the bundle's RPC: Railway `PONDER_RPC_URL` (must be exactly one URL), Railway `SEED_KEEPER_PK` (a hot key inside the indexer process — if it is set, a keeper bug shares a process with the read layer), and Vercel `VITE_SEPOLIA_RPC_URL`.
4. **`liquidatoor` allowlist and a checksummed manifest.** `api/cauldron/liquidatoor.ts:207-210` filters candidates with `/^0x[0-9a-f]{40}$/` *after* `.toLowerCase()`, so it is safe today — but `LIQUIDATOOR_COLLECTIONS` entries and any future checksummed `contracts.collection` would pass. Next step: confirm the deploy pipeline never writes a checksummed `collection` (`apply-deployment.mjs` writes what the broadcast recorded; `perpEngine` already lands mixed-case).
5. **`round.json` says `round: 44` / `schema: cauldron_r44d`** while this review is "round 45". If r45 ships contracts without bumping both, `start.mjs` resumes the old schema against new addresses. Next step: diff the intended r45 addresses against the manifest before `deploy-round.mjs`.

---

## 5. APP CALL LIST

Every write the app can send. Columns: manifest key → function as the app encodes it → file:line → value / approval / floor source.

| manifest key | function encoded | file:line | value / approval / minOut |
|---|---|---|---|
| `gachaRouter` | `play(uint256,uint256,uint256,uint256,uint256)` | `src/hooks/useCauldronSwap.ts:316-321` | `value = parseEther(ethIn)`, `quoteIn=0`, `minOut` from SwapWidget (`SwapWidget.tsx:217`), `gas=8e6` |
| `gachaRouter` | `play(...)` (ERC20-quote branch) | `src/hooks/useCauldronSwap.ts:301-306` | `value=0`, `quoteIn=spend`, approval bounded to `spend` (`:293-297`), floor scaled by `scaleFloor` |
| `gachaRouter` | `playChurn(uint256,uint256,uint256,uint256)` / `play` | `src/hooks/useCauldronSwap.ts:415-428` (ERC20) and `:432-441` (native) | native branch always used from the UI — **R5A** |
| `nativeZap` | `zap((address,address,uint24,int24,address),uint256)` | `src/hooks/useCauldronSwap.ts:193-201` | `value = parseEther(ethIn)`; `minOut` = oracle `expectedOut` − 300 bps; key hardcoded `fee 3000 / spacing 60 / hooks = address(0)` |
| `gachaRouter` (sell) | `play(0, tokenInWei, 0, minEthOut, openMax)` | `src/hooks/useCauldronSwap.ts:532-550` | `value=0`; `tokenInWei = parseEther(tokenIn)` clamped to the on-chain balance (`:539-540`); `minEthOut` from `SwapWidget.tsx:217` in the QUOTE's decimals (`outDecimals = qDec`) |
| quote token (mock) | `mint(address,uint256)` | `src/hooks/useCauldronSwap.ts:340-348` (`mintTestQuote`) | testnet faucet, `parseUnits(amount, decimals)` — decimals passed in |
| `collection` | `reveal(uint256)` | `src/hooks/useCauldronSwap.ts:449-457`, `src/components/wizards/CreatureModal.tsx:87` | none |
| `collection` | `revealBatch(uint256[])` (chunked ≤50) | `src/hooks/useCauldronSwap.ts:478-490` | none |
| `collection` | `openReady(uint256)` | `src/hooks/useCauldronSwap.ts:495-502` | none |
| `collection` | `redeem(uint256)` (vault) | `src/components/wizards/CreatureModal.tsx:104` | none |
| `registry` | `relaunch()` | `src/hooks/useCauldronMachine.ts:299` | none |
| `governor` | `vote(uint256)` | `src/hooks/useCauldronMachine.ts:317` | none |
| `registry` | `claimByBurn(uint256,uint256)` | `src/hooks/useCauldronMachine.ts:325` | none |
| `governor` | `propose(...)` | `src/hooks/useCauldronMachine.ts:397-404` | simulated first (`:366` note) |
| `registry` | `redeemOgFren(uint256)` | `src/hooks/useGenesisBonus.ts:174-176`, `src/components/wizards/FrenDetailModal.tsx:152-153` | none |
| `registry` | `recycleCollectionNFT(uint256,uint256)` | `src/hooks/useCollectionFloor.ts:112-114` | none |
| `registry` | `buyCollectionNFT(uint256,uint256)` | `src/hooks/useCollectionFloor.ts:128-130` | ETH value (floor price read on-chain) |
| `registry` | `rotateSliceFrom(uint256,uint256,uint256,(…))` | `src/hooks/useTreasuryRotation.ts:424-427` | `minOut` from `quoteSlice` simulate (`:397-405`); venue checked by `isVenueAllowed` (`:372-376`) |
| `treasuryGovernor` | `propose(address,uint256)` / `vote(uint256,bool)` / `execute(uint256)` | `src/hooks/useTreasuryRotation.ts:432, 440, 447` | none |
| `dividend` | `claimMany(uint256[])` | `src/hooks/useMiFrensDividend.ts:325-330` | none |
| `dividend` | `castMany(uint256[])` | `src/hooks/useMiFrensDividend.ts:341` | none |
| `dividend` | `claimTokens(uint256)` | `src/hooks/useMiFrensDividend.ts:359-361` | per-id loop |
| `dividend` | `withdrawOwedToken(address)` | `src/hooks/useMiFrensDividend.ts:370-372` | asset argument |
| `dividend` | `withdrawOwed()` | `src/hooks/useMiFrensDividend.ts:414` | none |
| royalty router (resolved from `royaltyInfo`) | `sweep(address)` | `src/hooks/useMiFrensDividend.ts:405-407` | address(0) or a quote asset |
| `perpEngine` | `openLong(uint8,uint256,uint256,uint256)` | `src/hooks/usePerpEngine.ts:226-229` | `value = parseEther(collateralEth)`, 4th arg must equal value; `minTokenOut = notional/spotPrice − slip` |
| `perpEngine` | `openShort(uint8,uint256,uint256,uint256)` | `src/hooks/usePerpEngine.ts:241-244` | same shape; floor in ETH |
| `perpEngine` | `close(uint256,uint256)` | `src/hooks/usePerpEngine.ts:259-262`, `:272-275` (closeAll) | floor 0 when unpriceable (documented) |
| `perpEngine` | `claimLiquidatorBadges(...)` | `src/components/wizards/LiquidatoorBadges.tsx:124-126` | none |
| `perpVault` | `depositEth()` | `src/hooks/usePerpVault.ts:129` | `value = parseEther(eth)` |
| `perpVault` | `deposit(uint256)` | `src/hooks/usePerpVault.ts:161-165` | `value = raw` when native, `0` when ERC20 — **R5B feeds this** |
| `perpVault` | `withdrawEth(uint256)` / `withdrawToken(uint256)` | `src/hooks/usePerpVault.ts:134, 182` | shares |
| `perpVault` | `depositToken(uint256)` | `src/hooks/usePerpVault.ts:177` | `parseEther` — correct, the iteration token is 18-dec |
| `perpVault` | `claimPendingEth()` / `claimPendingToken()` / `claimTokYield()` | `src/hooks/usePerpVault.ts:187, 192, 198` | none |
| quote token | `approve(spender=perpVault, maxUint256)` | `src/hooks/usePerpVault.ts:156, 172` | **infinite approval** |
| `presale` (`contracts.presale`) | `mint(uint256)` | `src/hooks/useMiFrensPresale.ts:239-241` | `value` from `priceWeiLive` (on-chain read), `simulateContract` first (`:180, :228`) |
| iteration token | `approve(spender=gachaRouter, amount)` | `src/hooks/useCauldronSwap.ts:408-412`, `:293-297` | bounded to `spend` — good |
| iteration token | `approve(spender=gachaRouter, maxUint256)` | `src/hooks/useCauldronSwap.ts:512-521` (`approveToken`, the SELL path) | **infinite approval** — see R5H |
| collection (ERC721) | `safeTransferFrom(address,address,uint256)` | `src/components/wizards/FrenDetailModal.tsx:127-129` | recipient is a user-typed address |

No `sendTransaction` / `encodeFunctionData` / custom signer wrapper exists in `src/` (grep for all five patterns returned only the `useWriteContract` sites above). Chain is enforced on every path by a `chainId !== CAULDRON.chainId → switchChainAsync` guard or `ensureChain()`; I found no write missing it.

---

## 6. LIVENESS NOTES (runbook material)

**(5) What kills Ponder, and what happens next.**
- *Fatal class* (DERIVED, from `indexer/ponder.config.ts:87-104`): a log whose `blockHash` disagrees with the block fetched for that height after a reorg. Ponder treats it as fatal. Observed once at Sepolia 11704817; the LOGS were canonical and `eth_getBlockByNumber` served the orphan. Tenderly had it right; publicnode and 1rpc served the losing sibling; ankr and blastapi had neither.
- *Restart* (VERIFIED from config): `railway.json` — `ON_FAILURE`, max 10 retries, healthcheck `/health`. `/health` is Ponder's own liveness (always 200 once the server is up); the divergence beacon is deliberately at `/freshness` (`indexer/src/api/index.ts:1280-1288`) precisely because a 503 there once deadlocked deploy promotion.
- *Crash loop*: yes, if the RPC list still round-robins. Recovery is `PONDER_RPC_URL=<one good provider>` then `railway up`. **A schema bump does not fix this** — `start.mjs:14-19` only chooses the Postgres schema; the bad data path is the live RPC, not the stored rows. Re-indexing into a fresh schema from a provider serving an orphan reproduces the same fault.
- *Self-heal*: the in-process watchdog (`index.ts:1291-1307`) exits(1) after ~9 min of *sustained, previously-healthy* divergence. It is gated on `everHealthy`, which is in-memory — see R5E.
- *Alerting*: none in the tree. `/freshness` is the only external signal and nothing polls it except the browser and `deploy-round.mjs:76-91`.
- *What still works with the indexer dark* (DERIVED from the hooks): everything on `useReadContract` — the swap widget's balances/allowance, `progress`/`missStreak`/`oddsForPlay` (`CrystalCauldronGame.tsx:141-167`), perp position reads, presale price/supply (`useMiFrensPresale`), the machine state in `useCauldronMachine`, floor reads, and every *write* in §5. Dead: candles, trade tape, activity feed, perp heatmap, collection floors, proposals, iterations, gacha lifetime stats, seeding progress. `useIndexerHealth` shows a degraded banner for `down`/`stale`/`syncing` — except in the R5E boot-into-divergence case.

**(6) Frontend RPC.** (VERIFIED from source.) `src/config/chains.ts:141-145`:
```
[sepolia.id]: fallback(
  SEPOLIA_RPCS.map((u) => http(u, { batch: { wait: 24 }, retryCount: 2, retryDelay: 250 })),
  { retryCount: 2, retryDelay: 300 },
),
```
`VITE_SEPOLIA_RPC_URL` **is** comma-split (`:92-93`) and every entry is prepended to four public nodes; viem's `fallback` rolls over on error/429. `sepolia.rpcUrls` is also overridden (`:107-113`) so chain-default paths cannot escape the list. Whether it is populated in production is **NOT VERIFIABLE** (nothing in `vercel.json`, no `.env.production`; the only evidence is `.env.vercel-backup`, which defines `VITE_CAULDRON_INDEXER` and `VITE_X_CLIENT_ID` but *not* `VITE_SEPOLIA_RPC_URL`). Rollover risk: `spotPrice` used for `minOut` comes from the indexer, not from these nodes (`SwapWidget.tsx:215-217` via `m.spotPrice`), so a provider rollover cannot silently change the floor; the reads it *can* change are balance/allowance/`priceWeiLive`, and a lagging node there causes a revert, not a bad price. `targetChain` (Arc) gets a single `http(RPC_URL)` with **no fallback** — one endpoint, no rollover.

**(7) Keeper / operator keys.** (VERIFIED from source.) `keeper.sh` requires `contracts/solidity/.env.sepolia` (`:31`), resolves the signer through `scripts/lib/signer.sh` — keystore preferred, raw `PRIVATE_KEY` fallback announces itself — so with `KEYSTORE_ACCOUNT` no key appears in argv or `ps`. Addresses are cross-checked against the manifest case-insensitively and the script *exits* on drift (`:45-48`). Reorg safety: actions are idempotent re-derived-from-chain checks (`isLiquidatable` then `liquidate`), sends are sequential and each waits on `cast send`, so a reorged-out liquidation is simply re-detected next sweep — no double action. Two weaknesses: every `cast send` is `>/dev/null 2>&1` (silent failure) and the sweep is an O(nextId) scan (R5G). `indexer/seed-keeper.mjs` holds `SEED_KEEPER_PK` from the environment, uses the FIRST `PONDER_RPC_URL` entry only (`:81-84`), guards overlap with an `inFlight` latch (`:93-97`), simulates before sending, waits for the receipt with a 120 s timeout, and wraps everything in try/catch so it cannot take the indexer down. A reorged-out `poke` is re-derived from `placedWad` on the next tick — no double spend. `scripts/market-round.mjs` **does not exist**; `scripts/marketmaker.sh` (212 lines) is the market-move helper.

**(8) Deploy pipeline.** (VERIFIED from source.) `deploy-round.mjs` does *not* build or broadcast contracts — it runs `railway up --detach` in `indexer/`, optionally `git push` (Vercel), then polls `/cauldron` + `/freshness` for ≤10 min asserting `poolId` match, `ok`, and `warmingUp === false`. It warns when Railway carries drift-prone env vars (`DATABASE_SCHEMA|POOL_IDS|PERP_ENGINE|…`) that would silently override the manifest. Contract builds live in `auto-deploy.sh` (`FOUNDRY_PROFILE=cauldron`, plain `forge build --sizes`) and `deploy-testnet.sh` / `deploy-arc.sh` / `go-testnet.sh` / `arc-ignite.sh` (same profile, `forge script … --broadcast`). **No `forge clean` and no `--force` anywhere**, so a stale `out/` is possible. Address readback is `apply-deployment.mjs`, reading `contracts/solidity/broadcast/<script>/<chain>/run-latest.json`; the name match is deliberately fuzzy (`Name` or `Name.0.8.30`, `:65-79`) with a documented chain-read fallback for `CauldronHook` (`:101-108`) and a *loud* refusal when `MockQuoteToken` CREATEs are absent (`:179-194`) rather than a silent skip. `verify-manifest.mjs` runs on `prebuild` and in `.github/workflows/deploy.yml:64`; `verify-selectors.mjs` runs nowhere (R5D).
