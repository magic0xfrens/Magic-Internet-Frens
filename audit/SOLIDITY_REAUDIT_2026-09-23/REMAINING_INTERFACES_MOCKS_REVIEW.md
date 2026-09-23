# Remaining interfaces and testnet mocks — full source traversal

All declarations/bodies reviewed; no production edits or final sign-off.

- ISeeder: shared SeederConfig includes full PoolKey, generation, signed tick
  geometry, uint64 window, WAD fractions and asset totals. Six entrypoints:
  startSeed payable, poke, withdrawAll return pair, rescue, isComplete, seeding.
  Interface alone imposes no caller/geometry/asset constraints; implementation
  and delegatecalled PoolOps handoff must enforce them. Existing seeder worksheet
  covers implementation; complete compiled call/return tuple parity pending.
- ICreatorToken: validator external view validates caller/from/to/id; discovery
  getter plus validation selector/bool and setter/event. Interface does not
  enforce royalties independently; collection validator policy/access and
  marketplace integration determine that claim. No external compatibility
  assertion inferred from interface naming.
- INFTContract: getHolderTaxRate in BPS and balanceOf. Numeric range/tier comment
  is not enforced at boundary. Hook tax clipping, replacement authority and
  reverting/malformed NFT dependency handling remain caller obligations.
- MockAggregator: constructor accepts any signed price, sets owner and round1;
  peg owner-only increments uint80 checked round and emits. Owner-only stale/down
  toggles; ownership may transfer to zero. latestRoundData returns matching round
  IDs, dynamic timestamp or1, and reverts when down. Stale1 is not necessarily
  old in early-chain/test time. No market discovery or true freshness is implied;
  mainnet safety is not enforced by code despite narrative. Oracle must reject
  nonpositive answer and handle failure/staleness; existing oracle tests apply.
- MockQuoteToken: ERC20 constructor plus immutable configurable uint8 decimals,
  unrestricted mint through OZ _mint. Intentional faucet authority, no mainnet
  guard/cap. Full ERC20 and decimals extremes require consumer boundary checks;
  do not treat mintable mock collateral as a production solvency assumption.

Final gates include ABI selectors/tuple checks at callers, production deployment
exclusion of mocks, actual tax/royalty/seed integration and source-hash parity.
