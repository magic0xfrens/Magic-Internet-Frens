# COH_A — Perpetuals / Liquidation / PLV Vault coherence

Scope: `PerpEngine.sol`, `PerpVault.sol`, `PerpSwapLib.sol`, `PerpMarkSource.sol`,
`PerpStakerOracle.sol`, the liquidation path in `CauldronHook.sol`; frontend
`usePerpEngine.ts` / `usePerpVault.ts` / `config/perp.ts` / `PerpPanel.tsx` /
`StakePanel.tsx`; indexer `ponder.config.ts` / `src/index.ts` / `src/api/index.ts`.

Method: read + grep only. No Foundry run (a runner holds the tree). Every claim
below is tagged VERIFIED (read the exact lines in this tree) or DERIVED
(read and reasoned, not executed). Nothing here was executed on chain.

---

## 1. Mismatch table

| id | severity | promise | contract evidence | frontend / indexer evidence | verdict |
|---|---|---|---|---|---|
| A-1 | High | "Leverage works on any quote — the ETH-only banner was removed because the engine is quote-agnostic" (`TheCauldron.tsx:1057-1068`) | `PerpEngine._pullQuote` really is quote-agnostic: native asserts `msg.value == amount` (`PerpEngine.sol:234`), ERC20 **refuses any msg.value** (`:236`) and pulls via `transferFrom` (`:243`) | `usePerpEngine.openLong/openShort` hardcode 18 decimals and **always** send `value` — `const value = parseEther(collateralEth.toFixed(18)); … args:[lev,minOut,liqHint,value], value` (`src/hooks/usePerpEngine.ts:223,228` and `:239,243`). There is no approve path and no `quoteToken` argument in the whole hook. `PerpPanel` is mounted with **no** `quote`/`quoteSymbol`/`quoteDecimals` props (`TheCauldron.tsx:1073-1082`) while its siblings `SwapWidget` (`:1018-1020`) and `StakePanel` (`:1129`) all receive them | **MISMATCH.** On a 6-dec USDG generation every open reverts `BadParam()` at `PerpEngine.sol:236`. Funds are safe (the revert returns the ETH), but the feature the UI advertises is unreachable and the whole panel is denominated "Ξ ETH" (`PerpPanel.tsx:493`, `:282`, `:615`, `:642`). DERIVED |
| A-2 | High | The revert a user hits is explained in words | `BadParam()` declared `PerpEngine.sol:479` and thrown on every ERC20-quote open (`:236`) | `BadParam` appears in **neither** `PERP_ABI`'s error list (`src/config/perp.ts:118-138`) nor `PERP_ERROR_HELP` (`:218-255`) nor `PERP_ERROR_SELECTORS` (`:268-281`) | **MISMATCH.** `explainPerpError` falls through to `raw.split("\n")[0].slice(0,140)` (`perp.ts:298`) — the user gets a hex blob. Compounds A-1. VERIFIED (grep) |
| A-3 | High | PLV stake amounts are shown in the live quote's units (the 6-decimal fix landed in `StakePanel` this run) | `PerpVault.ethPosition(address)` returns `(redeemable, instant, pending)` in **quote raw units** (`PerpVault.sol:770`); `assetsEth` likewise | The indexer formats all four with `formatEther` — `const n = (v: bigint) => Number(formatEther(v));` at `indexer/src/api/index.ts:1376` (`/perp-vault/:user`) and `:1348` (`vaultState()`); these are exactly the numbers `StakePanel` renders as `{compact(pos.redeemable)} {unit}` (`StakePanel.tsx:262-266`) and `Vault {qSym}` (`:257`) | **MISMATCH — the sibling of the fixed stake-panel bug.** `StakePanel`'s *write* path now parses in `quoteDecimals` (`:94`), but its *read* path comes back through an 18-decimal formatter. A 10 USDG stake displays as `0.00000000001`. The indexer already owns the right primitive — `rawToQuoteAmount(raw, quoteDecimals)` in `indexer/src/quoteUnits.ts:34` — and does not use it here. VERIFIED (grep) |
| A-4 | Medium | The perp position list shows real collateral / liq price | `positions(id)` returns `collateral`/`principal` in quote units, `size` in token units (`PerpEngine.sol` position struct, mirrored in `PERP_ABI` `perp.ts:95-102`) | `indexer/src/api/index.ts:1115`: `const collateral = Number(formatEther(p[2])), size = Number(formatEther(p[3])), principal = Number(formatEther(p[4]));` then `exactLiqPrice` divides principal by size | **MISMATCH (latent).** On a 6-dec quote the liq price is off by 1e12. Unreachable today only because A-1 makes ERC20 opens revert; it becomes live the moment A-1 is fixed. DERIVED |
| A-5 | Medium | The exit queue can be unstuck | `settlePendingEth(address)` `PerpVault.sol:493`, `settlePendingToken(address)` `:730`, both permissionless; `QueueInsolvent` gate at `:309` (ETH) and `:634` (token) | ABI present and correctly shaped (`perp.ts:185-186`); `QueueInsolvent` help text names them (`perp.ts:239`). **Nothing in `src/` calls either** (grep `settlePending` → only `src/config/perp.ts`). The indexer registers `PerpEngine` only (`indexer/ponder.config.ts:210`); there is no `PerpVaultAbi` in `indexer/abis/` and no `PerpVault` entry, so `QueueWrittenDown` has no consumer and no list of queued holders exists | **CONFIRMED GAP** (already recorded in LEDGER as OPEN). See §2.3. VERIFIED (grep) |
| A-6 | Medium | A trader knows their position can be force-closed inside a stranger's swap, at a *projected* price, with a 15% slack band | The pre-trade sweep liquidates on **zero-buffer insolvency at the projected post-trade price** (`PerpEngine.sol:1580-1582`: `uint160 pj = _projSqrtP; uint160 sp = pj != 0 ? pj : _sqrtP(); if (sp != 0) insolvent = _insolventVal(p, _quoteAt(p.size, sp));`), fired from `CauldronHook._liqSweep` on **any** swapper's `beforeSwap` (`CauldronHook.sol:1328`); overshoot band `SLACK_BPS = 1500` (`PerpSwapLib.sol:63`) | The only trader-facing risk sentence is `PerpPanel.tsx:592`: "Liquidations trigger off a manipulation-resistant TWAP mark; fees fund the OG dividend + treasury." | **DISCLOSURE GAP.** The sentence is true of the *maintenance* leg only. It does not say the insolvency leg has **no** maintenance buffer, runs on a **projected** price, executes inside someone else's transaction, or can overshoot by up to 15%. VERIFIED (read both) |
| A-7 | Low | `PERP_ERROR_HELP.QueueInsolvent` describes the current queue | Queue is now UNITS × a single INDEX; a shortfall is recognised **once, globally**, by scaling the index (`PerpVault.sol:193` region, per `beedf49`) — `settlePending*` is idempotent and per-user state is untouched | `perp.ts:239` says settling "banks **that address's** write-down" | **STALE WORDING.** Under the r45 shape there is no per-address write-down; banking the global index is what unblocks everyone. The advice still works; the mechanism named is the pre-`beedf49` one. VERIFIED |
| A-8 | Low | `PERP_ERROR_HELP.LiqGasStarved` quotes the real floor | Floor measured 1,064,355 gas (LEDGER, fixer-liq S08 row); gate at `CauldronHook.sol:801,805,835` | `perp.ts:243` says "roughly 1.05M gas" | **AGREES.** No mismatch. VERIFIED |

No Critical found in this scope. Nothing here lets a user lose funds through the
UI: A-1/A-2 revert before value moves, A-3/A-4 are display-only.

---

## 2. Answers to the named questions

### 2.1 The liquidation promise — traced end to end

**Claim:** positions that would go underwater are closed *before* the trade that
sinks them, so PLV stakers do not underwrite traders.

**Trace (all VERIFIED by reading, not executed):**

1. `CauldronHook._beforeSwap` calls the sweep with the pending trade attached:
   `_liqSweep(sender, params.amountSpecified, inputIsQuote, params.sqrtPriceLimitX96)`
   — `CauldronHook.sol:1328`. It is ungated except for the adoption gate and the
   `_inSelfBuy/_inRelaunchClose` early-out.
2. `_liqSweep` (`CauldronHook.sol:797-837`) forwards `g - reserve` gas to
   `PerpEngine.sweepLiquidations(tx.origin, amountSpecified, isBuy, limit)`; if
   the budget is short **and** `amountSpecified != 0`, it staticcalls
   `openCount()` and **reverts `LiqGasStarved()` when the book is non-empty**
   (`:833-835`). Empty book ⇒ no floor at all (`:824`).
3. `PerpEngine._doSweep` scans the whole book in one pass —
   `while (scanned < len && kills < MAX_LIQ_PER_SWAP)` (`PerpEngine.sol:1150`),
   the 12-slot window is gone — bounded by
   `if (gasleft() < SWEEP_KILL_RESERVE) break;` (`:1166`, `SWEEP_KILL_RESERVE = 420_000` at `:429`).
4. Per candidate it **re-projects from live spot**:
   `if (spec != 0) _projSqrtP = _project(spec, isBuy, limit);` (`:1179`), then
   `_tryLiquidate` (`:1180`).
5. `_liqTest` judges insolvency at the projected price with **zero buffer**
   (`:1580-1582`, `_insolventVal` at `:1590-1591`), and an insolvent position is
   **exempt from the per-block throttle** (`:1606` comment block).

**Verdict: the promise now holds for the common case, and the gas bypass that
broke it is closed.** It does *not* hold, and here are the exact conditions:

- **Book larger than 8 liquidatable positions.** `MAX_LIQ_PER_SWAP = 8`
  (`PerpEngine.sol:186`) hard-caps kills per swap. A trade that bankrupts 9+
  positions leaves the remainder open and insolvent. DERIVED.
- **Gas above the revert floor but below the sweep's appetite.** The floor gate
  only checks `g > LIQ_GAS_RESERVE + 2·LIQ_GAS_MIN` (≈980k, `:799-801`). A
  swapper who supplies exactly that passes the gate, forwards ≈`g-580k`, and the
  `SWEEP_KILL_RESERVE` break at 420k funds roughly **one** kill before
  degrading silently. The pre-trade sweep is therefore best-effort *above* the
  floor, not complete. The app pins 8,000,000 on every swap-bearing call
  (`useCauldronSwap.ts:70` `LIQ_SWAP_GAS = 8_000_000n`, applied at `:305,324,428,442,556`;
  `usePerpEngine.ts:58` `LIQ_OPEN_GAS = 8_000_000n`), so **app users** fund the
  full sweep; a raw/aggregator caller need not. DERIVED.
- **Post-trade sweep still degrades silently by design** — `_liqSweep(sender, 0, false, 0)`
  at `CauldronHook.sol:1006`, `amountSpecified == 0` so the `else if` branch at
  `:805` is never taken. Stated and intended.
- **The projection is of the *engine's own* pool, not the swapped pool.**
  `_project` (`PerpEngine.sol:1078`) feeds `PerpSwapLib.projectedSqrtPriceX96`
  with the engine's `_sqrtP()`/`activeEthDepth()`. A swap on any other tracked
  pool still triggers the sweep with that swap's `amountSpecified` projected onto
  the engine's pool. `CauldronHook.linkVolume` refuses siblings while
  `openCount > 0` (spec `E_D_spine_rotation_perps.md` S2), which bounds this in
  practice. DERIVED.
- **Mark source unarmed.** `markSource` is cleared on every generation sync
  (`PerpEngine.sol:1480`) and `_currentTick` falls back to the engine's own pool
  (`:700-712`). The *insolvency* leg never used `markSource` — it uses
  `_projSqrtP`/`_sqrtP()` — so pre-emptive liquidation still fires unarmed; only
  the TWAP/maintenance leg degrades to the manipulable own-pool tick.
  `PERP_ERROR_HELP.NotArmed` (`perp.ts:244`) describes this correctly.
- **Quote rotated.** `_guardOpen` (read in full this tree) checks summon warmup,
  ring warmup, `_isDead()`, leverage bounds — and **still has no
  `quote != registry.generationQuote(...)` check**, exactly as
  `audit/spec/sections/E_D_spine_rotation_perps.md` S3 records. A position opened
  in the post-rotation window pins the engine to the drained pool, and every
  price the sweep uses — mark, projection, depth — then comes from that pool.
  The pre-emptive sweep keeps firing; it fires off the wrong price. **This is the
  condition under which the promise is most wrong, and it is still open.** DERIVED.

### 2.2 Does the UI tell a trader their position can be closed inside someone else's swap?

**No.** `PerpPanel.tsx:592` is the only risk sentence and it names only the TWAP
mark. `PerpPanel.tsx:169-183` and `:580-584` do disclose the *self*-liquidation
case ("would be liquidated the instant it opens"), which is the narrower one.
Nothing anywhere says a third party's swap runs a liquidation sweep against your
position at a *projected* post-trade price with no maintenance buffer. Given
`SLACK_BPS = 1500` (`PerpSwapLib.sol:63`) permits a measured ~3.2% overshoot on
a ~0.93 ETH principal (LEDGER R1A row), this is a real risk the trader is not
told about. **Yes, it is a disclosure gap worth flagging** — one sentence in the
`pp-note`, severity High only because it is about risk, not funds.

### 2.3 The stuck-queue gap — confirmed and assessed

Confirmed on all three legs:
- Contract: `settlePendingEth(address)` `PerpVault.sol:493`, `settlePendingToken(address)` `:730`, both permissionless; `QueueInsolvent` at `:309`/`:634`.
- Frontend: `grep -rn settlePending src/` returns **only** `src/config/perp.ts:185-186` (the ABI) and `:239` (the help text). No call site.
- Indexer: `PerpEngine` is the only perp contract registered (`indexer/ponder.config.ts:210`); there is no `PerpVaultAbi` under `indexer/abis/`; `QueueWrittenDown` is decoded nowhere. `/perp-vault/:user` (`api/index.ts:1374`) is a per-address eth_call, so it can answer "is *this* address queued" but cannot enumerate queued holders.

**Smallest honest remedy: a keeper script, plus one line of UI text.** A button
is genuinely worse than nothing here because the app has no way to choose the
`address` argument — the only address it knows is the connected wallet, and a
blocked *depositor* is by definition not the queued party. The honest minimum is
(a) `scripts/keeper.sh` gains a `settle` verb that walks `Queued`/withdraw logs
and calls `settlePendingEth/Token` for each, and (b) `PERP_ERROR_HELP.QueueInsolvent`
stops implying the user can do it and says an operator/keeper does. If a UI
action is wanted later it needs the indexer to index `PerpVault` first, which is
a schema change, not a button.

### 2.4 Units

Quote assets in the manifest: ETH (18), USDG (6), xNVDA (18) — `indexer/deployments/round.json` `quoteAssets`.

| path | parses/formats in | correct? |
|---|---|---|
| `StakePanel` deposit (quote side) | `quoteDecimals` — `StakePanel.tsx:94` `const qDec = v.quoteIsErc20 ? quoteDecimals : 18;` | ✅ (fixed this run) |
| `usePerpVault.depositQuote` | raw bigint passed through, `value` only when native (`usePerpVault.ts:166-172`) | ✅ |
| `usePerpVault.approveQuote/approveToken` | bounded to the exact amount, spender `PERP.vault` (`:158-163`, `:176-181`) | ✅ |
| `usePerpVault.depositEth` | `parseEther` (`:129`) | ⚠️ native-only wrapper; only reachable when quote is ETH. Acceptable. |
| **`/perp-vault/:user` + `vaultState()`** | **`formatEther` (`api/index.ts:1376`, `:1348`)** | ❌ **A-3** |
| **`exactLiqPrice` collateral/principal** | **`formatEther` (`api/index.ts:1115`)** | ❌ **A-4** |
| **`usePerpEngine.openLong/openShort`** | **`parseEther` + always-native `value` (`:223,228`, `:239,243`)** | ❌ **A-1** |
| `usePerpEngine.floorFrom` (minOut) | `parseEther` (`:67`) | ❌ for a short's `minEthOut` (quote units) on a 6-dec quote; correct for a long's `minTokenOut` (token is always 18, `quoteUnits.ts:11`). Sub-case of A-1. |

`minOut` provenance: derived client-side from `spotPrice` (the Ponder mark) ×
notional × `(1 - slipBps)`, clamped to ≤90% (`usePerpEngine.ts:62-68`),
`PERP_SLIPPAGE_BPS = 300` (`perp.ts:45`). The user can see and change the
tolerance in the panel. Trustworthy as a floor; it is not an oracle, which is
the right design.

### 2.5 `LiqGasStarved` disclosure reach

`error LiqGasStarved()` is declared in `HOOK_ABI` (`src/config/cauldron.ts:239`)
so viem decodes it by name, and the selector `0x38dc5cd1` is a fallback
(`perp.ts:280`). Surfaces where a swap can revert with it:

- `SwapWidget` buy/sell → `explainPerpError(e)` at `SwapWidget.tsx:316`. ✅
- `CrystalCauldronGame` spin → `explainPerpError(e)` at `CrystalCauldronGame.tsx:228`. ✅
- `StakePanel` → `explainPerpError` at `StakePanel.tsx:72`; vault deposits do not
  swap, so this is belt-and-braces. ✅
- `PerpPanel` open/close → `explainPerpError` at `:94` and `:289`; but
  `CauldronHook._liqSweep` returns early when `sender == perpEngine`
  (`CauldronHook.sol:798`), so a perp open/close can never raise it. ✅ (moot)
- `ForgedCreatures.revealMany` (`ForgedCreatures.tsx:140`) — reveal, not a swap.
  Not a surface.

**All swap-bearing surfaces are covered.** Additionally every one of them pins
8,000,000 gas (`useCauldronSwap.ts:70`, `usePerpEngine.ts:58`), which is ~7.5×
the measured 1,064,355 floor, so an app user should never see it. No mismatch.

### 2.6 `PERP_ERROR_HELP` entries vs. today's contract

- `LiqGasStarved` (`:243`) — matches `CauldronHook.sol:835` and the measured floor. ✅
- `QueueInsolvent` (`:239`) — correct *advice*, stale *mechanism* (A-7).
- `NotArmed` (`:244`) — matches the fallback at `PerpEngine.sol:700-712` and the
  clear at `:1480`. ✅
- `TokenDeadParked` (`:232`) — still accurate: `syncGeneration` refuses under
  quote stake, `hasQuoteStake` is in the ABI (`perp.ts:172`). ✅
- `LiqCapped` is declared in `PERP_ABI` (`:130`) but has **no** `PERP_ERROR_HELP`
  entry, so it falls through to the raw blob — and since insolvent positions are
  now throttle-exempt (`PerpEngine.sol:1606` block), a user who sees it is being
  told nothing about a state that is genuinely transient. Low.
- Missing: `BadParam` (A-2), `UtilCapped` is present ✅, `NotTrader`/`NotOpen`/
  `EthSend`/`Reentrant`/`NotVault`/`AlreadySynced`/`PositionsOpen`/`OnlyHook`
  have ABI entries but no help text — they fall through to the raw blob. Low,
  and most are unreachable from the UI.

### 2.7 Indexer coverage of perp activity

Decoded: `Opened` (`indexer/src/index.ts:427`), `Liquidated` (`:470`),
`LiquidatoorAwarded` (`:483`), `Closed` (`:502`), `PartiallyClosed` (`:528`),
`TokenDebtWrittenOff` (`:562`); schema `perpPosition` (`ponder.schema.ts:173`),
`perpStat` (`:218`), `liquidator`. **Not decoded: anything from `PerpVault`** —
no ABI, no contract registration, so `QueueWrittenDown`, deposits, withdrawals
and queue entries produce no rows. All vault UI data is live eth_call
(`api/index.ts:1348,1374`), which is why A-3 and A-5 both land here.

---

## 3. Verdict (≤200 words)

The subsystem is structured sensibly. Pre-emptive liquidation is the right
shape: judge insolvency at the price the pending trade will leave, not the one it
found, exempt insolvent positions from the anti-cascade throttle, and refuse the
trade outright rather than trade blind when the sweep cannot be funded. The
gas-cap bypass that made the whole engine optional is genuinely closed at
`CauldronHook.sol:835`. The vault's units×index queue makes a shortfall
idempotent and order-independent, which is the correct answer to a grindable
per-user write-down.

**The incentive that breaks first is the liquidator's, not the staker's.** The
keeper share (`keeperBps = 145`) is paid to `tx.origin` of whoever's swap
happened to carry the sweep — so nobody is paid to *initiate* a liquidation, they
are paid for riding along. With `MAX_LIQ_PER_SWAP = 8` and a 420k reserve break,
a book that goes bad faster than swaps arrive accumulates open insolvent
positions that only a *voluntary* swapper's gas will clear. The protocol has
outsourced its solvency to organic swap flow. On a thin brew at 3am, that flow is
zero — and `PerpEngine.liquidate(id)` is permissionless but pays the same 145bps
on a position whose gas cost may exceed it.

---

## 4. Not verified / not reached

- **Nothing was executed.** No Foundry run, no `cast` read. Every VERIFIED tag
  above means "I read these exact lines in this tree", never "I ran it".
- A-1's revert path (`BadParam` on an ERC20-quote open) is **DERIVED** from
  `PerpEngine.sol:236` — I did not build a PoC that presses the panel's open
  button against a USDG generation.
- A-3/A-4's magnitude (1e12 skew) is arithmetic, not measured against the live
  r44 vault. r44's quote is native ETH, so both are latent, not currently visible.
- I did not verify `0x38dc5cd1` is truly `keccak("LiqGasStarved()")[0:4]` with
  `cast sig`; the name-based decode via `HOOK_ABI` (`cauldron.ts:239`) makes the
  selector table redundant either way.
- `PerpMarkSource.sol` and `PerpStakerOracle.sol` were reached only through their
  consumers in `PerpEngine` (`_currentTick` at `:700-712`, the clear at `:1480`);
  I did not read either file end to end.
- I did not check `PerpSwapLib.projectedSqrtPriceX96`'s arithmetic — only that
  `_project` feeds it the engine's own pool state.
- The S06 baseline failure (`S06_PerpVaultSolvency.t.sol`) is recorded in the
  LEDGER as pre-existing and owner-less; I did not re-run or re-assess it.
