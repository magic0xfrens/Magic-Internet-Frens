# V6 — subsystem 6 (off-chain) verification

Contract source read from the decontaminated tree `/tmp/blind-final/contracts/solidity`.
Frontend/indexer/api read from the live repo. Hunter artifacts run from `/tmp/blind-h6`.

---

## T6A — full quote balance passed as `quoteIn` — CONFIRMED (HIGH) — VERIFIED(frontend+PoC) / DERIVED(contract)

`src/hooks/useCauldronSwap.ts:181` takes the wallet's whole balance:

```
let amountIn = (await bal()) as bigint;
if (quoteExpected > 0n && amountIn < quoteExpected) { ... zap ... }
```

and `:215` signs it while the floor is the one computed for the typed amount:

```
args: [amountIn, 0n, minOut, 0n, BigInt(openMax)], value: 0n,
```

`minOut` is derived in `src/components/cauldron/SwapWidget.tsx:186,193,199` from the TYPED
`eth` only (`estTokensOut = netOfFee(eth)/spotPrice`), so the floor is unrelated to
`amountIn`.

Contract side (counter-arguments tried, all fail):
- `CauldronGachaRouter.sol:272-279` `_pullQuote` does `_safeTransferFrom(q, msg.sender,
  address(this), quoteIn)` — the FULL `quoteIn`, no cap at an approved-typed amount
  (the frontend approves exactly `amountIn` at `useCauldronSwap.ts:200-208`, so approval
  does not bound it either).
- Refund? `_play` (`:338`) pays back `spend - ethConsumed`, but the buy leg
  (`:422-431`) is an exact-input swap `amountSpecified: -int256(d.ethIn)` with
  `sqrtPriceLimitX96: _limit(true)` = `4295128740`, i.e. the extreme tick
  (`CauldronGachaRouter.sol:518-520`). Exact-input at the extreme limit consumes the
  whole `spend`; nothing is refunded.
- Only the floor could stop it, and the floor is sized for the typed amount.

Ran `node /tmp/blind-h6/poc_a_full_balance.mjs`:

```
typed  : 0.01 ETH  (~ 25 USDG )
balance: 10000 USDG
play(quoteIn= 10000 USDG , minTokenOut= 1000000000000000000 )
OVERSPEND FACTOR: 400 x
slippage floor covers only 0.250 % of the amount actually swapped
```

Reachability: requires a non-native `generationQuote`. `indexer/deployments/round.json`
ships two ERC20 quotes as `quoteAssets`: USDG (6 dec) and xNVDA (18 dec). Sharpest
counter-argument I could find: T6B's floor bug might make every ERC20 buy revert first,
masking T6A. It does for USDG (unit price BELOW ETH ⇒ `spotPrice` too small ⇒ floor too
high ⇒ revert), but NOT for xNVDA: 18 decimals kills the 1e12 term and the remaining
ETH/xNVDA ratio (~15) makes `spotPrice` LARGER than the ETH-denominated one, so
`estTokensOut` and hence `minOut` come out ~15x too LOW — satisfiable. On an
xNVDA-quoted generation the overspend executes with a floor covering ~1/15 of the size.
HIGH stands.

## T6B — indexer `lastPrice` is a raw currency ratio labelled ethPerToken — CONFIRMED (HIGH) — VERIFIED

`indexer/src/index.ts:27-31`:

```
function ethPerToken(sqrtPriceX96: bigint): number {
  const s = Number(sqrtPriceX96) / Q96;
  const tokenPerEth = s * s;
  return tokenPerEth > 0 ? 1 / tokenPerEth : 0;
}
```

No decimals term. `registerPool` DOES read and store the pool's `quote`
(`indexer/src/index.ts`, `generationQuote` read in `registerPool`), and the Swap handler
(`:292`) calls `ethPerToken(...)` without consulting it; `:321` writes it to
`lastPrice`. `amountEth = Math.abs(Number(amount0)) / 1e18` (`:294`) is likewise
hardcoded to 18 decimals, so volume/mcap/FDV inherit the error
(`src/hooks/useCauldronMachine.ts:435,439,440`). `grep -n decimals indexer/src/index.ts`
returns only comment hits at :724-726 (an unrelated oracle note) — no normalisation on
the read path; `src/config/quotes.ts` carries `decimals` for DISPLAY only and is never
applied to `spotPrice` (`useCauldronMachine.ts:261` takes `d.spotPrice` verbatim).

Ran `node /tmp/blind-h6/poc_b_quote_units.mjs`:

```
indexer spotPrice : 2.4999999999999994e-18 (true USDG/token: 0.0000025, true ETH/token: 1e-9)
price shown to trader is off by: 400000000.0000001 x
BUY reverts on floor : true  overshoot 396000000.0000001 x
```

Severity check the brief asked for: the zap and the buy are TWO separate signatures —
`useCauldronSwap.ts:189-190` awaits the zap receipt before `:210-216` signs `play`. So a
revert on the floor does NOT roll back the conversion: the user's ETH is already USDG,
and they eat the zap's swap fee + slippage + both gas bills, then hit a permanently
unbuyable market. Not pure loss (they keep the USDG), but not gas-only either, and the
same number misprices every chart, mcap and FDV shown to everyone. HIGH stands.

## T6C — slippage floors from an unauthenticated indexer number, no freshness gate — DOWNGRADED to LOW — VERIFIED

`src/hooks/useCauldronMachine.ts:261`:

```
spotPrice: d.spotPrice && d.spotPrice > 0 ? d.spotPrice : prev.spotPrice,
```

feeds `SwapWidget.tsx:186-199` → `minOut`. Counter-arguments that bite:
- The URL is not user-controllable and is HTTPS: `src/config/cauldron.ts:72`
  `CAULDRON_INDEXER = round.indexerUrl…` = `https://indexer-production-102c.up.railway.app`
  from the manifest.
- `grep -rn useIndexerHealth src` returns only `src/components/shared/IndexerHealthBanner.tsx:1,26`
  — the hunter's "banner-only" claim is accurate, so there is genuinely no sign-time gate.
- Impact is bounded and one-directional in practice: a STALE price on a rising market
  gives a too-LOW floor (weaker sandwich protection, capped by the user's own tolerance);
  a too-HIGH floor just reverts. Reaching a real theft requires compromising the operator's
  own indexer, at which point the whole read path is untrusted anyway.
LOW: a missing defence-in-depth gate, not an exploitable path on its own.

## T6D — seed keeper hardcodes sepolia + round.json — DOWNGRADED to LOW — DERIVED

`indexer/seed-keeper.mjs:37` (`import { sepolia } from "viem/chains"`), `:74`
(`readFileSync(new URL("./deployments/round.json"…))`), `:90` (`createPublicClient({ chain:
sepolia … })`) — the claim is accurate as written. But the keeper is NOT the only poker:
`CauldronHook.sol:1084-1091` calls it inside every swap, best-effort:

```
s.call{gas: g - SEED_POKE_GAS_RESERVE}(abi.encodeWithSelector(ISeederInSwap.pokeInSwap.selector));
```

and `CauldronSeeder.sol:38-42` documents `pokeInSwap` as the hook-driven path with `poke`
as the "permissionless standalone fallback". Any trade advances the stream, so on Arc the
consequence is only that a market with zero trading does not self-seed. LOW.

## T6E — public GET runs DDL per request — CONFIRMED (LOW) — VERIFIED

`api/brand.ts:103-108`: unauthenticated GET does
`await sql`CREATE TABLE IF NOT EXISTS cauldron_brand (…)`` then a SELECT, on every
request. The `Cache-Control: public, s-maxage=30` set at :107 is keyed on the full URL, so
any junk query param produces a fresh origin hit. `validGen(gen)` bounds the gen value but
not the request count, and there is no limiter in the file. LOW (Neon cost/availability).

## T6F — `?chain=` link parameter — REFUTED — VERIFIED

`src/config/deployments.ts:63-65`:

```
const fromUrl = Number(new URLSearchParams(window.location.search).get("chain"));
if (Number.isSafeInteger(fromUrl) && isDeployChain(fromUrl)) return fromUrl;
```

and `:43-45` `isDeployChain` = `Object.prototype.hasOwnProperty.call(DEPLOYMENTS, id)`.
The parameter selects a KEY of the bundled `DEPLOYMENTS` map — the two shipped manifests
and nothing else. No address injection, no arbitrary manifest; switching between two
first-party deployments via a shareable link is the feature.

---

## Refutation spot-checks

1. fren-teach auth / rightmost-XFF keying — AGREE with the refutation. `api/fren-teach.ts:84-88`
   `authed()` fails closed when `ADMIN_SECRET` is unset and requires the `x-fren-admin`
   header to match; the handler additionally 503s when `ADMIN_SECRET` is absent
   (`:105-108`). The limiter key at `:60-64` prefers the platform-set `x-real-ip` and
   otherwise takes `hops[hops.length - 1]` (rightmost), never the client-chosen leftmost,
   so header rotation does not mint fresh buckets. The same shape is used in
   `api/fren-ask.ts:163` and `api/x-token.ts:29`.
2. dist secret scan — AGREE. Ran a regex scan over the built bundle
   (`grep -rEl "sk-[A-Za-z0-9]{20}|SEED_KEEPER_PK|DATABASE_URL=|postgres://|xai-[A-Za-z0-9]{20}" dist`)
   and it matched no file. Nothing to raise.

## Discards

1 finding fully refuted (T6F); 2 downgraded (T6C, T6D). 0 NOT VERIFIED.
