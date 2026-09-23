# Mint curve and surtax source traversal

Current and frozen hashes match:
- MintCurvePolicy: cb6ee6ed84e4b6ee84d5872fdce4070166b51987df2f319a9e87fbcabe69114c
- SurtaxLib: 5014805332f9428af786b95b0cf046101b4de550d4d82bd133d9f0ee7b540479

## MintCurvePolicy — all three bodies read

Constructor rejects zero base/knee/supply/spread; imposes no upper limits.
priceAt ignores supplied hook calibration, computes base + spread*k*k/(k+knee).
Arithmetic is checked, not universally overflow-free; supported deployment
parameter bounds and governance supply matching remain caller obligations.
Integer rounding means positive spread alone does NOT establish strict increase
for every accepted calibration (e.g. base=1, spread=1, knee=100 at k=0 and k=1).
totalToMintOut loops supply; unbounded deployment input can exceed practical
view-call gas budgets. This is not on the swap path.

The documented floor guarantee assumes proportional, consistently valued flow
from minting volume. It is not a proof across arbitrary prior royalty donations,
token-price changes, gacha multipliers or existing reserve balances. Inspect
production calibrations and actual mint economics before assigning impact.
Hook nftPriceAt uses typed try/catch; malformed return decoding is a candidate
fallback gap analogous to confirmed fee-router issue, not reproduced here yet.

## SurtaxLib — both bodies read

surtaxBps tries configured policy, caps successful uint at hardCap, catches
ordinary revert then uses default curve. Empty/short successful response may
escape typed catch; test required. Default branch itself does not clamp to
hardCap: production correctness relies on configured maxBps bounds.
defaultSurtaxBps handles disabled/unknown/expired windows, computes decayed
maximum plus bounded per-block jitter, clamps to configured max. Future start,
block zero, extreme multiplication or maxBps+1 can panic on arbitrary library
inputs; distinguish these from reachable initialized pool/config inputs.
Block-selected entropy does not prevent callers conditioning transactions on
the publicly readable fee. It does prevent changing the draw with an intra-block
spot-price probe. Multi-block selection and proposer influence are not ruled out.

No production changes, no new severity assigned, no completed test claim for
these two files. Existing candidate suites: F13_MintCurve, B03_SurtaxJitterDeadCode,
X8b_SurtaxJitterBlockShoppable, X1b_SurtaxJitterSteerable. Review their fixtures
before interpreting passes. Runtime job 92250 belongs to fee-router compilation,
not validation of these modules.

Prepared R23_PolicyBoundaries.t.sol (not yet executed): direct SurtaxLib calls
for ordinary revert fallback, empty successful response, valid hard-cap result,
and 256-run default-curve bounds under supported inputs. Adds explicit tiny-
calibration plateau characterization on actual MintCurvePolicy. No production
changes or severity assignment based solely on these unexecuted tests. The next
batch should include this file and R23_FeeRouterAcceptance after active build
92250 terminates; avoid competing Foundry cache writers/full recompiles.

## Final disposition (2026-09-23)

Final: SurtaxLib fixed (FS-surtax-01); curve fallback gap = FS-hook-L01 Low. Signed off.
