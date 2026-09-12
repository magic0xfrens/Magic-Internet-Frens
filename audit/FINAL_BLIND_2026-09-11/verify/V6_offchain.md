# V6 — off-chain verification (Ponder / Vercel API / React UI / operator scripts)

Method: refutation-first. Each claim was re-derived from source at `path:line`, the hunter's
repro re-run or independently recomputed, and then attacked with the cheapest counter-argument
I could find (a check elsewhere, a deployment setting, a blast-radius cap, an unrealistic
precondition). A finding survives only where the counter-argument failed.

Contract source/ABIs read only from `/tmp/blind-final/contracts/solidity`. Nothing was sent to a
deployed host. My own artifacts: `/tmp/blind-h6-verify/`.

---

## X6a — rotation slippage floor is a flat ~1 token — **DOWNGRADED: Critical → Medium**

### The code is exactly as claimed
`src/components/cauldron/TreasuryRotation.tsx:256`

```ts
const minOut = parseUnits(String(Math.max(0, 1 - maxSlip / 100)), destMeta.decimals);
await rotateSlice(SLICE_BPS, minOut, route, fromLeg);
```

`maxSlip` defaults to `1` (`:162`), the label reads "Max slippage per slice … %" (`:363-371`),
and `SLICE_BPS = 2500` (`src/hooks/useTreasuryRotation.ts:170`). The expression is a pure
function of `maxSlip` and `destMeta.decimals` — the slice notional never enters it.

Recomputed independently (`/tmp/blind-h6-verify/minout-verify.out`), not taken from the hunter:

```
dest=USDG d=6   minOut=990000               = 0.99 USDG
dest=WETH d=18  minOut=990000000000000000   = 0.99 WETH
```

Two realistic sizes:
- **100-ETH quote side, one 25% slice = 25 ETH → ~75,000 USDG fair.** Signed floor 0.99 USDG =
  0.00132% of fair. UI promised 1%.
- **1-ETH quote side, one 25% slice = 0.25 ETH → an 18-decimal destination.** Signed floor
  0.99e18 *exceeds* fair 0.25e18, so the slice can never fill.

The entrypoint is permissionless, as claimed — `RedemptionExt.sol:280` is `public` with no
modifier, and `graph/rotation.md:405` lists it as "anyone (permissionless…)". A stranger can
call it with the UI's parameters; the destination and ceiling come from the vote, not the caller.

### Counter-argument tried — and it LANDED
The hunter stopped at the UI and never read what the rotator does with `minOut`.
`cauldron/QuoteRotator.sol:355-366` (the function `rotateSliceFrom` actually calls):

```solidity
if (!allowedVenue[PoolIdLibrary.toId(route)]) revert NoRoute();
out = _swap(route, from, to, amountIn);
uint256 floor = _oracleFloor(from, to, amountIn);
if (out < (minOut > floor ? minOut : floor)) revert SlippageTooHigh();
```

Two independent guards the claim ignores:

1. **An oracle floor the caller cannot lower.** `_oracleFloor` (`:398-408`) values the trade
   through `quoteOracle`, not through the pool being traded, and returns
   `fair * (BPS - rotationSlipBps) / BPS` with `rotationSlipBps = 300` (3%, `:373`, owner-capped
   at 2000 = 20%, `:376-379`). The contract takes the **max** of the caller's `minOut` and this
   floor, so a caller may tighten but never loosen.
2. **A venue allowlist keyed by PoolId** (`:355`) — the caller cannot substitute their own pool.

And the oracle is wired by both deploy paths:
`deploy/DeployRotationStack.s.sol:169` and `deploy/DeployLaunchpad.s.sol:637`,
`rotator.setArbParams(address(oracle), 1000, 5e18)`.

So the realized loss on a default deployment is bounded at ~3% of the slice, not the ~99.999%
claimed. The measured "signer accepts up to 99.999% loss" line in `minout.out` is arithmetic on
the UI value alone and does not describe what can actually execute.

### What survives
- The user-facing slippage control is **decorative**: the number the operator types never binds,
  because the oracle floor is always the larger of the two. The promise ("1%") and the enforced
  band (3%, tunable to 20%) differ, and the entrypoint is permissionless — an MEV sandwicher on
  the curated venue can take the 2% delta on every slice (0.5 ETH on a 25-ETH slice) as pure
  profit the treasury believed it had bounded.
- **The inverse is unconditional and needs no oracle at all**: any slice whose fair output is
  under ~1 whole destination token reverts `SlippageTooHigh`. For an 18-decimal destination that
  is every slice below ~1 token — a small treasury simply cannot rotate.
- **Conditional escalation.** `_oracleFloor` fails open by design (`:392-397`: "With no oracle
  wired (or a leg it cannot value) this returns 0 and the caller's `minOut` stands alone"), and
  `_usd` (`:564-573`) returns 0 if `quoteOracle` is unset **or** `cachedUsdPerRawUnit` reverts or
  returns 0 for *either* leg. On such a pair the UI's 0.99-token floor is the only guard and the
  original ~100% figure holds. That is a deployment/oracle-coverage condition, not the default.

**Verdict: DOWNGRADED to Medium** — real, reachable, and a real bug in a money path, but the
on-chain oracle floor + venue allowlist cap it at a few percent per slice rather than a drain;
escalate to High if any rotation pair can be unpriceable to `quoteOracle`.

---

## X6b — UI encodes a perp selector the engine does not implement — **CONFIRMED (High)**

`FOUNDRY_PROFILE=cauldron forge inspect PerpEngine methodIdentifiers`, blind tree:

```
| openLong(uint8,uint256,uint256,uint256)   | 79588b97 |
| openShort(uint8,uint256,uint256,uint256)  | 9e4a4754 |
```

Selectors derived myself with `cast sig`:

```
openLong(uint8,uint256,uint256)          0x1cff5d47   <- not implemented
openLong(uint8,uint256,uint256,uint256)  0x79588b97   <- implemented
openShort(uint8,uint256,uint256)         0x95dd8fe9   <- not implemented
openShort(uint8,uint256,uint256,uint256) 0x9e4a4754   <- implemented
```

The UI declares only the 2- and 3-arg shapes — `src/config/perp.ts:32,35,36` — and the hook
passes exactly three arguments, so viem resolves to the 3-arg overload:

```ts
// src/hooks/usePerpEngine.ts:190-191
address: PERP.engine, abi: PERP_ABI, functionName: "openLong",
args: [leverage, 0n, liqHint], value, ...
```

Reachable from the shipped UI: `src/components/cauldron/PerpPanel.tsx:215`
`if (side === "long") await perp.openLong(collateral, lev, liqHint);`

### Counter-arguments tried, all failed
- *Does viem pick the 4-arg form?* It cannot — the 4-arg shape is absent from `PERP_ABI`.
- *Does a fallback absorb the unknown selector?* No `fallback()` exists in `PerpEngine.sol`; the
  only catch-all is `receive() external payable {}` at `:1813`, which runs for **empty** calldata
  only. The call carries 100 bytes, so it reverts.
- *Is the 3-arg form perhaps an older deployed engine?* The UI reads its address from the shared
  round manifest with no env override (`src/config/perp.ts:6,19`), i.e. the same engine the
  blind tree builds.

Same drift operator-side: `scripts/marketmaker.sh:123` uses `'openLong(uint8,uint256)'`.

**Verdict: CONFIRMED at High.** No funds are lost (the revert is atomic; the user loses gas), but
every perp open from the shipped UI and from the market-maker script fails — a total outage of
the flagship feature.

---

## X6c — `x-forwarded-host` steers the doc fetch into the system prompt — **DOWNGRADED: High → Medium**

`api/fren-ask.ts:55-64`:

```ts
const host = (req.headers["x-forwarded-host"] || req.headers.host) as string;
const proto = (req.headers["x-forwarded-proto"] as string) || "https";
const res = await fetch(`${proto}://${host}/llms-full.txt`, { headers: { accept: "text/plain" } });
if (res.ok) return await res.text();
```

No allowlist, no comparison to a known host; the scheme is attacker-controlled too. The bytes
become the "source of truth" block of the system prompt at `:180-183`:

```ts
const system = PERSONA + "\n\n===== DOCS (source of truth) =====\n" + (docs || "…");
```

Hunter's repro re-read (`ssrf-fren-ask.out`): fetched `http://127.0.0.1:64111/llms-full.txt`;
`system prompt contains attacker text: true`, `contains real docs: false`; the injected block
instructs users toward a fake claim portal.

### Counter-arguments tried
- *Does `vercel.json` validate the host?* No. It only rewrites `/api/(.*)` straight through and
  sets response headers; there is no host or origin check anywhere in it. **Counter fails.**
- *Blast radius — does the poisoned answer reach anyone else?* **This counter lands.** The route
  sets `Cache-Control: no-store` twice (`:151` and `:211` in `replyWith`), headers are per-request,
  and there is no write path from this route into the `fren_corrections` table (that is
  `api/fren-teach.ts`, a separate route). The injection therefore poisons only the attacker's own
  response — self-injection, not stored cross-user injection. That is the difference between a
  High and a Medium.
- *Is it reachable at all from the internet?* **Open question I could not close.** Whether
  Vercel's proxy forwards a client-supplied `x-forwarded-host` to the function, or overwrites it
  from the routed Host, is platform behaviour I cannot test without hitting production (forbidden
  by the brief). If Vercel overwrites it, remote exploitation collapses to Host-header
  manipulation, which Vercel routes on. The code defect is unconditional either way.

### What survives
A genuine SSRF: the function issues an outbound request to an attacker-chosen scheme+host from
Vercel's egress (useful for internal-surface probing and as an oracle), and an attacker can make
the bot endorse arbitrary text in their own session — a credible screenshot/social-engineering
artifact on the project's own domain. But no other user is served the poisoned answer.

**Verdict: DOWNGRADED to Medium.**

---

## X6d — `/api/brand` accepts unauthenticated writes — **CONFIRMED (High)**

`api/brand.ts`. CORS wide open at `:16` (`Access-Control-Allow-Origin: *`). The POST branch:

```ts
// :36-38
if (req.method === "POST") {
  const { gen, logo, banner, website } = req.body ?? {};
  if (typeof gen !== "number") return res.status(400).json({ error: "gen required" });
```

Then a straight UPSERT over the live row (`:43-51`). The header comment at `:10` advertises
`POST /api/brand { gen, logo, banner, website, sig? }` — but `sig` is **never destructured and
never read**. That is the whole of the "auth": a parameter named in a comment. (This matches the
hunter's `auth checks in api/brand.ts: [ 'sig' ]` — the single occurrence is the doc line.)

Repro re-read (`brand-poc.out`): unauthenticated POST → `{"ok":true}`; `gen=999999`, `gen=-4`,
`gen=2147483647` all → `{"ok":true}`. The only validation is `typeof gen !== "number"`, so
negative, huge, and fractional generations all pass.

### Counter-arguments tried, all failed
- *Does `vercel.json` gate `/api`?* No — it rewrites `/api/(.*)` to the function unchanged, and
  its security headers are response-side only. No middleware file exists on this route.
- *Is there a rate limit?* None on this route. (`api/fren-ask.ts:134-147` has one, so the absence
  here is a gap, not a project-wide convention.)
- *Does an unset `DATABASE_URL` make it a harmless no-op?* `:21-22` degrades to a null brand, but
  the deployment plainly uses Neon (other routes read the same env), so this does not save it.
- *Is the damage bounded?* Partly: `:40` caps each image at ~3.5MB and `gen` is `INT PRIMARY KEY`,
  so distinct rows cap at ~2^31 — but at ~7MB per row that is unbounded in any practical sense,
  billed to the project, with no throttle.

Scope note, stated precisely: I verified the **write** is unauthenticated and that GET serves the
stored `logo`/`banner`/`website` back (`:28-33`). I did **not** trace the API-sourced `website`
to a rendered anchor — the `href={`https://${fallback.website}`}` at
`src/components/cauldron/TheCauldron.tsx:399` reads a hardcoded constant map (`:324`), so I make
no claim about a phishing-link chain from this route.

**Verdict: CONFIRMED at High.** A stranger with `curl` and no wallet, no key and no origin
defaces the live profile card for any generation and writes unbounded paid rows. Not Critical —
no funds move.

---

## X6e — `keeper.sh` binds addresses before sourcing the env — **CONFIRMED (Medium)**

`scripts/keeper.sh:21-25`:

```bash
PERP="${PERP_ENGINE:-0x26ae199E143d98be557Eaf89EF7764291bcc51e5}"
REGISTRY="${CAULDRON_REGISTRY:-0x6629a99fbb485c36ee63eb1190486660234611b8}"
set -a; source "contracts/solidity/.env.sepolia"; set +a
```

Both `${VAR:-default}` expansions evaluate at lines 21/24, when the variables are still unset;
the file that defines them is sourced at line 25 and can no longer affect them.

Re-ran the hunter's script (`bash /tmp/blind-h6-poc/keeper-order.sh`):

```
env file said PERP_ENGINE = 0x43cb1942df7ad2072a27f73b509fc1ee4c21ff92 (round.json: LIVE)
keeper.sh will use PERP   = 0x26ae199E143d98be557Eaf89EF7764291bcc51e5
keeper.sh will use REGISTRY = 0x6629a99fbb485c36ee63eb1190486660234611b8
                              (round.json registry = 0x018efe32379bfc3f38ed7e592f5c9f214b6e3ded)
```

Both defaults are a dead round, as claimed.

### Counter-arguments tried
- *An operator who exports `PERP_ENGINE` in their shell first gets the right address.* True, but
  the script's own header at `:16` documents the flow as "sources .env.sepolia" — the documented
  path is the one that loses. Counter fails for intended usage.
- *Does it fail loudly?* No: `sweep()` calls `nextId()` on the dead address and prints
  "(engine unreachable)" (`:39-40`), and `materialize()` swallows the failed send (`:33`). It
  looks like a quiet no-op, not an error.
- *Does anyone lose money?* Liquidation is permissionless, so a third-party keeper can cover;
  the exposure is the window in which underwater positions go unliquidated (bad debt against the
  vault) because the project's own keeper is pointed at a dead engine.

**Verdict: CONFIRMED at Medium** — operator liveness with a real but third-party-coverable
bad-debt tail.

---

## X6f — perp opens and closes signed with `minOut = 0n` — **CONFIRMED (Medium, rescoped)**

`src/hooks/usePerpEngine.ts`:

```ts
:191  args: [leverage, 0n, liqHint],   // openLong  — minTokenOut = 0
:202  args: [leverage, 0n, liqHint],   // openShort — minEthOut  = 0
:209  functionName: "close", args: [id, 0n],
:219  functionName: "close", args: [p.id, 0n],   // closeAll
```

### Counter-argument tried — partially lands
The **open** half is unreachable today: those calldata never execute (X6b), so the zero floor is
latent — it becomes live the moment X6b is fixed, which makes it a fix-ordering hazard rather
than a present loss.

The **close** half is live and I confirmed the selector exists on-chain:
`forge inspect PerpEngine methodIdentifiers` → `close(uint256,uint256) | 596c8976`, matching the
UI ABI at `src/config/perp.ts:37`. So every close and every `closeAll` from the shipped UI
executes with zero slippage protection and is freely sandwichable, with no UI control to set one.

Worth contrasting with `TreasuryRotation.tsx:249-255`, which argues at length that "0 would
execute at any price. That is never the right default on a permissionless entrypoint, so the
field has no 'off'" — the perp panel does exactly what the treasury panel forbids.

**Verdict: CONFIRMED at Medium**, scoped to `close`/`closeAll`; the open half is a latent
regression gated behind X6b.

---

## X6g — indexer subscribes to a nonexistent event — **DOWNGRADED: Medium → Low**

`indexer/abis/RegistryAbi.ts:60` declares `name: "UnclaimedBurned"` ("burnUnclaimed — deflation
of a superseded gen"), and `indexer/src/index.ts:209` registers a handler:

```ts
ponder.on("CauldronRegistry:UnclaimedBurned", async ({ event, context }) => {
  await bumpIter(context, Number(event.args.gen), "burned", event.args.amount as bigint); });
```

`grep -rn "UnclaimedBurned" /tmp/blind-final/contracts/solidity/` returns **zero hits** — the
event exists in no contract, confirming the claim. The registry documents the removal itself:
`CauldronRegistry.sol:1358` — "the old `burnUnclaimed` is obsolete in the reserve-LP model".

### Counter-argument tried — it lands
An ABI event that no contract emits does not break Ponder: the log filter simply matches nothing
and the handler never fires. Nothing crashes, no indexing stalls, no data is corrupted — the
`burned` counter silently stays 0 forever. This is a dead subscription tracking a deliberately
removed feature, i.e. stale code, not a fault. The hunter's own measurement supports the narrow
reading: 38 of 39 events match exactly.

**Verdict: DOWNGRADED to Low.**

---

## X6h — private keys in argv — **CONFIRMED (Low), count corrected**

`--private-key "$PRIVATE_KEY"` reaches the process argument vector, visible to any local user via
`ps`. Measured occurrences per file:

```
scripts/deploy-testnet.sh:1   scripts/go-testnet.sh:1     scripts/keeper.sh:3
scripts/mint-presale.sh:1     scripts/reclaim-old-lp.sh:2 scripts/recover-live.sh:1
scripts/marketmaker.sh:6
```

Seven scripts, not six. Counter-argument: on a single-operator machine the exposure is
negligible, and `--private-key` is `cast`'s documented idiom. Hygiene.

**Verdict: CONFIRMED at Low.**

---

## X6i — `api/x-token.ts` unauthed OAuth proxy — **CONFIRMED (Low)**

`:8` accepts any POST; `:12-15` takes `code`, `code_verifier`, `redirect_uri` from the body and
`:26-36` forwards `redirect_uri` verbatim to `https://api.x.com/2/oauth2/token`. No allowlist of
callbacks, no rate limit, no origin check.

Counter-argument that blunts it: X validates `redirect_uri` against the app's registered callback
list upstream, and PKCE requires a `code_verifier` matching a challenge the attacker never
issued — so this is not an account-takeover primitive. What remains is an unthrottled public
proxy in front of the project's client credentials (abuse/cost surface).

**Verdict: CONFIRMED at Low.**

---

## X6j — `liquidatoor.ts?col=` reads any contract — **CONFIRMED (Low)**

`api/cauldron/liquidatoor.ts:184` takes `const colRaw = (req.query.col ?? "").toString();` and
`:85-88` calls `readContract({ address: col, abi: LIQ_STATS_ABI, functionName: "liqStats", … })`,
rendering the result into badge SVG (`:122` and neighbours).

Counter-argument: it is an `eth_call` — no state change, no value, no signer. The response is
decoded against `LIQ_STATS_ABI`, whose fields are `address`/`uint` only, so an attacker chooses
the *numbers and addresses* shown but cannot inject markup (no field can carry `<`), and `:79`
documents a failed read returning null. Result: forged badge artwork served from the project's
domain, plus the RPC being used as a free read proxy.

**Verdict: CONFIRMED at Low.**

---

## Tally

| ID  | Hunter | Verdict | Reason |
|-----|--------|---------|--------|
| X6a | Critical | **Medium** | `QuoteRotator.sol:365-366` takes `max(minOut, oracleFloor)`; floor is 3% and the oracle is wired at deploy |
| X6b | High | **High (confirmed)** | 3-arg selector absent, no `fallback()`, only `receive()` |
| X6c | High | **Medium** | `no-store` on the response; injection is self-scoped, not cross-user |
| X6d | High | **High (confirmed)** | `sig` exists only in a comment; no auth, no rate limit, CORS `*` |
| X6e | Medium | **Medium (confirmed)** | defaults bind before `source`; reproduced |
| X6f | Medium | **Medium (rescoped)** | live for `close`; the open half is latent behind X6b |
| X6g | Medium | **Low** | dead subscription — never fires, nothing breaks |
| X6h | Low | **Low (confirmed)** | 7 scripts, not 6 |
| X6i | Low | **Low (confirmed)** | upstream `redirect_uri` validation + PKCE blunt it |
| X6j | Low | **Low (confirmed)** | typed ABI decode; no injection, forged art only |

Refuted outright: **0**. Severity corrections: **4** (X6a, X6c, X6g downgraded; X6f rescoped).
