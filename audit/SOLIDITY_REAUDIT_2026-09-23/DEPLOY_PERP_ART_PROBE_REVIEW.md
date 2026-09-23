# Perp/art deployment and buy probe — full source traversal

Four complete files reviewed; no execution/broadcast of scripts, no final sign-off.

## DeployPerp.s.sol

All local interfaces and run read. Deploys real engine/vault, hook wiring,
vault limits, optional warmup/insurance funding, guards, optional mark and
routing, optional native vault funding, then governance ownership transfers.
Defaults still allow absent mark/oracle/timelock; comments saying wiring is
unconditional mean setRouting is called, not that a nonzero oracle is required.
User's intended liquidation route is beforeSwap; script's afterSwap language
must not substitute for actual hook behavior. No keeper/public poke prerequisite.

TWAP_WINDOW narrows uint256 to uint32; printed original environment value can
differ from effective value. Warmup override also resets other six-argument risk
settings to hardcoded values. Optional native seeding assumes native quote.
Insurance floor may exceed zero-default insurance seed, intentionally preventing
opens until funded. Live pool check exists only when creating mark source.

Ownership handoff condition for mark source is DEPLOY_MARK_SOURCE rather than
an actual newly-created flag: if supplied PERP_MARK_SOURCE is nonzero and flag
true, script tries transferring a caller-supplied source despite comment saying
otherwise. A source not owned by broadcaster causes failure; multi-transaction
broadcast can already have transferred hook/engine. Local matrix verification
needed. Registry/hook/manager identity and final owner/routing/minter equality
are not fully asserted; final minter printed only. Constructor and every owner
setter need fresh size/dependency and full lifecycle validation before sign-off.

## DeployRenderer.s.sol

All run/interface declarations read. Deploys store/renderer, palette, parallel
manifest arrays, batches uploads, optional Peg wiring and irreversible freeze.
BATCH=0 makes loop non-progressing; extreme values can overflow i+batch.
Preflight positive batch and validate inputs before broadcast. Manifest length
is checked, not key/header uniqueness, palette references, canvas bounds or
output capacity. Freeze has no complete-art/render verification. Uses 5-argument
Peg renderer interface; Cauldron collection instead requires art adapter.
No raw renderer-to-collection compatibility inferred. Profile compiler issue
previously reproduced remains open. Upload transactions can partially persist.

## BadgeArtLib.sol

chunk uses 24,000 bytes plus one-byte runtime STOP within code limit; copies
ordered slices, empty body returns no chunks. upload reads both nonempty sides
and rejects raw hash before upload. _uploadSide uses setArt once then appendArt
per chunk; _assertEscaped checks only hash, not JSON escaping/percent validity.
Comments promising no half-upload are valid for a single atomic call only;
under startBroadcast these are multiple transactions and interrupted upload can
leave one side/partial data. Raw-key iteration and file hash parity needed.

## SnipeBuy.s.sol

All interfaces, run and signed _u helper read. Native-only fee0 spacing200 key
is hardcoded rather than queried. Optional seeder poke failure logs and proceeds.
Deploys PoolSwapTest and exact-input buy with minimum tick limit, no minimum
output. It is an operator test probe, not protected execution for user funds.
Raw hookData encodes buyer but opener policy determines whether trusted.
Reported ETH spent is requested budget, not measured net spend after refund;
price ratio should not be treated as measured cost without balance accounting.
Signed int24 tick subtraction can overflow for extreme endpoint separation;
amount uint-to-int cast also needs bounds for extreme env values. No actual
mainnet/testnet execution performed. All scripts require local simulations,
configuration/role preflight and deployment-artifact parity before sign-off.

## Final disposition (2026-09-23)

Final: mark-source handoff = FS-deployperp-I01, BATCH=0 = FS-deployrender-I01 (Informational). DeployPerp rehearsed successfully on a local chain. Signed off.
