# The Magic Internet Cauldron — Eternal Token

Autonomous, infinitely-relaunching token protocol on Uniswap V4. When a
generation's 24h volume dies, anyone can permissionlessly relaunch: the dead
pool's liquidity is recovered, a new token is deployed, and all recovered ETH
seeds the next generation's pool. Prior holders claim 1:1 forever.

## Contracts

| Contract | Role |
|----------|------|
| `CauldronRegistry.sol` | Orchestrator. `summon()` genesis, permissionless `relaunch()`, `claimTokens(gen)`. Removes dead-pool LP, deploys the next gen, seeds its V4 pool. |
| `CauldronHook.sol` | V4 hook. On-chain 24h volume tracking (`isDead()`), tiered swap-fee collection, ETH fee reserve that self-funds relaunches. |
| `CauldronToken.sol` | Per-generation ERC20. `markDead()` freezes balances into an immutable holder snapshot for claims. |

The 6 eternal creatures cycle: MIT → SPIRIT → WRAITH → BEAST → ASTRAL → STORM → (repeat).

## Build & test

The Cauldron uses Uniswap V4, whose deps have awkward solc pins (permit2 `=0.8.17`,
solmate `=0.8.15`) that can't share a compilation unit with our `^0.8.26` code.
A dedicated Foundry profile isolates it:

```bash
cd contracts/solidity
FOUNDRY_PROFILE=cauldron forge build
FOUNDRY_PROFILE=cauldron forge test --match-contract CauldronSummonForkTest -vvv
```

`test_CreatureCycle` runs in-process. The full `summon()` flow needs live V4, so
it's a **fork test**, activated by env (otherwise it no-ops):

```bash
export FORK_RPC=https://...
export POOL_MANAGER=0x...        # V4 PoolManager on that chain
export POSITION_MANAGER=0x...    # V4 PositionManager
FOUNDRY_PROFILE=cauldron forge test --match-contract CauldronSummonForkTest -vvv
```

## Deploy

V4 hooks must live at an address whose low bits encode their permission flags, so
the hook is CREATE2-mined via `vendor/HookMiner.sol`.

```bash
cd contracts/solidity
export PRIVATE_KEY=0x...
export POOL_MANAGER=0x... POSITION_MANAGER=0x...
export NFT_CONTRACT=0x...        # optional, for tiered tax
export GENESIS_ETH=100000000000000000   # 0.1 ETH genesis liquidity
FOUNDRY_PROFILE=cauldron forge script deploy/DeployCauldron.s.sol \
  --rpc-url $ETH_RPC --broadcast \
  --verify --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvv
```

## Setup notes / gaps closed

These were the gaps that stopped the Cauldron from ever compiling or working:

1. **Uniswap V4 deps were never installed.** Added `v4-core` + `v4-periphery`
   (`forge install`). Everything now resolves to periphery's nested v4-core
   (v4.0.0-12) via `remappings.txt`; the redundant top-level `v4-core` is
   excluded per-profile.
2. **`BaseHook` was removed from v4-periphery** (upstream #510 "move to hook
   repo"). Vendored `vendor/BaseHook.sol` against the installed v4-core and
   migrated `CauldronHook` to the newer internal-override pattern
   (`_afterInitialize` / `_afterSwap`).
3. **`SwapParams` moved** out of `IPoolManager` into `PoolOperation.sol` — updated
   the import.
4. **Real bug: liquidity seeding would revert.** V4's `PositionManager._pay`
   pulls ERC20s via **Permit2**, not a plain `approve`. `CauldronRegistry` now
   approves Permit2 and grants the PositionManager a Permit2 allowance before
   `modifyLiquidities`. Without this, `summon()`/`relaunch()` revert on real V4.
5. **Version isolation.** The registry uses a minimal local `IPositionManager`
   interface (the full one extends `IPermit2Forwarder`, dragging permit2's
   `=0.8.17` pin into our `^0.8.26` unit). `HookMiner` is vendored for the same
   reason.

## Still to do before mainnet

- Run the fork test against live V4 (Ethereum/Base) to confirm the full
  `summon → swap → death → relaunch → claim` cycle end-to-end.
- Wire `nftContract` to the deployed NFT so the tiered swap-tax tiers resolve.
- Professional audit — especially the LP-recovery path and the death/volume math.
