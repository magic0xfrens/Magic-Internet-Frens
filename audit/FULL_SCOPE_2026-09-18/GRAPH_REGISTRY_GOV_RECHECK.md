# REGISTRY and GOVERNANCE Graph Recheck

## Scope and method

All 89 REGISTRY nodes and all 48 GOVERNANCE nodes were read from their current comment-masked bodies. Mechanical fields are copied exactly from the two skeleton JSON files. Semantic edges were retained only when the method occurs in executable body text, except for the explicitly modeled selector-level `RedemptionExt` targets behind the registry's full-calldata delegatecall stubs.

Alias edges now use source-declared types: `hook` → `CauldronHook`, `governor` → `ICauldronGovernor`, `collectionLedger` → `ICollectionLedger`, collection metadata → `ICollectionMetadata`, generation-token burn → `CauldronToken`, MiFrens voting → `IVotes`/`IVotes721`, and quote admission → `IRegistryQuotes`. Raw `call`, `staticcall`, and `delegatecall` sites retain their actual dynamic expression.

Comment-only/keyword matches were removed and real omissions added. Material additions include the registry relaunch's internal phases (`_perpHousekeep`, `_removeLiquidity`, `_deployToken`, `_flushLegacyAtRelaunch`, `_seedGeneration`, collection continuation/deployment), CauldronGovernor's live calibration probes and proposal wrappers, and TreasuryGovernor's pricing, stalled-envelope, winner, pass, bench, and allowance dependencies.

## Source-derived candidates (not confirmed findings)

- **HYPOTHESIS — relaunch rollback liveness:** `relaunch` calls `markConsumed` before multiple external seed, hook, collection, and PositionManager interactions. Any later revert atomically restores the proposal to unconsumed state. The source contains several defensive clamps/catches, but totality still depends on every uncaught post-consumption dependency accepting the selected configuration. This is a property to fuzz across adversarial-but-allowlisted quote/token implementations, not a conclusion from comments.
- **DERIVED — best-effort recovery can omit assets:** `_removeLiquidity` swallows a failed rotated-leg delegate recovery, and `_perpHousekeep(true)` swallows a failed generation sync. This favors rebirth liveness over completeness; the state transition can continue without proving every auxiliary position/value source was recovered or synchronized.
- **HYPOTHESIS — unchecked ERC-20 boolean returns:** emergency LP withdrawal/sweep, successor migration, and the genesis airdrop use typed `transfer` without checking the returned boolean. Standard first-party tokens revert or return true, but an arbitrary emergency token or allowlisted nonstandard asset can report false without reverting, making the operation's event/state narrative diverge from actual movement.
- **DERIVED — bounded governance visibility:** CauldronGovernor's winner recomputation scans the fixed eight-slot bench rather than all proposals. This makes execution bounded, but correctness depends on `_benchRecord` preserving every proposal that could later become the best ended, unconsumed candidate.
- **HYPOTHESIS — optional oracle permits unpriceable mandates:** TreasuryGovernor deliberately treats an unset quote oracle as disabling priceability checks. If the registry allowlist contains an asset the downstream hook cannot value, governance can approve it while volume/death accounting may degrade. Deployment wiring, rather than this contract, must establish the intended invariant.
- **DERIVED — guardian authority:** TreasuryGovernor's guardian can cancel proposals/envelopes and rotate the guardian address without a delay inside this contract. That is an explicit privileged trust boundary, not permissionless governance.
- **DERIVED — caller-sized/bounded loops:** proposal leader scans are fixed at eight slots. `conversionFor` is bounded by input widths but can iterate up to 30,000 times for small `sliceBps`; as a pure helper this can still be impractical when called on-chain by another contract.

The independently reproduced duplicate native treasury-position issue is in `RedemptionExt`, outside these owned files; this recheck neither adjudicates nor modifies it.

## Residual limitations

REGISTRY has zero strict-join residuals. GOVERNANCE retains two exact pinned-dependency residuals: OpenZeppelin `IVotes.getVotes` and `IVotes.getPastVotes` in CauldronGovernor. `IVotes` is not represented by a first-party skeleton node or the joiner's explicit dependency-type allowlist; the annotations keep the exact source type rather than weakening it to an alias. TreasuryGovernor's local `IVotes721` interface resolves exactly.

Low-level calls establish only that EVM dispatch occurs; they do not prove runtime bytecode identity. Selector-level facet targets express intended dispatch based on unchanged calldata, while the actual EVM edge remains `ext.delegatecall`. Constructor base calls, casts, ABI operations, and hashing are not modeled as dispatch edges.
