# RH1 — re-hunt: chain/config + quote-decimals batch

Working tree: `/Users/0x0010110/Documents/GitHub/Magic Internet Frens`
PoC dir: `audit/RH_MAINNET_2026-09-16/poc/rh1/`

---

## 1. What this batch changed, as read from the code

`src/config/deployments.ts` now derives `DEPLOYMENTS` from each bundled manifest's own
`chainId` (`:43-45`), fatals on duplicate ids (`:49`), and resolves ONE chain at module
load (`resolveInitialChain`, `:96-143`) in the order `?chain=` → `localStorage` →
`VITE_CHAIN_ID` (fatal if unbundled, `:121`) → `VITE_NETWORK` slot (fatal if unknown,
`:137`) → primary manifest. `src/config/chains.ts` keys per-chain defaults by chain id
(`:53-65`), fatals when an unknown chain has no `VITE_RPC_URL` (`:74`), and validates
`VITE_CHAIN_DECIMALS` to `0..36` with a fallback (`:88-92`). `src/config/cauldron.ts:29`
turns the manifest/chain mismatch from a warning into a module-init `throw`.
`src/config/quotes.ts` builds `KNOWN_QUOTES` from `round.quoteAssets` with
`decimalsKnown: true`, and `quoteMeta()` returns `decimals: 18, decimalsKnown: false` for
anything unlisted. `src/hooks/useAllowedQuotes.ts:130` adds `useQuoteDecimals`, a live
`decimals()` read returning `number | null`, wired at `TheCauldron.tsx:512-514` into
`SwapWidget`'s `quoteDecimals` / `quoteDecimalsKnown`, where `decimalsResolved`
(`SwapWidget.tsx:246`) gates signing and `qDec` (`:200`) scales `payAmount` and `minOut`.

New failure modes I derived: (a) a network round-trip now sits in the `minOut` path;
(b) three throw sites execute before React mounts, so any that fires is a white screen
with no error boundary; (c) the target chain's transport is a single `http(RPC_URL)`
with no fallback (`chains.ts:191`) while Sepolia keeps a 4-way fallback (`:187-190`).

---

## 2. Findings

```
id: RH1A   severity: High   confidence: VERIFIED (bundle facts) / DERIVED (runtime)
subsystem: quote decimals -> minOut
file:line: src/hooks/useAllowedQuotes.ts:133,155
  133:  const [dec, setDec] = useState<number | null>(native ? 18 : null);
  155:  usePoll(load, 300_000, !!quote);
  src/hooks/usePoll.ts (effect deps):  }, [intervalMs, enabled]);
  src/components/cauldron/TheCauldron.tsx:514
  514:  const liveQuoteDecimals = onChainQuoteDecimals ?? liveQuote.decimals;
  src/components/cauldron/SwapWidget.tsx:200,222,223
  200:  const qDec = qNative ? 18 : quoteDecimals;
  222:  const outDecimals = mode === "buy" ? 18 : qDec;
  223:  const minOut = minOutFor(expectedOut, outDecimals);
title: For the first 300 s of every session on an ERC20-quoted generation the new
  on-chain decimals hook serves a latched 18 — overriding the manifest's correct 6 —
  so every sell signs a payout floor 1e12 too high (executes then reverts, gas burned)
  and every buy signs a token floor 1e12 too low (effectively minOut = 0, free sandwich).
precondition: the live generation is quoted in a 6-decimal ERC20 (USDG). Reached by
  governance summoning or rotating into a non-native quote — a shipped feature.
  No attacker action needed to open the window; it opens on every page load.
sequence:
  1. user loads /cauldrons. `useCurrentQuote` returns its initial NATIVE_QUOTE
     (useAllowedQuotes.ts:73), so `useQuoteDecimals` sees native=true, seeds dec=18
     (:133) and `usePoll` fires `load` once, which sets 18 (:136).
  2. ~1 s later `useCurrentQuote` resolves to the 6-decimal USDG address. `native`
     flips to false and `load` is rebuilt — but `usePoll`'s effect deps are only
     `[intervalMs, enabled]`, and `enabled = !!quote` was already true (the zero
     address is a truthy string). The effect does NOT re-run; `load` lives in a ref.
     No further call until the 300 000 ms tick.
  3. `onChainQuoteDecimals === 18`, so `quoteDecimalsKnown` is true (TheCauldron:513)
     and `liveQuoteDecimals = 18` (:514) — the `??` prefers the stale hook value over
     the manifest's correct 6.
  4. SELL leg: outDecimals=18, minOut = parseUnits(expected,18) = 1e12x the achievable
     payout. The swap executes and reverts on slippage; the panel meanwhile renders
     `formatUnits(minOut, 18)` (SwapWidget:605) = a plausible "1000.000000".
  5. BUY leg: payAmount = formatUnits(quoteExpected, 18) on 6-decimal raw units
     (:202) = 1e12 too small -> estTokensOut 1e12 too small -> minOut nonzero (so the
     `minOut <= 0n` refusal at :309 does NOT fire) but 1e12 below honest.
capital: none for the window to exist. To harvest step 5: a sandwich bot, capital
  FLASHLOANABLE, and full pending calldata is publicly readable on a ~100 ms chain.
attacker_cost: gas + swap fees.  damage: every sell reverts for 300 s after each page
  load (self-inflicted DoS, gas burned per attempt); every buy in that window carries
  an effectively-zero slippage floor -> a sandwicher takes the whole price impact.
  At a 50 ETH pool and a 5 ETH buy that is single-digit ETH per victim trade.
poc: audit/RH_MAINNET_2026-09-16/poc/rh1/rh1_stale_quote_decimals.mjs   needs_fork: no
note: this is the exact 1e12 defect the hook's own docstring (useAllowedQuotes.ts:118-124)
  says it exists to remove; the hook reintroduces it with HIGHER precedence than the
  manifest, so the surface is strictly worse than before for a manifest-listed quote.
```

PoC output (all assertions reached, exit 0):
```
usePoll compiled deps: [ 't', 'n' ] (len 2)
useQuoteDecimals compiled: useState(isNative?18:null) + usePoll(load, 3e5, !!quote)  OK
t=0ms      quote=0x000000 dec=18
t=1s       quote=0xusdg dec=18   <- 6-decimal token
t=61s      quote=0xusdg dec=18
t=311s     quote=0xusdg dec=6   (first on-chain read: ["0xusdg"])
buy 1,000 USDG:  honest minOut = 980100000000000007340032 token-wei
                 signed minOut = 980100000000 token-wei   (ratio 1 : 1000000000000)
```
Part 1 is VERIFIED against the shipped bundle (`dist/assets/index--w1LXG2g.js`:
`function Y1(e,t,n=!0){const r=E.useRef(e);r.current=e,E.useEffect(()=>{...},[t,n])}`
and `dist/assets/TheCauldron-BVdVHvsC.js`: `...useState(e?18:null)...pe(o,3e5,!!s)`).
Part 2 is a React-semantics simulation -> DERIVED.

```
id: RH1B   severity: Medium   confidence: DERIVED
subsystem: decimals gating
file:line: src/components/cauldron/TheCauldron.tsx:513
  513:  const quoteDecimalsKnown = onChainQuoteDecimals !== null || liveQuote.decimalsKnown === true;
title: The "never sign a guessed decimals" gate is an OR, so a manifest entry alone
  satisfies it — the on-chain read can fail entirely and signing still proceeds on
  bundled data, which is the split source of truth the hook was added to close.
precondition: the live quote is listed in `round.quoteAssets` (quotes.ts:52-60 sets
  `decimalsKnown: true` unconditionally for every manifest entry).
sequence: 1. `decimals()` reverts / RPC 429 -> setDec(null) (useAllowedQuotes.ts:150).
  2. `quoteDecimalsKnown` is still true via the right-hand operand.
  3. `liveQuoteDecimals` falls back to the manifest number and `decimalsResolved`
     (SwapWidget.tsx:246) lets the user sign.
capital: n/a   attacker_cost: n/a
damage: a stale manifest decimals for a rotated quote signs a 1e12-scaled floor with
  no warning. Bounded by operator manifest hygiene; no attacker lever found.
poc: same script (asserts the OR's operands); needs_fork: no
```

```
id: RH1C   severity: Medium   confidence: DERIVED
subsystem: target-chain transport resilience
file:line: src/config/chains.ts:187-191
  187:  [sepolia.id]: fallback(
  188:    SEPOLIA_RPCS.map((u) => http(u, { batch: { wait: 24 }, retryCount: 2, retryDelay: 250 })),
  189:    { retryCount: 2, retryDelay: 300 },
  190:  ),
  191:  [targetChain.id]: http(RPC_URL),
title: The mainnet target chain gets a single un-batched, un-retried, un-failed-over
  RPC while the testnet keeps a 4-way fallback; one 429 on the `decimals()` read
  leaves an unlisted quote unpriceable, and usePoll does not retry for 300 s.
precondition: chain 4663, where only two public RPCs exist and 429s are normal.
sequence: 1. `decimals()` 429s -> setDec(null). 2. quote is NOT in the manifest ->
  `decimalsKnown` false -> `decimalsResolved` false -> `priceable` false ->
  SwapWidget refuses to sign. 3. No retry until the next 300 s tick (usePoll's
  effect does not re-run on failure), so the trade panel is dead for five minutes.
capital: n/a (a third party cannot target one user's RPC, so this is fragility not
  a griefing primitive — hence Medium, not High).
damage: rolling 5-minute trading outages proportional to RPC error rate.
poc: read-only; see chains.ts:187-191 quoted above.   needs_fork: no
```

---

## 3. Refutations — throw sites I attacked and could not fire at a user

- **`src/config/cauldron.ts:29` manifest/chain mismatch (module-init throw, present in
  the main chunk: `dist/assets/index--w1LXG2g.js` contains
  `if(de.chainId!==qn)throw new Error(\`[cauldron] MANI...`).** I tried to reach it as
  an ordinary user on the wrong wallet network. It cannot be: both operands are
  build-time. `round.chainId === ACTIVE_ROUND.chainId === SELECTED_CHAIN_ID`
  (deployments.ts:148) and `ACTIVE_CHAIN_ID = IS_TARGET ? CHAIN_ID : sepolia.id` where
  `IS_TARGET = SELECTED_CHAIN_ID !== sepolia.id` and `CHAIN_ID = SELECTED_CHAIN_ID`
  when non-Sepolia (chains.ts:36,169,214-215). Both branches are identities. The
  connected wallet's chain is never read on this path. **Operator-only, fails closed.**
- **`?chain=` as a hostile link (deployments.ts:100-105).** Gated by `isDeployChain`,
  so it can only select a BUNDLED manifest, and it is not persisted to `localStorage`
  (only `selectDeployChain` writes, :160). A link cannot strand a user on a chain the
  build does not carry, and the switcher is always available to recover. No finding.
- **Stale `localStorage` across a cutover.** A persisted `11155111` after `round.json`
  is repointed to 4663 fails `isDeployChain` and falls through to the env default
  (:108). Handled.
- **Fresh clone, no env set.** Ran `npm run build` with no `VITE_*` exported:
  exit 0, `prebuild` ran `scripts/verify-manifest.mjs` and passed, 5 routes prerendered.
  No module-init throw fires on the default configuration. **VERIFIED.**
- **`VITE_CHAIN_DECIMALS` bounds (chains.ts:88-92).** `Number("")` is `NaN` and
  `Number(undefined)` is `NaN`, both failing `isSafeInteger` -> falls to `D?.decimals`.
  `0` and `36` are both accepted, `-1`/`37` rejected. Correct at both edges; the
  fallback is per-chain, not a flat 18. No finding.
- **`decimals()` returning 37 or reverting (useAllowedQuotes.ts:146-151).** Fails to
  `null`, which is the fail-closed answer. The problem is not this branch — it is that
  the branch never runs after a quote change (RH1A).

## 4. Leads (HYPOTHESIS)

- **L1** `CrystalCauldronGame.tsx:217` uses the same `quoteDecimals` prop in
  `formatUnits(quoteExpected, quoteDecimals)` and `:283` passes `spinFloor` into
  `spin(...)`. If it is fed from the same `liveQuoteDecimals`, RH1A applies to the
  gacha floor as well. Next step: read `TheCauldron.tsx:1085` prop wiring and check
  whether `spinFloor` is scaled by `quoteDecimals`.
- **L2** `useCauldronSwap.ts:213,256,277` (`quoteExpected`, `quoteInForTypedAmount`)
  receives `quoteDecimals` from `SwapWidget.tsx:310`. Next step: check whether the
  zap's own floor is also built from the stale value, which would mean the ETH->quote
  leg is mispriced too, not just the pool leg.
- **L3** `indexer/ponder.config.ts` / `indexer/src/api/index.ts` were in the batch and
  I did not reach them inside budget. Next step: check whether the indexer's default
  chain and the frontend's `SELECTED_CHAIN_ID` can disagree when `round.json` is
  repointed but `round.robinhood.template.json` is not copied over it.
```
