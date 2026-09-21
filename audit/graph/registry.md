# Function graph — `registry`

Current source-derived semantic map: **89 nodes** across **6 files**. The JSON file is canonical; this document renders every semantic field for review.

## Source files

| file | lines |
|---|---:|
| `CauldronRegistry.sol` | 1844 |
| `CauldronToken.sol` | 61 |
| `cauldron/ICauldron.sol` | 55 |
| `cauldron/IDeathChecker.sol` | 31 |
| `cauldron/ILiquidatorMintable.sol` | 48 |
| `cauldron/IPolicies.sol` | 74 |

## `ICollectionMetadata (declared in CauldronRegistry.sol)`

### `setMetadata` — CauldronRegistry.sol:60

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

### `constructor` — CauldronRegistry.sol:164

- Signature: `constructor( address _poolManager, address _positionManager, address _hook, address _emergencyAdmin, uint256 _emergencyDelay )`
- Authority: deployer
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `poolManager (line 173)`; `positionManager (line 174)`; `hook (line 175)`; `emergencyAdmin (line 177, immutable)`; `emergencyDelay (line 178, immutable)`; `allowedQuote (line 181)`; `quoteScale (line 182)`
- Value: NONE
- Reachability: Runs once at deploy. It writes the three former immutables as STORAGE so the delegatecall facet reads them correctly: `poolManager` CauldronRegistry.sol:173, `positionManager` CauldronRegistry.sol:174 and `hook` CauldronRegistry.sol:175. `emergencyAdmin` CauldronRegistry.sol:177 falls back to msg.sender when the argument is zero, and `emergencyDelay` CauldronRegistry.sol:178 is immutable so it can never be lowered afterwards. Native ether is seeded into the quote allowlist with `allowedQuote` CauldronRegistry.sol:181 and a 1e18 identity in `quoteScale` CauldronRegistry.sol:182, so a fresh deployment can always launch against ether. Ownership comes from the base constructor at `Ownable` CauldronBase.sol:437, which makes the deployer the owner (DERIVED).
- Edges: none
- Observations: none

### `setRedemptionExt` — CauldronRegistry.sol:190

- Signature: `function setRedemptionExt(address ext) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:190)`
- Reads: `redemptionExt (line 196)`
- Writes: `redemptionExt (line 196)`
- Value: NONE
- Reachability: Owner-only and one-shot: `redemptionExt` CauldronRegistry.sol:196 must still be zero or the call reverts AlreadySummoned, so the delegatecall target is frozen after the first write at `redemptionExt` CauldronRegistry.sol:196. A code-less target is rejected at `ext` CauldronRegistry.sol:190 because a delegatecall to an empty account returns success with no data. Every facet forwarder in this file depends on this having been set (DERIVED).
- Edges: none
- Observations: none

### `setReserveCeiling` — CauldronRegistry.sol:203

- Signature: `function setReserveCeiling(int24 offset) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:203)`
- Reads: none
- Writes: `nextReserveCeilingOffset (line 205)`
- Value: NONE
- Reachability: Owner-only. Bounds-checked at `offset` CauldronRegistry.sol:202 then stored in `nextReserveCeilingOffset` CauldronRegistry.sol:205, which the next seed reads at `nextReserveCeilingOffset` CauldronRegistry.sol:205 and CauldronRegistry.sol:205. It takes effect on the NEXT summon or relaunch only (DERIVED).
- Edges: none
- Observations: none

### `rotateSlice` — CauldronRegistry.sol:246

- Signature: `function rotateSlice(uint16, uint256, PoolKey calldata) external returns (uint256, uint256)`
- Authority: anyone at the registry; the facet holds the gate (RedemptionExt.rotateSliceFrom requires rotation wiring plus a live treasury-vote envelope)
- Gate evidence: `if (remaining == 0) revert NoRotationApproved(); (RedemptionExt.sol:316)`
- Reads: `redemptionExt (line 1501)`
- Writes: none
- Value: NONE in this stub; the value movement happens inside the delegatecalled facet, which runs on this registry's own custody
- Reachability: A three-argument stub whose whole body is `_forwardToExt` CauldronRegistry.sol:247, which delegatecalls the facet with the untouched calldata. It lands on `rotateSlice` RedemptionExt.sol:269, which immediately tail-calls `rotateSliceFrom` RedemptionExt.sol:274 with fromLeg hard-coded to 0, so this entry can only ever drain the primary pool. The registry side is ungated; the facet side requires `quoteRotator` RedemptionExt.sol:292 and `treasuryGovernor` RedemptionExt.sol:301 to be wired and the guild's envelope to have room at `remaining` RedemptionExt.sol:317.
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:247), TRUSTED, in-cluster`; `RedemptionExt.rotateSlice (CauldronRegistry.sol:246), TRUSTED, delegatecall`
- Observations: none

### `rotateSliceFrom` — CauldronRegistry.sol:270

- Signature: `function rotateSliceFrom(uint8, uint16, uint256, PoolKey calldata) external returns (uint256, uint256)`
- Authority: anyone at the registry; the facet holds the gate (RedemptionExt.rotateSliceFrom requires rotation wiring plus a live treasury-vote envelope)
- Gate evidence: `if (remaining == 0) revert NoRotationApproved(); (RedemptionExt.sol:316)`
- Reads: `redemptionExt (line 1501)`
- Writes: none
- Value: NONE in this stub; the value movement happens inside the delegatecalled facet, which runs on this registry's own custody
- Reachability: The four-argument form. Body is `_forwardToExt` CauldronRegistry.sol:274 and it reaches `rotateSliceFrom` RedemptionExt.sol:280, which is public on the facet. The gate is entirely facet-side: wiring at `rot` RedemptionExt.sol:293, a governor at `gov` RedemptionExt.sol:302, a non-zero envelope at `remaining` RedemptionExt.sol:317 and a slice within it at `sliceBps` RedemptionExt.sol:318. Timing is the only thing the caller chooses; destination and ceiling come from the vote (`allowance` RedemptionExt.sol:303).
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:274), TRUSTED, in-cluster`; `RedemptionExt.rotateSliceFrom (RedemptionExt.sol:280), TRUSTED, delegatecall`
- Observations: none

### `setRotationWiring` — CauldronRegistry.sol:280

- Signature: `function setRotationWiring(address, address) external`
- Authority: owner (the gate is on the facet: RedemptionExt.setRotationWiring is onlyOwner and runs against this registry's owner slot)
- Gate evidence: `external onlyOwner (RedemptionExt.sol:260)`
- Reads: `redemptionExt (line 1501)`
- Writes: none
- Value: NONE
- Reachability: Stub for `setRotationWiring` RedemptionExt.sol:260. Because the forward is a delegatecall, the facet's `onlyOwner` resolves against this registry's own owner slot, and the writes to `quoteRotator` RedemptionExt.sol:262 and `treasuryGovernor` RedemptionExt.sol:263 land in this registry's storage. Both arguments must be non-zero (`rotator` RedemptionExt.sol:261). Not one-shot: the wiring can be replaced (DERIVED).
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:280), TRUSTED, in-cluster`; `RedemptionExt.setRotationWiring (CauldronRegistry.sol:280), TRUSTED, delegatecall`
- Observations: none

### `recoverLegs` — CauldronRegistry.sol:296

- Signature: `function recoverLegs(uint256) external returns (uint256, uint256)`
- Authority: anyone at the registry; the facet holds the only gate (RedemptionExt.recoverLegs refuses generation 0 and the live generation)
- Gate evidence: `if (gen == 0 || gen >= currentGeneration) revert CannotClaimCurrentGen(); (RedemptionExt.sol:848)`
- Reads: `redemptionExt (line 1501)`
- Writes: none
- Value: NONE in this stub; the facet moves the recovered leg balances under delegatecall, so they land in this registry's own custody
- Reachability: New forwarder stub for the leg-unwind retry. The whole body is `_forwardToExt` CauldronRegistry.sol:296, which delegatecalls `recoverLegs` RedemptionExt.sol:834 on this registry's storage and custody. The gate is entirely facet-side: past generations only at `currentGeneration` RedemptionExt.sol:725, then the recovery at `_recoverLegs` RedemptionExt.sol:850 and the booking of its proceeds at `_bookLegProceeds` RedemptionExt.sol:851. This registry has no fallback, so before the stub existed the selector had no entry at all and the facet's own `recoverLegs` RedemptionExt.sol:834, though `public`, would run against the facet's empty storage (comment at `recoverLegs` CauldronRegistry.sol:296 records exactly that).
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:296), TRUSTED, in-cluster`; `RedemptionExt.recoverLegs (RedemptionExt.sol:878), TRUSTED, delegatecall`
- Observations: none

### `sweepLegProceeds` — CauldronRegistry.sol:306

- Signature: `function sweepLegProceeds(address, address) external returns (uint256)`
- Authority: owner (the gate is on the facet: RedemptionExt.sweepLegProceeds is onlyOwner)
- Gate evidence: `external onlyOwner returns (uint256 amount) (RedemptionExt.sol:997)`
- Reads: `redemptionExt (line 1501)`
- Writes: none
- Value: NONE in this stub; the facet sends the booked asset out of this registry's balance
- Reachability: Stub for `sweepLegProceeds` RedemptionExt.sol:864. Owner-gated facet-side; it zeroes `legProceeds` RedemptionExt.sol:883 before calling `sendAsset` RedemptionExt.sol:1006, so the balance leaves this registry's custody to an owner-chosen recipient. The matching reader `legProceedsOf` RedemptionExt.sol:961 has no stub here, and this contract declares no fallback (`receive` CauldronRegistry.sol:578), so that reader is unreachable through the registry.
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:306), TRUSTED, in-cluster`; `RedemptionExt.sweepLegProceeds (RedemptionExt.sol:1028), TRUSTED, delegatecall`
- Observations: none

### `setAllowedQuote` — CauldronRegistry.sol:314

- Signature: `function setAllowedQuote(address quote, bool allowed, uint256 scale) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:314)`
- Reads: none
- Writes: `allowedQuote (line 327)`; `quoteScale (line 329)`
- Value: NONE
- Reachability: Owner-only curation of the quote set a proposer may pick FROM. Native ether can never be removed (`quote` CauldronRegistry.sol:314) and an admitted quote must sort below the watermark (`QUOTE_WATERMARK` CauldronRegistry.sol:316) so every mined iteration token stays currency1. The flag is written at `allowedQuote` CauldronRegistry.sol:327 and, on admission only, a per-unit ether scale at `quoteScale` CauldronRegistry.sol:329 defaulting to 1e18. Relaunch re-reads the flag at `allowedQuote` CauldronRegistry.sol:327, so a de-listing between proposal and execution degrades the winner to native ether.
- Edges: none
- Observations: none

### `setSeeder` — CauldronRegistry.sol:333

- Signature: `function setSeeder(address _seeder) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:333)`
- Reads: `hook (line 335)`
- Writes: `seeder (line 334)`
- Value: NONE
- Reachability: Owner-only. Writes `seeder` CauldronRegistry.sol:334 and propagates the same address to the hook at `setSeeder` CauldronRegistry.sol:333 so afterSwap can nudge the stream. Setting it to zero turns progressive seeding off; the seed dispatcher tests both this and the window at `seeder` CauldronRegistry.sol:334.
- Edges: `CauldronHook.setSeeder (CauldronRegistry.sol:333), TRUSTED, out-of-cluster`
- Observations: none

### `rescueSeeder` — CauldronRegistry.sol:345

- Signature: `function rescueSeeder() external onlyEmergency timelocked nonReentrant`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency timelocked nonReentrant (CauldronRegistry.sol:345)`
- Reads: `seeder (line 344)`; `emergencyAdmin (line 370, immutable)`; `emergencyReadyAt (line 408)`; `emergencyDelay (line 407, immutable)`
- Writes: `emergencyReadyAt (line 408)`
- Value: receives native and/or token back from the seeder through `rescue` (line 348)
- Reachability: Break-glass path for an aborted progressive campaign. The caller must be the emergency admin (`emergencyAdmin` CauldronRegistry.sol:370) and must have armed the action first, since `_consumeTimelock` CauldronRegistry.sol:412 reverts when `emergencyReadyAt` CauldronRegistry.sol:408 is zero and clears it at CauldronRegistry.sol:408. A seeder must be configured (`s` CauldronRegistry.sol:346) before `rescue` CauldronRegistry.sol:348 pulls the seeder's loose ledger funds back to this registry.
- Edges: `ISeeder.rescue (CauldronRegistry.sol:348), TRUSTED, out-of-cluster`
- Observations: none

### `setSeedWindow` — CauldronRegistry.sol:356

- Signature: `function setSeedWindow(uint64 window) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:356)`
- Reads: none
- Writes: `nextSeedWindow (line 358)`
- Value: NONE
- Reachability: Owner-only. Either zero (atomic) or bounded to 60 seconds .. 7 days at `window` CauldronRegistry.sol:356, then stored at `nextSeedWindow` CauldronRegistry.sol:358. Progressive seeding fires only when this is non-zero AND a seeder is set, tested together at `nextSeedWindow` CauldronRegistry.sol:358.
- Edges: none
- Observations: none

### `enchantFee` — CauldronRegistry.sol:365

- Signature: `function enchantFee() external view returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `enchantFeeMultBps (line 366)`
- Writes: none
- Value: NONE
- Reachability: Open view. Multiplies the live floor from `floorPerFren` CauldronRegistry.sol:366 by `enchantFeeMultBps` CauldronRegistry.sol:366 over 10000. The multiplier is emergency-admin tunable at `enchantFeeMultBps` CauldronRegistry.sol:366, so the quoted fee moves with that setting.
- Edges: `CauldronBase.floorPerFren (CauldronRegistry.sol:366), TRUSTED, out-of-cluster`
- Observations: none

### `onlyEmergency` — CauldronRegistry.sol:369

- Signature: `modifier onlyEmergency()`
- Authority: internal (callers: rescueSeeder, armEmergency, setRedemptionPaused, setEnchantFeeMult, emergencyWithdrawLP, emergencySweep, setSuccessor, setClaimGate, migrateToSuccessor, setMinLifetime)
- Gate evidence: `if (msg.sender != emergencyAdmin) revert NotAdmin(); (CauldronRegistry.sol:369)`
- Reads: `emergencyAdmin (line 370, immutable)`
- Writes: none
- Value: NONE
- Reachability: The single break-glass gate. `emergencyAdmin` CauldronRegistry.sol:370 is immutable, set in the constructor at CauldronRegistry.sol:370, so this role can never be rotated or renounced after deploy. It is independent of `owner` CauldronRegistry.sol:437, which is the governance/timelock role.
- Edges: none
- Observations: none

### `timelocked` — CauldronRegistry.sol:378

- Signature: `modifier timelocked()`
- Authority: internal (callers: rescueSeeder, emergencyWithdrawLP, emergencySweep, migrateToSuccessor)
- Gate evidence: `_consumeTimelock(); (CauldronRegistry.sol:378)`
- Reads: `emergencyReadyAt (line 408)`; `emergencyDelay (line 407, immutable)`
- Writes: `emergencyReadyAt (line 408)`
- Value: NONE
- Reachability: Applied to the four custody-moving emergency actions. It consumes the arming BEFORE the body runs (`_consumeTimelock` CauldronRegistry.sol:379), so a revert inside the body rolls the consumption back with the transaction. Arming is always required even at zero delay (`emergencyReadyAt` CauldronRegistry.sol:408), which is what keeps the forced-open redemption exit in `_redeemBlocked` CauldronBase.sol:433 meaningful.
- Edges: `CauldronRegistry._consumeTimelock (CauldronRegistry.sol:379), TRUSTED, in-cluster`
- Observations: none

### `_consumeTimelock` — CauldronRegistry.sol:412

- Signature: `function _consumeTimelock() private`
- Authority: internal (callers: timelocked, setClaimGate)
- Gate evidence: `if (emergencyReadyAt == 0) revert Timelocked(); (CauldronRegistry.sol:412)`
- Reads: `emergencyReadyAt (line 413)`; `emergencyDelay (line 414, immutable)`
- Writes: `emergencyReadyAt (line 413)`
- Value: NONE
- Reachability: Two independent conditions: the action must be armed (`emergencyReadyAt` CauldronRegistry.sol:413) and, when the delay is non-zero, the wait must have elapsed (`emergencyDelay` CauldronRegistry.sol:414). It then zeroes the arming at `emergencyReadyAt` CauldronRegistry.sol:413, so each arming buys exactly one execution. The claim-gate setter invokes `_consumeTimelock` CauldronRegistry.sol:412 only in the restricting direction.
- Edges: none
- Observations: none

### `setIgniter` — CauldronRegistry.sol:420

- Signature: `function setIgniter(address who) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:420)`
- Reads: none
- Writes: `igniter (line 419)`
- Value: NONE
- Reachability: Owner-only, no bound and no one-shot. `igniter` CauldronRegistry.sol:419 is the second address (besides the owner) accepted by summon at `igniter` CauldronRegistry.sol:421, so it is a one-time ignition right rather than a standing power once `summoned` CauldronRegistry.sol:686 is set.
- Edges: none
- Observations: none

### `armEmergency` — CauldronRegistry.sol:426

- Signature: `function armEmergency() external onlyEmergency`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency (CauldronRegistry.sol:426)`
- Reads: `emergencyAdmin (line 370, immutable)`; `emergencyDelay (line 425, immutable)`; `emergencyReadyAt (line 427)`
- Writes: `emergencyReadyAt (line 427)`
- Value: NONE
- Reachability: Emergency-admin only. Sets `emergencyReadyAt` CauldronRegistry.sol:427 to now plus `emergencyDelay` CauldronRegistry.sol:425 and announces it. Arming has a second effect beyond the wait: it forces the redemption exit open, because `_redeemBlocked` CauldronBase.sol:433 only blocks while the arming is zero. The guardian can cancel it at `emergencyReadyAt` CauldronRegistry.sol:428.
- Edges: none
- Observations: none

### `setGuardian` — CauldronRegistry.sol:434

- Signature: `function setGuardian(address who) external`
- Authority: emergencyAdmin or owner
- Gate evidence: `if (msg.sender != emergencyAdmin && msg.sender != owner()) revert NotAdmin(); (CauldronRegistry.sol:436)`
- Reads: `emergencyAdmin (line 433, immutable)`
- Writes: `guardian (line 432)`
- Value: NONE
- Reachability: Either of the two admin roles may write `guardian` CauldronRegistry.sol:432, and it is not one-shot, so the emergency admin can replace a guardian that would veto it (DERIVED). The guardian's only power is the cancel at `emergencyReadyAt` CauldronRegistry.sol:446.
- Edges: `Ownable.owner (CauldronRegistry.sol:437), TRUSTED, out-of-cluster`
- Observations: none

### `vetoEmergency` — CauldronRegistry.sol:444

- Signature: `function vetoEmergency() external`
- Authority: guardian
- Gate evidence: `if (msg.sender != guardian) revert NotAdmin(); (CauldronRegistry.sol:444)`
- Reads: `guardian (line 445)`
- Writes: `emergencyReadyAt (line 446)`
- Value: NONE
- Reachability: Guardian-only, and the role defaults to address zero until `guardian` CauldronRegistry.sol:445 is set, so an unset guardian means no veto exists (DERIVED). Clearing `emergencyReadyAt` CauldronRegistry.sol:446 both cancels the pending action and re-closes the forced-open redemption exit that `_redeemBlocked` CauldronBase.sol:433 keys off.
- Edges: none
- Observations: none

### `setRedemptionPaused` — CauldronRegistry.sol:459

- Signature: `function setRedemptionPaused(bool paused) external onlyEmergency`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency (CauldronRegistry.sol:459)`
- Reads: `emergencyAdmin (line 370, immutable)`
- Writes: `redemptionPaused (line 460)`
- Value: NONE
- Reachability: Emergency-admin only and deliberately NOT timelocked, so the circuit breaker is immediate in both directions. `redemptionPaused` CauldronRegistry.sol:460 is one half of `_redeemBlocked` CauldronBase.sol:433; the other half is the arming, so pausing while an emergency is armed does not actually block redemptions.
- Edges: none
- Observations: none

### `setEnchantFeeMult` — CauldronRegistry.sol:468

- Signature: `function setEnchantFeeMult(uint256 bps) external onlyEmergency`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency (CauldronRegistry.sol:468)`
- Reads: `emergencyAdmin (line 370, immutable)`
- Writes: `enchantFeeMultBps (line 470)`
- Value: NONE
- Reachability: Emergency-admin only, capped at 1000000 bps (100x) at `bps` CauldronRegistry.sol:468 and written to `enchantFeeMultBps` CauldronRegistry.sol:470. The value is only ever read where the fee is computed, at `enchantFeeMultBps` CauldronRegistry.sol:470, which the dividend contract quotes off-chain and on-chain.
- Edges: none
- Observations: none

### `emergencyWithdrawLP` — CauldronRegistry.sol:475

- Signature: `function emergencyWithdrawLP(uint256 gen) external onlyEmergency timelocked nonReentrant`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency timelocked nonReentrant (CauldronRegistry.sol:475)`
- Reads: `emergencyReadyAt (line 408)`; `emergencyDelay (line 407, immutable)`; `generationToken (line 477)`; `emergencyAdmin (line 478, immutable)`
- Writes: `emergencyReadyAt (line 408)`
- Value: ERC20 transfer of the generation token `tok` to the emergency admin (line 477); sends native to `emergencyAdmin` (line 478)
- Reachability: Break-glass LP pull. Requires the emergency admin (`emergencyAdmin` CauldronRegistry.sol:478) and a prior arming consumed by `_consumeTimelock` CauldronRegistry.sol:412. It tears down the whole generation through `_removeLiquidity` CauldronRegistry.sol:476, which also unwinds the seeder and the rotated legs, then pushes both sides out: the token at `tok` CauldronRegistry.sol:477 and the ether at `emergencyAdmin` CauldronRegistry.sol:478. Effects precede the two external sends, and `nonReentrant` CauldronRegistry.sol:475 covers the whole call.
- Edges: `CauldronRegistry._removeLiquidity (CauldronRegistry.sol:476), TRUSTED, in-cluster`; `IERC20.transfer (CauldronRegistry.sol:478), TRUSTED, out-of-cluster`; `emergencyAdmin.call (CauldronRegistry.sol:480), TRUSTED, out-of-cluster`
- Observations: none

### `emergencySweep` — CauldronRegistry.sol:488

- Signature: `function emergencySweep(address token) external onlyEmergency timelocked nonReentrant`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency timelocked nonReentrant (CauldronRegistry.sol:488)`
- Reads: `emergencyReadyAt (line 408)`; `emergencyDelay (line 407, immutable)`; `emergencyAdmin (line 490, immutable)`
- Writes: `emergencyReadyAt (line 408)`
- Value: sends the registry's whole native balance to `emergencyAdmin` (line 490); ERC20 transfer of the caller-named `token` to the admin (line 486)
- Reachability: Emergency-admin only, armed and timelocked through `_consumeTimelock` CauldronRegistry.sol:412. A zero `token` CauldronRegistry.sol:486 sweeps the native balance; anything else is treated as an ERC20 and the token address is fully caller-chosen, so the external calls at `token` CauldronRegistry.sol:486 can reach arbitrary code. No return value is checked on the ERC20 transfer (DERIVED).
- Edges: `emergencyAdmin.call (CauldronRegistry.sol:490), TRUSTED, out-of-cluster`; `IERC20.balanceOf (CauldronRegistry.sol:493), UNTRUSTED, out-of-cluster`; `IERC20.transfer (CauldronRegistry.sol:493), UNTRUSTED, out-of-cluster`
- Observations: none

### `setSuccessor` — CauldronRegistry.sol:505

- Signature: `function setSuccessor(address _successor) external onlyEmergency`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency (CauldronRegistry.sol:505)`
- Reads: `emergencyAdmin (line 370, immutable)`
- Writes: `successor (line 506)`
- Value: NONE
- Reachability: Pointer only, not timelocked and not bounded: `successor` CauldronRegistry.sol:506 may be any address, including one with no code. The custody move that uses it is separately armed at `successor` CauldronRegistry.sol:506, so holders still get the forced-open exit window before value can follow the pointer.
- Edges: none
- Observations: none

### `setClaimGate` — CauldronRegistry.sol:524

- Signature: `function setClaimGate(address gate) external onlyEmergency`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency (CauldronRegistry.sol:524)`
- Reads: `emergencyReadyAt (line 408)`; `emergencyDelay (line 407, immutable)`; `emergencyAdmin (line 370, immutable)`
- Writes: `emergencyReadyAt (line 408)`; `claimGate (line 526)`
- Value: NONE
- Reachability: Asymmetric gate: the restricting direction consumes an arming at `_consumeTimelock` CauldronRegistry.sol:525, while clearing `claimGate` CauldronRegistry.sol:526 back to zero is immediate. A non-zero gate closes the three instant 1:1 paths, tested at `claimGate` CauldronRegistry.sol:526 and CauldronRegistry.sol:526, and on the extension side at `claimGate` RedemptionExt.sol:747.
- Edges: `CauldronRegistry._consumeTimelock (CauldronRegistry.sol:525), TRUSTED, in-cluster`
- Observations: none

### `migrateToSuccessor` — CauldronRegistry.sol:540

- Signature: `function migrateToSuccessor() external onlyEmergency timelocked nonReentrant`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency timelocked nonReentrant (CauldronRegistry.sol:540)`
- Reads: `emergencyReadyAt (line 408)`; `emergencyDelay (line 407, immutable)`; `successor (line 538)`; `currentGeneration (line 543)`; `generationPositionId (line 546)`; `generationReservePositionId (line 547)`; `positionManager (line 548)`; `seeder (line 552)`; `generationToken (line 565)`
- Writes: `emergencyReadyAt (line 408)`
- Value: ERC721 ownership of the active position is moved to the successor at `transferFrom` (line 548) and the reserve position at `transferFrom` (line 548) - the positions themselves are never withdrawn; ERC20 transfer of `tok` to the successor (line 565); sends the whole native balance to `to` (line 568)
- Reachability: The largest single custody move in the contract, reachable only by the emergency admin with an armed, elapsed timelock (`_consumeTimelock` CauldronRegistry.sol:412). It requires a pointer set beforehand (`to` CauldronRegistry.sol:541). Liquidity is handed over as position-NFT ownership rather than withdrawn, by the two ERC721 transferFrom calls at `activeId` CauldronRegistry.sol:546 and `reserveId` CauldronRegistry.sol:547, so a progressive generation whose active id is zero contributes nothing there and is instead unwound through `withdrawAll` CauldronRegistry.sol:554. The final native send targets a fully admin-chosen address at `to` CauldronRegistry.sol:568, and it happens after every effect (DERIVED).
- Edges: `IERC721.transferFrom (CauldronRegistry.sol:548), TRUSTED, out-of-cluster`; `IERC721.transferFrom (CauldronRegistry.sol:549), TRUSTED, out-of-cluster`; `ISeeder.seeding (CauldronRegistry.sol:560), TRUSTED, out-of-cluster`; `ISeeder.withdrawAll (CauldronRegistry.sol:561), TRUSTED, out-of-cluster`; `IERC20.balanceOf (CauldronRegistry.sol:567), TRUSTED, out-of-cluster`; `IERC20.transfer (CauldronRegistry.sol:568), TRUSTED, out-of-cluster`; `to.call (CauldronRegistry.sol:572), UNTRUSTED, out-of-cluster`
- Observations: none

### `receive` — CauldronRegistry.sol:578

- Signature: `receive() external payable`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: receives native through `receive` (line 578)
- Reachability: A bare payable `receive` CauldronRegistry.sol:578 with an empty body, so any address may push ether in; the hook's reserve pulls, the vault close and the seeder teardown all land here. This contract declares NO fallback, which is why every facet function needs an explicit stub such as `redeemOgFren` CauldronRegistry.sol:1421.
- Edges: none
- Observations: none

### `setGovernor` — CauldronRegistry.sol:585

- Signature: `function setGovernor(address _governor) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:585)`
- Reads: none
- Writes: `governor (line 584)`
- Value: NONE
- Reachability: Owner-only, unbounded and replaceable: `governor` CauldronRegistry.sol:584 accepts any address including zero. Relaunch reads it twice, for the liveness gate at `governor` CauldronRegistry.sol:586 and for the winning spec at `winner` CauldronRegistry.sol:903, so a swapped governor changes what the next rebirth launches.
- Edges: none
- Observations: none

### `setMinLifetime` — CauldronRegistry.sol:590

- Signature: `function setMinLifetime(uint256 _seconds) external onlyEmergency`
- Authority: emergencyAdmin
- Gate evidence: `onlyEmergency (CauldronRegistry.sol:590)`
- Reads: `emergencyAdmin (line 370, immutable)`
- Writes: `minLifetime (line 591)`
- Value: NONE
- Reachability: Emergency-admin only and unbounded in both directions: `minLifetime` CauldronRegistry.sol:591 takes any value, including zero (removing the grace period entirely) or a value large enough to make the check at `minLifetime` CauldronRegistry.sol:591 unsatisfiable in practice (DERIVED).
- Edges: none
- Observations: none

### `setFactory` — CauldronRegistry.sol:595

- Signature: `function setFactory(address _factory) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:595)`
- Reads: none
- Writes: `factory (line 594)`
- Value: NONE
- Reachability: Owner-only with no validation on `factory` CauldronRegistry.sol:594. It is called from inside the rebirth at `deployBrew` CauldronRegistry.sol:1217 and at `deployVault` CauldronRegistry.sol:1255, both outside any try/catch, so the configured factory is on the critical path of every relaunch (DERIVED).
- Edges: none
- Observations: none

### `setNftMaxSupply` — CauldronRegistry.sol:600

- Signature: `function setNftMaxSupply(uint256 _max) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:600)`
- Reads: none
- Writes: `nftMaxSupply (line 602)`
- Value: NONE
- Reachability: Owner-only, bounded to 1..MAX_NFT_SUPPLY at `MAX_NFT_SUPPLY` CauldronRegistry.sol:601 before writing `nftMaxSupply` CauldronRegistry.sol:602. The same ceiling is re-applied to the proposer's requested supply inside the rebirth at `MAX_NFT_SUPPLY` CauldronRegistry.sol:601, this time by clamping rather than reverting.
- Edges: none
- Observations: none

### `setRoyalty` — CauldronRegistry.sol:607

- Signature: `function setRoyalty(address _dividend, uint96 _bps) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:607)`
- Reads: none
- Writes: `royaltyDividend (line 609)`; `royaltyBps (line 610)`
- Value: NONE
- Reachability: Owner-only. Capped at 1000 bps at `_bps` CauldronRegistry.sol:607, then stored in `royaltyDividend` CauldronRegistry.sol:609 and `royaltyBps` CauldronRegistry.sol:610. Both are only consumed when a brew's collection is deployed, at `royaltyReceiver` CauldronRegistry.sol:1227, so a change applies to future collections only (DERIVED).
- Edges: none
- Observations: none

### `setGenesisMetadata` — CauldronRegistry.sol:615

- Signature: `function setGenesisMetadata(MetadataMode mode, string calldata baseURI, address renderer) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:616)`
- Reads: none
- Writes: `genesisMode (line 619)`; `genesisBaseURI (line 620)`; `genesisRenderer (line 621)`
- Value: NONE
- Reachability: Owner-only, no bound on the string length or the renderer address (`genesisBaseURI` CauldronRegistry.sol:620, `genesisRenderer` CauldronRegistry.sol:621). These three are the defaults a rebirth loads at `genesisMode` CauldronRegistry.sol:619 before the winning proposal overwrites them at `mode` CauldronRegistry.sol:619, so after iteration one they matter only as the values used when a spec leaves them empty (DERIVED).
- Edges: none
- Observations: none

### `setCollectionMetadata` — CauldronRegistry.sol:643

- Signature: `function setCollectionMetadata( uint256 gen, MetadataMode mode, address renderer, string calldata baseURI ) external onlyOwner`
- Authority: caller satisfying `onlyOwner`
- Gate evidence: `onlyOwner (CauldronRegistry.sol:640)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `setCollectionMetadata` is declared at CauldronRegistry.sol:643; caller satisfying `onlyOwner`.
- Edges: `ICollectionMetadata.setMetadata (CauldronRegistry.sol:651), UNTRUSTED, out-of-cluster`
- Observations: none

### `setGenesisBonus` — CauldronRegistry.sol:661

- Signature: `function setGenesisBonus(address _mifrens, uint256 _bonusBps, uint256 _shares) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:662)`
- Reads: `summoned (line 665)`
- Writes: `mifrens (line 668)`; `genesisBonusBps (line 669)`; `genesisShares (line 670)`
- Value: NONE
- Reachability: Owner-only and pre-ignition only: it reverts once `summoned` CauldronRegistry.sol:665 is set. The bonus is capped at 3000 bps at `_bonusBps` CauldronRegistry.sol:661 and both other fields must be non-zero at `_shares` CauldronRegistry.sol:659. `genesisShares` CauldronRegistry.sol:670 becomes the divisor of the live floor in `floorPerFren` CauldronBase.sol:423 and the OG/forged split boundary used throughout redemption.
- Edges: none
- Observations: none

### `setAirdropReserve` — CauldronRegistry.sol:676

- Signature: `function setAirdropReserve(address _wallet, uint256 _amount) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:676)`
- Reads: `summoned (line 677)`
- Writes: `airdropWallet (line 680)`; `airdropReserve (line 681)`
- Value: NONE
- Reachability: Owner-only, pre-ignition only (`summoned` CauldronRegistry.sol:677), non-zero wallet required at `_wallet` CauldronRegistry.sol:674 and capped at 20 percent of supply at `_amount` CauldronRegistry.sol:676. The reserve is paid out exactly once, off-LP, during ignition at `airdropReserve` CauldronRegistry.sol:681.
- Edges: none
- Observations: none

### `setPrimeFunder` — CauldronRegistry.sol:685

- Signature: `function setPrimeFunder(address who) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:685)`
- Reads: `summoned (line 686)`
- Writes: `primeFunder (line 687)`
- Value: NONE
- Reachability: Owner-only and pre-ignition only (`summoned` CauldronRegistry.sol:686). `primeFunder` CauldronRegistry.sol:687 is the sole gate on both prime-buy entries, at `primeFunder` CauldronRegistry.sol:687 and CauldronRegistry.sol:687, and it can never be changed after ignition (DERIVED).
- Edges: none
- Observations: none

### `fundPrimeBuy` — CauldronRegistry.sol:695

- Signature: `function fundPrimeBuy() external payable`
- Authority: primeFunder
- Gate evidence: `if (msg.sender != primeFunder) revert NotAdmin(); (CauldronRegistry.sol:695)`
- Reads: `primeFunder (line 694)`; `primeBuyEth (line 697)`
- Writes: `primeBuyEth (line 697)`
- Value: receives native, accumulated into `primeBuyEth` (line 697)
- Reachability: Only the configured funder may pay in (`primeFunder` CauldronRegistry.sol:694). The balance accrues in `primeBuyEth` CauldronRegistry.sol:697 as a counter alongside the registry's real ether balance, and it is spent in one shot during ignition at `primeBuyEth` CauldronRegistry.sol:697. With `primeFunder` CauldronRegistry.sol:694 unset the function is unreachable, since the zero address cannot call (DERIVED).
- Edges: none
- Observations: none

### `sweepPrimeBuy` — CauldronRegistry.sol:701

- Signature: `function sweepPrimeBuy() external`
- Authority: primeFunder
- Gate evidence: `if (msg.sender != primeFunder) revert NotAdmin(); (CauldronRegistry.sol:701)`
- Reads: `primeFunder (line 702)`; `primeBuyEth (line 703)`
- Writes: `primeBuyEth (line 703)`
- Value: sends native equal to `amt` back to the funder (line 703)
- Reachability: Funder-only reclaim. The counter is zeroed at `primeBuyEth` CauldronRegistry.sol:703 before the send at `amt` CauldronRegistry.sol:703, so the ordering is effects-then-interaction even though there is no reentrancy guard here. The amount paid out is the COUNTER, not a measured balance, and it is paid from whatever ether the registry holds (DERIVED).
- Edges: `msg.sender.call (CauldronRegistry.sol:705), UNTRUSTED, out-of-cluster`
- Observations: none

### `summon` — CauldronRegistry.sol:722

- Signature: `function summon() external payable nonReentrant returns (address token, PoolId poolId)`
- Authority: owner or igniter
- Gate evidence: `if (msg.sender != owner() && msg.sender != igniter) revert NotAdmin(); (CauldronRegistry.sol:730)`
- Reads: `igniter (line 728)`; `summoned (line 730)`; `genesisBonusBps (line 757)`; `genesisShares (line 757)`; `airdropReserve (line 767)`; `airdropWallet (line 767)`; `primeBuyEth (line 786)`; `primeFunder (line 790)`; `poolManager (line 792)`; `generationPoolKey (line 792)`; `genesisMode (line 797)`; `genesisBaseURI (line 797)`; `genesisRenderer (line 797)`; `nftMaxSupply (line 797)`
- Writes: `summoned (line 730)`; `currentGeneration (line 736)`; `lastSummonAt (line 737)`; `currentToken (line 746)`; `generationToken (line 747)`; `genesisSharePerFren (line 759)`; `genesisReserveOutstanding (line 760)`; `primeBuyEth (line 786)`; `_seedBuyUnlocked (line 791)`; `_seedBuyUnlocked (line 791)`
- Value: receives native as the entire genesis pairing, which `_seedGeneration` places into the pool (line 776); ERC20 transfer of the freshly minted token to `airdropWallet` (line 767); spends the accumulated prime ether inside `primeBuy` (line 792)
- Reachability: The one-time ignition. Two callers are accepted, the owner and the delegated igniter, at `igniter` CauldronRegistry.sol:728; it is one-shot either way because `summoned` CauldronRegistry.sol:730 is set immediately and re-entry is refused at `summoned` CauldronRegistry.sol:730. Non-zero msg.value is mandatory at `InsufficientETH` CauldronRegistry.sol:733. Generation one is always native-quoted: nothing writes `generationQuote` here, and the mapping's zero default is what the pool is built against (DERIVED). The genesis bonus is sized only if both `genesisBonusBps` CauldronRegistry.sol:757 and the share count are non-zero, fixing `genesisSharePerFren` CauldronRegistry.sol:759 for the life of the machine. The active band is the fixed 80 percent constant at `GEN1_ACTIVE_TOKENS` CauldronRegistry.sol:765 and the reserve is the remainder minus the airdrop. The prime buy runs AFTER the seed so it hits the intended starting price, with the callback window opened and closed around it at `_seedBuyUnlocked` CauldronRegistry.sol:791 and CauldronRegistry.sol:791.
- Edges: `Ownable.owner (CauldronRegistry.sol:731), TRUSTED, out-of-cluster`; `PoolOps.creatureFor (CauldronRegistry.sol:741), TRUSTED, library`; `LaunchLib.displayName (CauldronRegistry.sol:742), TRUSTED, library`; `CauldronRegistry._deployToken (CauldronRegistry.sol:745), TRUSTED, in-cluster`; `IERC20.transfer (CauldronRegistry.sol:769), TRUSTED, out-of-cluster`; `CauldronRegistry._seedGeneration (CauldronRegistry.sol:778), TRUSTED, in-cluster`; `PoolOps.primeBuy (CauldronRegistry.sol:792), TRUSTED, library`; `CauldronRegistry._deployCollection (CauldronRegistry.sol:797), TRUSTED, in-cluster`
- Observations: comment at `CREATE` CauldronRegistry.sol:744 says the generation token is deployed with plain CREATE; code reached from `_deployToken` CauldronRegistry.sol:745 deploys it with CREATE2 from a mined salt at `salt` PoolOps.sol:742, using plain CREATE only in the unmined fallback at `CauldronToken` PoolOps.sol:767.

### `relaunch` — CauldronRegistry.sol:821

- Signature: `function relaunch() external nonReentrant returns (address token, PoolId poolId)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: `relaunch` is declared at CauldronRegistry.sol:821; anyone.
- Edges: `CauldronHook.isDead (CauldronRegistry.sol:833), UNTRUSTED, out-of-cluster`; `ICauldronGovernor.hasProposals (CauldronRegistry.sol:841), UNTRUSTED, out-of-cluster`; `CauldronToken.burn (CauldronRegistry.sol:865), UNTRUSTED, out-of-cluster`; `CauldronHook.resolveTickets (CauldronRegistry.sol:876), UNTRUSTED, out-of-cluster`; `ICauldronGovernor.winner (CauldronRegistry.sol:903), UNTRUSTED, out-of-cluster`; `LaunchLib.displayName (CauldronRegistry.sol:967), TRUSTED, library`; `PoolOps.seedFunding (CauldronRegistry.sol:1002), TRUSTED, out-of-cluster`; `ICauldronGovernor.winner (CauldronRegistry.sol:903), UNTRUSTED, out-of-cluster`; `ICauldronGovernor.markConsumed (CauldronRegistry.sol:1031), UNTRUSTED, out-of-cluster`; `CauldronHook.setActiveProposer (CauldronRegistry.sol:1043), UNTRUSTED, out-of-cluster`; `PoolOps.crystallizeCollection (CauldronRegistry.sol:1092), TRUSTED, out-of-cluster`; `ICollectionLedger.totalEntitled (CauldronRegistry.sol:1096), UNTRUSTED, out-of-cluster`; `CauldronHook.setNftCurveFrom (CauldronRegistry.sol:1146), UNTRUSTED, out-of-cluster`; `CauldronRegistry._perpHousekeep (CauldronRegistry.sol:855), TRUSTED, in-cluster`; `CauldronRegistry._removeLiquidity (CauldronRegistry.sol:858), TRUSTED, in-cluster`; `CauldronRegistry._deployToken (CauldronRegistry.sol:970), TRUSTED, in-cluster`; `CauldronRegistry._flushLegacyAtRelaunch (CauldronRegistry.sol:1091), TRUSTED, in-cluster`; `CauldronRegistry._seedGeneration (CauldronRegistry.sol:1131), TRUSTED, in-cluster`; `CauldronRegistry._continueMiFrens (CauldronRegistry.sol:1139), TRUSTED, in-cluster`; `CauldronRegistry._deployCollection (CauldronRegistry.sol:1141), TRUSTED, in-cluster`; `CauldronRegistry._perpHousekeep (CauldronRegistry.sol:1151), TRUSTED, in-cluster`
- Observations: none

### `_perpHousekeep` — CauldronRegistry.sol:1160

- Signature: `function _perpHousekeep(bool sync) private`
- Authority: internal (callers: relaunch)
- Gate evidence: `UNGATED`
- Reads: `hook (line 1162)`; `RELAUNCH_TAIL_RESERVE (line 1191, constant)`; `hook (line 1162)`
- Writes: none
- Value: NONE
- Reachability: Private, reached only from the two calls inside the rebirth at `_perpHousekeep` CauldronRegistry.sol:1160 and CauldronRegistry.sol:1160. The two branches are not symmetric in failure handling: the sync branch swallows everything in a try/catch at `syncGeneration` CauldronRegistry.sol:1163, while the force-close branch calls `forceClosePerps` CauldronRegistry.sol:1182 bare, so a revert there propagates and rolls the whole relaunch back. Both are gas-capped, the close against `RELAUNCH_TAIL_RESERVE` CauldronRegistry.sol:1191, and the engine address is read off the hook rather than stored here (`perpEngine` CauldronRegistry.sol:1162). When the cap check fails because `g` CauldronRegistry.sol:1190 is below the reserve, the close is skipped entirely and the rebirth continues with the book untouched (DERIVED).
- Edges: `CauldronHook.perpEngine (CauldronRegistry.sol:1162), TRUSTED, out-of-cluster`; `IPerpSync.syncGeneration (CauldronRegistry.sol:1163), TRUSTED, out-of-cluster`; `CauldronHook.forceClosePerps (CauldronRegistry.sol:1192), TRUSTED, out-of-cluster`
- Observations: none

### `_deployCollection` — CauldronRegistry.sol:1201

- Signature: `function _deployCollection( uint256 gen, string memory name, string memory symbol, MetadataMode mode, string memory baseURI, address renderer, uint256 maxSupply ) private`
- Authority: internal (callers: summon, relaunch)
- Gate evidence: `UNGATED`
- Reads: `nftMaxSupply (line 1215)`; `factory (line 1217)`; `hook (line 1221)`; `royaltyDividend (line 1227)`; `royaltyBps (line 1228)`
- Writes: `generationCollection (line 1231)`; `generationVault (line 1232)`
- Value: NONE
- Reachability: Private; reached from ignition at `_deployCollection` CauldronRegistry.sol:1201 and from every non-continuation rebirth at CauldronRegistry.sol:1201. It cannot revert on missing metadata because an empty base URI falls back to a literal at `baseURI` CauldronRegistry.sol:1212 and a zero cap falls back to `nftMaxSupply` CauldronRegistry.sol:1215. The factory call at `deployBrew` CauldronRegistry.sol:1217 is NOT wrapped, so a broken or unset factory reverts the whole rebirth (DERIVED). The hook is then repointed at the new collection (`setCollection` CauldronRegistry.sol:1233) and its vault sink is deliberately zeroed (`setVault` CauldronRegistry.sol:1235), routing the floor share into the token buyback instead.
- Edges: `ICauldronFactory.deployBrew (CauldronRegistry.sol:1217), TRUSTED, out-of-cluster`; `CauldronHook.setCollection (CauldronRegistry.sol:1233), TRUSTED, out-of-cluster`; `CauldronHook.setVault (CauldronRegistry.sol:1237), TRUSTED, out-of-cluster`
- Observations: none

### `_continueMiFrens` — CauldronRegistry.sol:1250

- Signature: `function _continueMiFrens(uint256 gen) private`
- Authority: internal (callers: relaunch)
- Gate evidence: `UNGATED`
- Reads: `mifrens (line 1251)`; `factory (line 1255)`; `genesisShares (line 1252)`; `hook (line 1259)`
- Writes: `generationCollection (line 1256)`; `generationVault (line 1257)`
- Value: NONE
- Reachability: Private and reachable exactly once in the machine's life, from the iteration-two branch at `_continueMiFrens` CauldronRegistry.sol:1250, which requires `mifrens` CauldronRegistry.sol:1251 to be wired. No new collection is deployed; only a fresh floor vault at `deployVault` CauldronRegistry.sol:1255, whose offset is `genesisShares` CauldronRegistry.sol:1252 so the forged tranche cannot draw the OG floor. It then takes over the canonical collection by pointing its minter at the hook (`setMinter` CauldronRegistry.sol:1259), which requires this registry to already hold that authority on the collection (DERIVED).
- Edges: `ICauldronFactory.deployVault (CauldronRegistry.sol:1255), TRUSTED, out-of-cluster`; `IMiFrensContinuable.setVault (CauldronRegistry.sol:1258), TRUSTED, out-of-cluster`; `IMiFrensContinuable.setMinter (CauldronRegistry.sol:1259), TRUSTED, out-of-cluster`; `CauldronHook.setCollection (CauldronRegistry.sol:1260), TRUSTED, out-of-cluster`; `CauldronHook.setVault (CauldronRegistry.sol:1261), TRUSTED, out-of-cluster`
- Observations: none

### `claimByBurn` — CauldronRegistry.sol:1291

- Signature: `function claimByBurn(uint256 fromGen, uint256 amount) external returns (uint256 claimedAmount)`
- Authority: anyone (holders of a previous generation's token); blocked for ordinary callers while a vesting gate is set
- Gate evidence: `if (claimGate != address(0) && msg.sender != claimGate && msg.sender != hook.perpEngine()) { (CauldronRegistry.sol:1299)`
- Reads: `currentGeneration (line 1295)`; `claimGate (line 1300)`; `hook (line 1300)`; `generationToken (line 1303)`; `currentGeneration (line 1295)`; `positionManager (line 1311)`; `generationReservePositionId (line 1312)`; `generationPoolKey (line 1312)`; `reserveTickLower (line 1312)`; `reserveTickUpper (line 1312)`
- Writes: none
- Value: burns the caller's previous-generation balance and releases the same amount of the live token out of the reserve position, both inside `migrateOne` (line 1310)
- Reachability: Open to any holder of a strictly earlier generation (`currentGeneration` CauldronRegistry.sol:1295). When a vesting escrow is configured the direct path is closed to everyone except the escrow itself and the perp engine (`claimGate` CauldronRegistry.sol:1300). The source generation must be known (`prevToken` CauldronRegistry.sol:1303) and the caller must actually hold the amount (`balanceOf` CauldronRegistry.sol:1305). It deliberately carries no reentrancy guard, which is what lets the engine migrate its inventory while the rebirth already holds the lock (`migrateOne` CauldronRegistry.sol:1310). The release is strict: a reserve that cannot cover the amount reverts and un-burns atomically.
- Edges: `CauldronHook.perpEngine (CauldronRegistry.sol:1300), TRUSTED, out-of-cluster`; `IERC20.balanceOf (CauldronRegistry.sol:1305), TRUSTED, out-of-cluster`; `PoolOps.migrateOne (CauldronRegistry.sol:1310), TRUSTED, library`
- Observations: comment at `claimTokens` CauldronRegistry.sol:44 names the migration entry point as claimTokens(gen); code exposes it as `claimByBurn` CauldronRegistry.sol:1291 and `claimByBurnUpTo` CauldronRegistry.sol:1336, and no function of the documented name exists in this file.

### `claimByBurnUpTo` — CauldronRegistry.sol:1336

- Signature: `function claimByBurnUpTo(uint256, uint256) external returns (uint256)`
- Authority: any holder of an earlier generation, unless a claim gate is set, in which case only the gate itself or the perp engine; the gate is enforced facet-side
- Gate evidence: `if (claimGate != address(0) && msg.sender != claimGate && msg.sender != hook.perpEngine()) { (RedemptionExt.sol:746)`
- Reads: `redemptionExt (line 1501)`
- Writes: none
- Value: NONE in this stub; the burn and the reserve withdrawal happen inside the delegatecalled facet, on this registry's own storage and custody
- Reachability: Selector-preserving forwarder: the body moved to `claimByBurnUpTo` RedemptionExt.sol:742 and this stub keeps the ABI (comment at `claimByBurnUpTo` CauldronRegistry.sol:1336 gives EIP-170 headroom as the reason). Body is `_forwardToExt` CauldronRegistry.sol:1337, a delegatecall, so the facet executes on this registry's storage and custody. Every gate is facet-side: earlier generations only at `currentGeneration` RedemptionExt.sol:725, the escrow/engine exemption at `claimGate` RedemptionExt.sol:747, a known source token at `prevToken` RedemptionExt.sol:750 and a real balance at `balanceOf` RedemptionExt.sol:753; the capacity-aware migration itself is `migrateUpTo` RedemptionExt.sol:758, which sizes to what the reserve can deliver instead of reverting. The strict sibling `claimByBurn` CauldronRegistry.sol:1291 still holds its own copy of the same gate on this side.
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:1337), TRUSTED, in-cluster`; `RedemptionExt.claimByBurnUpTo (RedemptionExt.sol:758), TRUSTED, delegatecall`
- Observations: none

### `enableAutoMigrate` — CauldronRegistry.sol:1354

- Signature: `function enableAutoMigrate() external payable`
- Authority: anyone (free for any MiFren holder, otherwise a fee is required)
- Gate evidence: `if (msg.value < AUTO_MIGRATE_FEE) revert Fee(); (CauldronRegistry.sol:1359)`
- Reads: `mifrens (line 1356)`
- Writes: `autoMigrate (line 1362)`
- Value: receives native: the opt-in fee is required only when the caller holds no fren, checked at `AUTO_MIGRATE_FEE` (line 1360), and any ether sent stays in this registry
- Reachability: Open to anyone. The fren check is skipped entirely when `mifrens` CauldronRegistry.sol:1356 is unset, in which case everyone pays. Overpayment is not refunded: the comparison at `msg` CauldronRegistry.sol:1359 is a minimum, and no change is returned (DERIVED). The flag written at `autoMigrate` CauldronRegistry.sol:1362 is the only thing that authorises a keeper to burn that wallet's old-generation balance later, and it is revocable at `autoMigrate` CauldronRegistry.sol:1362.
- Edges: `IERC721.balanceOf (CauldronRegistry.sol:1359), TRUSTED, out-of-cluster`
- Observations: none

### `disableAutoMigrate` — CauldronRegistry.sol:1382

- Signature: `function disableAutoMigrate() external`
- Authority: anyone (for their own wallet only)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `autoMigrate (line 1383)`
- Value: NONE
- Reachability: Open and free: a caller can only ever clear their own slot, since the key is msg.sender at `autoMigrate` CauldronRegistry.sol:1383. It takes effect immediately because the keeper path re-reads the flag per holder inside `autoMigrateBatch` CauldronRegistry.sol:1380. Re-enabling costs the fee again at `AUTO_MIGRATE_FEE` CauldronRegistry.sol:1344 (DERIVED).
- Edges: none
- Observations: none

### `autoMigrateBatch` — CauldronRegistry.sol:1394

- Signature: `function autoMigrateBatch(uint256 fromGen, address[] calldata holders) external nonReentrant`
- Authority: anyone (permissionless keeper)
- Gate evidence: `UNGATED`
- Reads: `currentGeneration (line 1398)`; `claimGate (line 1402)`; `generationToken (line 1403)`; `currentGeneration (line 1398)`; `positionManager (line 1407)`; `generationReservePositionId (line 1408)`; `generationPoolKey (line 1408)`; `reserveTickLower (line 1408)`; `reserveTickUpper (line 1408)`
- Writes: none
- Value: burns each opted-in holder's whole previous-generation balance and releases the same amount of the live token from the reserve, inside `autoMigrateBatch` (line 1394)
- Reachability: Permissionless. Three state conditions: an earlier source generation at `currentGeneration` CauldronRegistry.sol:1398, no vesting escrow at all (`claimGate` CauldronRegistry.sol:1402 closes this path for everyone, unlike the per-caller exemption on the direct claims), and a known source token at `prevToken` CauldronRegistry.sol:1403. The holder list is caller-supplied and its length is the loop bound, so the only limit is the block gas limit (`holders` CauldronRegistry.sol:1394). Per-holder consent is checked inside the library, and the burn primitive it uses needs no allowance, so the opt-in flag at `autoMigrate` CauldronRegistry.sol:1344 is the whole authorisation.
- Edges: `PoolOps.autoMigrateBatch (CauldronRegistry.sol:1406), TRUSTED, library`
- Observations: none

### `redeemOgFren` — CauldronRegistry.sol:1437

- Signature: `function redeemOgFren(uint256) external returns (uint256)`
- Authority: anyone holding a genesis fren; the facet holds the gate (RedemptionExt checks OG ownership and the redemption circuit-breaker)
- Gate evidence: `if (IERC721(mifrens).ownerOf(mifrenTokenId) != msg.sender) revert NotOwnerOf(); (RedemptionExt.sol:85)`
- Reads: `redemptionExt (line 1501)`
- Writes: none
- Value: NONE in this stub; the facet pays the live floor out of this registry's reserve position and takes custody of the fren
- Reachability: Thin stub; the body is `_forwardToExt` CauldronRegistry.sol:1438 and the code that runs is `redeemOgFren` RedemptionExt.sol:78, executing on this registry's storage and custody. Every gate is facet-side: the circuit-breaker at `_redeemBlocked` RedemptionExt.sol:79, ignition at `summoned` RedemptionExt.sol:80, the OG-only id range at `genesisShares` RedemptionExt.sol:83 and ownership at `ownerOf` RedemptionExt.sol:84. The facet's own nonReentrant runs against this registry's guard slot, which is why the stub must not carry one (`nonReentrant` RedemptionExt.sol:78).
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:1438), TRUSTED, in-cluster`; `RedemptionExt.redeemOgFren (CauldronRegistry.sol:1437), TRUSTED, delegatecall`
- Observations: none

### `buyTreasuryOgFren` — CauldronRegistry.sol:1443

- Signature: `function buyTreasuryOgFren(uint256) external returns (uint256)`
- Authority: anyone; the facet holds the gate (the fren must currently sit in this registry's treasury)
- Gate evidence: `if (IERC721(mifrens).ownerOf(mifrenTokenId) != address(this)) revert NotOwnerOf(); (RedemptionExt.sol:120)`
- Reads: `redemptionExt (line 1501)`
- Writes: none
- Value: NONE in this stub; the facet pulls twice the live floor in the current token from the buyer and grows the reserve with it
- Reachability: Stub whose body is `_forwardToExt` CauldronRegistry.sol:1444, reaching `buyTreasuryOgFren` RedemptionExt.sol:115. Facet-side conditions: ignition at `summoned` RedemptionExt.sol:116, the OG id range at `genesisShares` RedemptionExt.sol:117, and treasury custody at `ownerOf` RedemptionExt.sol:119. The price is derived, not quoted: twice `floorPerFren` RedemptionExt.sol:121, so it moves with the reserve.
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:1444), TRUSTED, in-cluster`; `RedemptionExt.buyTreasuryOgFren (CauldronRegistry.sol:1443), TRUSTED, delegatecall`
- Observations: none

### `donateToReserve` — CauldronRegistry.sol:1449

- Signature: `function donateToReserve(uint256) external`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `redemptionExt (line 1501)`
- Writes: none
- Value: NONE in this stub; the facet pulls the donated amount of the current token from the caller into the reserve
- Reachability: Stub forwarding to `donateToReserve` RedemptionExt.sol:136, which has no caller gate at all; it only requires ignition at `summoned` RedemptionExt.sol:137 and a non-zero amount at `amount` RedemptionExt.sol:138. The pull is by transferFrom, so the caller must have approved this registry first (DERIVED). This is the path the dividend contract routes re-enchant fees through, which is why the fee quote at `enchantFee` CauldronRegistry.sol:365 lives on the registry.
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:1450), TRUSTED, in-cluster`; `RedemptionExt.donateToReserve (CauldronRegistry.sol:1449), TRUSTED, delegatecall`
- Observations: none

### `materializeLegacyReserve` — CauldronRegistry.sol:1455

- Signature: `function materializeLegacyReserve() external returns (uint256)`
- Authority: anyone (permissionless keeper)
- Gate evidence: `UNGATED`
- Reads: `redemptionExt (line 1501)`
- Writes: none
- Value: NONE in this stub; the facet sweeps the hook's held buyback tokens into this registry's reserve position
- Reachability: Stub forwarding to `materializeLegacyReserve` RedemptionExt.sol:147. No caller gate; the only precondition is ignition at `summoned` RedemptionExt.sol:148. It deposits and credits in one step so a ledger credit can never out-run the reserve backing it (`materializeLegacy` RedemptionExt.sol:151). The rebirth performs the same flush for the dying generation on the burn path at `_flushLegacyAtRelaunch` CauldronRegistry.sol:1548, so an uncalled keeper does not lose the value.
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:1456), TRUSTED, in-cluster`; `RedemptionExt.materializeLegacyReserve (CauldronRegistry.sol:1455), TRUSTED, delegatecall`
- Observations: none

### `floorClaimableNow` — CauldronRegistry.sol:1472

- Signature: `function floorClaimableNow() external returns (bool, uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `redemptionExt (line 1501)`
- Writes: none
- Value: NONE
- Reachability: A read that cannot be declared view because Solidity refuses delegatecall in a view body, so it is nonpayable and an eth_call serves it unchanged. It reaches `floorClaimableNow` RedemptionExt.sol:723, which reads the live tick and compares it with the reserve band at `reserveTickUpper` RedemptionExt.sol:728. Ungated on both sides.
- Edges: `CauldronRegistry._forwardToExtView (CauldronRegistry.sol:1473), TRUSTED, in-cluster`; `RedemptionExt.floorClaimableNow (RedemptionExt.sol:739), TRUSTED, delegatecall`
- Observations: comment at `fallback` RedemptionExt.sol:698 says this view is reached through the registry's fallback; code at `floorClaimableNow` CauldronRegistry.sol:1472 is an explicit stub and `receive` CauldronRegistry.sol:578 is the only special function the registry declares.

### `legCount` — CauldronRegistry.sol:1477

- Signature: `function legCount(uint256) external returns (uint256)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `redemptionExt (line 1501)`
- Writes: none
- Value: NONE
- Reachability: Ungated read forwarded to `legCount` RedemptionExt.sol:766, which returns the length of the rotated-leg array for that generation from this registry's own storage (`generationLegs` RedemptionExt.sol:767). Nonpayable rather than view for the same delegatecall reason as the other two readers (`_forwardToExtView` CauldronRegistry.sol:1478).
- Edges: `CauldronRegistry._forwardToExtView (CauldronRegistry.sol:1478), TRUSTED, in-cluster`; `RedemptionExt.legCount (RedemptionExt.sol:782), TRUSTED, delegatecall`
- Observations: comment at `fallback` CauldronBase.sol:535 says legCount and legAt are reached through the registry's fallback; code at `legCount` CauldronRegistry.sol:1477 and `legAt` CauldronRegistry.sol:1482 are explicit stubs, and the registry declares no fallback (`receive` CauldronRegistry.sol:578).

### `legAt` — CauldronRegistry.sol:1482

- Signature: `function legAt(uint256, uint256) external returns (address, uint256, PoolKey memory)`
- Authority: anyone
- Gate evidence: `UNGATED`
- Reads: `redemptionExt (line 1501)`
- Writes: none
- Value: NONE
- Reachability: Ungated read forwarded to `legAt` RedemptionExt.sol:771. There is no explicit bounds check; an out-of-range index reverts on the array access at `generationLegs` RedemptionExt.sol:767 (DERIVED). Callers are expected to page it against the count from `legCount` CauldronRegistry.sol:1477.
- Edges: `CauldronRegistry._forwardToExtView (CauldronRegistry.sol:1483), TRUSTED, in-cluster`; `RedemptionExt.legAt (RedemptionExt.sol:787), TRUSTED, delegatecall`
- Observations: none

### `_forwardToExtView` — CauldronRegistry.sol:1495

- Signature: `function _forwardToExtView() private`
- Authority: internal (callers: floorClaimableNow, legCount, legAt)
- Gate evidence: `UNGATED`
- Reads: `redemptionExt (line 1501)`
- Writes: none
- Value: NONE
- Reachability: A one-line alias over `_forwardToExt` CauldronRegistry.sol:1496 that exists only to document why the three read stubs are not `view` CauldronRegistry.sol:1493. It adds no gate and no state of its own, so the three readers inherit exactly the facet's behaviour (DERIVED).
- Edges: `CauldronRegistry._forwardToExt (CauldronRegistry.sol:1496), TRUSTED, in-cluster`
- Observations: none

### `_forwardToExt` — CauldronRegistry.sol:1505

- Signature: `function _forwardToExt() private`
- Authority: internal (callers: rotateSlice, rotateSliceFrom, setRotationWiring, sweepLegProceeds, redeemOgFren, buyTreasuryOgFren, donateToReserve, materializeLegacyReserve, _forwardToExtView)
- Gate evidence: `if (ext == address(0)) revert NotConfigured(); (CauldronRegistry.sol:1506)`
- Reads: `redemptionExt (line 1506)`
- Writes: none
- Value: NONE directly; the delegatecalled code executes with this registry's balances and position custody
- Reachability: The single door to the facet. It rejects an unset target at `ext` CauldronRegistry.sol:1506, because a delegatecall to an empty account would return success with empty data and silently no-op. The full calldata is copied verbatim at `calldatasize` CauldronRegistry.sol:1509 and returndata or revert data is bubbled unchanged at `returndatasize` CauldronRegistry.sol:1511. The target is whatever was frozen in at `redemptionExt` CauldronRegistry.sol:1506, and it has unrestricted write access to every slot of this contract (DERIVED). It forwards all remaining gas (`gas` CauldronRegistry.sol:1510).
- Edges: `ext.delegatecall (CauldronRegistry.sol:1510), TRUSTED, delegatecall`
- Observations: comment at `fallback` CauldronRegistry.sol:1832 says the fallback delegatecalls any unknown selector to the facet; code at `receive` CauldronRegistry.sol:578 declares only a receive function and each facet entry is an explicit stub such as `floorClaimableNow` CauldronRegistry.sol:1472, which the note at `fallback` CauldronRegistry.sol:1461 also states.

### `setCollectionLedger` — CauldronRegistry.sol:1527

- Signature: `function setCollectionLedger(address ledger) external onlyOwner`
- Authority: owner
- Gate evidence: `onlyOwner (CauldronRegistry.sol:1527)`
- Reads: none
- Writes: `collectionLedger (line 1528)`
- Value: NONE
- Reachability: Owner-only, unvalidated and replaceable despite the one-time wording: `collectionLedger` CauldronRegistry.sol:1528 accepts any address and can be written again. Zero keeps the legacy floor off, which is what the two collection paths test at `collectionLedger` CauldronRegistry.sol:1528 and CauldronRegistry.sol:1528, and what the rebirth tests at `collectionLedger` CauldronRegistry.sol:1528.
- Edges: none
- Observations: none

### `_flushLegacyAtRelaunch` — CauldronRegistry.sol:1548

- Signature: `function _flushLegacyAtRelaunch(uint256 oldGen, address oldToken) private`
- Authority: internal (callers: relaunch)
- Gate evidence: `UNGATED`
- Reads: `positionManager (line 1551)`; `hook (line 1551)`; `collectionLedger (line 1552)`; `mifrens (line 1552)`; `genesisShares (line 1552)`; `generationCollection (line 1552)`; `genesisPending (line 1555)`
- Writes: `genesisPending (line 1555)`
- Value: NONE at this level; the library sweeps the hook's un-materialized buyback tokens for the dying generation and, with the deposit flag false, credits the ledger as a NUMBER instead of depositing them, inside `materializeLegacy` (line 1550)
- Reachability: Private and called from exactly one place, the ledger branch of the rebirth at `_flushLegacyAtRelaunch` CauldronRegistry.sol:1548, which itself only runs when `collectionLedger` CauldronRegistry.sol:1552 is non-zero. The burn path is selected by the trailing false argument at `empty` CauldronRegistry.sol:1549, so the reserve reference is unused. The OG share it returns is accumulated into `genesisPending` CauldronRegistry.sol:1555, which the same rebirth folds into the genesis reserve a few lines earlier in program order at `genesisPending` CauldronRegistry.sol:1555 — the fold happens BEFORE this flush in the source, so a flush's OG share lands in the NEXT rebirth's sizing (DERIVED).
- Edges: `PoolOps.materializeLegacy (CauldronRegistry.sol:1550), TRUSTED, library`
- Observations: comment at `Hook` CauldronRegistry.sol:1533 documents a hook-called recorder that is hook-only and no-ops without a ledger; code declares no such function here, and the next declaration is the private `_flushLegacyAtRelaunch` CauldronRegistry.sol:1548 reachable only from the rebirth.

### `recycleCollectionNFT` — CauldronRegistry.sol:1562

- Signature: `function recycleCollectionNFT(uint256 gen, uint256 tokenId) external nonReentrant returns (uint256 amount)`
- Authority: anyone owning the collection NFT (ownership enforced in the library)
- Gate evidence: `if (ICollectionOps(collection).ownerOf(tokenId) != caller) revert("not owner"); (PoolOps.sol:1580)`
- Reads: `generationCollection (line 1566)`; `collectionLedger (line 1570)`; `currentGeneration (line 1571)`; `positionManager (line 1573)`; `generationReservePositionId (line 1575)`; `generationPoolKey (line 1575)`; `reserveTickLower (line 1575)`; `reserveTickUpper (line 1575)`
- Writes: none
- Value: releases the collection's floor entitlement in the LIVE generation's token out of the shared reserve to the caller, and moves the NFT into this registry's custody, inside `recycleCollection` (line 1568)
- Reachability: Open to the NFT's owner. The circuit-breaker applies here (`_redeemBlocked` CauldronRegistry.sol:1565), and both the ledger and the generation's collection must be wired (`collectionLedger` CauldronRegistry.sol:1570). Payment is made in the CURRENT generation's token from the shared reserve position, read at `currentGeneration` CauldronRegistry.sol:1571, not in the token of the generation the NFT belongs to. The OG-tranche exclusion and the ownership check both live in the library at `recycleCollection` CauldronRegistry.sol:1568, and the reserve-short rollback is enforced there too.
- Edges: `CauldronBase._redeemBlocked (CauldronRegistry.sol:1565), TRUSTED, out-of-cluster`; `PoolOps.recycleCollection (CauldronRegistry.sol:1572), TRUSTED, library`
- Observations: none

### `buyCollectionNFT` — CauldronRegistry.sol:1583

- Signature: `function buyCollectionNFT(uint256 gen, uint256 tokenId) external nonReentrant returns (uint256 paid)`
- Authority: anyone (the NFT must currently sit in this registry's treasury)
- Gate evidence: `if (ICollectionOps(collection).ownerOf(tokenId) != address(this)) revert("not treasury"); (PoolOps.sol:1630)`
- Reads: `generationCollection (line 1586)`; `collectionLedger (line 1587)`; `currentGeneration (line 1588)`; `positionManager (line 1590)`; `generationToken (line 1591)`; `generationReservePositionId (line 1592)`; `generationPoolKey (line 1592)`; `reserveTickLower (line 1592)`; `reserveTickUpper (line 1592)`
- Writes: none
- Value: pulls twice the NFT's floor in the live token from the buyer into the reserve and hands the NFT over, inside `buyCollection` (line 1589)
- Reachability: Open to anyone. Unlike the recycle side it does NOT consult the redemption circuit-breaker: there is no `_redeemBlocked` CauldronRegistry.sol:1565 equivalent in this body (DERIVED). Preconditions are only a wired ledger and a known collection at `collectionLedger` CauldronRegistry.sol:1587. The payment token is the LIVE generation's, read at `generationToken` CauldronRegistry.sol:1591, and the price is derived from the ledger floor inside the library rather than supplied by the caller.
- Edges: `PoolOps.buyCollection (CauldronRegistry.sol:1589), TRUSTED, library`
- Observations: none

### `_removeLiquidity` — CauldronRegistry.sol:1606

- Signature: `function _removeLiquidity(uint256 gen) private returns (uint256 ethRecovered, uint256 tokensRecovered)`
- Authority: internal (callers: relaunch, emergencyWithdrawLP)
- Gate evidence: `UNGATED`
- Reads: `generationPoolKey (line 1610)`; `generationToken (line 1611)`; `positionManager (line 1612)`; `generationPositionId (line 1616)`; `generationReservePositionId (line 1621)`; `seeder (line 1614)`; `redemptionExt (line 1653)`; `RECOVER_LEGS (line 1661, constant)`
- Writes: none
- Value: recovers both sides of the active and reserve positions into this registry through `removeAll` (line 1618) and (line 1618); recovers the streamed book through `withdrawAll` (line 1636); recovers every rotated leg through the delegatecall at `RECOVER_LEGS` (line 1661)
- Reachability: Private, reached from the rebirth at `_removeLiquidity` CauldronRegistry.sol:1606 and from the break-glass pull at CauldronRegistry.sol:1606. Four recovery sources are summed into ONE pair of totals: the active position, skipped when its id is zero on a streamed generation (`activeId` CauldronRegistry.sol:1616); the reserve position (`rid` CauldronRegistry.sol:1621); the seeder's bands, only while it reports itself active (`seeding` CauldronRegistry.sol:1635); and the rotated legs via a delegatecall whose failure is deliberately swallowed at `ok` CauldronRegistry.sol:1658. The leg selector is compiler-computed at `RECOVER_LEGS` CauldronRegistry.sol:1661 rather than hand-written, because a wrong selector would fail silently through that same swallow. The totals are denominated in the PRIMARY pair's currency0, which is why only legs in that same asset may be added to them (`recoverLegs` RedemptionExt.sol:834).
- Edges: `PoolOps.removeAll (CauldronRegistry.sol:1618), TRUSTED, library`; `PoolOps.removeAll (CauldronRegistry.sol:1623), TRUSTED, library`; `ISeeder.seeding (CauldronRegistry.sol:1635), TRUSTED, out-of-cluster`; `ISeeder.withdrawAll (CauldronRegistry.sol:1636), TRUSTED, out-of-cluster`; `ext.delegatecall (CauldronRegistry.sol:1661), TRUSTED, delegatecall`; `RedemptionExt.recoverLegs (RedemptionExt.sol:878), TRUSTED, delegatecall`
- Observations: none

### `_deployToken` — CauldronRegistry.sol:1680

- Signature: `function _deployToken( string memory name, string memory symbol, uint256 gen, address want ) private returns (address token, address quoteUsed)`
- Authority: internal (callers: summon, relaunch)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE; the deployed token mints its entire fixed supply to this registry inside its own constructor
- Reachability: Private, called once per generation from `_deployToken` CauldronRegistry.sol:1680 and CauldronRegistry.sol:1680. It is delegatecalled into the library so `address(this)` stays this registry, making the registry both the deployer and the holder of the whole supply. It returns the quote that was ACTUALLY achievable rather than the one requested (`quoteUsed` CauldronRegistry.sol:1685), and the caller records that value, which is why a mining failure downgrades the generation to native ether instead of reverting.
- Edges: `PoolOps.deployTokenAbove (CauldronRegistry.sol:1695), TRUSTED, library`
- Observations: comment at `CREATE2` CauldronRegistry.sol:1689 says this uses plain CREATE and NOT CREATE2 because a predictable address could be squatted; code at `salt` PoolOps.sol:742 deploys with CREATE2 from a mined salt, and the note two lines below at `CREATE2` CauldronRegistry.sol:1689 calls the registry the CREATE2 deployer.

### `_createPoolAndSeedWithBuy` — CauldronRegistry.sol:1725

- Signature: `function _createPoolAndSeedWithBuy( address token, uint256 activeTokens, uint256 ethAmount, uint256 reserveTokens, uint256 gen ) private returns (PoolId poolId)`
- Authority: internal (callers: _seedGeneration)
- Gate evidence: `UNGATED`
- Reads: `poolManager (line 1736)`; `positionManager (line 1736)`; `hook (line 1736)`; `nextReserveCeilingOffset (line 1738)`; `generationQuote (line 1739)`
- Writes: none
- Value: pays the whole funded amount and the active token tranche into the new pool, then buys the reserve back out as a visible first-block trade, inside `createAndSeedWithBuy` (line 1735)
- Reachability: Private, reached only from the atomic branch at `_createPoolAndSeedWithBuy` CauldronRegistry.sol:1725. It does NOT arm the callback window itself; the caller hoisted that, so it relies on `_seedBuyUnlocked` CauldronRegistry.sol:1733 already being set. The per-iteration ceiling comes from `nextReserveCeilingOffset` CauldronRegistry.sol:1738 and the pair from `generationQuote` CauldronRegistry.sol:1739, which the rebirth wrote before seeding at CauldronRegistry.sol:1739.
- Edges: `PoolOps.createAndSeedWithBuy (CauldronRegistry.sol:1735), TRUSTED, library`; `CauldronRegistry._recordSeed (CauldronRegistry.sol:1741), TRUSTED, in-cluster`
- Observations: none

### `_seedGeneration` — CauldronRegistry.sol:1757

- Signature: `function _seedGeneration( address token, uint256 activeTokens, uint256 ethAmount, uint256 reserveTokens, uint256 gen ) private returns (PoolId poolId)`
- Authority: internal (callers: summon, relaunch)
- Gate evidence: `UNGATED`
- Reads: `seeder (line 1755)`; `nextSeedWindow (line 1776)`; `poolManager (line 1778)`; `positionManager (line 1778)`; `hook (line 1778)`; `nextReserveCeilingOffset (line 1780)`; `seeder (line 1755)`; `nextSeedWindow (line 1776)`; `generationQuote (line 1782)`
- Writes: `_seedBuyUnlocked (line 1775)`; `_seedBuyUnlocked (line 1775)`
- Value: hands the active tranche plus the funding to either the streaming seeder or the atomic green-candle seed; on the progressive branch the token side leaves this registry for the seeder inside `createAndSeedProgressive` (line 1765)
- Reachability: Private, the single seed dispatcher for both ignition (`_seedGeneration` CauldronRegistry.sol:1757) and every rebirth (CauldronRegistry.sol:1757). It arms the PoolManager callback window for BOTH branches at `_seedBuyUnlocked` CauldronRegistry.sol:1775 and clears it unconditionally at CauldronRegistry.sol:1775, so the window is open for the whole seed rather than just the buy. The branch is taken only when a seeder is set AND the window is non-zero (`nextSeedWindow` CauldronRegistry.sol:1776); anything else falls through to the atomic path at `_createPoolAndSeedWithBuy` CauldronRegistry.sol:1773. A non-native generation is handled inside the library rather than here (`createAndSeedProgressive` CauldronRegistry.sol:1765).
- Edges: `PoolOps.createAndSeedProgressive (CauldronRegistry.sol:1777), TRUSTED, library`; `CauldronRegistry._recordSeed (CauldronRegistry.sol:1784), TRUSTED, in-cluster`; `CauldronRegistry._createPoolAndSeedWithBuy (CauldronRegistry.sol:1786), TRUSTED, in-cluster`
- Observations: comment at `_createPoolAndSeedWithBuy` CauldronRegistry.sol:1773 says BOTH genesis and relaunch now use the green-candle seed; code at `createAndSeedProgressive` CauldronRegistry.sol:1765 takes a different library entry whenever a seeder is set and `nextSeedWindow` CauldronRegistry.sol:1776 is non-zero.

### `_recordSeed` — CauldronRegistry.sol:1794

- Signature: `function _recordSeed(SeedResult memory r, uint256 gen) private returns (PoolId poolId)`
- Authority: internal (callers: _seedGeneration, _createPoolAndSeedWithBuy)
- Gate evidence: `UNGATED`
- Reads: `hook (line 1792)`
- Writes: `generationPoolId (line 1796)`; `generationPoolKey (line 1797)`; `generationPositionId (line 1798)`; `generationReservePositionId (line 1799)`; `reserveTickLower (line 1800)`; `reserveTickUpper (line 1801)`
- Value: NONE
- Reachability: Private bookkeeping, reached from both seed branches at `_recordSeed` CauldronRegistry.sol:1794 and CauldronRegistry.sol:1794. It is the only writer of the six per-generation position fields, including `generationPositionId` CauldronRegistry.sol:1798, which stays zero for a streamed generation and is what the teardown checks at `activeId` CauldronRegistry.sol:1616. It then pushes the live key to the hook at `setLiveKey` CauldronRegistry.sol:1802 so the legacy buyback can only spend into the current pool; that call is not wrapped, so a hook that refuses the key reverts the seed (DERIVED).
- Edges: `CauldronHook.setLiveKey (CauldronRegistry.sol:1802), TRUSTED, out-of-cluster`
- Observations: none

### `unlockCallback` — CauldronRegistry.sol:1812

- Signature: `function unlockCallback(bytes calldata data) external returns (bytes memory)`
- Authority: poolManager, and only while the seed-buy window is armed
- Gate evidence: `if (msg.sender != address(poolManager)) revert NotPoolManager(); (CauldronRegistry.sol:1812)`
- Reads: `poolManager (line 1813)`; `_seedBuyUnlocked (line 1814)`
- Writes: none
- Value: spends this registry's quote side and receives the bought token, inside `executeBuy` (line 1815)
- Reachability: Two independent conditions, both mandatory: the caller must be the PoolManager (`poolManager` CauldronRegistry.sol:1813) and the transient window must be open (`_seedBuyUnlocked` CauldronRegistry.sol:1814). The window is opened by the seed dispatcher at `_seedBuyUnlocked` CauldronRegistry.sol:1814 and by the ignition prime buy at `_seedBuyUnlocked` CauldronRegistry.sol:1814, and it is a plain storage bool rather than a transient slot, so it is set and cleared within the same transaction (DERIVED). The swap encoding lives entirely in the delegatecalled library at `executeBuy` CauldronRegistry.sol:1815, so it runs on this registry's balances.
- Edges: `PoolOps.executeBuy (CauldronRegistry.sol:1815), TRUSTED, library`
- Observations: comment at `relaunch` CauldronRegistry.sol:1752 says the callback is accepted ONLY while a relaunch buy is armed; code at `_seedBuyUnlocked` CauldronRegistry.sol:1814 accepts it whenever the flag is set, and ignition also sets it, at `_seedBuyUnlocked` CauldronRegistry.sol:1814 and CauldronRegistry.sol:1814.

## `CauldronToken`

### `constructor` — CauldronToken.sol:36

- Signature: `constructor( string memory _name, string memory _symbol, uint256 _generation, address _registry, uint256 _initialSupply ) ERC20(_name, _symbol)`
- Authority: deployer (the registry, acting through the delegatecalled PoolOps deploy)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: `generation (line 43, immutable)`; `birthBlock (line 44, immutable)`; `registry (line 45, immutable)`
- Value: NONE in native terms; the entire initial supply is minted to the registry at `_mint` (line 46)
- Reachability: Reached only from the generation deploy inside the linked library, at `CauldronToken` PoolOps.sol:668 for the mined CREATE2 path and `CauldronToken` PoolOps.sol:767 for the unmined fallback. Because the library is delegatecalled, address(this) is the registry, so the `registry` CauldronToken.sol:45 recorded here and the mint recipient are the same contract that orchestrates the generation. There is no minting function afterwards, so supply can only ever fall (DERIVED).
- Edges: none
- Observations: comment at `TOTAL_SUPPLY` CauldronToken.sol:29 declares a fixed 777 million supply as a constant; code at `_initialSupply` CauldronToken.sol:46 mints whatever amount the deployer passes and never compares it with that constant.

### `onlyRegistry` — CauldronToken.sol:49

- Signature: `modifier onlyRegistry()`
- Authority: internal (callers: burn)
- Gate evidence: `if (msg.sender != registry) revert NotRegistry(); (CauldronToken.sol:49)`
- Reads: `registry (line 50, immutable)`
- Writes: none
- Value: NONE
- Reachability: The token's only access control. `registry` CauldronToken.sol:50 is immutable, fixed at construction from the deploying contract at CauldronToken.sol:50, so the role can never be transferred or revoked (DERIVED). It guards exactly one function, `burn` CauldronToken.sol:58.
- Edges: none
- Observations: none

### `burn` — CauldronToken.sol:58

- Signature: `function burn(address from, uint256 amount) external onlyRegistry`
- Authority: registry
- Gate evidence: `onlyRegistry (CauldronToken.sol:58)`
- Reads: `registry (line 50, immutable)`
- Writes: none
- Value: destroys `amount` of the named holder's balance, reducing total supply (line 59)
- Reachability: Callable only by the immutable registry (`onlyRegistry` CauldronToken.sol:58). It needs no allowance and names an arbitrary holder, so it is the primitive behind both the dead-LP burn at `burn` CauldronRegistry.sol:865 and the 1:1 migration burns issued through the library at `burn` PoolOps.sol:1386 and PoolOps.sol:1386. The keeper batch reaches it for an opted-in wallet without that wallet signing anything, which is why the opt-in flag is revocable at `autoMigrate` CauldronRegistry.sol:1344.
- Edges: none
- Observations: comment at `leftovers` CauldronToken.sol:56 lists burning unclaimed migration leftovers as a use of this function; code at `burnUnclaimed` CauldronRegistry.sol:1412 records that path as obsolete in the reserve-LP model, and no such caller remains in the registry.

## `ICollectionRenderer (declared in ICauldron.sol)`

### `tokenURI` — ICauldron.sol:12

- Signature: `function tokenURI(uint256 tokenId) external view returns (string memory)`
- Authority: anyone (view on a proposer-supplied renderer contract)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only; no body here. It is consumed by the collections' metadata path at `tokenURI` CauldronCollection.sol:379 and `tokenURI` MiFrensGenesis.sol:745, and for badges at `tokenURI` CauldronCollection.sol:379. The address comes from the winning proposal, copied at `renderer` CauldronRegistry.sol:900 and handed to the factory config at `renderer` CauldronRegistry.sol:1207, so it is proposer-controlled code (DERIVED).
- Edges: none
- Observations: none

## `LaunchLib (declared in ICauldron.sol)`

### `displayName` — ICauldron.sol:38

- Signature: `function displayName(string memory name) internal pure returns (string memory)`
- Authority: internal (callers: summon, relaunch)
- Gate evidence: `UNGATED`
- Reads: `GUILD_SUFFIX (line 39, constant)`
- Writes: none
- Value: NONE
- Reachability: Pure and internal, so it is inlined into its callers: ignition at `displayName` CauldronRegistry.sol:742 and every rebirth at `displayName` CauldronRegistry.sol:967. The suffix is the file constant read at `GUILD_SUFFIX` ICauldron.sol:39, never a parameter, so a proposer controls only the prefix. The proposer's raw name is unbounded in length, and this concatenation is what the token and collection are then constructed with (DERIVED).
- Edges: none
- Observations: none

## `ICauldronGovernor (declared in ICauldron.sol)`

### `winner` — ICauldron.sol:45

- Signature: `function winner() external view returns (uint256 proposalId, BrewSpec memory spec)`
- Authority: anyone (view); the registry is its only in-tree caller
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the read the rebirth takes at `winner` CauldronRegistry.sol:903. The implementation at `winner` CauldronGovernor.sol:340 selects the best unconsumed proposal at `_bestUnconsumed` CauldronGovernor.sol:192 and reverts when there is none, which is why the rebirth checks liveness first at `hasProposals` CauldronRegistry.sol:841. Everything in the returned spec is proposer-authored, including the quote and the renderer (DERIVED).
- Edges: none
- Observations: none

### `markConsumed` — ICauldron.sol:46

- Signature: `function markConsumed(uint256 proposalId) external`
- Authority: registry (the implementation restricts the caller)
- Gate evidence: `if (msg.sender != registry) revert NotRegistry(); (CauldronGovernor.sol:763)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the one state-changing governor call the registry makes, at `markConsumed` CauldronRegistry.sol:1011. The implementation at `markConsumed` CauldronGovernor.sol:529 accepts only the wired registry and refuses a second consumption at `consumed` CauldronGovernor.sol:622. Its placement in the rebirth is load-bearing: anything that reverts after it rolls the consumption back with the transaction, which is why the only remaining revert sits immediately before it at `totalETH` CauldronRegistry.sol:992.
- Edges: none
- Observations: none

### `hasProposals` — ICauldron.sol:47

- Signature: `function hasProposals() external view returns (bool)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the liveness gate the rebirth applies at `hasProposals` CauldronRegistry.sol:841, alongside a zero-address check on the governor itself. The implementation at `hasProposals` CauldronGovernor.sol:336 simply reports whether an unconsumed proposal exists at `_bestUnconsumed` CauldronGovernor.sol:740.
- Edges: none
- Observations: none

## `ICauldronCollection (declared in ICauldron.sol)`

### `mint` — ICauldron.sol:52

- Signature: `function mint(address to) external returns (uint256 tokenId)`
- Authority: the collection's wired minter (the volume hook)
- Gate evidence: `if (msg.sender != minter) revert OnlyMinter(); (CauldronCollection.sol:208)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the mint the hook performs when a play wins, at `mint` CauldronHook.sol:2448. The implementation at `mint` CauldronCollection.sol:207 accepts only the wired minter and refuses once the cap is reached at `maxSupply` CauldronCollection.sol:209. The registry is what wires the hook in, at `setCollection` CauldronRegistry.sol:1233 for a fresh brew and at `setMinter` CauldronRegistry.sol:1259 for the continuation.
- Edges: none
- Observations: none

### `totalMinted` — ICauldron.sol:53

- Signature: `function totalMinted() external view returns (uint256)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration satisfied by a public state variable rather than a written function: the counter is incremented in place at `totalMinted` CauldronCollection.sol:210, so the interface is served by the compiler-generated getter (DERIVED). The hook reads it for the curve anchor at `totalMinted` CauldronHook.sol:2189 and for mint-out checks at `totalMinted` CauldronHook.sol:2189.
- Edges: none
- Observations: none

### `maxSupply` — ICauldron.sol:54

- Signature: `function maxSupply() external view returns (uint256)`
- Authority: anyone (view)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the per-brew cap the hook compares against at `maxSupply` CauldronHook.sol:2304 and CauldronHook.sol:2304. The value originates in the registry, either from the owner setting at `nftMaxSupply` CauldronRegistry.sol:602 or from the proposer's request clamped at `MAX_NFT_SUPPLY` CauldronRegistry.sol:962, and it is fixed when the collection is constructed (DERIVED).
- Edges: none
- Observations: none

## `IDeathChecker`

### `isDead` — IDeathChecker.sol:27

- Signature: `function isDead(PoolId id, uint256 volume24h, uint256 deathThreshold) external view returns (bool dead)`
- Authority: anyone (view on a pluggable module)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the swappable death rule. The hook calls it only when one is wired, inside a try/catch at `isDead` CauldronHook.sol:1651, and falls back to the built-in volume comparison at `deathThreshold` CauldronHook.sol:1804 on any revert, so a broken module cannot brick the rebirth. The volume it is handed is summed across a generation's sibling pools at `getVolume24h` CauldronHook.sol:1677. The registry's rebirth gate consumes the answer at `isDead` CauldronRegistry.sol:833.
- Edges: none
- Observations: comment at `owner` IDeathChecker.sol:13 says the hook owner points the hook at a new checker; code at `registry` CauldronHook.sol:1888 accepts the registry address as well as the owner.

## `ILiquidatorMintable`

### `mintLiquidatorWithStats` — ILiquidatorMintable.sol:38

- Signature: `function mintLiquidatorWithStats(address to, LiqStats calldata s) external returns (uint256 tokenId)`
- Authority: the collection's wired liquidatorMinter (the perp engine)
- Gate evidence: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (CauldronCollection.sol:409)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration only. The implementation at `mintLiquidatorWithStats` CauldronCollection.sol:402 forwards to `_mintLiquidator` CauldronCollection.sol:397, where the single caller check lives. Badge ids come from a separate range at `LIQUIDATOR_ID_BASE` CauldronCollection.sol:394, so the art tranche's counters are untouched, and the stats write is skipped entirely for a zero victim at `victim` CauldronCollection.sol:415.
- Edges: none
- Observations: none

### `mintLiquidator` — ILiquidatorMintable.sol:44

- Signature: `function mintLiquidator(address to) external returns (uint256 tokenId)`
- Authority: the collection's wired liquidatorMinter (the perp engine)
- Gate evidence: `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter(); (CauldronCollection.sol:409)`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: The stats-free form, kept for an engine deployed before the stats existed. The implementation at `mintLiquidator` CauldronCollection.sol:396 passes an all-zero record into the same internal path at `_mintLiquidator` CauldronCollection.sol:397, so the gate and the id range are identical to the stats form (`liquidatorMinter` CauldronCollection.sol:353).
- Edges: none
- Observations: none

### `liqStats` — ILiquidatorMintable.sol:47

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

### `surtaxBps` — IPolicies.sol:25

- Signature: `function surtaxBps(PoolId id, uint256 initBlock, uint256 maxBps, uint256 windowBlocks) external view returns (uint256 bps)`
- Authority: anyone (view on a pluggable module)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the anti-sniper surtax rule. The hook consults it only when wired, through the linked library, inside a try/catch at `surtaxBps` SurtaxLib.sol:46, with the hook passing its own configured peak and window at `MAX_SNIPE_BPS` CauldronHook.sol:1567 so a simple module can reuse them. The module is installed by the owner or the registry at `surtaxPolicy` CauldronHook.sol:2085. It returns a number and never custodies funds, so a malicious module's blast radius is the fee rate it reports (DERIVED).
- Edges: none
- Observations: none

## `IOddsPolicy (declared in IPolicies.sol)`

### `oddsBps` — IPolicies.sol:37

- Signature: `function oddsBps(uint256 playWei, uint256 maxBps, uint256 fullVolumeWei) external view returns (uint256 bps)`
- Authority: anyone (view on a pluggable module)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the gacha win-probability rule, consulted inside a try/catch at `oddsBps` CauldronHook.sol:2367 and installed alongside the other two modules at `oddsPolicy` CauldronHook.sol:2086. The play size it receives is denominated in the units the hook measures a play in, which is the same unit its own configured full-volume threshold uses (DERIVED).
- Edges: none
- Observations: none

## `ICurvePolicy (declared in IPolicies.sol)`

### `priceAt` — IPolicies.sol:49

- Signature: `function priceAt(uint256 k, uint256 base, uint256 step) external view returns (uint256 cost)`
- Authority: anyone (view on a pluggable module)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE
- Reachability: Declaration of the mint-cost curve, consulted inside a try/catch at `priceAt` CauldronHook.sol:2318 with the hook's own base and step, and installed at `curvePolicy` CauldronHook.sol:2087. The base the hook passes is the value the registry pushes from the winning proposal at `setNftCurveFrom` CauldronRegistry.sol:1146.
- Edges: none
- Observations: none

## `IFeeRouter (declared in IPolicies.sol)`

### `route` — IPolicies.sol:70

- Signature: `function route(uint256 feeAmount, address guild, address vault, uint256 guildBps, uint256 floorBps) external view returns (uint256 toGuild, uint256 toFloor, uint256 toRelaunch)`
- Authority: anyone (view on a pluggable module)
- Gate evidence: `UNGATED`
- Reads: none
- Writes: none
- Value: NONE; the module only returns amounts, and the hook performs every send itself
- Reachability: Declaration of the fee-split structure. The hook calls it in a try/catch at `route` CauldronHook.sol:1327 and accepts the answer ONLY when the three parts sum exactly to the fee at `feeAmount` CauldronHook.sol:1407; otherwise it falls through to the built-in split at `wantGuild` CauldronHook.sol:1460. The router is installed by the owner or the registry at `feeRouter` CauldronHook.sol:2097, and the reference implementation makes the sum exact by construction at `toRelaunch` DefaultFeeRouter.sol:24.
- Edges: none
- Observations: none
