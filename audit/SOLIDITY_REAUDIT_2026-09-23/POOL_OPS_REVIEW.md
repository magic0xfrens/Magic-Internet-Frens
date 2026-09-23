# PoolOps — full source traversal, final verification pending

All1,663 source lines including structs/interfaces/constants and executable
bodies read. Linked external library executes in caller custody context; no
independent authentication in library. Registry/helper admission and callback
arming are essential. Earlier badge-floor patch included, no new edit here.

| Functions | Analysis and outstanding obligations |
|---|---|
| creatureFor | six-name cycle, gen0 underflows; callers must supply positive generation. |
| _approve/_balance/sendAsset | ERC20 approval ignores bool and assumes ordinary allowance semantics; Permit2 amount narrows uint160 and deadline uint48. Native send checks success; optional-return token transfer decodes bool and reverts malformed replies. Caller/quote admission supplies trusted identity and token behavior. |
| _minQuoteFor/_sqrtPrice | Raw-quote representability floor, FullMath quotient then Babylonian square root. Clamping changes initial price for low quote budget; no independent safe seed guarantee. ratio0 returns0, max quotient x+1 overflow and valid TickMath range need boundary proof against actual reachable supply/budget. |
| createAndSeed | currency0 quote, currency1 token; initialize, active full-range seed, optional reserve ticks/seed. Correct ordering relies on token mining/admission. No permission checks inside library. |
| createAndSeedProgressive | Non-native atomic fallback; native base fraction currently100%, _greenCandle then immediate return, no campaign. Dormant streaming branch approves remainder and starts shared SeederConfig. A future base change invalidates present liquidity/keeper assumptions. |
| createAndSeedWithBuy/_greenCandle | Total active+reserve, proportional active quote less64-unit buffer, full-range mint, exact-output reserve buy via caller unlock, reserve band at post-buy tick. Consumes decoded actual bought amount; exact-output completeness and fee-exemption/manager callback assumptions need integration. Signed amount casts safe only with bounded production supply. |
| executeBuy/primeBuy | Callback assumes msg.sender PoolManager, quote0/token1, correct delta signs. Native settle or sync/transfer/settle quote, take token to chosen recipient. Host registry must authenticate manager and armed unlock. Exact input has min-tick only and no minOut; bounded/atomic priming design needs economic check. |
| deployTokenAbove | Registry-context CREATE2, up to1024 salts with hash over creation+args, strict address above watermark/quote. Asserts derived address. Fallback plain CREATE/native may not preserve watermark for future adoptability; reachability of exhausting salts is remote but should be explicitly qualified. Public-factory squatting narrative does not apply to registry-context CREATE2. |
| _seedActive/_seedReserve | Full-range aligned ticks, LiquidityAmounts and encoded MINT/SETTLE/SWEEP. Return predicted NFT ID; caller must retain every ID. uint128 amount maxima narrow; production bounds required. Reserve zero-liquidity returns0 before mint, leaving loose tokens. Active mint lacks zero-liquidity skip (expected to reject unusable launch). |
| openOrAddPair | Requires positive budgets and token>quote. Tries initialize; on failure only proceeds with nonzero live slot0 and sizes at live price. ALWAYS mints a new position; it never increases old NFT. All callers reviewed for ID replacement, including confirmed VenueSeeder defect and destination consolidation in RedemptionExt. |
| removePartial/removeAll | Partial<=50% of current liquidity, positive rounded take; full decrease/take/burn. Measures actual quote currency0 and token balance deltas. Full returns0 immediately for zero-liquidity NFT (no burn/fee collection). Verify zero-liquidity residual fees/position semantics. No minimum asset withdrawal amounts, protocol accepts spot holdings on teardown. |
| seedFunding/_pullAsset/_peek/_pullEth | Best-effort vault close; select funded proposal quote without abandoning recovered incompatible asset, native fallback or old quote. MIN_SEED_UNITS and peek before reserve mutation. Native vault sweep omitted from non-native reported numerator, loose native still remains. Claimed 'nothing reverts' narrative overstates checked arithmetic/ABI and external-balance guarantees; ordinary trusted hook matters. Cross-asset loose balances need recovery accounting. |
| claimFromReserve/addToReserve | Convert amount to floor-rounded liquidity; withdrawal caps by held liquidity, takes BOTH assets to recipient but measures token1 only. Zero-liquidity returns0. Add measures actual consumed token, zero max quote prevents in-range funding. No universal positionId0 early guard; some comments overstate it. Geometry, capacity and fee effects require funded boundary tests. |
| migrateUpTo/migrateOne/autoMigrateBatch | Capacity assumes full token1 reserve geometry. Burn first then measured claim; shortfall>1e12 reverts, <=dust accepted even potentially zero payout. Batched opt-in holders skip insufficient nominal capacity, but migration revert (e.g. reserve in-range) still reverts whole batch. It is not a universal catch-per-holder routine. Verify reachable dust loss and actor consent, no new severity yet. |
| doLegacyNote/materializeLegacy | MiFrens continuation splits by OG+forged count, other collections receive all. Live sweep then reserve add credits measured consumption; zero add returns after sweep, potentially leaving loose uncredited tokens. Death path burns and carries number. Dust accumulation/recovery lead needs reproduction; no double-credit assertion without backing invariant. |
| crystallizeCollection | Only uncrystallized, wired collection/ledger and nonzero funding. mulDiv swept/total in same units, freezes vault outstanding excluding OG. Links to prior patched ledger retirement semantics. |
| _eligible/_ogCount/recycleCollection/buyCollection | Static genesis count, art-ID admission plus ownership, forged-only denominator, OG blocked in both directions. Recycle debits ledger, custody transfer and reserve claim then dust shortfall check. Buy pulls2x floor, deposits measured amount, ledger buyback and custody. Need preserve ledger/asset rollback and verify zero deposit path (ledger enforcement), not infer safety from checks alone. |

Final gates: all host callback/access paths, reserves vs outstanding migration+
OG+legacy claims, zero liquidity/dust boundaries, multi-decimal cold-balance
seeding, rotation/new-position custody, hostile quote assumptions, full regression
and source-matched size/ABI/storage/consumer/deployment evidence. No final sign-off.

## Final disposition (2026-09-23)

Final: dust and zero-liquidity leads are Informational (bounded CLAIM_DUST; loose uncredited tokens after zero reserve add). Signed off.
