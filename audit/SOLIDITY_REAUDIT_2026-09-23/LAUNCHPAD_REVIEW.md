# DeployLaunchpad — full source traversal, final verification pending

All 1,026 pre-edit source lines read, including five implementation bodies,
IOwnable, constants, role/environment declarations and narrative. Candidate now
adds separate band helper. No broadcast or production state interaction.

- run calls quote preflight before credentials; guard applies only DEPLOY_QUOTES,
  which is Sepolia-only. External QUOTE_ORACLE path lacks same feed preflight.
  Other settings are validated much later: timelock/emergency window, supply/cap,
  curve arithmetic, block-time divisor, optional ownership paths. Multi-tx
  broadcast interruption is not atomic rollback of all previously mined txs.
- Signer default msg.sender vs actual broadcast signer needs simulation. Timelock
  grants proposer/executor/admin to deployer; role handoff to Safe is manual.
  Three-minute default minDelay is not a production governance recommendation.
- Genesis receives immutable deployer authority and caller-supplied constructor
  cap (no binding cap assertion here). Hook mined with correct beforeSwap delta
  and afterSwap flags; explicit owner avoids CREATE2 factory owner. Registry
  emergency delay must be positive, but emergencyAdmin can be overridden.
- Facet one-time wiring precedes ownership transfer. Factory, dividend, gacha,
  ledger and optional badge renderer created, badge upload may span transactions.
  Hook knows registry/dividend/openers, registry/seeder exemptions need both flags.
  Royalty/dividend/ledger/factory/governor joins inspected; setters still require
  actual broadcaster identities. In particular dividend treasury differs from
  broadcaster when TREASURY env overridden; owner-role compatibility needs test.
- USD oracle flows into hook, gacha and rotator; treasuryGov oracle is only
  printed for later timelock call (timelock always exists). Therefore one-shot
  run does not establish complete quote-admission oracle wiring. USD ladder
  calibrated to artCap, curve baseBps/knee/target inputs can divide by zero or
  underflow. Arithmetic failures need early configuration validation.
- Seeder window narrows uint256->uint64; BLOCK_TIME zero can divide by zero.
  Configured seed campaign still depends on PoolOps base fraction. Funding
  optional prime budget may need refund if streaming inactive. Legacy buyback,
  metadata/art adapter, badge renderer, airdrop and prime funder wiring inspected.
- Treasury timing narrows to uint64; TESTNET_GOV not itself chain-gated. Rotator
  configured with explicit no-oracle opt-in fallback. Registry igniter is presale;
  registry owner becomes timelock. Hook owner remains deployer until DeployPerp.
  Factory, badge renderer, governor, gacha, oracle/rotator owner roles are not
  universally transferred here. Header's presale-owner claim is obsolete.
- _preflightQuoteStack checks mock chain and unpegged feeds. _requireUsableFeed
  checks code, success/length, positive/fresh timestamp, decimals conversion and
  bounds; ABI malformed words may decode-revert (still prevents deployment).
  Does not inspect answeredInRound. Bounds raw uint256 vs later uint128 narrowing
  require parity check. Configured QuoteOracle has its own final live-value test.
- _deployQuoteOracle creates native pegged or fed oracle, bounds then nonzero
  read; narrative about non-Sepolia pegged chains does not override mock chain
  preflight. _deployRotationStack retries mock address below watermark32 times,
  configures pegged/fed USDG, rotator floor and optional narrowed slipBps,
  allowlists quote, derives venue units from same oracle. No assumption of
  market peg/production collateral validity for mock assets.
- Venue originally seeded full-range then band into SAME helper. That confirms
  repeated-seed loss is reachable via shipped optional deployment flow. The new
  single-position admission guard alone would break it. Candidate now mints each
  tranche directly into a separate helper, logs both recoverable holder addresses,
  preserves full-range opening liquidity plus optional band. Total intended
  mock mint/native budget unchanged. RecoverVenue can recover each separately.
  Runtime compatibility test running; no complete script success asserted.
- NativeQuoteZap created after venue curation. It converts only; gacha remains
  user's direct call. Actual configuration export/source/artifact parity pending.

Remaining: full no-broadcast local script execution, configuration matrix,
complete role handoff/readbacks, band-width lead, target-chain/dependency/size
checks and immutable uploaded-art verification. Source traversal not sign-off.

Compatibility update: two-helper actual V4 lifecycle passes in mixed batch.
Shared env-mutating preflight tests fail under concurrency; all12 pass serially.
No deployment end-to-end success inferred. See retained logs for both runs.

## Final disposition (2026-09-23)

Final: DeployLaunchpad rehearsed successfully on a local chain with full lifecycle (rehearsal/README.md). Signed off with target-chain limitation.
