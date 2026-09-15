# V5 — off-chain / frontend verification (round 45)

Method: read + grep the exact lines, ran hunter 5's two node PoCs, exercised the live
indexer read-only (two GETs). Contract sources touched only for ABI/signature shape.

---

## R5A — CONFIRMED, HIGH (conditional on an ERC20-quoted generation) — VERIFIED (static) / DERIVED (on-chain effect)

`src/hooks/useCauldronSwap.ts:355-358`:
```
  const spin = useCallback(
    async (
      ethIn: number, loops = 3, openMax = 0, minTokenOut: bigint = 0n,
      quote: Address = NATIVE_QUOTE, quoteExpected: bigint = 0n, quoteSymbol = "the quote",
```
`src/components/cauldron/CrystalCauldronGame.tsx:206`: `const hash = await spin(stake, loops, 0, spinFloor);` — 4 of 7 args.
The component cannot do better: its `Props` (`CrystalCauldronGame.tsx:65-75`) contain
`ticker, token, collection, spotPrice, ethUsd, col, nftMinted, nftMax, onBought` — **no
quote**, and the mount at `src/components/cauldron/TheCauldron.tsx:1027-1037` passes none,
while the sibling SwapWidget mount at `TheCauldron.tsx:1018-1020` does pass
`quote / quoteSymbol / quoteDecimals`. So `quote === NATIVE_QUOTE`, `isNativeQuote(quote)`
is true at `useCauldronSwap.ts:379`, and the ERC20 branch (zap → bounded approve →
`value: 0n`, `useCauldronSwap.ts:379-425`) is unreachable from the game; the native branch
signs a non-zero `value`. The hook's own comment at `useCauldronSwap.ts:374-378` states the
failure mode: "`_pullQuote` takes no value on a non-native quote, so this hard-coded native
`value` reverted `ErcQuoteTakesNoValue` and SPIN was simply dead ... on any rotated
generation." (Comment = not evidence; it is quoted as the author's statement of the router
ABI shape, and it matches the ERC20 branch sending `value: 0n`.)

PoC `hunt/h5-poc/r5a-spin-quote-unaware.mjs`, run, exit 0, output verbatim:
```
args passed: 4
CrystalCauldronGame Props keys: ticker, token, collection, spotPrice, ethUsd, col, nftMinted, nftMax, onBought
TheCauldron passes quote to SwapWidget: true
TheCauldron passes quote to CrystalCauldronGame: false
```

Counter-arguments tried:
1. *Is the game gated off under a non-native quote?* No. The only mount gate is
   `{m.token && ...}` (`TheCauldron.tsx:1025`). There is no `isNativeQuote` test anywhere
   around the mount. Counter fails.
2. *Is a non-native quote reachable?* The propose form lets a user pick the quote
   (`TheCauldron.tsx:1659-1676`, `useAllowedQuotes()`), `indexer/deployments/round.json:38`
   declares `quoteAssets`, and `round.json:25` publishes a `quoteRotator`. Reachable, but
   the LIVE generation is gen 1 (`/freshness` → `chainGen: 1`) — I did **not** verify the
   live quote asset is ERC20, so the bug is latent today and bites the first ERC20-quoted
   relaunch/rotation. That is why this is conditional, not Critical.
3. *Value loss?* No: the failure is a revert before any transfer (gas only). High, not
   Critical, per the brief's own rule.

Secondary claim (floor units): `CrystalCauldronGame.tsx:157-164` computes
`honest = (stake / spotPrice) * ...` and `parseEther`s it while `spotPrice` is
`livePerpPrice` (`TheCauldron.tsx:1031`). Under an ERC20 quote this mixes an ETH-typed
stake with a quote-denominated price — **HYPOTHESIS**, not separately exercised, and moot
while the tx reverts first.

NOT VERIFIABLE: the live generation's actual quote asset (would need a contract read I
scoped out of this pass); the on-chain revert itself (no tx sent, by instruction).

---

## R5B — CONFIRMED, HIGH — VERIFIED (arithmetic) / DERIVED (recovery path)

`src/components/cauldron/StakePanel.tsx:84-88` (quote side of `deposit`):
```
          let raw = parseEther(amount.toFixed(18));
          if (v.quoteIsErc20) {
            if (raw > v.quoteBalance) raw = v.quoteBalance;
            if (raw <= 0n) { setToast({ kind: "err", msg: `No ${quoteSymbol} to stake` }); return; }
```
`parseEther` is 18-decimal regardless of the quote. The clamp is to the **wallet balance**
(`v.quoteBalance` = `balanceOf(address)`, `src/hooks/usePerpVault.ts:140-144`), so on a
6-decimal quote every typed amount ≤ 1e12 units collapses to "stake everything".
The decimals ARE available in the tree — `TheCauldron.tsx:506` builds
`liveQuote = quoteMeta(liveQuoteAddr)` and passes `quoteDecimals={liveQuote.decimals}` to
SwapWidget at `:1020` — but the StakePanel mount (`TheCauldron.tsx:1126`) passes only
`quote={liveQuoteAddr} quoteSymbol={liveQuote.symbol}`: the decimals are dropped at the
prop boundary, and `parseUnits` is never used in StakePanel.tsx.

PoC `hunt/h5-poc/r5b-stakepanel-decimals.mjs`, run, exit 0:
```
typed            : 1 USDG
parseEther raw   : 1000000000000000000  (1e12x too large)
after clamp      : 10000000000  (10000 USDG)
Overspend factor: 10000x
```

Approval: **infinite**, to the vault — `src/hooks/usePerpVault.ts:153-156`
`approve(PERP.vault, maxUint256)`; the deposit is `deposit(raw)` with
`value: quoteIsErc20 ? 0n : raw` (`usePerpVault.ts:160-166`). Reachability of the
token/quote deposit path is real: `deposit`, `depositToken`, `withdrawEth`, `withdrawToken`
are all called by this hook.

Counter-arguments tried:
1. *Input validation / confirm dialog showing the real amount?* None: the only checks are
   `amount <= 0` (`StakePanel.tsx:75`) and the balance clamp; the toast says
   "Confirming deposit…" (`StakePanel.tsx:118`) with no figure. The wallet prompt shows
   `deposit(10000000000)` raw — not a human amount. Counter fails.
2. *Is this fund loss?* No — withdrawal exists and is share-based
   (`usePerpVault.ts:132-134` `withdrawEth(shares)`, `:180-182` `withdrawToken(shares)`),
   plus `claimPendingEth` / `claimPendingToken` (`:187-196`) and a position shape of
   `{ redeemable, instant, pending }` (`usePerpVault.ts:16`). So over-staked funds are
   recoverable, but a `pending` bucket + explicit claim step means recovery is **queued,
   not instant**, and the stake is at vault PnL risk meanwhile. High (unintended full-balance
   exposure + infinite allowance), not Critical.

NOT VERIFIABLE here: whether the pending queue carries a delay/haircut (that is vault
contract logic, out of my scope); the live quote's decimals.

---

## R5C — CONFIRMED-AS-DERIVED, MEDIUM (downgraded from High)

`indexer/ponder.config.ts:107-121`:
```
        const SEPOLIA = [
          "https://sepolia.gateway.tenderly.co",
          "https://ethereum-sepolia-rpc.publicnode.com",
          "https://1rpc.io/sepolia",
          "https://rpc.ankr.com/eth_sepolia",
          "https://eth-sepolia.public.blastapi.io",
        ];
        ...
        const env = (process.env.PONDER_RPC_URL ?? "").split(",").map((s) => s.trim()).filter(Boolean);
        const list = env.length > 0 ? env : DEFAULTS;
        return list.length > 1 ? list : list[0];
```
and its own comment at `:101-105`: "pin `PONDER_RPC_URL` to a single provider when it
happens again — a comma-separated list makes Ponder round-robin, which only widens the
window for two providers to disagree." The default IS the multi-provider list the comment
blames. `indexer/railway.json:8-9`: `"restartPolicyType": "ON_FAILURE",
"restartPolicyMaxRetries": 10` — a crash-loop exhausts restarts and stays down.
Override is `PONDER_RPC_URL`, comma-split, env wins over defaults (`:119-120`);
`grep PONDER_RPC_URL indexer/start.mjs` → no hits, so **start.mjs never sets it**: the
default is active unless a Railway variable is set.

Counter-argument tried: *maybe the live indexer is already pinned / already down.* It is
up and converged right now — `GET /freshness` returned
`{"ok":true,"chainGen":1,"indexedGen":1,...,"divergingForMs":0,"warmingUp":false}`
(live, 2026-09-15). So this is a latent availability risk, not a present outage → Medium,
not High.

**NOT VERIFIABLE: the value of the Railway service variable `PONDER_RPC_URL`.** If it is
set to one provider the finding is moot; the repo cannot tell me.

---

## R5D — DOWNGRADED to LOW (from Medium) — VERIFIED

`grep -rn "verify-selectors"` across the tree (excluding node_modules/.git/audit) returns
exactly ONE hit, inside the script itself:
`scripts/verify-selectors.mjs:16: //  Run after every deploy:  node scripts/verify-selectors.mjs`.
`package.json` scripts are `sync-llms, predev, dev, prebuild, build, postbuild, preview,
test:unit, test:e2e, test:e2e:dev, build-only, type-check, test, lint, format,
verify:manifest` — no selector check. No `forge clean` and no `--force` anywhere:
`scripts/auto-deploy.sh:77` is `forge build --sizes`, `.github/workflows/deploy.yml:49` is
`forge build --sizes`.

Counter-argument that partially succeeded: the CI deploy runs on a **fresh GitHub Actions
checkout**, where `out/` does not exist, so the stale-artifact class the missing
`forge clean` guards against cannot occur on the CI path — only on a developer's local
`auto-deploy.sh`. That, plus zero user-facing impact (a process guard, not a live bug),
drops this to Low.
NOT VERIFIED: the historical claim that selector drift "already shipped twice (playChurn)"
— that needs history, which I am barred from reading. Do not repeat that claim as fact.

---

## R5E — CONFIRMED, MEDIUM — DERIVED

`indexer/src/api/index.ts:1223`: `let everHealthy = false;  // gate the watchdog: only self-restart if we WERE fine`
`:1253-1254`: `if (diverged) { if (!divergingSince) divergingSince = now; } else { divergingSince = 0; everHealthy = true; }`
`:1260`: `const ok = !diverged || !everHealthy || persistedMs <= HEALTH_GRACE_MS;`
`:1301`: `if (!ok && everHealthy && divergingSince && Date.now() - divergingSince > WATCHDOG_KILL_MS) {`
`everHealthy` is a module-level flag set ONLY on a non-diverged evaluation, so a container
that boots into divergence and never converges keeps `everHealthy === false` →
`ok` is forced true by the second disjunct forever, the body reports
`warmingUp: true` (`:1266`) forever, and the watchdog at `:1301` can never fire. The catch
arm (`:1273-1275`) likewise returns `ok: true, warmingUp: true` on any thrown read.

Counter-argument tried: *is this just the intended backfill grace?* The comment at
`:1257-1259` says the gate exists so "this can never deadlock a deploy" — intended for the
warm-up window, but nothing ever times the warm-up out, so the intended grace is unbounded.
The design trade is real (a strict gate would block deploys), which is why this is Medium:
a monitoring blind spot, not a fund issue. Live today the flag is set:
`/freshness` returns `"warmingUp":false`, i.e. this instance did converge at least once.

---

## R5F — CONFIRMED, LOW — VERIFIED (live, one request)

`curl -s -i https://indexer-production-102c.up.railway.app/candles/abc` →
```
HTTP/2 500
content-type: text/plain; charset=UTF-8
error: invalid input syntax for type integer: "NaN" occurred in '/app/node_modules/pg-pool/index.js:45:11' while handling a 'GET' request to the route '/candles/abc'
```
Unvalidated path param reaches Postgres; the 500 body leaks the container filesystem
layout, the ORM/driver and its version path, and the raw PG error class.
Counter-argument tried: *is it behind auth or rate-limited?* No — unauthenticated, CORS
`access-control-allow-origin: *`, and it is cached (`s-maxage=5`). Counter fails.
Low: information disclosure + a trivially reachable error path, no data exposure.

---

## R5G — CONFIRMED, LOW — VERIFIED (static)

`scripts/keeper.sh:63`: `for (( id=1; id<next; id++ )); do` over `nextId()` read at `:60`,
with two `cast call`s per id (`:65`, `:68`). The sweep is O(nextId) forever — closed
positions are skipped only AFTER paying a call for them (`:65-66`). Error handling:
`:71` `if cast send "$PERP" 'liquidate(uint256)' "$id" ... >/dev/null 2>&1; then` — stderr
discarded, and the failure message at `:75` asserts a cause ("healthy at TWAP mark, or
per-block cap") that the script did not observe; `:59` `materializeLegacyReserve()` is the
same shape with `>/dev/null 2>&1` and no else branch at all.
Counter-argument tried: *is the loop bounded by an off-chain cursor elsewhere?* No cursor
or resume file exists in the sweep. Low — it is an operator script; failure mode is a slow
/ silently-failing keeper, degrading over time, not a direct user loss.

---

## R5H — CONFIRMED, LOW — VERIFIED (static)

`src/hooks/useCauldronSwap.ts:512-521` (the approval the sell path uses):
```
  const approveToken = useCallback(
    async (token: Address): Promise<`0x${string}`> => {
      ...
      return writeContractAsync({
        address: token, abi: ERC20_SWAP_ABI, functionName: "approve",
        args: [CAULDRON.gachaRouter as Address, maxUint256],
      });
```
Called from the sell flow at `src/components/cauldron/SwapWidget.tsx:289`:
`if (needsApproval) { await approveToken(token); return; } // approve first`.
The buy path states the opposite policy at `useCauldronSwap.ts:288-290`:
"BOUNDED TO `spend`. Never an infinite approval, and never the whole balance: the
allowance is the last line of defence if the calldata is ever wrong again." — and indeed
approves `spend` (`:293-296`).
Counter-argument tried (and it softens the finding): the two approvals are on **different
assets** — the buy path bounds the *quote* (real money), while `approveToken` grants the
*iteration/creature token* to the same router. An infinite allowance on the creature token
exposes only tokens the user holds for trading, and the spender is the protocol's own
`CAULDRON.gachaRouter`, not a third party. So: a genuine policy inconsistency at the same
router, Low, not High.

---

Discards: 0 findings refuted, 0 not verified. Downgrades: R5C High→Medium, R5D Medium→Low,
R5H High→Low. R5A's "floor divides ETH by a quote-denominated price" sub-claim is
HYPOTHESIS only.
