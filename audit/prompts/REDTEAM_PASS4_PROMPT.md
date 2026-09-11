# Red-Team Pass 4 — Adversarial Exploit Prompt

Paste everything below the line into a fresh session opened at the repo root.

---

You are an adversarial security researcher running a **red-team exploit engagement**
against Magic Internet Frens / The Cauldron. You are not reviewing code for style.
You are trying to steal money.

Your objective, stated plainly: **extract value from this protocol, or brick it.**
Drain the fee reserve. Break the 1:1 claim guarantee. Make the perp vault insolvent.
Mint tokens you did not pay for. Liquidate a solvent position and take the bounty.
Force a relaunch that seeds a pool you control. Make the machine unable to relaunch
at all and strand every holder. Any of these is a win. Find the cheapest one.

Work like an attacker with a real budget: you have flash liquidity, you can deploy
contracts, you can be the LP, you can be the counterparty, you can call anything
permissionless, and you can wait. You do **not** have any privileged key.

## This is Pass 4. Read passes 1–3 first.

Three red-team passes already ran. Do not waste the engagement rediscovering them:

- `contracts/solidity/test/attacks/EXPLOIT_REPORT.md` — passes 1–2. Findings A-01
  (CREATE2 summon/relaunch squat, CRITICAL, fixed), A-02 (stale-`lastTick` mark
  poisoning, HIGH, fixed), A-03 (`forceCloseAllDead` cap strands the engine, HIGH,
  fixed), plus proven-safe results A-05 through A-08.
- `contracts/solidity/test/attacks/EXPLOIT_REPORT_PASS3.md` — pass 3, with a lead
  ledger driving every open item to a verdict. Y-01 reserve-ceiling breach
  (CONFIRMED Medium), Y-02a depth-derived risk caps flash-manipulable (CONFIRMED
  mechanism), Y-02b PLV drain (REFUTED), Z-07 relaunch gas brick (fixed), Z-12,
  Z-17 (fixed).
- Existing PoC harnesses you should reuse rather than rebuild:
  `test/attacks/YBase.sol` (raw `modifyLiquidity` for LP-primitive attacks;
  directional pumps through the 69× reserve ceiling), `test/attacks/ZAuditBase.sol`,
  `test/final/FinalAuditBase.sol`.
- Existing PoCs: `test/audit/AuditPoC{,2,3,4}.t.sol`,
  `AuditPoC5_DividendBasket.t.sol`, `AuditPoC6_QuoteReserve.t.sol`,
  `AuditPoC7_StaleOracleDeath.t.sol`, `ReserveBoundProbe.t.sol`.

**Verify the fixes actually hold.** A finding marked FIXED in a prior report is a
claim, not a fact. Re-run those regressions and try to route around each patch —
patched bugs are the highest-yield hunting ground in any codebase, because the fix
was written under time pressure by someone who had already decided the bug was
understood.

### The surface no pass has ever touched

Pass 3 predates the entire **multi-quote / multi-pool refactor** — roughly 30 commits
between `b5db948` and `HEAD` (`0a1830b`). None of it has ever been red-teamed. This is
your primary hunting ground:

| Commit | What landed |
|---|---|
| `b5db948`, `c18bfe2`, `acc379f`, `05c6bf6`, `7ff2508` | Perps and pool construction on any quote asset; token address mined above the quote |
| `e8cff39`, `01c2d69`, `2a61052`, `4019623` | `QuoteRotator` — the guild rotates what the LP is denominated in; rotation modelled as a flow |
| `662a3fa`, `a01d8fe` | Death judged on a *generation's* volume across pools, normalized across quotes |
| `dfe5db2`, `87922e2` | `TreasuryGovernor`; proposals compete instead of queueing |
| `aadcaad`, `047400a` | `QuoteOracle` — volume denominated in USD via Chainlink, cached |
| `3c9b453` | `arbStep` captures the spread between the protocol's *own* pools |
| `a1e7dae` | `MiFrensDividend` pays a multi-asset fee basket |
| `bb1e7e3` | Quote-agnostic perp trading; vault stakes in the generation's quote |
| `b4c125b`, `710e138` | `FeeRouteLib`; hook routes fees in whatever asset it collected |

New code, no adversarial review, and it touches every value path in the system.
Start here.

## Environment

```bash
cd contracts/solidity
export FORK_RPC=https://ethereum-sepolia-rpc.publicnode.com \
       POOL_MANAGER=0xE03A1074c86CFeDd5C142C4F04F1a1536e203543 \
       POSITION_MANAGER=0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4
FOUNDRY_PROFILE=cauldron forge build
FOUNDRY_PROFILE=cauldron forge test --match-path 'test/attacks/*' -vv
```

Fork tests **silently no-op** without those env vars. A green run that skipped
everything is worse than a red one. Confirm the fork suites actually executed.

Live deployment for reference: `indexer/deployments/round.json` (round 34, Sepolia
`11155111`). Mainnet target is **Robinhood Chain**, an Arbitrum Orbit L2 — pass 3
carried Z-13/Z-14/Z-21 as "deployment-config items" precisely because block clocks,
`tx.origin` aliasing and sequencer behaviour differ there. Re-open those. An L2
assumption that was merely *accepted* on testnet becomes an exploit on mainnet.

## Attack surface — where the money is

**The value sinks.** Hook fee reserve, `PerpVault` PLV + insurance, `MiFrensDividend`
accumulator, the LP position itself, the 69× redemption reserve, `MigrationVesting`,
`CauldronSeeder` ledgers, royalty flows. For each: who can move value out, and what
is the *cheapest* input that makes it move in your direction.

**Multi-quote — the new seams.** Attack these specifically:

- **Decimals.** USDG is 6-decimal, ETH and xNVDA are 18. Every conversion between
  raw units and USD is a place to lose or gain a factor of 10^12. Hunt for a path
  where a 6-decimal quote is treated as 18 or vice versa, then size the profit.
- **The oracle.** `QuoteOracle.usdPerRawUnit` returns 0 when it does not trust the
  price. What consumes that 0? Can you *induce* the 0 — stale round, sequencer
  downtime on an Orbit L2, a quote whose feed you can grief — and does the protocol
  then fake a death, refuse a real one, mis-split a fee, or misprice a liquidation?
  `AuditPoC7_StaleOracleDeath.t.sol` opened this door; walk further through it.
- **Volume normalization.** Death is now judged on USD volume across a generation's
  pools. Can you inflate USD volume cheaply in a thin quote to keep a dead
  generation alive, or suppress it to kill a live one? Wash-trading cost vs. the
  value of controlling relaunch timing — compute it.
- **The fee basket.** Fees now accrue in whatever asset was collected. Dust,
  rounding direction, and `FeeRouteLib.send` vs `deliver` (the dividend and perp
  engine are pull-based *because* a stray transfer would look identical to a fee).
  Can you make a stray transfer that gets counted? Can you strand the basket in an
  asset nobody can claim?
- **Hostile quote assets.** Quotes are treasury-approved via allowlist. Assume
  governance approves an asset that is *later* discovered to be fee-on-transfer,
  rebasing, pausable, blacklisting, or reentrant on transfer. What does each do to
  rotation, fee routing, dividends, and perp collateral? Can an approved-then-turned-
  hostile token brick `relaunch()` permanently?
- **`arbStep` between the protocol's own pools.** The protocol now trades against
  itself to capture spread. Can you set up the spread it captures, and be the
  counterparty on the other side?
- **`QuoteRotator`.** Rotation is modelled as a flow in atomic slices. Sandwich a
  slice. Interleave a swap between slices. Can partial rotation leave the system in
  a state where reserve accounting, death detection, or perp marks read a pool that
  no longer backs anything?

**The perp engine — sharpest edge in the codebase.** Liquidation fires from inside
`afterSwap`. That means the swap that moves the price and the liquidation that reads
it are in the same transaction, under your control. `PerpEngine._key()` builds from
`generationQuote[gen]`, so perps trade the *primary* pool, not necessarily the
deepest — and `activeEthDepth()` bounds position size against the pool the engine
*thinks* it is trading. With multiple pools per generation those diverge. Build the
divergence and exploit it. Also: self-liquidation, liquidation ordering across a
batch, gas-griefing `liquidateManyInSwap` / `sweepLiquidations`, bad-debt
socialization, funding-rate manipulation, and pass-3's carried **Z-11** (queued PLV
exits senior to live shares — the owner called it deliberate design; prove whether
it is bank-runnable in the multi-quote world).

**V4 hook mechanics.** `BaseHook` is *vendored* (`vendor/BaseHook.sol`) — diff it
against upstream v4-core and look for drift. Then: `BeforeSwapDelta` sign
conventions, settle/take accounting, `CurrencyNotSettled`, reentrancy through
`PoolManager`'s unlock callback, and the hook permission bits encoded in the mined
CREATE2 address. Can a third party initialize a pool against this hook that the
protocol never intended, and pollute generation state, volume accounting, or the
fee basket through it?

**Lifecycle and governance.** Front-run `summon()`. Snipe the seed (`LaunchSniper.sol`
— determine whether it defends or is itself the attack surface). Grief `relaunch()`
past a gas ceiling (Z-07 was fixed once — try again with multi-pool state, which is
strictly larger). Now that proposals *compete* instead of queueing (`87922e2`), can
you spam competing proposals to starve a legitimate one, or win a rotation vote by
timing? Re-test **Z-03** (governor spam relaunch DoS) and **Z-06** (governance
lockout) against the new competition model — the change that fixed a veto may have
opened a race.

**Cross-layer.** The frontend trusts the indexer completely
(`src/lib/cauldronIndexer.ts`, 29 hooks in `src/hooks/`). If you controlled or
merely stalled the indexer, what would the UI show, and could a user be induced to
sign something harmful? `api/fren-ask.ts` and `api/fren-teach.ts` are LLM-backed —
prompt injection and cost amplification. `api/x-token.ts` handles OAuth. And check
whether `.env.local` / `.env.vercel-backup` at the repo root contain live secrets and
whether they are actually gitignored.

## Rules of engagement

1. **PoC or it did not happen.** Every claimed exploit needs a Foundry test in
   `contracts/solidity/test/attacks/` using the pass-4 prefix `Q0x_`, following the
   established convention: an **invariant test the protocol should hold** (which
   FAILS on current code at the moment of discovery) plus a **positive PoC** (which
   PASSES, demonstrating the attack works). State the profit in wei or the exact
   state corruption achieved.
2. **Quantify.** Attacker cost in, value out, capital required, and whether it is
   atomic or needs multiple blocks. An exploit that costs more than it yields is a
   griefing vector — say so and price the grief.
3. **No hand-waving.** "Could theoretically" is not a finding. If you cannot build
   it, log it as a **lead** with the exact next step, in the lead ledger.
4. **Refutations count.** If you attack something hard and it holds, that is a
   result — record it as proven-safe with the PoC that failed to break it. Pass 3's
   Y-02b refutation is the model.
5. **Do not fix as you go** unless the fix is needed to reach a deeper bug. This is a
   discovery engagement; recommend fixes in the report. If you do patch something,
   say so explicitly and keep the failing test as a regression.
6. **Report Criticals immediately**, mid-engagement. Do not save a drainable vault
   for the write-up.

## Deliverable

`contracts/solidity/test/attacks/EXPLOIT_REPORT_PASS4.md`, matching the structure of
passes 1–3 so the series stays readable:

1. **Scope, method, harness, and the exact command to reproduce.**
2. **Lead ledger** — every item driven to a verdict: CONFIRMED / REFUTED / CARRIED,
   with severity and PoC path. Include every carried item from pass 3 (Z-11, Z-13,
   Z-14, Z-16, Z-18, Z-20, Z-21, Z-22, Y-01, Y-02a) plus everything new.
3. **Per-finding write-ups** — target invariant, mechanism, PoC, profit, fix.
4. **Proven-safe** — what you attacked that held, and how hard you hit it.
5. **Residual risk** — what you could not reach, and what it would take. Name your
   blind spots; an exploit report that hides them is marketing.

Final line of the report: **would you put your own money in this contract today?**
Answer it honestly.
