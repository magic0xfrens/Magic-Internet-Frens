# Vendored first-party hook base/miner — source traversal complete

## vendor/HookMiner.sol

Read both functions and constants. find masks requested permissions to the lower
14 hook bits, hashes creation code plus constructor arguments, tests salts from
0 through 160443, and returns only matching addresses with zero code length.
computeAddress follows the CREATE2 preimage (0xff/deployer/32-byte salt/initcode
hash), narrowing the digest to 160 bits. Pure deterministic address math, except
find's candidate code existence checks. No custody, role or storage mutation.
Bounded loop can exhaust before finding a match; no guarantee every initcode
finds a salt in this interval. code.length alone does not test account nonce
collision. Deployer proxy identity, actual linked initcode, constructor args and
permissions must match the eventual deployment. Existing funded local hook
fixtures exercise CREATE2 mining/deployment, but independent address-vector,
collision and exact production deployment rehearsal remain gaps. No edit.

## vendor/BaseHook.sol

Read constructor, abstract getHookPermissions, validateHookAddress, all ten
external wrappers and their ten internal default implementations. Constructor
fixes manager through inherited ImmutableState and validates address permission
bits using the overriding implementation's getHookPermissions. All wrappers
(before/after initialize, add/remove liquidity, swap, donate) use onlyPoolManager,
forward sender/key/parameters/deltas/hookData without rewriting, and return the
internal implementation's tuple. Defaults revert HookNotImplemented. Actual
permission bits and override/return-delta consistency must be checked on
CauldronHook; test subclasses overriding validation cannot establish deployment
address safety. ABI routing, manager authority and malicious direct callers need
source-matched regression evidence. Imported ImmutableState enforces immutable
manager equality; this is dependency-interaction review, not a dependency audit.

No final sign-off: production hook semantic coverage, exact deployed flags,
source/dependency hashes and deployment rehearsal remain open.
