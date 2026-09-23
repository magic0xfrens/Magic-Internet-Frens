# Upgrade readiness: what it takes to add cross-chain launches later

2026-09-23 · HEAD `72832ad` · evidence: `contracts/solidity/test/functional/F23_SuccessorRehearsal.t.sol`
(7/7 pass, local V4, no RPC; re-confirmed 7/7 in a clean worktree at `72832ad`, so it is not dirty-tree contamination). Companion to `docs/CROSSCHAIN_REVIEW_2026-09-22.md` §3.9–3.10.

## The one rule

> **After a registry handover, everything a holder could do before it must
> still be possible, through the new registry.**

Cross-chain launches (the roaming Cauldron) need new registry entrypoints: exit
instead of reseed, and resume at generation N+k. The registry can't gain them
in place:

- it has **8 bytes** free and no catch-all fallback (`CauldronRegistry.sol:1461`);
- its facet is **frozen** after the first set (`:190-197`);
- the hook is unpatchable.

So roaming ships as a **v2 registry through the successor handover**, the
protocol's only core-upgrade route: `setSuccessor` → `armEmergency` → wait
`emergencyDelay` → `migrateToSuccessor`, plus the hook's
`proposeRegistryOverride` → 7 days → `executeRegistryOverride`.

That route is a good shape for an audited upgrade:

- v2 is reviewed as its own codebase;
- the switch is announced on-chain and slow;
- redemptions are forced open while it's armed, so any holder can leave at the
  floor first.

**But today the route delivers a successor that can't run the machine.** The
fixes below are cheap *now*. After launch, the only way to fix the handover is
a handover.

---

## 1. What the rehearsal proves (executed, not read)

Each test first shows the capability working before the handover, so no
assertion can pass vacuously. Every post-handover failure is pinned to its
exact revert.

| test | before the handover | after the handover |
|---|---|---|
| H0 | — | ✅ both LP position NFTs → v2; hook answers to v2 |
| H1 | v1 prices the genesis floor | ❌ v2 holds the LP with **no state**: `summoned=false`, generation 0, token 0, floor 0 |
| H2 | — | ❌ `genesis.setRegistry(v2)` → `RegistryAlreadySet`; v2 → `custodyTransfer` → `NotAuthorized` |
| H3 | OG redeem via v1 ✅ | ❌ v1 → `NotApproved(v1)` (PositionManager), v2 → `NotSummoned`; a treasury fren can never be resold |
| H4 | a moved fren re-enchants ✅ | ❌ `castSpell` → `NotApproved(v1)`: the fee is routed to v1, which no longer owns the reserve. `dividend.setRegistry(v2)` → `NotOwner` |
| H5 | — | ❌ v2 `burn` of a gen-1 token → `NotRegistry` (`CauldronToken.registry` is immutable) |
| H6 | real relaunch to gen 2 (continues the real MiFrens); gen-1 → gen-2 `claimByBurn` ✅ | ❌ v1 → `NotApproved(v1)`, v2 → `CannotClaimCurrentGen`; the rest of the holder's gen-1 balance can't migrate |

Nothing is *lost*: each failing call reverts atomically. But the OG floor, the
re-enchant loop, treasury resale and old-generation migration all stop for good.

**Not yet covered** (same mechanism by reading; extend F23 before any v2 audit):
legacy NFT floor redeem (`recycleCollectionNFT`), `MigrationVesting` claims,
perp stake withdrawal, and `QuoteRotator` legs.

---

## 2. Requirements

Each item names what to build, why (which test flips), and where it lives. **None
of them needs a byte of the registry.**

### R1 · State handover: v2 must start from v1's exact state

`migrateToSuccessor` moves the position NFTs and loose balances, **no storage**
(H1). `CauldronBase` holds ~53 state variables, 18 of them mappings.

- **Recommended: an off-chain snapshot, verified during the timelock.**
  1. A script reads every `CauldronBase` slot of v1 (`eth_getStorageAt`).
  2. v2 is constructed from that snapshot.
  3. The timelock *is* the verification window: anyone can diff v2's
     constructor arguments against v1's storage before the switch executes.
  4. Publish the diff script with the proposal.
- **Mappings that can't be enumerated on-chain:** `autoMigrate` (per-account),
  rebuilt from `AutoMigrateSet` events; `allowedQuote` / `quoteScale` /
  `legProceeds` (per-asset, small), rebuilt from events and asserted. v2 should
  **reject its own activation** unless the imported totals reconcile. For
  example, reserve-position liquidity read live from the PositionManager must
  cover `genesisReserveOutstanding` + ledger entitlements.
- **On-chain alternative:** give v1 a generic `extsload(bytes32[])` view
  (~150 B). It doesn't fit in 8 bytes, so it's only viable if bytes are freed.
- `docs/registry-storage-baseline.txt` is stale (2026-09-04) and starts with a
  compiler error line. Regenerate it from a `storageLayout` build before relying
  on it.

**Flips:** H1, and together with R2–R4, H3 and H6.

### R2 · The collection follows the registry  (F14, pre-launch)

`custodyTransfer` (the primitive behind OG redeem and treasury resale) accepts
only `registry`, which is set once (`MiFrensGenesis.sol:352-357, :530`).

- Give the collection the hook's **propose → delay → execute** pair for
  `registry`. Delay ≥ the registry's `emergencyDelay`. Proposable by the current
  registry or the timelock owner.
- This applies to the **4663 mirror** in the cross-chain design, which is a new
  contract anyway. It's also the only contract here that **can't be
  redeployed**: it *is* the collection.
- Also decide the permanent **deployer lever**. `setMinter` / `setVault` /
  `setDividend` accept the immutable `deployer` forever (`onlyDeployerOrRegistry`,
  already recorded in `audit/graph/nft.md:1713`). A re-pointable minter can mint
  forged frens. Put it under the same arm → delay, or renounce it at launch.

**Flips:** H2, H3.

### R3 · The dividend follows the registry  (pre-launch)

`MiFrensDividend.registry` is set once (`:189-193`). It prices and receives the
re-enchant fee.

- **Recommended: the same propose → delay → execute pair.**
- The rejected alternative is to redeploy the dividend and re-point the
  collection's `dividend`. The old dividend would stay claimable, but **every
  enchantment resets**, and moved frens would pay the re-enchant fee a second
  time.

**Flips:** H4.

### R4 · v2 retires foreign-generation tokens without `burn`

`CauldronToken.registry` is immutable, so only v1 can ever burn a v1-era
generation token (H5). This also holds across chains: chain B can never burn
chain A's tokens.

- v2's `claimByBurn` and relaunch step 3a must **lock** v1-era tokens, or
  transfer them to a dead address, never `burn` them.
- Any supply view v2 exposes must subtract that dead balance (`totalSupply` no
  longer drops).
- Reserve sizing is unaffected: it uses `TOTAL_SUPPLY − newActive`
  (`CauldronRegistry.sol:1045-1066`).

**Flips:** H5, and with R1, H6.

### R5 · Every other dependent: re-point, wind down, or redeploy

13 contracts bind to the registry. R2–R4 cover four of them. The rest:

| contract | pointer | holds | decision for v2 |
|---|---|---|---|
| `CollectionLedger` | immutable | **NFT floor entitlements** (`totalEntitled`, per-gen) | **re-point pair** (small contract), or import into a new ledger and verify totals (R1) |
| `MigrationVesting` | immutable | **escrowed tokens mid-vest** | handover **precondition: empty**, or re-point pair. `setClaimGate(0)` restores direct migration instantly (`:524`) |
| `PerpVault` | immutable | **staker capital** | precondition: withdraw-only mode. Stakers exit during the window; v2 deploys a fresh vault |
| `PerpEngine` | immutable | positions | precondition: `openCount() == 0` (the same invariant relaunch enforces); redeploy |
| `TreasuryGovernor` | immutable | guild mandates, allowances | precondition: no open mandate; redeploy |
| `QuoteRotator` | immutable | assets mid-rotation | precondition: no rotation in flight, legs swept; redeploy |
| `CauldronGovernor` | set once | open proposals | redeploy; wire it **before** v2's first relaunch |
| `CauldronSeeder` | immutable | streamed LP | `migrateToSuccessor` already unwinds a live seed (`:560-561`); redeploy |
| `CauldronGachaRouter`, `CauldronVault`, `CauldronFactory` | immutable / none | — | redeploy |

Preconditions should be **checked by v2's activation**, not by a runbook: v2
refuses to activate while any of them fails.

### R6 · The handover procedure itself

- **Order matters.** `executeRegistryOverride` flushes the hook's `relaunchETH`
  to the **outgoing** registry (`CauldronHook.sol:2257-2270`). If it runs after
  `migrateToSuccessor`, that ETH lands in v1 after v1 has already been swept,
  and needs a second arm + wait + migrate. Execute both from one Safe batch:
  **hook override first, then `migrateToSuccessor`**. The 7-day and
  `emergencyDelay` clocks must be staged so both are ripe together.
- **Announce the exit window.** While armed, redemptions are forced open
  (`_redeemBlocked`, `CauldronBase.sol:478-480`). That is the holders' guarantee
  and the reason this route is acceptable. Say so in the proposal.
- **Rehearse on 46630** with shortened delays, using the real deploy scripts and
  the real Safe. It's the only place the Safe batching and the snapshot diff get
  exercised for real.

### R7 · Cross-chain specifics (so v2 *can* roam)

| item | why now |
|---|---|
| **Mainnet hub: active-chain pointer + chain table** | the hub is the one immutable contract; it can't grow these later |
| Mirror re-pointable on every chain (R2) | in roaming, each chain's collection must answer to that chain's current registry |
| LZ OApp owner/delegate = the timelock; DVN config changes timelocked (≥3 DVNs) | the DVN set is the key to the handoff packet |
| Value receiver: **anonymous value, LZ-only authority** | Across fills carry relayer-supplied data; see review §3.9 |
| R4 applies across chains | chain B can never burn chain A's generation tokens |

### R8 · Audit and rehearsal gates

1. **F23 flips from PoC to regression** as R1–R4 land. Each H-test's assertion
   inverts to "succeeds through v2".
2. **Extend F23** to the uncovered paths (§1). Add a full two-registry
   lifecycle: v1 gen 1 → relaunch → handover → v2 relaunch → gen 3, asserting
   OG floor, migration, dividends and NFT floors at every step.
3. **v2 audit scope:**
   - the v2 registry: exit, resume, import, activation checks;
   - the re-point pairs;
   - the RoamPort / RoamReceiver;
   - LZ configuration;
   - the Across integration;
   - cross-chain migration claims;
   - hub pointer updates;
   - **the handover itself**, as a scripted, rehearsed operation.
4. **Admin-power inventory in the audit brief.** Every `onlyOwner` /
   `onlyEmergency` / deployer lever and its delay. Note that `setSeeder` and
   `setGovernor` are instant `onlyOwner` today (`CauldronRegistry.sol:333, 585`).

---

## 3. What to do, in what order

**Before the Robinhood launch.** Cheap now, impossible later, and all in
standalone contracts:

1. R2: re-point pair on the collection/mirror, plus a decision on the deployer
   lever.
2. R3: re-point pair on the dividend.
3. R5: re-point pairs on `CollectionLedger` and `MigrationVesting` (the two that
   hold user value and are small), or accept wind-down preconditions.
4. R7: the hub's active-chain pointer and chain table.
5. Re-run F23. H2 and H4 must flip; H1, H3, H5 and H6 wait for v2.

**Later, as v2:** R1 import, R4 retirement, R5 activation checks, R6 runbook,
R7 roaming parts, and the R8 audit, then ship it through the handover.

**What not to do:** don't make the registry a proxy. The hook is unpatchable,
the registry is at EIP-170, and an upgradeable proxy would replace "every change
waits in public while holders can leave" with "the admin can change the code".
That is a worse trust model than the one this protocol was built around, and it
would invalidate every audit to date.
