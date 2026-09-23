# Shared interfaces and schemas — full source traversal, final verification pending

Read all four files: IPolicies.sol, IDeathChecker.sol, ILiquidatorMintable.sol,
ICauldron.sol. Counted as source traversals, not implementation safety proofs.
Compiler graph resolves their declarations; consumer/deployed-ABI parity remains.

## IPolicies.sol

ISurtaxPolicy.surtaxBps, IOddsPolicy.oddsBps, ICurvePolicy.priceAt and
IFeeRouter.route are external view declarations, no custody or implementation.
Owner/registry selection and numeric caps belong to their callers, not these
interfaces. Relevant reviews: SURTAX/POLICY_MATH, GACHA_LIB and FEE_ROUTING.
Interface wording that a reverting module can never brick execution is too
broad: gas exhaustion, malformed successful data and downstream arithmetic
require separate defenses. Surtax/router malformed-data regressions exist;
odds/curve fallback completeness and consumer units remain obligations.
ETH-named input comments must be reconciled with actual normalized/quote units.
Fee three-tuple order is guild/floor/relaunch; compiled callsite/consumer joins
must preserve this order, not merely selector identity.

## IDeathChecker.sol

isDead(PoolId,uint256,uint256) external view returns bool: configurable read-only
policy can choose death classification within caller authority. No intrinsic
access gate. Caller must decide fallback on revert, malformed bool, code-free
address and oversized data. Comment says currency0 volume; compare with hook's
current oracle-normalized volume before treating this as external implementer
specification. Full CauldronHook death-path review remains open.

## ILiquidatorMintable.sol

LiqStats fields read in order: address victim, bool wasLong, uint8 leverage,
uint96 collateralWei, uint96 bountyWei, uint64 blockNo, uint128 entryPrice,
uint128 liqPrice. Struct declaration has no writes/casts; actual packing and
narrowing occurs at producers/storage consumers and requires compiler checks.
ETH-named fields after quote changes need denomination/display reconciliation.
Two mint selectors return uint256; liqStats returns this exact tuple. No interface
access gate: collection implementation must enforce liquidatorMinter. Badges
excluded from art supply by implementation; FS-badge-floor-01 showed consumers
must enforce this too. PerpSwapLib.tryMintBadge observes call success without
verifying returned id/mint, so dependency failure handling remains to validate.
Earned badge claim, stat truncation and renderer consumer paths still open.

## ICauldron.sol

MetadataMode is a two-value enum (BaseURI/Renderer); ABI decoding of out-of-range
values reverts. BrewSpec dynamic tuple order: name, symbol, mode, baseURI,
renderer, website, socials, quote, nftSupply, volumePerNFT, proposer. No bounds or
sanitization imposed by schema; governor/launch and UI consumers must enforce
needed limits. ICollectionRenderer.tokenURI is an untrusted external string
return; returndata size/revert handling belongs to collection/render path.
LaunchLib.displayName concatenates supplied name and fixed guild suffix: pure,
no calls/state/custody, cost scales with input name length. Calling governor
validation and proposal gas bounds remain required. ICauldronGovernor winner,
markConsumed and hasProposals define lifecycle calls, no authorization themselves.
ICauldronCollection mint/totalMinted/maxSupply define art mint/supply surface;
mint access control and accurate art-only count require implementation evidence.
