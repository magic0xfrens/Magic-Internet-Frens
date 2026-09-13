# Ca — Coherence pass, sections A (genesis & NFT) + B (iteration lifecycle)

Agent: coherence (a). Real repo, working tree at `redteam/2026-09-11`.
Read: `audit/spec/sections/{A_genesis_nft,B_iteration_lifecycle}.md`;
`docs/protocol/{02-LIFECYCLE,03-GENESIS-AND-SEEDING,08-NFT-ECONOMY}.md`;
`src/components/docs/magicfrens-llm.md`; §1 of `hunt/{H1,H4,H5}`; LEDGER DONE rows.
Contract/frontend/indexer facts below were each grepped or ranged-read in the tree.

Tags: **V** = I read the exact line quoted. **D** = derived by comparing two artefacts I read
(no bytecode run — I did not spend budget on `forge inspect`; ABI checks are source-signature
comparisons, not bytecode diffs).

---

## Mismatch table

| id | sev | spec/docs claim (quote, with file) | code reality (file:line) | frontend | indexer | can it lose a user's funds? |
|---|---|---|---|---|---|---|
| **B-01** | **Medium** | "every SHIPPED deployment turns progressive on … your launch is progressive and there is **no green candle**; the anti-snipe comes from the thin streamed book" (`src/components/docs/magicfrens-llm.md:262-266`); "**Strategy B — progressive streaming (opt-in)** … `SEED_BASE_WAD` \| `0.15e18` — two-sided full-range base" (`docs/protocol/03-GENESIS-AND-SEEDING.md:241,268`) | `uint256 internal constant SEED_BASE_WAD = 1e18;` (`contracts/solidity/cauldron/PoolOps.sol:168`) makes `baseTok`/`baseEth` the WHOLE of ledger A (`:395-396`), so `if (activeTokens <= baseTok \|\| ethAmount <= baseEth) return r;` (`:405`) always fires and `startSeed` at `:410` never runs. Every launch is the atomic green candle; there is no stream and no streamed anti-snipe. The deploy script still arms the dead path: `SEED_WINDOW` defaults to 900 and `setSeeder`+`setSeedWindow` are both called (`contracts/solidity/deploy/DeployLaunchpad.s.sol:368-373`) — V | Nothing in `src/` reads seeder state for the launch UI; no exposure either way — V | `ponder.on("Seeder:SeedStarted", …)` exists (`indexer/src/index.ts:633`) and can never fire — V | **No.** Per the brief this constant is deliberate (`40b9608`, full-range base, seeder dormant), and prime ETH is recoverable since `refundPrime` (LEDGER `fixSEED K5b`, `ca2b76e`). The loss is expectation, not principal |
| **A-01** | **Medium** | "A holder who computes an unfavourable tier can simply not reveal, wait out the 256-block window, and **re-anchor to a fresh seed**" (`docs/protocol/08-NFT-ECONOMY.md:116-117`); spec A3: "if `bh == 0` … re-anchors `mintBlockOf[tokenId] = block.number` … leaving the token still unrevealed for a later call" (`audit/spec/sections/A_genesis_nft.md:80`) | The re-anchor is **one-shot** and the second expiry silently commits the base tier: `if (!reanchored[tokenId]) { reanchored[tokenId] = true; … return; } rarityOf[tokenId] = 0; revealed[tokenId] = true;` (`contracts/solidity/cauldron/CauldronCollection.sol:300-312`, same shape `cauldron/MiFrensGenesis.sol:560-563`, flag declared `:518`/`:253`) — V | `reveal`/`revealBatch` are wired (`src/config/cauldron.ts:348,351`; `src/hooks/useCauldronSwap.ts:318,341`) but **no component warns about the ~256-block seed window or the one-shot re-anchor** — grep for `256\|expire\|reanchor` across `ForgedCreatures.tsx`/`CreatureModal.tsx` returns only rarity strings — V | No `ReAnchored` handler anywhere in `indexer/src/index.ts` (the reveal handlers are `:153,:167,:180`), so a re-anchored token is indistinguishable from a never-opened one — V | **No** (no principal moves), but an inattentive holder is silently downgraded to Common with no UI or indexer signal. The docs also now overstate the grind (safe direction) |
| **A-02** | **Medium** | Tier table "0=Common, 1=Rare, 2=Epic, 3=Ultra" (`docs/protocol/08-NFT-ECONOMY.md:83`, spec A3 `:80`) | `// Rarity tiers: 0=Common, 1=Rare, 2=Epic, 3=Ultra.` / `uint16[4] public rarityCumBps = [uint16(7900), 9400, 9900, 10000];` (`contracts/solidity/cauldron/CauldronCollection.sol:99-101`) — V | **Wrong and self-inconsistent.** `const RARITY = ["Common", "Uncommon", "Rare", "Epic", "Legendary"];` (`src/components/wizards/ForgedCreatures.tsx:33`, rendered `:278`) mislabels every non-Common tier by one slot (an Ultra renders "Epic"); `src/components/wizards/CreatureModal.tsx:10` uses a *different*, correct-for-0..3 table `["Common","Rare","Epic","Ultra","Legendary"]` (rendered `:147`). The same NFT gets two different rarity names in two places in the same app — V | `rarity` is carried on `Minted`/`VolumeMinted`/`Revealed` (`indexer/abis/CollectionAbi.ts:8-21`) and is correct on the wire — V | **No** in-protocol, but it misprices secondary sales: a user reading the gallery sells a top-tier creature believing it is one tier lower |
| **B-05** | Low | "Death floor" rendered as `Ξ`: `<Tele label="Death floor" value={…Ξ} />` (`src/components/cauldron/TheCauldron.tsx:993`, also `:855`) and the doc "24h volume … below `deathThreshold`" (`magicfrens-llm.md:210-213`) | The hook's threshold is **USD-1e18 once an oracle is wired**, not ether — `CauldronHook.sol:1795` ("PRICED IN USD at 1e18. `deathThreshold` was migrated with it") — V | Reads the indexer's `deathThresholdEth` (`src/hooks/useCauldronMachine.ts:241,251`) — V | `deathThreshold` read on-chain and unit-cast to ether: `deathThresholdEth: Number(formatEther(deathThr))` (`indexer/src/api/index.ts:373,381`); the 24h figure it is compared against is summed from indexer swap rows (`:966`), a different accumulator from the hook's buckets — V | **No** — display only; the binding `dead` flag comes from the live `hook.isDead` call (`indexer/src/api/index.ts:980-983`), not from this number |
| **A-05** | Low | "`cancelPresale()` + `refund()` — if the sale never sells out, the deployer can cancel and everyone takes their ETH back" (`magicfrens-llm.md:184-186`); `docs/protocol/03-GENESIS-AND-SEEDING.md:41-49` | Both exist and are correct: `cancelPresale()` `contracts/solidity/cauldron/MiFrensGenesis.sol:289`, `refund()` `:300` — V | **ABI-only, no UI.** `refund`/`cancelled`/`paid` are declared (`src/config/presale.ts:53-56`) and `AlreadyCancelled` has an error string (`src/hooks/useMiFrensPresale.ts:49`), but no component calls `refund` — a repo-wide grep of `src/components` finds only unrelated `cancelled` locals — V | No presale-refund path; presale state is served from `Presale:Transfer` (`indexer/src/index.ts:147`) — V | **No** — funds are recoverable by calling `refund()` directly; the app just never offers it |
| **B-02** | Low | "**`hasClaimed()` always returns false.** … has exactly one reader, `CauldronRegistry.hasClaimed` (`:1774-1776`)" (`docs/protocol/02-LIFECYCLE.md:290-295`); spec B5 lists `claimed[gen][holder]` as live storage (`B_iteration_lifecycle.md:141`) | The accessor is **gone**: `// \`hasClaimed(uint256,address)\` REMOVED. It read {CauldronBase.claimed},` (`contracts/solidity/CauldronRegistry.sol:1822`, matching note `cauldron/CauldronBase.sol:222`). Repo-wide grep for `hasClaimed\|claimed[` in non-test Solidity returns only those two comments — V | No caller (grep clean across `src/`) — V | No caller (grep clean across `indexer/`) — V | **No** |
| **B-03** | Low | Both lifecycle docs footer: "Every `file:line` above was mechanically re-mapped and then spot-verified against the tree at this commit" (`02-LIFECYCLE.md:317-321`, `03-GENESIS-AND-SEEDING.md:427`) | Line cites are shifted by ~35-50 lines throughout: docs say `summon()` `:686`, actual `CauldronRegistry.sol:722`; docs say `relaunch()` `:785`, actual `:821`; docs say `claimByBurn` `:1243`, actual `:1291`; docs say `igniteCauldron` `MiFrensGenesis.sol:575`, actual `:609` — V | n/a | n/a | **No** |
| **A-03** | Low | "Liquidatoor badges … **uncapped**" (`docs/protocol/08-NFT-ECONOMY.md:35,530`) — stated, and true | `tokenId = LIQUIDATOR_ID_BASE + (++liquidatorMinted)` with no supply check (`cauldron/CauldronCollection.sol:351`) — V. What **no** doc states is spec-A delta D3: `MiFrensGenesis` badges are `ERC721Votes` and carry a governance vote, `CauldronCollection` badges carry none (`A_genesis_nft.md:160`) — D (spec-sourced, not re-read this pass) | `LiquidatoorMinted` is consumed (`src/hooks/useLiveSwaps.ts:81` "badge") — V | `LiquidatoorMinted` handled at `indexer/src/index.ts:157,184,187` — V | **No** — but an uncapped, vote-bearing badge on the genesis collection is a governance-weight faucet keyed to liquidation count |
| **B-04** | Info | `docs/protocol/02-LIFECYCLE.md:160-162`: "`getVolume24h` returns 0 outright if the pool has not been touched for more than a day" | Still true, and today's K1a fix landed in the real tree — `_recordVolume` now steps on the **absolute** hour index, `uint256 steps = block.timestamp / SECONDS_PER_HOUR - lastTs / SECONDS_PER_HOUR;` with the audit note naming K1a (`contracts/solidity/CauldronHook.sol`, `_recordVolume` body) — V. Undocumented behaviour change: the reported window used to be able to reach ~46h and now cannot exceed 24h (LEDGER `fixHOOK K1a`, `146a08f`) | No change (no ABI change) | No change | **No** |
| **A-04** | Info | Today's ABI churn, checked for drift in this scope | `playChurn(uint256 quoteIn, uint256 loops, uint256 minTokenOut, uint256 openMax)` (`cauldron/CauldronGachaRouter.sol:379`) matches the 4-input frontend ABI (`src/config/cauldron.ts:437-445`) and the call site (`src/hooks/useCauldronSwap.ts:308`) — D. `new RoyaltyRouter(c.hook, c.royaltyReceiver)` has exactly one caller (`cauldron/CauldronFactory.sol:87`) and **no** `src/` or `indexer/` consumer — V. `refundPrime` has no frontend/indexer consumer, as the LEDGER predicted — V. Manifest schema is `cauldron_r44c` with `chainId: 11155111` (`indexer/deployments/round.json`) — V | consistent | consistent | **No** |
| **A-06** | Info | Presale display sizing | `remaining = p.maxSupply - p.minted` (`src/components/presale/PresaleModal.tsx:102`) with `maxSupply: round.genesisSupply ?? 1111` (`src/config/presale.ts:31`) — this is the **genesis tranche**, matching the contract's `remaining()`/`soldOut()`, which key on `GENESIS_SUPPLY`, not `MAX_SUPPLY` (`cauldron/MiFrensGenesis.sol:638-645`). Correct; the obvious `MAX_SUPPLY` trap was avoided — V | correct | `Presale:Transfer` (`indexer/src/index.ts:147`) | **No** |

**Counts: 0 Critical, 0 High, 3 Medium (B-01, A-01, A-02), 4 Low (B-05, A-05, B-02, B-03, + A-03), 3 Info.**

### Question 5 — the incentive that breaks first, per section

- **A (genesis/NFT).** The reveal grind, and it breaks in the *holder's* favour until it doesn't:
  the one-shot cap (`CauldronCollection.sol:300-312`) makes the ceiling best-of-two, which is a
  sound trade, but the cost of declining is silently paid by the least attentive holder, and the
  app gives them no clock (A-01). Second: badge minting is uncapped and, on the genesis
  collection, vote-bearing (A-03) — the marginal liquidator buys governance weight at the price of
  a liquidation, which is a cheaper vote than a mint.
- **B (lifecycle).** Nothing in section B breaks on incentives as built. `relaunch()` is genuinely
  permissionless (`CauldronRegistry.sol:821`, gate `if (!hook.isDead(oldPoolId)) revert TokenStillAlive();`
  `:833`) and today's K1a fix removed the one mechanism that let a dust trader suspend it. The
  weakest joint is B-01: the launch's advertised anti-snipe is the streamed book, and there is no
  streamed book, so the first block of every generation is defended only by the hook's snipe
  surtax.

---

## Verdict (≤200 words)

Yes — A and B describe a protocol that is structured sensibly as built, and the structural
promises hold where it matters. Generation 1 is honestly documented as ETH-only and the code
hard-passes `address(0)`; the 1:1 migration right is backed by a pre-sized reserve position rather
than a mint; `relaunch()` is permissionless in code, not just in prose, and the K1a volume-window
fix landed in the tree I read. The presale's money path has no owner withdraw, and the UI sizes
the tranche off `genesisSupply`, avoiding the obvious `MAX_SUPPLY` trap.

The incoherences are documentation and presentation, not custody. One is substantive: the public
and operator docs both promise a streamed progressive launch that `SEED_BASE_WAD = 1e18` makes
unreachable, while the deploy script still arms it — the docs describe a machine with an
anti-snipe ladder that ships without one. The rest is drift: a rarity table the gallery renders
one tier low, a removed `hasClaimed` still documented as a limitation, a re-anchor cap the docs
predate, and file:line cites shifted 35-50 lines despite a footer claiming a remap. No path found
in this scope lets a user sign a losing transaction.
