# The Cauldron — Independent Re-Review, Gas Efficiency & Deployment Cost

*Third-party-style pass, reviewed fresh against the current source. Companion to
`CauldronSecurityAudit.tex` (rev 2). Date: 2026-08-26.*

---

## 1. Scope reviewed

`CauldronHook`, `CauldronRegistry`, `CauldronToken`, `MiFrensGenesis`,
`MiFrensDividend`, `CauldronGachaRouter`, `CauldronCollection`, `CauldronVault`,
`CauldronGovernor`, `CauldronFactory`, `LaunchSniper` + interfaces
(`IDeathChecker`, `IPolicies`). Solidity `^0.8.26`, `via_ir`, OZ + Uniswap v4.

## 2. Security — independent verdict

A clean-slate control-flow pass was run over every external entrypoint and every
value-bearing path. **No new High or Medium issue was found.** The design holds up
to independent scrutiny:

- **Reentrancy:** every fund-moving external function (`play`, `playChurn`,
  `openReady`, `claim`, `claimMany`, `withdrawOwed`, `redeem`, `close`,
  `claimByBurn`, `claimGenesis`, `relaunch`, `summon`, `autoMigrateBatch`) is
  `nonReentrant` **and** follows checks-effects-interactions (state settled before
  the ETH send). The gacha router pays the user out **last**, after commit +
  resolve. ✔
- **External sends** use low-level `.call` with return checks or graceful
  fallbacks; ERC-20 movement of arbitrary tokens uses safe-transfer wrappers in
  the router. The in-house `CauldronToken` reverts on failure. ✔
- **`MiFrensDividend.receive()`** (called during the hook's fee routing) settles
  `accPerShare` / `residual` **before** the treasury send, and the treasury is a
  trusted, deploy-set address; v4's pool lock blocks re-entering a swap. ✔
- **Bounded loops:** volume-bucket clearing (≤24), gacha resolution
  (`MAX_MINTS_PER_CALL`), auto-migrate batch (caller-sized, per-holder skip). No
  unbounded iteration over holders. ✔
- **Arithmetic:** 0.8.x checked math; the only `unchecked` block (credit accrual)
  saturates on overflow so a swap can never revert there; seed price uses
  `FullMath.mulDiv` (no `<<192` overflow). ✔
- **Pluggable modules** (death / surtax / odds / curve): `view`-only (staticcall,
  can't reenter or mutate), **clamped** to hard caps, and `try/catch` so a broken
  module falls back to the built-in rule — never bricks a swap or relaunch, never
  in a fund path. ✔

**Confirmed from the prior engagement** (all remediated + regression-tested):
F-01 hook reserve drain (one-time `setRegistry`), F-02 genesis-freeze (moot — token
is now non-freezable), F-13 fee-exemption bypass (gated to trusted opener).

**Residual risk (unchanged):** owner-key centralization (F-03/F-14). The hook
`owner` and the registry `emergencyAdmin` retain power (module setters, LP
break-glass). **Mainnet must:** (1) hold both roles in a Gnosis Safe multisig;
(2) route the module setters through the registry so they inherit the immutable
emergency **timelock**; (3) publish the intended decommission/renounce path.

**Test coverage:** 66/66 passing (12 targeted regression tests across the fixed
findings + modules).

---

## 3. Gas efficiency

Bytecode & one-time deploy gas (real, from the round-13 broadcast):

| Contract | runtime B | deploy gas |
|---|---:|---:|
| CauldronRegistry | 24,458 | 5,449,916 |
| MiFrensGenesis | 15,876 | 3,715,497 |
| CauldronHook | 16,229 | 3,653,529 |
| CauldronFactory | 12,054 | 2,653,046 |
| CauldronGachaRouter | 6,926 | 1,599,839 |
| CauldronGovernor | 6,124 | 1,404,501 |
| MiFrensDividend | 3,600 | 862,141 |
| **wiring (setters)** | — | 697,556 |
| **LaunchSniper** (est) | 1,747 | ~450,000 |
| **Launchpad total** | | **~20.5M** |

**Efficiency notes (all minor — the code is already lean):**
- `CauldronRegistry` is **24,458 / 24,576 B** — 118 B under EIP-170. It already
  uses custom errors (not require-strings) and offloads collection/vault creation
  to `CauldronFactory` precisely to stay under the limit. Any *new* registry
  feature will need a library extraction; that's the one real constraint.
- **Storage packing (small win):** several hook policy knobs are `uint256` but
  hold ≤`uint16` values (`buyWeightBps`, `sellWeightBps`, `floorBps`, `guildBps`,
  `snipeMaxBps`, `snipeWindowBlocks`, `maxOddsBps`, `pityThreshold`). Packing them
  into one or two slots would shave cold-`SLOAD`s in the swap hot path. They're
  read on every fee take, so this is the highest-value micro-opt — but it's a
  handful of gas per swap, not structural.
- **Volume buckets** are `uint256[24]` per pool; `_recordVolume` clears only stale
  buckets (bounded ≤24). Fine.
- The **module external call** adds one `STATICCALL` per swap *only when a module
  is set* (default = built-in inline path, zero overhead). Acceptable.

Per-op gas (typical for these patterns; measure on your fork before mainnet):
`mint(1)` ~140–190k · `finalize()→summon` ~4.5–5.5M (deploys token + inits the v4
pool + adds LP + deploys collection & vault) · `play()` swap ~350–550k ·
`claimGenesis` ~55–70k · `relaunch()` ~4–6M.

---

## 4. Deployment cost to Robinhood Chain

**Full stand-up ≈ 25.5M gas** = ~20.5M (launchpad contracts + wiring + sniper) +
~5M (the one-time `summon` that mints iteration-1, seeds the pool, deploys the
collection & vault). *(The 1111 genesis mints are paid by buyers, not the
deployer.)*

Robinhood Chain is an **Arbitrum Orbit L2** with ETH as the gas token, so
execution gas is cheap; the L1 data-availability posting of ~150 KB of bytecode is
the variable part.

Cost of the 25.5M-gas stand-up at ETH ≈ $2,462:

| gas price | ETH | USD |
|---|---:|---:|
| 0.01 gwei | 0.00025 | **$0.63** |
| 0.1 gwei | 0.00255 | **$6.27** |
| 1 gwei | 0.02549 | **$62.75** |
| 10 gwei | 0.25486 | **$627** |

**Realistic all-in estimate: ~$5–$60.** Orbit L2 execution typically runs
0.01–0.1 gwei (≈$0.60–$6 execution), plus the L1 calldata surcharge for the
bytecode, which varies with L1 base fee. It is **not** thousands of dollars.

**Caveat:** Robinhood Chain's exact live gas price / L1-posting formula isn't
publicly pinned (the repo config even flags the chain-id as unverified). Before
mainnet, query the live `eth_gasPrice` on the Robinhood RPC and dry-run the deploy
with `forge script --fork-url <robinhood-rpc>` to get an exact number.

**Budget guidance:** hold ~**0.1 ETH** in the deployer for the full deploy + go-live
with comfortable headroom, plus your snipe/airdrop ETH separately.
