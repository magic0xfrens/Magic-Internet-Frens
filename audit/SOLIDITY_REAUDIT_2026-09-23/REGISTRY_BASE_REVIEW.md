# CauldronBase — executable traversal complete, final verification pending

Read all state/interface declarations, constants and four executable bodies:
constructor, floorPerFren, _redeemBlocked, renounceOwnership. Read storage and
floor/emergency/treasury-leg narrative. No production edit.

- Constructor initializes Ownable to deployer; ReentrancyGuard storage is shared
  by registry and facet. Direct facet deployment has its own owner/storage and
  does not establish delegated access authority.
- floorPerFren: no shares -> zero; otherwise divide reserve by shares minus
  treasury-held OGs when held < shares, else full shares. No division by zero;
  all-held fallback deliberately permits resale. Requires exact treasury-held
  accounting and art/OG ID admission across custody paths. Cross-contract
  conservation cannot be inferred from this pure denominator rule.
- _redeemBlocked: paused AND no armed emergency. Once emergencyReadyAt is nonzero,
  fast pause cannot suppress exits. Emergency reset/execute/adopt ordering and
  clock-based custody protection require registry/facet review.
- renounceOwnership: onlyOwner then always RenounceDisabled. Inherited transfer
  and owner getters remain; role transfer to an unusable contract is not
  prevented. Deployment role wiring remains required.

Interfaces read: ICauldronFactory.Config/deployBrew/deployVault;
IMiFrensContinuable setters/totalMinted/custodyTransfer/everMoved; IVaultClose.close;
IPerpSync.syncGeneration/openCount; IPerpBook.requoteBook;
ICollectionLedger.totalEntitled; IPositionManager modifyLiquidities/nextTokenId/
getPositionLiquidity. No interface enforces roles, transfer success or units;
consumer/implementation selector and tuple compatibility remain obligations.

All 61 compiler storage entries (including inherited owner/reentrancy state,
packed members, mappings and nested TreasuryLeg/PoolKey types) compared recursively
across CauldronBase, CauldronRegistry and RedemptionExt. They match exactly in
current source-matched compiler graph. Evidence:
remediation/REGISTRY_FACET_STORAGE_CHECK.json. This closes one static layout gap,
not facet-call authorization, initialization, dynamic writes or deployed parity.

Critical cross-file state groups: generation token/quote/pool/id watermarks;
reserve and genesis entitlement; collections/vaults/ledger; owner/guardian/
successor/claimGate/igniter; prime funding; emergency readiness; tracked treasury
legs and per-asset foreign proceeds. Every writer and exit still needs joining
against registry/facet/PoolOps. Inline slot comments are not authoritative.
