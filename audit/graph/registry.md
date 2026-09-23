# Function graph — `registry`

Current source-derived semantic map: **89 nodes** across **6 files**. The JSON file is canonical; this document renders every semantic field for review.

## Source files

| file | lines |
|---|---:|
| `CauldronRegistry.sol` | 1856 |
| `CauldronToken.sol` | 61 |
| `cauldron/IPolicies.sol` | 74 |
| `cauldron/IDeathChecker.sol` | 31 |
| `cauldron/ILiquidatorMintable.sol` | 48 |
| `cauldron/ICauldron.sol` | 55 |


## `ICollectionMetadata (declared in CauldronRegistry.sol)`

### `setMetadata/function` — CauldronRegistry.sol:60

- Signature: `function setMetadata(MetadataMode mode, address renderer, string calldata baseURI) external`
- Authority: implementation-defined caller through this interface
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setMetadata` is declared at CauldronRegistry.sol:60; implementation-defined caller through this interface.
- Edges: none
- Observations: none


## `CauldronRegistry`

### `constructor/constructor` — CauldronRegistry.sol:164

- Signature: `constructor( address _poolManager, address _positionManager, address _hook, address _emergencyAdmin, uint256 _emergencyDelay )`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `poolManager (line 173)`; `positionManager (line 174)`; `hook (line 175)`; `emergencyAdmin (line 177, immutable)`; `emergencyDelay (line 178, immutable)`; `allowedQuote (line 181)`; `quoteScale (line 182)`
- Value: NONE
- Reachability: Runs once at deploy. It writes the three former immutables as STORAGE so the delegatecall facet reads them correctly: `poolManager` CauldronRegistry.sol:173, `positionManager` CauldronRegistry.sol:174 and `hook` CauldronRegistry.sol:175. `emergencyAdmin` CauldronRegistry.sol:177 falls back to msg.sender when the argument is zero, and `emergencyDelay` CauldronRegistry.sol:178 is immutable so it can never be lowered afterwards. Native ether is seeded into the quote allowlist with `allowedQuote` CauldronRegistry.sol:181 and a 1e18 identity in `quoteScale` CauldronRegistry.sol:182, so a fresh deployment can always launch against ether. Ownership comes from the base constructor at `Ownable` CauldronBase.sol:488, which makes the deployer the owner (DERIVED).
- Edges: none
- Observations: none

### `setRedemptionExt/function` — CauldronRegistry.sol:190

- Signature: `function setRedemptionExt(address ext) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:190)`
- Reads: `redemptionExt (line 196)`
- Writes: `redemptionExt (line 196)`
- Value: NONE
- Reachability: Owner-only and one-shot: `redemptionExt` CauldronRegistry.sol:196 must still be zero or the call reverts AlreadySummoned, so the delegatecall target is frozen after the first write at `redemptionExt` CauldronRegistry.sol:196. A code-less target is rejected at `ext` CauldronRegistry.sol:190 because a delegatecall to an empty account returns success with no data. Every facet forwarder in this file depends on this having been set (DERIVED).
- Edges: none
- Observations: none

### `setReserveCeiling/function` — CauldronRegistry.sol:203

- Signature: `function setReserveCeiling(int24 offset) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:203)`
- Reads: none
- Writes: `nextReserveCeilingOffset (line 205)`
- Value: NONE
- Reachability: Owner-only. Bounds-checked at `offset` CauldronRegistry.sol:202 then stored in `nextReserveCeilingOffset` CauldronRegistry.sol:205, which the next seed reads at `nextReserveCeilingOffset` CauldronRegistry.sol:205 and CauldronRegistry.sol:205. It takes effect on the NEXT summon or relaunch only (DERIVED).
- Edges: none
- Observations: none

### `rotateSlice/function` — CauldronRegistry.sol:246

- Signature: `function rotateSlice(uint16, uint256, PoolKey calldata) external returns (uint256, uint256)`
- Authority: anyone at the registry; the facet holds the gate (RedemptionExt.rotateSliceFrom requires rotation wiring plus a live treasury-vote envelope)
- Gate evidence: `if (remaining == 0) revert NoRotationApproved(); (RedemptionExt.sol:343)`
- Reads: `redemptionExt (line 1513)`
- Writes: none
- Value: NONE in this stub; the value movement happens inside the delegatecalled facet, which runs on this registry's own custody
- Reachability: A three-argument stub whose whole body is `_forwardToExt` CauldronRegistry.sol:247, which delegatecalls the facet with the untouched calldata. It lands on `rotateSlice` RedemptionExt.sol:296, which immediately tail-calls `rotateSliceFrom` RedemptionExt.sol:301 with fromLeg hard-coded to 0, so this entry can only ever drain the primary pool. The registry side is ungated; the facet side requires `quoteRotator` RedemptionExt.sol:319 and `treasuryGovernor` RedemptionExt.sol:328 to be wired and the guild's envelope to have room at `remaining` RedemptionExt.sol:344.
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:247), TRUSTED, in-cluster`; `RedemptionExt.rotateSlice (CauldronRegistry.sol:246), TRUSTED, delegatecall`
- Observations: none

### `rotateSliceFrom/function` — CauldronRegistry.sol:270

- Signature: `function rotateSliceFrom(uint8, uint16, uint256, PoolKey calldata) external returns (uint256, uint256)`
- Authority: anyone at the registry; the facet holds the gate (RedemptionExt.rotateSliceFrom requires rotation wiring plus a live treasury-vote envelope)
- Gate evidence: `if (remaining == 0) revert NoRotationApproved(); (RedemptionExt.sol:343)`
- Reads: `redemptionExt (line 1513)`
- Writes: none
- Value: NONE in this stub; the value movement happens inside the delegatecalled facet, which runs on this registry's own custody
- Reachability: The four-argument form. Body is `_forwardToExt` CauldronRegistry.sol:274 and it reaches `rotateSliceFrom` RedemptionExt.sol:307, which is public on the facet. The gate is entirely facet-side: wiring at `rot` RedemptionExt.sol:320, a governor at `gov` RedemptionExt.sol:329, a non-zero envelope at `remaining` RedemptionExt.sol:344 and a slice within it at `sliceBps` RedemptionExt.sol:345. Timing is the only thing the caller chooses; destination and ceiling come from the vote (`allowance` RedemptionExt.sol:330).
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:274), TRUSTED, in-cluster`; `RedemptionExt.rotateSliceFrom (RedemptionExt.sol:307), TRUSTED, delegatecall`
- Observations: none

### `setRotationWiring/function` — CauldronRegistry.sol:280

- Signature: `function setRotationWiring(address, address) external`
- Authority: owner (the gate is on the facet: RedemptionExt.setRotationWiring is onlyOwner and runs against this registry's owner slot)
- Gate evidence: `external onlyOwner (RedemptionExt.sol:287)`
- Reads: `redemptionExt (line 1513)`
- Writes: none
- Value: NONE
- Reachability: Stub for `setRotationWiring` RedemptionExt.sol:287. Because the forward is a delegatecall, the facet's `onlyOwner` resolves against this registry's own owner slot, and the writes to `quoteRotator` RedemptionExt.sol:289 and `treasuryGovernor` RedemptionExt.sol:290 land in this registry's storage. Both arguments must be non-zero (`rotator` RedemptionExt.sol:288). Not one-shot: the wiring can be replaced (DERIVED).
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:280), TRUSTED, in-cluster`; `RedemptionExt.setRotationWiring (CauldronRegistry.sol:280), TRUSTED, delegatecall`
- Observations: none

### `recoverLegs/function` — CauldronRegistry.sol:296

- Signature: `function recoverLegs(uint256) external returns (uint256, uint256)`
- Authority: anyone at the registry; the facet holds the only gate (past generations, or the live generation after a successor handoff)
- Gate evidence: `if (gen == 0 || gen >= currentGeneration) revert CannotClaimCurrentGen(); (RedemptionExt.sol:930)`
- Reads: `redemptionExt (line 1665)`
- Writes: none
- Value: NONE in this stub; the facet moves recovered leg balances, or hands leg NFTs to the successor, under delegatecall from this registry's custody
- Reachability: Forwarder stub for the leg-unwind retry: the body is `_forwardToExt` (CauldronRegistry.sol:296), which delegatecalls `recoverLegs` (RedemptionExt.sol:925) on this registry's storage and custody. The gate is facet-side: the live generation is served only after its primary custody provably moved to the recorded successor (`_handedOff` RedemptionExt.sol:926), in which case the leg NFTs follow it (`_handOffLegs` RedemptionExt.sol:927); otherwise past generations only (`currentGeneration` RedemptionExt.sol:930), with recovery and booking of proceeds (`_bookLegProceeds` RedemptionExt.sol:932).
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:296), TRUSTED, in-cluster`; `RedemptionExt.recoverLegs (RedemptionExt.sol:925), TRUSTED, delegatecall`
- Observations: none

### `sweepLegProceeds/function` — CauldronRegistry.sol:306

- Signature: `function sweepLegProceeds(address, address) external returns (uint256)`
- Authority: owner (the gate is on the facet: RedemptionExt.sweepLegProceeds is onlyOwner)
- Gate evidence: `function sweepLegProceeds(address asset, address to) external onlyOwner returns (uint256 amount) { (RedemptionExt.sol:1147)`
- Reads: `redemptionExt (line 1665)`
- Writes: none
- Value: NONE in this stub; the facet sends the booked asset out of this registry's balance
- Reachability: Stub for `sweepLegProceeds` (RedemptionExt.sol:1147). Owner-gated facet-side; it zeroes the booked figure (`legProceeds` RedemptionExt.sol:1149) before sending, so the balance leaves this registry's custody to an owner-chosen recipient.
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:306), TRUSTED, in-cluster`; `RedemptionExt.sweepLegProceeds (RedemptionExt.sol:1147), TRUSTED, delegatecall`
- Observations: none

### `setAllowedQuote/function` — CauldronRegistry.sol:314

- Signature: `function setAllowedQuote(address quote, bool allowed, uint256 scale) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:314)`
- Reads: none
- Writes: `allowedQuote (line 327)`; `quoteScale (line 329)`
- Value: NONE
- Reachability: Owner-only curation of the quote set a proposer may pick FROM. Native ether can never be removed (`quote` CauldronRegistry.sol:314) and an admitted quote must sort below the watermark (`QUOTE_WATERMARK` CauldronRegistry.sol:316) so every mined iteration token stays currency1. The flag is written at `allowedQuote` CauldronRegistry.sol:327 and, on admission only, a per-unit ether scale at `quoteScale` CauldronRegistry.sol:329 defaulting to 1e18. Relaunch re-reads the flag at `allowedQuote` CauldronRegistry.sol:327, so a de-listing between proposal and execution degrades the winner to native ether.
- Edges: none
- Observations: none

### `setSeeder/function` — CauldronRegistry.sol:333

- Signature: `function setSeeder(address _seeder) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:333)`
- Reads: `hook (line 335)`
- Writes: `seeder (line 334)`
- Value: NONE
- Reachability: Owner-only. Writes `seeder` CauldronRegistry.sol:334 and propagates the same address to the hook at `setSeeder` CauldronRegistry.sol:333 so afterSwap can nudge the stream. Setting it to zero turns progressive seeding off; the seed dispatcher tests both this and the window at `seeder` CauldronRegistry.sol:334.
- Edges: `CauldronHook.setSeeder (CauldronRegistry.sol:333), TRUSTED, out-of-cluster`
- Observations: none

### `rescueSeeder/function` — CauldronRegistry.sol:345

- Signature: `function rescueSeeder() external onlyEmergency timelocked nonReentrant`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency timelocked nonReentrant (CauldronRegistry.sol:345)`
- Reads: `seeder (line 344)`; `emergencyAdmin (line 370, immutable)`; `emergencyReadyAt (line 408)`; `emergencyDelay (line 407, immutable)`
- Writes: `emergencyReadyAt (line 408)`
- Value: receives native and/or token back from the seeder through `rescue` (line 348)
- Reachability: Break-glass path for an aborted progressive campaign. The caller must be the emergency admin (`emergencyAdmin` CauldronRegistry.sol:370) and must have armed the action first, since `_consumeTimelock` CauldronRegistry.sol:412 reverts when `emergencyReadyAt` CauldronRegistry.sol:408 is zero and clears it at CauldronRegistry.sol:408. A seeder must be configured (`s` CauldronRegistry.sol:346) before `rescue` CauldronRegistry.sol:348 pulls the seeder's loose ledger funds back to this registry.
- Edges: `ISeeder.rescue (CauldronRegistry.sol:348), TRUSTED, out-of-cluster`
- Observations: none

### `setSeedWindow/function` — CauldronRegistry.sol:356

- Signature: `function setSeedWindow(uint64 window) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:356)`
- Reads: none
- Writes: `nextSeedWindow (line 358)`
- Value: NONE
- Reachability: Owner-only. Either zero (atomic) or bounded to 60 seconds .. 7 days at `window` CauldronRegistry.sol:356, then stored at `nextSeedWindow` CauldronRegistry.sol:358. Progressive seeding fires only when this is non-zero AND a seeder is set, tested together at `nextSeedWindow` CauldronRegistry.sol:358.
- Edges: none
- Observations: none

### `enchantFee/function` — CauldronRegistry.sol:365

- Signature: `function enchantFee() external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `enchantFeeMultBps (line 366)`
- Writes: none
- Value: NONE
- Reachability: Open view. Multiplies the live floor from `floorPerFren` CauldronRegistry.sol:366 by `enchantFeeMultBps` CauldronRegistry.sol:366 over 10000. The multiplier is emergency-admin tunable at `enchantFeeMultBps` CauldronRegistry.sol:366, so the quoted fee moves with that setting.
- Edges: `CauldronBase.floorPerFren (CauldronRegistry.sol:366), TRUSTED, out-of-cluster`
- Observations: none

### `onlyEmergency/modifier` — CauldronRegistry.sol:369

- Signature: `modifier onlyEmergency()`
- Authority: internal (callers: rescueSeeder, armEmergency, setRedemptionPaused, setEnchantFeeMult, emergencyWithdrawLP, emergencySweep, setSuccessor, setClaimGate, migrateToSuccessor, setMinLifetime)
- Gate evidence: `if (msg.sender != emergencyAdmin) revert NotAdmin(); (CauldronRegistry.sol:369)`
- Reads: `emergencyAdmin (line 370, immutable)`
- Writes: none
- Value: NONE
- Reachability: The single break-glass gate. `emergencyAdmin` CauldronRegistry.sol:370 is immutable, set in the constructor at CauldronRegistry.sol:370, so this role can never be rotated or renounced after deploy. It is independent of `owner` CauldronRegistry.sol:437, which is the governance/timelock role.
- Edges: none
- Observations: none

### `timelocked/modifier` — CauldronRegistry.sol:378

- Signature: `modifier timelocked()`
- Authority: internal (callers: rescueSeeder, emergencyWithdrawLP, emergencySweep, migrateToSuccessor)
- Gate evidence: `_consumeTimelock(); (CauldronRegistry.sol:378)`
- Reads: `emergencyReadyAt (line 408)`; `emergencyDelay (line 407, immutable)`
- Writes: `emergencyReadyAt (line 408)`
- Value: NONE
- Reachability: Applied to the four custody-moving emergency actions. It consumes the arming BEFORE the body runs (`_consumeTimelock` CauldronRegistry.sol:379), so a revert inside the body rolls the consumption back with the transaction. Arming is always required even at zero delay (`emergencyReadyAt` CauldronRegistry.sol:408), which is what keeps the forced-open redemption exit in `_redeemBlocked` CauldronBase.sol:484 meaningful.
- Edges: `CauldronRegistry._consumeTimelock (CauldronRegistry.sol:379), TRUSTED, in-cluster`
- Observations: none

### `_consumeTimelock/function` — CauldronRegistry.sol:412

- Signature: `function _consumeTimelock() private`
- Authority: internal (callers: timelocked, setClaimGate)
- Gate evidence: `if (emergencyReadyAt == 0) revert Timelocked(); (CauldronRegistry.sol:412)`
- Reads: `emergencyReadyAt (line 413)`; `emergencyDelay (line 414, immutable)`
- Writes: `emergencyReadyAt (line 413)`
- Value: NONE
- Reachability: Two independent conditions: the action must be armed (`emergencyReadyAt` CauldronRegistry.sol:413) and, when the delay is non-zero, the wait must have elapsed (`emergencyDelay` CauldronRegistry.sol:414). It then zeroes the arming at `emergencyReadyAt` CauldronRegistry.sol:413, so each arming buys exactly one execution. The claim-gate setter invokes `_consumeTimelock` CauldronRegistry.sol:412 only in the restricting direction.
- Edges: none
- Observations: none

### `setIgniter/function` — CauldronRegistry.sol:420

- Signature: `function setIgniter(address who) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:420)`
- Reads: none
- Writes: `igniter (line 419)`
- Value: NONE
- Reachability: Owner-only, no bound and no one-shot. `igniter` CauldronRegistry.sol:419 is the second address (besides the owner) accepted by summon at `igniter` CauldronRegistry.sol:421, so it is a one-time ignition right rather than a standing power once `summoned` CauldronRegistry.sol:683 is set.
- Edges: none
- Observations: none

### `armEmergency/function` — CauldronRegistry.sol:426

- Signature: `function armEmergency() external onlyEmergency`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency (CauldronRegistry.sol:426)`
- Reads: `emergencyAdmin (line 370, immutable)`; `emergencyDelay (line 425, immutable)`; `emergencyReadyAt (line 427)`
- Writes: `emergencyReadyAt (line 427)`
- Value: NONE
- Reachability: Emergency-admin only. Sets `emergencyReadyAt` CauldronRegistry.sol:427 to now plus `emergencyDelay` CauldronRegistry.sol:425 and announces it. Arming has a second effect beyond the wait: it forces the redemption exit open, because `_redeemBlocked` CauldronBase.sol:484 only blocks while the arming is zero. The guardian can cancel it at `emergencyReadyAt` CauldronRegistry.sol:428.
- Edges: none
- Observations: none

### `setGuardian/function` — CauldronRegistry.sol:434

- Signature: `function setGuardian(address who) external`
- Authority: emergencyAdmin or owner
- Gate evidence: `if (msg.sender != emergencyAdmin && msg.sender != owner()) revert NotAdmin(); (CauldronRegistry.sol:436)`
- Reads: `emergencyAdmin (line 433, immutable)`
- Writes: `guardian (line 432)`
- Value: NONE
- Reachability: Either of the two admin roles may write `guardian` CauldronRegistry.sol:432, and it is not one-shot, so the emergency admin can replace a guardian that would veto it (DERIVED). The guardian's only power is the cancel at `emergencyReadyAt` CauldronRegistry.sol:446.
- Edges: `Ownable.owner (CauldronRegistry.sol:437), TRUSTED, out-of-cluster`
- Observations: none

### `vetoEmergency/function` — CauldronRegistry.sol:444

- Signature: `function vetoEmergency() external`
- Authority: guardian
- Gate evidence: `if (msg.sender != guardian) revert NotAdmin(); (CauldronRegistry.sol:444)`
- Reads: `guardian (line 445)`
- Writes: `emergencyReadyAt (line 446)`
- Value: NONE
- Reachability: Guardian-only, and the role defaults to address zero until `guardian` CauldronRegistry.sol:445 is set, so an unset guardian means no veto exists (DERIVED). Clearing `emergencyReadyAt` CauldronRegistry.sol:446 both cancels the pending action and re-closes the forced-open redemption exit that `_redeemBlocked` CauldronBase.sol:484 keys off.
- Edges: none
- Observations: none

### `setRedemptionPaused/function` — CauldronRegistry.sol:459

- Signature: `function setRedemptionPaused(bool paused) external onlyEmergency`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency (CauldronRegistry.sol:459)`
- Reads: `emergencyAdmin (line 370, immutable)`
- Writes: `redemptionPaused (line 460)`
- Value: NONE
- Reachability: Emergency-admin only and deliberately NOT timelocked, so the circuit breaker is immediate in both directions. `redemptionPaused` CauldronRegistry.sol:460 is one half of `_redeemBlocked` CauldronBase.sol:484; the other half is the arming, so pausing while an emergency is armed does not actually block redemptions.
- Edges: none
- Observations: none

### `setEnchantFeeMult/function` — CauldronRegistry.sol:468

- Signature: `function setEnchantFeeMult(uint256 bps) external onlyEmergency`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency (CauldronRegistry.sol:468)`
- Reads: `emergencyAdmin (line 370, immutable)`
- Writes: `enchantFeeMultBps (line 470)`
- Value: NONE
- Reachability: Emergency-admin only, capped at 1000000 bps (100x) at `bps` CauldronRegistry.sol:468 and written to `enchantFeeMultBps` CauldronRegistry.sol:470. The value is only ever read where the fee is computed, at `enchantFeeMultBps` CauldronRegistry.sol:470, which the dividend contract quotes off-chain and on-chain.
- Edges: none
- Observations: none

### `emergencyWithdrawLP/function` — CauldronRegistry.sol:481

- Signature: `function emergencyWithdrawLP(uint256) external onlyEmergency timelocked`
- Authority: the emergency admin, after a matured emergency arm
- Gate evidence: `function emergencyWithdrawLP(uint256) external onlyEmergency timelocked { _forwardToExt(); } (CauldronRegistry.sol:481)`
- Reads: `redemptionExt (line 1665)`
- Writes: none
- Value: NONE in this stub; the facet removes the generation's LP, seeder campaign and legs into this registry and pays both assets to the emergency admin (`sendAsset` RedemptionExt.sol:1044)
- Reachability: Break-glass LP pull. The stub enforces the emergency admin and consumes the armed, matured emergency timelock (`timelocked` CauldronRegistry.sol:481), then delegatecalls the body in the facet (`emergencyWithdrawLP` RedemptionExt.sol:1020). The body moved out to keep the registry under EIP-170; the modifiers stay here so the gate runs before the forward, whose assembly return skips any modifier post-code.
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:481), TRUSTED, in-cluster`; `RedemptionExt.emergencyWithdrawLP (RedemptionExt.sol:1020), TRUSTED, delegatecall`
- Observations: none

### `emergencySweep/function` — CauldronRegistry.sol:485

- Signature: `function emergencySweep(address token) external onlyEmergency timelocked nonReentrant`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency timelocked nonReentrant (CauldronRegistry.sol:485)`
- Reads: `emergencyReadyAt (line 408)`; `emergencyDelay (line 407, immutable)`; `emergencyAdmin (line 487, immutable)`
- Writes: `emergencyReadyAt (line 408)`
- Value: sends the registry's whole native balance to `emergencyAdmin` (line 487); ERC20 transfer of the caller-named `token` to the admin (line 483)
- Reachability: Emergency-admin only, armed and timelocked through `_consumeTimelock` CauldronRegistry.sol:412. A zero `token` CauldronRegistry.sol:483 sweeps the native balance; anything else is treated as an ERC20 and the token address is fully caller-chosen, so the external calls at `token` CauldronRegistry.sol:483 can reach arbitrary code. No return value is checked on the ERC20 transfer (DERIVED).
- Edges: `IERC20.balanceOf (CauldronRegistry.sol:490), UNTRUSTED, out-of-cluster`; `IERC20.transfer (CauldronRegistry.sol:490), UNTRUSTED, out-of-cluster`
- Observations: none

### `setSuccessor/function` — CauldronRegistry.sol:502

- Signature: `function setSuccessor(address _successor) external onlyEmergency`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency (CauldronRegistry.sol:502)`
- Reads: `emergencyAdmin (line 370, immutable)`
- Writes: `successor (line 503)`
- Value: NONE
- Reachability: Pointer only, not timelocked and not bounded: `successor` CauldronRegistry.sol:503 may be any address, including one with no code. The custody move that uses it is separately armed at `successor` CauldronRegistry.sol:503, so holders still get the forced-open exit window before value can follow the pointer.
- Edges: none
- Observations: none

### `setClaimGate/function` — CauldronRegistry.sol:521

- Signature: `function setClaimGate(address gate) external onlyEmergency`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency (CauldronRegistry.sol:521)`
- Reads: `emergencyReadyAt (line 408)`; `emergencyDelay (line 407, immutable)`; `emergencyAdmin (line 370, immutable)`
- Writes: `emergencyReadyAt (line 408)`; `claimGate (line 523)`
- Value: NONE
- Reachability: Asymmetric gate: the restricting direction consumes an arming at `_consumeTimelock` CauldronRegistry.sol:522, while clearing `claimGate` CauldronRegistry.sol:523 back to zero is immediate. A non-zero gate closes the three instant 1:1 paths, tested at `claimGate` CauldronRegistry.sol:523 and CauldronRegistry.sol:523, and on the extension side at `claimGate` RedemptionExt.sol:800.
- Edges: `CauldronRegistry._consumeTimelock (CauldronRegistry.sol:522), TRUSTED, in-cluster`
- Observations: none

### `migrateToSuccessor/function` — CauldronRegistry.sol:537

- Signature: `function migrateToSuccessor() external onlyEmergency timelocked nonReentrant`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency timelocked nonReentrant (CauldronRegistry.sol:537)`
- Reads: `emergencyReadyAt (line 408)`; `emergencyDelay (line 407, immutable)`; `successor (line 535)`; `currentGeneration (line 540)`; `generationPositionId (line 543)`; `generationReservePositionId (line 544)`; `positionManager (line 545)`; `seeder (line 549)`; `generationToken (line 562)`
- Writes: `emergencyReadyAt (line 408)`
- Value: ERC721 ownership of the active position is moved to the successor at `transferFrom` (line 545) and the reserve position at `transferFrom` (line 545) - the positions themselves are never withdrawn; ERC20 transfer of `tok` to the successor (line 562); sends the whole native balance to `to` (line 565)
- Reachability: The largest single custody move in the contract, reachable only by the emergency admin with an armed, elapsed timelock (`_consumeTimelock` CauldronRegistry.sol:412). It requires a pointer set beforehand (`to` CauldronRegistry.sol:538). Liquidity is handed over as position-NFT ownership rather than withdrawn, by the two ERC721 transferFrom calls at `activeId` CauldronRegistry.sol:543 and `reserveId` CauldronRegistry.sol:544, so a progressive generation whose active id is zero contributes nothing there and is instead unwound through `withdrawAll` CauldronRegistry.sol:551. The final native send targets a fully admin-chosen address at `to` CauldronRegistry.sol:565, and it happens after every effect (DERIVED).
- Edges: `IERC721.transferFrom (CauldronRegistry.sol:545), TRUSTED, out-of-cluster`; `IERC721.transferFrom (CauldronRegistry.sol:546), TRUSTED, out-of-cluster`; `ISeeder.seeding (CauldronRegistry.sol:557), TRUSTED, out-of-cluster`; `ISeeder.withdrawAll (CauldronRegistry.sol:558), TRUSTED, out-of-cluster`; `IERC20.balanceOf (CauldronRegistry.sol:564), TRUSTED, out-of-cluster`; `IERC20.transfer (CauldronRegistry.sol:565), TRUSTED, out-of-cluster`
- Observations: none

### `receive/receive` — CauldronRegistry.sol:575

- Signature: `receive() external payable`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: receives native through `receive` (line 575)
- Reachability: A bare payable `receive` CauldronRegistry.sol:575 with an empty body, so any address may push ether in; the hook's reserve pulls, the vault close and the seeder teardown all land here. This contract declares NO fallback, which is why every facet function needs an explicit stub such as `redeemOgFren` CauldronRegistry.sol:1433.
- Edges: none
- Observations: none

### `setGovernor/function` — CauldronRegistry.sol:582

- Signature: `function setGovernor(address _governor) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:582)`
- Reads: none
- Writes: `governor (line 581)`
- Value: NONE
- Reachability: Owner-only, unbounded and replaceable: `governor` CauldronRegistry.sol:581 accepts any address including zero. Relaunch reads it twice, for the liveness gate at `governor` CauldronRegistry.sol:583 and for the winning spec at `winner` CauldronRegistry.sol:900, so a swapped governor changes what the next rebirth launches.
- Edges: none
- Observations: none

### `setMinLifetime/function` — CauldronRegistry.sol:587

- Signature: `function setMinLifetime(uint256 _seconds) external onlyEmergency`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency (CauldronRegistry.sol:587)`
- Reads: `emergencyAdmin (line 370, immutable)`
- Writes: `minLifetime (line 588)`
- Value: NONE
- Reachability: Emergency-admin only and unbounded in both directions: `minLifetime` CauldronRegistry.sol:588 takes any value, including zero (removing the grace period entirely) or a value large enough to make the check at `minLifetime` CauldronRegistry.sol:588 unsatisfiable in practice (DERIVED).
- Edges: none
- Observations: none

### `setFactory/function` — CauldronRegistry.sol:592

- Signature: `function setFactory(address _factory) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:592)`
- Reads: none
- Writes: `factory (line 591)`
- Value: NONE
- Reachability: Owner-only with no validation on `factory` CauldronRegistry.sol:591. It is called from inside the rebirth at `deployBrew` CauldronRegistry.sol:1229 and at `deployVault` CauldronRegistry.sol:1267, both outside any try/catch, so the configured factory is on the critical path of every relaunch (DERIVED).
- Edges: none
- Observations: none

### `setNftMaxSupply/function` — CauldronRegistry.sol:597

- Signature: `function setNftMaxSupply(uint256 _max) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:597)`
- Reads: none
- Writes: `nftMaxSupply (line 599)`
- Value: NONE
- Reachability: Owner-only, bounded to 1..MAX_NFT_SUPPLY at `MAX_NFT_SUPPLY` CauldronRegistry.sol:598 before writing `nftMaxSupply` CauldronRegistry.sol:599. The same ceiling is re-applied to the proposer's requested supply inside the rebirth at `MAX_NFT_SUPPLY` CauldronRegistry.sol:598, this time by clamping rather than reverting.
- Edges: none
- Observations: none

### `setRoyalty/function` — CauldronRegistry.sol:604

- Signature: `function setRoyalty(address _dividend, uint96 _bps) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:604)`
- Reads: none
- Writes: `royaltyDividend (line 606)`; `royaltyBps (line 607)`
- Value: NONE
- Reachability: Owner-only. Capped at 1000 bps at `_bps` CauldronRegistry.sol:604, then stored in `royaltyDividend` CauldronRegistry.sol:606 and `royaltyBps` CauldronRegistry.sol:607. Both are only consumed when a brew's collection is deployed, at `royaltyReceiver` CauldronRegistry.sol:1239, so a change applies to future collections only (DERIVED).
- Edges: none
- Observations: none

### `setGenesisMetadata/function` — CauldronRegistry.sol:612

- Signature: `function setGenesisMetadata(MetadataMode mode, string calldata baseURI, address renderer) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:613)`
- Reads: none
- Writes: `genesisMode (line 616)`; `genesisBaseURI (line 617)`; `genesisRenderer (line 618)`
- Value: NONE
- Reachability: Owner-only, no bound on the string length or the renderer address (`genesisBaseURI` CauldronRegistry.sol:617, `genesisRenderer` CauldronRegistry.sol:618). These three are the defaults a rebirth loads at `genesisMode` CauldronRegistry.sol:616 before the winning proposal overwrites them at `mode` CauldronRegistry.sol:616, so after iteration one they matter only as the values used when a spec leaves them empty (DERIVED).
- Edges: none
- Observations: none

### `setCollectionMetadata/function` — CauldronRegistry.sol:640

- Signature: `function setCollectionMetadata( uint256 gen, MetadataMode mode, address renderer, string calldata baseURI ) external onlyOwner`
- Authority: caller satisfying `onlyOwner`
- Gate evidence: `onlyOwner (CauldronRegistry.sol:637)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setCollectionMetadata` is declared at CauldronRegistry.sol:640; caller satisfying `onlyOwner`.
- Edges: `ICollectionMetadata.setMetadata (CauldronRegistry.sol:648), UNTRUSTED, out-of-cluster`
- Observations: none

### `setGenesisBonus/function` — CauldronRegistry.sol:658

- Signature: `function setGenesisBonus(address _mifrens, uint256 _bonusBps, uint256 _shares) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:659)`
- Reads: `summoned (line 662)`
- Writes: `mifrens (line 665)`; `genesisBonusBps (line 666)`; `genesisShares (line 667)`
- Value: NONE
- Reachability: Owner-only and pre-ignition only: it reverts once `summoned` CauldronRegistry.sol:662 is set. The bonus is capped at 3000 bps at `_bonusBps` CauldronRegistry.sol:658 and both other fields must be non-zero at `_shares` CauldronRegistry.sol:656. `genesisShares` CauldronRegistry.sol:667 becomes the divisor of the live floor in `floorPerFren` CauldronBase.sol:461 and the OG/forged split boundary used throughout redemption.
- Edges: none
- Observations: none

### `setAirdropReserve/function` — CauldronRegistry.sol:673

- Signature: `function setAirdropReserve(address _wallet, uint256 _amount) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:673)`
- Reads: `summoned (line 674)`
- Writes: `airdropWallet (line 677)`; `airdropReserve (line 678)`
- Value: NONE
- Reachability: Owner-only, pre-ignition only (`summoned` CauldronRegistry.sol:674), non-zero wallet required at `_wallet` CauldronRegistry.sol:671 and capped at 20 percent of supply at `_amount` CauldronRegistry.sol:673. The reserve is paid out exactly once, off-LP, during ignition at `airdropReserve` CauldronRegistry.sol:678.
- Edges: none
- Observations: none

### `setPrimeFunder/function` — CauldronRegistry.sol:682

- Signature: `function setPrimeFunder(address who) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:682)`
- Reads: `summoned (line 683)`
- Writes: `primeFunder (line 684)`
- Value: NONE
- Reachability: Owner-only and pre-ignition only (`summoned` CauldronRegistry.sol:683). `primeFunder` CauldronRegistry.sol:684 is the sole gate on both prime-buy entries, at `primeFunder` CauldronRegistry.sol:684 and CauldronRegistry.sol:684, and it can never be changed after ignition (DERIVED).
- Edges: none
- Observations: none

### `fundPrimeBuy/function` — CauldronRegistry.sol:692

- Signature: `function fundPrimeBuy() external payable`
- Authority: primeFunder
- Gate evidence: `if (msg.sender != primeFunder) revert NotAdmin(); (CauldronRegistry.sol:692)`
- Reads: `primeFunder (line 691)`; `primeBuyEth (line 694)`
- Writes: `primeBuyEth (line 694)`
- Value: receives native, accumulated into `primeBuyEth` (line 694)
- Reachability: Only the configured funder may pay in (`primeFunder` CauldronRegistry.sol:691). The balance accrues in `primeBuyEth` CauldronRegistry.sol:694 as a counter alongside the registry's real ether balance, and it is spent in one shot during ignition at `primeBuyEth` CauldronRegistry.sol:694. With `primeFunder` CauldronRegistry.sol:691 unset the function is unreachable, since the zero address cannot call (DERIVED).
- Edges: none
- Observations: none

### `sweepPrimeBuy/function` — CauldronRegistry.sol:698

- Signature: `function sweepPrimeBuy() external`
- Authority: primeFunder
- Gate evidence: `if (msg.sender != primeFunder) revert NotAdmin(); (CauldronRegistry.sol:698)`
- Reads: `primeFunder (line 699)`; `primeBuyEth (line 700)`
- Writes: `primeBuyEth (line 700)`
- Value: sends native equal to `amt` back to the funder (line 700)
- Reachability: Funder-only reclaim. The counter is zeroed at `primeBuyEth` CauldronRegistry.sol:700 before the send at `amt` CauldronRegistry.sol:700, so the ordering is effects-then-interaction even though there is no reentrancy guard here. The amount paid out is the COUNTER, not a measured balance, and it is paid from whatever ether the registry holds (DERIVED).
- Edges: none
- Observations: none

### `summon/function` — CauldronRegistry.sol:719

- Signature: `function summon() external payable nonReentrant returns (address token, PoolId poolId)`
- Authority: owner or igniter
- Gate evidence: `if (msg.sender != owner() && msg.sender != igniter) revert NotAdmin(); (CauldronRegistry.sol:727)`
- Reads: `igniter (line 725)`; `summoned (line 727)`; `genesisBonusBps (line 754)`; `genesisShares (line 754)`; `airdropReserve (line 764)`; `airdropWallet (line 764)`; `primeBuyEth (line 783)`; `primeFunder (line 787)`; `poolManager (line 789)`; `generationPoolKey (line 789)`; `genesisMode (line 794)`; `genesisBaseURI (line 794)`; `genesisRenderer (line 794)`; `nftMaxSupply (line 794)`
- Writes: `summoned (line 727)`; `currentGeneration (line 733)`; `lastSummonAt (line 734)`; `currentToken (line 743)`; `generationToken (line 744)`; `genesisSharePerFren (line 756)`; `genesisReserveOutstanding (line 757)`; `primeBuyEth (line 783)`; `_seedBuyUnlocked (line 788)`; `_seedBuyUnlocked (line 788)`
- Value: receives native as the entire genesis pairing, which `_seedGeneration` places into the pool (line 773); ERC20 transfer of the freshly minted token to `airdropWallet` (line 764); spends the accumulated prime ether inside `primeBuy` (line 789)
- Reachability: The one-time ignition. Two callers are accepted, the owner and the delegated igniter, at `igniter` CauldronRegistry.sol:725; it is one-shot either way because `summoned` CauldronRegistry.sol:727 is set immediately and re-entry is refused at `summoned` CauldronRegistry.sol:727. Non-zero msg.value is mandatory at `InsufficientETH` CauldronRegistry.sol:730. Generation one is always native-quoted: nothing writes `generationQuote` here, and the mapping's zero default is what the pool is built against (DERIVED). The genesis bonus is sized only if both `genesisBonusBps` CauldronRegistry.sol:754 and the share count are non-zero, fixing `genesisSharePerFren` CauldronRegistry.sol:756 for the life of the machine. The active band is the fixed 80 percent constant at `GEN1_ACTIVE_TOKENS` CauldronRegistry.sol:762 and the reserve is the remainder minus the airdrop. The prime buy runs AFTER the seed so it hits the intended starting price, with the callback window opened and closed around it at `_seedBuyUnlocked` CauldronRegistry.sol:788 and CauldronRegistry.sol:788.
- Edges: `Ownable.owner (CauldronRegistry.sol:728), TRUSTED, out-of-cluster`; `PoolOps.creatureFor (CauldronRegistry.sol:738), TRUSTED, library`; `LaunchLib.displayName (CauldronRegistry.sol:739), TRUSTED, library`; `CauldronRegistry._deployToken (CauldronRegistry.sol:742), TRUSTED, in-cluster`; `IERC20.transfer (CauldronRegistry.sol:766), TRUSTED, out-of-cluster`; `CauldronRegistry._seedGeneration (CauldronRegistry.sol:775), TRUSTED, in-cluster`; `PoolOps.primeBuy (CauldronRegistry.sol:789), TRUSTED, library`; `CauldronRegistry._deployCollection (CauldronRegistry.sol:794), TRUSTED, in-cluster`
- Observations: comment at `CREATE` CauldronRegistry.sol:741 says the generation token is deployed with plain CREATE; code reached from `_deployToken` CauldronRegistry.sol:742 deploys it with CREATE2 from a mined salt at `salt` PoolOps.sol:742, using plain CREATE only in the unmined fallback at `CauldronToken` PoolOps.sol:767.

### `relaunch/function` — CauldronRegistry.sol:818

- Signature: `function relaunch() external nonReentrant returns (address token, PoolId poolId)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Permissionless rebirth of a dead generation. It force-closes the perp book first (`_perpHousekeep` CauldronRegistry.sol:852) and tears down every position (`_removeLiquidity` CauldronRegistry.sol:855). When a collection ledger is wired, the dead generation's legacy buffer is flushed BEFORE the genesis pending share is folded into the outstanding figure (`_flushLegacyAtRelaunch` CauldronRegistry.sol:1057), so the flush's genesis credit is counted in the same relaunch; the same wiring test then crystallizes the collection (`hasLedger` CauldronRegistry.sol:1093). A new token and pool are seeded (`_seedGeneration` CauldronRegistry.sol:1133) and the engine is re-synced.
- Edges: `CauldronHook.isDead (CauldronRegistry.sol:830), UNTRUSTED, out-of-cluster`; `ICauldronGovernor.hasProposals (CauldronRegistry.sol:838), UNTRUSTED, out-of-cluster`; `CauldronToken.burn (CauldronRegistry.sol:862), UNTRUSTED, out-of-cluster`; `CauldronHook.resolveTickets (CauldronRegistry.sol:873), UNTRUSTED, out-of-cluster`; `ICauldronGovernor.winner (CauldronRegistry.sol:900), UNTRUSTED, out-of-cluster`; `LaunchLib.displayName (CauldronRegistry.sol:964), TRUSTED, library`; `PoolOps.seedFunding (CauldronRegistry.sol:999), TRUSTED, out-of-cluster`; `ICauldronGovernor.winner (CauldronRegistry.sol:900), UNTRUSTED, out-of-cluster`; `ICauldronGovernor.markConsumed (CauldronRegistry.sol:1028), UNTRUSTED, out-of-cluster`; `CauldronHook.setActiveProposer (CauldronRegistry.sol:1040), UNTRUSTED, out-of-cluster`; `PoolOps.crystallizeCollection (CauldronRegistry.sol:1094), TRUSTED, out-of-cluster`; `ICollectionLedger.totalEntitled (CauldronRegistry.sol:1098), UNTRUSTED, out-of-cluster`; `CauldronHook.setNftCurveFrom (CauldronRegistry.sol:1148), UNTRUSTED, out-of-cluster`; `CauldronRegistry._perpHousekeep (CauldronRegistry.sol:852), TRUSTED, in-cluster`; `CauldronRegistry._removeLiquidity (CauldronRegistry.sol:855), TRUSTED, in-cluster`; `CauldronRegistry._deployToken (CauldronRegistry.sol:967), TRUSTED, in-cluster`; `CauldronRegistry._flushLegacyAtRelaunch (CauldronRegistry.sol:1057), TRUSTED, in-cluster`; `CauldronRegistry._seedGeneration (CauldronRegistry.sol:1133), TRUSTED, in-cluster`; `CauldronRegistry._continueMiFrens (CauldronRegistry.sol:1141), TRUSTED, in-cluster`; `CauldronRegistry._deployCollection (CauldronRegistry.sol:1143), TRUSTED, in-cluster`; `CauldronRegistry._perpHousekeep (CauldronRegistry.sol:1153), TRUSTED, in-cluster`
- Observations: none

### `_perpHousekeep/function` — CauldronRegistry.sol:1162

- Signature: `function _perpHousekeep(bool sync) private`
- Authority: internal (callers: relaunch)
- Gate evidence: `UNGATED`
- Reads: `hook (line 1164)`; `RELAUNCH_TAIL_RESERVE (line 1205, constant)`
- Writes: none
- Value: NONE
- Reachability: Private, reached twice inside the rebirth: before teardown to force-close the dead book, after rebirth to re-sync the engine. The sync branch swallows everything in a try/catch (`syncGeneration` CauldronRegistry.sol:1165). The force-close branch always runs, gas-capped so the relaunch tail keeps its reserve (`RELAUNCH_TAIL_RESERVE` CauldronRegistry.sol:1205), and is not wrapped: a revert there, including running out of the forwarded gas, rolls the whole relaunch back, so a relaunch can never proceed with the book left open. The engine address is read off the hook (`perpEngine` CauldronRegistry.sol:1164).
- Edges: `CauldronHook.perpEngine (CauldronRegistry.sol:1164), TRUSTED, out-of-cluster`; `IPerpSync.syncGeneration (CauldronRegistry.sol:1165), TRUSTED, out-of-cluster`; `CauldronHook.forceClosePerps (CauldronRegistry.sol:1205), TRUSTED, out-of-cluster`
- Observations: none

### `_deployCollection/function` — CauldronRegistry.sol:1213

- Signature: `function _deployCollection( uint256 gen, string memory name, string memory symbol, MetadataMode mode, string memory baseURI, address renderer, uint256 maxSupply ) private`
- Authority: internal (callers: summon, relaunch)
- Gate evidence: `UNGATED`
- Reads: `nftMaxSupply (line 1227)`; `factory (line 1229)`; `hook (line 1233)`; `royaltyDividend (line 1239)`; `royaltyBps (line 1240)`
- Writes: `generationCollection (line 1243)`; `generationVault (line 1244)`
- Value: NONE
- Reachability: Private; reached from ignition at `_deployCollection` CauldronRegistry.sol:1213 and from every non-continuation rebirth at CauldronRegistry.sol:1213. It cannot revert on missing metadata because an empty base URI falls back to a literal at `baseURI` CauldronRegistry.sol:1224 and a zero cap falls back to `nftMaxSupply` CauldronRegistry.sol:1227. The factory call at `deployBrew` CauldronRegistry.sol:1229 is NOT wrapped, so a broken or unset factory reverts the whole rebirth (DERIVED). The hook is then repointed at the new collection (`setCollection` CauldronRegistry.sol:1245) and its vault sink is deliberately zeroed (`setVault` CauldronRegistry.sol:1247), routing the floor share into the token buyback instead.
- Edges: `ICauldronFactory.deployBrew (CauldronRegistry.sol:1229), TRUSTED, out-of-cluster`; `CauldronHook.setCollection (CauldronRegistry.sol:1245), TRUSTED, out-of-cluster`; `CauldronHook.setVault (CauldronRegistry.sol:1249), TRUSTED, out-of-cluster`
- Observations: none

### `_continueMiFrens/function` — CauldronRegistry.sol:1262

- Signature: `function _continueMiFrens(uint256 gen) private`
- Authority: internal (callers: relaunch)
- Gate evidence: `UNGATED`
- Reads: `mifrens (line 1263)`; `factory (line 1267)`; `genesisShares (line 1264)`; `hook (line 1271)`
- Writes: `generationCollection (line 1268)`; `generationVault (line 1269)`
- Value: NONE
- Reachability: Private and reachable exactly once in the machine's life, from the iteration-two branch at `_continueMiFrens` CauldronRegistry.sol:1262, which requires `mifrens` CauldronRegistry.sol:1263 to be wired. No new collection is deployed; only a fresh floor vault at `deployVault` CauldronRegistry.sol:1267, whose offset is `genesisShares` CauldronRegistry.sol:1264 so the forged tranche cannot draw the OG floor. It then takes over the canonical collection by pointing its minter at the hook (`setMinter` CauldronRegistry.sol:1271), which requires this registry to already hold that authority on the collection (DERIVED).
- Edges: `ICauldronFactory.deployVault (CauldronRegistry.sol:1267), TRUSTED, out-of-cluster`; `IMiFrensContinuable.setVault (CauldronRegistry.sol:1270), TRUSTED, out-of-cluster`; `IMiFrensContinuable.setMinter (CauldronRegistry.sol:1271), TRUSTED, out-of-cluster`; `CauldronHook.setCollection (CauldronRegistry.sol:1272), TRUSTED, out-of-cluster`; `CauldronHook.setVault (CauldronRegistry.sol:1273), TRUSTED, out-of-cluster`
- Observations: none

### `claimByBurn/function` — CauldronRegistry.sol:1303

- Signature: `function claimByBurn(uint256 fromGen, uint256 amount) external returns (uint256 claimedAmount)`
- Authority: anyone (holders of a previous generation's token); blocked for ordinary callers while a vesting gate is set
- Gate evidence: `if (claimGate != address(0) && msg.sender != claimGate && msg.sender != hook.perpEngine()) { (CauldronRegistry.sol:1311)`
- Reads: `currentGeneration (line 1307)`; `claimGate (line 1312)`; `hook (line 1312)`; `generationToken (line 1315)`; `currentGeneration (line 1307)`; `positionManager (line 1323)`; `generationReservePositionId (line 1324)`; `generationPoolKey (line 1324)`; `reserveTickLower (line 1324)`; `reserveTickUpper (line 1324)`
- Writes: none
- Value: burns the caller's previous-generation balance and releases the same amount of the live token out of the reserve position, both inside `migrateOne` (line 1322)
- Reachability: Open to any holder of a strictly earlier generation (`currentGeneration` CauldronRegistry.sol:1307). When a vesting escrow is configured the direct path is closed to everyone except the escrow itself and the perp engine (`claimGate` CauldronRegistry.sol:1312). The source generation must be known (`prevToken` CauldronRegistry.sol:1315) and the caller must actually hold the amount (`balanceOf` CauldronRegistry.sol:1317). It deliberately carries no reentrancy guard, which is what lets the engine migrate its inventory while the rebirth already holds the lock (`migrateOne` CauldronRegistry.sol:1322). The release is strict: a reserve that cannot cover the amount reverts and un-burns atomically.
- Edges: `CauldronHook.perpEngine (CauldronRegistry.sol:1312), TRUSTED, out-of-cluster`; `IERC20.balanceOf (CauldronRegistry.sol:1317), TRUSTED, out-of-cluster`; `PoolOps.migrateOne (CauldronRegistry.sol:1322), TRUSTED, library`
- Observations: comment at `claimTokens` CauldronRegistry.sol:44 names the migration entry point as claimTokens(gen); code exposes it as `claimByBurn` CauldronRegistry.sol:1303 and `claimByBurnUpTo` CauldronRegistry.sol:1348, and no function of the documented name exists in this file.

### `claimByBurnUpTo/function` — CauldronRegistry.sol:1348

- Signature: `function claimByBurnUpTo(uint256, uint256) external returns (uint256)`
- Authority: any holder of an earlier generation, unless a claim gate is set, in which case only the gate itself or the perp engine; the gate is enforced facet-side
- Gate evidence: `if (claimGate != address(0) && msg.sender != claimGate && msg.sender != hook.perpEngine()) { (RedemptionExt.sol:800)`
- Reads: `redemptionExt (line 1665)`
- Writes: none
- Value: NONE in this stub; the burn and the reserve withdrawal happen inside the delegatecalled facet, on this registry's own storage and custody
- Reachability: Selector-preserving forwarder: the body is `claimByBurnUpTo` (RedemptionExt.sol:795) and this stub keeps the ABI. Every gate is facet-side: earlier generations only (`currentGeneration` RedemptionExt.sol:799), the escrow/engine exemption (`claimGate` RedemptionExt.sol:800), a known source token (`prevToken` RedemptionExt.sol:803) and a real balance (`balanceOf` RedemptionExt.sol:806); the capacity-aware migration sizes to what the reserve can deliver instead of reverting (`migrateUpTo` RedemptionExt.sol:811).
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:1349), TRUSTED, in-cluster`; `RedemptionExt.claimByBurnUpTo (RedemptionExt.sol:795), TRUSTED, delegatecall`
- Observations: none

### `enableAutoMigrate/function` — CauldronRegistry.sol:1366

- Signature: `function enableAutoMigrate() external payable`
- Authority: anyone (free for any MiFren holder, otherwise a fee is required)
- Gate evidence: `if (msg.value < AUTO_MIGRATE_FEE) revert Fee(); (CauldronRegistry.sol:1371)`
- Reads: `mifrens (line 1368)`
- Writes: `autoMigrate (line 1374)`
- Value: receives native: the opt-in fee is required only when the caller holds no fren, checked at `AUTO_MIGRATE_FEE` (line 1372), and any ether sent stays in this registry
- Reachability: Open to anyone. The fren check is skipped entirely when `mifrens` CauldronRegistry.sol:1368 is unset, in which case everyone pays. Overpayment is not refunded: the comparison at `msg` CauldronRegistry.sol:1371 is a minimum, and no change is returned (DERIVED). The flag written at `autoMigrate` CauldronRegistry.sol:1374 is the only thing that authorises a keeper to burn that wallet's old-generation balance later, and it is revocable at `autoMigrate` CauldronRegistry.sol:1374.
- Edges: `IERC721.balanceOf (CauldronRegistry.sol:1371), TRUSTED, out-of-cluster`
- Observations: none

### `disableAutoMigrate/function` — CauldronRegistry.sol:1394

- Signature: `function disableAutoMigrate() external`
- Authority: anyone (for their own wallet only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `autoMigrate (line 1395)`
- Value: NONE
- Reachability: Open and free: a caller can only ever clear their own slot, since the key is msg.sender at `autoMigrate` CauldronRegistry.sol:1395. It takes effect immediately because the keeper path re-reads the flag per holder inside `autoMigrateBatch` CauldronRegistry.sol:1392. Re-enabling costs the fee again at `AUTO_MIGRATE_FEE` CauldronRegistry.sol:1356 (DERIVED).
- Edges: none
- Observations: none

### `autoMigrateBatch/function` — CauldronRegistry.sol:1406

- Signature: `function autoMigrateBatch(uint256 fromGen, address[] calldata holders) external nonReentrant`
- Authority: anyone (permissionless keeper)
- Gate evidence: `UNGATED`
- Reads: `currentGeneration (line 1410)`; `claimGate (line 1414)`; `generationToken (line 1415)`; `currentGeneration (line 1410)`; `positionManager (line 1419)`; `generationReservePositionId (line 1420)`; `generationPoolKey (line 1420)`; `reserveTickLower (line 1420)`; `reserveTickUpper (line 1420)`
- Writes: none
- Value: burns each opted-in holder's whole previous-generation balance and releases the same amount of the live token from the reserve, inside `autoMigrateBatch` (line 1406)
- Reachability: Permissionless. Three state conditions: an earlier source generation at `currentGeneration` CauldronRegistry.sol:1410, no vesting escrow at all (`claimGate` CauldronRegistry.sol:1414 closes this path for everyone, unlike the per-caller exemption on the direct claims), and a known source token at `prevToken` CauldronRegistry.sol:1415. The holder list is caller-supplied and its length is the loop bound, so the only limit is the block gas limit (`holders` CauldronRegistry.sol:1406). Per-holder consent is checked inside the library, and the burn primitive it uses needs no allowance, so the opt-in flag at `autoMigrate` CauldronRegistry.sol:1356 is the whole authorisation.
- Edges: `PoolOps.autoMigrateBatch (CauldronRegistry.sol:1418), TRUSTED, library`
- Observations: none

### `redeemOgFren/function` — CauldronRegistry.sol:1449

- Signature: `function redeemOgFren(uint256) external returns (uint256)`
- Authority: anyone holding a genesis fren; the facet holds the gate (RedemptionExt checks OG ownership and the redemption circuit-breaker)
- Gate evidence: `if (IERC721(mifrens).ownerOf(mifrenTokenId) != msg.sender) revert NotOwnerOf(); (RedemptionExt.sol:88)`
- Reads: `redemptionExt (line 1513)`
- Writes: none
- Value: NONE in this stub; the facet pays the live floor out of this registry's reserve position and takes custody of the fren
- Reachability: Thin stub; the body is `_forwardToExt` CauldronRegistry.sol:1450 and the code that runs is `redeemOgFren` RedemptionExt.sol:81, executing on this registry's storage and custody. Every gate is facet-side: the circuit-breaker at `_redeemBlocked` RedemptionExt.sol:82, ignition at `summoned` RedemptionExt.sol:83, the OG-only id range at `genesisShares` RedemptionExt.sol:86 and ownership at `ownerOf` RedemptionExt.sol:87. The facet's own nonReentrant runs against this registry's guard slot, which is why the stub must not carry one (`nonReentrant` RedemptionExt.sol:81).
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:1450), TRUSTED, in-cluster`; `RedemptionExt.redeemOgFren (CauldronRegistry.sol:1449), TRUSTED, delegatecall`
- Observations: none

### `buyTreasuryOgFren/function` — CauldronRegistry.sol:1455

- Signature: `function buyTreasuryOgFren(uint256) external returns (uint256)`
- Authority: anyone; the facet holds the gate (the fren must currently sit in this registry's treasury)
- Gate evidence: `if (IERC721(mifrens).ownerOf(mifrenTokenId) != address(this)) revert NotOwnerOf(); (RedemptionExt.sol:127)`
- Reads: `redemptionExt (line 1513)`
- Writes: none
- Value: NONE in this stub; the facet pulls twice the live floor in the current token from the buyer and grows the reserve with it
- Reachability: Stub whose body is `_forwardToExt` CauldronRegistry.sol:1456, reaching `buyTreasuryOgFren` RedemptionExt.sol:122. Facet-side conditions: ignition at `summoned` RedemptionExt.sol:123, the OG id range at `genesisShares` RedemptionExt.sol:124, and treasury custody at `ownerOf` RedemptionExt.sol:126. The price is derived, not quoted: twice `floorPerFren` RedemptionExt.sol:128, so it moves with the reserve.
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:1456), TRUSTED, in-cluster`; `RedemptionExt.buyTreasuryOgFren (CauldronRegistry.sol:1455), TRUSTED, delegatecall`
- Observations: none

### `donateToReserve/function` — CauldronRegistry.sol:1461

- Signature: `function donateToReserve(uint256) external`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `redemptionExt (line 1513)`
- Writes: none
- Value: NONE in this stub; the facet pulls the donated amount of the current token from the caller into the reserve
- Reachability: Stub forwarding to `donateToReserve` RedemptionExt.sol:148, which has no caller gate at all; it only requires ignition at `summoned` RedemptionExt.sol:149 and a non-zero amount at `amount` RedemptionExt.sol:150. The pull is by transferFrom, so the caller must have approved this registry first (DERIVED). This is the path the dividend contract routes re-enchant fees through, which is why the fee quote at `enchantFee` CauldronRegistry.sol:365 lives on the registry.
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:1462), TRUSTED, in-cluster`; `RedemptionExt.donateToReserve (CauldronRegistry.sol:1461), TRUSTED, delegatecall`
- Observations: none

### `materializeLegacyReserve/function` — CauldronRegistry.sol:1467

- Signature: `function materializeLegacyReserve() external returns (uint256)`
- Authority: anyone (permissionless keeper)
- Gate evidence: `UNGATED`
- Reads: `redemptionExt (line 1513)`
- Writes: none
- Value: NONE in this stub; the facet sweeps the hook's held buyback tokens into this registry's reserve position
- Reachability: Stub forwarding to `materializeLegacyReserve` RedemptionExt.sol:159. No caller gate; the only precondition is ignition at `summoned` RedemptionExt.sol:160. It deposits and credits in one step so a ledger credit can never out-run the reserve backing it (`materializeLegacy` RedemptionExt.sol:163). The rebirth performs the same flush for the dying generation on the burn path at `_flushLegacyAtRelaunch` CauldronRegistry.sol:1560, so an uncalled keeper does not lose the value.
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:1468), TRUSTED, in-cluster`; `RedemptionExt.materializeLegacyReserve (CauldronRegistry.sol:1467), TRUSTED, delegatecall`
- Observations: none

### `floorClaimableNow/function` — CauldronRegistry.sol:1484

- Signature: `function floorClaimableNow() external returns (bool, uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `redemptionExt (line 1665)`
- Writes: none
- Value: NONE
- Reachability: A read that cannot be declared view because Solidity refuses delegatecall in a view body, so it is nonpayable and an eth_call serves it unchanged. It reaches `floorClaimableNow` (RedemptionExt.sol:776), which compares the live tick with the reserve band (`reserveTickUpper` RedemptionExt.sol:781). Ungated on both sides.
- Edges: `CauldronRegistry._forwardToExtView (CauldronRegistry.sol:1485), TRUSTED, in-cluster`; `RedemptionExt.floorClaimableNow (RedemptionExt.sol:776), TRUSTED, delegatecall`
- Observations: none

### `legCount/function` — CauldronRegistry.sol:1489

- Signature: `function legCount(uint256) external returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `redemptionExt (line 1665)`
- Writes: none
- Value: NONE
- Reachability: Ungated read forwarded to `legCount` (RedemptionExt.sol:819), the length of the rotated-leg array for that generation in this registry's storage (`generationLegs` RedemptionExt.sol:820). Nonpayable rather than view for the delegatecall reason (`_forwardToExtView` CauldronRegistry.sol:1490).
- Edges: `CauldronRegistry._forwardToExtView (CauldronRegistry.sol:1490), TRUSTED, in-cluster`; `RedemptionExt.legCount (RedemptionExt.sol:819), TRUSTED, delegatecall`
- Observations: none

### `legAt/function` — CauldronRegistry.sol:1494

- Signature: `function legAt(uint256, uint256) external returns (address, uint256, PoolKey memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `redemptionExt (line 1665)`
- Writes: none
- Value: NONE
- Reachability: Ungated read forwarded to `legAt` (RedemptionExt.sol:824). An out-of-range index reverts on the array access (`generationLegs` RedemptionExt.sol:829) (DERIVED); callers page it against `legCount` (CauldronRegistry.sol:1489).
- Edges: `CauldronRegistry._forwardToExtView (CauldronRegistry.sol:1495), TRUSTED, in-cluster`; `RedemptionExt.legAt (RedemptionExt.sol:824), TRUSTED, delegatecall`
- Observations: none

### `_forwardToExtView/function` — CauldronRegistry.sol:1507

- Signature: `function _forwardToExtView() private`
- Authority: internal (callers: floorClaimableNow, legCount, legAt)
- Gate evidence: `UNGATED`
- Reads: `redemptionExt (line 1513)`
- Writes: none
- Value: NONE
- Reachability: A one-line alias over `_forwardToExt` CauldronRegistry.sol:1508 that exists only to document why the three read stubs are not `view` CauldronRegistry.sol:1505. It adds no gate and no state of its own, so the three readers inherit exactly the facet's behaviour (DERIVED).
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:1508), TRUSTED, in-cluster`
- Observations: none

### `_forwardToExt/function` — CauldronRegistry.sol:1517

- Signature: `function _forwardToExt() private`
- Authority: internal (callers: rotateSlice, rotateSliceFrom, setRotationWiring, sweepLegProceeds, redeemOgFren, buyTreasuryOgFren, donateToReserve, materializeLegacyReserve, _forwardToExtView)
- Gate evidence: `if (ext == address(0)) revert NotConfigured(); (CauldronRegistry.sol:1518)`
- Reads: `redemptionExt (line 1518)`
- Writes: none
- Value: NONE directly; the delegatecalled code executes with this registry's balances and position custody
- Reachability: The single door to the facet. It rejects an unset target at `ext` CauldronRegistry.sol:1518, because a delegatecall to an empty account would return success with empty data and silently no-op. The full calldata is copied verbatim at `calldatasize` CauldronRegistry.sol:1521 and returndata or revert data is bubbled unchanged at `returndatasize` CauldronRegistry.sol:1523. The target is whatever was frozen in at `redemptionExt` CauldronRegistry.sol:1518, and it has unrestricted write access to every slot of this contract (DERIVED). It forwards all remaining gas (`gas` CauldronRegistry.sol:1522).
- Edges: none
- Observations: comment at `fallback` CauldronRegistry.sol:1844 says the fallback delegatecalls any unknown selector to the facet; code at `receive` CauldronRegistry.sol:575 declares only a receive function and each facet entry is an explicit stub such as `floorClaimableNow` CauldronRegistry.sol:1484, which the note at `fallback` CauldronRegistry.sol:1473 also states.

### `setCollectionLedger/function` — CauldronRegistry.sol:1539

- Signature: `function setCollectionLedger(address ledger) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:1539)`
- Reads: none
- Writes: `collectionLedger (line 1540)`
- Value: NONE
- Reachability: Owner-only, unvalidated and replaceable despite the one-time wording: `collectionLedger` CauldronRegistry.sol:1540 accepts any address and can be written again. Zero keeps the legacy floor off, which is what the two collection paths test at `collectionLedger` CauldronRegistry.sol:1540 and CauldronRegistry.sol:1540, and what the rebirth tests at `collectionLedger` CauldronRegistry.sol:1540.
- Edges: none
- Observations: none

### `_flushLegacyAtRelaunch/function` — CauldronRegistry.sol:1560

- Signature: `function _flushLegacyAtRelaunch(uint256 oldGen, address oldToken) private`
- Authority: internal (callers: relaunch)
- Gate evidence: `UNGATED`
- Reads: `positionManager (line 1563)`; `hook (line 1563)`; `collectionLedger (line 1564)`; `mifrens (line 1564)`; `genesisShares (line 1564)`; `generationCollection (line 1564)`; `genesisPending (line 1567)`
- Writes: `genesisPending (line 1567)`
- Value: NONE at this level; the library sweeps the hook's un-materialized buyback tokens for the dying generation and, with the deposit flag false, credits the ledger as a NUMBER instead of depositing them, inside `materializeLegacy` (line 1562)
- Reachability: Private and called from exactly one place, the ledger branch of the rebirth at `_flushLegacyAtRelaunch` CauldronRegistry.sol:1560, which itself only runs when `collectionLedger` CauldronRegistry.sol:1564 is non-zero. The burn path is selected by the trailing false argument at `empty` CauldronRegistry.sol:1561, so the reserve reference is unused. The OG share it returns is accumulated into `genesisPending` CauldronRegistry.sol:1567, which the same rebirth folds into the genesis reserve a few lines earlier in program order at `genesisPending` CauldronRegistry.sol:1567 — the fold happens BEFORE this flush in the source, so a flush's OG share lands in the NEXT rebirth's sizing (DERIVED).
- Edges: `PoolOps.materializeLegacy (CauldronRegistry.sol:1562), TRUSTED, library`
- Observations: comment at `Hook` CauldronRegistry.sol:1545 documents a hook-called recorder that is hook-only and no-ops without a ledger; code declares no such function here, and the next declaration is the private `_flushLegacyAtRelaunch` CauldronRegistry.sol:1560 reachable only from the rebirth.

### `recycleCollectionNFT/function` — CauldronRegistry.sol:1574

- Signature: `function recycleCollectionNFT(uint256 gen, uint256 tokenId) external nonReentrant returns (uint256 amount)`
- Authority: anyone owning the collection NFT (ownership enforced in the library)
- Gate evidence: `if (ICollectionOps(collection).ownerOf(tokenId) != caller) revert("not owner"); (PoolOps.sol:1584)`
- Reads: `generationCollection (line 1578)`; `collectionLedger (line 1582)`; `currentGeneration (line 1583)`; `positionManager (line 1585)`; `generationReservePositionId (line 1587)`; `generationPoolKey (line 1587)`; `reserveTickLower (line 1587)`; `reserveTickUpper (line 1587)`
- Writes: none
- Value: releases the collection's floor entitlement in the LIVE generation's token out of the shared reserve to the caller, and moves the NFT into this registry's custody, inside `recycleCollection` (line 1580)
- Reachability: Open to the NFT's owner. The circuit-breaker applies here (`_redeemBlocked` CauldronRegistry.sol:1577), and both the ledger and the generation's collection must be wired (`collectionLedger` CauldronRegistry.sol:1582). Payment is made in the CURRENT generation's token from the shared reserve position, read at `currentGeneration` CauldronRegistry.sol:1583, not in the token of the generation the NFT belongs to. The OG-tranche exclusion and the ownership check both live in the library at `recycleCollection` CauldronRegistry.sol:1580, and the reserve-short rollback is enforced there too.
- Edges: `CauldronBase._redeemBlocked (CauldronRegistry.sol:1577), TRUSTED, out-of-cluster`; `PoolOps.recycleCollection (CauldronRegistry.sol:1584), TRUSTED, library`
- Observations: none

### `buyCollectionNFT/function` — CauldronRegistry.sol:1595

- Signature: `function buyCollectionNFT(uint256 gen, uint256 tokenId) external nonReentrant returns (uint256 paid)`
- Authority: anyone (the NFT must currently sit in this registry's treasury)
- Gate evidence: `if (ICollectionOps(collection).ownerOf(tokenId) != address(this)) revert("not treasury"); (PoolOps.sol:1637)`
- Reads: `generationCollection (line 1598)`; `collectionLedger (line 1599)`; `currentGeneration (line 1600)`; `positionManager (line 1602)`; `generationToken (line 1603)`; `generationReservePositionId (line 1604)`; `generationPoolKey (line 1604)`; `reserveTickLower (line 1604)`; `reserveTickUpper (line 1604)`
- Writes: none
- Value: pulls twice the NFT's floor in the live token from the buyer into the reserve and hands the NFT over, inside `buyCollection` (line 1601)
- Reachability: Open to anyone. Unlike the recycle side it does NOT consult the redemption circuit-breaker: there is no `_redeemBlocked` CauldronRegistry.sol:1577 equivalent in this body (DERIVED). Preconditions are only a wired ledger and a known collection at `collectionLedger` CauldronRegistry.sol:1599. The payment token is the LIVE generation's, read at `generationToken` CauldronRegistry.sol:1603, and the price is derived from the ledger floor inside the library rather than supplied by the caller.
- Edges: `PoolOps.buyCollection (CauldronRegistry.sol:1601), TRUSTED, library`
- Observations: none

### `_removeLiquidity/function` — CauldronRegistry.sol:1618

- Signature: `function _removeLiquidity(uint256 gen) private returns (uint256 ethRecovered, uint256 tokensRecovered)`
- Authority: internal (callers: relaunch)
- Gate evidence: `UNGATED`
- Reads: `generationPoolKey (line 1622)`; `generationToken (line 1623)`; `positionManager (line 1624)`; `generationPositionId (line 1628)`; `generationReservePositionId (line 1633)`; `seeder (line 1646)`; `redemptionExt (line 1665)`; `RECOVER_LEGS (line 1673, constant)`
- Writes: none
- Value: recovers both sides of the active and reserve positions into this registry through `removeAll` (line 1630) and (line 1635); recovers the streamed book through `withdrawAll` (line 1648); recovers every rotated leg through the delegatecall at `RECOVER_LEGS` (line 1673)
- Reachability: Private, reached from the rebirth (the break-glass pull now does the same teardown in the facet). Four recovery sources are summed into one pair of totals: the active position, skipped when its id is zero (`activeId` CauldronRegistry.sol:1628); the reserve position (`rid` CauldronRegistry.sol:1633); the seeder's bands, only while it reports itself active (`seeding` CauldronRegistry.sol:1647); and the rotated legs via a delegatecall to the ungated teardown entry whose failure is swallowed (`ok` CauldronRegistry.sol:1674). The leg selector is compiler-computed (`RECOVER_LEGS` CauldronRegistry.sol:71) because a wrong selector would fail silently through that swallow. Totals are in the primary pair's currency0.
- Edges: `PoolOps.removeAll (CauldronRegistry.sol:1630), TRUSTED, library`; `PoolOps.removeAll (CauldronRegistry.sol:1635), TRUSTED, library`; `ISeeder.seeding (CauldronRegistry.sol:1647), TRUSTED, out-of-cluster`; `ISeeder.withdrawAll (CauldronRegistry.sol:1648), TRUSTED, out-of-cluster`; `RedemptionExt.recoverLegsAtTeardown (RedemptionExt.sol:1048), TRUSTED, delegatecall`
- Observations: none

### `_deployToken/function` — CauldronRegistry.sol:1692

- Signature: `function _deployToken( string memory name, string memory symbol, uint256 gen, address want ) private returns (address token, address quoteUsed)`
- Authority: internal (callers: summon, relaunch)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE; the deployed token mints its entire fixed supply to this registry inside its own constructor
- Reachability: Private, called once per generation from `_deployToken` CauldronRegistry.sol:1692 and CauldronRegistry.sol:1692. It is delegatecalled into the library so `address(this)` stays this registry, making the registry both the deployer and the holder of the whole supply. It returns the quote that was ACTUALLY achievable rather than the one requested (`quoteUsed` CauldronRegistry.sol:1697), and the caller records that value, which is why a mining failure downgrades the generation to native ether instead of reverting.
- Edges: `PoolOps.deployTokenAbove (CauldronRegistry.sol:1707), TRUSTED, library`
- Observations: comment at `CREATE2` CauldronRegistry.sol:1701 says this uses plain CREATE and NOT CREATE2 because a predictable address could be squatted; code at `salt` PoolOps.sol:742 deploys with CREATE2 from a mined salt, and the note two lines below at `CREATE2` CauldronRegistry.sol:1701 calls the registry the CREATE2 deployer.

### `_createPoolAndSeedWithBuy/function` — CauldronRegistry.sol:1737

- Signature: `function _createPoolAndSeedWithBuy( address token, uint256 activeTokens, uint256 ethAmount, uint256 reserveTokens, uint256 gen ) private returns (PoolId poolId)`
- Authority: internal (callers: _seedGeneration)
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 1748)`; `positionManager (line 1748)`; `hook (line 1748)`; `nextReserveCeilingOffset (line 1750)`; `generationQuote (line 1751)`
- Writes: none
- Value: pays the whole funded amount and the active token tranche into the new pool, then buys the reserve back out as a visible first-block trade, inside `createAndSeedWithBuy` (line 1747)
- Reachability: Private, reached only from the atomic branch at `_createPoolAndSeedWithBuy` CauldronRegistry.sol:1737. It does NOT arm the callback window itself; the caller hoisted that, so it relies on `_seedBuyUnlocked` CauldronRegistry.sol:1745 already being set. The per-iteration ceiling comes from `nextReserveCeilingOffset` CauldronRegistry.sol:1750 and the pair from `generationQuote` CauldronRegistry.sol:1751, which the rebirth wrote before seeding at CauldronRegistry.sol:1751.
- Edges: `PoolOps.createAndSeedWithBuy (CauldronRegistry.sol:1747), TRUSTED, library`; `CauldronRegistry._recordSeed (CauldronRegistry.sol:1753), TRUSTED, in-cluster`
- Observations: none

### `_seedGeneration/function` — CauldronRegistry.sol:1769

- Signature: `function _seedGeneration( address token, uint256 activeTokens, uint256 ethAmount, uint256 reserveTokens, uint256 gen ) private returns (PoolId poolId)`
- Authority: internal (callers: summon, relaunch)
- Gate evidence: `UNGATED`
- Reads: `seeder (line 1767)`; `nextSeedWindow (line 1788)`; `poolManager (line 1790)`; `positionManager (line 1790)`; `hook (line 1790)`; `nextReserveCeilingOffset (line 1792)`; `seeder (line 1767)`; `nextSeedWindow (line 1788)`; `generationQuote (line 1794)`
- Writes: `_seedBuyUnlocked (line 1787)`; `_seedBuyUnlocked (line 1787)`
- Value: hands the active tranche plus the funding to either the streaming seeder or the atomic green-candle seed; on the progressive branch the token side leaves this registry for the seeder inside `createAndSeedProgressive` (line 1777)
- Reachability: Private, the single seed dispatcher for both ignition (`_seedGeneration` CauldronRegistry.sol:1769) and every rebirth (CauldronRegistry.sol:1769). It arms the PoolManager callback window for BOTH branches at `_seedBuyUnlocked` CauldronRegistry.sol:1787 and clears it unconditionally at CauldronRegistry.sol:1787, so the window is open for the whole seed rather than just the buy. The branch is taken only when a seeder is set AND the window is non-zero (`nextSeedWindow` CauldronRegistry.sol:1788); anything else falls through to the atomic path at `_createPoolAndSeedWithBuy` CauldronRegistry.sol:1785. A non-native generation is handled inside the library rather than here (`createAndSeedProgressive` CauldronRegistry.sol:1777).
- Edges: `PoolOps.createAndSeedProgressive (CauldronRegistry.sol:1789), TRUSTED, library`; `CauldronRegistry._recordSeed (CauldronRegistry.sol:1796), TRUSTED, in-cluster`; `CauldronRegistry._createPoolAndSeedWithBuy (CauldronRegistry.sol:1798), TRUSTED, in-cluster`
- Observations: comment at `_createPoolAndSeedWithBuy` CauldronRegistry.sol:1785 says BOTH genesis and relaunch now use the green-candle seed; code at `createAndSeedProgressive` CauldronRegistry.sol:1777 takes a different library entry whenever a seeder is set and `nextSeedWindow` CauldronRegistry.sol:1788 is non-zero.

### `_recordSeed/function` — CauldronRegistry.sol:1806

- Signature: `function _recordSeed(SeedResult memory r, uint256 gen) private returns (PoolId poolId)`
- Authority: internal (callers: _seedGeneration, _createPoolAndSeedWithBuy)
- Gate evidence: `UNGATED`
- Reads: `hook (line 1804)`
- Writes: `generationPoolId (line 1808)`; `generationPoolKey (line 1809)`; `generationPositionId (line 1810)`; `generationReservePositionId (line 1811)`; `reserveTickLower (line 1812)`; `reserveTickUpper (line 1813)`
- Value: NONE
- Reachability: Private bookkeeping, reached from both seed branches at `_recordSeed` CauldronRegistry.sol:1806 and CauldronRegistry.sol:1806. It is the only writer of the six per-generation position fields, including `generationPositionId` CauldronRegistry.sol:1810, which stays zero for a streamed generation and is what the teardown checks at `activeId` CauldronRegistry.sol:1628. It then pushes the live key to the hook at `setLiveKey` CauldronRegistry.sol:1814 so the legacy buyback can only spend into the current pool; that call is not wrapped, so a hook that refuses the key reverts the seed (DERIVED).
- Edges: `CauldronHook.setLiveKey (CauldronRegistry.sol:1814), TRUSTED, out-of-cluster`
- Observations: none

### `unlockCallback/function` — CauldronRegistry.sol:1824

- Signature: `function unlockCallback(bytes calldata data) external returns (bytes memory)`
- Authority: poolManager, and only while the seed-buy window is armed
- Gate evidence: `if (msg.sender != address(poolManager)) revert NotPoolManager(); (CauldronRegistry.sol:1824)`
- Reads: `poolManager (line 1825)`; `_seedBuyUnlocked (line 1826)`
- Writes: none
- Value: spends this registry's quote side and receives the bought token, inside `executeBuy` (line 1827)
- Reachability: Two independent conditions, both mandatory: the caller must be the PoolManager (`poolManager` CauldronRegistry.sol:1825) and the transient window must be open (`_seedBuyUnlocked` CauldronRegistry.sol:1826). The window is opened by the seed dispatcher at `_seedBuyUnlocked` CauldronRegistry.sol:1826 and by the ignition prime buy at `_seedBuyUnlocked` CauldronRegistry.sol:1826, and it is a plain storage bool rather than a transient slot, so it is set and cleared within the same transaction (DERIVED). The swap encoding lives entirely in the delegatecalled library at `executeBuy` CauldronRegistry.sol:1827, so it runs on this registry's balances.
- Edges: `PoolOps.executeBuy (CauldronRegistry.sol:1827), TRUSTED, library`
- Observations: comment at `relaunch` CauldronRegistry.sol:1764 says the callback is accepted ONLY while a relaunch buy is armed; code at `_seedBuyUnlocked` CauldronRegistry.sol:1826 accepts it whenever the flag is set, and ignition also sets it, at `_seedBuyUnlocked` CauldronRegistry.sol:1826 and CauldronRegistry.sol:1826.


## `CauldronToken`

### `constructor/constructor` — CauldronToken.sol:36

- Signature: `constructor( string memory _name, string memory _symbol, uint256 _generation, address _registry, uint256 _initialSupply ) ERC20(_name, _symbol)`
- Authority: deployer (the registry, acting through the delegatecalled PoolOps deploy)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `generation (line 43, immutable)`; `birthBlock (line 44, immutable)`; `registry (line 45, immutable)`
- Value: NONE in native terms; the entire initial supply is minted to the registry at `_mint` (line 46)
- Reachability: Reached only from the generation deploy inside the linked library, at `CauldronToken` PoolOps.sol:668 for the mined CREATE2 path and `CauldronToken` PoolOps.sol:767 for the unmined fallback. Because the library is delegatecalled, address(this) is the registry, so the `registry` CauldronToken.sol:45 recorded here and the mint recipient are the same contract that orchestrates the generation. There is no minting function afterwards, so supply can only ever fall (DERIVED).
- Edges: none
- Observations: comment at `TOTAL_SUPPLY` CauldronToken.sol:29 declares a fixed 777 million supply as a constant; code at `_initialSupply` CauldronToken.sol:46 mints whatever amount the deployer passes and never compares it with that constant.

### `onlyRegistry/modifier` — CauldronToken.sol:49

- Signature: `modifier onlyRegistry()`
- Authority: internal (callers: burn)
- Gate evidence: `if (msg.sender != registry) revert NotRegistry(); (CauldronToken.sol:49)`
- Reads: `registry (line 50, immutable)`
- Writes: none
- Value: NONE
- Reachability: The token's only access control. `registry` CauldronToken.sol:50 is immutable, fixed at construction from the deploying contract at CauldronToken.sol:50, so the role can never be transferred or revoked (DERIVED). It guards exactly one function, `burn` CauldronToken.sol:58.
- Edges: none
- Observations: none

### `burn/function` — CauldronToken.sol:58

- Signature: `function burn(address from, uint256 amount) external onlyRegistry`
- Authority: registry
- Gate evidence: `onlyRegistry (CauldronToken.sol:58)`
- Reads: `registry (line 50, immutable)`
- Writes: none
- Value: destroys `amount` of the named holder's balance, reducing total supply (line 59)
- Reachability: Callable only by the immutable registry (`onlyRegistry` CauldronToken.sol:58). It needs no allowance and names an arbitrary holder, so it is the primitive behind both the dead-LP burn at `burn` CauldronRegistry.sol:862 and the 1:1 migration burns issued through the library at `burn` PoolOps.sol:1386 and PoolOps.sol:1386. The keeper batch reaches it for an opted-in wallet without that wallet signing anything, which is why the opt-in flag is revocable at `autoMigrate` CauldronRegistry.sol:1356.
- Edges: none
- Observations: comment at `leftovers` CauldronToken.sol:56 lists burning unclaimed migration leftovers as a use of this function; code at `burnUnclaimed` CauldronRegistry.sol:1424 records that path as obsolete in the reserve-LP model, and no such caller remains in the registry.


## `ICollectionRenderer (declared in ICauldron.sol)`

### `tokenURI/function` — ICauldron.sol:12

- Signature: `function tokenURI(uint256 tokenId) external view returns (string memory)`
- Authority: anyone (view on a proposer-supplied renderer contract)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; no body here. It is consumed by the collections' metadata path at `tokenURI` CauldronCollection.sol:379 and `tokenURI` MiFrensGenesis.sol:854, and for badges at `tokenURI` CauldronCollection.sol:379. The address comes from the winning proposal, copied at `renderer` CauldronRegistry.sol:897 and handed to the factory config at `renderer` CauldronRegistry.sol:1219, so it is proposer-controlled code (DERIVED).
- Edges: none
- Observations: none


## `LaunchLib (declared in ICauldron.sol)`

### `displayName/function` — ICauldron.sol:38

- Signature: `function displayName(string memory name) internal pure returns (string memory)`
- Authority: internal (callers: summon, relaunch)
- Gate evidence: `UNGATED`
- Reads: `GUILD_SUFFIX (line 39, constant)`
- Writes: none
- Value: NONE
- Reachability: Pure and internal, so it is inlined into its callers: ignition at `displayName` CauldronRegistry.sol:739 and every rebirth at `displayName` CauldronRegistry.sol:964. The suffix is the file constant read at `GUILD_SUFFIX` ICauldron.sol:39, never a parameter, so a proposer controls only the prefix. The proposer's raw name is unbounded in length, and this concatenation is what the token and collection are then constructed with (DERIVED).
- Edges: none
- Observations: none


## `ICauldronGovernor (declared in ICauldron.sol)`

### `winner/function` — ICauldron.sol:45

- Signature: `function winner() external view returns (uint256 proposalId, BrewSpec memory spec)`
- Authority: anyone (view); the registry is its only in-tree caller
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the read the rebirth takes at `winner` CauldronRegistry.sol:900. The implementation at `winner` CauldronGovernor.sol:340 selects the best unconsumed proposal at `_bestUnconsumed` CauldronGovernor.sol:192 and reverts when there is none, which is why the rebirth checks liveness first at `hasProposals` CauldronRegistry.sol:838. Everything in the returned spec is proposer-authored, including the quote and the renderer (DERIVED).
- Edges: none
- Observations: none

### `markConsumed/function` — ICauldron.sol:46

- Signature: `function markConsumed(uint256 proposalId) external`
- Authority: registry (the implementation restricts the caller)
- Gate evidence: `if (msg.sender != registry) revert NotRegistry(); (CauldronGovernor.sol:763)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the one state-changing governor call the registry makes, at `markConsumed` CauldronRegistry.sol:1008. The implementation at `markConsumed` CauldronGovernor.sol:529 accepts only the wired registry and refuses a second consumption at `consumed` CauldronGovernor.sol:622. Its placement in the rebirth is load-bearing: anything that reverts after it rolls the consumption back with the transaction, which is why the only remaining revert sits immediately before it at `totalETH` CauldronRegistry.sol:989.
- Edges: none
- Observations: none

### `hasProposals/function` — ICauldron.sol:47

- Signature: `function hasProposals() external view returns (bool)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the liveness gate the rebirth applies at `hasProposals` CauldronRegistry.sol:838, alongside a zero-address check on the governor itself. The implementation at `hasProposals` CauldronGovernor.sol:336 simply reports whether an unconsumed proposal exists at `_bestUnconsumed` CauldronGovernor.sol:740.
- Edges: none
- Observations: none


## `ICauldronCollection (declared in ICauldron.sol)`

### `mint/function` — ICauldron.sol:52

- Signature: `function mint(address to) external returns (uint256 tokenId)`
- Authority: the collection's wired minter (the volume hook)
- Gate evidence: `if (msg.sender != minter) revert OnlyMinter(); (CauldronCollection.sol:208)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the mint the hook performs when a play wins, at `mint` CauldronHook.sol:2595. The implementation at `mint` CauldronCollection.sol:207 accepts only the wired minter and refuses once the cap is reached at `maxSupply` CauldronCollection.sol:209. The registry is what wires the hook in, at `setCollection` CauldronRegistry.sol:1245 for a fresh brew and at `setMinter` CauldronRegistry.sol:1271 for the continuation.
- Edges: none
- Observations: none

### `totalMinted/function` — ICauldron.sol:53

- Signature: `function totalMinted() external view returns (uint256)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration satisfied by a public state variable rather than a written function: the counter is incremented in place at `totalMinted` CauldronCollection.sol:210, so the interface is served by the compiler-generated getter (DERIVED). The hook reads it for the curve anchor at `totalMinted` CauldronHook.sol:2327 and for mint-out checks at `totalMinted` CauldronHook.sol:2327.
- Edges: none
- Observations: none

### `maxSupply/function` — ICauldron.sol:54

- Signature: `function maxSupply() external view returns (uint256)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the per-brew cap the hook compares against at `maxSupply` CauldronHook.sol:2442 and CauldronHook.sol:2442. The value originates in the registry, either from the owner setting at `nftMaxSupply` CauldronRegistry.sol:599 or from the proposer's request clamped at `MAX_NFT_SUPPLY` CauldronRegistry.sol:959, and it is fixed when the collection is constructed (DERIVED).
- Edges: none
- Observations: none


## `IDeathChecker`

### `isDead/function` — IDeathChecker.sol:27

- Signature: `function isDead(PoolId id, uint256 volume24h, uint256 deathThreshold) external view returns (bool dead)`
- Authority: anyone (view on a pluggable module)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the swappable death rule. The hook calls it only when one is wired, inside a try/catch at `isDead` CauldronHook.sol:1740, and falls back to the built-in volume comparison at `deathThreshold` CauldronHook.sol:1893 on any revert, so a broken module cannot brick the rebirth. The volume it is handed is summed across a generation's sibling pools at `getVolume24h` CauldronHook.sol:1766. The registry's rebirth gate consumes the answer at `isDead` CauldronRegistry.sol:830.
- Edges: none
- Observations: comment at `owner` IDeathChecker.sol:13 says the hook owner points the hook at a new checker; code at `registry` CauldronHook.sol:1977 accepts the registry address as well as the owner.


## `ILiquidatorMintable`

### `mintLiquidatorWithStats/function` — ILiquidatorMintable.sol:38

- Signature: `function mintLiquidatorWithStats(address to, LiqStats calldata s) external returns (uint256 tokenId)`
- Authority: the collection's wired liquidatorMinter (the perp engine)
- Gate evidence: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (CauldronCollection.sol:409)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only. The implementation at `mintLiquidatorWithStats` CauldronCollection.sol:402 forwards to `_mintLiquidator` CauldronCollection.sol:397, where the single caller check lives. Badge ids come from a separate range at `LIQUIDATOR_ID_BASE` CauldronCollection.sol:394, so the art tranche's counters are untouched, and the stats write is skipped entirely for a zero victim at `victim` CauldronCollection.sol:415.
- Edges: none
- Observations: none

### `mintLiquidator/function` — ILiquidatorMintable.sol:44

- Signature: `function mintLiquidator(address to) external returns (uint256 tokenId)`
- Authority: the collection's wired liquidatorMinter (the perp engine)
- Gate evidence: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (CauldronCollection.sol:409)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: The stats-free form, kept for an engine deployed before the stats existed. The implementation at `mintLiquidator` CauldronCollection.sol:396 passes an all-zero record into the same internal path at `_mintLiquidator` CauldronCollection.sol:397, so the gate and the id range are identical to the stats form (`liquidatorMinter` CauldronCollection.sol:353).
- Edges: none
- Observations: none

### `liqStats/function` — ILiquidatorMintable.sol:47

- Signature: `function liqStats(uint256 tokenId) external view returns (LiqStats memory)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Open read of what a badge commemorates, implemented at `liqStats` CauldronCollection.sol:421 over the mapping the mint writes at `_liqStats` CauldronCollection.sol:415. A stats-free mint leaves the record zeroed, so the reader cannot distinguish absent from zero (DERIVED).
- Edges: none
- Observations: none


## `ISurtaxPolicy (declared in IPolicies.sol)`

### `surtaxBps/function` — IPolicies.sol:25

- Signature: `function surtaxBps(PoolId id, uint256 initBlock, uint256 maxBps, uint256 windowBlocks) external view returns (uint256 bps)`
- Authority: anyone (view on a pluggable module)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the anti-sniper surtax rule. The hook consults it only when wired, through the linked library, inside a try/catch at `surtaxBps` SurtaxLib.sol:46, with the hook passing its own configured peak and window at `MAX_SNIPE_BPS` CauldronHook.sol:1656 so a simple module can reuse them. The module is installed by the owner or the registry at `surtaxPolicy` CauldronHook.sol:2223. It returns a number and never custodies funds, so a malicious module's blast radius is the fee rate it reports (DERIVED).
- Edges: none
- Observations: none


## `IOddsPolicy (declared in IPolicies.sol)`

### `oddsBps/function` — IPolicies.sol:37

- Signature: `function oddsBps(uint256 playWei, uint256 maxBps, uint256 fullVolumeWei) external view returns (uint256 bps)`
- Authority: anyone (view on a pluggable module)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the gacha win-probability rule, consulted inside a try/catch at `oddsBps` CauldronHook.sol:2514 and installed alongside the other two modules at `oddsPolicy` CauldronHook.sol:2224. The play size it receives is denominated in the units the hook measures a play in, which is the same unit its own configured full-volume threshold uses (DERIVED).
- Edges: none
- Observations: none


## `ICurvePolicy (declared in IPolicies.sol)`

### `priceAt/function` — IPolicies.sol:49

- Signature: `function priceAt(uint256 k, uint256 base, uint256 step) external view returns (uint256 cost)`
- Authority: anyone (view on a pluggable module)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the mint-cost curve, consulted by a bounded one-word STATICCALL from `nftPriceAt` with the hook's own base and step (`priceAt` CauldronHook.sol:2459), and installed at `curvePolicy` CauldronHook.sol:2225. The base the hook passes is the value the registry pushes from the winning proposal at `setNftCurveFrom` CauldronRegistry.sol:1148.
- Edges: none
- Observations: none


## `IFeeRouter (declared in IPolicies.sol)`

### `route/function` — IPolicies.sol:70

- Signature: `function route(uint256 feeAmount, address guild, address vault, uint256 guildBps, uint256 floorBps) external view returns (uint256 toGuild, uint256 toFloor, uint256 toRelaunch)`
- Authority: anyone (view on a pluggable module)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE; the module only returns amounts, and the hook performs every send itself
- Reachability: Declaration of the fee-split structure. The hook calls it in a try/catch at `route` CauldronHook.sol:1399 and accepts the answer ONLY when the three parts sum exactly to the fee at `feeAmount` CauldronHook.sol:1479; otherwise it falls through to the built-in split at `wantGuild` CauldronHook.sol:1532. The router is installed by the owner or the registry at `feeRouter` CauldronHook.sol:2235, and the reference implementation makes the sum exact by construction at `toRelaunch` DefaultFeeRouter.sol:24.
- Edges: none
- Observations: none
