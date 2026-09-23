# CauldronCollection source traversal

Current and frozen SHA256:
`027606f0538c51ea0e5072f38e1cda1f18cf75a816620543630175e7fc300d8c`.
All first-party implementation bodies read. No production edits or final sign-off.

## Function obligations (DERIVED unless executed evidence is stated)

- Constructor: nonzero minter/controller, art supply below badge range, renderer
  code or nonempty base URI, royalty <=10%. Controller and factory/configurator
  are distinct immutable roles. Factory documentation still sometimes conflates them.
- `_update`, validator getters/setter, supportsInterface: validator applies to
  mint/transfer/burn through a view call. Only controller can configure it.
  Registry source has no matching setter forwarder; impersonating registry in
  a unit test does not demonstrate a production administrative action.
- `mint`: only immutable minter, lifetime art cap, sequential IDs, mint-block
  commit, plain `_mint` (no receiver callback). Failed mint rolls back count.
- `reveal`, `revealBatch`, `_reveal`, `_rollRarity`: owner-only (not approved
  operator); batch length 1..50; one reanchor then base-tier terminal reveal.
  Ownership checked even for already-revealed IDs. Invalid ID/owner reverts the
  entire batch. Seed is blockhash plus token ID and contract address. One optional
  second draw and producer influence remain; no unbiased randomness claim.
- `setVault`: controller/configurator, zero sentinel permits repeated zero
  assignments; production factory wires nonzero vault atomically.
- `setRoyalty`: controller/configurator and <=10%; inherited receiver validation.
- `setLiquidatorMinter`: controller or art minter, replaceable/zero-disableable.
- `setMetadata`: controller; renderer code required, but BaseURI permits empty
  unlike constructor. Registry forwarder and delay require lifecycle review.
- URI setters: controller only. Actual registry reachability still needs closure.
- `mintLiquidator`, `mintLiquidatorWithStats`, `_mintLiquidator`: wired engine
  only, separate IDs above one million, no art-supply consumption. Stats written
  only for nonzero victim. Plain mint; zero recipient or validator failure reverts
  all badge effects. Claim-later zero-stat badges are explicitly owner-accepted.
- `liqStats`, renderer setter, trait helper: stats/trait do not require existence;
  renderer can be codeless/reverting and block metadata reads, not transfers.
- `burnFromVault`: vault-only; no lifetime supply decrement. Review vault's art
  versus badge admission independently before assigning redemption safety.
- `custodyTransfer`: controller-only approval bypass; caller must establish
  redemption ownership/payment. `_transfer` still checks from/recipient.
- `tokenURI`: existence required; badge branch bypasses art reveal; art uses
  unrevealed placeholder, renderer, or base/rarity/id. Header's immutable/no-admin
  assertions and simple base/id format are stale documentation.
- `setRarityOdds`: controller, before first art mint, nondecreasing cumulative
  boundaries ending at 10,000. Badge minting alone does not lock art odds.

## Gaps and next joins

Inherited ERC721 approval/transfer behavior and dirty dependency version must be
reconciled, not inferred from upstream alone. Complete registry setter reachability,
custody/retirement accounting, old-collection pending mint resolution, engine badge
claim lifecycle, and renderer failure recovery. Badge `revealed` mapping defaults
false despite always-renderable metadata; consumers must use badge classification.

Selected tests: CollectionTest, RevealBatchTest, LiquidatoorBadgeTest. These use
synthetic authorized minter/controller addresses and do not prove registry or
engine forwarding. Reveal diversity assertion demonstrates different observed
outputs, not statistical independence. Execution logged as `collection-review`.

VERIFIED: `collection-review` finished successfully (exit 0, 2.14s), with cached
compilation reused: 5 collection, 6 reveal, and 8 badge tests passed, no skips.
This supports the selected local assertions, not the outstanding lifecycle joins.
