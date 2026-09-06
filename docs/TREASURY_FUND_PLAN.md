# MiFrens as fund manager — multi-pool treasury, arbitrage capture, governance

## Where the current design is wrong

I fixed cross-quote volume with a **governance-set scalar** (ETH-equivalent wei
per raw unit of each quote). For measuring *liveness* that is defensible. As an
answer to "how do two pools of the same token relate", it is a fudge, and the
critique landed:

- **It goes stale.** A scalar set when ETH was $3,000 is 2× wrong when ETH is
  $6,000. Nothing corrects it but a governance transaction.
- **It ignores the real event.** Two pools holding the same token *will* diverge
  in price. That divergence is not noise to be smoothed over — it is value, and
  today it leaves the protocol.

## The thing that actually matters: we are the counterparty

The protocol owns liquidity in **both** pools. When GNOME/ETH and GNOME/USDG
drift apart, an outside arbitrageur buys cheap from one of our pools and sells
dear into the other. The spread is paid by our own LP positions. This is
loss-versus-rebalancing, and today 100% of it is extracted by third parties.

Capturing it is not an optimisation. It is stopping a leak that scales with
exactly the thing the guild wants to do — hold more assets.

**And it improves as the treasury diversifies.** Seven pools of differing
volatility diverge more often than two, so a strategy the guild would choose for
exposure reasons also produces more arb flow. The fund-management story and the
revenue story are the same story.

## Design

### 1. Arbitrage capture — `arbStep()`

Permissionless, keeper-rewarded, atomic inside one v4 `unlock`.

- Compare the token's implied price across two of the generation's pools, each
  converted to a common denominator via **Chainlink**.
- If the gap exceeds fees + a floor, buy the token in the cheap pool and sell it
  in the dear one **within a single unlock**, settling only the net delta.
- v4's flash accounting means this needs **no capital**: the two legs net out and
  we take the surplus. If there is no surplus, the call reverts and nothing moved.
- Split the profit: the majority to the treasury, a sliver to whoever called it.
  The sliver is what makes it happen without us running a bot.

**Why Chainlink is acceptable here but not for death detection.** Blast radius.
A wrong oracle on an arb produces a bad trade bounded by `minOut` — recoverable,
capped, and it simply will not execute if the bound is not met. A wrong oracle on
death detection kills a generation, and relaunch is permissionless, so it is
irreversible. Same feed, completely different consequence of being wrong.

Robinhood Chain has Chainlink feeds for all 95 stock tokens, and the L2 sequencer
uptime feed must be checked alongside them — a stale price during a sequencer
outage is exactly when an arb bound would be wrong.

### 2. Volume — measure the TOKEN side, not the quote

> **Attempted, reverted, and worth knowing why.** The switch itself is three
> lines and works: a fork test proves a 6-decimal-quoted pool reports
> token-denominated volume (`1e22`) rather than quote units (`1e8`) — a 1e14
> discrepancy, confirmed by reverting the fix and watching the test fail.
>
> It broke an audit test, and the reason generalises: **`deathThreshold` is
> configured in ETH** — `1 ether` in the constructor, in `DeployLaunchpad`, and
> on the live deployment. Against token-denominated volume that threshold is
> roughly four orders of magnitude too small, so pools would stop reading as
> dead and relaunch would never fire.
>
> So the change is not three lines; it is three lines plus a re-denomination of
> the one number that decides whether a generation dies, across config and a
> live deployment. That is worth doing deliberately rather than at the end of a
> session. The code carries a comment at the site so the next person does not
> rediscover this the hard way.

Replace the scalar entirely. Every pool in a generation trades **the same token**,
so token-side volume is already in one unit — no conversion, no oracle, no drift.

For a liveness question ("is anyone trading this?") token units are also the more
honest measure: they count activity rather than the price of activity.

Crystal credit is the one caller that genuinely wants *value* rather than
activity, so it keeps a quote-side measure. Those are two different questions and
conflating them is what produced the bug.

### 3. Many pools, not one

`generationPoolId[gen]` is a single id today, with an unbounded
`_volumeSiblings` array beside it. To hold seven assets:

- Promote to `generationPools[gen]` as a first-class, **bounded** set. The
  sibling array is currently unbounded and `isDead` loops it — that is a gas
  ceiling waiting to be found in production.
- Every pool carries the same hook, so each charges fees, forges crystals and
  reports volume. Verified already for the two-pool case.
- Death aggregates across the set (already does, via siblings).

### 4. Governance operations

All three are the same primitives (`removePartial`, `swapOnce`, `openOrAddPair`)
in different order, so each is a proposal type on `TreasuryGovernor`:

| Operation | What it does |
| --- | --- |
| **Diversify** | Split N% of one pool into a new quote |
| **Consolidate** | Merge two pools into one (e.g. NVDA + SPCX → one) |
| **Rebalance** | Shift weight between existing pools |

Each is voted as an envelope — asset(s), max share, expiry — and executed
permissionlessly in slices within it.

### 5. Guardrails that must survive all of this

- **The allowlist stays deployer/timelock-only.** A vote picks among vetted
  assets; it can never introduce one. This is the guardrail that removes a
  category rather than limiting damage.
- **Bounded pool count per generation**, or death detection runs out of gas.
- **Floor in the primary quote**, so the treasury can always denominate itself.
- **Per-slice `minOut`**, so an announced rotation cannot be front-run into a bad
  fill — a pumped route produces *no* fill.
- **Sequencer + staleness checks** on every oracle read.
- **Arb profit floor**, so a keeper cannot spam dust arbs to farm the reward.

## Order of work

1. **Token-side volume** — removes the scalar and the drift. Small, and it
   corrects a live bug rather than adding surface.
2. **Bounded pool set** — prerequisite for more than two pools, and closes the
   unbounded-loop gas risk.
3. **`arbStep()`** — the revenue piece, and the reason multi-pool is worth doing.
4. **Governor proposal types** — diversify / consolidate / rebalance.
5. **Tests throughout.** `TreasuryGovernor` currently has none, and voting maths
   is the last thing that should ship on inspection alone.
