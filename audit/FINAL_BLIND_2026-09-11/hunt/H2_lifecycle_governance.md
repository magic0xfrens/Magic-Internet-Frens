# H2 — Lifecycle & governance (blind hunt)

Tree: `/tmp/blind-final-h2/contracts/solidity`. PoCs: `test/attacks/X2*.t.sol`.
Run: `FOUNDRY_PROFILE=cauldron forge test --match-path 'test/attacks/X2*' --skip DeployPermit2 -vv` → **8 passed, 0 failed**.

---

## 1. Model from code

**Two independent governors, one envelope, one facet.**

`CauldronGovernor` (brews): `propose` (:229, needs 1 vote, strings bounded :246-251), `vote` (:329, checkpointed, window closes before eligibility :448-449), `winner`/`hasProposals` (:375/:394 → `_bestUnconsumed` :446), `markConsumed` (:399, registry-only). Leader is a cached hint + a **one-deep runner-up** (:178-179), with a fallback **positional** rescan of the newest 64 (`_recomputeLeader` :478). `CauldronRegistry.relaunch` gates on `hasProposals()` (:787), reads `winner()` (:849) and consumes late (:977).

`TreasuryGovernor` (envelopes): `propose` (:364, 5 MiFrens, allowlisted + `_requirePriceable` :783), `vote` (:406, five-branch hint), `execute` (:478, permissionless, must be `winner()`, quorum on `getPastTotalSupply`), `cancel`/`setGuardian` (:516/:523, guardian-only), `allowance`/`migrationMandateSpent`/`consume` (:643/:683/:697). `consume` is registry-only and debits **two** counters: `movedBps` always, `movedPrimaryBps` only when the slice came from the generation's own position.

`RedemptionExt` (delegatecall facet, registry storage): value in/out via `redeemOgFren` (:78), `buyTreasuryOgFren` (:115), `donateToReserve` (:136), `materializeLegacyReserve` (:147); rotation via **permissionless** `rotateSliceFrom` (:280) → `PoolOps.removePartial` → `QuoteRotator.swapOnce` (registry-only, :331) → `PoolOps.openOrAddPair` → `_recordLeg` (:679) → `consume` (:437) → conditional `generationQuote[gen] = toQuote` (:505) + best-effort `syncGeneration`. Teardown: `recoverLegs` (:699) reached only by selector from `_removeLiquidity` (Registry:1607); foreign proceeds book to `legProceeds` and exit via owner-only `sweepLegProceeds` (:794).

**Cross-subsystem:** `generationQuote` is read by `PerpEngine` (:1034, :1307), `CauldronGachaRouter` (:205), `PerpMarkSource`; `QuoteOracle.cachedUsdPerRawUnit` is the sole price input to `QuoteRotator._oracleFloor` (:398) and `arbStep` (:496).

---

## 2. Findings

```
id: X2a   severity: High   confidence: VERIFIED
subsystem: cauldron/TreasuryGovernor.sol:697-709 + cauldron/RedemptionExt.sol:437, :504-505
    function consume(uint16 bps, bool fromPrimary) external {
        if (msg.sender != registry) revert NotGuardian();
        ...
        e.movedBps += bps;
        if (fromPrimary) e.movedPrimaryBps += bps;
        if (e.movedBps >= e.maxTotalBps) e.active = false;
  TreasuryGovernor.sol:683
    return e.maxTotalBps >= BPS_ONE && e.movedPrimaryBps >= e.maxTotalBps;
  RedemptionExt.sol:437
    ITreasuryGovernor(gov).consume(sliceBps, fromLeg == 0);
  RedemptionExt.sol:504
    if (fromLeg == 0 && ITreasuryGovernor(gov).migrationMandateSpent()) {
title: Anyone can spend a voted full-migration envelope through a secondary leg so
       `migrationMandateSpent()` can never become true, permanently denying the
       guild's approved treasury redenomination.
precondition: one secondary leg exists whose quote differs from the envelope's
       destination. Legs are created by `_recordLeg` (RedemptionExt.sol:682) on any
       earlier rotation, so this holds for every generation whose guild has rotated
       more than once to different assets. `fromLeg` is an argument of the
       PERMISSIONLESS `rotateSliceFrom` (RedemptionExt.sol:280-285) — no role needed.
sequence:
  1. guild: propose(USDG, 10_000) / vote / execute  →  envelope {maxTotalBps 10000}
  2. attacker: rotateSliceFrom(fromLeg=1, sliceBps=2500, minOut, route)  ×4
     → consume(2500,false) ×4  → movedBps 10000, movedPrimaryBps 0
  3. allowance() = (0,0); envelope.active = false; migrationMandateSpent() = false
  4. guild cannot even re-file: propose reverts CooldownActive for COOLDOWN (7 days)
  5. repeat at every envelope
attacker_cost: 4 txs of gas + the pool fees on rotating a dust leg (governor-side
       bookings measured at 14,057 gas total). No capital at risk, no role.
damage: the generation's recorded denomination can never follow its liquidity;
       `generationQuote[gen]` stays on the launch asset for the generation's whole
       life and the perp engine keeps marking against it. Grief, indefinitely
       repeatable at gas cost; each cycle costs the guild a 3-day re-vote + 7-day
       cooldown.
poc: test/attacks/X2a_MigrationMandateStarvation.t.sol   needs_fork: no
```

```
id: X2b   severity: Medium   confidence: VERIFIED (routing) / DERIVED (stranding)
subsystem: cauldron/RedemptionExt.sol:686-699, :749-751 + CauldronRegistry.sol:1599-1610
  RedemptionExt.sol:690  "Called by `CauldronRegistry._removeLiquidity` during relaunch, and safe to
  RedemptionExt.sol:691   call directly afterwards for a generation whose rebirth predates this."
  RedemptionExt.sol:697  "A failed leg stays recorded, so it can be retried once whatever broke is fixed."
  RedemptionExt.sol:749      } catch {
  RedemptionExt.sol:750          // Left in place on purpose — see the note above.
  CauldronRegistry.sol:1606-1607
        (bool ok, bytes memory ret) =
            ext.delegatecall(abi.encodeWithSelector(RECOVER_LEGS, gen));
title: A rotated treasury leg whose unwind reverts during relaunch is stranded
       permanently, and the documented "retry" reports success while recovering
       nothing.
precondition: one `PoolOps.removeAll` reverts inside the per-leg try/catch — a
       quote token that starts reverting/blacklisting, or a pool broken between
       rotation and rebirth. `recoverLegs(uint256)` has NO registry forwarder and
       the registry declares `receive()` and no `fallback()` (CauldronRegistry.sol:1408),
       so the only caller in the tree is the private `_removeLiquidity(gen)`, which
       relaunch runs exactly once per generation.
sequence:
  1. guild rotates; leg L recorded for generation G
  2. L's quote token begins reverting on transfer
  3. relaunch(): recoverLegs(G) catches L, leaves it recorded, rebirth proceeds
  4. operator "retries": registry.recoverLegs(G) → EMPTY revert (unroutable)
  5. operator calls the facet directly → SUCCEEDS, returns (0,0), reads the facet's
     own permanently-empty storage. Nothing is recovered and nothing says so.
attacker_cost: n/a (not attacker-driven; a hostile quote token makes it cheap)
damage: the leg's LP is locked for the life of the deployment. `legProceedsOf`
       (:757) has no forwarder either, so the booked amount is not even readable
       on-chain from the registry.
poc: test/attacks/X2b_StrandedLegNoRetry.t.sol   needs_fork: no
```

```
id: X2c   severity: High   confidence: VERIFIED (oracle) / DERIVED (rotator consequence)
subsystem: cauldron/QuoteOracle.sol:305-313
    function cachedUsdPerRawUnit(address quote) external returns (uint256) {
        Cached storage c = cache[quote];
        if (block.timestamp <= c.at + TTL && c.factor != 0) return c.factor;
        uint256 fresh = this.usdPerRawUnit(quote);
        c.at = uint64(block.timestamp);
        if (fresh > 0) c.factor = fresh;
        return c.factor;
    }
  consumed by cauldron/QuoteRotator.sol:564-575 (_usd) → :398-408 (_oracleFloor)
        uint256 fair = (inUsd * 1e18) / perUnitTo;
        return (fair * (BPS - rotationSlipBps)) / BPS;
  which is the only non-caller-supplied guard on QuoteRotator.sol:365-367
        uint256 floor = _oracleFloor(from, to, amountIn);
        if (out < (minOut > floor ? minOut : floor)) revert SlippageTooHigh();
title: `c.at` is re-stamped on a FAILED refresh, so a dead/stale/out-of-band feed
       serves its last good price forever; the price guard on the permissionless
       rotation path drifts arbitrarily far from reality while `priceable()`
       correctly reports the asset as unvaluable.
precondition: any feed failure mode `usdPerRawUnit` degrades to 0 — aggregator
       stale past `heartbeat`, reverting, `answer <= 0`, outside `minUsd/maxUsd`
       (the reference deploy bands ETH at $100..$100k, DeployLaunchpad.s.sol:617-621),
       or an L2 sequencer feed that will not answer (:328-343). Measured on this
       project's own testnet: a 23.7h-stale feed against a 12h heartbeat
       (DeployLaunchpad.s.sol:570-573). The TTL early-return then re-serves the
       stale factor for another full window, on every call, indefinitely.
sequence:
  1. cache primed at the good price (any swap or rotation does it)
  2. feed dies / goes stale / the asset leaves its sanity band
  3. `cachedUsdPerRawUnit` keeps returning the pre-death factor: verified unchanged
     after 15 min, 1 year and 10 years of a dead feed
  4. `priceable()` = false the whole time — the governor's gate and the rotator's
     price disagree
  5. attacker calls the permissionless `rotateSliceFrom(0, 2500, minOut=0, curatedRoute)`
     and sandwiches the curated venue; the floor that should stop them is computed
     from the frozen price
attacker_cost: gas + the sandwich capital
damage: measured in the PoC — after a 10x collapse of the destination asset the
       floor `_oracleFloor` computes is 9.7 units where the true-price floor is 97,
       i.e. the rotation will accept **10x too little**, on treasury liquidity, from
       an unprivileged caller. The mirror direction is a liveness bug: a frozen-high
       source price makes every governance-approved slice revert.
poc: test/attacks/X2c_FrozenOracleCache.t.sol   needs_fork: no
```

```
id: X2d   severity: High   confidence: VERIFIED
subsystem: cauldron/CauldronGovernor.sol:474-489
    uint256 internal constant MAX_LEADER_SCAN = 64;
    function _recomputeLeader() private view returns (uint256 bestId, uint256 bestVotes) {
        uint256 n = proposalCount;
        uint256 first = n > MAX_LEADER_SCAN ? n - MAX_LEADER_SCAN + 1 : 1;
        for (uint256 i = first; i <= n; i++) {
  reached from CauldronGovernor.sol:419  (_leaderId, _leaderVotes) = _recomputeLeader();
  and       from CauldronGovernor.sol:452 (uint256 id, ) = _recomputeLeader();
  runner-up mitigation, one deep: CauldronGovernor.sol:356-359
            if (proposalId != _leaderId) {
                _runnerId = _leaderId;
                _runnerVotes = _leaderVotes;
            }
title: 64 junk filings from a single MiFren erase a settled, voted, unconsumed brew
       mandate, and `relaunch()` reverts `NoProposal()` until the guild votes again.
precondition: the runner-up slot must be empty at the moment `markConsumed` fires —
       which happens whenever a third proposal overtakes the leader (the displaced
       LEADER takes the runner slot, CauldronGovernor.sol:357-358, and the previous
       runner-up is forgotten) and two consumptions then drain it. `propose` needs
       ONE MiFren, has no cooldown, no deposit and no per-address cap
       (CauldronGovernor.sol:240).
sequence:
  1. A(100 votes) leads; B(90) is runner-up; C(150) overtakes → runner := A, B dropped
  2. all voting windows close
  3. mallory: propose() ×64 with one MiFren        [11,844,209 gas measured]
  4. relaunch consumes C → promotes A; relaunch consumes A → runner empty →
     `_recomputeLeader()` scans ids (n-63..n) — all mallory's — and returns 0
  5. `hasProposals()` = false → `CauldronRegistry.relaunch` reverts `NoProposal()`
     at CauldronRegistry.sol:787; `winner()` reverts `NoProposals`
attacker_cost: 11.8M gas per cycle (~0.012 ETH at 1 gwei; cents on an L2), 64 txs
damage: the guild's voted mandate is erased. The "relaunches permissionlessly"
       promise stalls until a new proposal is filed AND its 3-day VOTING_PERIOD
       elapses — repeatable every cycle, so relaunch is indefinitely deferrable.
       The sibling governor removed exactly this shape and said why
       (TreasuryGovernor.sol:573-580: "a window over a list anyone may grow is a
       window anyone may flood ... The guild's mandate was erased by spam that cost
       gas"); CauldronGovernor still carries it.
poc: test/attacks/X2d_MandateErasedBySpam.t.sol   needs_fork: no
```

```
id: X2e   severity: Medium   confidence: DERIVED
subsystem: cauldron/RedemptionExt.sol:346-353, :504-505
        if (fromLeg == 0) {
            fromQuote = generationQuote[gen];
            srcPositionId = generationPositionId[gen];
            srcKey = generationPoolKey[gen];
  ...
        if (fromLeg == 0 && ITreasuryGovernor(gov).migrationMandateSpent()) {
            generationQuote[gen] = toQuote;
title: After a migration completes, the ~32% residual left in the primary pair can
       never be rotated again for the rest of the generation.
precondition: a full 10_000-bps mandate consumed from the primary. Slices take a
       share of CURRENT liquidity, so 4×2500 bps moves 1-0.75^4 = 68.4% and the
       code acknowledges the tail (RedemptionExt.sol:501-503).
sequence:
  1. mandate completes; `generationQuote[gen]` flips to the destination
  2. `generationPositionId[gen]` / `generationPoolKey[gen]` still name the LAUNCH
     pair (they must — the 69x redemption reserve shares that key, :718-721)
  3. a NEW envelope is voted; any `fromLeg == 0` slice now reads `fromQuote` from
     the flipped mapping and `srcKey` from the old pair, measures one asset and
     settles another, and reverts (`quoteOut == 0` → BadConfig, :368)
attacker_cost: none — this is the outcome of the honest path
damage: ~32% of the treasury is frozen in the old denomination until relaunch.
       Not lost: `recoverLegs` matches on the primary's own `currency0`
       (RedemptionExt.sol:730) and `seedFunding` is passed the same
       (CauldronRegistry.sol:951), so the tail is recovered at rebirth.
poc: none (DERIVED from RedemptionExt.sol:346-353 vs :505 — the code's own comment
     at :485-489 states this consequence for the leg path it fixed, but the same
     mismatch survives on the legitimate primary path)   needs_fork: n/a
```

```
id: X2f   severity: Low   confidence: VERIFIED
subsystem: cauldron/TreasuryGovernor.sol:523-526
    function setGuardian(address g) external {
        if (msg.sender != guardian) revert NotGuardian();
        guardian = g;
    }
title: The guardian can be set to address(0) with no zero check, permanently
       disabling both the emergency `cancel` (:516) and `setQuoteOracle` (:791).
precondition: a guardian fat-finger or an intentional "renounce".
damage: the only emergency stop on a passed-but-malicious envelope is gone, and
       the priceability gate's oracle pointer can never be re-pointed — both are
       guardian-gated and there is no other writer.
poc: none (one-line read)   needs_fork: n/a
```

```
id: X2g   severity: Low   confidence: VERIFIED
subsystem: cauldron/RedemptionExt.sol:605-609 / cauldron/QuoteRotator.sol:691-695
  RedemptionExt.sol:605  function completeRotation(address quote, uint256 quoteAmount, uint256 tokenAmount)
  RedemptionExt.sol:606      external
  RedemptionExt.sol:607      onlyOwner
  QuoteRotator.sol:693-694
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        if (!(ok && (ret.length == 0 || abi.decode(ret, (bool))))) revert TransferFailed();
title: (a) `completeRotation` is an owner-only facet function with no registry
       forwarder and no fallback — dead bytecode in a contract the tree repeatedly
       cites EIP-170 pressure on. (b) `_safeTransfer`'s header claims the return is
       CHECKED, but an empty return is accepted as success, which is also exactly
       what a call to a CODELESS address produces; there is no `code.length` test.
damage: hygiene. (b) matters only on a path where the asset address can be wrong.
poc: (a) asserted in test/attacks/X2b_StrandedLegNoRetry.t.sol   needs_fork: no
```

---

## 3. Refutations — surfaces attacked hard that held

1. **Rotation back to native ether.** `rotateSliceFrom` gates on `allowedQuote[toQuote]` (RedemptionExt.sol:322) and `address(0)` is both "native" and the zero value, so I expected the return leg to be ungated-out. It is not: `CauldronRegistry.sol:173` sets `allowedQuote[address(0)] = true` in the constructor and `setAllowedQuote` refuses to unset it — `if (quote == address(0) && !allowed) revert NativeQuoteRequired();` (CauldronRegistry.sol:291). `QuoteRotator._allowed` also returns true for `address(0)` unconditionally (:712). Rotation is genuinely two-way. HELD.

2. **`TreasuryGovernor`'s five-branch vote hint (`_leadId`/`_leadVotes`/`_openVotedAt`).** Case (4) at :443-461 is the only branch that LOWERS `_leadVotes`, which is where an erasure would live. I enumerated every path a support vote can take: a vote on a non-leader lands in case 3, 4 or 5; 3 and 5 both stamp `_openVotedAt = now`; case 4's extra clause `block.timestamp > _openVotedAt + VOTING_PERIOD + EXECUTION_WINDOW` therefore guarantees every untracked rival is past `votingEndsAt + EXECUTION_WINDOW` and dead, and `_dead` is monotone (:626-629). I could not construct a sequence where a live, higher-voted rival is demoted. HELD (DERIVED).

3. **`TreasuryGovernor.winner()`'s backward scan** (:593-602). I tried the X2d attack here first. It does not work: the scan walks ids downward and `break`s on the first proposal past `votingEndsAt + EXECUTION_WINDOW`, and `votingEndsAt = created + VOTING_PERIOD` is monotone in id, so the window is TIME-bounded, not positional — spam is paid for per proposal and ages out in 6 days, and no live proposal is ever skipped. The `execute` fast path (`_leadId` + `_executable`, :562-563) is O(1) while a genuine leader holds the hint. HELD.

4. **Double-spending the envelope by re-entering `rotateSliceFrom`** (no `nonReentrant` on :280, on the registry stub at CauldronRegistry.sol:262, or anywhere in `QuoteRotator`) through a hostile quote token during `PoolOps.openOrAddPair`. `consume` re-derives `left` from `allowance()` itself (TreasuryGovernor.sol:701-706) rather than trusting the caller's earlier read, so the second booking reverts `BadParam` instead of over-spending. HELD (DERIVED).

5. **`redeemOgFren`'s conditional reserve debit** (`if (genesisReserveOutstanding >= F) genesisReserveOutstanding -= F;`, RedemptionExt.sol:91) — a "pay without debiting" branch. It is unreachable: `F = floorPerFren() = genesisReserveOutstanding / genesisShares` (CauldronBase.sol:379), so `F <= genesisReserveOutstanding` for any `genesisShares >= 1`. HELD.

6. **`QuoteRotator.unlockCallback` settling the REQUESTED size rather than the realised delta** (`_settle(from, size)` at :631 against `poolManager.swap`'s actual `amount0`). A partial fill would leave a non-zero currency delta and PoolManager's `unlock` reverts `CurrencyNotSettled`. Fails closed. HELD (DERIVED).

---

## 4. Leads (HYPOTHESIS — exact next step)

- **Real keeper cut paid against a fictitious profit.** `arbStep` judges profit entirely through the same cache X2c freezes (`inUsd`/`outUsd`, QuoteRotator.sol:531-533) and then pays `keeperCut = (received * profitUsd * arbKeeperBps) / (outUsd * BPS)` in the REAL received asset to `msg.sender` (:557-559). With one leg's price frozen, a real-value-negative arb can read as profitable and pay a real cut. NEXT STEP: park treasury funds in the rotator via `setPlan` (:212), curate two venues, freeze one leg's feed, call `arbStep` from a stranger and compare the ETH-denominated treasury before/after. Needs a fork.

- **Per-block arb notional cap bypassable by a vetted hook.** `poolManager.unlock` runs at QuoteRotator.sol:526 but `arbUsdThisBlock` is written at :548, AFTER the swaps settle. A curated venue's hook (curation explicitly "vets its hook", :176-178) re-entering `arbStep` from `afterSwap` sees the counter un-incremented. NEXT STEP: deploy a venue whose hook re-enters `arbStep`, list it, and sum the notional moved in one block against `maxArbNotionalUsd`.

- **What the perp engine does in the flip window.** `PerpEngine.sol:1307` reads `if (quote != registry.generationQuote(registry.currentGeneration())) return true;`. `RedemptionExt.sol:505` flips that mapping and then re-points the engine only best-effort inside `try/catch` (:538-540). NEXT STEP: read PerpEngine.sol:1290-1320 to learn what the `true` means, then drive the flip with a `syncGeneration` that reverts and check whether live positions become liquidatable/dead.

- **`_oracleFloor` fails open on an unpriceable SOURCE.** `TreasuryGovernor._requirePriceable` (:783) validates only the DESTINATION and exempts `address(0)` outright (:782). If `_usd(from, amountIn) == 0` the floor is 0 and the permissionless caller's `minOut` stands alone (QuoteRotator.sol:401). The reference deploy does wire a feed for `address(0)` (DeployLaunchpad.s.sol:613) — but only there. NEXT STEP: assert on a real deployment that `QuoteOracle.feeds[address(0)].aggregator != 0` and that its cache is primed before the first rotation; an unprimed cache plus a first-rotation-during-outage is a full-slice drain.
