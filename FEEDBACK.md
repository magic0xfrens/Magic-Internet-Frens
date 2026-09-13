# Uniswap v4 — Developer Feedback

**Project:** Magic Internet Frens / The Magic Internet Cauldron
**Repo:** https://github.com/magic0xfrens/Magic-Internet-Frens
**What it is:** an autonomous token machine built as a single Uniswap v4 hook, where the
hook *is* the economic engine rather than a fee tweak on an otherwise normal pool.
**Track:** ETHGlobal — Continuity (ongoing protocol, not a from-scratch build)

Submitted alongside the Uniswap Developer Feedback Form as required.

---

## Contents

- [Two asks](#two-asks)
- [Where to verify the integration](#where-to-verify-the-integration)
- [What we actually built on v4](#what-we-actually-built-on-v4)
- [What worked well](#what-worked-well)
- [Friction, in order of what it cost us](#friction-in-order-of-what-it-cost-us)
- [Documentation requests, concretely](#documentation-requests-concretely)
- [Would we build on v4 again](#would-we-build-on-v4-again)

---

## Two asks

### 1. We have applied to the Uniswap Foundation Audit Subsidy programme

The application is in, and its full text is in this repo at
[`UNISWAP_AUDIT_GRANT_APPLICATION.txt`](UNISWAP_AUDIT_GRANT_APPLICATION.txt) so there is no
gap between what we told the Foundation and what a reviewer can read here.

Where we are on security today, so the request is judged on substance:

- **611 tests passing**, of which **96 are adversarial PoCs** in
  [`contracts/solidity/test/attacks/`](contracts/solidity/test/attacks). Each one is an
  attack that was landed against the protocol first, then fixed, then pinned as a
  regression test so it cannot come back.
- Multiple internal blind red-team passes, written up in
  [`audit/`](audit) — including the Criticals log and the remediation ledger.
- The findings that mattered most were **not** the ones a checklist finds. Examples, all
  fixed: a completed governance quote rotation permanently bricked `relaunch()`; a
  proposer-fee slice accrued in the pool's quote asset but paid out in native wei,
  draining the relaunch reserve's backing; and a publicly predictable next-generation
  `PoolKey` could be squatted for 33k gas to brick relaunch forever.

What we want from an audit is exactly the class of bug above — cross-subsystem state
machine failures behind a state-consuming flag — which is where we think an ambitious v4
hook is genuinely hard to get right and where we would most value outside eyes.

### 2. We would like the hook considered for Uniswap interface / router auto-routing

**We built it router-optional from day one**, before we had any reason to believe it would
be reviewed, because it seemed like the right way to build a hook. Concretely:

- `hookData` is **entirely optional**. The check is `hookData.length >= 32`
  ([`CauldronHook.sol:877`](contracts/solidity/CauldronHook.sol#L877)) — a presence test,
  not a requirement.
- A plain swap carrying **no** `hookData`, arriving from the Uniswap interface or any
  aggregator, does the full job: it pays the hook fee, records volume, mints NFTs, and can
  trigger a perp liquidation. The code paths are commented as such
  ([`:846`](contracts/solidity/CauldronHook.sol#L846),
  [`:959`](contracts/solidity/CauldronHook.sol#L959)).
- `POOL_FEE = 0` ([`CauldronBase.sol:157`](contracts/solidity/cauldron/CauldronBase.sol#L157))
  and the hook takes its fee through return deltas, so there is no custom-router-only
  discount path and no swap shape that behaves differently for a generic router.
- Pools the hook does not serve are untouched: there is an explicit adoption gate
  (`trackedPools`), and an unadopted pool returns `ZERO_DELTA` and no fee.

We are not asking for an exception or special treatment — we are asking for a **look**,
and we would happily act on whatever changes a review asks for. The hook is deliberately
designed to behave like an ordinary pool from a router's point of view, and it would be a
shame for that to go unused because nobody looked. If there is a formal queue or a
prerequisite checklist for this, we would like to be pointed at it.

---

## Where to verify the integration

Line numbers verified against the commit this file ships in.

| What | File and line |
| --- | --- |
| Hook permissions — **both** return-delta flags enabled | [`CauldronHook.sol:576-597`](contracts/solidity/CauldronHook.sol#L576-L597) |
| `POOL_FEE = 0` — no LP fee at all | [`cauldron/CauldronBase.sol:157`](contracts/solidity/cauldron/CauldronBase.sol#L157) |
| Fee taken on the **quote side**, currency-agnostic | [`CauldronHook.sol:1520`](contracts/solidity/CauldronHook.sol#L1520) |
| `poolManager.take` realises the accrued delta | [`CauldronHook.sol:1522`](contracts/solidity/CauldronHook.sol#L1522) |
| `afterSwap` returns the fee as a delta, not a transfer | [`CauldronHook.sol:1006`](contracts/solidity/CauldronHook.sol#L1006) |
| **Keeper-free liquidation swept inside `afterSwap`** | [`CauldronHook.sol:953`](contracts/solidity/CauldronHook.sol#L953) |
| NFT minted from volume, inside the swap, routerless | [`CauldronHook.sol:970`](contracts/solidity/CauldronHook.sol#L970) → [`:2436`](contracts/solidity/CauldronHook.sol#L2436) |
| Liquidation mints a badge with the kill engraved | [`cauldron/PerpEngine.sol:2116`](contracts/solidity/cauldron/PerpEngine.sol#L2116) |
| Router-optional paths (`hookData` absent) | [`:846`](contracts/solidity/CauldronHook.sol#L846), [`:877`](contracts/solidity/CauldronHook.sol#L877), [`:959`](contracts/solidity/CauldronHook.sol#L959) |
| Hook-initiated `poolManager.swap` inside our own `unlock` | [`cauldron/PerpSwapLib.sol:248`](contracts/solidity/cauldron/PerpSwapLib.sol#L248) |
| Native-currency `sync` → `settle` → `take` | [`cauldron/PerpSwapLib.sol:278-287`](contracts/solidity/cauldron/PerpSwapLib.sol#L278-L287) |
| Cumulative-tick TWAP ring built from the pool's own ticks | [`cauldron/PerpEngine.sol:268-290`](contracts/solidity/cauldron/PerpEngine.sol#L268-L290) |
| Multi-range book placed via `modifyLiquidity` on the singleton | [`cauldron/PoolOps.sol:543`](contracts/solidity/cauldron/PoolOps.sol#L543) |
| One LP recovered and re-seeded into a new `PoolKey` | [`CauldronRegistry.sol:858`](contracts/solidity/CauldronRegistry.sol#L858) |
| EIP-1153 transient flags for self-trading reentrancy | [`CauldronHook.sol:339-344`](contracts/solidity/CauldronHook.sol#L339-L344) |
| **We deployed v4 core to a chain that lacked it** | [`deploy/DeployV4Core.s.sol:71-83`](contracts/solidity/deploy/DeployV4Core.s.sol#L71-L83) |

---

## What we actually built on v4

Short version, because the README covers it properly.

There is no LP fee. `POOL_FEE = 0`, and 100% of revenue is a **quote-denominated hook fee**
taken through `beforeSwapReturnDelta` / `afterSwapReturnDelta`, on **both legs** of every
trade, always on the quote side. An LP fee structurally cannot do this, because LP fees
accrue in the *input* currency — so your revenue splits across both assets by trade
direction and you never get to choose. Return deltas let us choose. And because the quote
asset is a governance-rotatable parameter, the protocol's revenue denomination is a live
governance decision rather than a deploy-time constant.

Inside that same swap lifecycle:

- **Perpetual futures that are hook-native.** Positions open, close and liquidate as real
  `poolManager.swap` calls with real price impact and no synthetic book. The mark comes
  from a cumulative-tick TWAP ring we maintain from the pool's own ticks, because v4 ships
  no oracle. **Liquidations are swept from `afterSwap`**, so any swap on any interface
  closes underwater positions and earns the bounty — no keeper network, no external oracle.
- **NFTs minted by on-chain activity.** Trading volume forges them inside `afterSwap`, gas
  bounded via an isolated self-call so it can never revert or OOG the trade it rides on.
  Liquidating a perp mints the liquidator a trophy badge with the kill engraved on-chain:
  victim, side, leverage, collateral, your bounty, their entry, and the exact mark that
  killed them.
- **A liquidity book that outlives its tokens.** The hook keeps a 24-hour volume ring in
  `afterSwap`, so when a token's volume dies anyone can permissionlessly relaunch against
  data the pool produced itself — no keeper, no indexer, no trusted reporter. Liquidity is
  recovered and re-seeded into a new `PoolKey` built with the **same hook address**, with
  an adoption gate letting one hook serve an unbounded sequence of pools. Holder
  entitlements and redemption floors persist in the hook while the pool rotates underneath.

None of the above is portable to v2 or v3. That is the point.

---

## What worked well

**The hook interface is genuinely well designed, and we want to say so before the
complaints.**

- **Permissions encoded in the address** is elegant, and `HookMiner` made CREATE2 mining a
  non-event. We expected this to be the annoying part of the build and it wasn't.
- **Return deltas are the single best thing about v4 for us.** Being able to express "the
  protocol takes a slice of this swap" as *accounting* rather than as a transfer removed a
  whole class of reentrancy concern, and it is what makes a currency-chosen fee model
  possible at all. Nothing else in the DEX landscape lets you do this.
- **The singleton plus flash accounting** made our liquidity lifecycle tractable. Placing a
  multi-range book, tearing it down at relaunch, and settling it all as deltas inside one
  `unlock` is dramatically less code than the equivalent NFT-position juggling.
- **`take` is currency-agnostic**, which is why rotating the pool's quote asset required
  generalising only the *choice of side* and not the fee mechanism itself. That was a
  pleasant surprise.
- Local iteration with Foundry against v4 was fast, and the fork-test story is good.

---

## Friction, in order of what it cost us

### 1. EIP-170 is the real constraint on an ambitious hook, and it is undocumented

This cost us more time than everything else combined.

A hook with actual product logic hits the 24,576-byte ceiling early, and there is no
canonical guidance on what to do next. We ended up with **five external libraries plus a
delegatecall facet**, and our registry now sits at **24,492 / 24,576 bytes — 84 bytes of
headroom.** At that point every new feature becomes a size negotiation rather than a design
decision, and several of our design choices exist purely to save bytes. Two concrete
examples, both documented in the code:

- A proposer-fee slice is *skipped* on a non-native fee asset rather than tracked in a
  second per-asset mapping, because there was no room for the mapping.
- A liquidity-weighted mark lives in the perp engine rather than the hook, because the hook
  had tens of bytes left and the engine could absorb it.

**What would help:** a patterns page for "my hook exceeded 24KB". Library extraction vs.
delegatecall facets, what each costs in gas and in call-graph legibility, and the gotchas
(a facet behind a registry with no fallback needs explicit forwarder stubs — we learned
that the hard way). This is a predictable wall for anyone building something real, and
right now everyone hits it alone.

### 2. Hooks that trade on their own pool need a documented reentrancy story

Our hook initiates swaps on the pool it hooks — fee routing, a buyback, and the perp
engine's fills. Every one of those re-enters `beforeSwap` / `afterSwap`.

We solved it with EIP-1153 transient flags
([`CauldronHook.sol:339-344`](contracts/solidity/CauldronHook.sol#L339-L344)) and it works
cleanly, but we arrived there by reasoning from first principles rather than by reading
anything. The caveat that bit us and is worth stating explicitly in the docs: **transient
storage persists for the whole transaction, not for the `unlock`.** A flag you set inside
one unlock is still set in the next one in the same transaction, which is a live footgun
for exactly this pattern.

**What would help:** one worked example of a self-trading hook, with the reentrancy guard
and that caveat called out.

### 3. `BalanceDelta` sign conventions in nested flows

Everything else in this codebase we could unit-test into confidence quickly. Delta signs
across a nested `unlock` → `swap` → `settle` chain are where our bugs actually lived. The
one that took longest: a buyback settled the *intended* amount rather than the **realised**
debit read from the returned delta, so a binding price limit left a positive un-taken delta
and reverted the user's swap. That is a subtle, production-only failure.

**What would help:** more worked examples with the signs spelled out for each step,
especially for a hook that is itself the swapper. Prose about sign conventions is much less
useful here than three annotated examples.

### 4. v4's chain prerequisites are not stated in deployable terms

We ported this stack to Arc testnet, which **did not have Uniswap v4 deployed**. So we
deployed it ourselves ([`DeployV4Core.s.sol`](contracts/solidity/deploy/DeployV4Core.s.sol)),
and it worked on the first try — which is a real compliment to v4's deployability.

But before committing to the port we had to answer "can v4 even run here?" ourselves, by
sending a raw `eth_call` executing `TSTORE`/`TLOAD` and checking the return value. v4
settles every `unlock` through transient storage, so **EIP-1153 is a hard requirement**,
and a CREATE2 factory is a second one because hook permissions live in a mined address.

**What would help:** one line in the deployment docs — "v4 requires EIP-1153 and a CREATE2
factory" — plus a note on `PositionManager`'s constructor arguments that are safely zero
(`tokenDescriptor` and `weth9` both are, if you settle native directly). That is maybe
three sentences and it would save every new-chain integrator the same afternoon.

### 5. Smaller things

- `PositionManager`'s `unsubscribeGasLimit` has no documented sane default for a deployer
  who doesn't use subscriptions. We used v4-periphery's own test value.
- The docs assume the canonical deployment exists. A short "deploying v4 yourself" page
  would be useful now that more chains are launching without it.
- It is not obvious from the docs whether a hook returning a non-zero `afterSwap` delta
  interacts correctly with a *binding* `sqrtPriceLimitX96`. We established it empirically.

---

## Documentation requests, concretely

In priority order, all of them small:

1. **"My hook exceeded 24KB"** — library extraction vs. facets, costs and gotchas.
2. **A self-trading hook example** — reentrancy guard, and the transient-storage-is-per-
   transaction caveat.
3. **Annotated `BalanceDelta` sign examples** for nested `unlock` → `swap` → `settle`.
4. **Chain prerequisites for v4** — EIP-1153 and CREATE2, stated once, somewhere findable.
5. **"Deploying v4 core yourself"** — including which `PositionManager` constructor args
   are safely zero.

---

## Would we build on v4 again

Yes, without hesitation, and we would not build this protocol any other way — it does not
exist without hooks. The things we are complaining about are all *documentation* gaps
around genuinely good primitives, not flaws in the primitives. Return deltas and the
singleton changed what we were able to design, and the fact that we could stand v4 up on a
chain that had never seen it, and run an unmodified hook on top, says a lot about the
quality of the implementation.

Happy to talk to anyone at the Foundation about any of the above, and happy to be told we
got something wrong — several of the items here are things we worked out ourselves and
would genuinely like to hear the intended answer to.
