# PerpEngine — executable source traversal complete, final verification pending

Read declarations, state, constructor, modifiers, all executable bodies, assembly
and receive in the 3,000+ line engine. Read narrative around oracle, sweeps,
settlement, generation adoption and payout retirement; excluded comment-only
lines for the remaining executable traversal. Historical comment claims are not
fresh security evidence. Full scope requires the gaps below, not reading alone.

## Authority and custody

Constructor fixes manager/hook/registry/NFT; Ownable controls risk/routing/funding
and vault selection, renunciation forbidden. Quote starts native; deploying into
an already ERC20-quoted generation requires explicit adoption validation.
notNested checks inLocked/liqReentry; nonReentrant guards public open/settle/vault
withdrawal/requote paths. Hook sweep is hook-only and uses separate nesting flags;
selfSweep is self-only, callback is manager-only. Native receive accepts funds
without booking them. Owner/admin setter tests and all callback interleavings
remain required; existence of modifiers alone is insufficient.

Quote custody: plv, insuranceEth, token-yield pot, shorts' collateral/proceeds,
payoutOwed, and unbooked residue. Long principal is a receivable in longOiEth;
long collateral has already bought tokens. Token custody: free plvToken, tokens
held for longs, and stranded old-generation balances; shortOiToken is debt,
not held inventory. Every source balance/counter path needs a stateful model.

## Traversed function groups

| Group | Functions and observations/gaps |
|---|---|
| asset/registry/pool getters | totalEth/freeEth/totalTokenAssets/freeToken, _tok/_gq/_bal/_liq/_col/_gen, _key/_pid/_slot0/_sqrtP, _quoteIsNative/_q. _key uses current registry token, whereas some orientation decisions use syncedToken; prove divergence lifecycle cannot mix generations. quoteUnit multiplication can overflow extreme owner/dependency inputs. |
| mark/funding | _currentTick, poke/_writeObs/twapTick, blocksVolumeLink, markSqrtPriceX96, activeEthDepth/maxLeverage, _quoteAt/_quoteEth/_quoteMark, _pokeFunding/_fundingDelta/fundingDelta. Mark-range patch under verification. Public poke is optional; hook sweep calls funding internally. Cumulative arithmetic, cap settlement, warm-up, temporal price manipulation and signed rounding require models. |
| opening | openLong/openShort, _openPrologue/_guardOpen/_isDead, _takeFee/_checkNotional, _book/_addOpen. Pull then guards (rollback on failure), fees attributed by side, utilization/OI caps and swaps, finally book then best-effort self sweep. _book narrows collateral to uint128 without explicit bound; prove supported asset/price/depth restrictions or reproduce. _isDead fails open if hook read reverts. |
| liquidation/closing | close/liquidate/sweepLiquidations, _project/selfSweep/_sweepAfterOpen/_doSweep, _condemnedByThisTrade/_tryLiquidate, _deadPrep/_open/forceCloseDead/forceCloseAllDead. Book capped at 64, kills at 30, cascade passes at four, forced iterations at 96. Pretrade snapshots ids to resist swap-pop. Later cascade membership checks use projection state before refresh: re-evaluate projection freshness after settlements using mixed-book evidence. Gas/status semantics must be measured at limits. |
| trigger math | isLiquidatable/_underwater/_liqTest/_insolventVal/_underwaterVal/_throttle. TWAP maintenance plus worse spot/projected insolvency; insolvent bypasses throttle. Throttle is timestamp-based. Accounting, execution price and flag comparisons need funded long/short boundary tests. |
| settlement | _settle/_ownerFloor/_rebook/_removeOpen. Delete/decrement before swap then partial short rebooks under same id. Partial return bypasses final funding/penalty but retains funding snapshot and surviving collateral basis. Long unsold tokens become PLV inventory; death short remainder written off. Funding debit limited to residual; credit limited to insurance+PLV. Follow with fee/keeper/trader payments. Validate conservation and repeated partial-close economics with independent model. |
| manager paths | _run/_swapExactIn/_buyUpTo/unlockCallback/_swapBody/_ethToToken. Engine manager-only callback decodes SwapReq; nested in-hook settlement uses existing unlock. Linked-library settlement and exact-output limits assume current quote/token ordering. Validate manager deltas and callbacks, not just value returned. |
| book conversion | _bookSlots/requoteBook/syncGeneration. Compiler-packed slot/delegatecall correspondence inspected; library checks registry authority. Generation sync requires zero open positions, migrates inventory best-effort, books stranded difference, resets ring, converts or writes off quote, adopts then seeds ring. Retry/cross-generation custody and owner write-off policies need integration. |
| funding and loss | _insuranceNeed/_utilGate/_routeFee, _replenishPlv/_absorbPlvLoss/_bd/_writeOffTok/_vf/_vw. Insurance first, then PLV, explicit unabsorbed diagnostic; fee credits differ native/ERC20 hook routes. Zero recipients may retain unbooked fee residue. Independent per-asset liability/balance reconciliation pending. |
| payout transport | _pullQuote/_pushQuote/_sendEth/_payOut/_tryPush/_safeTransfer, retirePayout/claimPayout. Reverting native recipients become owed claims; owner may write off, nonowner retirement only during quote divergence and successful payment. Token false/malformed/mutation-before-false return behavior remains a lead; see library review. No forced zero claims count as execution. |
| badge | _killStats/_awardBadge/claimLiquidatorBadges. Stats clamp values, derive prices from quote amounts; quote-aware render units pending. Mint bool interpreted as success; failure banks badge count, claim loop caller bounded by own credits but uncapped in one transaction. Earned-badge integration to art-floor rejection remains required. |
| supply/withdraw | fundPlv/fundPlvToken/_pullTokenIn/fundInsurance, creditPerpFee/creditPerpFeeToken/creditPerpFeeAsset/_creditPerp/_pullIntoPlv, fundFromVault/fundTokenFromVault/withdrawPlvTo/withdrawTokYieldTo/withdrawPlvTokenTo/_vaultPaid. Hook/vault gates distinguish attribution. Token pull ignores returned bool: first-party token trust must be established, not generalized to arbitrary tokens. Deposit callbacks can encounter fundInsurance without nonReentrant. |
| admin | setFees/setRisk/setTiers/setRouting/setVaultSplit/setGuards/setVault/setVaultLimits/setMinCollateral/skimInsurance/renounceOwnership. Numeric bounds mostly explicit; tiers may be unsorted/zero, owner can choose codeless dependencies, insuranceFloor scaling can overflow. FS-perpvault-01 fixes existing-vault eligibility, not new-vault validity. Review intended governance abilities separately from outsider attacks. |
| frontend/read | positionHealth and all public variable getters, receive. Health is mark/spot-sensitive; ABI and actual quote denomination must match indexer/UI. No frontend/deployed parity sign-off yet. |

## Evidence and pending work

PERP_PACKED_SLOT_REVIEW.json verifies full uint256 slot shapes, address offsets
and 16-bit representability against fresh compiler layout; source encoder and
library decoder orders agree. Not dynamic write isolation or deployment proof.

Confirmed malformed-mark issue reproduced through production beforeSwap with
no external poke in test sequence. Current candidate changes only _currentTick
return admission. Surface check passes, runtime test/size completion pending.

Other existing local tests cover selected partial-close, write-off and cascade
paths; rerun source-matched assertions before treating them as new evidence.
No complete solvency/gas/invariant validation or final sign-off is claimed.

## Final disposition (2026-09-23)

Final: R23-L1 not reproduced in 256 mixed-leverage fuzz runs + 24-step ladder (21 in-sweep kill fills) — Informational wording mismatch. Engine open/close and relaunch force-close exercised in the local rehearsal. Signed off.
