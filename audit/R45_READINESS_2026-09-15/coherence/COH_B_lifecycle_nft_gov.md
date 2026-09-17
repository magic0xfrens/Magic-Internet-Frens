# COH-B — lifecycle / NFT-gacha / governance / treasury coherence (r45 readiness)

Scope: does the protocol DO WHAT IT SAYS across contract, frontend and indexer.
Not a vulnerability hunt. Nothing was modified. Tags: VERIFIED (ran it) /
DERIVED (read + reasoned) / NOT VERIFIED.

## 1. Mismatch table

| id | sev | promise | contract evidence | frontend / indexer evidence | verdict |
|---|---|---|---|---|---|
| B-1 | High | "your crystal reveals on your next spin" — nothing says a crystal can EXPIRE and be forfeited | `cauldron/GachaLib.sol:124-135` (second expiry sets `expired`), `:150` (`win = (forced \|\| (!expired && roll < odds))`), `:182` (no pity credit), `:183` (`TicketLost`) | `src/components/cauldron/CrystalCauldronGame.tsx:519` "resolves on your next spin", `:571` "forged — reveal on your next spin"; zero occurrences of expire/forfeit/256 in the component; `scripts/keeper.sh:58-65` materializes only, never resolves | CONFIRMED mismatch (DERIVED) |
| B-2 | High | the displayed "% chance" is the chance the chain rolls | `CauldronGachaRouter.sol:326` `hook.commitCrystals(..., _playInCurveUnits(playWei))`, `:136-145` multiplies by `usdPerRawUnit(quote)/1e18`; `CauldronHook.sol:2346-2357` `oddsForPlay` is linear in its argument | `CrystalCauldronGame.tsx:162` `spinWei = parseEther(stake*loops)` → `:202` `oddsForPlay(spinWei)` RAW; nothing in `src/` calls the router's `playInCurveUnits` (grep: only `config/cauldron.ts:208` declares `oddsForPlay`) | TRUE TODAY, BREAKS ON ONE OWNER TX (VERIFIED, see §2.1) |
| B-3 | High | "available for the rebirth" | `cauldron/PoolOps.sol:1195-1211` seeds from `wantQuote` / native / `oldQuote` reserves; `:225` `MIN_SEED_UNITS = 777_000_000e18 >> 60` = 673,940,070 BASE units; `:1158-1174` documents that this is 42–673 **tokens** on a 6-dec quote; `CauldronRegistry.sol:1030` `revert NoLiquidityToSeed()` | `indexer/src/api/index.ts:373` reads `relaunchETH` ONLY (never `relaunchAsset`), `:383/:385` `formatEther` on both it and `getBalance(vault)`; `src/hooks/useCauldronMachine.ts:244` `availableEth = relaunchEth + vaultEth` | CONFIRMED mismatch (DERIVED) |
| B-4 | Medium | "Spin 3× — more loops = more volume from the same ETH" | `CauldronGachaRouter.sol:379` `playChurn` exists in source; per LEDGER the r44 runtime lacks the selector | `src/hooks/useCauldronSwap.ts:73-101` probes the bytecode and falls back to `play` with `loops` DROPPED (`:421-424`, `:436-439`), while the UI still charges `stake` and shows `{loops}×` and `{stake*loops}Ξ volume` (`CrystalCauldronGame.tsx:610,616,629`) | CONFIRMED, mitigated for r45 by the verify-selectors abort |
| B-5 | Medium | "N until guaranteed" pity meter | `CauldronHook.sol:451` `uint256 internal pityThreshold = 8`, setter `:2563`; no public getter | `CrystalCauldronGame.tsx:212` `const pityN = 8;` hard-coded | CONFIRMED (cosmetic until the setter is used) |
| B-6 | Medium | "Minted out" / spin availability | `GachaLib.sol:150` win requires `minted < max`; `:182` a `minted >= max` roll earns NO pity credit either | `CrystalCauldronGame.tsx:110` `soldOut` from `nftMinted` = indexer `/collections` (`useCauldronMachine.ts:146,163`), `nftMax` from chain | CONFIRMED: crystals bought across the sold-out boundary resolve to nothing, silently |
| B-7 | Low | spin denomination copy | quote may be USDG (`round.json` quoteAssets) | `CrystalCauldronGame.tsx:602,616,629` hard-code `Ξ` for the stake pills, the "volume" figure and the CTA | CONFIRMED wording |
| — | OK | per-NFT floor + redemption units | floor is denominated in the LIVE 18-dec creature token | `useCollectionFloor.ts:10,137` `parseEther`/`formatEther`, `CollectionFloorPanel.tsx:11,129` price it in `$ticker` | NO MISMATCH |
| — | OK | treasury envelope governance | `propose(address,uint16)` | `useTreasuryRotation.ts:81` ABI, `:430-434` `args:[quote, maxTotalBps]` | NO MISMATCH |
| — | OK | brew governance, 3 `propose` overloads | — | `config/cauldron.ts:309,320,337`; `useCauldronMachine.ts:397-403` picks by capability probe, viem disambiguates on arg count | NO MISMATCH |

## 2. The specific questions

### 2.1 The gacha odds promise (priority 1)

**What `resolveTickets` now does.** First time a batch's blockhash has aged out,
`GachaLib.sol:125-128` marks the hashed re-anchor slot, re-stamps `commitBlock`
and `break`s (so the whole FIFO queue stalls behind it until the next call).
A SECOND expiry takes `:135` `expired = true`, and then `:150`
`bool win = (forced || (!expired && roll < odds)) && minted < max;` — the
crystal cannot win on its roll. Pity still pays (`forced` is independent of
`expired`), and `:182` `if (!expired && roll >= odds && minted < max) missStreak[player] += 1;`
means a forfeited crystal buys NO pity credit.

**Displayed probability vs rolled probability.** VERIFIED on the live r44
deployment (Sepolia, addresses from `indexer/deployments/round.json`):

- `gachaRouter.oracle()` → `0x0000…0000`
- `gachaRouter.playInCurveUnits(9e16)` → `90000000000000000` (identity)
- `hook.oddsForPlay(9e16)` → `1620` (16.20 %)

So today the UI's raw-wei argument and the chain's curve-unit argument are the
same number and the displayed 16 % is honest. That equality is an accident of an
UNSET oracle. `CauldronGachaRouter.setOracle` (`:99`, `onlyOwner`) is a one-tx
action, and it is exactly what a USDG generation needs for correct sizing
(`:128-135` documents the R-05 bug that motivated it). The moment it is armed,
the chain rolls `oddsForPlay(playWei * usdPerRawUnit / 1e18)` while
`CrystalCauldronGame.tsx:202` still asks `oddsForPlay(parseEther(stake*loops))`.
The router exposes `playInCurveUnits` publicly and its own comment says it is
there "so the odds are the same odds the chain will roll" (`:117-119`) — and no
frontend file calls it. Direction: the display UNDERSTATES (safe for funds,
wrong for the promise). **Verdict: the odds display is correct only while
`oracle == 0`; it is one owner transaction away from lying, and the fix is to
route `spinWei` through `playInCurveUnits`.**

**Copy about re-rolls / expiry.** The only "re-roll" text is a source comment
(`CrystalCauldronGame.tsx:27-28`, not rendered). No rendered string mentions
expiry, re-anchoring, a 256-block window, or the possibility of losing a
crystal. The user-visible model is `:519` / `:571`: "forged — reveal on your
next spin", which reads as a crystal that waits indefinitely and safely.

**What a twice-expired player sees.** `GachaLib.sol:183` emits the SAME
`TicketLost(player, bi)` as an ordinary miss, so neither the receipt parser
(`CrystalCauldronGame.tsx:280`) nor the indexer can distinguish a forfeit from a
fair loss. The player sees "N fizzled" (`:565`) and a pity meter that did not
move (correct — `:182` withheld the credit), with no explanation for either.
Reachability needs no attacker: resolution only happens when someone calls
`play`/`playChurn` (`CauldronGachaRouter.sol:329,363`) or the permissionless
`hook.resolveTickets` (`CauldronHook.sol:2482`), and `scripts/keeper.sh` calls
NEITHER (its only registry action is `materializeLegacyReserve`, `:58-65`). Two
play events more than ~256 blocks apart — roughly 51 minutes of quiet on a
12-second chain — is the ordinary state of a testnet round. **This is the
finding I would block on: the cap itself is right, its consequence is
undisclosed, and nothing is paid to prevent it.**

### 2.2 Supply conservation as displayed

`nftMinted` is the indexer's `/collections` `totalMinted` (`useCauldronMachine.ts:146,163`),
`nftMax` is an on-chain `maxSupply` read (`indexer/src/api/index.ts:374`). The
forfeit path mints nothing, so it cannot inflate supply — supply conservation
holds. The divergence it creates is on the CRYSTAL side: a forfeited crystal is
decremented from `pendingOf` / `outstandingCrystals` (`GachaLib.sol:151-153`)
with no mint and no pity, and there is no surface anywhere that reports
outstanding-vs-forfeited. Separately (B-6) the `soldOut` gate is a lagging
indexer number while the contract's `minted < max` test is live, so spins across
the boundary consume crystals for nothing.

### 2.3 The relaunch promise

Contract gate: `CauldronRegistry.sol:821` `relaunch()`, `:837`
`if (block.timestamp < lastSummonAt + minLifetime) revert TooYoung();`,
`:1030` `if (totalETH == 0) revert NoLiquidityToSeed();` — placed deliberately
on the safe side of `governor.markConsumed` (`:1031`) so a short rebirth is
retryable, which is the correct "runs forever" shape.

The new peek-before-pull (`PoolOps.sol:1195-1211`, `_pullAsset` `:1224-1226`,
`_pullEth` `:1243-1245`) is a strict improvement on-chain: a branch that would
fall short no longer strips the hook's reserve. Its user-facing consequence is
that a sub-floor reserve now produces a clean `NoLiquidityToSeed` revert, and
`MIN_SEED_UNITS` is decimal-blind (`:225`, acknowledged at `:1158-1174`): dust in
ether, but **673.94 tokens on a 6-decimal quote**.

The UI does not model this at all. `RelaunchPanel` (`TheCauldron.tsx:1529-1547`)
gates only on `hasWinner && !tooYoung`; funding is not a factor in the button.
The funding number it does show comes from `indexer/src/api/index.ts:383`,
`relaunchEth = lpEth + formatEther(relaunchETH())` — the per-ASSET reserve
(`relaunchAsset`, the very reserve `PoolOps.sol:1197/1209` seeds from) is never
read, and `vaultEth` (`:385`) is a native `getBalance`. So on a rotated
generation the "available for the next launch" figure is structurally
incomplete, and the button is offered for a rebirth that may revert.
**Verdict: the permissionless-forever promise holds in the contract; the UI's
affordance is under-gated (offers an unfundable relaunch) and its funding
readout is native-only.**

### 2.4 Quote rotation end to end — every number that must follow a 6-dec quote

| number | source | follows the quote? |
|---|---|---|
| spin payment / approval | `useCauldronSwap.ts:376-414` | YES — zap, bounded `approve(router, spend)` at `:409`, `quoteIn` non-zero, `value: 0n` |
| spin slippage floor | `CrystalCauldronGame.tsx:191` `formatUnits(quoteExpected, quoteDecimals)`, `useCauldronSwap.ts:401` `scaleFloor` | YES (this is the 6-dec bug already fixed this run) |
| **spin ODDS argument** | `CrystalCauldronGame.tsx:162,202` | **NO** — raw `parseEther`, never `playInCurveUnits` (B-2) |
| spin stake / volume / CTA labels | `CrystalCauldronGame.tsx:602,616,629` | **NO** — hard `Ξ` (B-7) |
| **relaunch reserve readout** | `indexer/src/api/index.ts:383,385` | **NO** — `relaunchETH` + `formatEther` only, no `relaunchAsset` (B-3) |
| death threshold | `indexer/src/api/index.ts:381` `formatEther(deathThreshold)` + `TheCauldron.tsx:855` "Ξ/24h" | **NO** — quote-denominated on chain, printed as ether |
| per-NFT floor / redemption | `useCollectionFloor.ts:10,137`; `CollectionFloorPanel.tsx:129` | YES — floor is in the 18-dec creature token by construction |
| buyback buffer | `useCollectionFloor.ts:83-85`, rendered only as `bufferPct` (`CollectionFloorPanel.tsx:113-117`) | YES by accident — a ratio is decimal-invariant; the raw `buffer` bigint is never rendered |
| treasury rotation panel | `useTreasuryRotation.ts:292-340` (legs, envelope, `minOut` from `quoteSlice`) | YES — `minOut` is quoted from the venue, not typed |

Siblings of the already-fixed 6-dec perp bug in my scope: **B-2 (odds argument)**
and **B-3 (relaunch reserve)**, plus the cosmetic `Ξ` labels on the spin console
and the death threshold.

### 2.5 Dividends and floors

Claim surface reads `owed`, `owedAsset`, `pendingToken`, and writes `claimMany`,
`claimTokens`, `withdrawOwedToken`, `withdrawOwed` (`useMiFrensDividend.ts:293,154,165,328,360,371,414`),
with per-asset `decimals()` fetched at `:153` — i.e. the multi-asset dividend
path is decimal-aware, unlike the gacha/relaunch paths above. Floors: see 2.4.
I did NOT read the dividend contract's own guards, so whether the UI can offer a
claim the contract refuses is **NOT VERIFIED** (see §4).

### 2.6 Governance

`CauldronGovernor`: three `propose` overloads declared (`config/cauldron.ts:309,320,337`),
including the 9-argument legacy form; `useCauldronMachine.ts:397-403` chooses
between them from a live capability probe and viem disambiguates by argument
count. `TreasuryGovernor`: `useTreasuryRotation.ts:81` declares
`propose(address,uint16)` and `:430-434` sends `[quote, maxTotalBps]` — matches.
`vote(uint256,bool)` and `execute(uint256)` at `:440,:447`. No mismatch found.

## 3. Verdict (≤200 words)

The three subsystems are structurally sound where they are on-chain: the
one-re-anchor cap is the right shape (it closes a grind without ever wedging the
queue), the peek-before-pull makes a short rebirth retryable instead of
value-destroying, and governance signatures line up on both governors. What is
incoherent is the surface. Two of the three headline user numbers — the win
chance and the rebirth funding — are computed in units the contract stopped
using once a generation can be quoted in something other than ether, and the
single most consequential new behaviour, a crystal that can be forfeited, has no
representation anywhere: not in copy, not in an event distinguishable from a
fair loss, not in a keeper that would prevent it.

**The incentive that breaks first is crystal resolution.** Nobody is paid to
call `resolveTickets`; it rides free on the next trade. Exactly when the machine
is quiet — the state the whole volume-or-death design is meant to punish — plays
fall more than 256 blocks apart, and the mechanism that was meant to stop a
grinder starts eating honest players' crystals instead, with the pity counter
correctly refusing to compensate them.

## 4. Not verified / not reached

- No PoC was executed for the forfeit path; B-1's two-expiry sequence is DERIVED
  from `GachaLib.sol:124-135` plus the absence of any resolver in `keeper.sh`.
- Dividend CONTRACT-side guards (`MiFrensDividend` / `CollectionLedger`) were not
  opened; §2.5 is one-sided (frontend only).
- `MiFrensGenesis.sol`, `CauldronCollection.sol`, `RedemptionExt.sol`,
  `CauldronSeeder.sol`, `QuoteRotator.sol` and `CauldronBase.sol` were not read;
  presale (`useMiFrensPresale.ts`) and `useGenesisBonus.ts` were not reached.
- Indexer HANDLERS (`indexer/src/index.ts`) were not read — only the API layer —
  so "is `TicketLost` indexed with a forfeit flag" is answered from the contract
  side (it cannot be: one event, no flag) rather than from the schema.
- B-2's post-arming magnitude is reasoned from `usdPerRawUnit` semantics, not
  measured: the live oracle is unset, so there was nothing to measure.
