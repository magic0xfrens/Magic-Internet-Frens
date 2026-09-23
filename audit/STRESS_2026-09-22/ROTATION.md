# Quote rotation round trip — live Sepolia, 2026-09-22

Executed against round 45 (`cauldron_r45b`), chain 11155111, funder `0xc944…c133`.
Action log: `audit/STRESS_2026-09-22/rotation-actions.jsonl` (append-only, 16 lines).

## Answers to the four lead questions

**Did the round trip complete? No.** It stopped inside Stage 2, after exactly one
rotation slice. `generationQuote(1)` never flipped and is `0x0` (native ETH) now,
as it was at Stage 0. Stages 3, 4 and 5 were never reachable.

**Did anything strand at either flip? No flip occurred**, so the denomination-change
strand tests are untested, not passed. Nothing stranded at the one slice that did
run: registry holds 3,444 wei dust and 0 USDG; the rotator holds 0 of both. The
rotated value is in a live recorded leg (position `39747`, 569.12 USDG).

**Did `unabsorbedEth` move? No. It read `0` at every single measurement** —
baseline, after 3 opens, after the slice, after every close, and at the end.

**Stage 3 decimals table: not produced.** The generation never became USDG-denominated,
so `minCollateral` under a 6-decimal quote, the ERC20 `openLong` shape, the
`NativeQuoteTakesValue` / `ErcQuoteTakesNoValue` flip and `depositEth`/`withdrawEth`
redenomination were all unreachable. Reporting them untested rather than guessing.

## What actually happened

| Stage | Result |
|---|---|
| 0 baseline | `genQuote=0x0`, `plv` 2.54e13 (drained), `openCount` 0, `unabsorbed` 0, depth 2.4366 ETH |
| 1 perps on ETH | `depositEth` 0.4 ETH → `plv` 4.0e17. 3× 2x longs opened (ids 59/60/61). Funding accrued (pos59 +2.146e11 wei over the run). Closed 61. **PASS** |
| 2 governance | `propose(USDG,20000)` → `vote(1,true)` → 120 s → `execute(1)`. Envelope live: `USDG / 20000 bps`. **PASS** |
| 2 rotation | Slice 1 of 1000 bps executed. **Every subsequent slice, at every size from 2500 down to 10 bps, reverts `SlippageTooHigh()`.** Rotation dead. **FAIL** |
| 3–5 | Unreachable. Protocol left on ETH, book empty, `unabsorbed` 0. |

Key transactions: deposit `0x1b892057…`, opens `0x23b7041a…` `0xf3b1d409…` `0xdcc25dd6…`,
propose `0xbb50bff5…`, vote `0x02c3c478…`, execute `0x66a472f6…`, **slice `0xffc3fc5e…`**,
closes `0x24981ae3…` `0xa896670c…` `0x09b5c609…`.

## Findings

### R-1 (HIGH, new) — the `linkVolume` "book is provably empty" safety argument is false

`RedemptionExt.sol` justifies calling `syncGeneration()` inline at the denomination flip
with: *"reaching this line required `linkVolume` to succeed earlier in this same call,
and that reverts `PerpsOpen()` unless `openCount == 0`. So the book is provably empty
right now."* That is not what the guard does:

```solidity
// PerpEngine.sol:887
function blocksVolumeLink() external view returns (bool) {
    if (openCount == 0 || markSource != address(0)) return false;
    (, bool ok) = twapTick();
    return !ok;
}
```

It blocks only when `openCount != 0` **and** no `markSource` is armed **and** the TWAP is
broken. With a healthy TWAP — the normal case — it never blocks, whatever the open
interest. **Executed proof:** slice `0xffc3fc5e…` ran to completion with `openCount == 2`;
`linkVolume` is called unconditionally on that path and did not revert.

Consequence at a real flip: `syncGeneration()` reverts `PositionsOpen()` (PerpEngine.sol:1540),
the flip's `try/catch` swallows it, and the engine keeps `quote` pointed at the pool the
rotation just drained. By the same comment's own reasoning, once `openCount != 0` no
reachable call can correct it until every position voluntarily closes — marking, funding
and in-swap liquidation all running off the thin residual pool. This is precisely the
Critical the comment claims is closed, and it is the exact case the brief asked about
(a position held across a denomination change). It stayed latent here only because the
flip never happened.

### R-2 (HIGH) — one slice self-poisons the venue and kills the whole envelope

The only allowlisted ETH/USDG venue (fee 3000, tickSpacing 60, no hook) is far too thin
for this treasury. Measured, before any slice: 2500 bps reverted `SlippageTooHigh()`,
1000 bps filled. **After** the single 1000-bps slice moved 0.2474 ETH through it, *every*
size — 2500, 2000, 1500, 1000, 500, 400, 250, 100, 50, 25, **10 bps** — reverts
`SlippageTooHigh()`. A 10-bps slice is ~0.0002 ETH, so this is not price impact: the
venue's spot is now parked below the oracle floor and stays there. The rotation's own
price impact is what disables the rotation.

### R-3 (HIGH) — `stalled()` misses the realistic wedge, and governance is now stuck

`stalled()` requires `movedBps == 0 && movedPrimaryBps == 0` (TreasuryGovernor.sol:926).
It is written to stop an unexecutable mandate wedging governance, but it only covers the
*zero-progress* case. An envelope that moves one slice and *then* becomes unexecutable —
which is exactly what R-2 produces, and R-2's cause is the slice itself — is not
"stalled" and blocks everything. **Executed proof:** `propose()` now reverts
`ProposalActive()` (`0xefb28d8c`). No new treasury proposal can be filed until the
envelope expires: `ENVELOPE_LIFETIME` is 7200 s here, but the mainnet default is 30 days.
The only earlier exit is the guardian (`0x326abb80…`, the timelock).

### R-4 (HIGH, deployment) — the executed slice lost 16.3% of the treasury value it moved

`rotationSlipBps` is set to **2000** on this deployment (the contract default is 300, and
2000 is the owner-settable maximum). Measured on slice `0xffc3fc5e…`, oracle ETH = $2747.77,
USDG = $1.00:

| | value |
|---|---|
| removed from ETH pair | 0.24740642 ETH = $679.82 |
| oracle-fair USDG | 679.815948 |
| 80% floor | 543.852758 |
| **actually received** | **569.116929** |
| fill vs fair | **83.72%** |
| value destroyed | **110.70 USDG** |

The fill cleared the floor by 4.6% and no more. A 20% band means a rotation is *permitted*
to burn a fifth of everything it moves, and on a thin venue it will use most of that band
every time. At 20 slices this compounds into a large, fully-authorised loss.

### R-5 (MEDIUM, config drift) — `round.json` names a USDG the registry rejects

`indexer/deployments/round.json` lists USDG as `0xB9fcDa126b0CB5D1964B714EC7Cd37218Fc4Df78`;
`allowedQuote()` for it is **false**. The allowlisted USDG is `0xD55ef581Dc794987FAA346843B06673Ab0bdCBFf`.
Both are 6-decimal and both answer `symbol() == "USDG"`, so the wrong one looks right.
`round.json` is the canonical manifest for both frontend and indexer, so the UI would
offer a quote asset whose `propose()` reverts `QuoteNotAllowed()`.

### R-6 (LOW, ops) — `close()` under-estimates gas and reverts

`close(60,0)` mined with status `0x0` (tx `0xb3f1a7cc…`) using cast's estimate. The same
call simulated clean, and succeeded with `--gas-limit 3000000` (tx `0x09b5c609…`).
`_settle`'s gas-reserved sweep makes the estimate unreliable; a wallet default can fail a
user's close. Not a protocol defect, but it will generate support traffic.

### Refuted — not to re-raise

Rotation is **not** blocked by open perp positions. Slices simulated and executed fine
with `openCount == 2`. The `PerpsOpen()` path is far narrower than the comments imply
(see R-1) — that is a *hazard*, not a liveness problem.

## State left behind

`generationQuote(1) == 0x0` (ETH), `openCount == 0`, `unabsorbedEth == 0`,
`insuranceEth` 6.2533e16, `activeEthDepth` 2.2077 ETH (down from 2.4366 — the 10% slice),
`isDead == false`. PLV left funded at 3.919e17 wei rather than restored to its drained
baseline, which is strictly healthier. The envelope stays active with `movedBps = 1000`
until it expires (~2 h from `0x66a472f6…`), after which `propose` works again; no action
needed. 10% of the treasury now sits in a USDG leg (position `39747`, 569.12 USDG) while
the generation is still ETH-denominated — a legitimate mid-rotation split, recorded and
recoverable, but it will not be rotatable further until the venue is fixed.

## To make this testable again

The venue is the blocker, and it is a deployment problem, not a code one: seed real depth
into the ETH/USDG pool (USDG is mintable by the deployer) or allowlist a deeper one via
`QuoteRotator.setVenue`. `swapOnce` is `onlyRegistry`, so the rotator cannot be used to
rebalance its own venue. With that fixed, re-run from Stage 2 with `maxTotalBps = 10000`
(the flip needs `movedPrimaryBps >= maxTotalBps` and `maxTotalBps >= 10000`, so 10000 is
the cheapest completable mandate — 4 slices of 2500, not the 20 that 20000 demands),
and hold a perp open across the flip to land R-1 as an executed Critical.
