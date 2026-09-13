# 09 — Frontend

How the web app talks to the chain.

The app is React 19 with wagmi/viem. It has two data paths. Writes go to the
chain through the user's wallet. Reads come almost entirely from the Ponder
indexer, not from RPC. This document lists every write path, then the read
paths, then where addresses and chain config live.

Every claim below cites a file and line that was read. Where the code and a
comment disagree, the code is described and the disagreement is recorded.

---

## 1. Where addresses and chain config live

There is one deployment manifest: `indexer/deployments/round.json`.

| Fact | Source |
|---|---|
| Contract addresses | `indexer/deployments/round.json:12-31` |
| Chain id | `indexer/deployments/round.json:5` (`11155111`, Sepolia) |
| Indexer base URL | `indexer/deployments/round.json:6` |
| Deploy / perp / indexer start blocks | `indexer/deployments/round.json:7-11` |
| Quote assets shown in the UI | `indexer/deployments/round.json:35-60` |

The frontend imports that file directly (`src/config/cauldron.ts:10`,
`src/config/perp.ts:6`, `src/config/quotes.ts:2`). The indexer imports the same
file (`indexer/ponder.config.ts:17`). The file physically lives inside
`indexer/` because `railway up` only uploads that directory, and the frontend
reaches across the tree for it (`src/config/cauldron.ts:3-9`).

There is deliberately **no environment override** for the indexer URL
(`src/config/cauldron.ts:39-46`) or for the perp addresses
(`src/config/perp.ts:15-18`). An env var that disagreed with the manifest would
point the UI at a different deployment than the indexer reports on, which
surfaces as empty panels rather than an error.

Chain selection is a single switch. `VITE_NETWORK` chooses testnet (Sepolia) or
mainnet (Robinhood Chain), and `ACTIVE_CHAIN_ID` flows into `CAULDRON.chainId`
and `PERP.chainId` (`src/config/chains.ts:85-90`, `src/config/cauldron.ts:13`,
`src/config/perp.ts:14`). Sepolia RPC endpoints are a viem `fallback` list;
`VITE_SEPOLIA_RPC_URL` accepts a comma-separated list and its entries are tried
first (`src/config/chains.ts:63-71`). The Robinhood chain id defaults to `4663`
and is overridable (`src/config/chains.ts:19-20`); the repo's own note says
sources have shown 4663 for mainnet and 46646 for testnet and that the value
should be confirmed (`src/config/chains.ts:9-12`). **Unverified:** which of
those two ids is correct.

Two addresses are read from the manifest rather than from the chain because the
contracts cannot expose them: `treasuryGovernor` is `internal` on
`CauldronBase` and the registry has no byte budget for a getter
(`src/config/cauldron.ts:23-26`, `src/hooks/useTreasuryRotation.ts:206-210`).

---

## 2. Write paths

Every write goes through wagmi's `useWriteContract` → `writeContractAsync`. All
of them first switch the wallet to `CAULDRON.chainId` / `PERP.chainId` if it is
on a different network.

### 2.1 Table

Selectors were computed with `cast sig` against the signatures in the ABIs the
app actually encodes.

| Write path | Contract function | Selector | Asset sent | `minOut` source |
|---|---|---|---|---|
| Buy the iteration token | `CauldronGachaRouter.play(uint256,uint256,uint256,uint256,uint256)` | `0x7fe7c4b6` | native ETH as `value` | caller argument; the UI passes **`0n`** (`src/components/cauldron/SwapWidget.tsx:96`) |
| Sell the iteration token | `CauldronGachaRouter.play(...)` | `0x7fe7c4b6` | none (`value: 0n`), token pulled by `transferFrom` | caller argument; the UI passes **`0n`** (`src/components/cauldron/SwapWidget.tsx:103`) |
| Spin (churn volume) | `CauldronGachaRouter.playChurn(uint256,uint256,uint256)` | `0xc4ffce88` | native ETH as `value` | none — no slippage argument exists (`src/hooks/useCauldronSwap.ts:77-84`) |
| Open banked crystals | `CauldronGachaRouter.openReady(uint256)` | `0x96c8709f` | none | n/a |
| Approve router to sell | `ERC20.approve(address,uint256)` | `0x095ea7b3` | none | n/a — `maxUint256` (`src/hooks/useCauldronSwap.ts:159-162`) |
| Reveal one crystal | `CauldronCollection.reveal(uint256)` | `0xc2ca0ac5` | none | n/a |
| Reveal many crystals | `CauldronCollection.revealBatch(uint256[])` | `0x75ef961f` | none | n/a — chunked at 50 per tx (`src/hooks/useCauldronSwap.ts:121-128`) |
| Burn a creature to the vault | `vault.redeem(uint256)` | `0xdb006a75` | none | n/a (`src/components/wizards/CreatureModal.tsx:109-110`) |
| Open a long | `PerpEngine.openLong(uint8,uint256,uint256,uint256)` | `0x79588b97` | native ETH as `value`, equal to the 4th arg | simulated-free: `expected × (1 − 100 bps)` where expected = `collateral × (1 − openFeeBps) × leverage / spotPrice` (`src/hooks/usePerpEngine.ts:204-210`, floor at `:46-49`) |
| Open a short | `PerpEngine.openShort(uint8,uint256,uint256,uint256)` | `0x9e4a4754` | native ETH as `value`, equal to the 4th arg | `collateral × (1 − openFeeBps) × leverage`, then `× (1 − 100 bps)` (`src/hooks/usePerpEngine.ts:220-225`) |
| Close a position | `PerpEngine.close(uint256,uint256)` | `0x596c8976` | none | `expectedCloseEth(p, spotPrice) × (1 − 100 bps)`; `0` only when there is no price (`src/hooks/usePerpEngine.ts:237-243`, `src/components/cauldron/PerpPanel.tsx:504-508`) |
| Close all positions | `PerpEngine.close(...)`, one tx each | `0x596c8976` | none | same as close, per position (`src/hooks/usePerpEngine.ts:247-259`) |
| Claim Liquidatoor badges | `PerpEngine.claimLiquidatorBadges(uint256)` | `0x81160a89` | none | n/a (`src/components/wizards/LiquidatoorBadges.tsx:124-127`) |
| Stake ETH in the PLV vault | `PerpVault.depositEth()` | `0x439370b1` | native ETH as `value` | n/a |
| Stake the quote asset | `PerpVault.deposit(uint256)` | `0xb6b55f25` | native if the quote is ETH, else `0` and an ERC20 pull (`src/hooks/usePerpVault.ts:127-132`) | n/a |
| Stake the iteration token | `PerpVault.depositToken(uint256)` | `0x6215be77` | none — ERC20 pull | n/a |
| Approve the vault (quote) | `ERC20.approve` | `0x095ea7b3` | none | `maxUint256` (`src/hooks/usePerpVault.ts:120-124`) |
| Approve the vault (token) | `ERC20.approve` | `0x095ea7b3` | none | `maxUint256` (`src/hooks/usePerpVault.ts:136-140`) |
| Unstake ETH shares | `PerpVault.withdrawEth(uint256)` | `0xc311d049` | none | n/a — by **shares**, not amount (`src/components/cauldron/StakePanel.tsx:119-128`) |
| Unstake token shares | `PerpVault.withdrawToken(uint256)` | `0x50baa622` | none | n/a |
| Claim queued ETH | `PerpVault.claimPendingEth()` | `0x971557d1` | none | n/a |
| Claim queued token | `PerpVault.claimPendingToken()` | `0x51c724af` | none | n/a |
| Claim token-side ETH yield | `PerpVault.claimTokYield()` | `0x038a5ce7` | none | n/a |
| Mint the genesis presale | `MiFrensGenesis.mint(uint256)` | `0xa0712d68` | native ETH, `PRICE() × quantity`, price re-read on every mint (`src/hooks/useMiFrensPresale.ts:206-220`) | n/a — `simulateContract` runs first (`:226-236`) |
| Relaunch the machine | `CauldronRegistry.relaunch()` | `0x7770e80c` | none | n/a |
| Vote for a brew proposal | `CauldronGovernor.vote(uint256)` | `0x0121b93f` | none | n/a |
| Propose the next brew | `CauldronGovernor.propose(string,string,uint8,string,address,string,string,uint256,uint256)` | `0xd4bb3bb4` | none | n/a |
| …with a quote asset | `CauldronGovernor.propose(...,address)` | `0x1e8901ff` | none | n/a — arity probed at runtime (`src/hooks/useCauldronMachine.ts:348-356`) |
| Migrate a dead gen's tokens | `CauldronRegistry.claimByBurn(uint256,uint256)` | `0x85f82cc9` | none | n/a |
| Recycle a genesis fren | `CauldronRegistry.redeemOgFren(uint256)` | `0x97b53762` | none | n/a (`src/hooks/useGenesisBonus.ts:127-130`, `src/components/wizards/FrenDetailModal.tsx:152-154`) |
| Recycle a dead collection NFT | `CauldronRegistry.recycleCollectionNFT(uint256,uint256)` | `0xa74aa2d0` | none | n/a |
| Buy a treasury-held NFT (2×) | `CauldronRegistry.buyCollectionNFT(uint256,uint256)` | `0x5af0f5a4` | none | n/a |
| Claim genesis dividends | `MiFrensDividend.claimMany(uint256[])` | `0x925489a8` | none | n/a |
| Cast the spell | `MiFrensDividend.castMany(uint256[])` | `0x449518c5` | none | n/a |
| Withdraw settled dividend | `MiFrensDividend.withdrawOwed()` | `0x39a72c5c` | none | n/a |
| Transfer an NFT | `ERC721.safeTransferFrom(address,address,uint256)` | `0x42842e0e` | none | n/a |
| Rotate one treasury slice | `CauldronRegistry.rotateSliceFrom(uint8,uint16,uint256,(address,address,uint24,int24,address))` | `0x28e60cba` | none | **simulated**: `rotateSliceFrom` is `eth_call`ed with `minOut = 0`, and the returned `moved` is scaled by `1 − maxSlip` (`src/hooks/useTreasuryRotation.ts:300-316`, `src/components/cauldron/TreasuryRotation.tsx:285-293`) |
| Propose a rotation envelope | `TreasuryGovernor.propose(address,uint16)` | `0x636f04a8` | none | n/a |
| Vote on an envelope | `TreasuryGovernor.vote(uint256,bool)` | `0xc9d27afe` | none | n/a |
| Execute an envelope | `TreasuryGovernor.execute(uint256)` | `0xfe0d94c1` | none | n/a |

38 write paths.

### 2.2 Asset handling: native vs ERC20

The buy leg supplies the quote side as native `value` and passes `quoteIn = 0`
(`src/hooks/useCauldronSwap.ts:52-62`). That is correct only while the
generation trades against ETH. On an ERC20-quoted generation the router reverts
`ErcQuoteTakesNoValue`; a USDG-denominated buy would need an approve plus a
non-zero `quoteIn` with no value, and **the UI does not implement that path**
(comment and code agree, `src/hooks/useCauldronSwap.ts:55-59`).

The sell leg supplies no buy side at all, so it is valid on both native and
ERC20 generations. The proceeds come back in whatever the generation trades, so
the parameter named `minEthOut` is really a minimum *quote* out
(`src/hooks/useCauldronSwap.ts:185-189`).

The vault's quote-side deposit is the one path that branches: it sends `value =
raw` when the quote is native and `value = 0` with an ERC20 pull otherwise
(`src/hooks/usePerpVault.ts:127-132`).

Perp collateral is native ETH only. `openLong`/`openShort` send `value =
parseEther(collateralEth)` and repeat the same number as the 4th argument
(`src/hooks/usePerpEngine.ts:204-209`, `:220-224`); `src/config/perp.ts:50-53`
records that the 4th argument is the collateral amount and must equal the ETH
sent on a native book.

### 2.3 Decimals

Amounts entered as human numbers are converted with `parseEther(x.toFixed(18))`
— the swap buy (`src/hooks/useCauldronSwap.ts:46`), the sell
(`:180`), the spin (`:83`), perp collateral
(`src/hooks/usePerpEngine.ts:204`) and the ETH vault deposit
(`src/hooks/usePerpVault.ts:96`).

Two places correct for the float loss that causes:

- **Sell** clamps `tokenInWei` to the wallet's exact raw balance when the
  caller supplies it, so "MAX" cannot compute more than you hold and revert
  `transferFrom` (`src/hooks/useCauldronSwap.ts:180-181`, rationale at
  `:167-172`).
- **Unstake** withdraws by *shares* using the raw share balance rather than by
  amount, so a full exit leaves no dust (`src/components/cauldron/StakePanel.tsx:119-128`).

Quote-asset decimals are display-only; `src/config/quotes.ts:23-25` says pool
maths takes raw amounts, and the manifest carries the decimals for rendering
(`indexer/deployments/round.json:40,48,56`). The rotation panel formats the
signed `minOut` with `formatUnits(..., destMeta.decimals)`
(`src/components/cauldron/TreasuryRotation.tsx:421`).

### 2.4 Slippage, stated honestly

| Path | Floor signed |
|---|---|
| Spot buy / sell | `0` — no protection (`src/components/cauldron/SwapWidget.tsx:96,103`) |
| Spin | no parameter exists |
| Perp open / close | 100 bps below an expected value computed from the spot price (`src/config/perp.ts:34`) |
| Treasury rotation | user-chosen bps below a **simulated** output (`src/hooks/useTreasuryRotation.ts:300-316`) |

The perp and rotation floors were introduced today (commits `6a275c5`,
`50839dc`). The spot swap path was not changed and still signs `0n`. The
router's own `minTokenOut` / `minQuoteOut` parameters exist
(`src/config/cauldron.ts:314-325`) and the hook accepts them
(`src/hooks/useCauldronSwap.ts:40,174`) — only the widget does not supply them.

### 2.5 Approvals

Three approval flows exist, all `approve(spender, maxUint256)`:

1. **Router**, before any sell — `approveToken(token)` targets
   `CAULDRON.gachaRouter` (`src/hooks/useCauldronSwap.ts:159-162`). The widget
   calls it and returns, so the user sells on a second click
   (`src/components/cauldron/SwapWidget.tsx:100`).
2. **Vault, quote side** — allowance is read with `useReadContract` and
   compared to the amount before offering the approve
   (`src/hooks/usePerpVault.ts:113-124`).
3. **Vault, token side** — same shape (`src/hooks/usePerpVault.ts:135-140`).

Perps need no approval: collateral is native.

### 2.6 Gas overrides

Two paths force a gas limit because the wallet's estimate is taken while the
liquidation target is still healthy and cannot foresee the nested swaps:
`LIQ_SWAP_GAS = 3_000_000` on buy and sell
(`src/hooks/useCauldronSwap.ts:14,61,190`) and `LIQ_OPEN_GAS = 3_000_000` on a
hinted open (`src/hooks/usePerpEngine.ts:42,209,224`).

### 2.7 Dead arguments

`useCauldronSwap.buy` and `.sell` accept a `liqHint` and **discard it**
(`src/hooks/useCauldronSwap.ts:47-48,182`). The hook auto-liquidates on every
swap without a hint, and the router's `playLiq` path is not called. The
parameter survives in the signature and in `SwapWidget.tsx:96,103`, which is
confusing but not a defect.

---

## 3. Read paths

### 3.1 From the indexer

`CAULDRON_INDEXER` is the manifest's `indexerUrl` with trailing slashes stripped
(`src/config/cauldron.ts:46`). Twenty-one modules read it (all files matching
`CAULDRON_INDEXER` under `src/`). The endpoints the app requests:

| Endpoint | Consumer |
|---|---|
| `/freshness` | `src/hooks/useIndexerHealth.ts:38` |
| `/candles/:generation` | `src/hooks/useCandles.ts` |
| `/recent/:generation` | `src/hooks/useSwapTape.ts`, `src/hooks/useActivityFeed.ts` |
| `/cauldron` | `src/hooks/useCauldronMachine.ts` |
| `/presale` | `src/hooks/useMiFrensPresale.ts` |
| `/treasury` | `src/hooks/useLpComposition.ts` |
| `/liquidity` | `src/components/cauldron/LiquidityDial.tsx` |
| `/floor`, `/collection-floors` | `src/hooks/useCollectionFloor.ts` |
| `/collections`, `/collection/:address/nfts`, `/nfts/:owner` | `src/lib/cauldronIndexer.ts`, `src/components/wizards/ForgedCreatures.tsx` |
| `/perp-heatmap/:generation` | `src/hooks/usePerpEngine.ts:112`, `src/hooks/usePerpHeatmap.ts` |
| `/perp-positions/:trader` | `src/hooks/usePerpEngine.ts:151` |
| `/perp-rekt/:trader`, `/perp-kills/:wallet`, `/perp-liquidators` | `src/hooks/usePerpRekt.ts`, `src/components/wizards/LiquidatoorBadges.tsx` |
| `/perp-vault`, `/perp-vault/:user` | `src/hooks/usePerpVault.ts` |
| `/seeding` | `src/hooks/useSeedProgress.ts` |
| `/proposals` | `src/hooks/useCauldronMachine.ts` |
| `/iterations`, `/enchants/:owner` | `src/lib/cauldronIndexer.ts` |

The perp panel is the strongest statement of the design: "ALL READS COME FROM
PONDER … The browser makes NO read RPC calls"
(`src/hooks/usePerpEngine.ts:52-57`). Confirmation of a perp action is detected
by a position appearing in or leaving the indexed list, not by a receipt
(`src/hooks/usePerpEngine.ts:75-89`). One RPC receipt read is kept so a
submitted-but-reverted transaction surfaces as an error rather than a timeout
(`:66-69`).

Polling intervals: engine stats every 4 s and paused while the tab is hidden
(`src/hooks/usePerpEngine.ts:129-133`); positions every 1.2 s while an action is
pending, 3 s at rest (`:164`); health every 25 s
(`src/hooks/useIndexerHealth.ts:75-77`); machine state every 15 s
(`src/hooks/useCauldronMachine.ts:288`); rotation envelope every 30 s
(`src/hooks/useTreasuryRotation.ts:270`).

`src/lib/cauldronIndexer.ts:32-38` coalesces concurrent identical
`/nfts/:owner` requests; it is a dedupe, not a cache.

### 3.2 From RPC

Direct chain reads are the exception:

- The registry lifecycle and the rotation envelope, via `usePublicClient`
  (`src/hooks/useTreasuryRotation.ts:216-247`).
- Presale `PRICE()` before every mint, and a `simulateContract` dry run
  (`src/hooks/useMiFrensPresale.ts:217,228-230`).
- The governor arity probe (`src/hooks/useCauldronMachine.ts:350-354`).
- `rotateSliceFrom` simulated for the rotation quote
  (`src/hooks/useTreasuryRotation.ts:304-308`).
- Receipts: `waitForTransactionReceipt` in the machine
  (`src/hooks/useCauldronMachine.ts:302-307`), the floor hooks
  (`src/hooks/useCollectionFloor.ts:116,132`), the genesis redeem loop
  (`src/hooks/useGenesisBonus.ts:131`) and the NFT modals
  (`src/components/wizards/FrenDetailModal.tsx:132,155`).
- Vault allowances and balances (`src/hooks/usePerpVault.ts:108-117`).
- `badgesOwed` on the engine (`src/config/perp.ts:63`, read in
  `src/components/wizards/LiquidatoorBadges.tsx`).

### 3.3 What the UI shows when data is stale

The indexer's `/freshness` response drives one app-wide banner.
`useIndexerHealth` maps it to four states (`src/hooks/useIndexerHealth.ts:5`):

| State | Trigger | Message |
|---|---|---|
| `stale` | the indexed pool set does not contain the chain's current pool | "indexing a different pool — trades will not appear" (`:56-58`) |
| `syncing` | `indexedGen < chainGen`, or `ok === false` | "catching up to generation N" / "syncing (reason)" (`:60-67`) |
| `down` | non-2xx, or the fetch throws | "indexer returned N" / "cannot reach the indexer" (`:39-41,70-72`) |
| `ok` | none of the above | banner hidden |

`IndexerHealthBanner` is mounted in the app shell so it appears on every route
(`src/components/shared/IndexerHealthBanner.tsx:25-27`). Its header records why:
nineteen modules read the indexer and only one consulted the health signal, so
a diverged indexer rendered "a confident, wrong, empty page" — a sold-out
presale displayed 0 / 1111 (`:6-19`).

Individual hooks do **not** error on a stale indexer. They keep the last value
(`src/hooks/usePerpEngine.ts:124,160`) or return empty. `PerpStats.stale` is
carried through from the heatmap response and shown in the perp panel
(`src/hooks/usePerpEngine.ts:20,122`).

If the RPC path is the one that fails, `waitForReceipt` raises explicitly rather
than hanging, which catches the "wallet was on the wrong network" trap
(`src/hooks/useCauldronMachine.ts:297-306`).

---

## 4. Doc/code disagreements found

1. **`useCauldronSwap` still takes a `liqHint` it never uses.** The parameter is
   accepted and discarded (`src/hooks/useCauldronSwap.ts:47-48,182`) while
   `SwapWidget.tsx:96,103` computes and passes one. The comment says so; the
   signature does not.
2. **The spot swap path signs `minOut = 0`.** The hook documents `minOut` as
   "the caller's slippage floor (0 accepts any)"
   (`src/hooks/useCauldronSwap.ts:25`) and the widget always passes `0n`. There
   is no slippage control in the swap UI.
3. **`PERP_SLIPPAGE_BPS` is a single global constant** (`src/config/perp.ts:34`)
   with no UI control, so "1%" is not user-adjustable on perps even though the
   rotation panel does expose a slider
   (`src/components/cauldron/TreasuryRotation.tsx:163,399-402`).

---

## Verification

- `git rev-parse --short HEAD` → `20d6de2`
- Selectors computed with `cast sig` (foundry, nightly) against the signatures
  encoded by the app's ABIs.
- Disagreements found: the three listed in section 4.
- Not verified: the correct Robinhood Chain id (4663 vs 46646); the ERC20-quote
  buy path has no implementation to inspect.
