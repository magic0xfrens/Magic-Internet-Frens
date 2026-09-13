# V5 — genesis / seed / deploy — verification

Blind copy: /tmp/blind-final-v5/contracts/solidity. Ran:
`forge test --match-path 'test/attacks/K5*' -vv` with FORK_RPC/POOL_MANAGER/POSITION_MANAGER exported.
Result: `[PASS] test_K5b_ProgressiveSeedNeverStarts_AndPrimeFundingIsLocked() (gas: 5724875)`; logs
`seeder.seeding(): 0 / seeder.gen(): 0 / seeder.token(): 0x0 / seeder.ethTotal(): 0`.

## K5b — CRITICAL claimed → SPLIT: dead-code half REFUTED, fundPrime trap DOWNGRADED to MEDIUM

PoC hygiene (VERIFIED): the only `return;` is `test/attacks/K5b_ProgressiveSeederUnreachable.t.sol:53`, inside
`setUp()`, and the test body opens with `require(active, ...)` (:92), so a missing fork env fails rather than
skips. No `vm.skip`. The four `log_named_*` lines (:109-112) printed, which sit *between* the summon and the
final assertions, so the assertion block at :113-131 executed.

### Counter-argument 1 — deliberate configuration? YES. Dead BY DESIGN.
`cauldron/PoolOps.sol:157-167`:
> "Laying the WHOLE of ledger A as a two-sided full-range base removes the failure at its source ...
>  Anti-snipe does not depend on this: the surtax and {LaunchSniper} are the real defences, and both are
>  untouched. Lower this below 1e18 to bring the streamed launch back — the machinery is intact — but
>  anything that hosts perps wants it at 1e18."
`cauldron/PoolOps.sol:168` `uint256 internal constant SEED_BASE_WAD = 1e18;`
`cauldron/PoolOps.sol:402-405`:
> "NOTHING LEFT TO STREAM once the base is the whole of ledger A. `startSeed` with a zero budget would revert
>  `BadConfig` and take the summon down with it, so the campaign is simply not started — which is also the
>  honest state: an atomic launch has no seeding campaign."
> `if (activeTokens <= baseTok || ethAmount <= baseEth) return r;`
Readers of the constant: only `PoolOps.sol:395,396` (grep across all `*.sol`). `startSeed` call sites: only
`PoolOps.sol:410` + `cauldron/ISeeder.sol:30` (decl) + `test/CauldronSeeder.t.sol:81` (direct unit test).
No other arming path exists. `cauldron/LaunchSniper.sol` exists and is wired from `MiFrensGenesis.sol`/`PoolOps.sol`,
and `deploy/DeployLaunchpad.s.sol:390-393` ties `snipeWindowBlocks` to the seed window — so the anti-snipe
promise is carried by the surtax + LaunchSniper, not by the stream.
**Verdict: the seeder is dead BY DESIGN**, a documented one-constant knob. The "broken anti-snipe promise /
Critical brick" framing is REFUTED (DERIVED from the quoted comments + the exhaustive grep).

### Counter-argument 2 — is the fundPrime ETH trap real? YES.
Every native egress in `cauldron/CauldronSeeder.sol` (`grep -n "call{value|\.transfer\(|\.send\("`):
- `:632` inside `_teardown`, reached only via `withdrawAll` (`:806 onlyRegistry lock`). Both registry call sites
  are gated: `CauldronRegistry.sol:560` and `:1635` — `if (_seeder != address(0) && ISeeder(_seeder).seeding())`.
  `seeding` is set only by `startSeed`, which never runs. Gate is false forever.
- `:842` inside `rescue(address to)` (`:838 onlyRegistry lock`), reachable via `CauldronRegistry.sol:345
  rescueSeeder() external onlyEmergency timelocked nonReentrant`. It begins
  `uint256 bal = IERC20(token).balanceOf(address(this));` with `token == address(0)` pre-campaign → extcodesize
  check on an empty account → revert. PoC asserts this at :130 with delay=0 and emergencyAdmin=this.
- `:630`/`:687`/`:840` are ERC20 transfers, not native.
There is no owner sweep, no `receive`-side accounting escape. **1 ETH trapped, asserted at PoC :131 (VERIFIED).**

`fundPrime` callability, `cauldron/CauldronSeeder.sol:338-339`:
`if (msg.sender != deployer && msg.sender != IRegistryOwner(registry).owner()) revert OnlyRegistry();`
→ the seeder's deploying EOA (`:224 deployer = msg.sender`) or the registry owner. Not permissionless.
Its NatSpec at `:335-336` claims "{withdrawAll} returns any unspent remainder to the registry at relaunch, so
nothing here can be stranded" — that sentence is FALSE in the shipped atomic configuration.

Deployed path: `deploy/DeployLaunchpad.s.sol:398-402`
`uint256 primeEth = vm.envOr("PRIME_BUY_ETH", uint256(0)); if (primeEth > 0) { seeder.fundPrime{value: primeEth}(...) }`
→ **default 0, so the default deploy does NOT fund it**; but `deploy/DeployLaunchpad.s.sol:536-541` advertises
"Send 2-3Ξ", so an operator following the script's own guidance burns 2-3 ETH of protocol launch budget.

### Severity
Dead-by-design + opt-in funding + owner-only caller + no attacker ⇒ not Critical. It is a real, silent,
irreversible loss of the protocol's own funds contradicted by its own NatSpec.
**DOWNGRADED to MEDIUM.** Cheapest fix: make `rescue()` tolerate `token == address(0)`, which also fixes K5c.
One-line PoC falsifier that would have refuted the mechanism: change `SEED_BASE_WAD` to `9e17` — `startSeed`
then runs, `seeding()` is true, and both DEFECT-1 and DEFECT-3 assertions fail. I could not find a falsifier
that leaves the constant at 1e18, i.e. the mechanism holds exactly as stated.

## K5c — MEDIUM claimed → CONFIRMED (VERIFIED)
`cauldron/CauldronSeeder.sol:838-842` quoted above; `token` is unset pre-campaign so `IERC20(address(0)).balanceOf`
reverts. Exercised by `_tryRescue()` and asserted at PoC :130, which executed. This is the same defect as K5b
defect 3, not an independent loss — it is the *reason* K5b's trap has no exit.

## K5d — MEDIUM claimed → DOWNGRADED to INFORMATIONAL (DERIVED)
Unreachable while `SEED_BASE_WAD == 1e18` (`poke()` at `:302` no-ops; PoC :123-125 asserts `primeSpent()==0`,
`deployedWad()==0`). And the prime buy is not unprotected: `CauldronSeeder.sol:193 MAX_TICK_DEV = 1000`
(~10.5%), a per-block ratcheted reference `_syncRef` (`:471-477`, at most `MAX_TICK_DEV` ticks per block), a
hard swap tick limit `:392 int24 lim = _refTick - MAX_TICK_DEV;`, and a binding minOut
`:420-422 minOut = FullMath.mulDiv(owed, pxX96, 1<<96); minOut = minOut*(10_000-PRIME_SLIP_BPS)/10_000;
require(got >= minOut, "prime slippage");` with `:199 PRIME_SLIP_BPS = 1000` (10%). So ~18-20%/tranche is the
*documented worst-case bound of the design*, reachable only by holding a manipulated price for whole blocks
(`:166-169`), not an unbounded sandwich. Latent + bounded + priced-in ⇒ Informational.

## K5e — LOW claimed → CONFIRMED (DERIVED)
`cauldron/MiFrensGenesis.sol:268`: `if (balanceOf(msg.sender) + quantity > MAX_PER_WALLET) revert PerWalletCap();`
Balance-based, so transferring out between mints resets the cap. Standard, well-known LOW; no state corruption.

## K5f — LOW claimed → REFUTED (DERIVED)
`cauldron/MiFrensGenesis.sol:286-295`: "Deployer safety valve: cancel a stalled genesis so minters can be made
whole. ... Irreversible; stops minting and opens refunds." and `:612-621` documents the sold-out-and-cancelled
state as a deliberate, permanent refund-pot gate: "`cancelled` is irreversible by design, so this gate is
permanent: a cancelled round is refunded, never ignited." Minters are refunded via `refund()`; the deployer
gains nothing. This is a documented admin power, not a griefing surface.

## Spot-check — "vault donation entitlement" refutation: AGREE
`cauldron/CauldronVault.sol:71-78` states the reason; `:95 uint256 public accountedDeposits;` is bumped only on
the gated path at `:119`, and the death sweep at `:187-194` sizes `swept` from `acc`, not from
`address(this).balance`, emitting `UnaccountedSweep` (`:104`) for the donated excess. A stranger's donation
therefore cannot walk the dead collection's crystallised entitlement toward 1. The hunter's refutation stands.

## Discards
2 discards: K5b's Critical dead-code framing (refuted; dead by design) and K5f (refuted; documented admin power).
K5d downgraded to Informational. Net surviving: K5b-as-Medium (fundPrime trap), K5c Medium, K5e Low.
