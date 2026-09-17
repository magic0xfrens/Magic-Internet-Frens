# Findings register — RH mainnet review, 2026-09-16

Orchestrator-maintained. One row per finding, severity after verification.
`fix:` empty = not yet assigned to a fixer.

## Closed — committed

| id | sev | title | fix |
|----|-----|-------|-----|
| T5A | **Critical** | Frontend could not target 4663 at all: `DEPLOYMENTS` hard-coded `{11155111, 5042002}`, so a Robinhood manifest loaded under the **Sepolia** key, force-switched the wallet to Sepolia and signed Robinhood-addressed value calldata there. Proven from the emitted bundle. | `800271a` |
| T5B | High | Unset `PONDER_RPC_URL` indexed Sepolia and served it as chain 4663 while `/freshness` reported green. | `f59425e` |
| T5D | Medium | Quote decimals came from the manifest while the address came from the chain: a 6-dec quote produced a sell floor 1e12 too large. | `72cff8b` |
| T5E + 0a/0b/0c | Low | Deploy runbook pointed at an RPC host **that does not exist** (`rpc.chain.robinhood.com`, TLS handshake_failure from three stacks); testnet id 46646 → **46630**; ops table documented env vars no code reads. | `d209241` |
| RH1A | **High (fix-induced)** | `useQuoteDecimals` latched 18 and never re-read — for 300 s of every session a **buy signed a slippage floor 1e12 too low**, nonzero so the `minOut<=0n` guard never fired. Found by re-hunt round 1. | `bff755a` |
| RH1B | Medium | "Decimals known" gate was an OR — the on-chain read could fail entirely and signing proceeded. Now AND, chain authoritative, disagreement = refuse. | `bff755a` |
| RH1C | Medium | Mainnet had a single un-retried RPC while Sepolia kept a 4-way fallback. Only CHAIN_PROFILE §8-verified hosts added (lookalike RPCs exist for this chain). | `bff755a` |
| RH1D | **High** | `useSwapTape` served the **dead generation's price** for up to 5 s after a rebirth → floor ~100× too low. Same class as RH1A, found by following its pattern. | `55b0b65` |
| RH1E | Medium | Both signing call sites passed `useLpComposition(0)` → never fetched → **every ERC20-quoted buy was permanently unpriceable**. Failed closed. | `55b0b65` |

## Open — verified, awaiting fix

| id | sev | title | blocker |
|----|-----|-------|---------|
| T1a | **High** | `LiqGasStarved` floor is a **constant** (~980k), independent of `openCount()` and of how many positions the trade bankrupts, so the gate passes trades it exists to refuse. Dose–response: cap 1.1M→3 shorts stranded, 1.2M→2, 1.6M→1, 1.9M→0. At 1.3/1.4/1.5M the tx burns an identical 880,287 gas and leaves 2 open — **~620k of supplied gas never spent**. 4.36 ETH PLV bad debt on a 30 ETH vault. | fixer in progress |
| E1A | **CRITICAL** | `PerpEngine.liquidate()` is permissionless and judges short insolvency at **live spot** (`:1581`); the projected-price guard (`:1569-1573`) covers **only** the in-swap sweep. Buy-back has **no price band** (`:1660`) and a budget spanning **all of plv** (`:1696`). One flashloaned spot push force-liquidates a **healthy** short and socializes the overspend onto stakers. **Net-positive to a pure swapper — no LP position needed** — at the protocol's own max short size (`maxNotionalBps=500`): 1 ETH push → PLV −0.0719, attacker **+0.0435**; 3 ETH push → PLV −0.4400, attacker **+0.2720**. Atomic, flashloan-repayable same-tx, repeatable across all 64 slots. | queued behind T1a (same file) |
| T3B | **High** | A crystal unresolved across two 256-block windows is **forfeited** — a 9,000 bps draw becomes a guaranteed loss. `resolveTickets` pays no keeper reward. **256 blocks ≈ 25.6 s at ~100 ms blocks**, so the two-window forfeit lands at ~51 s. Needs no attacker. | fixer in progress |
| T3C | **High** | No per-actor throttle anywhere (`cooldown\|perWallet\|perBlock\|dailyCap\|mintCap` = zero hits); `MAX_MINTS_PER_CALL=30` bounds a call, not an actor. One address took **1,632 of 3,333 NFTs for 547.4 ETH** at ~30/block, stopping only on the PoC's own loop cap. | unassigned — see open questions |
| T4C-b | Medium | **Fixed `696899b`.** An unexecutable mandate wedged `propose` until envelope expiry, guardian-only escape. New `stalled()` view (active + `movedBps==0` + `movedPrimaryBps==0` + past `COOLDOWN`) relaxes **both** the `propose:437` and `execute:617` gates. Cannot supersede an advancing mandate: one successful slice of any size by any address sets `movedBps != 0` and immunises the envelope for life. Residual: a stuck *primary* with live secondary legs still needs guardian `cancel`. | done |
| T4C | Medium | Once a quote is migrated away, the denomination can **never come home**: `rotateSliceFrom` derives the source from `generationPoolKey[gen].currency0` (written once at launch). `movedPrimaryBps` stays 0, so the envelope never deactivates and **`propose` is blocked until expiry**. | fixer in progress |
| E2A | Medium | Governance electorate farmable: the in-swap sweep credits badges to **`tx.origin`** (`PerpEngine.sol:1069` via `_sweepAfterOpen:1099`); a long opened while spot is above TWAP is **born insolvent** and the next open kills it. Auto-delegate at `MiFrensGenesis.sol:703-704`. Measured **0.001784 ETH/badge** after a one-off 4.74 ETH pump. Majority ≈ 4.74 + 0.0018·H ETH. `MiFrensGenesis.sol:175-178` documents "capital-at-risk … not cheaply farmable" — **contradicted by the code**. Second-order: each farmed kill is genuine insolvency, so **PLV capital is converted into votes**. | queued behind T1a (same file) |
| R1A | Medium (re-raised) | Free-kill inside the projection slack. Bounty scales linearly: a 100-ETH victim loses ~6.9 ETH while the searcher nets ~0.1 ETH, gas-only. | unassigned |
| R2A | Medium (re-raised) | `PerpVault._syncEthQueue` (`:460-466`) haircuts the queue **only** when it exceeds total backing; below that, queued stakers eat **0%** and stayers **100%**. Contradicts the code's own "shared in proportion, not by reaction speed". | unassigned |
| S06 | open 3+ reviews | Bad-debt shedding. Still failing today, numbers **bit-identical at five measurements** (`344218925886143795 <= 459182015833333191`). E2 verdict: **should not be open on a real-money deploy**; ~0.115 ETH misallocation, scales with PLV. | owner decision |
| F-ICE | Low | solc 0.8.30 crashes ("Tag too large for reserved space") compiling the fork-harness test under the project's own `cauldron` profile. Build-integrity issue. | unassigned |
| COV-1 | Low | `test/attacks/YBase.sol:356 YMockMiFrens` has **no `mintLiquidator*`**, so every badge in the shared harness silently becomes `badgesOwed`. **All existing tests are blind to badge minting** — this is why E2A survived four reviews. | unassigned |

## Refuted — do not re-raise without new evidence

- **PoolKey / CREATE2 squat** — closed by `_afterInitialize:643 require(sender == registry)`. (H4)
- **Rotation venue + `minOut` drain** — closed by `allowedVenue` by PoolId + pre-swap oracle floor (`QuoteRotator.sol:359/374/389`). (H4)
- **Flash-borrowed votes** — sealed `block.number-1` snapshot. (E2)
- **Sandwiching the liquidation sweep** — refuted **by chain property**: `eth_maxPriorityFeePerGas`=0, FCFS at one sequencer. Ordering cannot be bought on 4663. (P0.5/E2)
- **Same-block TWAP mark manipulation** — `lastTick·0` tail, 5-min window, warmup guard. (H2)
- **PerpVault units×index restructure** — no dilution, no >1-wei rounding gain, no insolvency; settle-spam closed. (H2)
- **Module-init throws blanking the app for an ordinary user** — provably operator-only; both operands are build-time identities, wallet chain never read. Fresh clone with no env builds clean. (RH1)
- **`linkVolume` spam / SIB1-D** — registry-gated, not permissionless. (E2)
- **Churn as an extraction path** — measured **14.69×**, not the briefed 30.9×; *worse* per ETH of fee burned than a plain buy (36.7 vs 48.5); and `lifetimeVolumeOf`/`totalLifetimeVolume` (`CauldronHook.sol:956-961`) are **read by nothing on-chain**. (H3)
- **`liquidate()` as the vote-farming path** — never productive, `kills attempted 0`. The productive path is the in-swap sweep. (V2)

## Open questions that decide a severity

1. **T3C redemption arithmetic — NOT costed.** Does redeeming 1,632 NFTs return more than the ~1,118 ETH full-supply cost? DERIVED bound says no (floor pot funded only by the legacy-buyback slice, must be dumped into the same pool) → stays High. Executing it would settle Critical vs High.
2. ~~**E1A lead L3 — attacker-as-LP.**~~ **RESOLVED: E1A is CRITICAL.** The −0.0147 ETH was a dust-scale artifact (0.02 ETH short). At max notional a **pure swapper** nets positive with no LP position; the LP-capture caveat is withdrawn. See the E1A row.
3. ~~**E1A lead L4 — over-push settle-revert.**~~ **RESOLVED: transient DoS, NOT a permanent brick.** A 300-ETH push makes buy-back cost exceed engine ETH so `settle{value}` and `liquidate()` revert — but the owner's `close()` succeeds once spot is restored (`E1C` PASS: reverted-under-push=yes, closed-after-restore=yes). Low/Medium griefing, capital-bound rather than flashloan-atomic. The revert is a balance comparison (value-logic, optimizer-independent), reproduced at `runs={0,50}`.

## The 18-decimal class — NOT closed by this run, tracked instance by instance

The previous review's dominant finding class ("the contracts were built for quote
rotation and the read layer was not"). **Three independent agents each found
surviving instances**, which is the strongest evidence that this is a class problem
and not a list of bugs. Treat any new quote-denominated value as guilty until proven.

| instance | where | state |
|---|---|---|
| Quote decimals from manifest, address from chain | `src/config/quotes.ts` | fixed `72cff8b` |
| `useQuoteDecimals` latched 18 | `src/hooks/useAllowedQuotes.ts` | fixed `bff755a` |
| Indexer `bufferEth/1e18` vs manifest ETH threshold | `indexer/` | fixed `1c53fed` |
| **CA-1** perp collateral/OI/PLV/depth at hardcoded `1e18` | `indexer/src/index.ts:430,431,506,507`, `api/index.ts:205` | fixed `f5580de` |
| **CA-2** `Ξ` hardcoded, mislabels a USDG book | frontend | fixed `2508a6b` |
| **B-4** `legacyThreshold = 0.02 ether` vs quote-raw `legacyBuffer` | `CauldronHook.sol:336` vs `:1115,:1124` | **OPEN** — DERIVED, needs a 6-dec PoC; on USDG the floor buyback silently never fires while the UI advertises it |
| Activity feed `quoteWei` round-trip | `useActivityFeed.ts:49` → `ActivityDrawer.tsx:104`, `SpellFeed.tsx:116` | **OPEN** — display only, no signature depends on it; 1e12 off on a 6-dec quote |

**Confirmed correct, do NOT "fix":** `indexer/src/api/index.ts:1588,1620` (vault helpers
already pair a decimals-aware `q()` with `formatEther` `n()` for the token side),
`plvToken`, `size`, `reserveTokens`, `StakePanel` token maths,
`usePerpVault.depositEth` (native `value`), `vaultEth` (vault holds native ETH).

## Measurement reconciliation — E2A cost per badge

Two agents reported figures 42× apart and neither was wrong; they measured different
things. **Both numbers belong in the report:**
- Verifier V2: 8 badges = 4.7423 ETH, 64 badges = 4.8422 ETH → **marginal 0.001784 ETH/badge**.
- Coherence B: 4.84 ETH / 64 badges → **average 0.0757 ETH/badge**.

The pump is a **one-off ~4.74 ETH**; each additional badge then costs ~0.0018. The
marginal figure is the one that governs "what does a majority cost" at scale; the
average is the one that governs a small farm. Quote both or the number looks wrong.

## Deferred with a written recommendation

- **`usePoll` primitive** (`usePoll.ts:35-36`): deps are `[enabled, intervalMs]` while `fn` lives in a ref, so **every** caller whose loader closes over a changing input inherits RH1A's bug silently. Contained fix: optional 4th `key` param added to the effect deps, ~4 lines, **zero call-site changes** (13 call sites, all in `src/hooks/`). Not shipped: dead code until call sites opt in, and a wide opt-in sweep this late in a run is how the next bug gets introduced. First adopters: `useActivityFeed:65`, `useCandles`, `useMiFrensPresale`.
