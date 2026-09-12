# V5 — verification: genesis / seed / deploy (X5a–X5d)

Tree: `/tmp/blind-final-h5/contracts/solidity`. All four PoC tests compile and pass:

```
Ran 2 tests for test/attacks/X5a_GenesisCancelledIgnite.t.sol:X5aGenesisCancelledIgnite
[PASS] test_Attack_StrangerIgnitesCancelledPresale_DestroysRefunds() (gas: 5761795)
  stranger gas: 47326
  ETH swept out of the cancelled pot (wei): 1110000000000000000
  bob's un-refundable paid (wei): 1110000000000000000
[PASS] test_Positive_CancelledPresaleRefundsInFull() (gas: 5673411)
[PASS] X5b test_Attack_SniperPlaySelectorDoesNotExistOnTheRouter() (gas: 1948360)
  declared selector: 0x1ca5b161...  router selector: 0x7fe7c4b6...
[PASS] X5c test_Attack_TwentyGweiCrystallizesTheWholeActiveSupply() (gas: 259020)
  attacker ETH donated (wei): 20000000000
  attack entitled (tokens): 800000000000000000000000000
  newborn active tranche (tokens): 800000000000000000000000000
Ran 3 test suites: 4 tests passed, 0 failed, 0 skipped
```

`grep -n "return;" test/attacks/X5*.t.sol` → no hits in any of the three files; every
`try/catch` helper returns a value pair that is asserted on. No vacuous early exit.

---

## X5a — DOWNGRADED: Critical → High

**The bug is real and the PoC is non-vacuous.** `MiFrensGenesis.igniteCauldron()`
(cauldron/MiFrensGenesis.sol:575-586) gates on four things and `cancelled` is not one of them:

```solidity
575:    function igniteCauldron() external nonReentrant returns (address token) {
576:        if (address(registry) == address(0)) revert RegistryNotSet();
577:        if (finalized) revert AlreadyFinalized();
578:        if (minted < GENESIS_SUPPLY) revert NotSoldOut();
581:        if (finalizer != address(0) && msg.sender != finalizer) revert NotAuthorized();
583:        finalized = true;
584:        uint256 bal = address(this).balance;
585:        (token, ) = registry.summon{value: bal}();
```

**Non-vacuity (mutation).** Inserting one line — `if (cancelled) revert AlreadyCancelled();`
after :578 — flips the attack test at the exact assertion under test and leaves the positive
control passing; source restored afterwards (`grep -n cancelled` now hits only 145,146,264,292,293,301):

```
[FAIL: BUG: igniteCauldron succeeds on a CANCELLED presale] test_Attack_...() (gas: 5757005)
  stranger gas: 10492 | ETH swept out of the cancelled pot (wei): 0
[PASS] test_Positive_CancelledPresaleRefundsInFull()
Suite result: FAILED. 1 passed; 1 failed
```

**State reachability — confirmed.** `cancelPresale` (:289-294) has no sell-out precondition:
`if (msg.sender != deployer) revert NotAuthorized(); if (finalized) revert PresaleOver();
if (cancelled) revert AlreadyCancelled();`. So cancelled ∧ sold-out is an ordinary state.

**Recoverability — confirmed unrecoverable.** `grep -n "call{value|transfer(|send(|selfdestruct"`
over MiFrensGenesis.sol returns exactly two ETH exits: :305 (`refund`) and :584 (`ignite`).
There is no owner withdraw/sweep/emergency path. `refund()` (:300-307) still passes its
`cancelled` gate after the ignite but the pot is zero → `RefundFailed`. `paid[bob]` survives
as a debt with nothing behind it (PoC: bob's un-refundable paid = 1.11e18 wei).

**Counter-argument that landed: the `finalizer` gate in the canonical deploy.**
`deploy/DeployLaunchpad.s.sol:524` — `presale.setFinalizer(vm.envOr("FINALIZER", deployer));`
with the comment "Defaults to the deployer; FINALIZER=0x0 restores the permissionless
behaviour if that is what a round actually wants." The PoC's `setUp` never calls
`setFinalizer`, so it runs with `finalizer == address(0)` (the *contract* default —
MiFrensGenesis.sol:423-426 "Zero = anyone (default)"), where the attack is exactly as claimed.
Under the canonical script's default the ignite is deployer-only and the attack reduces to
deployer self-harm.

**Verdict.** High. The missing gate, the permanent unrecoverable refund loss, and the
free-for-all ignite are all verified; the "anyone, 47k gas, 0 ETH" framing holds only in the
explicitly opt-in `FINALIZER=0x0` configuration (or a presale deployed outside the launchpad
script), which is a config precondition rather than "permissionless at any cost". Critical-
equivalent in that configuration. One-line fix either way.

---

## X5b — DOWNGRADED: High → Low

**Fact verified twice.** `cast sig "play(uint256,uint256,uint256,uint256)"` → `0x1ca5b161`;
`cast sig "play(uint256,uint256,uint256,uint256,uint256)"` → `0x7fe7c4b6`. `LaunchSniper.sol:17-18`
declares the 4-arg form; `CauldronGachaRouter.sol:233` implements
`play(uint256 quoteIn, uint256 tokenIn, uint256 minTokenOut, uint256 minQuoteOut, uint256 openMax)`.
`grep -n "fallback|receive()"` on the router returns only `552: receive() external payable {}` —
no fallback, so the dispatcher falls through with empty returndata. The PoC deploys the *real*
`CauldronGachaRouter` and raw-calls it (`liveOk == false`, `liveRetLen == 0`), then runs the real
`LaunchSniper.launch()` against a faithful 5-arg router (reverts) and against a hypothetical
4-arg router (succeeds, control). `launch()` is unconditionally dead.

**Counter-arguments that landed (three).**
1. `DeployLaunchSniper.s.sol` is a separate, optional script. The canonical
   `DeployLaunchpad.s.sol:524` points the finalizer at the *deployer*, not the sniper, and
   `grep -i sniper deployments/*.json` returns nothing — LaunchSniper is not deployed anywhere.
   The claim "makes that sniper the presale's **only** permitted finalizer" is true only if
   that optional script is run.
2. Even then it is re-pointable: `MiFrensGenesis.sol:423-426` —
   `function setFinalizer(address _finalizer) external { if (msg.sender != deployer) revert
   NotAuthorized(); finalizer = _finalizer; }` — no pre-ignition restriction, no `finalized`
   check. One deployer transaction clears the block. It is a dead feature, not a lock.
3. `launch()` reverts atomically, so `msg.value` is returned. No funds are ever at risk.

**Verdict.** Low. A genuinely broken, undeployed deploy helper: guaranteed launch-day incident
if `DeployLaunchSniper` is used, zero fund loss, recoverable with a single owner call.

---

## X5c — CONFIRMED at High (impact restated)

**The PoC is a calculator, not an exploit** — it calls `PoolOps.crystallizeCollection` directly
against two mocks, so it proves the arithmetic and nothing about reachability. The hunter's own
`DERIVED` tag is correct. The argument order matches production exactly
(`CauldronRegistry.sol:1026-1028` → `(ledger, collection, vault, oldGen, vaultSwept, newActive, totalETH)`).

**The denomination mismatch is verified by reading the whole chain.**
- `cauldron/CauldronVault.sol:116-124` — `close()` is registry-only and
  `swept = address(this).balance;` i.e. native wei, unconditionally.
- `cauldron/CauldronVault.sol:72` — `receive() external payable { emit Deposited(...); }` —
  wide open, anyone can donate to a live vault.
- `cauldron/PoolOps.sol:1013` — `try IVaultCloseOps(oldVault).close() returns (uint256 s)
  { vaultSwept = s; } catch {}`, before any branch selection.
- `cauldron/PoolOps.sol:1054` — `return (wantQuote, p, vaultSwept);` and `:1064` —
  `return (oldQuote, recovered + _pullAsset(hookAddr, oldQuote), vaultSwept);`. Both return a
  **non-native** amount alongside the native `vaultSwept`, and neither adds `vaultSwept` into
  the seed (it cannot be — wrong asset). Only the native branch (:1059) folds it in.
- `cauldron/CauldronRegistry.sol:936-937`, the code's own admission:
  "`totalETH` keeps its name for the native case it is usually carrying, **but it is now
  denominated in `specQuote`'s OWN units.**"
- `cauldron/PoolOps.sol:1356` — `entitled = FullMath.mulDiv(swept, activeBase, totalETH);`
  wei over quote-units.

Non-18-decimal quotes are first-class (`QuoteOracle.sol:138,155` read `IERC20Decimals(quote).decimals()`),
so a 6-decimal quote gives a ~1e12 scale error; the PoC's 20 gwei figure is that error applied.
Note the bug is latent even with zero donation: any native floor left in the dying vault
mis-sizes the entitlement on every non-native relaunch.

**Counter-argument that partially landed: a downstream clamp exists.**
`CauldronRegistry.sol:1029-1045`:

```solidity
uint256 legacy = collectionLedger.totalEntitled();
if (newActive > legacy) { newActive -= legacy; }
else { emit ReserveShortfall(newGen, legacy, newActive); newActive = 0; }
if (newActive == 0) newActive = GEN1_ACTIVE_TOKENS;
```

So the dead collection does **not** literally receive 100% of the newborn supply. What actually
happens: the newborn's active LP tranche collapses to the fixed `GEN1_ACTIVE_TOKENS` floor
(seeded at :1065 against an unchanged `totalETH`, so the launch price is distorted),
`newReserve = TOTAL_SUPPLY - newActive` swells, and the dead collection's ledger carries an
inflated per-NFT token floor payable out of that reserve. The shortfall is emitted, i.e.
observable but not prevented — and the comment concedes "proportional haircutting across
claimants is an owner policy", i.e. there is none on-chain.

**Permanence — confirmed.** `CollectionLedger.sol:143-154`: `crystallize` reverts
`AlreadyCrystallized` on a second call and only ever does `entitledTokens[gen] += extraEntitled;
totalEntitled += extraEntitled;`. No downward adjuster exists on the ledger.

**Verdict.** High. Permissionless to trigger and amplify (open `receive()`), permanent, and it
mis-sizes both the newborn's LP and the legacy claim. Not Critical: it requires a generation
whose seed branch is non-native (a governance/rotation state, not the gen-1 default), and the
registry clamp keeps the newborn pool tradeable rather than bricking it. Who loses: the newborn
generation's LP/holders, in favour of the dead collection's NFT holders (an attacker holding
dead-gen NFTs profits directly).

---

## X5d — CONFIRMED at Low (hygiene only)

`deployments/sepolia.json`, `deployments/sepolia-launch.json` and `deployments/sepolia-final.json`
each record a **completely disjoint** address set for the same contracts, and two of them claim
authority: sepolia.json "Canonical autonomous Cauldron launchpad"; sepolia-launch.json
"CANONICAL v7 (AUDITED ...)"; sepolia-final.json is named *final* and asserts "Full cycle live".

| | sepolia.json | sepolia-launch.json | sepolia-final.json |
|---|---|---|---|
| MiFrensPresale | 0x046E6DCD… (+twin 0x25287d6B…) | 0x66ab0548… | 0xb1d4cba4… |
| CauldronHook | 0xf682c71C… | 0x4f44adc0… | 0xebCD5387… |
| CauldronRegistry | 0x0dcc4D2d… (+twin 0x0181A8d6…) | 0x09579fbb… | 0x4Cdb936e… |
| CauldronGovernor | 0x4b0d6f5C… | 0x999690fc… | 0xAF3D7aa0… |

No overlapping address, only one `deployedAt` field (2026-08-20), no ordering. Zero on-chain
consequence: the deploy scripts read `vm.envAddress`/`vm.envUint`, not these files
(`DeployLaunchSniper.s.sol:31-34`, `DeployLaunchpad.s.sol`). Testnet records only. Low, as
claimed — an ops/documentation defect, not a security finding.
