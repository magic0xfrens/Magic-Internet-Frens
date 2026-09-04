# Progressive-Seed Launch + Vested Old-Holder Claim — Design (NOT built)

Brainstorm w/ Quex + Lana + refinement, 2026-09. Two independent ideas:
1. **Vesting claim** (high confidence, buildable now) — old-gen holders' new
   allocation drips instead of unlocking as an instant dumpable lump.
2. **Progressive seed** (v2, needs audit) — build the FULL active LP thin→full
   over a seed window instead of seeding it all atomically, so snipers eat impact
   early but the token becomes genuinely liquid (both sides) after the window.

The **69× out-of-range reserve is UNCHANGED** — it still accounts for ALL
old-holder supply (the redemption floor). Progressive seed only concerns the
ACTIVE tranche (the raise ETH + the active token tranche).

---

## Idea 2: Progressive seed — the corrected model

NOT a price-gated token-only ladder (that stranded old holders — no bid support
for sells unless new buyers arrive). Instead: **deploy the full two-sided book
gradually, on a schedule independent of buying**, so ETH bid-side liquidity
arrives regardless of demand → old holders CAN exit after the window even with
zero new buyers.

### SAFETY FIRST — two sacrosanct, SEPARATE ledgers (non-negotiable)
The progressive seed may only ever touch the ACTIVE tranche. Redemption backing
is a different bucket that it can never reach:

| Ledger | What | For | Touched by seed? |
|---|---|---|---|
| **A — raise `R` (ETH) + `T_active` (tokens)** | the active LP | traders / market exit | YES — this streams in |
| **B — `T_reserve` (TOKEN, 69× band)** | redemption floor (`floorPerFren × genesisShares`) | **OG minter redemption** | **NEVER** |

**Hard invariant (on-chain assert):** the streamer can deploy at most `R` ETH and
`T_active` tokens; `T_reserve` is placed IN FULL at summon into the 69× band and
is a balance the seeder cannot access. Consequences:
- `redeemOgFren` pulls from ledger B, 100% funded from block 0 → **redemption works
  from t=0 regardless of seed progress** (an OG can redeem the floor even while the
  active book is still thin).
- Even if the active LP is fully drained by sells, the reserve is untouched →
  **minter redemption stays SAFE.** The two ledgers never mix. This is the invariant
  the whole mechanic hangs on — enforce + test it first.

### The launch window is CONFIGURABLE (governance/deploy param)
`T_seed` (time to stream from the seed % to full active depth) and `T_tax` (time
for the surtax to decay to min) are **parameters, not hardcodes** — set per
iteration by the deployer/timelock. Only rule: **`T_tax ≥ T_seed`** — the tax must
NOT reach min before the pool is fully seeded, or you'd open a "cheap-tax +
still-thin pool" window a whale exploits. Also configurable: seed % at t=0 (e.g.
10%), starting tax (e.g. 99%), min tax (e.g. the normal brew tax). On a fast L2,
15–30 min windows are reasonable; longer just drags.

### Worked example — all in % of raise `R` (scale-free)
`price ×= (1 + B/D)²` — `B` = net ETH after tax (%R), `D` = active depth (%R).
Setup: seed **D₀ = 10% of R**, stream to **100% of R over the launch window**;
tax **99% → 1%** over the (≥) same window.

**Whale bringing ETH = 100% of R (as much as the whole raise):**

| window elapsed | Depth (%R) | Tax | Net B (%R) | Price pump | vs CURRENT atomic (D=100% from t0) |
|--:|--:|--:|--:|--:|--:|
| 0%   | 10%  | 99% | 1%  | +21%  | — |
| 50%  | 55%  | 50% | 50% | **+264%** | **+125%** — today lets them accumulate cheaper |
| 100% | 100% | 1%  | 99% | +296% | +296% — identical once fully seeded |

Headline: today a whale who waits out the tax buys a big bag at +125% impact; the
progressive book makes the same whale eat +264% because depth is still thin →
**size is punished exactly during tax-decay.** By window-end both converge (fair,
no first-mover edge). A small buyer (ETH = 10% of R) only ever moves price +2%→+21%
across the window; sells mirror (a 5%-of-R dump craters −75% early vs −10% at full
depth → early dumping self-defeating; floor redemption via ledger B always available).

If nobody buys: price stays ~P0, by window-end the full `R`+`T_active` = a normal
two-sided book identical to the old atomic LP, `T_reserve` sat safe throughout.

### Phase 3.3 — summon integration (NEXT; two blockers to resolve first)
`SeedLib` (3.1) + `CauldronSeeder` (3.2) are built + FORK-PROVEN on live v4. The
remaining work is wiring the seeder into the summon/relaunch path. Design:
- ONE persistent seeder, deployed in DeployLaunchpad, wired to registry + hook.
  Reused each generation via `startSeed` (resets its campaign + positionIds).
- Registry, when progressive is enabled (`seedWindow > 0` + seeder set): seed only
  a THIN active slice, then hand the rest of ledger A (ETH+token) to the seeder via
  a new `PoolOps.createAndSeedProgressive` (delegatecalled → msg.sender = registry,
  so the seeder's onlyRegistry + the token transfer both work from inside PoolOps →
  keeps the registry footprint tiny). Reserve (ledger B, 69×) placed in full as today.
- Hook `afterSwap` → `seeder.poke()` best-effort (try/catch + gas reserve).
- Opt-in: `seedWindow == 0` → the current atomic green-candle path, unchanged.

⚠️ **BLOCKER 1 — EIP-170 (measured: ~450 B reclaim needed).** The wiring was built
end-to-end and compiles, but pushes the registry ~430 B over the 24,576 limit even
AFTER (a) moving the atomic-vs-progressive branch + SeederConfig build into
`PoolOps.createAndSeedProgressive` and (b) making floor/throttle/band-width fixed
PoolOps constants (only the WINDOW stays per-iteration). Remaining registry
additions that don't fit: `seeder` storage + `setSeeder`, `nextSeedWindow` +
`setLaunchParams(ceilingOffset, window)` (replaces `setReserveCeiling`), and the
one `createAndSeedProgressive` call site w/ the `SeedParams` build. Net ≈ +430 B
over.
- **Status:** the SAFE, deployable-neutral half is COMMITTED — `ISeeder`/`SeederConfig`
  (shared type) + `PoolOps.createAndSeedProgressive` (the summon-side glue). The
  registry edits were REVERTED to keep main deployable (registry back at +86 B).
- **MEASURED (2026-09): setter consolidation is NOT enough.** Attempted the full
  wiring + reclaim end to end: with the branch/struct-build moved to
  `PoolOps.createAndSeedAuto` and floor/throttle/band-width as PoolOps constants,
  the registry was **+431 B over**. Consolidating `setGovernor`+`setFactory`+
  `setCollectionLedger`+`setSeeder` into one `setWiring(...)` reclaimed only ~59 B
  net (a 4-field guarded setter is ~as big as the 3 one-liners it replaced) → still
  **+372 B over**. Conclusion: the registry is SATURATED; setter-golfing yields too
  little. Closing the last ~370 B needs an **architectural** change, not micro-golf:
  - **(A) split the registry** — move a coherent subsystem (e.g. the OG-redemption/
    legacy-reserve ops: `redeemOgFren`/`buyTreasuryOgFren`/`donateToReserve`/
    `materializeLegacyReserve`) into a sibling contract the registry calls, freeing
    ~1–2 KB. Biggest, cleanest headroom; needs careful storage/ownership design.
  - **(B) offload those same ops to a linked delegatecall lib** — less refactor but
    storage-layout-sensitive (the lib must mirror registry slots exactly). Riskier.
  All of this is a DEDICATED, reviewed effort on real-money code — do NOT rush it
  at the tail of a session. The wiring diff itself is small + known; it drops in
  once the space exists.

  **Turnkey recipe for option (A) — shared-storage facet (execute deliberately,
  storage layout independently reviewed before deploy):**
  1. New `CauldronBase is Ownable, ReentrancyGuard, <same storage-bearing bases in
     the same order>` — move ALL registry state vars into it, in the SAME order.
     Layout is then identical BY CONSTRUCTION as long as neither child adds state.
  2. `CauldronRegistry is CauldronBase, IUnlockCallback` — functions/events/errors/
     modifiers only, NO new state vars.
  3. `RedemptionExt is CauldronBase` — bodies of `redeemOgFren`/`buyTreasuryOgFren`/
     `donateToReserve`/`materializeLegacyReserve` only.
  4. Registry keeps thin forwarders: `(bool ok, bytes memory ret) =
     redemptionExt.delegatecall(msg.data); if(!ok) revert; return ret;` (custody
     stays in the registry — delegatecall runs ext code on registry storage).
  5. ⚠️ IMMUTABLE GOTCHA: `mifrens` + `positionManager` (+ any immutable the ext
     reads) MUST become STORAGE vars in the base — immutables resolve against the
     EXECUTING contract's code, so under delegatecall the ext would read ZERO.
     Registry constructor writes them to storage. (Fork tests for redeemOgFren
     catch a miss loudly — zero addr → revert — but review the layout regardless.)
  6. Gate: full 183-suite + all fork tests green (they exercise redeem/buy/summon/
     relaunch → a layout or immutable slip fails them). THEN drop in the seeder
     wiring diff (setWiring + setLaunchParams window + createAndSeedAuto call).

  **✅ DETERMINISTIC VERIFICATION (use this, not eyeballing) — `forge inspect`:**
  Foundry emits the exact compiled storage layout (slot/offset/bytes per var). The
  correct check for a delegatecall facet is that the two sharing contracts have
  IDENTICAL layouts:
  ```
  FOUNDRY_PROFILE=cauldron forge inspect CauldronRegistry storageLayout > /tmp/reg.txt
  FOUNDRY_PROFILE=cauldron forge inspect RedemptionExt   storageLayout > /tmp/ext.txt
  # strip the trailing "Contract" column, then:
  diff <(cut -d'|' -f2-6 /tmp/reg.txt) <(cut -d'|' -f2-6 /tmp/ext.txt)   # MUST be empty
  ```
  A ground-truth pre-refactor snapshot is committed at
  `docs/registry-storage-baseline.txt` (41 real storage slots, 0..40; immutables are
  NOT in it — they live in code, so converting them to storage ADDS new slots and
  shifts everything, which is fine for a FRESH deploy as long as reg==ext). NOTE:
  this is a NEW mainnet deploy, not a proxy upgrade → the layout need NOT match the
  old registry; it only needs reg-layout == ext-layout. Also run a
  **`solidity-auditor` pass** on the delegatecall/immutable/forwarder semantics +
  custody logic (the layout diff proves slots; the audit proves behavior).

  ⚠️ The hand-listed order BELOW is a REFERENCE ONLY and is known-incomplete (it
  missed `autoMigrate` @ slot 40). TRUST `forge inspect` / the baseline file, not
  this list, for the authoritative layout.

  **Hand-reference (non-authoritative) ordered layout for `CauldronBase` — 3
  immutables become the first STORAGE vars set in the registry ctor; exclude
  constants; move initializers (3333/500/15000/1h) to the ctor; `_seedBuyUnlocked`
  private→internal; inheritance `Ownable, ReentrancyGuard` (registry adds
  `IUnlockCallback`, ext adds nothing):**
  ```
   1 IPoolManager     poolManager        // was immutable → STORAGE
   2 IPositionManager positionManager    // was immutable → STORAGE
   3 CauldronHook     hook               // was immutable → STORAGE
   4 bool             summoned
   5 bool internal    _seedBuyUnlocked
   6 uint256          currentGeneration
   7 address          currentToken
   8 mapping(uint256=>address)  generationToken
   9 mapping(uint256=>address)  generationProposer
  10 mapping(uint256=>uint256)  generationParent
  11 mapping(uint256=>PoolId)   generationPoolId
  12 mapping(uint256=>PoolKey)  generationPoolKey
  13 mapping(uint256=>uint256)  generationPositionId
  14 mapping(uint256=>uint256)  generationReservePositionId
  15 mapping(uint256=>int24)    reserveTickLower
  16 mapping(uint256=>int24)    reserveTickUpper
  17 uint256          genesisReserveOutstanding
  18 mapping(uint256=>mapping(address=>bool)) claimed
  19 mapping(uint256=>address)  generationCollection
  20 mapping(uint256=>address)  generationVault
  21 ICollectionLedger collectionLedger
  22 uint256 internal genesisPending
  23 ICauldronFactory factory
  24 ICauldronGovernor governor
  25 uint256          nftMaxSupply        (init 3333 → ctor)
  26 address          royaltyDividend
  27 uint96           royaltyBps          (init 500 → ctor)
  28 MetadataMode     genesisMode
  29 string           genesisBaseURI
  30 address          genesisRenderer
  31 address          mifrens
  32 uint256          genesisBonusBps
  33 uint256          genesisShares
  34 uint256          genesisSharePerFren
  35 uint256          enchantFeeMultBps   (init 15_000 → ctor)
  36 bool             redemptionPaused
  37 address          guardian
  38 address          successor
  39 address          claimGate
  40 address          airdropWallet
  41 uint256          airdropReserve
  42 uint256          primeBuyEth
  43 address          primeFunder
  44 address          emergencyAdmin      // was immutable → STORAGE
  45 uint256          emergencyDelay      // was immutable → STORAGE
  46 uint256          emergencyReadyAt
  47 uint256          lastSummonAt
  48 uint256          minLifetime         (init 1 hours → ctor)
  49 int24 internal   nextReserveCeilingOffset  (keep; already exists)
  // + seeder additions: address seeder; uint64 nextSeedWindow;
  ```
  Redemption ops read immutables hook(7×)/poolManager(3×)/positionManager(8×) → all
  three MUST be storage. `mifrens` is already storage. ⚠️ REVIEW THE STORAGE DIFF
  SLOT-FOR-SLOT (human/auditor) before this touches a live deployment — a passing
  test suite catches gross errors, not every layout subtlety, and the failure mode
  is irreversible loss of the redemption reserve.
- Exact registry diff that needs to fit (from this session, reverted): `setLaunchParams`
  + `setSeeder` + `seeder`/`nextSeedWindow` storage + swapping the seed call to
  `createAndSeedProgressive` when `seeder != 0 && nextSeedWindow > 0`.

⚠️ **BLOCKER 2 — teardown of the seeder's positions.** Today death/relaunch reclaims
ONE active position. The progressive seeder mints N distributed mini-positions
(one ask + one bid per poke). At death these N must be unwound + their ETH/token
returned to the relaunch flow. Options: (a) seeder exposes `withdrawAll(to)`
(registry-only) that burns all positionIds → returns funds to the registry at
relaunch; (b) cap N low (coarse minStepWad) so teardown gas is bounded. Needs a
design decision + its own fork test (seed → partial fill → death → full recovery,
no funds stranded). This is the real remaining design gap.

### The hard truth (settled)
You cannot both allow free trading during the seed AND peg the end price to P0 —
real buys must move price (pegging = defending a peg = arbers drain the treasury).
So the goal is **conserve LIQUIDITY, not price**:
- Total ETH + active-tokens deployed = exactly the old atomic-seed model's.
- **Zero net flow → pool ends identical to the old LP; vesting holders are exactly
  where they were when the old LP was removed.** (Provable — the case Lana cares about.)
- Net buys → higher price (real appreciation, fine).
- Net early sells (old holders dumping a thin book) → lower price + they eat the
  impact (discourages early dumping, fine).

### How to add LP with NO leftover-ratio problem
Two-sided adds at a drifted price leave leftover ETH *or* tokens (ratio is fixed by
current price). Fix: add **single-sided** on each side —
- **ETH → bid bands BELOW spot** (what sellers, incl. old holders, sell into).
- **tokens → ask bands ABOVE spot** (what buyers buy).
Single-sided adds have no ratio constraint → never a mismatch. In aggregate at
rest they equal a concentrated two-sided position centered at P0 = the old LP. As
price moves it just consumes one side.

### Liquidity shape & range (the crux)
Key fact that resolves the "capital efficiency" worry:
`ETH single-side [Pa,P0]  +  token single-side [P0,Pb]  ≡  ONE concentrated
position on [Pa,Pb]`. It's MORE capital-efficient than full range (more depth per
$ inside the range), so this is an UPGRADE over today's active LP (which is
full-range + the 69× reserve), not a downgrade.

- **"Idle ETH after a pump" is NOT waste** — when buys eat the token asks, the
  position converts to ETH sitting as bids below spot = exactly the exit liquidity
  old holders sell into. Every concentrated position goes one-sided at its edges;
  that's normal, not an inefficiency we introduced.
- **The real knobs are RANGE + SHAPE, not auto-rebalancing:**
  - **Bid floor:** don't extend to 0 (capital at prices that never occur). ~**−80%**
    (bids from P0 down to ~0.2×P0) is plenty; below that the 69× redemption floor
    is the backstop.
  - **Ask ceiling:** up to **P_max** = discovery cap (~5–10× P0). Running out of
    ask above P_max just means "price discovered."
  - **Depth profile:** deliberately concentrate MOST depth in narrow bands near P0
    and taper into the tails (uneven liquidity is a feature we choose). Yes, some
    prices are deeper than others — by design.
  - **Band count:** few. Minimum 2 (one bid range + one ask range); ~3 ask + 2 bid
    for a tapered profile. More = smoother but more summon gas. Not dozens.
- **P0 = the price the FIRST sell/marginal trade gets.** Not everyone exits at P0 —
  pool ETH depth caps that (game of chairs, same as the old model). Marginal/gradual
  exits ≈ P0; a mass dump walks the book down.

### Auto-concentrate / auto-rebalance — REJECTED for launch
A hook that re-centers liquidity on spot each swap (Gamma/Arrakis-style) is a
dangerous rabbit hole here:
- **Bleeds to MEV:** attacker moves price with a big swap → hook re-centers onto the
  manipulated price → attacker reverses → freshly-placed liquidity fills the reversal
  at bad prices → pool drained. Needs TWAP-gating + cooldowns = big audit surface.
- **Fights anti-snipe:** auto-deepening around spot right after a snipe undoes the
  thin-book punishment.
- **On a pump, re-centering buys token back high** → pool chases price → rebalance loss.
Capital efficiency is a PERMANENT-LP concern; a launch mechanic wants controlled,
bounded, ungameable release. **Optional safer middle ground (v2+):** a
ONE-DIRECTIONAL RATCHET — ask bands re-place UPWARD only as price rises (fresh
resistance above), bid-side stays the fixed P0-floor. Never chases price down, so
it dodges the reversal-drain exploit.

### Anti-gaming: stream, don't randomize
"Pseudo-random adds" fights the problem the wrong way — and Arbitrum has NO
on-chain randomness (`prevrandao`=1), so RNG timing is fragile there. Better:
**continuous streaming** — the deployed fraction advances pro-rata to elapsed
time, added in tiny slivers on each swap (hook `afterSwap`) or any permissionless
`poke()`. No discrete "add LP" tx exists → nothing to sandwich/front-run → no RNG
needed. Strictly better than random discrete adds.

### Why it beats "deep seed + high tax"
A thin early book makes a block-0 snipe eat massive PRICE IMPACT (which tax can't
replicate) on top of the surtax; later organic buyers get better prices as depth
streams in. Impact does the anti-snipe work structurally.

### Reserve interaction: max pump, the gap, and redemption-in-range
- **Max pump is UNCHANGED.** The active ask ceiling `P_max` does not cap price —
  above it, the 69× reserve (untouched) is the real ceiling. Progressive seed only
  reshapes `P0→P_max`. Same top-end as today.
- **Gap → price teleports.** In v3/v4 a swap across a ZERO-liquidity tick range
  moves price for ~free (snaps to the next liquid tick). If there's a dead zone
  between `P_max` and the reserve band, a big buy that clears the active asks jumps
  price straight to 69×. FIX: taper active asks to connect continuously (thin but
  non-zero) up toward the reserve → price climbs steeply instead of teleporting.
  The reserve then catches the mania and converts token→ETH (grows the floor) — by
  design.
- **⚠️ Redemption-in-range → "you still get your value out at 69×" (BUILD REQ).**
  `redeemOgFren → PoolOps.claimFromReserve` does DECREASE_LIQUIDITY + TAKE_PAIR and
  its comment ASSUMES *"reserve is out of range so ETH out = 0"* → redeemer gets F
  TOKEN while `floorPerFren`/`genesisReserveOutstanding` are token-denominated. If a
  mega-pump pushes price INTO/THROUGH the 69× band the reserve has converted
  token→ETH, so the raw-token assumption breaks. **Requirement: a redeemer must
  always receive their CORRESPONDING VALUE, in whatever the band now holds —**
  - Below the band (normal): pay `F` TOKEN, as today.
  - In/above the band (post-69×): the removed liquidity yields ETH — pay the
    redeemer that ETH, which is their share's value (the reserve sold their tokens
    high, so the ETH ≈ `F × the crossing price` — a *better* outcome, not a loss).
  - **Accounting fix:** track the reserve as VALUE (a per-share claim on the reserve
    position), and on redeem remove `liquidity = pro-rata share of the position` and
    `TAKE_PAIR` whatever mix (token and/or ETH) it yields → the redeemer's value is
    conserved on both sides of the band, and `genesisReserveOutstanding` debits by
    the share removed (not a fixed token qty that desyncs). Never leaves a redeemer
    short. Test: redeem below band, exactly at band-cross, and fully above.
  - Independent of progressive seed but adjacent — spec it into the reserve rework.

### Interactions to resolve (why it's v2 + needs audit)
- **Green-candle relaunch** currently seeds the ENTIRE supply full-range then
  market-buys the reserve amount to fund the out-of-range band + print a green
  candle. Streaming the active seed conflicts with that atomic path — must be
  reconciled (does the green candle still fire? at what point in the stream?).
- **Death clock:** does streamed seeding count as volume / when does the death
  timer start — at first seed or at full seed?
- **Perp warmup:** don't let perps open against a half-seeded thin book.
- Rewrites the summon/seed path (`PoolOps` / `CauldronRegistry`) — most sensitive
  code. Fresh audit + fork tests (partial-fill, exhaustion, dump-into-thin-book).

---

## Idea 1: Vested old-holder claim (buildable now, high confidence)
- **Burn old-gen token → new alloc is a LINEAR VESTING DRIP** (claimable over a
  window, hours–days), NOT an instant lump → can't nuke a pump peak in one tx.
- **Stakers get INSTANT claimable** — reward for committing ("stake & chill"),
  ties to the perp-autostake stakers who already carry across relaunch.
- Buildable as a vesting escrow keyed to burn timestamp; does NOT touch the pool,
  so it's low-risk and can ship independently of Idea 2.
- Decide: which "stakers" get instant (perp PLV stakers? enchanted genesis?) +
  vest window length.

---

## Supply accounting — disjoint buckets (double-spend guard)
1. seed active LP (streamed) · 2. floor reserve @69× (UNCHANGED) ·
3. old-holder vested claim · 4. staker instant claim.
Registry tracks `reserveTokens`; add a streamed-active bucket + a claim bucket so
nothing is placed/minted twice.

## Config params (per-iteration, set at summon from the winning proposal — like name/symbol)
- **`reserveCeilingMult` / `reserveCeilingOffset`** — the "69×" is TODAY a hardcoded
  `RESERVE_CEILING_OFFSET = 42400` constant in the registry, but `PoolOps`/`ReserveLib`
  ALREADY take it as an argument. Make it a **per-iteration parameter** (stored per
  generation, chosen in the governance proposal alongside token name/symbol/supply):
  e.g. a spicy iteration ships a 420× ceiling, a conservative one 10×. Offset =
  `ln(mult)/ln(1.0001)` aligned up to tick spacing. Just plumb the stored value into
  the existing `ceilingOffset` arg instead of the constant.
- `launchWindow` (= `T_seed`): time to stream seed% → 100% active depth. CONFIGURABLE.
- `taxWindow` (= `T_tax`): time for surtax to decay to min. **Must be ≥ `launchWindow`.**
- `seedPct` at t=0 (e.g. 10%), `taxStart` (e.g. 99%), `taxMin` (e.g. normal brew tax).
- (v2 opt) `bidFloorPct` (~−80%), `askCeilingMult` (P_max ~5–10×), band count/weights.
- NOTE the ceiling interacts with the redemption-in-range req above: a LOWER ceiling
  (e.g. 10×) is far easier for price to actually reach, so the "value out at the
  ceiling" handling is MORE important the lower the mult is set.

## BUILD ARCHITECTURE — a dedicated `CauldronSeeder` contract (chosen)
The registry is at the EIP-170 limit, so DON'T pile the streaming logic into it.
Instead isolate it in a fresh, independently-auditable contract:

- **`CauldronSeeder` (new contract, own deploy → not subject to the registry's
  size limit).** Holds the streaming schedule + the held active-tranche ETH+tokens
  (ledger A only). Exposes `poke()` (permissionless) and is poked by the hook's
  `afterSwap`. Places single-sided bands (ETH bid below / token ask above) into the
  pool pro-rata to elapsed time until fully seeded. All the risky new math lives here.
- **`SeedLib` (linked pure lib):** band tick math + the elapsed→fraction schedule.
- **Registry: MINIMAL change** — summon seeds only the thin slice, then hands the
  rest of ledger A to the Seeder + records it. A few lines, not a rewrite → little/no
  new EIP-170 pressure (the whole reason to use a separate contract). `T_reserve`
  (ledger B, the 69× reserve) is placed in full at summon exactly as today — the
  Seeder never touches it (the sacrosanct-ledger invariant is structural: the Seeder
  literally only holds ledger A).
- **Hook `afterSwap`:** one `seeder.poke()` call (best-effort, try/catch, gas-reserved
  — never reverts a swap). Continuous streaming = no discrete add tx to front-run.

Build order (Phase 3):
1. `SeedLib` + `CauldronSeeder` with unit tests (band placement, schedule, disjoint
   ledger) — no registry/summon changes yet.
2. Fork tests: seed thin → poke over time → depth grows → buys/sells behave per the
   %R model; zero-flow ends == atomic-seed end state.
3. Wire summon (thin seed + handoff) + hook afterSwap poke. Reconcile GREEN-CANDLE
   (does the first-block buy fire against the thin slice or post-stream?) + death
   clock (timer starts at full seed) + perp warmup (no perps vs half-seeded book).
4. **Phase 2 redemption "value-out at the ceiling"** (pay ETH-equiv when the reserve
   band is crossed) — independent but ship together.
5. Full audit pass (solidity-auditor skill).

## Recommendation
- ✅ **Idea 1 (vesting) SHIPPED** (commit e5a0e52) — escrow + per-iteration ceiling +
  EIP-170 reclaim, 162/162 green, deployable.
- **Idea 2 (progressive seed):** build via the `CauldronSeeder` architecture above
  (keeps the registry lean). Ledger-A/B disjointness is structural (Seeder holds only
  ledger A). Frame the goal as **conserved liquidity** (zero-flow → identical to old
  LP), NOT pegged price.
