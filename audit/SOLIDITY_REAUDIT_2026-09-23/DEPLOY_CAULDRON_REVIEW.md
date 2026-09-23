# DeployCauldron — full source traversal, final verification pending

Constructor constants and entire run reviewed. Reads signer/config, mines
CREATE2 hook address, broadcasts hook/registry/facet, wires registry and opener/
exemption, then summons. No script execution or broadcast performed.

Original incompatibility: mined flags included afterInitialize,
afterSwap, afterSwapReturnDelta only. Current hook getHookPermissions additionally
requires beforeSwap and beforeSwapReturnDelta. BaseHook construction checks
permission address bits, so current script cannot instantiate the requested
hook at its mined address. Do not treat this legacy script as deploy-ready.
FS-deployhook-01 (Low) now reproduced and patched: script uses internal
_hookFlags including beforeSwap and beforeSwapReturnDelta. The test harness
reads this same helper; actual constructor with old flags reverts with the exact
HookAddressNotValid(predicted) error, and actual constructor with current script
flags succeeds with predicted address, manager and owner. Two tests pass in
logs/deploy-hook-permission-offline.*. The initial non-offline run crashed in
Foundry's macOS system proxy/signature client (exit -6); retained separately.
Manager is a placeholder address for constructor checks: this does NOT prove
manager interactions, canonical factory broadcast routing or full summon.
Gas figures include offchain salt search and harness deployment and must not be
reported as onchain hook deployment gas. No broadcast executed.

Canonical CREATE2 deployer implementation/code and Foundry factory routing
assumed; post-address require checks equality but not dependency provenance.
Owner explicitly broadcaster to avoid factory-owned hook. Registry uses instant
emergency delay and default admin. Redemption facet wired one-time, registry
made opener/exempt before summon. No collection factory/governor/gacha/perp/full
launchpad setup here; intended minimal deployment must be tested independently.
No target chain/dependency preflight or runtime size checks in run. Multi-tx
sequence may partially persist; no atomic full-deploy claim. No final sign-off.
