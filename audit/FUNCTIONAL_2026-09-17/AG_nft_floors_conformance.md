# Functional conformance — Area A (Genesis/NFT) + Area G (floors, redemption, 2× ratchet)

Date 2026-09-17 · branch `main` @ `9c27596` · no source changed.
Specs audited: `audit/spec/sections/A_genesis_nft.md`, `audit/spec/sections/G_floors_redemption.md`
(both written 2026-09-10 on branch `fix/b05-b07-relaunch-totality`).
Intent docs read: `contracts/solidity/COLLECTION_FLOOR_UNIFY.md`.
All three named commits are ancestors of HEAD (`git merge-base --is-ancestor`): `e0d4c9f`
(gacha seed pinning), `6eaf67c` (mutable `MAX_PER_WALLET`), `60ebd01` (`setUnrevealedURI`).

Every line cite below was opened and read in this checkout. Paths relative to
`contracts/solidity/`.

---

## Headline answers to the four questions

1. **Which creature floor mechanism is LIVE?** The **ledger** (mechanism b).
   Production callers: `CauldronRegistry.recycleCollectionNFT` (`CauldronRegistry.sol:1562`)
   → `PoolOps.recycleCollection` (`PoolOps.sol:1610`) → `CollectionLedger.redeem`
   (`CollectionLedger.sol:161`); and `CauldronRegistry.buyCollectionNFT`
   (`CauldronRegistry.sol:1583`) → `PoolOps.buyCollection` (`PoolOps.sol:1633-1637`) →
   `CollectionLedger.buyback` (`CollectionLedger.sol:174`). `redeem` is **not** death-gated:
   `outstanding()` takes the live `totalMinted` while alive and the frozen snapshot after
   `crystallize` (`CollectionLedger.sol:90-94`). Mechanism (a) `CauldronVault.redeem`
   (`CauldronVault.sol:155`) is `DEPRECATED-PRESENT` — both deploy paths null the hook's
   vault pointer (`CauldronRegistry.sol:1237`, `:1261`) so it holds no ETH and reverts
   `UnifiedFloorActive()` (`CauldronVault.sol:37,163`) — but it is **externally re-armable**
   (finding G-3). Mechanism (c) `redeemCreature`/`buyTreasuryCreature` is `DESIGN-ONLY`:
   zero `.sol` matches repo-wide; named only in `COLLECTION_FLOOR_UNIFY.md:30,33,83-84`
   against branch `feat/unified-collection-floor`, which does not exist.
2. **Does INVARIANT R have an on-chain assert?** **No — on no path.** `grep` for
   `_assertReserveCoversClaims|assertReserveCovers|InvariantR` over `cauldron/*.sol` and
   `*.sol` returns **only** comments (`CollectionLedger.sol:21,133`, `PoolOps.sol:1483`,
   `RedemptionExt.sol:144`, `CauldronHook.sol:345`) and one test comment
   (`test/functional/F11_FloorsAndRedemption.t.sol:98`). R holds by construction +
   payout-time short-revert only (table in G-2). `COLLECTION_FLOOR_UNIFY.md:158-159`
   still describes the unimplemented assert. **`migrationOutstanding` still names no
   on-chain variable**, so the doc's formula remains uncheckable as written.
3. **Is supply conserved across mint / badge / reveal / redeem?** Yes. Badge ids are
   `LIQUIDATOR_ID_BASE + ++liquidatorMinted` = ≥ 1,000,001
   (`MiFrensGenesis.sol:188,194,449`; `CauldronCollection.sol:74,80,411`); both
   constructors reject `maxSupply_ >= LIQUIDATOR_ID_BASE`
   (`MiFrensGenesis.sol:276`, `CauldronCollection.sol:148`), so art ids ≤ 999,999 can
   never collide. Art caps read only `minted`/`totalMinted` (`MiFrensGenesis.sol:546`),
   never `liquidatorMinted` — badges are outside the art cap. Test:
   `test/LiquidatoorBadge.t.sol::test_BadgeIds_AndTraits_AndArtCapUntouched` (PASS).
4. **Gacha odds as displayed vs computed on chain?** Aligned. Chain: `oddsForPlay`
   (`CauldronHook.sol:2364-2375`) consumes a **curve-unit** play; the router converts
   (`CauldronGachaRouter.sol:121,136,328,398`), `openReady` deliberately does not
   (`:357`, already curve units), the in-swap path feeds USD-converted volume
   (`CauldronHook.sol:914,994,1038`). UI now reads `playInCurveUnits` and feeds the
   result to `oddsForPlay` (`src/config/cauldron.ts:485-494`,
   `src/components/cauldron/CrystalCauldronGame.tsx:197-211,229,240`). The committed
   `uint16` cast is safe: `ODDS_HARD_CAP_BPS = 9_500`, `maxOddsBps = 9_000`
   (`CauldronHook.sol:451-452,2369,2479`).

---

## Area A findings

### A-1 — Reveal re-anchor is now capped at one; the spec says it is unbounded
FEATURE: A / `MiFrensGenesis._reveal`, `CauldronCollection._reveal`
INTENT: spec A3 — "if `bh == 0` … re-anchors `mintBlockOf[tokenId] = block.number` …
and returns quietly, leaving the token still unrevealed for a later call" (no cap stated).
ACTUAL: one re-anchor per token, ever (`mapping(uint256 => bool) public reanchored`,
`MiFrensGenesis.sol:588`; branch at `:628-640`), after which the token is **committed to
`rarityOf = 0` (Common) and marked revealed** — not re-rolled. Same shape in
`CauldronCollection.sol:255-310`. Rationale in-file (red-team Z-08): an uncapped
re-anchor was "an unlimited free gacha re-roll … measured at 400 re-rolls to a
deterministic Ultra".
DELTA: the cap and the terminal forfeit do not exist in the spec at all.
CLASS: `SPEC-STALE` (code is right, spec is old).
IMPACT: none adverse; spec readers mis-model the reveal state machine.
REPRO: read `MiFrensGenesis.sol:586-646`.

### A-2 — The seed-pinning fix was applied to the gacha queue only, not to reveal
FEATURE: A / sealed-crystal reveal vs `GachaLib` pinning
INTENT: `e0d4c9f`'s own stated reason (`GachaLib.sol:92-101`): `blockhash` is 256 blocks
= **25.9 s** on the 0.1012 s/block target chain, so "an honest player who pays for a
9,000-bps draw and hits a slow RPC loses the whole stake, with no attacker involved."
ACTUAL: `GachaLib` pins (`SEED_SLOT` `:123`, `PIN_SPAN = 4` `:130`, `_pinSeeds` `:147-157`,
called `:272`, read first at `:192-193`), so any resolve inside the window immunises the
batch forever. The reveal path has **no pin**: `_reveal` re-derives `blockhash(mb)` every
call (`MiFrensGenesis.sol:595`) and is **owner-only** (`:591`,
`if (ownerOf(tokenId) != msg.sender) revert OnlyMinter()`), so no keeper, swap or third
party can pin or reveal on a holder's behalf. Miss ~25.6 s twice and the token is
force-committed to Common (`:628-640`), i.e. the rarity draw is forfeited outright
(worse than a fair roll).
DELTA: identical hazard, identical chain timing, fix applied to one of the two sibling
paths. The gacha comment's own argument ("every swap fires one via `nativeGachaStep`")
is exactly what reveal lacks.
CLASS: `DEVIATES` (intent vs code, sibling-path inconsistency).
IMPACT: a holder on a slow RPC / away from the keyboard for ~52 s loses the rarity they
paid swap volume for and silently receives a Common.
REPRO: `test/attacks/M3B_ExpiredCrystalForfeit.t.sol` covers the *gacha* side (1 test,
PASS, 0 skipped). No equivalent exists for `_reveal`; a PoC would mint via the hook,
`vm.roll(mintBlock + 257)` twice with `reveal()` between, and assert
`rarityOf == 0 && revealed == true` (use `vm.getBlockTimestamp()` per the viaIR gotcha).

### A-3 — Seed pinning itself: specified correctly and grants no extra draw
FEATURE: A / `GachaLib._pinSeeds` + `resolveTickets`
INTENT: "freeze the outcome so the 256-block deadline stops applying … WITHOUT handing
anyone a second draw" (`GachaLib.sol:104-110`).
ACTUAL: the pinned value is `blockhash(b.commitBlock)` and is written **only when
non-zero** (`:151-153`) — a current/future block's hash is zero and skipped, so nothing
is ever pinned to an undetermined seed; resolve prefers the pin and falls back to the
live `blockhash` (`:192-193`). A player therefore cannot improve an outcome by choosing
*when* to resolve: the seed is fixed by the commit block, not by the resolve block.
DELTA: none against intent. Two residuals, both documented and deliberate: (i) the single
re-anchor is still a genuinely fresh draw, so a player who peeks at a losing seed and
declines to resolve gets one extra roll **if nobody pins the batch first** — pinning is
best-effort (only `PIN_SPAN = 4` batches from the cursor per call, `:148-149`), so a
batch sitting >4 deep behind a long head batch during a quiet ~26 s can still age out;
(ii) a twice-expired batch still honours pity (`forced`, `:224`) but cannot win on its
roll, and is explicitly not counted as a miss (`:246-249`).
CLASS: `CONFORMS` (mechanism) / `UNDERSPECIFIED` (the residual one-re-anchor option is
described in code comments only; spec A4 mentions neither pinning nor the cap).
IMPACT: none for honest players; the peek-and-wait option is bounded at one extra draw
and shrinks with pool activity.
REPRO: `test/attacks/M3B_ExpiredCrystalForfeit.t.sol` (PASS).

### A-4 — `MAX_PER_WALLET` mutability behaves as specified
FEATURE: A / `MiFrensGenesis.setMaxPerWallet`
ACTUAL: `MiFrensGenesis.sol:297-303` — deployer-only; `newCap == 0 || newCap >=
GENESIS_SUPPLY` refused (non-binding cap cannot be re-entered); `minted != 0 && newCap >
MAX_PER_WALLET` refused (ratchet-down only). Storage is now a mutable
`uint256 public MAX_PER_WALLET` (`:126`), set from the constructor (`:280`). The cap is
tested against `balanceOf` (`:338`), which **does** count badges (badge ids are ordinary
ERC-721 balances).
CLASS: `CONFORMS`. The badge/`balanceOf` interaction is real but unreachable in practice:
the only cap check lives in the presale `mint(uint256)`, and `liquidatorMinter` is wired
to a `PerpEngine` that does not exist until after the presale is finalized
(`CauldronHook._wireLiquidator` runs on `setCollection`/`setPerpEngine`).
IMPACT: a wrong constructor argument is correctable pre-mint without a redeploy; buyers
cannot have the cap widened under them.
REPRO: `test/attacks/B2_PerWalletCap.t.sol` (5 PASS, 0 skipped),
`test/attacks/L1_LaunchStops.t.sol` (6 PASS, 0 skipped).

### A-5 — `setUnrevealedURI` present and gated
`MiFrensGenesis.sol:313-316` and `CauldronCollection.sol:388-391`, both
`msg.sender != deployer → NotAuthorized`. `tokenURI` returns `unrevealedURI` only for
`tokenId > GENESIS_SUPPLY && !revealed` (`MiFrensGenesis.sol:756`). CLASS: `CONFORMS`
(spec A predates it entirely → `SPEC-STALE`).

### A-6 — Badge voting weight: suppressed at the source; quorum denominator agrees
FEATURE: A / governance weight of badges and forged frens
INTENT: spec A open-delta **D3** asserts `MiFrensGenesis` badges carry "ONE governance
vote, exactly like a volume-minted MiFren".
ACTUAL: false today. `_update` routes **only** genesis ids through `ERC721Votes._update`
(`bool votable = tokenId != 0 && tokenId <= GENESIS_SUPPLY`, `MiFrensGenesis.sol:803`);
non-genesis ids go straight to `ERC721._update` (`:816`), so no voting unit is ever
created for a badge or a forged fren. `_getVotingUnits` is overridden to
`genesisBalanceOf[account]` (`:734-736`), closing the `delegate()` re-admission hole.
Because the unit never enters `_totalCheckpoints`, the **quorum denominator matches the
numerator by construction**: `TreasuryGovernor._passed` uses
`mifrens.getPastTotalSupply(p.snapshot) * QUORUM_BPS / 10_000` with
`QUORUM_BPS = 1000` (10%) (`TreasuryGovernor.sol:328,996`) — i.e. quorum is measured
against the **checkpointed genesis voting-unit total at the proposal snapshot**, not
`totalSupply()` and not badge-inclusive `balanceOf`. Unbounded badge minting therefore
cannot push quorum out of reach.
DELTA: spec statement D3 is now wrong for `MiFrensGenesis`; it remains right for
`CauldronCollection` (plain ERC-721, no Votes).
CLASS: `SPEC-STALE`.
REPRO: `test/attacks/V2B_GenesisOnlyQuorum.t.sol` — 4 PASS, 0 skipped, including
`test_V2B_quorumStaysReachableAfterMassBadgeMinting`.

---

## Area G findings

### G-1 — Live-mechanism verdict (see Headline #1) — spec G2 re-confirmed, lines drifted
`redeemOgFren` `RedemptionExt.sol:78`, `buyTreasuryOgFren` `:115`, `donateToReserve`
`:136`, `materializeLegacyReserve` `:144`; registry stubs `CauldronRegistry.sol:1437,
1443,1449,1455`; `floorPerFren` `cauldron/CauldronBase.sol:423-427`; `_redeemBlocked`
`:433-435` (still checked in `redeemOgFren` and `recycleCollectionNFT` only, **not** in
either buy leg). CLASS: `CONFORMS` / `SPEC-STALE` on every line number in spec G.

### G-2 — INVARIANT R: no assert anywhere; construction-only, and now one step stronger
FEATURE: G3 / reserve solvency
INTENT: `COLLECTION_FLOOR_UNIFY.md:44-52,158-159` — "enforced on **every** credit and
redeem … Add an on-chain assert … This assert is the safety core."
ACTUAL (per-path, all read):

| Path | Term | Direction | On-chain check |
|---|---|---|---|
| `redeemOgFren` (`RedemptionExt.sol:91`) | `genesisReserveOutstanding` | −F (saturating) | none pre-pull; paired `claimFromReserve` + `if (amount + 1e12 < F) revert NoBalance` (`:104`) rolls back |
| `_pullGrow` (`RedemptionExt.sol:165-183`) | `genesisReserveOutstanding` | += **actual** `addToReserve` result; `added == 0 → NoBalance` | deposit-first, cannot over-claim |
| `CollectionLedger.credit` (`:146-155`) | `entitledTokens`, `totalEntitled` | += | **none.** New since the spec: `isDeadEnd(gen)` credits are dropped with `CreditRejected` instead of booked (`:120-123,148-151`) |
| `CollectionLedger.redeem` (`:161-169`) | both | −payout (round **down**) | none in ledger; caller reverts `"reserve short"` (`PoolOps.sol:1615`) |
| `CollectionLedger.buyback` (`:174-181`) | both | += **deposited** `added` | caller deposits before crediting (`PoolOps.sol:1636-1637`) |
| `CollectionLedger.crystallize` (`:187-200`) | both | += `extraEntitled` | none; dropped if already fully retired (`:195-199`) |
| `PoolOps.claimFromReserve` (`:1421`) | reserve LP | − actual | returns short, reverts nothing; callers revert |

DELTA: the assert named in the doc does not exist (Headline #2); `migrationOutstanding`
still names nothing. One genuine improvement since the spec: `materializeLegacyReserve`
now deposits **and** credits in one step, documented as "a legacy credit can never
out-run the reserve backing it (Invariant R holds by construction, not by the reserve's
slack)" (`RedemptionExt.sol:144-149`; `PoolOps.sol:1475-1477,1483`).
CLASS: `MISSING` (the assert) — headline regardless of exploitability, exactly as the
doc says.
IMPACT: a single future caller of `credit` that does not deposit first breaks R with
nothing on chain to catch it; the failure surfaces as the **last** redeemers'
`"reserve short"`/`NoBalance` revert, i.e. the people least able to react.
REPRO: `test/functional/F11_FloorsAndRedemption.t.sol::test_F11_InvariantRIsEnforcedAtPayoutNotAtCredit`
(2 PASS, 0 skipped) — credits `type(uint128).max` with no reserve, no revert.
`test/invariants/LedgerInvariants.t.sol` (3 PASS) fuzzes only `totalEntitled == Σ`,
never a real reserve LP balance. No test in the tree exercises the cross-contract
inequality.

### G-3 — The "deprecated" ETH vault is externally re-armable, and its redeem desyncs the ledger
FEATURE: G2(a) / `CauldronVault.redeem` vs `CollectionLedger`
INTENT: spec G2 §1 — "No ETH leaks in anywhere else: `receive()` … is still open to
anyone … but no protocol code path does this"; `CauldronVault.sol:146-154` documents the
function as one that "cannot succeed".
ACTUAL: "cannot succeed" is conditional on the balance, not structural.
`receive()` is open to **anyone** (`CauldronVault.sol:117-121`; only registry/minter
sends increment `accountedDeposits`). `redeem` reverts `UnifiedFloorActive` only when
`address(this).balance == 0` (`:163-166`); any donor sending ≥ `outstanding()` wei to a
**live** (`!closed`) brew's vault makes `amount > 0` and the function executes. It then
`burnFromVault`s the NFT (`:172`, `CauldronCollection.sol:444`, `MiFrensGenesis.sol:649`
→ plain `_burn`) — and `_burn` does **not** decrement `totalMinted`, which is the very
denominator the live ledger floor uses (`PoolOps._eligible` = `totalMinted − ogCount`,
consumed at `PoolOps.sol:1560-1563,1609-1610,1633`).
DELTA: the two mechanisms are not merely "one live, one inert" — they can be live
simultaneously and they do not share a retirement counter. A vault-burned NFT (i) is
destroyed, so it can never be recycled through the live ledger path, while (ii) still
inflating `outstanding(gen, mintedNow)` until death, so every subsequent
`recycleCollectionNFT` pays `entitledTokens/n` with `n` too large. The residual
`entitledTokens[gen]` is never re-claimable and stays inside `totalEntitled`, which the
registry subtracts from **every future generation's** active tranche — the same
permanent cross-generation tax the `isDeadEnd`/`CreditRejected` guard was written to
prevent (`CollectionLedger.sol:126-143`), arriving through a different door.
CLASS: `DEVIATES` (classification "DEPRECATED-PRESENT" is right about intent, wrong
about reachability).
IMPACT: for dust ETH an outsider can open a path that lets forged-NFT holders burn
their NFT for a near-zero ETH payout, permanently destroying their token-denominated
floor claim and shaving the floor of everyone who waits. No attacker profit identified;
the loss is to holders and to future generations' supply.
REPRO (not executed — no source changed): deploy a brew, `vm.deal` a donor,
`payable(vault).transfer(outstanding() wei * k)`, then `vault.redeem(id)` as a forged
holder; assert it does **not** revert `UnifiedFloorActive`, that `collection.totalMinted()`
is unchanged, and that `ledger.floorPerNFT(gen, totalMinted)` fell for the remaining
holders. `test/functional/F11_FloorsAndRedemption.t.sol:58-96` asserts only the
zero-balance state, so it does not cover this.

### G-4 — `redeemOgFren`'s debit became saturating; the spec documents a plain `-=`
FEATURE: G1 / `RedemptionExt.sol:91`
INTENT: spec G1 step 2 — "Debit `genesisReserveOutstanding -= F` (checks-effects, before
the pull)".
ACTUAL: `if (genesisReserveOutstanding >= F) genesisReserveOutstanding -= F;` — the debit
is **skipped entirely** when the accounting scalar is below the floor it just quoted.
DELTA: with `F = genesisReserveOutstanding / genesisShares`
(`CauldronBase.sol:423-427`) and `genesisShares >= 1`, `F <= genesisReserveOutstanding`
always, so the guard is unreachable today — defensive code, not a behaviour change. But
it fails *silently* in the one direction that matters: were it ever reachable, the caller
would still be paid `F` from the LP while outstanding-claims accounting stayed put,
which is precisely an Invariant-R break with no assert to catch it (G-2).
CLASS: `UNDERSPECIFIED` (silent saturation where a revert is the safe failure).
REPRO: read `RedemptionExt.sol:86-106` beside `CauldronBase.sol:423-427`.

### G-5 — Fold-forward still correct for both tranches
FEATURE: G4. Genesis folds `genesisPending` into `genesisReserveOutstanding` at the start
of `relaunch()` and carves it out of `newActive`; creatures fold via
`_flushLegacyAtRelaunch` (`CauldronRegistry.sol:1548-1556`) →
`PoolOps.materializeLegacy` (burn branch, `toReserve = false`) → `ledger.credit`, then
`crystallizeCollection` (`PoolOps.sol:1514-1528`) freezes the supply base from
`IVaultRedeemedOps(vault).outstanding()` and folds the final swept-ETH sizing, and the
**aggregate** `totalEntitled` is subtracted from the new generation's active tranche.
Both redeem legs always resolve the reserve against `g = currentGeneration`
(`CauldronRegistry.sol:1571,1588`), so a generation-1 NFT redeems against generation N's
reserve in generation N's token — no per-collection `claimByBurn` is needed.
CLASS: `CONFORMS` (line numbers in spec G4 are stale). Note the vault remains
load-bearing as the death-time NFT counter, so mechanism (a) cannot simply be deleted —
`PoolOps.sol:1527` must be re-based first (spec G open-delta 6 still stands).

---

## Conformance table

| # | Feature | Class | Test evidence (skips) |
|---|---|---|---|
| A-1 | reveal re-anchor capped at one + Common forfeit | `SPEC-STALE` | read-only |
| A-2 | reveal has no seed pin; owner-only, ~25.6 s window | `DEVIATES` | none exists (gacha twin: M3B 1 PASS / 0 skip) |
| A-3 | gacha seed pinning grants no extra draw | `CONFORMS` + `UNDERSPECIFIED` residual | M3B 1 PASS / 0 skip |
| A-4 | mutable `MAX_PER_WALLET`, ratchet-down only | `CONFORMS` | B2 5 PASS, L1 6 PASS / 0 skip |
| A-5 | `setUnrevealedURI` (both contracts, deployer-only) | `CONFORMS` (`SPEC-STALE`) | read-only |
| A-6 | badges/forged carry no votes; quorum denominator agrees | `SPEC-STALE` (D3 false) | V2B 4 PASS / 0 skip |
| A-7 | badge id namespace + art-cap exclusion | `CONFORMS` | LiquidatoorBadge 8 PASS / 0 skip |
| A-8 | odds displayed == odds committed (curve units) | `CONFORMS` | read-only (chain + FE) |
| G-1 | ledger is the live creature floor | `CONFORMS` / `SPEC-STALE` lines | F11 2 PASS / 0 skip |
| G-1c | `redeemCreature`/`buyTreasuryCreature` | `DESIGN-ONLY` | grep: 0 `.sol` hits |
| G-2 | INVARIANT R on-chain assert | `MISSING` | F11 `…EnforcedAtPayoutNotAtCredit` PASS; LedgerInvariants 3 PASS / 0 skip |
| G-3 | `CauldronVault` re-armable by donation; burn desyncs ledger | `DEVIATES` | uncovered |
| G-4 | saturating `genesisReserveOutstanding` debit | `UNDERSPECIFIED` | read-only |
| G-5 | fold-forward, genesis + creatures | `CONFORMS` | read-only |
| G-6 | `CauldronVault` still load-bearing for death sizing | `DEPRECATED-PRESENT` | read-only |

**Test totals:** 8 suites, 43 tests, **43 passed, 0 failed, 0 skipped** (no fork gate was
silently skipped). Command form: `FOUNDRY_PROFILE=cauldron forge test --match-path <file> -vv`.

---

## Spec statements found FALSE

1. `A_genesis_nft.md` A3 — expired-seed re-anchor is unbounded and "leaves the token still
   unrevealed for a later call". Capped at one since Z-08; the second expiry commits
   `rarityOf = 0` and sets `revealed` (`MiFrensGenesis.sol:588,628-640`).
2. `A_genesis_nft.md` A4 — the gacha re-anchor is described as unbounded and pinning is
   absent from the spec. Both wrong: `REANCHORED_SLOT` caps it and `SEED_SLOT`/`PIN_SPAN`
   pin live seeds (`GachaLib.sol:123,130,147-157,192-215`).
3. `A_genesis_nft.md` open-delta **D3** — "a badge carries ONE governance vote, exactly
   like a volume-minted MiFren". False: `MiFrensGenesis.sol:803` + `:734`.
4. `A_genesis_nft.md` A1/A2 — `MAX_PER_WALLET` described as an immutable checked at
   `:268`; it is now mutable (`:126`) with a ratchet setter (`:297-303`) and the check
   sits at `:338`.
5. `A_genesis_nft.md` — no mention of `setUnrevealedURI` (`MiFrensGenesis.sol:313`,
   `CauldronCollection.sol:388`).
6. `G_floors_redemption.md` G2 §1 — "no ETH leaks in anywhere else … no protocol code
   path does this." Understates it: `receive()` is permissionless and re-arms a
   ledger-desynchronising burn-redeem (G-3).
7. `G_floors_redemption.md` G3 — `CollectionLedger.credit` "grows unconditionally".
   It now drops credits to a dead-end generation (`CollectionLedger.sol:120-123,148-151`).
8. `G_floors_redemption.md` G1 — `redeemOgFren` "Debit `genesisReserveOutstanding -= F`".
   It is now conditional/saturating (`RedemptionExt.sol:91`).
9. `G_floors_redemption.md` — every line number in G1/G2/G3/G4 has drifted (e.g.
   `redeemOgFren` 73→78, `recycleCollectionNFT` 1461→1562, `CollectionLedger.redeem`
   117→161, `PoolOps.recycleCollection` 1356→1572); the branch it was written on
   (`fix/b05-b07-relaunch-totality`) is not `main`.
10. `COLLECTION_FLOOR_UNIFY.md:3` — `Status: DESIGN (approved to build, pre-audit) ·
    branch feat/unified-collection-floor`. P1/P2's live-redeem half is merged on `main`;
    the branch does not exist; the `redeemCreature` rename and the INVARIANT R assert in
    the same P2 bullet are still unbuilt. The doc is simultaneously behind and ahead of
    the code — it should not be used as an intent oracle without this note.
