# Fee routing source traversal

Current and baseline hashes match:
- DefaultFeeRouter.sol: 7a581bce27d3ee5f79942d7e82de9a7ceea9b6c1a38cdf12c61d305eddb0d9eb
- FeeRouteLib.sol: c49839ad353fdb8e5125a077ad1ce9e9a515c3fafc56a80a53faa29ff4b51f44

## Bodies inspected

DefaultFeeRouter.route: pure split, guild cut then floor fraction of remainder,
no vault-address gate. Checked multiplication/subtraction; requires caller's
bps bounds and realistic fee amounts. Router chooses amounts, not recipients,
but a custom router can change economics even if the sum is valid.

FeeRouteLib.routeSplit: guild funding and floor transfer, leftovers aggregate.
routePerp: same guild path plus selector-driven staker delivery. Both are linked
library calls using caller custody, not independently permissioned vaults.
_move: requires recipient code; native low-level call or ERC20 transfer/boolean
decode. Malformed token ABI can revert despite fail-soft documentation.
_fundGuild: code-check, native receive or approve + fundToken; only EVM approval
success checked, not return bool. Clears allowance on failed pull only.
_deliver: analogous selector-based pull; clears allowance on failed pull only.
send: arbitrary recipient permitted; optional gas cap only on native path;
ERC20 malformed bool can revert, codeless asset returns apparent success.
deliver: code-check and native/pull path; attempts unconditional allowance reset,
ignoring its success. Partial pull reported as full success; existing fixture
explicitly demonstrates this behavior while checking only allowance revocation.

Recipient/asset trust and callback joins remain open. Production hook folds
non-native vault share into reserve instead of invoking _move for ERC20 floor.
Thus library-only malformed floor tests would not establish shipped hook impact.
Do not claim all sends fail softly or all allowances are necessarily cleared.

## Executed evidence

logs/fee-routing-review.*: 20 passes across six suites, no failures/skips,
no compile. Covers codeless guild/vault/engine recipients, guild accounting,
no-claimant fallback, and deliver allowance cases. Does not cover every callback,
malformed asset or false-success/partial-pull production configuration.

## FS-feerouter-01 — Medium, confirmed availability; unpatched

CauldronHook fee split path around fr.route: typed try/catch does not catch
return decoding failure; g+f+r checked overflow occurs in the success block and
also escapes fallback. Configured router dependency failure can therefore stop
fee-bearing swaps until owner replaces/unsets it, contrary to intended built-in
fallback. No outsider router selection or theft demonstrated.

R23_FeeRouterFallback.t.sol uses actual local V4 managers, hook, registry and
funded trade. Owner selects fixture router. logs/fee-router-boundaries.*:
ordinary reverting router control passes; empty-return and max-uint-plus-one
split fail the funded swap (empty revert and arithmetic panic respectively).
No storage overwrite, no mock pool or mocked swap. Governor fixture remains.

Next: bounded raw 96-byte response validation with overflow-safe sum check,
preserve fallback and valid custom split semantics. Hook size is tightly bounded;
inspect exact runtime before selecting helper/library placement. No production
edit yet, no new completion claim. Include valid/mismatched/short/trailing cases,
ABI/storage/runtime checks and neighboring swaps in remediation validation.
