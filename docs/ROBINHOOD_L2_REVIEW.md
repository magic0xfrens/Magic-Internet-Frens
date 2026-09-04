# Robinhood (Arbitrum Orbit) vs Sepolia — Pre-Mainnet L2 Review

Robinhood Chain is an **Arbitrum Orbit / Nitro L2**. Most of the protocol works
the same or better on it (Uniswap v4 is the same canonical deployment, CREATE2
hook mining, transient storage / Cancun all supported, cheaper gas). But three
Nitro semantics differ from Sepolia/L1 and touch our code. Findings below.

Authoritative facts (Arbitrum docs + research):
- `block.number` returns the **L1/parent-chain block number**, synced ~every
  13–15s. It does NOT increment per (sub-second) L2 block.
- `block.timestamp` is L2 wall-clock from the sequencer, monotonic, but
  **"unreliable in the shorter term (minutes)"** — trust it over hours, not seconds.
- `block.prevrandao` / `block.difficulty` **always return the constant `1`** — no
  randomness is bridged from L1.

---

## F-1 (HIGH) — `prevrandao` is constant → predictable randomness
`block.prevrandao` = `1` on Arbitrum, so anything seeding "randomness" from it is
deterministic/grindable:
- **Trait/mint rolls** — `MiFrensGenesis.sol:397` & `CauldronCollection.sol:179`
  seed from `blockhash(block.number-1), block.prevrandao, to, tokenId`. With
  prevrandao fixed, a contract can mint, check the result, and revert if not rare
  → **grind for rares**. Rares have value → exploitable.
- **Anti-sniper surtax jitter** — `CauldronHook.sol:847` folds `prevrandao` into
  the fee jitter; with it constant the jitter is predictable → snipers pick
  cheap-fee blocks, defeating the surtax.
- **OK:** the crystal gacha (`openCrystals`) uses a proper **commit-reveal on a
  future `blockhash(commitBlock)`** (`:1409/:1446`) — that pattern largely holds
  on Arbitrum and is the model to copy.
- **Fix:** drop `prevrandao` as entropy. Move trait/mint rolls to the same
  future-blockhash commit-reveal the gacha uses (or Chainlink VRF if available on
  Robinhood). At minimum, fold in unpredictable state (e.g. a per-mint nonce +
  future blockhash) so a same-tx grind can't see the outcome.

## F-2 (MEDIUM-HIGH) — short-term `block.timestamp` imprecision → don't run the perp TWAP at 1s
We lowered `MIN_TWAP` to 1s for tunability, which is good as a FLOOR. But since
the sequencer clock is only reliable over minutes, a 1–15s liquidation-mark TWAP
sits in the imprecise zone. **Set `twapWindow` to ~30–60s at launch** (keep the
1s floor available). The TWAP is still monotonic and safe at that window; this
just avoids over-tightening onto noisy second-level timestamps. (Revises the
earlier "15s is ideal" — 30–60s is the safer mainnet value.)

## F-3 (MEDIUM) — `block.number` is the L1 number → block-based clocks drift ~8%
The hook's death/volume clock is block-based, calibrated to 12s L1 blocks
(`BLOCKS_PER_HOUR=300`, `BLOCKS_PER_DAY=7200`). Because Arbitrum's `block.number`
tracks L1 at ~13–15s, the intended 24h window becomes **~26h** (not the
sub-second catastrophe one might fear — block.number does NOT follow the fast L2
blocks). Approximately fine, but:
- **Recommended:** migrate the death clock + snipe window (`snipeWindowBlocks`)
  from `block.number` to `block.timestamp` (SECONDS_PER_HOUR/DAY) — chain-agnostic
  and exact. Otherwise recalibrate the constants for the confirmed parent-chain
  cadence.
- **Verify:** whether Robinhood Orbit settles to Ethereum or Arbitrum One (both
  ~12–15s, so the drift stays ~8%).

## F-4 (MEDIUM) — per-block liquidation cap is coarser than intended
`PerpEngine` resets its per-block liq accumulator on `block.number` change
(`:546/:667`). Since dozens of sub-second L2 blocks share one L1 `block.number`,
the "per-block" flash-liquidation cap actually spans ~13s / many L2 blocks →
weaker than designed. Consider keying the cap on `block.timestamp` (per-second)
or accept the coarser window (the `maxLiqBps` guard still bounds it).

## F-5 (LOW-MED) — governor uses a block-number clock
`CauldronGovernor` snapshots/periods use `block.number` (`:190`). It functions
(L1-cadence blocks), but the L2-recommended pattern is an ERC-6372 timestamp
clock. Fine for launch; note for a future governor rev.

---

## Works the same or BETTER on Robinhood
- Uniswap v4 (same canonical PoolManager/PositionManager — confirmed live), hook
  permission-flag address mining (CREATE2), afterSwap accounting.
- Perp TWAP core (timestamp monotonic; safe at ≥30–60s), funding, warmup.
- Transient storage / Cancun (v4 uses TSTORE → supported).
- Crystal gacha commit-reveal (future blockhash).
- Cheaper gas → liquidation sweeps / `_sweepAfterOpen` gas-reserve pattern have
  more headroom, not less.

## Status (2026-09)
- **F-1 ✅ FIXED** (commit `fd2d9ee`): rarity now rolls at `reveal()` off the mint
  block's future hash (commit-reveal) in both CauldronCollection + MiFrensGenesis;
  surtax jitter no longer uses `prevrandao`. 142/142 tests green.
- **F-2 ✅ HANDLED**: `MIN_TWAP` lowered to 1s for tunability; **launch value =
  30–60s** (documented in MAINNET_LAUNCH.md), set via timelock post-deploy.
- **F-4 ✅ FIXED** (commit `fd2d9ee`): per-block liq throttle re-keyed to
  `block.timestamp`.
- **F-3 ⏳ DEFERRED (low-impact, functional)**: measured impact is benign — with
  block.number tracking L1 at ~13–15s, the 24h death window becomes ~27h and the
  snipe window ~6.75min (both slightly longer, harmless direction). Migrating the
  core volume/death accounting to `block.timestamp` is the robust fix but is a
  dedicated change (touches _recordVolume/getVolume24h/_getCurrentBucket, the
  IPolicies interface, and ~7 tests roll→warp) that needs new timestamp-specific
  tests. Do it as its own reviewed PR, or accept the ~12% longer grace.
- **F-5 ⏳ DEFERRED (functional)**: governor block-number clock works on the
  L1-cadence; ERC-6372 timestamp clock is a future governor rev.

## Remaining pre-mainnet action
- Re-run the full fork test-suite against a **Robinhood RPC fork** (not just Sepolia)
  to confirm parity before mainnet.
