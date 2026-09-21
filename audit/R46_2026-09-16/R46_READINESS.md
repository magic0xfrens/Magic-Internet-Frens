# R46 — Robinhood mainnet (4663) readiness verdict

Run opened 2026-09-16, closed 2026-09-20. Branch: work landed on `main`
(judging ended mid-run; the owner lifted the freeze). **Nothing pushed.**
31 commits on top of `6eaf67c`, the commit at which the §2 baseline was measured.

Ledger: `audit/R46_2026-09-16/LEDGER.md`. Nine agents, ≤4 concurrent.

---

## 1. Verdict

**DO NOT DEPLOY.** Not because the protocol is unsound — it is in materially
better shape than when this run opened — but because of one defect found in the
last hours and one measurement problem that makes the tree unverifiable today.

**The treasury rotation cannot execute on the mainnet deploy path.** Not
degraded: every `rotateSlice` reverts. The guild can pass a mandate and never
spend it. The fix is written and compiles; **half of it is still uncommitted**
because it is interleaved with another session's in-flight work (§2).

**The suite is at 38 failures against a baseline of 4**, and ~27 of those are
that one defect. That is the good news — it is one cause, not thirty-eight. The bad
news is that **`test/attacks/YBase.sol`, the shared harness every attack PoC
boots from, is uncommitted and unclaimed**, so no suite number anyone reports
right now is reproducible — and that it took four attempts to measure the suite
correctly at all (§6).

Deploy when: the rotation oracle wiring is committed, the suite returns to ~4
known failures, and the harness is pinned. That is days, not weeks.

---

## 2. Can we deploy?

**The mechanism: yes. The configuration: no.**

A real mainnet deploy path now exists (`scripts/deploy-mainnet-rh.sh`, `8def6b1`)
and was **rehearsed end to end against a 4663 fork**: deploy → mint-out → ignite
→ perp → manifest → frontend, with the built bundle rendering live fork state
over `POST 127.0.0.1:8545`. `MAX_PER_WALLET` was read back from deployed state.
**EIP-170 is clear**: 1,605 rows, zero negative runtime margins.

### The blocker

`QuoteRotator.quoteOracle` has exactly **one** writer in the entire protocol —
`setArbParams` (`QuoteRotator.sol:484`) — and the only call to it is
`DeployLaunchpad.s.sol:813`, inside `_deployRotationStack` (`:727`), which `:556`
skips whenever `DEPLOY_QUOTES` is false (`:652`, default **false**).

Mainnet **must** run it false: `MockQuoteToken.sol:27` has an ungated `mint()`
and the rotation stack allowlists that token as a rotation destination.

So on every mainnet deploy the slot stays `address(0)`, `_oracleFloor` returns 0
for every pair, and `QuoteRotator.sol:389 if (floor == 0) revert NotPriceable();`
refuses every slice.

**VERIFIED two independent ways.** (a) `-vvv` trace of
`test_S0x_LIVENESS_RotationCompletesWithAnEmptyPerpBook`: `swapOnce` →
`allowedQuote` = true → `NotPriceable()`, with **no oracle call anywhere in the
trace**, because `_usdLive` short-circuits at `:620-621 if (o == address(0))
return 0`. (b) A peer session ran the deploy script twice: `DEPLOY_QUOTES` set →
18 contracts including `QuoteOracle`; unset → 14 contracts, **no QuoteOracle**.

**`QUOTE_ORACLE` was not a workaround, and believing it was would have been
worse than not having it.** It reaches `gacha.setOracle` (`:282`), the hook's
volume denomination (`:305-313`) and `treasuryGov.setQuoteOracle` (`:534`) — but
never the rotator, and `:813` passes the *locally deployed* oracle rather than
the env value. Setting it nonetheless **cleared the deploy script's only
warning**, so an operator would have seen the alarm go quiet while rotation
stayed dead.

**Status of the fix.** The shell half is committed (`3562770`): the `:385`
comment corrected (it claimed `:533` / DEFAULT TRUE; both wrong), the oracle
check now **refuses** instead of warning, with `ACCEPT_NO_ORACLE=1` as an
explicit opt-in for a deliberately ETH-denominated launch. The Solidity half —
an `else if (quoteOracle != address(0)) { rotator.setArbParams(...) }` — is
written and **compiles clean**, but sits in a `git diff` where **six of seven
hunks belong to another session** and `deployQuotes` is defined in one of
theirs. Committing mine alone would not compile. **This needs whoever owns those
hunks to commit first.**

### Other deploy-config findings

- **CRITICAL, gated:** `DEPLOY_QUOTES` defaulted **true**, deploying
  `MockQuoteToken` with an ungated `mint()` and allowlisting it as a rotation
  destination. Root cause `DeployLaunchpad.s.sol`; the script now refuses.
- **`FEED_ETH_USD` was a wrong constant, not a missing feed.** Chainlink ETH/USD
  **does** exist on 4663 at `0x78F3556b67E17Df817D51Ef5a990cDaF09E8d3A9`,
  8 decimals, `description()` = `"ETH / USD"`, verified live. **But the address
  alone is insufficient**: its published heartbeat is **86,400 s**, while the
  code ships `HB_ETH = 4 hours`. `QuoteOracle.sol:246` returns 0 past the
  heartbeat, so a 4 h window against a 24 h feed reads "cannot judge" for up to
  **20 h of every 24** — the same zero-volume outcome as no feed at all. Set
  `HEARTBEAT_ETH=86400`.
- **No sequencer-uptime feed exists on 4663** (zero hits across Chainlink's
  directory). 4663 is an Arbitrum Orbit L2 and Chainlink's own guidance is to
  check sequencer liveness plus a grace period before trusting a price.
  `_sequencerOk()` returns true when unset — the only available behaviour.
- **Manifest:** `indexerUrl` is genuinely underivable (Railway assigns it) and is
  a required input. `blocks.perp` is **silently wrong** when the perp stage has
  not run — written as the launchpad block, so the indexer would scan perp events
  from a block with no engine. `legacyBps`/`legacyThreshold` cannot be read back
  (`internal`, no getter) and must be re-passed by hand.
- **`docs/MAINNET_LAUNCH.md` is a trap.** Followed verbatim it sets
  `PRESALE_MAXWALLET=100` (wrong), runs a bare `forge script` with no
  `DEPLOY_QUOTES=false`, and instructs a post-deploy `setTwapWindow(15)` that
  contradicts the 300 s floor — and being applied later via the timelock, the
  gate cannot see it. **Rewrite or delete before launch.**

### Three gates that passed on inputs they never read

All three found by executing the gates against adversarial inputs, not reading
them. Fixed in `0b5511b` / `f0c5107`.

1. **`apply-deployment.mjs`'s selector gate had never once executed on this
   machine.** It built a child-process path with `new URL(...).pathname`, which
   percent-encodes; this repo lives at `/Magic Internet Frens/`, so the space
   became `%20`, node exited `MODULE_NOT_FOUND` every run, and the harness
   rendered that as "selector parity FAILED". **The gate was not weak — it was
   never running, and its failure looked like the gate working.** Its own header
   names this defect as the reason `playChurn` shipped twice. Once repaired it
   ran for real: 10 contracts, `playChurn` 3/3, `redeem(uint256)` 1/1 — the vault
   check had also never executed, because it only resolves after a summon.
2. **The repaired EIP-170 gate still fail-opened narrowly.** A build dying
   *mid-table* scans zero rows, and zero rows over the limit reads as "nothing
   over the limit". Header-only and 10-of-803 both PASSED. Now requires a minimum
   row count **and** every deployed contract present by name.
3. **`verify-selectors.mjs` printed "selector parity OK" and exited 0 on a
   manifest with zero contracts** — the gate built to catch `playChurn`.

**The general lesson, and it recurs four times in this run: a gate must
distinguish "I checked and it is fine" from "I could not check."** Both size-gate
bugs, the selector gate, and the `QUOTE_ORACLE` false-clear are that same
confusion.

**The live r44 Sepolia router still lacks `playChurn`** — third sighting.

---

## 3. Re-hunt result

The brief's thesis was that four consecutive remediations had each shipped their
own bug. **This run makes it five and six**, and the pattern is now the single
most reliable predictor in this codebase.

### The two questions §9 required answered either way

**Nested-sweep reentrancy — ANSWERED: guarded, not exploitable.** `_settle`'s
in-place settlement swap does re-enter, but `_liqReentry` makes the inner pass
return **before** `_pokeFunding`, before the book is read, and before any kill
(`PerpEngine.sol:1152` `if (_liqReentry) return complete;`, set `:1166`, cleared
`:1233`). External mutating entrypoints instead carry `notNested` and hard-revert
`Reentrant()`. The asymmetry is deliberate: the sweep must never revert the
triggering swap. Proof at `9f0826a`; the depth counter unwinds to zero and no
position is left half-settled. **Three prior reviews left this open.**

**Book-padding griefing — ANSWERED: real.** `RH2A_BookPadGasFloor.t.sol` asserts
`minGasPadded > minGasEmpty * 2`: padding the book with dust positions **more
than doubles the gas floor of every swap**. This matters beyond griefing — it
means the gas floor is **attacker-influenced**, which is why LIQ04's fixed bound
had to be reconsidered rather than simply raised.

### What held

- **The quorum denominator trap does not bite.** The denominator is
  `TreasuryGovernor.sol:996 getPastTotalSupply(p.snapshot) * QUORUM_BPS / 10_000`
  = `Votes._totalCheckpoints`, and `6eaf67c` fixed the vote-farming bug **at the
  source** in `MiFrensGenesis._update`, so badges enter neither numerator nor
  denominator — the same trace on both sides. Proven at production scale
  (`17fe081`): 1,111 genesis across 112 wallets **plus 3,000 badges** leaves the
  bar at 111 votes, where it would be 411 if badges counted; the proposal
  proposes, votes, warps and executes.
- **`GachaLib` hashed slots held — VERIFIED against real bytecode.** `R2E`
  5 passed / 0 failed / 0 skipped, DELEGATECALLed from a harness owning the
  storage (the same relation as `CauldronHook.sol:2519`), no mock of the code
  under test. **No collision, no overwrite, no pre-emption, randomness is not
  caller-biasable.** Slots derive from `keccak256(abi.encode(bi, BASE))` with
  `BASE` itself a keccak output; 1,024 derived slots across both namespaces gave
  zero self-collisions and none below 4096, and since a Solidity mapping preimage
  is `(key, smallSlotIndex)` while these bases exceed 2^200, the 64-byte preimages
  can never coincide. `_pinSeed` is `private`, single-assignment under
  `if (_seed(k) == bytes32(0))`, and the pinned value is exactly
  `blockhash(commitBlock)` with nothing caller-supplied — a second attacker-sent
  resolve 50 blocks later left it byte-identical, and recomputing wins from the
  pinned seed matched. One re-anchor then terminal forfeit verified end to end.
  **One Low, hygiene:** `PIN_SPAN = 4`, so with 8 queued batches at cursor 0 only
  indices 0–3 pin — the protection does not reach a queue deeper than four.
  Self-rescuable, since `resolveTickets` is permissionless with arbitrary
  `maxCount`.
- **The presale setter held.** Deployer-only, refuses `newCap == 0` or
  `>= GENESIS_SUPPLY`, refuses widening after the first mint; cannot brick
  sellout. Two deployer-role Lows only (a deployer can front-run a pending
  `mint(n)` with a tightening to burn a buyer's gas — zero pre-inclusion privacy
  on 4663 — and can slow sellout arbitrarily). **Badge-spam DoS of a victim's
  genesis mint is refuted:** `_mintLiquidator` is gated to the perp engine, which
  requires sellout, by which point `mint()` is closed; iteration #2 mints ids
  above `GENESIS_SUPPLY` through a different path.

### What broke

- **B-4, HIGH, confirmed and fixed.** `legacyThreshold = 0.02 ether` compared
  against a raw quote-denominated buffer. Measured on the unfixed hook:
  **$9,900,000 buffered on a 6-decimal quote, `token bought 0`, buffer frozen**,
  while the 18-decimal ERC20 control spends end to end. My own earlier read that
  this was probably Low was **wrong**, and wrong because I trusted a source
  comment: `CauldronHook.sol:1125-1134` claims the path is ETH-layout-only and
  that "the native settle would revert against an ERC20 quote anyway". It is
  stale — `LegacyBuyLib.sol:263-275` settles ERC20 via sync→transfer→settle.
  Regression `587a6ed`.
- **`stalled()` dust immunity — Medium, VERIFIED.** `696899b`'s `stalled()`
  (`TreasuryGovernor.sol:926-933`) reads **both** `movedBps` and
  `movedPrimaryBps`. A single **1-bps secondary** slice — `consume(1, false)`, a
  leg the mandate is not about — leaves `allowance()` at the full 10,000 and
  `migrationMandateSpent()` false, i.e. advances the migration by *nothing*, yet
  makes `stalled()` false at cooldown **and 30 days later**. `propose` is then
  blocked until envelope expiry. The design separates those two counters
  precisely so a side-pool slice cannot speak for the migration; `stalled()`
  reading both undoes that separation. The boundary itself is clean (not stalled
  at `+COOLDOWN-1`, stalled at exactly `+COOLDOWN`, both directions), and
  `consume(0,false)` does not immunise — so the dust floor is real but is one
  bps. `capital:` ~0 ETH plus gas; **not flashloanable** (needs a rotatable
  secondary leg in a different quote). Guardian `cancel` remains the escape.
  `R2B_StalledDustImmunity.t.sol`, 3 passed / 0 failed.

### RETRACTED — the round-trip rotation inversion

I reported, and a peer session independently confirmed by its own greps, that
`f3d3f9e`'s derivation inverts on a return trip: after ETH → USDG → ETH,
`RedemptionExt.sol:412-415` would make `fromPrimary` true only for `fromLeg == 0`
(the drained launch pair) and false for the rotated leg holding the treasury.

**Execution refutes the precondition. This is not a finding and must not be
carried as one.** A third reading reached it independently and then ran it
against a stub rotator (so `NotPriceable()` never entered the path and the
rotation genuinely executed). The leg book after the come-home:

```
AFTER away migration ETH->USD        AFTER come-home USD->ETH
  legCount 1                           legCount 1
    .quote      0xA4AD…828c (USD)        .quote      0xA4AD…828c (USD)
    .positionId 39615                    .positionId 39615   <-- unchanged
  generationQuote 0xA4AD…828c          generationQuote 0x0000…0000
```

`generationQuote` came home, but **no ETH-quoted leg was ever pushed** and leg 0
did not move. With one position holding ETH, `fromPrimary` true for `fromLeg == 0`
is **correct**.

**What went wrong in the analysis:** `_upsertLeg` *does* contain a branch that
pushes a new leg, and all three of us verified that branch exists. None of us
checked whether the come-home path actually reaches it with that argument. Two
independent readings agreeing raised confidence when what it really meant was
that both had made the same omission. **Agreement between readings is not
evidence; execution is.**

**It leaves an open LEAD, possibly High.** The come-home slices demonstrably
minted into the ETH/token pair — the denomination flip at `RedemptionExt.sol:615`
requires reaching step 3 with `toQuote == address(0)` — yet
`_recordLeg(gen, address(0), …)` left `legCount` at 1. Either **that position is
unreferenced (the LEG-01 orphan class, `:440-460`, reopened on the come-home
path)**, or the stub rotator's 1:1 accounting routed it somewhere untraced. An
orphaned position is value, not bookkeeping. Next step: re-run `R2D` with
`-vvvv` and grep for `MINT_POSITION` / `LegOpened` between the two dumps.
- **LIQ04 — the bound was wrong, and it was measuring itself.** The assertion was
  `loadedGas <= baselineGas * 4`, failing `3000000 > 1600000`. But the clean-pool
  buy passes at *every* rung, so `baselineGas` reported 400,000 — which is just
  `ladder[0]`, the harness's own first array element. Replaced with a measured
  absolute ceiling of 4M (observed 3M ≈ 10% of a 30M block; the next rung at 5M
  still fails). **No assertion removed; one added** — `assertEq(kills, opened)`,
  pinning all-N-or-revert. `b2b1ae9`.
- **The per-wallet cap did not cap.** `MAX_PER_WALLET` tested
  `balanceOf(msg.sender)` — a current holding, not a lifetime allowance. PoC
  minted **40 under a cap of 20**, one actor, no sybils, by transferring out
  between mints. Now a cumulative `genesisMintedBy` counter (`a552a28`).
- **`/freshness` would have latched a permanent false 503** (HIGH, O1). The
  Ponder finality patch inserted its cases immediately before `default:`, and a
  switch takes the **first** match — so for any chain Ponder already lists, the
  inserted case was **dead code**. On Sepolia the API published 30 while Ponder
  ran 65, against a measured finality lag of **77 blocks** — permanent 503 and a
  permanent "data delayed" banner from the moment it deployed. `8bba93f`; the
  regression is self-defending (revert the placement and the indexer refuses to
  boot).
- **`_rebook` zeroed `p.collateral`** (peer session, `712c2b1`), which zeroed
  funding in both directions, the liquidation penalty, the keeper cut and the
  badge bounty for the rest of a position's life.

### Fix-induced, this run

- **`55ba6fe` — the E1A Critical fix — pushed `PerpEngine` over EIP-170 and made
  it undeployable.** Measured 25,185 B, −609. Recovered by a read-dedup refactor
  (`c20671a`); now 23,382 B with **+1,194 free** after `712c2b1` cost 139 B.
- **The repaired EIP-170 gate shipped its own narrower fail-open** (§2).

---

## 4. Closed this run

| finding | sev | commit | regression |
|---|---|---|---|
| Rotation dead on mainnet path (script half) | **Critical** | `3562770` | `--self-test` 4/4 |
| Rotation dead on mainnet path (wiring half) | **Critical** | **UNCOMMITTED** | compiles; blocked §2 |
| `DEPLOY_QUOTES` ships ungated-mint token as rotation destination | **Critical** | `8def6b1` (gated) | `--self-test` |
| `PerpEngine` over EIP-170, undeployable | **Critical** | `c20671a` | `forge build --sizes` |
| No mainnet deploy path at all | High | `8def6b1` | rehearsed on fork |
| Selector gate had never executed (`%20` path bug) | High | `f0c5107` | 10 contracts checked |
| Deploy gates passed on unread inputs | High | `0b5511b` | adversarial inputs |
| B-4 quote-decimals floor buyback | High | `587a6ed` | `F2A_LegacyThresholdDecimals.t.sol` |
| `/freshness` permanent false 503 | High | `8bba93f` | self-defending tripwire |
| `_rebook` erased funding/penalty/bounty | High | `712c2b1` | `D04_...t.sol` |
| L1-C per-wallet cap bypassable | Medium | `a552a28`, `4c72f71` | `C1_GenesisCapCumulative.t.sol` |
| LIQ04 self-referential bound | Medium | `b2b1ae9` | `LIQ04_GasStarve.t.sol` 7/7 |
| Stop paths had never been executed | Medium | `18033d1` | `L1_LaunchStops.t.sol` 6/6 fork-free |
| No external monitoring anywhere | Medium | `8bba93f`, `7f25f72` | probe + workflow |
| Quorum denominator trap | **no finding** | `17fe081` | `V2C_...t.sol` 2/2 |
| Nested-sweep reentrancy | **no finding** | `9f0826a` | `XL1_...t.sol` |
| `GachaLib` hashed slots | **no finding** | R2E | 5/5 |

---

## 5. Day-one launch configuration

**Opening TVL is knowable exactly: 6.89 ETH.** `igniteCauldron` forwards the
whole contract balance (`MiFrensGenesis.sol:698-699`) and refuses unless the
presale fully sells out (`:692`), so TVL is precisely
`GENESIS_SUPPLY × PRESALE_PRICE` = 1111 × 0.0062. Every cap below is priced
against that rather than guessed.

| knob | current | day one | call | when |
|---|---|---|---|---|
| `liqPenaltyBps` | 690 | **200** | `setFees(690,5000,200,6000,50)` | **pre-handoff** |
| `keeperBps` | 145 | **50** | same call | pre-handoff |
| `minCollateral` | 0.003 ETH | **0.05 ETH** | `setMinCollateral(5e16)` | pre-handoff |
| `nftMaxSupply` | 3333 | **1111** | `setNftMaxSupply(1111)` | pre-summon |
| `MAX_PER_WALLET` | 7 | **20** | constructor | **deploy** |
| `TIMELOCK_DELAY` | **180 s** | **172800** | env | **constructor** |
| `guardian` | **unset** | a separate key | `setGuardian(addr)` | post-deploy |
| `HEARTBEAT_ETH` | 14400 | **86400** | env | deploy |
| `maxNotionalBps` | 500 | keep | — | — |
| `MAX_OPEN_POSITIONS` | 64 | **not settable** (`constant`) | — | new code only |

**`MAX_PER_WALLET` = 20, not 7.** Now that the cap is cumulative it genuinely
binds, which makes the sellout arithmetic a real launch precondition: cap 7 needs
**159** distinct funded wallets, 20 needs **56**, 50 needs **23**. The setter
ratchets *down* after the first mint, so 20 keeps a live lever toward 7, whereas
7 from the start makes 159 buyers a precondition with no recovery but cancel +
refund + redeploy.

**The ordering trap is the whole game.** `DeployPerp.s.sol:247-248` hands hook
*and* engine to the timelock, and every knob above is `onlyOwner`. After that
line each change costs a full governance cycle. `setMinCollateral` is **never
called by the script**, and `setRisk` runs **only if `PERP_WARMUP != 0`**. The
script already learned this for `setGuards` (made unconditional precisely because
"a pending manual step behind an ownership transfer is a step that silently never
runs") and did not apply it to `setRisk`.

**There is a kill switch, and it was not documented.**
`setRisk(warmup, ceiling, maintBps, 0, 0, funding)` zeroes `maxNotionalBps` and
`maxOiBps`, halting **all perp opens** while closes, liquidations and force-close
keep working. One tx, `onlyOwner`, reversible. **DERIVED, not executed — execute
it before launch.** It is the single highest-value item still open.

**Otherwise there is no pause.** No `Pausable`, no `pause()`, no
`whenNotPaused` anywhere. Trading cannot be stopped at all — `trackedPools` is
write-once with no un-track. The only real stops are `setRedemptionPaused`
(`CauldronRegistry.sol:459`, redemption path only) and `vetoEmergency` (`:444`).
Six plausible global-stop selectors against the deployed registry bytecode: all
six revert.

**L1-A (Medium, operational):** `_redeemBlocked()` is
`redemptionPaused && emergencyReadyAt == 0` (`CauldronBase.sol:433-435`), so
**arming an emergency silently disengages the redemption breaker while
`redemptionPaused()` still returns true.** Every dashboard reads PAUSED while the
exit is open, and re-pausing cannot re-close it. Since `emergencyWithdrawLP` is
timelocked, the rescue window is exactly the window holders can race you to the
exit.

### What a capped launch does NOT protect against

**Caps bound loss per transaction; nothing bounds transaction count.** R1A nets
a searcher 0.1% of victim collateral profitably, gas-only. With ~100 ms blocks,
zero priority fee and **no per-actor throttle on any trading path**, halving
`maxNotionalBps` halves per-victim loss and doubles the victim count. Aggregate
exposure is bounded by volume, not by any parameter you can set.

**The perp vault cannot be capped.** `PerpVault.deposit` is permissionless, has
no ceiling, and the contract **has no admin at all**. A third party can deposit
1,000 ETH on day one. S06 and R2A both scale with that number and no knob exists.

**Book-fill DoS is cheap.** `MAX_OPEN_POSITIONS` is a global constant with no
per-actor cap: 64 × `minCollateral` locks every perp trader out, of which only
the ~6.9% open fee is actually spent. At `minCollateral = 0.05`: **3.2 ETH locked
(46% of the pool) + 0.237 ETH burned**, and the positions stay healthy so nobody
can liquidate them.

**A cap does not shrink a logic bug — it makes it cheaper to discover.** A 6.89
ETH pool is a public testnet with real money and an audience. The deploy-config
findings in §2 dominate every cap here.

---

## 6. Suite

| | §2 baseline (`6eaf67c`) | now |
|---|---|---|
| suites | 264 | **295** |
| passed | 1030 | **1113** |
| skipped | 1 | **1** |
| failed | 4 | **43** → **38** (see below) |

Measured under `FOUNDRY_PROFILE=cauldron` with **only** the mandatory permit2
skip. **Skipped did not grow.** Zero infrastructure noise in this run.

**Three earlier numbers in this run were wrong. All three are retracted, and how
they were wrong matters more than the values.**

- **"36 failures" — understated.** It carried a second skip,
  `test/audit_full_scope/**`, on the belief that `PreSweepLargeBookLocal.t.sol`
  did not compile. That belief had a first-hand source — agent F2 hit a real
  `Error (9574): Type uint8 is not implicitly convertible to expected type
  int256` at `:63`. **But the file was fixed afterwards** (mtime 2026-09-19
  09:41; `:63` is now `uint256 paid = _buyExactOut(...)`) and nobody re-tested
  the assumption. The skip silently excluded **14 files / 83 tests**. A peer
  session caught it. *A workaround adopted from a true observation outlives the
  condition that justified it.*
- **"89 failures" — infrastructure.** The first unskipped run was contaminated:
  **66 of 89 were DNS failures** against `ethereum-sepolia-rpc.publicnode.com`
  (`failed to lookup address information`). The endpoint recovered on retry.
  Discarded per the brief's own rule that 429s/5xx are infrastructure. A peer
  session saw the identical spike (110 FAIL lines, `could not instantiate forked
  environment`) on the same host, and **zero** infrastructure failures on a keyed
  endpoint. **Record for anyone re-measuring: the free public endpoint cannot
  carry a 295-suite run.** `rpc.sepolia.org` now 404s and `sepolia.drpc.org` is
  paywalled, so a keyed provider is effectively required to measure this suite.
- **A peer's "35"** was a tree seven commits stale. Same endpoint, so the RPC was
  never the variable.

**43 → 38: five of the failures were mine, and uncommitted.** Three badge tests
(`test_AutoLiquidateOnSwap_MintsBadge`, `test_AutoLiquidate_Many_RektsAll`,
`test_AutoLiquidate_ReentrantKeeper_Blocked`) failed `0 != 1` / `0 != 2` — no
badge struck in-swap. Cause: an uncommitted `_doSweep` hunk in the worktree
changing the loop bound to `spec != 0 || kills < MAX_LIQ_PER_SWAP`, which removes
the kill cap on pre-trade sweeps and burns enough extra gas that the hybrid badge
**defers to `badgesOwed` instead of auto-minting**. VERIFIED by reverting the file
to HEAD: all three pass (gas 1,746,192 / 2,342,949 / 1,828,833). **The hunk has
been reverted and NOT landed**; it is preserved outside the tree. The behaviour
it intended — a pre-trade sweep must scan the whole book rather than certify an
unscanned tail — is still worth having, but not at this cost and not without a
test that pins the badge path.

### The four known baseline failures, individually

1. **`test_S06_POC_RealEngine_...LpB`** — still failing, and the numbers are
   **still bit-identical at a seventh measurement**
   (`344218925886143795 <= 459182015833333191`). Confirmed static, not drifting.
   **Owner decision:** E2's mainnet verdict was that this should not be open on a
   real-money deploy. It is still open.
2. **`test_CHURN1_playWorksButChurnReverts`** — still failing (`EvmError: Revert`).
   Passes once a router with `playChurn` ships. The live r44 router still lacks it.
3. **`test_LIQ04_PreSweepDoesNotStarveTheUsersSwap`** — **FIXED** (`b2b1ae9`).
   Suite 7 passed / 0 failed / 0 skipped.
4. **`test_S08_E_PoC_ABiggerBookRaisesTheBarForEverySweep`** — still failing
   ("the swap still fills below the bar"). Encodes pre-fix behaviour.

### The 35 remaining new failures

- **~27 are ONE cause** — §2's unwired rotation oracle. The `NotPriceable()` ten
  (`S02_*`, `T02_*`, `refute_routeB`) and the rotation-control seventeen
  (`"the rotation must actually run: 0 <= 0"`, `"no slice executed"`,
  `"a slice must move value on a clean book"`, `"the rotation completed"`,
  `"the envelope must run more than one slice"`) are the same defect seen from
  two angles. **These tests are not broken; they are showing exactly what mainnet
  would do.** They should go green together when the wiring lands.
- **2 are stale-by-success** — `test_S0x_DustPerpPositionHoldsTheApprovedRotationHostage`
  and `test_S0x_FIXED_WeightedMarkLetsTheApprovedRotationProceed`, both failing
  with messages beginning `"FIXED: ..."`. They encode pre-fix behaviour and fail
  *because* the fix landed. Retire or invert them; this is bookkeeping.
- **`R2D`** now fails on `"a leg holding the current denomination (ETH) exists
  beside the launch pair: 0 <= 0"` — which is the assertion that **refutes** the
  round-trip inversion rather than confirming it. See §3.
- **2 more were the same reverted hunk** — `test_decimalOverflowRejected`
  (`InvalidHeartbeat(0) != FeedUnusable(0xF628…820a)`) and
  `test_LIQ05_GriefCrossoverVersusVictimHealth` (`WrappedError`). Both **PASS**
  in isolation against the reverted tree (gas 207,565 and 27,744,033), confirmed
  independently by two sessions with matching gas figures. Neither touches the
  oracle surface the first error shape suggested. **So the uncommitted `_doSweep`
  hunk accounted for 5 of the 43, not 3** — and two of those five wore error
  shapes that pointed at an unrelated subsystem. An uncommitted change does not
  fail where you expect it to.

**Caveat that undermines all of the above:** `test/attacks/YBase.sol` is
**uncommitted**. Until it is committed or dropped, every suite number in this
document has an unpinned dependency.

**Build claims are profile-dependent.** Plain `forge build` exits 1 tree-wide
(`Found incompatible versions` — permit2 pins `=0.8.17` against forge-std's
ranges), pre-existing and unrelated to any work here.
`FOUNDRY_PROFILE=cauldron forge build` exits 0. Every "builds clean" in this
document means the latter.

---

## 7. Blind spots

- **`test/attacks/YBase.sol` is dirty and unclaimed.** Shared harness, `_boot`
  made virtual. Neither this session nor the peer owns it. **No suite number is
  reproducible until it is resolved.**
- **The LEG-01 orphan lead is open** — a come-home slice that mints into the
  ETH/token pair while `legCount` stays 1. Possibly High, possibly a stub
  artifact. Not run.
- **The pre-trade full-book sweep is not landed.** The intent — a pre-trade sweep
  must scan the whole bounded book rather than stop at `MAX_LIQ_PER_SWAP` and
  certify an unscanned tail as safe — is sound and is still unimplemented,
  because the attempt cost enough in-swap gas to break the hybrid badge mint.
  Whoever retries it needs a test pinning the badge path.
- **No trades were executed in the deploy rehearsal**, so "the hook records
  non-zero volume once an oracle is wired" is DERIVED, not verified.
- **The indexer was never exercised** in the rehearsal — an invented Railway URL,
  so every indexer-derived UI value rendered `—`. The indexed read layer is
  unvouched.
- **The monitor has never run on GitHub** (that needs a push) and the webhook
  path is untested end-to-end — it needs one pasted secret to arm.
- **Alchemy archive *depth* on 4663 is a vendor claim**, not a measurement.
- **No key-rotation process exists anywhere.** Not written, not built. The
  Alchemy Sepolia key leaked into a transcript in the previous run **and is still
  not rotated** — owner action, steps in `indexer/monitor/README.md`.
- **Never broadcast to real 4663.** Fork only, by design.
- **The oracle heartbeat mismatch is unfixed in code** — `HB_ETH = 4 hours`
  against a 24 h feed. Currently mitigable only by env.

---

## What I would still lose sleep over

**1. That the rotation defect was found by accident, in the last hours, by a
peer session running a suite I had not yet run.** Nobody was looking for it. It
had survived every prior review because reading the code shows a rotation
feature that works — the failure is in what the *deploy script* omits, and no
amount of contract review finds that. This is the third time in this protocol's
history that an entire feature was dead while reading as working. **What would
close it:** a post-deploy conformance test that exercises every advertised
feature against the actual deployed stack — not the source, the deployment. If
the guild can't execute a mandate on the fork, the deploy fails.

**2. That six of nine agents' most valuable findings were things their brief told
them were already true.** The brief said B-3 was uncommitted (it wasn't), that
`MAX_PER_WALLET` must be 7 (it must not), that there was no archive RPC for 4663
(Alchemy is the official provider), that `setGuards` sets `maxNotionalBps` (it
doesn't), and cited setter line numbers that were all wrong. I passed several of
those on to agents as fact before they were checked. **What would close it:**
treat the brief as a hypothesis document and verify its claims at P0, before
spending any agent on work premised on them — which is what §5.12 says and what I
did only partially.

**3. That it took four attempts to measure the suite, and three of the four
wrong answers were confidently reported.** 36 (a stale workaround), 89
(a DNS outage), 35 (a stale tree), and finally 43 — of which 3 were an
uncommitted change of my own that I had been carrying while reporting numbers
measured *with* it. A dirty shared harness, an untracked file that was broken
then silently fixed, and three sessions editing one worktree. **The measurement
apparatus was less reliable than the thing it measures**, and that is precisely
the state in which real-money deploys go wrong: not because anyone lied, but
because every number had a dependency nobody had pinned. **What would close it:**
freeze the tree to one session, commit or drop the harness, and make a clean
~4-failure suite a deploy *gate* rather than a status report — so that measuring
it correctly is forced rather than optional.
