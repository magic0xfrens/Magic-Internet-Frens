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

### 2. Volume in USD — `QuoteOracle` (BUILT)

Everything downstream of volume is denominated in ETH today: `deathThreshold`
(1 ether) and `volumePerNFT` (0.02 ether). With one quote that is fine. With two
it is incoherent — a fren's mint-out cost would depend on which pool you happened
to trade in, and death would sum figures 1e12 apart.

**USD is the common denominator that makes multi-pool actually work.** A fren
costs $X of volume wherever it was earned; a generation is dead below $Y/day
across all its pools.

`QuoteOracle` returns USD per RAW unit scaled 1e18, so a caller does
`usdVolume = rawVolume * factor / 1e18` with no decimals handling at the call
site — getting decimals wrong per call site is the bug it exists to remove.

It REFUSES to answer (returns 0) when: no feed, the answer is stale past its
heartbeat, the answer is non-positive, or the L2 sequencer is down or only just
back. Callers must read 0 as "cannot judge", never "no volume" — death is
irreversible, so the failure direction is toward ALIVE.

**This reverses my earlier position, and the earlier reasoning was wrong.** I
argued an oracle on death detection was a manipulation surface. That conflated
deriving a price from our own thin pools (manipulable) with a Chainlink feed
aggregated off-chain across venues (not manipulable by any flash loan). The
governance scalar's real property was never safety — it was staleness.

Still to do: re-denominate `deathThreshold` and `volumePerNFT` in USD and wire
the hook to the oracle. That is the same re-denomination flagged below, now with
a correct source for the conversion.

### 2b. Volume — token-side alternative (rejected in favour of USD)

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


---

## The fee basket — an unfinished path, found by asking the right question

"Where do fees go when a generation trades in several quotes?" turns out to be
the gap that blocks multi-quote in production. Verified in the code, not assumed:

- The fee is TAKEN in the quote — `poolManager.take(quoteIsCurrency0 ? c0 : c1, …)`
  is already currency-agnostic. So a USDG pool collects **USDG** fees. Correct.
- Every fee is then ROUTED with `.call{value:}` — the guild dividend, the floor
  vault, the perp stakers, the surtax. Five sites, all native ETH.
- `MiFrensDividend` accrues in `receive() external payable`. It can only ever
  hold ETH.

So a USDG-quoted generation would collect USDG and be unable to distribute it.
The fee take was generalised; the fee *distribution* was not.

### The floor is fine

The collection floor already becomes **token buy pressure** rather than banked
quote: the floor share routes to the buyback buffer and market-buys the
iteration token. That path is quote-agnostic in intent — it just needs
`legacyBuyStep` generalised, which is already flagged and deliberately gated to
ETH pools today.

### The dividend is the hard part

Three shapes, and the third is almost certainly right:

1. **Convert everything to ETH at collection.** Simple, keeps `MiFrensDividend`
   untouched — but it sells the basket at whatever price the moment produces,
   and burns gas on a swap per fee.
2. **A dividend per asset.** Honest, and it makes claiming N transactions and the
   UI N times harder. Also strands dust in assets nobody wants to claim.
3. **One accumulator, USD-denominated, paid in a chosen asset.** Track each
   holder's entitlement in USD via the same oracle the volume accounting uses,
   and let a claim be settled in whichever basket asset the treasury is longest.
   Tracking stays a single number per holder however many pools exist, and the
   composition question moves from accounting into settlement, where it belongs.

Option 3 also answers "how does this stay clean when pool composition changes and
different pools generate different volumes" — it does not track composition at
all. It tracks value, which is invariant to where the volume came from.

### Ordering

This is a prerequisite for a live non-ETH generation, not an enhancement. The
perp engine already refuses non-ETH generations for exactly the same reason —
its collateral and payouts are native — and the dividend needs the same honesty
until it is fixed.
