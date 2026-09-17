# H5 — off-chain layer & the source↔chain seam (Robinhood chain 4663)

Scope: `src/config/`, `src/hooks/`, `api/`, `indexer/`, `scripts/`, `indexer/deployments/*.json`.
No file under `audit/`, `contracts/solidity/test/`, `hive/`, or any AUDIT/REDTEAM/REVIEW `.md` was opened; no `git log`.
I restored `indexer/deployments/round.json` byte-for-byte after the build PoCs (`diff` → IDENTICAL).
I did **not** modify `.claude/agents/hunter.md` (it was already dirty at start).

---

## 1. Model from code

**Chain/address resolution (the seam).** `src/config/deployments.ts:24-29` hard-codes
`DEPLOYMENTS = { 11155111: round.json, 5042002: round.arc.json }`. `resolveInitialChain()`
(`:58-77`) returns only a key of that map: `?chain=` → `localStorage` → `VITE_NETWORK`
(`"target"|"mainnet"|"arc"` → 5042002, else 11155111). `ACTIVE_ROUND = DEPLOYMENTS[SELECTED_CHAIN_ID]`
(`:82`). `src/config/chains.ts:37` then does
`CHAIN_ID = SELECTED_CHAIN_ID !== sepolia.id ? SELECTED_CHAIN_ID : ENV_CHAIN_ID` and
`:133 IS_TARGET = SELECTED_CHAIN_ID !== sepolia.id`; `:180-181 ACTIVE_CHAIN/ACTIVE_CHAIN_ID`.
`src/config/cauldron.ts:34 CAULDRON.chainId = ACTIVE_CHAIN_ID` — every `writeContract`/
`switchChainAsync` uses it. Addresses come only from the manifest; ABIs are hand-written
per hook, not generated from `contracts/solidity`.

**Frontend reads.** All market data is HTTP from one indexer URL (`cauldron.ts:73`,
manifest-only, no env override). On-chain reads are wagmi/viem via `VITE_RPC_URL`.
**Writes:** `useCauldronSwap.buy/sell/spin` → `CauldronGachaRouter.play`,
`usePerpEngine.openLong/openShort`, `usePerpVault.depositEth`, ERC20 `approve`.

**minOut path (traced end-to-end).** `TheCauldron.tsx:510 livePerpPrice = tradeTape[last].price`
← `useSwapTape.ts:36 fetch(${INDEXER}/recent/<gen>)`; fallback `m.spotPrice`
← `useCauldronMachine.ts:162,261` (indexer `/candles` + `/cauldron`). →
`SwapWidget.tsx:200,202,211-218 minOut` → `useCauldronSwap.ts:297/306` → calldata.
On an ERC20 quote, the **spend amount** is `quoteExpected` (`SwapWidget.tsx:171-177`)
from `useLpComposition.prices` ← indexer `/treasury`, which itself proxies the on-chain
`usdPerRawUnit` (`indexer/src/api/index.ts:766,800`).

**API entrypoints & gates.** `api/brand.ts` GET public; POST = Origin allowlist +
EIP-191 `recoverMessageAddress` against `BRAND_SIGNERS` + 10-min TTL + monotonic `ts` +
`MAX_ROWS` + 2.5 MB cap (`:138-200`). `api/fren-teach.ts:85-88` shared secret
`x-fren-admin` (timing-safe hash compare). `api/fren-ask.ts` unauthenticated, IP-rate-limited.
`api/x-token.ts:16` `redirect_uri` allowlist. `api/cauldron/*` public GET, `CORS *`.
`indexer/src/api/index.ts` is **read-only** (every route `app.get`); `/graphql` mounted at
`:116-117` behind a body cap.

**What the indexer trusts.** `ponder.config.ts:23 chainId = round.chainId`; RPC from
`PONDER_RPC_URL` or a chain-keyed default (`:117`). Health (`/freshness`) uses a *different*
client, `API_RPC_URL` (`indexer/src/api/index.ts:127-135`).

---

## 2. Findings

```
id: T5A    severity: Critical   confidence: VERIFIED
subsystem: frontend chain resolution
src/config/deployments.ts:24-29
    export const DEPLOYMENTS = {
      11155111: sepoliaRound,
      5042002: arcRound as typeof sepoliaRound,
    } as const;
src/config/chains.ts:37
    const CHAIN_ID = SELECTED_CHAIN_ID !== sepolia.id ? SELECTED_CHAIN_ID : ENV_CHAIN_ID;
src/config/chains.ts:133
    export const IS_TARGET = SELECTED_CHAIN_ID !== sepolia.id;
src/config/cauldron.ts:34
      chainId: ACTIVE_CHAIN_ID,
title: The documented Robinhood cutover cannot produce a build that targets chain 4663; it
       ships an app whose CAULDRON.chainId is 11155111 and which force-switches the user's
       wallet to Sepolia before submitting Robinhood-addressed, value-bearing calldata.
precondition: the cutover exactly as written in indexer/deployments/round.robinhood.template.json:2
  ("copy this over round.json … then node scripts/deploy-round.mjs --push"). Neither
  scripts/deploy-round.mjs nor scripts/apply-deployment.mjs touches src/config/deployments.ts
  (grepped: neither file mentions DEPLOYMENTS or deployments.ts).
sequence:
  1. Operator copies the Robinhood template over round.json, fills every <FILL>, sets
     VITE_CHAIN_ID=4663 and every VITE_CHAIN_* var, builds, deploys.
  2. resolveInitialChain() can only return 11155111 or 5042002 (there is no 4663 key).
     - VITE_NETWORK unset/"testnet" -> 11155111. ACTIVE_ROUND = the Robinhood manifest,
       but IS_TARGET=false, so ACTIVE_CHAIN=sepoliaFixed, ACTIVE_CHAIN_ID=11155111.
       cauldron.ts:25 detects the 4663-vs-11155111 mismatch and only console.error()s
       ("Loud but non-fatal", :22-23). CAULDRON.chainId = 11155111.
     - VITE_NETWORK="mainnet" -> 5042002. ACTIVE_ROUND = round.arc.json: the Robinhood
       manifest is not read at all; the app runs on Arc TESTNET addresses.
  3. User clicks Buy. useCauldronSwap.ts:194-196 / 543-545:
       if (chainId !== CAULDRON.chainId) await switchChainAsync({ chainId: CAULDRON.chainId });
     -> the wallet is switched to SEPOLIA, then writeContractAsync sends
       play(...) with value: parseEther(ethIn) to the ROBINHOOD gachaRouter address.
  4. Every indexer fetch, every read hook and every explorer link follows the same wrong chain.
capital: none. This is a deploy-time brick, not an attack requiring capital.
attacker_cost: 0 (self-inflicted). An outside attacker's optional amplification: the repo is
  public, so the CREATE2 initcode for the router/hook is public; a squatter who can reproduce
  the deployer+salt could place a contract at the same address on Sepolia and receive the
  force-switched value calls. Not required for the brick.
damage: the mainnet frontend never talks to chain 4663. 100% of user-initiated value flow
  either reverts or lands on the wrong chain. Permanent until src/config/deployments.ts is
  edited and the app rebuilt. At any TVL.
poc: audit/RH_MAINNET_2026-09-16/poc/h5/h5_chain4663_seam.sh   needs_fork: no
```

**PoC transcript (VERIFIED, run 2026-09-15).**
Command: `bash audit/RH_MAINNET_2026-09-16/poc/h5/h5_chain4663_seam.sh`
The script copies the template over `round.json`, sets `chainId: 4663`, runs the real
`npm run build` twice (`VITE_NETWORK=mainnet` and `=testnet`) with all `VITE_CHAIN_*`
set for Robinhood, then greps `dist/`. Emitted bundle (`dist/assets/index-JNC5KA7u.js`),
verbatim:

```js
Ea={11155111:z1,5042002:tS}            // DEPLOYMENTS — no 4663 key survives minification
function Ih(e){return Object.prototype.hasOwnProperty.call(Ea,e)}
function oS(){ …const e="testnet"… return e==="target"||e==="mainnet"||e==="arc"?5042002:11155111}
const Ur=oS(), de=Ea[Ur]              // SELECTED_CHAIN_ID, ACTIVE_ROUND
Rc=4663, aS=Number.isSafeInteger(Rc)&&Rc>0?Rc:5042002, q1=Ur!==ha.id?Ur:aS   // CHAIN_ID
de.chainId!==Wn&&console.error(`[cauldron] MANIFEST/CHAIN MISMATCH …`)        // Wn=Ld.id
```

`targetChain.id` does become 4663 on the testnet-branch build, but `IS_TARGET` (`Ur!==ha.id`)
is **false**, so `ACTIVE_CHAIN` is `sepoliaFixed` and `Wn` (`ACTIVE_CHAIN_ID`) is 11155111 —
which is what `CAULDRON.chainId` and every `switchChainAsync` use. Confirmed by the presence
of the mismatch `console.error` in the shipped bundle.

Sub-effect of the same root cause, same severity class: because `IS_TARGET` is false,
`src/config/chains.ts:176-177`
```ts
export const NATIVE_SYMBOL = IS_TARGET ? targetChain.nativeCurrency.symbol : "ETH";
export const NATIVE_DECIMALS = IS_TARGET ? targetChain.nativeCurrency.decimals : 18;
```
silently discards `VITE_CHAIN_DECIMALS` and `VITE_CHAIN_CURRENCY` on a 4663 build. If
chain 4663's native gas token is not 18 decimals, every figure is off by `1e(18-d)` with
no warning — and the validated-decimals machinery at `:54-56` never runs.

---

```
id: T5B    severity: High   confidence: VERIFIED
subsystem: indexer RPC default
indexer/ponder.config.ts:88-91 (comment) and :117 (code)
    // CHAIN-AWARE default: pick the fallback set from the manifest's chainId so
    // an unset PONDER_RPC_URL can NEVER silently point Sepolia nodes at a
    // Robinhood (4663) manifest — that mismatch = wrong/empty data or a crash.
    …
    const SEPOLIA = ["https://sepolia.gateway.tenderly.co"];
    const ARC     = ["https://rpc.testnet.arc.network"];
    const DEFAULTS = chainId === 5042002 ? ARC : SEPOLIA;
    const env = (process.env.PONDER_RPC_URL ?? "")…
    const list = env.length > 0 ? env : DEFAULTS;
title: The comment claims the exact protection it does not implement — chainId 4663 falls to
       the `else` branch, so an unset PONDER_RPC_URL points a Robinhood manifest at a SEPOLIA
       node, and the indexer syncs the wrong chain while declaring chain id 4663.
precondition: Robinhood manifest deployed with PONDER_RPC_URL unset or blank on Railway.
  `.env.example:63` lists PONDER_RPC_URL with an empty value, i.e. unset is the shipped state.
sequence:
  1. round.json.chainId = 4663. ponder.config.ts:23 chainId = 4663.
  2. :117 `4663 === 5042002` is false -> DEFAULTS = SEPOLIA.
  3. Ponder declares `chains: { cauldron: { id: 4663 } }` (:74) while fetching blocks and
     logs from sepolia.gateway.tenderly.co.
  4. `pollingInterval` (:138) takes the same wrong branch -> 4000 ms on a fast chain.
  5. /freshness uses a SEPARATE client (indexer/src/api/index.ts:127-135) whose default when
     API_RPC_URL is unset is five SEPOLIA public nodes — so the divergence check compares
     Sepolia against Sepolia and can report healthy.
capital: none / not applicable. This is an operator-config trap, not a paid attack.
attacker_cost: 0. An attacker who knows the Robinhood registry/hook addresses are CREATE2-
  derived from public initcode can pre-place contracts at those addresses on SEPOLIA and
  emit the protocol's own events, feeding fabricated generations, prices and floors into
  the mainnet indexer that the frontend then signs minOut against (see T5C). Cost: Sepolia
  gas only.
damage: the entire read layer (prices, candles, floors, perp positions, proposals) serves
  another chain's data as Robinhood data, and the frontend computes signed slippage floors
  from it. Silent — no banner fires if /freshness agrees with the sync.
poc: audit/RH_MAINNET_2026-09-16/poc/h5/h5_ponder_default_chain.mjs   needs_fork: no
```

```
id: T5C    severity: High   confidence: DERIVED
subsystem: swap slippage floor / price source
src/hooks/useSwapTape.ts:14-16,36
    * This is the ONE price source for the app: the brew line, the trading chart and
    * the header all derive from it …
        const res = await fetch(`${INDEXER}/recent/${generation}?limit=5000`, …);
src/components/cauldron/TheCauldron.tsx:510
    const livePerpPrice = tradeTape.length ? tradeTape[tradeTape.length - 1].price : m.spotPrice;
src/hooks/useCauldronMachine.ts:261
        spotPrice: d.spotPrice && d.spotPrice > 0 ? d.spotPrice : prev.spotPrice,
src/components/cauldron/SwapWidget.tsx:211-218
    const minOutFor = (expected: number, decimals: number): bigint => { …
      return (parseUnits(expected.toFixed(decimals), decimals) * (10_000n - slipBps)) / 10_000n; }
    const minOut = minOutFor(expectedOut, outDecimals);
title: Every slippage floor the user signs is derived from a single unauthenticated HTTP
       endpoint's cached, lagging view of the price, with no on-chain quote anywhere in the
       path and no freshness gate at the moment of signing.
precondition: none. This is the normal path for every buy and sell.
sequence:
  1. Attacker buys into the thin generation pool, moving the mark up N%.
  2. Ponder polls (4000 ms default on 4663 per T5B), then the indexer's own cache
     (indexer/src/api/index.ts:26 `public, max-age=5, s-maxage=5, stale-while-revalidate=30`)
     plus the frontend poll interval hold that pumped price in front of users for up to
     ~35 s after it is no longer true.
  3. Attacker sells back out, paying only the round-trip hook fee + impact.
  4. For the remainder of the stale window, every victim buy computes
     estTokensOut = netOfFee(pay)/spotPrice against the PUMPED price, so its floor is ~N%
     below fair. The attacker sandwiches each victim down to that floor and pockets the gap.
  5. useCauldronMachine.ts:261 makes the staleness STICKY: if the indexer returns 0 or is
     unreachable, `prev.spotPrice` is kept indefinitely and the app keeps signing floors
     against a frozen price. IndexerHealthBanner.tsx:26-27 only renders a banner; it does
     not disable the Trade button, and nothing in SwapWidget reads `health.degraded`
     (grepped: `degraded` appears only in IndexerHealthBanner.tsx).
capital: sized to the pool, not to the victim. FLASHLOANABLE: NO — the pump must survive at
  least one indexer poll + cache TTL, so the capital is held for several blocks. A whale or a
  short-term borrow works; a single-transaction flashloan does not.
attacker_cost: two hook fees on the round trip plus the price impact the attacker eats on the
  way back out (both paid whether or not a victim shows up), plus gas.
damage: up to (N% + the victim's slipPct) of every trade signed inside the stale window.
  MAX_SLIP_PCT = 50 (SwapWidget.tsx:66) caps the self-inflicted half at 50%. At a 100 ETH
  generation TVL and a 1 ETH victim buy with a 25% pump, ~0.25 ETH per victim.
poc: not reproduced end to end — see Leads L3 for the exact next step.   needs_fork: yes
```

```
id: T5D    severity: Medium   confidence: VERIFIED
subsystem: quote decimals fallback
src/config/quotes.ts:43
    export const KNOWN_QUOTES: QuoteAsset[] = (round.quoteAssets ?? []).map(…)
src/config/quotes.ts:58-64
      return {
        address: (quote ?? NATIVE_QUOTE) as Address,
        symbol: `${(quote ?? "").slice(0, 6)}…${(quote ?? "").slice(-4)}`,
        name: "Unlisted quote",
        decimals: 18,
title: Any quote asset not enumerated in the manifest is assumed 18-decimal; the Robinhood
       template has no `quoteAssets` key at all, so on that deployment EVERY quote is 18.
precondition: a generation rotated into an ERC20 quote whose address is not in
  `round.quoteAssets` — which is every quote on the Robinhood template, and is also the
  steady state for any quote approved on-chain after the manifest was built.
sequence:
  1. Live generation quote rotates to a 6-decimal token (USDG-class).
  2. quoteMeta() misses -> decimals 18.
  3. SwapWidget.tsx:194 `const qDec = qNative ? 18 : quoteDecimals;`
     :217 `const outDecimals = mode === "buy" ? 18 : qDec;`
     :218 minOut = parseUnits(estEthOut.toFixed(18), 18) -> a sell floor 1e12 too large.
  4. Every sell reverts on Slippage. The displayed minimum-out
     (`:502,591 formatUnits(minOut, qDec)`) is 1e12 wrong, so the number on screen does not
     explain the revert.
capital: none.
attacker_cost: 0 — it triggers on a legitimate governance rotation, no attacker needed. A
  Vandal can force it by getting a 6-decimal quote approved and rotated to.
damage: selling is bricked in the UI for the duration; buys are unaffected (their floor is
  token-side, 18 correct, and the ERC20 spend derives from `usdPerRawUnit`, which already
  carries decimals — see Refutation R2). Recoverable by editing the manifest + redeploy.
poc: audit/RH_MAINNET_2026-09-16/poc/h5/h5_quote_decimals.mjs   needs_fork: no
```

```
id: T5E    severity: Low   confidence: VERIFIED
subsystem: manifest template completeness / dead env var
indexer/deployments/round.robinhood.template.json (whole file — no `positionManager`,
  no `quoteAssets`, no `legacyThresholdEth`, no `legacyBps`)
.env.example:19
    VITE_CAULDRON_INDEXER=
src/config/cauldron.ts:73
    export const CAULDRON_INDEXER: string = round.indexerUrl.replace(/\/+$/, "");
title: The Robinhood template is missing keys the build's own verifier requires, and
       .env.example advertises VITE_CAULDRON_INDEXER, which no code reads.
sequence:
  1. `npm run build` on the unfilled template fails prebuild with 16 errors including
     `contracts.positionManager is missing` (VERIFIED — /tmp/h5_build.log). Good that it
     fails; the template itself is incomplete beyond the <FILL>s, so the cutover has an
     undocumented step.
  2. `grep -rn VITE_CAULDRON_INDEXER src/` returns nothing but the .env.example line; the
     indexer URL is manifest-only (cauldron.ts:66-72 says so deliberately). An operator who
     sets it on Vercel gets silence, not an override.
capital: none.   damage: one failed deploy / one misconfigured operator.
poc: bash audit/RH_MAINNET_2026-09-16/poc/h5/h5_chain4663_seam.sh (first variant, before it
     was changed to fill the manifest — reproduce with `cp round.robinhood.template.json
     round.json && npm run build`)   needs_fork: no
```

---

## 3. Refutations — surfaces I hit hard that held

**R1 — `<FILL>` placeholders reaching production. HELD (VERIFIED).**
I copied `round.robinhood.template.json` verbatim over `round.json` and ran the real
`npm run build`. `package.json:9-11` runs `prebuild` → `scripts/verify-manifest.mjs`, which
exited non-zero with all 16 placeholders named individually (`/tmp/h5_build.log`). A
`<FILL>` address cannot reach a bundle. *However* `verify-manifest.mjs:44` only checks
`Number.isInteger(m.chainId)` — it does not validate the chainId against the supported set,
which is what lets T5A through.

**R2 — the ERC20 spend amount being an invented off-chain number. HELD (VERIFIED by grep).**
`SwapWidget.tsx:171-177` builds `quoteExpected` (which becomes the exact `spend` at
`useCauldronSwap.ts:277,304`) from `useLpComposition.prices`. I chased that to
`indexer/src/api/index.ts:766,800,1590`, which are `readContract(... functionName:
"usdPerRawUnit" ...)` — an on-chain oracle read, not an indexer-invented price, and in
USD-per-RAW-unit so it already carries decimals (which is why T5D does not corrupt the spend).
`useCauldronSwap.ts:256-258` additionally refuses to sign when `quoteExpected <= 0n`, and
`:292-296` bounds the approval to `spend` rather than `maxUint256`. Residual: the frontend
relays the value over HTTP instead of reading `usdPerRawUnit` itself from
`CAULDRON.quoteRotator`, which it has. That is Lead L2, not a finding.

**R3 — `x-forwarded-for` rate-limiter bypass. HELD (VERIFIED by reading all three).**
`api/fren-ask.ts:161-166`, `api/fren-teach.ts:59-63`, `api/x-token.ts:27-30` all prefer
`x-real-ip` and otherwise take `hops[hops.length - 1]` — the **rightmost** hop. A client
prepending its own `x-forwarded-for` cannot move the bucket. I attacked the leftmost-element
bypass and there is no leftmost read anywhere in `api/`.

**R4 — `api/brand.ts` unauthenticated write. HELD (VERIFIED by reading `:138-205`).**
POST requires: an Origin in `BRAND_ALLOWED_ORIGINS` when present, a non-empty `BRAND_SIGNERS`
(else 503), `ts` within a 10-minute TTL, a well-formed 65-byte sig, `recoverMessageAddress`
landing in `SIGNERS`, a strictly-increasing `ts` per row (replay/rollback blocked at `:198`),
`MAX_ROWS`, `MAX_GEN = round.round + 16`, and a 2.5 MB body cap. No CORS header is emitted on
the write path. I could not construct an unauthorized write.

**R5 — secrets in the shipped bundle. HELD (VERIFIED).**
After a real `npm run build`, I scanned every `dist/assets/*.js` for `gsk_`, `AIzaSy`, `sk-`,
`postgres(ql)://`, JWTs, `alchemy.com/v2/<key>`, `infura.io/v3/<key>`. Zero hits. Every
`VITE_*` var in `.env.example` is genuinely public (chain metadata, a WalletConnect project
id, an OAuth *client* id). `X_CLIENT_SECRET`, `FREN_ADMIN_SECRET`, `GROQ_API_KEY`,
`GEMINI_API_KEY`, `DATABASE_URL` are all read only via `process.env` in `api/`, never `VITE_`.
`.env.local`, `.env.recovery`, `.env.vercel-backup` and `contracts/solidity/.env` are all
matched by `.gitignore:61 .env*` (`git check-ignore -v` confirms) and none is tracked
(`git ls-files | grep -i env` returns only the three `.example`/`.template` files).

**R6 — the indexer as a write surface. HELD (VERIFIED by grep).**
Every route in `indexer/src/api/index.ts` is `app.get` (34 of them, enumerated). The only
non-GET mounts are `graphql()` at `:116-117`, both behind `graphqlBodyCap` at `:114-115`.
There is no mutation resolver and no admin route.

---

## 4. Leads (HYPOTHESIS — exact next step each)

**L1 — CREATE2 address collision between the Robinhood and Sepolia deployments.**
T5A force-switches the wallet to Sepolia and then sends value to the Robinhood router address.
If the Robinhood deploy reuses the same CREATE2 factory + salt + initcode as the Sepolia one,
those addresses already hold the *old Sepolia round's* live contracts, which would **accept**
the call. Next step: `cast code <robinhood gachaRouter>` against a Sepolia RPC once the
Robinhood manifest is filled; non-empty means T5A's damage escalates from "reverts" to
"executes against a stale contract".

**L2 — the frontend never verifies `usdPerRawUnit` on-chain.**
`CAULDRON.quoteRotator` is in the manifest (`cauldron.ts:44`) and the app has a viem client.
Next step: add a `readContract(quoteRotator.usdPerRawUnit)` in `SwapWidget` and assert it
within 1% of `lp.prices[quote]` before signing; measure how far apart they can be pushed.

**L3 — reproduce T5C.** Next step: run the indexer locally against an anvil fork
(`DATABASE_URL` unset → pglite), execute a pump swap, `curl $INDEXER/recent/1` and record
the price, dump back out, then `curl` again inside the 30 s `stale-while-revalidate` window
and show the endpoint still returns the pumped price. Then encode the calldata `SwapWidget`
would produce at that price and compare `minOut` against a live `quoteExactInput`.

**L4 — serverless rate-limit state is per-lambda-instance.**
`api/fren-ask.ts` keeps `rlHits` in module memory. Vercel runs many concurrent instances, so
the effective limit is `RL_MAX × instances`, and `fren-ask` calls a **paid** LLM
(`GROQ_API_KEY`/`GEMINI_API_KEY`). Next step: measure `RL_WINDOW_MS`/`RL_MAX` and the per-call
token cost, then decide whether a shared store (the Neon `DATABASE_URL` already present at
`:38`) or a hard daily cap is needed before mainnet.

**L5 — indexer reorg/restart behaviour (notes for the liveness pass you asked for).**
`ponder.config.ts:92-109` documents a Sepolia reorg that crash-looped Ponder because a log's
`blockHash` disagreed with `eth_getBlockByNumber` for the same height; the mitigation was to
default to **one** provider (`rank: false` ordered failover, never round-robin) so two nodes
can never be asked about the same height. That mitigation is **chain-keyed by the same broken
`chainId === 5042002` test as T5B**, so on 4663 the single default provider is a Sepolia node.
`indexer/start.mjs` + `railway.json` ON_FAILURE, and `evaluateHealth()`
(`indexer/src/api/index.ts:1291-1358`) with `divergingSince` + a 4 s cache and
"history cannot excuse divergence" (`:1338`), are the restart/divergence machinery —
re-read `start.mjs:1-end` and `railway.json` first in that pass. `/freshness` is the beacon
(`:1364`); `/health` is deliberately Ponder's own (`:1359-1363`).

---

## Env vars required for chain 4663

| Var | Set where | Read at | If unset / blank — what SILENTLY happens |
|---|---|---|---|
| `VITE_NETWORK` | Vercel build | `src/config/deployments.ts:74` | defaults `"testnet"` → `SELECTED_CHAIN_ID = 11155111`. App reads `round.json` under the **Sepolia** key and `IS_TARGET=false`. Setting it to `mainnet` is **worse**: selects 5042002 → `round.arc.json`, Robinhood manifest ignored. **Neither value can reach 4663** (T5A). |
| `VITE_CHAIN_ID` | Vercel build | `chains.ts:29,36` | defaults **5042002 (Arc testnet)**. Also **ignored whenever `SELECTED_CHAIN_ID !== sepolia.id`** (`:37`). |
| `VITE_CHAIN_NAME` | Vercel build | `chains.ts:45` | `"Arc Testnet"` in the header of a mainnet app. |
| `VITE_RPC_URL` | Vercel build | `chains.ts:46,155` | **`https://rpc.testnet.arc.network`** — a testnet RPC serving a mainnet app. |
| `VITE_EXPLORER_URL` | Vercel build | `chains.ts:47,187,195-198` | `https://testnet.arcscan.app`; every tx/address/NFT link points at the wrong explorer. |
| `VITE_EXPLORER_NAME` | Vercel build | `chains.ts:48` | `"Arcscan"`. |
| `VITE_CHAIN_CURRENCY` | Vercel build | `chains.ts:63` | `"ETH"`. Also overridden to `"ETH"` by `chains.ts:176` whenever `IS_TARGET=false`. |
| `VITE_CHAIN_CURRENCY_NAME` | Vercel build | `chains.ts:62` | `"Ether"`. |
| `VITE_CHAIN_DECIMALS` | Vercel build | `chains.ts:54-56` | **18**, and `chains.ts:177` discards it entirely when `IS_TARGET=false`. If 4663's gas token is not 18-dec, every balance/price is off by `1e(18-d)` with no warning. |
| `VITE_CHAIN_IS_TESTNET` | Vercel build | `chains.ts:75` | `"true"` → `testnet: true` on a mainnet chain; wallets may show a testnet badge. |
| `VITE_WALLETCONNECT_PROJECT_ID` | Vercel build | `chains.ts:79-85,140` | placeholder → the WalletConnect connector is **silently omitted** (`:164`). Injected wallets only; no mobile wallet can connect. |
| `VITE_SEPOLIA_RPC_URL` | Vercel build | `chains.ts:99` | falls back to four public Sepolia nodes. Irrelevant on 4663 *unless* T5A puts the app on Sepolia — in which case it is the live transport. |
| `VITE_CAULDRON_INDEXER` | `.env.example:19` | **nowhere** | dead var (T5E). The indexer URL is manifest-only (`cauldron.ts:73`). |
| `DEPLOYMENT` | Railway (indexer) | `indexer/deployments/active.ts:29,36` | `"sepolia"` → `round.json`. The chain guard at `:36` fires **only** for `arc`; a Robinhood manifest is accepted with no chain check. |
| `PONDER_RPC_URL` | Railway (indexer) | `ponder.config.ts:118` | **`https://sepolia.gateway.tenderly.co`** for chainId 4663 (`:117`) — indexes the wrong chain. **T5B, the single most dangerous unset var.** |
| `POLLING_INTERVAL_MS` | Railway (indexer) | `ponder.config.ts:138` | `4000` ms on 4663 (only 5042002 gets the fast cadence). |
| `PONDER_MAX_RPS` | Railway (indexer) | `ponder.config.ts:143-144` | `12` (scales with the number of `PONDER_RPC_URL` entries, so `12` when that is unset too). |
| `DATABASE_URL` | Railway (indexer) | `ponder.config.ts:68-69` | no Postgres → Ponder's local pglite; state is lost on every restart and a full resync follows. |
| `API_RPC_URL` | Railway + Vercel | `indexer/src/api/index.ts:127`, `api/cauldron/creature.ts:47`, `api/cauldron/liquidatoor.ts:29` | **five SEPOLIA public nodes**. `/freshness`'s divergence check, the creature-art renderer and the liquidatoor badge all read the wrong chain (T5B step 5). |
| `CORS_ORIGIN` | Railway (indexer) | `indexer/src/api/index.ts:12` | `"*"` — acceptable for a read-only API, worth pinning anyway. |
| `STRICT_POOL_FILTER` | Railway (indexer) | `indexer/src/api/index.ts:179` | off; the pool filter is load-bearing on range-capped RPCs (`ponder.config.ts:115`). |
| `DATABASE_URL` (Vercel) | Vercel | `api/brand.ts:114`, `api/fren-ask.ts:38`, `api/fren-teach.ts:20` | brand writes 500, fren memory disabled. |
| `BRAND_SIGNERS` | Vercel | `api/brand.ts:40,143` | empty → all brand writes 503. Fail-closed. |
| `BRAND_ALLOWED_ORIGINS` | Vercel | `api/brand.ts:48,139-141` | empty → **every browser Origin is refused**; only originless (non-browser) clients pass the Origin check, and they still need a valid signature. Fail-closed but confusing. |
| `BRAND_MAX_ROWS` | Vercel | `api/brand.ts:56` | `256`. |
| `FREN_ADMIN_SECRET` | Vercel | `api/fren-teach.ts:21,86,107` | teaching disabled (503). Fail-closed. |
| `GROQ_API_KEY` / `GEMINI_API_KEY` | Vercel | `api/fren-ask.ts:28,30,207` | both unset → the ask endpoint falls back with no LLM. Fail-closed. |
| `CAULDRON_DOCS_ORIGIN` | Vercel | `api/fren-ask.ts:72,81` | falls back to `VERCEL_PROJECT_PRODUCTION_URL`/`VERCEL_URL`; the `x-forwarded-host` spoof is already removed (`:58-69`). |
| `X_CLIENT_SECRET` / `VITE_X_CLIENT_ID` | Vercel | `api/x-token.ts:65-66` | OAuth exchange fails. Note `VITE_X_CLIENT_ID` **ships to the browser** — correct for an OAuth *client* id, wrong for anything else. |
| `X_REDIRECT_URIS` | Vercel | `api/x-token.ts:16` | empty allowlist → every exchange refused. Fail-closed. |
| `LIQUIDATOOR_COLLECTIONS` | Vercel | `api/cauldron/liquidatoor.ts:196`, `creature.ts:180` | only the manifest collection is honoured. |

---

## 5. PoC transcripts (all three run 2026-09-15, exit 0)

### T5A — `bash audit/RH_MAINNET_2026-09-16/poc/h5/h5_chain4663_seam.sh`
Two real `npm run build` runs against a filled 4663 manifest. Emitted bundle
(`dist/assets/index-JNC5KA7u.js`) contains, verbatim:
```js
Ea={11155111:z1,5042002:tS}                                   // DEPLOYMENTS — no 4663 key
function oS(){…const e="testnet"…return e==="target"||e==="mainnet"||e==="arc"?5042002:11155111}
const Ur=oS(),de=Ea[Ur]                                       // SELECTED_CHAIN_ID, ACTIVE_ROUND
Rc=4663,aS=Number.isSafeInteger(Rc)&&Rc>0?Rc:5042002,q1=Ur!==ha.id?Ur:aS   // CHAIN_ID
de.chainId!==Wn&&console.error(`[cauldron] MANIFEST/CHAIN MISMATCH …`)     // Wn = ACTIVE_CHAIN_ID
```
`targetChain.id` reaches 4663, but `IS_TARGET` (`Ur!==ha.id`) is false, so `ACTIVE_CHAIN_ID`
— which is `CAULDRON.chainId` and the argument to every `switchChainAsync` — is 11155111.
The mismatch `console.error` shipping in the production bundle is the proof.
The script restores `round.json` on EXIT; `diff` against the backup is IDENTICAL.

### T5B — `node audit/RH_MAINNET_2026-09-16/poc/h5/h5_ponder_default_chain.mjs`
```
ponder.config.ts:89    // can NEVER silently point Sepolia nodes at a
ponder.config.ts:117   const DEFAULTS = chainId === 5042002 ? ARC : SEPOLIA;
ponder.config.ts:138   process.env.POLLING_INTERVAL_MS ?? (chainId === 5042002 ? 1000 : 4000)

 chainId    rpcDefault                              pollingMs
 11155111   https://sepolia.gateway.tenderly.co     4000
 5042002    https://rpc.testnet.arc.network         1000
 4663       https://sepolia.gateway.tenderly.co     4000     <-- Robinhood

round.robinhood.template.json:5  chainId = 4663
ponder.config.ts declares  chains.cauldron.id = 4663
ponder.config.ts fetches blocks/logs from     = https://sepolia.gateway.tenderly.co
RESULT: T5B CONFIRMED.
```
The script asserts the three source strings still exist before evaluating them, so it
fails loudly rather than silently if the code is changed. No `return` and no skip.

### T5D — `node audit/RH_MAINNET_2026-09-16/poc/h5/h5_quote_decimals.mjs`
```
src/config/quotes.ts:43   export const KNOWN_QUOTES = (round.quoteAssets ?? []).map
src/config/quotes.ts:61   name: "Unlisted quote",  decimals: 18
round.robinhood.template.json  quoteAssets present: false
round.arc.json                 quoteAssets present: true  (USDC/18d, USDG/6d)
round.json (sepolia)           quoteAssets present: true  (ETH/18, USDG/6, xNVDA/18)

SwapWidget.tsx:195  const qDec = qNative ? 18 : quoteDecimals;
SwapWidget.tsx:217  const outDecimals = mode === "buy" ? 18 : qDec;
SwapWidget.tsx:213  return (parseUnits(expected.toFixed(decimals), decimals) * (10_000n - slipBps)) / 10_000n;

quote 0x3bfc…48e3  true decimals=6  app believes=18
signed minOut (raw)     = 970000000000000000000
correct minOut (raw)    =           970000000
best possible out (raw) =          1000000000
signed floor is 1000000000000x too large
UI shows minimum out as = 970.000000   <-- looks correct, is not
RESULT: T5D CONFIRMED.
```

**Reachability chain for T5D, verified by grep (this is why it is not merely a
template-completeness nit):**
```
src/hooks/useAllowedQuotes.ts:78-88   useCurrentQuote -> registry.generationQuote(gen)   [ON-CHAIN]
src/components/cauldron/TheCauldron.tsx:494   const liveQuoteAddr = useCurrentQuote(m.gen);
src/components/cauldron/TheCauldron.tsx:506   const liveQuote = quoteMeta(liveQuoteAddr);  [MANIFEST + 18 fallback]
src/components/cauldron/TheCauldron.tsx:1020,1040,1076,1132   quoteDecimals={liveQuote.decimals}
src/components/cauldron/SwapWidget.tsx:97     quoteDecimals = 18            (a SECOND 18 default)
src/components/cauldron/SwapWidget.tsx:195    const qDec = qNative ? 18 : quoteDecimals;
src/components/cauldron/SwapWidget.tsx:217-218 -> the signed minOut
```
The **live quote address is read from the chain** while its **decimals come from the
manifest**. They can therefore diverge with no redeploy: any quote approved by governance
after the bundle was built — or every quote at all on the Robinhood manifest, which has no
`quoteAssets` key — lands on the 18 fallback. Note `useAllowedQuotes.ts:38` only ever
*offers* quotes drawn from `KNOWN_QUOTES`, so the offer list and the live quote are sourced
differently; the app cannot even describe a quote it is already trading against.

---

## 6. Additional lead

**L6 — `KNOWN_QUOTES[0]` is `undefined` on the Robinhood manifest (HYPOTHESIS).**
`src/hooks/useAllowedQuotes.ts:31`
```ts
const [quotes, setQuotes] = useState<QuoteAsset[]>([KNOWN_QUOTES[0]]);
```
`round.json` and `round.arc.json` both have a non-empty `quoteAssets` (verified above), so
`KNOWN_QUOTES[0]` is a real object today. The Robinhood template has none, making the initial
state `[undefined]`, which `TreasuryRotation.tsx:312` and `TheCauldron.tsx:1614` consume.
Next step: find the `.map(` over `quotes` in each consumer and check whether it dereferences
`q.address`/`q.symbol` before `load()` resolves; if it does, the rotation panel white-screens
on first paint. Cheap to confirm: build with an empty `quoteAssets` and open the page.
