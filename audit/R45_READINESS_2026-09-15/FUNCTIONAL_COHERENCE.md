# Functional coherence (P5) — does the protocol do what it says?

Round-45 deploy-readiness review, 2026-09-15. Merged by the orchestrator from `coherence/COH_A_perps.md`
(perps, liquidation, PLV vault) and `coherence/COH_B_lifecycle_nft_gov.md` (pool lifecycle, NFT/gacha,
governance, treasury). Both agents worked the post-fix tree, so these findings are about the protocol as it
stands after this run's twenty commits, not before.

**No Criticals.** Neither agent found a path where the UI itself loses a user's funds.

## Mismatch table

| id | sev | promise | contract evidence | frontend / indexer evidence | verdict |
|---|---|---|---|---|---|
| A-1 | High | A trader can open a perp on the live quote | `PerpEngine.sol:236` reverts `BadParam()` when the sent value does not match | `PerpPanel` mounted with no quote props (`TheCauldron.tsx:1073-1082`); `usePerpEngine.ts:223,228,239,243` hardcodes `parseEther` and always sends `value`; panel labelled "Ξ ETH" | **Feature dead on a 6-dec generation.** Funds safe. Exact sibling of the crystal-spin bug fixed this run. FIXING |
| A-2 | High | A failed action explains itself | `BadParam` exists on the engine | absent from every ABI, help map and selector map in `src/config/perp.ts` | A-1's revert reaches the user as a hex blob. FIXING |
| A-3 | High | Vault/position balances are shown truthfully | quote-denominated raw amounts | `indexer/src/api/index.ts:1376,:1348` format `ethPosition`/`assetsEth` with `formatEther`; `StakePanel.tsx:257-266` renders them as quote units; `rawToQuoteAmount` exists unused at `indexer/src/quoteUnits.ts:34` | **The units fix landed on the write path only.** Read path off by 10^12 on USDG. FIXING |
| A-4 | Med | Liquidation price is shown truthfully | — | `api/index.ts:1115` `formatEther` on collateral/principal | latent until A-1 is fixed. FIXING |
| A-6 | High | A trader understands their liquidation risk | killing leg is zero-buffer insolvency at a **projected** price, `PerpEngine.sol:1580-1582`, `SLACK_BPS=1500` (`PerpSwapLib.sol:63`) | `PerpPanel.tsx:592` names only the TWAP mark | **Disclosure gap: the UI never says a stranger's swap can close you.** Logged, not fixed — see below |
| B-1 | High | A committed crystal resolves | second expiry commits a loss with no pity credit (`GachaLib.sol:135,150,182`) | UI says only "forged — reveal on your next spin" (`CrystalCauldronGame.tsx:519,571`); `scripts/keeper.sh:58-65` materializes but never resolves | **Fix-induced by this run's `d21cfbe`.** FIXING (keeper resolve + copy) |
| B-2 | High | Displayed odds match the roll | `_playInCurveUnits(playWei)` (`CauldronGachaRouter.sol:326,136-145`) | UI sends raw `parseEther(stake*loops)` to `oddsForPlay` (`CrystalCauldronGame.tsx:162,202`) | Honest **today** only because the live router's `oracle()` is `0x0`; dies on the first `setOracle`, which the USDG path needs. FIXING |
| B-3 | High | The relaunch panel shows whether a rebirth is funded | `PoolOps.sol:1197,1209` seeds from the **per-asset** reserve | `indexer/src/api/index.ts:373,383,385` reads `relaunchETH` with `formatEther`, never `relaunchAsset` | Under a non-native quote the readout can be wrong in both directions. FIXING |
| B-4 | Med | "×N" spins are delivered | — | `useCauldronSwap.ts:421-424,436-439` silently drops `loops` on a router without `playChurn` while the UI charges the stake | Exactly the live r44 condition. Closes when r45 ships a router with the selector |
| B-5 | Med | Pity counter is accurate | `pityThreshold` settable (`CauldronHook.sol:451,2563`) | UI hard-codes 8 | FIXING if budget allows |
| B-6 | Med | "Sold out" is accurate | `GachaLib.sol:150,182` burns the crystal with no pity | `soldOut` from a lagging indexer | logged |
| A-7 | Low | `QueueInsolvent` text describes reality | queue is now units × one index (`beedf49`) | `src/config/perp.ts:239` still describes the per-user write-down | FIXING |
| A-8 / B-7 | Low | — | — | `LiqGasStarved` text and its ~1.05M figure are **correct**; hard `Ξ` labels elsewhere | ok / logged |

## The liquidation promise, end to end

**It holds for the common case, and the conditions where it does not are now named.** The gas bypass is
closed (`CauldronHook.sol:835`) and `_doSweep` scans the whole book (`PerpEngine.sol:1150,1166`). It is
still *not* complete when:
- more than 8 positions are sinkable in one trade (`MAX_LIQ_PER_SWAP`, `PerpEngine.sol:186`);
- gas clears the ~980k gate but not the 420k-per-kill reserve;
- on the post-trade sweep, which stays silent by design;
- after a quote rotation — `_guardOpen` still has no stale-quote check, so the sweep prices off the drained
  pool. **This is the most interesting residual in the report** and is carried as a lead, not a fix.

`LiqGasStarved` disclosure does reach every swap-bearing surface (`SwapWidget.tsx:316`,
`CrystalCauldronGame.tsx:228`), and both pin 8,000,000 gas against the ~1.05M floor.

## The stuck-queue gap — confirmed on all three legs

`settlePendingEth`/`settlePendingToken` exist (`PerpVault.sol:493,730`), have **zero call sites in `src/`**,
and the indexer registers no `PerpVault` contract and no `PerpVaultAbi` at all, so there is no feed of
queued holders to supply the required `address` argument. Both the coherence agent and the off-chain fixer
independently judged that a UI button would be worse than none, because the app cannot choose the argument.
**Accepted remedy: a keeper verb plus honest help text.** Recorded rather than silently closed.

## Verdict (≤ 200 words)

The protocol is structured sensibly and its core promises are implemented. Relaunch keeps its "runs
forever" guarantee — `NoLiquidityToSeed` sits on the safe side of `markConsumed`
(`CauldronRegistry.sol:1030-1031`) — governance matches its UI including all three `propose` overloads, and
floors, dividends and treasury `minOut` are denomination-clean. Liquidation now does what it claims for the
common case.

The coherent weakness is not in the contracts: **it is that the frontend and indexer still assume ETH.**
Every High in this table except A-6 and B-1 is the same defect wearing different clothes — a value parsed or
formatted at 18 decimals, or a `value`-bearing call, on a protocol whose whole thesis is that a generation's
quote can rotate to USDG or xNVDA. The contracts were built for rotation; the read layer was not.

**The incentive that breaks first:** nobody rotates, because the first generation to move to a 6-decimal
quote discovers the perp panel is dead, the balances read 10^12 too small, and the relaunch panel lies about
funding. The de-risking switch the protocol is proudest of is the one its UI cannot survive.

## Not verified

No Foundry or `cast` execution by coherence agent A (A-1 and the A-3/A-4 magnitudes are DERIVED);
`PerpMarkSource.sol` and `PerpStakerOracle.sol` read only through consumers; no PoC for the forfeit path
(DERIVED); agent B did not reach the dividend contract-side guards, `MiFrensGenesis`, `CauldronCollection`,
`RedemptionExt`, `CauldronSeeder`, `QuoteRotator`, `CauldronBase`, the presale and genesis-bonus hooks, or
the indexer event handlers (API layer only).
