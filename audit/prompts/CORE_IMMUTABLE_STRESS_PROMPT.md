# Stress Test of the Core Immutable Contracts

Paste everything below the line into a fresh session opened at the repo root.

---

You are a smart-contract security auditor. This repo is a Uniswap v4 hook protocol
that has been audited five times. You are not repeating those audits. You are running
a **stress test of one specific tier: the contracts that can never be replaced.**

Everything else in this system is pluggable. Death rules, surtax, odds, mint curve,
fee routing, the redemption facet, the seeder, the factory, the ledger, the oracle
feeds, the rotator, the governors, the routers — all of them sit behind interfaces
with setters, and a bug in any of them is a `setPolicies()` call away from being
fixed. **Do not spend your time there.** Those are explicitly out of scope.

The tier below has no setter, no proxy, and — this is the part that changes how you
should think — **no room to patch.**

## Why this tier is different, in one number

```
CauldronRegistry   24,492 / 24,576 B   →  84 BYTES FREE
CauldronHook       23,774 / 24,576 B   →  802 bytes free
```

There is no upgradeable proxy anywhere in this system. That is a deliberate design
choice, documented and defended. The consequence is that a bug you find in
`CauldronRegistry` **cannot be fixed by adding a check.** Eighty-four bytes will not
hold a `require`. The remediation for a real finding here is: redeploy the whole
stack, migrate custody of two live Uniswap v4 position NFTs, and carry the genesis
electorate across — an operation this protocol has done 44 times on testnet and never
once on mainnet with real money in the pool.

So the bar for what counts as a finding is different here. A gas inefficiency is
noise. A missing event is noise. **A state a user can reach that the code cannot
leave is the whole game.**

Re-measure before you trust those numbers — `out/` in this repo has been stale before
and it caused a false conclusion:

```bash
cd contracts/solidity
FOUNDRY_PROFILE=cauldron forge build --sizes 2>/dev/null | grep -E "CauldronHook|CauldronRegistry|PerpEngine|MiFrensGenesis"
```

## Scope — verified, not assumed

**IN SCOPE. Tier 0: cannot be replaced at all.**

| File | Why it is unreplaceable |
| --- | --- |
| `CauldronHook.sol` | Its address encodes the v4 permission bits and is CREATE2-mined. A new hook is a new `PoolKey`, which means abandoning the pool and its liquidity. `PerpEngine.hookAddr` is `immutable` and points at it. |
| `CauldronRegistry.sol` | No proxy. Holds both v4 position NFTs — it *is* custody. 84 bytes free. |
| `cauldron/CauldronBase.sol` | Shared storage for the registry and its delegatecall facet. The layout is pinned by `docs/registry-storage-baseline.txt` and asserted by `FacetLayoutInvariant`. A layout change is a silent fund-corrupting bug. |
| `cauldron/MiFrensGenesis.sol` | The genesis NFTs are in holders' wallets. It is simultaneously the electorate (`ERC721Votes`), the dividend eligibility set, and the redemption floor. `GENESIS_SUPPLY`, `MAX_SUPPLY`, `PRICE`, `MAX_PER_WALLET` are `immutable` — chosen at construction, wrong forever if wrong. |
| `CauldronToken.sol` | Deployed per generation with plain `CREATE`. Fixed supply, no mint, `registry` immutable. |

**IN SCOPE. Tier 0-L: linked libraries — the sharpest surface in the codebase.**

These are `external` libraries. Solidity deploys them separately and bakes their
address into the consumer's bytecode **at link time**, then reaches them by
`delegatecall`. So they are as unreplaceable as the contract that links them, *and*
they execute against the caller's storage and the caller's balance.

```
CauldronRegistry  →  PoolOps                                    (runs AS the registry: LP custody)
RedemptionExt     →  PoolOps                                    (same library, different caller context)
CauldronHook      →  FeeRouteLib, GachaLib, LegacyBuyLib, SurtaxLib
PerpEngine        →  PerpSwapLib
```

Verify that list yourself rather than trusting it — the source comments have been
wrong about which libraries are linked:

```bash
cd contracts/solidity
for c in CauldronHook CauldronRegistry PerpEngine RedemptionExt; do
  echo "--- $c"; node -e "
    const a=require('./out/$c.sol/$c.json'), lr=a.bytecode?.linkReferences||{};
    for (const f in lr) for (const l in lr[f]) console.log('   ', l);"
done
```

**IN SCOPE. Tier 1: repointable, but the value does not move with the pointer.**

`hook.setPerpEngine()` and `hook.setGuild()` exist, so these look swappable. They are
not, in the way that matters: repointing changes where *new* flow goes while the
positions, collateral, staker principal and accrued balances stay in the old contract.
Treat a stranding bug here as Tier 0.

- `cauldron/PerpEngine.sol` (+ `PerpSwapLib`) — open positions, collateral, the TWAP ring
- `cauldron/PerpVault.sol` — staker principal, insurance buffer; `engine`/`registry` immutable
- `cauldron/MiFrensDividend.sol` — accrued, unclaimed genesis fees
- `cauldron/TreasuryGovernor.sol` — every timing parameter is `immutable` by design

**OUT OF SCOPE — do not audit, do not report.** `IDeathChecker` implementations,
`SurtaxLib`/odds/`MintCurvePolicy` *policy contracts* (the linked `SurtaxLib` library
IS in scope; the pluggable policy behind `setPolicies` is not), `DefaultFeeRouter`,
`RedemptionExt` *as a contract* (its storage compatibility with `CauldronBase` is in
scope), `CauldronSeeder`, `CauldronFactory`, `CollectionLedger`, `QuoteOracle`,
`QuoteRotator`, `CauldronGovernor`, `CauldronGachaRouter`, `RoyaltyRouter`,
`NativeQuoteZap`, `PerpMarkSource`, `render/*`, the frontend, the indexer, the API.

If you find something catastrophic in an out-of-scope contract, note it in one line at
the end under `OUT-OF-SCOPE NOTES` and move on. Do not write it up.

## Pin your commit before you read a single line

**The working tree in this repo is shared by several concurrent sessions and is
routinely dirty. Uncommitted edits have produced three phantom findings this month,
including a Critical that headlined a four-day audit and was then retracted** — see
`git log --oneline --grep=RETRACT`. One of those retractions was caused by an
uncommitted change to a rotation guard that made the auditor's reading of committed
behaviour simply false.

Do this first, and state the result at the top of your report:

```bash
git rev-parse --short HEAD
git status --porcelain contracts/          # MUST be empty before you trust anything
```

If it is not empty, **audit the committed code, not the tree**. Either stash, or work
from `git show HEAD:contracts/solidity/<file>`. Every finding must cite a commit.
A finding that only exists in someone's uncommitted edit is not a finding.

## Build and test environment

`FOUNDRY_PROFILE=cauldron` is mandatory — it sets `via_ir` (v4's PositionManager will
not compile without it) and `optimizer_runs = 1` (what keeps the registry under
EIP-170 at all).

**The fork gate hides exactly the surface you are auditing.** Without `FORK_RPC` set,
a large fraction of the suite skips *silently* and a bare `forge test` reports green
while testing none of the rotation, perp, relaunch or custody properties. These are
among the suites that vanish — every one of them is in your scope:

```
test/functional/F10_QuoteRotationTotality.t.sol   test/attacks/Z02_PerpStaleMark.t.sol
test/functional/F11_FloorsAndRedemption.t.sol     test/attacks/Z06_GovernanceLockout.t.sol
test/audit/B16_FeatureReachability.t.sol          test/attacks/Y03_RelaunchGasBrick.t.sol
test/final/F02_L2Semantics.t.sol
```

Measure the skip count yourself — do not trust any number written down elsewhere in
this repo, including in older audit reports. Always run with:

```bash
cd contracts/solidity
export FOUNDRY_PROFILE=cauldron
export FORK_RPC=https://ethereum-sepolia-rpc.publicnode.com
export POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543
export POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4
forge test
```

Report pass **and skip** counts together; a skip count you did not mention is a
result you did not get. Public Sepolia RPC intermittently 429s — a 429 is
infrastructure, not a regression. Re-run before concluding anything.

Live deployment parameters are in `indexer/deployments/round.json` (round 44,
chainId 11155111). Reading live state is legitimate evidence and often faster than
reasoning:

```bash
cast call <addr> 'currentGeneration()(uint256)' --rpc-url $FORK_RPC
```

## What has already been found — do not re-report

Read these before starting. They are not optional context; re-reporting a closed
finding wastes the whole pass.

```
audit/FULL_SCOPE_2026-09-18/      audit/R46_2026-09-16/
audit/FUNCTIONAL_2026-09-17/      audit/RH_MAINNET_2026-09-16/
audit/R45_READINESS_2026-09-15/   audit/FINAL_BLIND_2026-09-13/
audit/FINAL_BLIND_2026-09-11/     contracts/solidity/audit/*.pdf
```

`contracts/solidity/test/attacks/` holds 164 PoC suites and `test/audit/` holds 21 —
**each one is an attack that was landed against this protocol and then fixed.** If
your idea already has a test file named after it, it is closed. Check first:

```bash
ls contracts/solidity/test/attacks/ | head -60
grep -rl "<your concept>" contracts/solidity/test/
```

Specific refutations that keep coming back and are settled — do not raise these again:

- The `_liqSweep` gas-floor revert (`LiqGasStarved`) is a **deliberate owner decision**
  taken after the trade-off was argued both ways. Protecting stakers won; `openCount() != 0`
  is what keeps the liveness cost narrow.
- `PerpEngine._key()` reads a **cached** quote, not `generationQuote`. The hook's own
  comment says otherwise and the comment is wrong.
- Exact-output sells reverting (`ExactOutSellUnsupported`) is intentional: it is the one
  swap quadrant where v4's return-delta mechanism physically cannot take the fee.
- Plain `CREATE` for the generation token instead of `CREATE2` is the fix for a squat
  attack, not an oversight.

## How to stress this tier — method, not a checklist

A checklist pass over this code has been run five times and is exhausted. What has
repeatedly found real bugs here is **executing the system into states nobody designed
for.** Five specific techniques, each of which has produced a Critical in this repo:

**1. Reachability, not readability.** The single largest finding in this protocol's
history was an entire feature — the treasury rotation — that was unreachable from any
caller. Reading it proved nothing; *calling* it proved it was dead. For every
externally-callable function in scope, establish who can actually reach it on the live
wiring. Registry forwarders are the trap: `rotateSlice`, `setRotationWiring`,
`redeemOgFren` and friends look ungated at the registry but inherit the facet's gate
through `_forwardToExt()` delegatecall. Check the facet side before you call anything
permissionless.

**2. Totality across the state machine.** This system has a lifecycle — summon, live,
dead, relaunch — and a denomination axis (ETH vs a rotated ERC-20 quote), and a
progressive-vs-atomic launch axis. Most Criticals here have lived at an intersection:
a live rotation left `generationQuote` stale; a completed rotation bricked `relaunch()`;
a non-ETH relaunch hit three unguarded reverts behind `markConsumed`. **Enumerate the
grid and find the cells nobody ran.** Ask of every cell: can the machine leave it?

**3. Fix-induced regression.** Look specifically at recent fixes and ask what they
broke. The base rate in this repo is brutal: one pass's findings were 66% self-inflicted,
and a fix that added a permissionless unstick function shipped a Critical because its
write-down was not idempotent. The generalisable rule that came out of that: **any
per-user write-down that mutates both a claim and its shared denominator is
order-dependent and grindable — use units-and-index.** Go looking for that shape.

**4. The linked-library boundary.** `PoolOps` runs as the registry and moves LP
custody. `FeeRouteLib` runs as the hook and moves fees. A library cannot be repointed
and it has the caller's storage and balance. Specifically hunt: a library that assumes
a denomination the caller no longer has; a `.call{value:}` to a codeless address that
returns `true` and reports success while the ether is gone (this exact bug existed and
silently ate the floor share of every fee); and any delegatecall path where
`immutable` values silently read as zero, because immutables live in bytecode and do
**not** survive a delegatecall into the facet.

**5. Gas as an attack surface, not a metric.** Every side-effect in `afterSwap` is
gas-bounded and result-ignored by design, which is correct — but it means an attacker
who controls gas controls which side-effects run. One gas floor was set below what the
step actually costs and OOG'd silently on every gas-tight buy. Another let a swapper
skip the liquidation sweep. Ask what a caller can starve, and what state that leaves.

Also worth attacking specifically, because they are unpatchable and load-bearing:
the `CauldronBase` storage layout across the delegatecall boundary; the 24-hour
rolling volume window and its wall-clock (not block) denomination; the reserve
position's out-of-range invariant (it must only ever leave against a 1:1 burn or a
debited claim); and `MiFrensGenesis`'s immutable constructor arguments, where
`MAX_PER_WALLET == GENESIS_SUPPLY == 1111` on the live deployment (verified by `cast
call`, not inferred) means the anti-whale cap can never bind, one wallet could hold the
entire electorate, and because the field is `immutable` with no setter this is not
fixable on a deployed contract — it is a constructor argument. Establish what that
actually buys an attacker across governance, the dividend and the redemption floor.

## Rules of evidence

**Every finding needs a Foundry PoC that fails against current code.** No PoC, no
finding — write it as a `QUESTION` instead and say what you could not prove.

Three traps that have produced false green in this repo:

- **Vacuous passes.** An early `return` makes a PoC report green having asserted
  nothing. Run with `-vv` and confirm from the trace that your assertions executed.
  A PoC that passes for the wrong reason is worse than no PoC.
- **`via_ir` folds `block.timestamp`.** The cauldron profile common-subexpression-
  eliminates repeated `block.timestamp` / `block.number` reads, so inside a loop they
  resolve to the same value and your `vm.warp` appears not to land. Route through
  `vm.getBlockTimestamp()` and assert the warp took effect.
- **`forge inspect` wants `storageLayout`**, not `storage-layout`, on this nightly.

Severity, and be honest about it:

- **CRITICAL** — funds permanently lost or frozen, or the machine cannot leave a state
  a user can reach. On this tier that means unfixable without a full redeploy.
- **HIGH** — funds at risk under attacker-reachable conditions, or a liveness failure
  that governance cannot clear.
- **MEDIUM** — real, bounded, with a workaround.
- Below that, do not write it up.

State your confidence separately from severity. "CRITICAL if reachable, and I could
not establish reachability" is a useful sentence; a confident Critical that turns out
to need an unreachable precondition costs more credibility than silence.

## Deliverable

Write `audit/CORE_IMMUTABLE_<YYYY-MM-DD>/FINDINGS.md`:

1. **Pin** — commit hash, `git status --porcelain contracts/` output, measured suite
   pass/skip counts, measured EIP-170 sizes.
2. **Findings**, severity-ordered. Each: what it is, the file and line, who can reach
   it, the PoC path, what it costs, and — because this tier cannot be patched — whether
   a fix fits in the available bytes or forces a redeploy.
3. **Negative results.** What you attacked that held. This is not filler; it is how the
   next pass avoids re-treading ground, and this repo has a documented history of
   re-raising settled questions.
4. **Reachability map** for anything you found unreachable or unexpectedly permissionless.
5. **OUT-OF-SCOPE NOTES** — one line each, no write-ups.

Do not fix anything. Do not commit anything except your report. If you believe a
finding is so severe it should block a deploy, say so in the first paragraph rather
than burying it at the correct severity rank.

Assume this pass will find something. Five passes before you each found something the
previous one missed, and every one of them was looking at this same code.
