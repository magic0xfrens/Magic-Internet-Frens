# Venue stack and volume scripts — full source traversals

Four files fully read, including embedded VenueSeeder/RecoverVenue contracts,
interfaces, constructor, receive and all function bodies. No scripts run.
No final sign-off.

## SellVolume / SwapVolume

Both create PoolSwapTest and hardcode native/token fee0 spacing200 hooked pool;
no lookup ensures current-generation key. Sell approves unlimited allowance and
ignores bool (first-party token is assumed), loops exact-input with max tick,
empty hookData. Buy encodes player, loops native budget with min tick, reports
crystals and NFT balances via current selectors. No min-output protection or
actual balance/fee assertions, so running these is not a correctness test.
Extreme amounts may change sign on uint->int cast; counts/budgets unbounded.
Testnet probes need explicit network/funds/config limits before use. Report-only
view calls can fail after simulated swaps; broadcast atomicity not assumed.

## TopUpVenue / RecoverVenue

No-key startBroadcast; deploys new VenueSeeder, mints mock USDG to it, seeds
native/mock full-range fee3000 spacing60. Optional slip update narrows uint256
to uint16; target owner and intended value need preflight. Default budget/slippage
narrative is historical, not a verified current envelope fill guarantee.
Recovery reconstructs same native/mock/unhooked key and calls seeder as its
original deployer. Wrong manager/asset/key or broadcaster cannot be assumed safe.
This script is explicitly mock-venue support, not production quote minting.

## DeployRotationStack

run reads role/wiring inputs, creates freely mintable mock and oracle, reuses
rotator/governor only if BOTH provided, otherwise deploys a new pair. Supplying
just one silently discards intended partial reuse; verify operator configuration.
Reused rotator setArbParams/setVenue still require broadcaster authority even
if registry owner differs. Oracle feed addresses are hardcoded Sepolia constants;
no chain guard, live freshness or implementation verification in this review.
Mock price model must not be used as production collateral valuation.
Governance environment windows narrow to uint64. Oracle ownership handed to
registry owner, but new rotator/governor remain broadcaster-owned here unless
separately handed off. Creates/mints/transfers mock venue funding; curated venue
pins complete PoolKey. Registry allowlisting/wiring only when owner==broadcaster,
otherwise printed instructions; a printed deployment summary is not usable
rotation proof. Asset scale, engine oracle and hook integration remain gates.

## VenueSeeder (deployed helper within script file)

Constructor immutably records deployer. seed/seedBand/recover require deployer;
receive accepts native refunds. seed delegatecalls linked PoolOps.openOrAddPair
using helper balances and stores returned positionId. No existing-position guard:
a later seed may overwrite the only recoverable ID. Needs funded real-PositionManager
reproduction; do not yet claim permanent loss across arbitrary helpers/managers.

seedBand validates bandBps1..5000 and initialized pool, calculates ticks/liquidity,
approves Permit2 and position manager, encodes mint/settle pair and stores predicted
nextTokenId. Helper has no ERC721 transfer rescue or arbitrary call. No explicit
msg.value==ethAmount, spacing>0, tick-bound or uint160 allowance bound; caller is
trusted deployer. External manager/asset parameters are not retained or validated.
Formula delta=bandBps*995/100 gives 4,975 ticks for 500bps; roughly 64% upper
price movement, not described 5%. Lead requires runtime tick capture and exact
liquidity/return analysis before classification. Full-range seed uses existing
PoolOps path; repeated position ID replacement is shared with seedBand.

recover calls removeAll on stored ID then clears it, sweeps whole supplied token
balance and all native balance to immutable deployer. Return values represent
removeAll amounts, not necessarily entire swept balances (loose donations/fees).
Failed calls revert atomically. Transfer bool ignored for mock token (OZ returns
true); unrelated assets and lost prior position IDs have no explicit rescue.
Reentrancy from owner recipient stays within owner authority but needs settlement
verification. Position identity, fee recovery, approvals and band boundary tests
are required. This is deployed code despite living in deploy/.

Repeated-seed lead confirmed with funded real local managers; see FS-venueseed-01.
Both entrypoints patched to require prior recovery. Follow-up lifecycle test
running; no final verification or deployed-state recovery implied.

## Final disposition (2026-09-23)

Final: band width = FS-venueband-L01 Low (10x documented band, optional testnet venue). Signed off.
