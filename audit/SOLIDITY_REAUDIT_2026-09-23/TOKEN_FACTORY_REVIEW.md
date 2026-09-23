# Token / factory review — in progress

Read complete CauldronToken and CauldronFactory sources. No production changes.

Token constructor sets immutable registry/generation/birthBlock and mints the
supplied initial amount to registry. TOTAL_SUPPLY is a public constant, NOT a
constructor cap: deployed supply depends on registry creation arguments.
onlyRegistry gates burn; registry can burn any holder without allowance at the
token layer. User consent must be proved in each registry caller, not inferred
from ERC20 allowances. No mint entry point or transfer freeze override exists.
Inherited ERC20 behavior/dependency hash and generated getters remain part of
the compiler/consumer join.

Existing test_NoMintFunction only asserts a computed selector is nonzero; it
does not call the token or inspect its ABI. Added R23_TokenAuthority to execute
the missing selector call and verify unchanged supply/balance, plus rejection
of burn by an approved spender while ordinary transferFrom remains functional.
First run failed to compile because the new test referenced a custom error on
an instance rather than its contract type; corrected harness, no production
failure claimed. `token-factory-review-corrected` pending, session 21594.

Factory source traversal:
- owner initialized to deployer; setLiquidatorRenderer and transferOwnership
  gate on that address. Transfer accepts zero and emits no ownership event;
  assess as configuration/observability risk, not automatic fund-loss severity.
- deployBrew is permissionless but creates NEW collection/vault/router using
  caller-supplied configuration; no ability to mutate existing registry pointers
  is established. Factory deployer privilege performs wiring atomically.
- deployVault likewise deploys a new vault, does not wire an existing collection.
- Global badge renderer is applied only at new collection creation; owner change
  does not update already deployed collections. Consumer/deployment semantics
  must reflect this rather than claiming retroactive renderer control.

Pending: inspect constructor/setter external edges in collection/vault/router,
test results and exact assertions, ownership failure paths, runtime sizes, and
real registry mint/burn caller joins. Factory deploy permissionlessness alone
is not a vulnerability.

Batch completed: token-factory-review-corrected exit 0 in 4.72s; 25 passed,
zero failures/skips (four inherited duplicate token tests). Two new executable
authority tests pass. Session 21594 terminal. The old selector-sanity test remains
a weak assertion, not proof of absent mint; the new call test supplies concrete
negative-dispatch evidence. CREATE2 tests are harness-based; inspect their exact
caller/nonce/quote assertions before extending results to deployed factories.
