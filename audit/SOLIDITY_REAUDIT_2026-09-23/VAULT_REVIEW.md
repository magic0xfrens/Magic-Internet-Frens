# CauldronVault source traversal

Checkpoint 2026-09-23. Current and frozen source SHA256 both:
`15bfc39e368baac8ada44966159463081c8ba3755d48fedb2ca4db9599f3a5bd`.
No production change in this review. Full source read, not final sign-off.

Subsequent badge-floor remediation supersedes the unchanged-source statement
above: candidate SHA256 is
`b374dd5c5a645d9fc0cc61b96b6dcc37fed927e9d56b7d7976cf00f9105e0081`.
`redeem` now rejects token IDs above totalMinted, preserving the art-only
denominator. FS-badge-floor-01 has a funded registry reproduction; the analogous
legacy vault branch has a prepared dedicated test, R23_BadgeLegacyVault, requiring
badge rejection with unchanged balances/ownership and subsequent successful
redemption of both legitimate art NFTs. That new test has not yet executed.
It uses an explicitly enabled legacy-mode fixture, not shipped unified-mode wiring.

| Body | Reviewed behavior and remaining obligations |
|---|---|
| constructor | Immutable collection, registry and offset; trusts deployment wiring, no zero/code validation. Deployment paths require separate review. |
| outstanding | Saturates eligible minted minus redeemed at zero. Requires totalMinted to count historical mints and other burn paths not to invalidate denominator. Inspected collection/genesis vault-only burn entry points; full collection lifecycle pending. |
| receive | Open donations; counts only registry or live collection minter. Registry short-circuit avoids minter call. Closed vault still accepts funds. |
| _minter | Low-level staticcall then address ABI decode. Reverts on noncanonical address despite defensive comment; dynamic return allocation unbounded. Actual collection getter returns a Solidity address; no production-reachable malformed return established, therefore not a confirmed vulnerability. |
| floorPerNFT | Closed/unified mode returns zero; integer division leaves remainder for remaining holders. External getters are dependencies. |
| redeem | Closed/offset/owner/mode checks; nonReentrant; increments redeemed before burn then ETH payment. Failed burn/payment rolls back state. Callback cross-contract lifecycle still requires validation. |
| _legacyFloorActive | Requires exact 32-byte hook reply matching this vault. Wrong, unsupported or reverting hook getter fails closed; _minter itself can still revert. |
| close | Registry-only, nonReentrant; closes before transferring all ETH. Reports min(balance, cumulative protocol deposits), not actual transfer. Repeat close permitted; production caller reachability and repeated accounting require lifecycle review. |

## Executed evidence

`logs/vault-floor-review-offline.*`: 11 passes, zero failures/skips, two suites,
no compilation needed. Eight UnifiedVaultDonation cases cover unified/legacy
mode, forced balance and invalid hook getters. Three Z2 cases cover donation
exclusion from reported entitlement, live donation redemption and balance clamp.
These fixtures supply privileged hook/registry roles; they are not complete
production relaunch validation. Forced balance uses vm.deal, not an actual
forced-transfer transaction. Malformed getter test targets hook.vault(), not
collection.minter().

The first attempt (`vault-floor-review`) terminated in Foundry's macOS system
proxy initialization, before test results. Retrying with --offline passed;
that crash is tooling evidence, not a Solidity failure.

## Open lifecycle questions

- Cumulative accountedDeposits is not decremented on redemption or close. A
  later donation can replenish balance up to the historical cap after payouts;
  existing tests do not establish the intended attribution in that sequence.
  Both inspected registry creation paths set hook.setVault(0), disabling legacy
  redemption, which limits reachability. Do not call this a confirmed finding
  without checking actual supported mode transitions and entitlement effects.
- PoolOps.seedFunding catches close failure. Determine whether subsequent
  relaunch accounting remains safe and whether any old-vault custody is stranded.
- Verify floorOffset and collection denominator across continuation generations,
  recycling, burns and crystallization; verify repeat-close production gating.
- Malicious/invalid immutable deployment dependencies and gas-burning getters
  are not proven tolerated. No universal liveness assertion.
