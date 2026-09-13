# Cauldron — Architecture

What this document covers: the registry/facet/delegatecall design, the shared
storage layout, the forwarder pattern with a worked example, why code lives where
it does, and the deployed-contract inventory.

This is the part of the system a new reader is most likely to get wrong, because
it is subtle and because a comment inside the registry describes it incorrectly.

---

## 1. The problem: EIP-170

A contract's deployed bytecode cannot exceed 24,576 bytes. `CauldronRegistry` is
the orchestrator for the whole lifecycle and does not fit. The response is three
different code-placement techniques, each with different semantics.

| Technique | Example | `address(this)` at runtime | `msg.sender` seen downstream |
|---|---|---|---|
| **Linked library, delegatecalled** | `PoolOps` | the registry | the registry |
| **Facet, explicitly delegatecalled** | `RedemptionExt` | the registry | the registry |
| **Separate contract, plain `call`** | `CauldronFactory`, both governors, `CauldronSeeder` | itself | the registry |

The first two are the same EVM mechanism. The difference is that a library is
linked at deploy time and has no storage of its own by construction, while a facet
is a full contract whose storage layout must be made to match by hand.

---

## 2. The facet pair

```
              caller
                |
                | registry.redeemOgFren(7)
                v
      +---------------------------+
      |     CauldronRegistry      |   <-- owns ALL storage, ETH, position NFTs,
      |   is CauldronBase         |       and is the msg.sender everyone sees
      +---------------------------+
                |
                | DELEGATECALL, full calldata forwarded verbatim
                v
      +---------------------------+
      |      RedemptionExt        |   <-- code only. Its own storage is never
      |   is CauldronBase         |       touched and holds nothing.
      +---------------------------+
```

Both contracts derive from `CauldronBase` (`cauldron/CauldronBase.sol:95`) and
**neither adds a state variable of its own**. That is what makes their compiled
storage layouts identical by construction — a hard requirement, because the facet
executes its code against the registry's storage
(`CauldronBase.sol:72-84`).

The file names the verification command it expects
(`CauldronBase.sol:82-83`):

```
forge inspect CauldronRegistry storageLayout
forge inspect RedemptionExt   storageLayout   # must be byte-identical
```

There is also a Foundry invariant test for it,
`contracts/solidity/test/invariants/FacetLayoutInvariant.t.sol`, which asserts
among other things that the facet custodies nothing
(`FacetLayoutInvariant.t.sol:103`).

### The immutable gotcha

`poolManager`, `positionManager` and `hook` were `immutable` in the monolith.
Immutables are baked into the **executing** contract's code, not read from
storage — so under delegatecall the facet would resolve them as **zero**. They are
storage variables now, written by the registry constructor
(`CauldronBase.sol:85-88`, `:284-286`; `CauldronRegistry.sol:167-169`).

The opposite case is deliberate: `emergencyAdmin` and `emergencyDelay` stay
`immutable` on the registry because the facet never reads them, and immutables live
in code rather than storage so they do not affect the shared layout
(`CauldronRegistry.sol:119-130`).

### Reentrancy

The facet's functions keep their own `nonReentrant`, which runs against the
**registry's** `ReentrancyGuard` slot (inherited through `CauldronBase`). The
registry's forwarders therefore must **not** be `nonReentrant` — a guard on the
outer call would double-lock and revert every redemption
(`CauldronRegistry.sol:1381-1384`).

---

## 3. The forwarder pattern

### There is no fallback

This is the single most important structural fact in this section, and it is where
the in-tree documentation is wrong.

`CauldronRegistry` declares `receive() external payable {}`
(`CauldronRegistry.sol:572`) and **no `fallback()`**. Every facet function
therefore needs an explicit stub on the registry, or the call dies as
"unrecognized function selector ... which has no fallback function". The registry
says exactly this at `:1411-1420`.

A comment at `CauldronRegistry.sol:1778-1782` states the opposite — "the fallback
delegatecalls any unknown selector to the facet, so
`registry.floorClaimableNow()` still answers exactly as before". **That is
false.** `floorClaimableNow` works because it has an explicit stub at `:1424`.

This defect class has bitten this contract pair at least five times, each recorded
in the source:

| Missing stub | Consequence | Cite |
|---|---|---|
| `setRotationWiring` | the rotation could never be wired | `RedemptionExt.sol:215-227` (referenced), stub now `CauldronRegistry.sol:274` |
| the three views | frontend reads reverted | `CauldronRegistry.sol:1411-1420`, stubs `:1424`, `:1429`, `:1434` |
| `rotateSliceFrom` | the treasury UI's rotate button reverted on **every** press, not just the multi-leg path | `CauldronRegistry.sol:247-263`, stub `:264` |
| `recoverLegs` | the documented retry had no way in; calling the facet directly ran against the facet's own empty storage and returned `(0,0)` | `CauldronRegistry.sol:279-289`, stub `:290` |
| `sweepLegProceeds` | booked foreign leg proceeds were stuck with no way to read or move them | `CauldronRegistry.sol:292-299`, stub `:300` |

**A facet function is only real once both halves exist.**

One read is *deliberately* left unstubbed: `legProceedsOf`. The registry had
roughly 40 bytes of headroom and the value-moving half had to win; the balance
stays observable off-chain from `LegProceedsBooked`/`LegProceedsSwept` and
on-chain from the slot. "A read-only gap is recoverable; a stuck asset is not"
(`CauldronRegistry.sol:302-306`).

### The forwarder

```solidity
function _forwardToExt() private {
    address ext = redemptionExt;
    if (ext == address(0)) revert NotConfigured();
    assembly {
        calldatacopy(0, 0, calldatasize())
        let ok := delegatecall(gas(), ext, 0, calldatasize(), 0, 0)
        returndatacopy(0, 0, returndatasize())
        switch ok
        case 0 { revert(0, returndatasize()) }
        default { return(0, returndatasize()) }
    }
}
```
— `CauldronRegistry.sol:1457-1468`.

It forwards the **full** calldata (selector included) and bubbles return data or
the revert verbatim. The zero-target check matters: a delegatecall to an empty
account returns SUCCESS with no data, so an unset facet would silently no-op
rather than revert (`:1451-1456`).

### Worked example — `redeemOgFren(uint256)`

```
1.  A holder calls  registry.redeemOgFren(7)
2.  The registry's stub at CauldronRegistry.sol:1389 runs _forwardToExt()
3.  DELEGATECALL into RedemptionExt with calldata  0x<selector>0000..07
4.  RedemptionExt.redeemOgFren (RedemptionExt.sol:78) executes, but:
      address(this)        == the registry
      storage slots read   == the registry's
      msg.sender           == the holder  (delegatecall preserves it)
      the MiFrens / PositionManager see the REGISTRY as their caller
5.  It debits genesisReserveOutstanding (RedemptionExt.sol:91) - the registry's slot
6.  Return data bubbles back out through the stub, unchanged
```

The stub carries the NatSpec and the signature; the body lives on the facet. ABI,
authority and custody semantics are byte-for-byte what a monolith would have
produced.

### The registry's stub inventory

| Registry stub | Line | Facet implementation | Gate lives on |
|---|---|---|---|
| `rotateSlice(uint16,uint256,PoolKey)` | `:240` | `RedemptionExt.sol:269` | the facet |
| `rotateSliceFrom(uint8,uint16,uint256,PoolKey)` | `:264` | `RedemptionExt.sol:280` | the facet |
| `setRotationWiring(address,address)` | `:274` | `RedemptionExt.sol:260` | the facet — `onlyOwner` |
| `recoverLegs(uint256)` | `:290` | `RedemptionExt.sol:732` | the facet |
| `sweepLegProceeds(address,address)` | `:300` | `RedemptionExt.sol:847` | the facet — `onlyOwner` |
| `claimByBurnUpTo(uint256,uint256)` | `:1288` | `RedemptionExt` | the facet |
| `redeemOgFren(uint256)` | `:1389` | `RedemptionExt.sol:78` | the facet — `nonReentrant` |
| `buyTreasuryOgFren(uint256)` | `:1395` | `RedemptionExt.sol:115` | the facet |
| `donateToReserve(uint256)` | `:1401` | `RedemptionExt.sol:136` | the facet |
| `materializeLegacyReserve()` | `:1407` | `RedemptionExt.sol:147` | the facet |
| `floorClaimableNow()` | `:1424` | `RedemptionExt.sol:634` | — (read) |
| `legCount(uint256)` | `:1429` | `RedemptionExt.sol:677` | — (read) |
| `legAt(uint256,uint256)` | `:1434` | `RedemptionExt.sol:682` | — (read) |

**A forwarder looks ungated at the registry and is not.** `rotateSliceFrom` has no
modifier on the registry stub; its real gate is inside the facet
(`RedemptionExt.sol:292-327`). Anyone auditing "which registry functions are
permissionless" by reading the registry alone will get the wrong answer for every
row above.

**The three read stubs are not `view`.** Solidity refuses `delegatecall` inside a
`view` body, in assembly too. They are `nonpayable` reads, which an `eth_call`
serves exactly as before — but a *Solidity* caller must not declare them `view` in
an interface, which is why every internal reader uses `floorPerFren()`
(genuinely `view`, on `CauldronBase`) instead
(`CauldronRegistry.sol:1438-1449`).

### The one hand-rolled selector

`_removeLiquidity` reaches the facet's ungated teardown entry through a raw
delegatecall rather than a stub, because the entry exists only for that call:

```solidity
bytes4 private constant RECOVER_LEGS = bytes4(keccak256("recoverLegsAtTeardown(uint256)"));
```
— `CauldronRegistry.sol:65`, used at `:1612-1613`.

It is `constant` so solc folds the hash at compile time; the same expression
written inline hashes on every call and cost 156 bytes of EIP-170 margin
(`:58-65`). The failure mode if it were wrong is silent: the delegatecall returns
`false`, the `if (ok)` skips, and every rotated leg stays stranded with nothing to
show for it (`:1607-1611`).

---

## 4. The shared storage layout

Declaration order in `CauldronBase` is **load-bearing**. Anything new must be
**appended**, never inserted — an inserted slot renumbers everything below it and
silently corrupts the facet's view of state
(`CauldronBase.sol:169-174`, `:325-329`, `:344-347`, `:508-511`).

### The layout, in declaration order

| Group | Variables | Cite |
|---|---|---|
| Reserve ceiling | `nextReserveCeilingOffset` | `:177` |
| Lifecycle flags | `summoned`, `_seedBuyUnlocked`, `currentGeneration`, `currentToken` | `:179-184` |
| Per-generation maps | `generationToken`, `generationProposer`, `generationParent`, `generationPoolId`, `generationPoolKey`, `generationPositionId`, `generationReservePositionId`, `reserveTickLower`, `reserveTickUpper` | `:187-204` |
| Genesis floor | `genesisReserveOutstanding` | `:206` |
| Claim bookkeeping | `claimed` — **dead, see below** | `:209` |
| Collections | `generationCollection`, `generationVault`, `collectionLedger`, `genesisPending` | `:211-219` |
| Wiring | `factory`, `governor`, `nftMaxSupply`, `royaltyDividend`, `royaltyBps` | `:222-232` |
| Genesis config | `genesisMode`, `genesisBaseURI`, `genesisRenderer`, `mifrens`, `genesisBonusBps`, `genesisShares`, `genesisSharePerFren`, `enchantFeeMultBps` | `:235-249` |
| Safety | `redemptionPaused`, `guardian` | `:252-254` |
| V2 seam | `successor`, `claimGate` | `:257-260` |
| Airdrop / prime | `airdropWallet`, `airdropReserve`, `primeBuyEth`, `primeFunder` | `:263-269` |
| Timing | `emergencyReadyAt`, `lastSummonAt`, `minLifetime` | `:272-276` |
| **End of the documented baseline (slot 40)** | `autoMigrate` | `:279` |
| Appended: former immutables | `poolManager`, `positionManager`, `hook`, `redemptionExt` | `:284-289` |
| Appended: progressive seed | `seeder`, `nextSeedWindow` | `:295-299` |
| Appended: ignition role | `igniter` | `:313` |
| Appended: quotes | `allowedQuote`, `generationQuote`, `quoteRotator`, `treasuryGovernor`, `quoteScale` | `:329-397` |
| Appended: treasury legs | `generationLegs`, `legProceeds` | `:489`, `:511` |

Slots 0..40 are stated to reproduce `docs/registry-storage-baseline.txt` exactly
(`CauldronBase.sol:90-93`); that file exists in the repo but was not diffed in this
pass.

### Two things that are not what a reader will assume

**The slot numbers in the comments are off by one.** `CauldronBase.sol:340`
labels `generationQuote` "slot 49"; `:347` labels `quoteRotator` "slot 50";
`:353` labels `treasuryGovernor` "slot 51"; `:397` labels `quoteScale` "slot 52".
A `forge inspect` measurement taken on 2026-09-10 on this branch put the real
slots at 48, 49, 50 and 51 respectively, cross-checked against live round-38
registry storage. That measurement was **not re-run in this pass** — treat the
comment numbers as approximate and re-measure before relying on a slot index. The
*ordering* is what the design depends on, and it is correct.

**`claimed` is dead.** `mapping(uint256 => mapping(address => bool)) public
claimed` (`CauldronBase.sol:209`) has exactly one reader — `hasClaimed`
(`CauldronRegistry.sol:1774-1776`) — and no writer anywhere in the non-test tree.
`hasClaimed()` therefore always returns `false`. Migration is tracked by burning
the real old-generation balance, not by a flag
(`CauldronRegistry.sol:1344-1345`). The slot is retained for layout stability.

### Readers deliberately placed on the facet

`legCount` and `legAt` read the `generationLegs` mapping but are implemented on
`RedemptionExt`, not on `CauldronBase`. A function on the base is inherited by the
registry too, and those two views alone cost it 250 bytes of a ~130-byte margin.
The mapping stays on the base — storage declarations carry no bytecode
(`CauldronBase.sol:513-519`).

---

## 5. Why code lives where it does

### `PoolOps` — a linked library, delegatecalled

Every V4 PositionManager encoding lives here, plus the token deployer, both
seeding paths, the funding decision, and the migration primitives
(`cauldron/PoolOps.sol:114-125`). Because it is delegatecalled, `address(this)` is
the registry: the registry holds the tokens and ETH, owns the position NFTs, and
is the `msg.sender` that the PositionManager and Permit2 see. The library holds no
state.

Three consequences worth naming:

- `PoolOps.deployTokenAbove`'s CREATE2 deployer is the **registry**, which is why
  the mined token address cannot be front-run (`PoolOps.sol:660-669`).
- `PoolOps.seedFunding` calls `hook.releaseRelaunchETH()` and
  `hook.releaseRelaunchAsset()`, which are registry-gated — and the hook sees
  `msg.sender == registry` because of the delegatecall
  (`PoolOps.sol:60-67`, `:1098-1107`; `CauldronHook.sol:1686`, `:1714`).
- `PoolOps.autoMigrateBatch` reads the opt-in flag through a **self-call**,
  `IAutoFlag(address(this)).autoMigrate(h)` — `address(this)` is the registry
  (`PoolOps.sol:1302`).

### Things extracted purely for bytes

| Moved out | To | Reclaimed | Cite |
|---|---|---|---|
| The 3.2 KB `CauldronToken` creation blob | `PoolOps.deployTokenAbove` | — | `CauldronRegistry.sol:1638-1640` |
| The creature name table | `PoolOps.creatureFor` | — | `PoolOps.sol:147-152` |
| Collection + vault creation bytecode | `CauldronFactory` | — | `cauldron/CauldronFactory.sol:9-15` |
| The OG-redemption ops | `RedemptionExt` | — | `CauldronRegistry.sol:1369-1379` |
| `claimByBurnUpTo`'s body | `RedemptionExt` | 396 B | `CauldronRegistry.sol:1281-1287` |
| The anti-sniper surtax path | `SurtaxLib` | ~330 B | commit `402b473` |
| `legCount` / `legAt` | `RedemptionExt` | 250 B | `CauldronBase.sol:513-519` |
| The badge renderer wiring | `CauldronFactory` | — | `CauldronHook.sol:2038-2041`; `CauldronFactory.sol:23-32` |
| The `RECOVER_LEGS` selector, precomputed | a `constant` | 156 B | `CauldronRegistry.sol:58-65` |
| The solvency check and `markConsumed`, reordered | — | shortened the fatal window | `CauldronRegistry.sol:974-995` |

The pattern repeats across the tree: when a fix must land in the hook or the
registry there is essentially no room, so it lands in `RedemptionExt`, a governor,
the factory, or a library instead. Several source comments record the exact margin
at the time they were written; those figures are stale and are listed as
unverified below.

### The `try/catch` discipline

Anything reached from inside `relaunch()` that could revert is wrapped, because a
revert after `markConsumed` is permanent:

| Call | Wrapping | Cite |
|---|---|---|
| `hook.resolveTickets` | gas-capped + `try/catch` | `CauldronRegistry.sol:839-841` |
| `IPerpSync.syncGeneration` | `try/catch` | `:1115` |
| `vault.close()` | `try/catch` | `PoolOps.sol:1013-1015` |
| `hook.releaseRelaunchETH` / `releaseRelaunchAsset` | `try/catch` | `PoolOps.sol:1098-1107` |
| `recoverLegsAtTeardown` | raw delegatecall, result checked | `CauldronRegistry.sol:1612-1618` |
| `collection.setLiquidatorMinter` | `try/catch` | `CauldronHook.sol:2038-2041` |
| `deathChecker.isDead` | `try/catch`, falls back to the built-in rule | `CauldronHook.sol:1639-1646` |
| `stakerOracle.isInstant` | `try/catch`, treated as "not instant" | `MigrationVesting.sol:298-299` |

The one deliberate exception is `hook.forceClosePerps()`, which is **not**
wrapped. Swallowing it let a gas-starved relaunch strand the whole perp book: the
close is all-or-nothing, an out-of-gas mid-loop reverts every settle it had done,
and survivors could never be cleared afterwards. Measured at a 12M gas cap, 64 of
64 positions survived and were locked permanently. Letting it revert rolls the
rebirth back with `markConsumed` included, leaving the winning proposal live for a
retry with more gas; the work is bounded, so a retry always fits in a block
(`CauldronRegistry.sol:1125-1145`).

### The gas reserve

`RELAUNCH_TAIL_RESERVE = 8_000_000` (`CauldronRegistry.sol:141`). Because of the
63/64 rule, an out-of-gas child would otherwise consume all but 1/64 of the gas
and the `catch` would resume with far too little to finish the rebirth. Capping
sub-calls to `gasleft() - RELAUNCH_TAIL_RESERVE` makes an OOG child consume only
its budget (`:132-141`, applied at `:839-840` and `:1142-1145`).
`RELAUNCH_TICKETS = 50` bounds the ticket-resolution loop (`:144`).

---

## 6. Deployed-contract inventory

> **Read this section as repo state, not chain state.** The addresses below were
> read from manifest files in this repository. None was verified against a chain
> in this pass.

### Two files each claim to be canonical, and they disagree

| File | Self-description | Round | Registry |
|---|---|---|---|
| `deployments/sepolia.json` | "CANONICAL Cauldron deployment (Sepolia). SINGLE SOURCE OF TRUTH." | 20 | `0x60f5e17f0A7cb39503B4C5A844b16DBc6604BB51` |
| `indexer/deployments/round.json` | "CANONICAL DEPLOYMENT MANIFEST - the single source of truth for the live deployment." | 38 | `0x018efe32379bfc3f38ed7e592f5c9f214b6e3ded` |

They agree on `poolManager` and `positionManager` and on nothing else. Commit
`a6a56f8` addressed a *different* instance of this (three files under
`contracts/solidity/deployments/`, now marked `_status: SUPERSEDED`) and named the
repo-root `deployments/sepolia.json` the single source of truth — but
`indexer/deployments/round.json` is the newer of the two, is round 38 against the
root file's round 20, and is the one the frontend and the indexer actually read
according to its own header.

**Unresolved. Do not deploy from either file without first settling which is
live.**

### `indexer/deployments/round.json` — round 38, chain 11155111 (Sepolia)

| Contract | Address |
|---|---|
| `registry` | `0x018efe32379bfc3f38ed7e592f5c9f214b6e3ded` |
| `hook` | `0xa319112cc4896f89ae0770b7be00c990c64010cc` |
| `governor` (brews) | `0x4d8afe933683172f0af8b455a1caf905dec77314` |
| `treasuryGovernor` | `0xe4a2f1bb0b094891f076716299475d43bdee8a7b` |
| `timelock` | `0x06705E8c819D962bEf3a3d7d0fF5a91E404e23B3` |
| `factory` | `0xf61db0761246e18a44a094d74b3db12211cb20e8` |
| `presale` (MiFrensGenesis) | `0x9589089c648797b5b1246a2514b4cb4820f22089` |
| `collection` | `0x09be0DFc031E3F4c0131673f4603421DAD2CaE93` |
| `collectionLedger` | `0x9250bfb86b026131af1d56d4dd962a4ea818d9ba` |
| `dividend` | `0xe0b3dd1cda3cca883af546237ca20ba2f7ac5b85` |
| `gachaRouter` | `0x5e9aa391edbfd1e5029e528981b1b362a933bf54` |
| `seeder` | `0xd0452a3cc29ff6dcb0a691e2a5348803f0cefd22` |
| `quoteRotator` | `0xb07bf8fa577c44bbe583195725e6a1edd39a69fa` |
| `quoteOracle` | `0x6cbe784d4a3c1abc17cacda71e53708e7baea44f` |
| `perpEngine` | `0x43cb1942df7ad2072a27f73b509fc1ee4c21ff92` |
| `perpVault` | `0xfc9b5eed31ef11b90b53538bccf7b2b51d112569` |
| `poolManager` (Uniswap) | `0xE03A1074c86CFeDd5C142C4F04F1a1536e203543` |
| `positionManager` (Uniswap) | `0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4` |
| `genesisSupply` | 1111 |
| `deathThresholdEth` | 0 |
| `legacyThresholdEth` / `legacyBps` | 0.02 / 4000 |

Notably **absent** from this manifest: `redemptionExt`. The facet is set once at
deploy via `setRedemptionExt` and frozen (`CauldronRegistry.sol:184-192`), and a
zero facet makes every forwarded call revert `NotConfigured` (`:1459`) — so its
address needs to be recorded somewhere. It is not in either manifest.

Also absent: `migrationVesting` and `launchSniper` (both optional), and
`permit2`, which is a hard-coded constant `0x000000000022D473030F116dDEE9F6B43aC78BA3`
(`PoolOps.sol:126`).

### Constructor arguments that must be right at deploy

| Contract | Args | Cite |
|---|---|---|
| `CauldronRegistry` | `poolManager`, `positionManager`, `hook`, `emergencyAdmin`, `emergencyDelay` — the last two are **immutable** | `CauldronRegistry.sol:158-178` |
| `TreasuryGovernor` | `mifrens`, `registry`, `guardian`, 4 durations, `testnet` — the durations are **immutable**, and `testnet` waives the floors | `TreasuryGovernor.sol:363-399` |
| `CauldronGovernor` | `mifrens` | `CauldronGovernor.sol:243-246` |
| `MiFrensGenesis` | `name`, `symbol`, `genesisSupply`, `maxSupply`, `price`, `maxPerWallet`, `baseURI` — all **immutable** | `MiFrensGenesis.sol:227-246` |
| `CauldronSeeder` | `registry`, `positionManager` (unused), `poolManager` | `CauldronSeeder.sol:159-164` |
| `MigrationVesting` | `registry`, `owner`, `vestWindow`, `stakerOracle` | `MigrationVesting.sol:146-156` |
| `CollectionLedger` | `registry` (immutable) | `CollectionLedger.sol:72-75` |
| `CauldronToken` | `name`, `symbol`, `generation`, `registry`, `initialSupply` — deployed by the protocol, never by hand | `CauldronToken.sol:36-47` |

`emergencyDelay` being immutable means a deployment configured with the wrong
delay can never be corrected. `TreasuryGovernor`'s `testnet` flag being immutable
means the same for its timing floors.

### One-shot wiring calls

Each of these can be set exactly once and is then frozen:

| Call | Freeze | Cite |
|---|---|---|
| `CauldronRegistry.setRedemptionExt` | `if (redemptionExt != 0) revert AlreadySummoned()` | `CauldronRegistry.sol:190` |
| `CauldronGovernor.setRegistry` | `if (registry != 0) revert RegistryAlreadySet()` | `CauldronGovernor.sol:252` |
| `MiFrensGenesis.setRegistry` | `if (registry != 0) revert RegistryAlreadySet()` | `MiFrensGenesis.sol:251` |

The hook's controller pointer is **not** one-shot, but changing it is a two-step,
7-day-delayed action that flushes the relaunch reserve to the outgoing registry
first (`CauldronHook.sol:263`, `:1964`, `:1984`).

---

## 7. Consolidated documentation debt

Every item below is a place where a comment, README or prior document disagrees
with the code at this commit. The code is what these documents describe.

| # | Where | What it says | What the code does |
|---|---|---|---|
| 1 | `CauldronRegistry.sol:1778-1782` | "the fallback delegatecalls any unknown selector to the facet" | There is no `fallback()`; only `receive()` (`:572`) and explicit stubs. The note at `:1411-1420` is correct and contradicts it. |
| 2 | `CauldronBase.sol:340`, `:347`, `:353`, `:397` | `generationQuote` slot 49, `quoteRotator` 50, `treasuryGovernor` 51, `quoteScale` 52 | A `forge inspect` run on 2026-09-10 measured 48/49/50/51 — off by one. Not re-measured in this pass. |
| 3 | `CauldronGovernor.sol:532-550` | `MAX_LEADER_SCAN = 64` bounds the leader rescan | `_recomputeLeader` (`:554-571`) iterates `BENCH_SLOTS` (8) and never reads the constant. It is dead. |
| 4 | `TreasuryGovernor.sol:637-655` | documents a `MAX_WINNER_SCAN` positional bound | Removed; `:656-657` says so and `winner()` (`:693-704`) bounds by time. The surviving block records a rejected design. |
| 5 | `TreasuryGovernor.sol:933` | `setQuoteOracle` is "Timelock-set" | The gate is `msg.sender != guardian` (`:936`). |
| 6 | `MiFrensGenesis.sol:29-30` | ignition unlocks at `minted == MAX_SUPPLY` and is "callable by ANYONE" | The gate is `minted >= GENESIS_SUPPLY` (`:588`); a set `finalizer` restricts it (`:591`); a cancelled sale blocks it (`:587`). |
| 7 | `MiFrensGenesis.sol:30`, `:36`, `:562-565` | the entrypoint is `finalize()`; registry ownership is handed to the presale | It is `igniteCauldron()` (`:575`), and `summon()` accepts `owner()` **or** `igniter` (`CauldronRegistry.sol:695`) precisely so ownership need not move (`CauldronBase.sol:301-313`). |
| 8 | `PoolOps.sol:247-251` | the progressive entry is "pending a ~450B reclaim"; the registry "will call this ... once its EIP-170 wiring lands" | The registry calls it today (`CauldronRegistry.sol:1729`). |
| 9 | `PoolOps.sol:285-287`, `:549`, and many others | inline cross-file line references (`:912`, `:1000`, `:273`, `:409`, `:322`) | All drifted. The real `markConsumed` is `CauldronRegistry.sol:995` and `_seedGeneration` is `:1083`. Treat comment line refs as concept pointers. |
| 10 | `CauldronBase.sol:209` + `CauldronRegistry.sol:1774` | a per-generation `claimed` flag with a `hasClaimed()` view | No writer exists in the non-test tree; `hasClaimed()` always returns `false`. |
| 11 | `deployments/sepolia.json` vs `indexer/deployments/round.json` | both call themselves the single canonical source | They disagree on every protocol address and are 18 rounds apart. Unresolved. |
| 12 | `docs/PROTOCOL_SPEC.md`, `TOKENOMICS.md`, `FLYWHEEL_ECONOMICS.md`, `DEATH_SPIRAL_ANALYSIS.md`, `SECURITY_ANALYSIS.md`, `DEPLOYMENT_GUIDE.md`, `PHOENIX_SYSTEM.md`, `PHOENIX_TAX_SYSTEM.md` | described an OP_NET / Bitcoin-L1 lending protocol with a BTC-collateralised stablecoin, a staking token and LTV liquidations | **None of it exists in this tree.** Moved to `archive/superseded-docs/opnet-era/`. They were cited as intent sources by prior audit prompts, which means those audits were partly checking against fiction. |
| 13 | `audit/graph/README.md` | generated at commit `39d04e1` | ~30 fix commits have landed since; its line numbers are not current. The file warns of this itself. |
| 14 | `audit/spec/sections/B_iteration_lifecycle.md` | written against a 1,736-line `CauldronRegistry.sol` | The file is 1,791 lines at this commit; every line number in that section is shifted. Its behavioural claims re-checked in this pass all held. |
| 15 | `CauldronVault.sol` NatSpec header (`:12-24`) | describes a working ETH floor: "every minted collection NFT is backed by an EQUAL redeemable slice of the pooled ETH" | Under the shipped configuration no ETH ever reaches it — both collection paths call `hook.setVault(address(0))` (`CauldronRegistry.sol:1189`, `:1213`) — so `redeem` always reverts `UnifiedFloorActive()` (`:102`). The contract flags this at `:85-93`, but the header above it still describes the old model. |

---

## Verification

- **Commit documented against:** `880220a`. The tree was under active edit
  throughout this pass — `CauldronHook.sol`, `CauldronBase.sol`,
  `TreasuryGovernor.sol`, `CauldronGovernor.sol`, `LaunchSniper.sol` and
  `CauldronRegistry.sol` all shifted while these documents were written, some by
  90+ lines. Every `file:line` above was mechanically re-mapped and then
  spot-verified against the tree at this commit. `CauldronBase.sol`,
  `TreasuryGovernor.sol`, `LaunchSniper.sol`, `PerpEngine.sol` and `PerpVault.sol`
  still carried uncommitted working-tree edits at the end of the pass, so a later
  commit may shift them again.

- **Documentation debt:** the consolidated table above (15 items).
- **Unverified:**
  - **EIP-170 byte margins.** A `forge build --sizes` attempted during this pass
    produced no output for the contracts of interest, so no current figure exists.
    The last verified measurement (2026-09-10, this branch, before the ~30 fix
    commits) was: `CauldronRegistry` 24,521 (55 B free), `CauldronHook` 24,508
    (68 B free), `RedemptionExt` 13,399, `CauldronSeeder` 12,974,
    `MiFrensGenesis` 20,261, `CauldronFactory` 18,159, `QuoteRotator` 7,692,
    `TreasuryGovernor` 5,676. Several commits since then explicitly moved bytes
    (`f337813` reclaimed 396 B, `402b473` ~330 B), so these are lower bounds on
    the free space at best. **Re-measure before assuming any headroom.**
  - **Storage-layout equality** between `CauldronRegistry` and `RedemptionExt`.
    Asserted by `CauldronBase.sol:72-84` and by
    `test/invariants/FacetLayoutInvariant.t.sol`; neither `forge inspect` nor the
    test was run in this pass.
  - **The slot-0..40 baseline** in `docs/registry-storage-baseline.txt` was not
    diffed against the current layout.
  - **Every deployed address.** Read from repo manifests only; nothing was queried
    on chain, and the two manifests disagree.
  - **Whether the tree compiles at this commit.** Fixes were landing throughout
    this pass.
