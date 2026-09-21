# NFT-01 — explicit legacy ETH-floor mode

## Reproduction and correction

Production `CauldronVault.redeem` previously inferred unified mode only when its
ETH balance was zero. In a two-NFT fixture, an outsider's 2-wei donation enabled
a holder to burn one NFT for 1 wei despite `hook.vault() == 0`. Forced ETH behaved
the same way. `burnFromVault` burns without notifying `CollectionLedger`.
The holder must submit redemption; a donor cannot burn another wallet's NFT.

Pre-patch command:
`FOUNDRY_PROFILE=cauldron forge test --offline --threads 1 --match-contract UnifiedVaultDonationTest -vv`

Result: **2 failures / 1 passing explicit legacy control**. The fixture uses real
collection/vault/ledger but supplies hook/registry roles. Its ledger credits are
accounting-only, not a funded reserve-drain reproduction.

The minimal guard now requires the immutable collection's current minter to
affirmatively report this exact vault. `floorPerNFT` returns zero when inactive
or closed. Ownership, tranche, closed, CEI/reentrancy and sweep controls remain.
No storage field or constructor parameter was added.

A first typed try/catch variant failed the unsupported-return regression because
return-data decoding occurs in the caller. The final implementation checks raw
success, exactly one ABI word and its full numeric equality to this vault. EOA,
revert, empty and malformed address responses all fail closed.

Post-patch: **8/8 new cases + 6/6 legacy controls pass**, recorded in
`LOCAL_LIFECYCLE_RESULTS.md`. Legacy fixtures explicitly mock `hook.vault()` to
their tested vault; payout, sweep, ownership and donation-accounting assertions
were not weakened. Vault runtime: 2,402 bytes; factory: 20,427 bytes.

## Production reachability and compatibility

Source-reviewed: `CauldronFactory.deployBrew` sets collection minter to the hook
and wires its vault; `CauldronRegistry._deployCollection` then explicitly calls
`hook.setVault(0)`. `_continueMiFrens` wires the same getter through the canonical
genesis collection and also selects zero. The hook's `vault` getter is public
and its setter registry-only. Both shipped unified paths are disabled by the
guard irrespective of ETH balance.

Explicit legacy mode remains available only if a supported hook deliberately
routes to this exact vault. Unknown third-party minters without the getter are
no longer treated as active legacy mode; this is intentional fail-closed behavior.

## Limits

- Does not repair an existing deployed vault or historically burned NFTs.
- Does not assert that every burned share strands entitlement forever: death
  crystallization uses vault outstanding supply and can change the denominator.
  An all-burned generation with existing credited entitlement needs separate
  historical recovery analysis; no arbitrary third-party theft is claimed.
- Actual fresh and genesis-continuation wiring was checked in source, not fully
  rehearsed with this new guard in a deployed-state fork.
- External NFT transfer validators and hostile refund recipients are not fully
  covered by these focused tests.
- This remains a local Medium remediation awaiting final lifecycle acceptance.
