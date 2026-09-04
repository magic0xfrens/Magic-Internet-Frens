# PLV → Synthetix `StakingRewards` adapter spec (for vfat.tools)

vfat's standard loader (`loadSynthetixPoolInfo` / `loadMultipleSynthetixPools`)
reads the Synthetix `StakingRewards` ABI. The PerpVault
(`contracts/solidity/cauldron/PerpVault.sol`) is a **real-yield vault**, not a
fixed-emission farm, so it does NOT natively expose that ABI. This adapter
presents it. Deploy **two instances** (ETH side, token side), verify both on the
explorer, and put their addresses in `mifrens.js`.

## Why an adapter (not a raw read)
- vfat projects APR from `rewardRate` (rewards/sec). The PLV has **no emission
  rate** — yield is whatever trading produced. The adapter turns realized fee
  flow into a **trailing `rewardRate`**: at each epoch it snapshots the vault's
  cumulative yield and time, and reports `rewardRate = Δyield / Δt` for the last
  epoch, with `periodFinish = now + epochLen` so vfat treats it as "live."
- This is the honest real-yield APR (same idea vfat uses for GMX/GLP/Gains).

## Required ABI (must match `mifrens.js` MIFRENS_PLV_ABI exactly)
```solidity
function stakingToken()          external view returns (address); // WETH (ETH side) or iteration token (token side)
function rewardsToken()          external view returns (address); // WETH for both sides
function totalSupply()           external view returns (uint256); // TVL in stakingToken units
function balanceOf(address a)    external view returns (uint256); // a's staked amount (stakingToken units)
function earned(address a)       external view returns (uint256); // a's claimable rewards (WETH)
function rewardRate()            external view returns (uint256); // trailing WETH/sec (see below)
function periodFinish()          external view returns (uint256); // now + epochLen while active

// action selectors — vfat renders buttons; route to the real vault
function stake(uint256 amount)   external;   // (ETH side may also expose stakeETH() payable)
function withdraw(uint256 amount) external;
function getReward()             external;
function exit()                  external;
```

## Mapping to PerpVault state
### TOKEN side (clean Synthetix fit)
- `stakingToken` → `registry.currentToken()` (pin genesis token, or resolve live)
- `rewardsToken` → WETH
- `totalSupply` → `vault.assetsTok()` (token backing live shares)
- `balanceOf(a)` → `tokenPosition(a).redeemable` (token redeemable for a's shares)
- `earned(a)` → `vault.pendingTokYield(a)` (already exact — claimable ETH)
- `getReward()` → `vault.claimTokYield()`; `stake` → `depositToken`; `withdraw` → `withdrawToken`
- `rewardRate` → trailing from `engine.tokYieldCumulative()` epoch delta

### ETH side (auto-compounding → normalize)
The ETH side compounds (no separate claim), so `earned` isn't native. Two options:
- **(A) Compounding-as-reward:** adapter tracks each staker's WETH cost basis;
  `earned(a) = redeemableEth(a) − costBasis(a)`, `getReward()` = withdraw-the-gain.
  Cleanest for a vfat "earn WETH" display. Adapter becomes stateful (holds shares
  on behalf of stakers) → **needs audit**.
- **(B) List as a 4626 vault instead** using vfat's vault/pricePerShare support;
  skip the Synthetix shape for this side. Lower effort, but not the standard loader.
- `rewardRate` (option A) → trailing from a new **ETH-side cumulative-yield
  counter** (add a mirror of `tokYieldCumulative()` to the engine) OR from
  `pricePerShareEth` growth × TVL over the epoch.

## Recommended small on-chain additions (view-only, safe)
- [ ] `engine.ethYieldCumulative()` — mirror of `tokYieldCumulative()` so ETH-side
      trailing APR needs no off-chain history.
- [ ] `vault.pricePerShareEth()` / `vault.pricePerShareTok()` — one call each.
- [ ] A permissionless `poke()` on the adapter to roll the epoch (or roll it on any
      stake/withdraw/getReward). No admin key required.

## Checklist before wiring into `mifrens.js`
- [ ] Both adapters deployed to the mainnet launch chain and **verified**.
- [ ] `stakingToken`/`rewardsToken` have priceable DEX liquidity (WETH is free; the
      iteration token needs a pool so vfat can derive USD).
- [ ] Non-zero TVL in each pool.
- [ ] Adapter audited (option A holds user funds — treat as in-scope for the audit).
