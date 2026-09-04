# vfat.tools listing readiness — MiFrens / Cauldron

Goal: be able to submit a mergeable PR to https://github.com/vfat-io/vfat-tools the
day MiFrens deploys to a mainnet vfat indexes. This is a **pre-flight checklist**,
not a submission — vfat is mainnet-only and everything is currently on Sepolia
(chainId 11155111), so nothing here is listable yet.

## DECISION (best-for-vfat, locked)
Conform to vfat's **standard Synthetix `StakingRewards` loader** via a read-adapter
— NOT a bespoke page. vfat merges standard-shape pages fastest (cryptex.js pattern:
`loadSynthetixPoolInfo` + `loadMultipleSynthetixPools`) and the numbers are accurate.
The fork-ready submission bundle is staged in **`marketing/vfat/`** (`mifrens.js`,
`index.ejs`, `ADAPTER_SPEC.md`, `SUBMIT.md`). The one on-chain thing to build before
mainnet is the **PLV→StakingRewards adapter** (two instances: ETH side + token side)
that surfaces the PLV's real fee yield as a **trailing `rewardRate`** — see
`marketing/vfat/ADAPTER_SPEC.md`.

Contact for the maintainer: `vfat0` on Twitter/Telegram. Paid fast-track review
exists via MCN Ventures (https://mcn.ventures/review) — optional.

---

## Hard gates (a PR is rejected without these)

- [ ] **Mainnet deployment.** vfat supports 60+ mainnets (Ethereum, Base, Arbitrum,
      Optimism, BNB, Polygon, Sonic, Unichain, …) but **no testnets**. Sepolia will
      never be indexed. Pick the launch chain first — it decides which index file
      the PR touches (ETH → `src/static/js/all.js`; others → e.g. `base.js`).
- [ ] **All contracts verified** on that chain's explorer (Etherscan/Basescan/etc.).
      vfat and its reviewers read verified source; unverified = auto-reject.
- [ ] **Real, non-zero TVL** in the staking/reward contract. vfat is a farm
      dashboard — an empty pool gets no attention and may be pruned.

## The architecture problem (decide this BEFORE mainnet)

vfat's loaders only understand **two contract shapes**. MiFrens is Uniswap-v4
hook-native with in-hook dividends, a perp engine, PLV staking and gacha — none of
which map onto either shape out of the box. Pick one path:

### Reality: PLV is a REAL-YIELD vault, not a fixed-emission farm
This is the important thing. Read `contracts/solidity/cauldron/PerpVault.sol`:

- **ETH side** — an **auto-compounding ERC-4626-style vault**. Perp fees (open fee +
  funding + liquidation penalties) accrue *inside* `engine.totalEth()`, so
  assets-per-share rises. There is **no reward token, no `earned()`, no
  `rewardRate()`** — yield only shows up as share-price growth.
- **TOKEN side** — a **MasterChef-style accumulator that pays ETH** (real short-side
  fees) via `accEthPerTokShare` / `pendingTokYield(user)`. Per-user claimable is
  clean, but there is still **no emission rate** — the reward flow is whatever
  trading produced.

Consequence: both of vfat's stock loaders (`loadSynthetixPool`, `loadChefContract`)
assume a **fixed forward emission rate** to project APR. A fee-revenue vault has
none, so APR must be **realized / trailing** (e.g. last-7d fee flow annualized, or
share-price growth over a window). vfat happily lists real-yield protocols
(GMX/GLP, Gains) — but they're **custom pages**, not stock-loader pages. So for the
PLV, **Path B is the realistic path**, optionally with the Path-A adapter trick to
keep the JS thin.

### Path A — Wrap it as a standard interface (thin JS, needs an adapter)
Two ways to reuse a stock loader despite the no-emission-rate problem:

- **Synthetix `StakingRewards` adapter** — deploy an adapter that presents
  `stakingToken()`, `rewardsToken()`, `rewardRate()`, `totalSupply()`,
  `balanceOf(address)`, `earned(address)`, `periodFinish()` over the real PLV state,
  and feed it a **trailing `rewardRate`** by recording realized fee flow into
  fixed epochs (à la Synthetix `notifyRewardAmount`, one call per epoch). Then vfat's
  `loadSynthetixPool(...)` "just works" and shows a realized APR. More infra, but
  plugs straight into the stock loader.
- **MasterChef adapter** — same idea over `poolInfo`/`userInfo`/`pending*`; the token
  side already has `pendingTokYield(user)` as the `pending<Reward>` equivalent.

### Path B — Fully custom page (recommended for the PLV)
A bespoke `mifrens.js` that reads the vault directly and computes **realized** APR.
vfat requires custom/non-standard farms to be submitted **via PR** (issues are
auto-rejected for non-standard farming). You own the math, but it's honest and
matches how vfat lists other real-yield protocols. The loader would:

- **TVL**: `assetsEth()` × ETH-USD  +  `assetsTok()` × token-USD.
- **APR (realized)**: sample a cumulative-yield signal now vs. an earlier point and
  annualize. ETH side → track `pricePerShareEth = (assetsEth()+1)/(ethShares+1e6)`;
  token side → `engine.tokYieldCumulative()` delta over `dt`.
- **Per-user**: `ethPosition(user)`, `tokenPosition(user)`, `pendingTokYield(user)`.
- **Actions**: `depositEth` / `withdrawEth` / `claimPendingEth`, `depositToken` /
  `withdrawToken` / `claimTokYield`.

### View functions to add (view-only; an adapter is fine) to make either path clean
- [ ] `pricePerShareEth()` and `pricePerShareTok()` — one call each for APY tracking.
- [ ] A **cumulative ETH-yield** counter for the ETH side (mirror of the engine's
      `tokYieldCumulative()`) + a `block.timestamp` read, so trailing APR needs no
      off-chain history.
- [ ] `assetsEth()` / `assetsTok()` are already public → use directly for TVL.

## Data points the loader must be able to compute on-chain

For whichever surface you list, the loader needs a live source (contract view or
price oracle) for each:

- [ ] **Staked/deposit token** address + its USD price (must be on a DEX vfat's
      price helper can read, or add it to the price map).
- [ ] **Reward token(s)** address + USD price (GNOME/iteration token — needs a
      mainnet pool with liquidity so a price is derivable).
- [ ] **Total value staked** (`totalSupply()` × staked-token price).
- [ ] **Reward emission rate** (`rewardRate()` or `rewardPerSecond` × allocShare) →
      annualized for APR.
- [ ] **Per-user** staked balance + claimable rewards (`balanceOf` / `earned`).
- [ ] **Claim / stake / unstake** function selectors (vfat renders action buttons).

Note: because iteration tokens **rotate on relaunch** (per-iteration token/vault
addresses change), either (a) list the **genesis/GNOME** surface which is stable, or
(b) point the loader at the **registry** and resolve the current iteration live.
Pin nothing that rotates.

## The PR itself (once the above is true)

Three files, per vfat's README:

1. [ ] `src/views/pages/mifrens/index.ejs` — the view (copy an existing page's ejs).
2. [ ] `src/static/js/mifrens.js` — the loader: `init_ethers()`, read the contract,
       call `loadSynthetixPool(...)` or `loadChefContract(...)`.
3. [ ] Index entry appended (chronologically, at the bottom) to the chain file
       (`all.js` for ETH, else the chain's file). **Do not** touch the front-page index.

Then: fork → branch → `npm install && npm run dev` → verify the page renders real
numbers locally → commit → open PR. Reference the project URL + verified contract
links in the PR body.

## Pre-mainnet TODO summary
1. Decide launch chain (drives everything).
2. Decide Path A vs B — strongly prefer A (adapter contract if needed).
3. Ensure reward + staked tokens have priceable mainnet liquidity.
4. Verify all contracts on the explorer.
5. Draft the 3 files against real mainnet addresses; test locally.
6. Open the PR (optionally MCN fast-track).
