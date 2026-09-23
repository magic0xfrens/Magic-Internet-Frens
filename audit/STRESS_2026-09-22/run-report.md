# Live-market stress test — Cauldron r45 on Sepolia (11155111)

Harness: `scripts/stress/stress-market.mjs`. Generated 2026-09-22T11:48:15.477Z.

## Summary

| phase | attempted | succeeded | reverted | revert reasons (grouped) |
|---|---:|---:|---:|---|

## Notes

- router runtime 8814 bytes, playChurn selector present=true (r43/r44 shipped 8580 B with it MISSING)
- ethBackingMark(0.304338910192439203) != engine.totalEth(0.304349663590670634) at "t0 / before anything" (delta -0.000010753398231431)
- ethBackingMark(0.304338910192439203) != engine.totalEth(0.304349663590670634) at "final" (delta -0.000010753398231431)

## Snapshots

| point | activeEthDepth | plv | freeEth | totalEth | insurance | **unabsorbedEth** | openCount | vault.assetsEth | vault.ethBackingMark | vault.pendingEth |
|---|---|---|---|---|---|---|---|---|---|---|
| t0 / before anything | 2.848281784407891051 | 0.304349663590670634 | 0.304349663590670634 | 0.304349663590670634 | 0.060816355031533112 | **0** | 0 | 0.304349663590670634 | 0.304338910192439203 | 0 |
| final | 2.848281784407891051 | 0.304349663590670634 | 0.304349663590670634 | 0.304349663590670634 | 0.060816355031533112 | **0** | 0 | 0.304349663590670634 | 0.304338910192439203 | 0 |

## Every action

| phase | action | result | tx / reason | gas |
|---|---|---|---|---|
