# Live-market stress test — Cauldron r45 on Sepolia (11155111)

Harness: `scripts/stress/stress-market.mjs`. Generated 2026-09-22T11:30:17.780Z.

## Summary

| phase | attempted | succeeded | reverted | revert reasons (grouped) |
|---|---:|---:|---:|---|
| liq | 7 | 7 | 0 | - |
| edge | 13 | 10 | 3 | `DustPosition` x1<br>`Transaction creation failed.` x1<br>`undecoded selector 0x90bfb865` x1 |

## Notes

- router runtime 8814 bytes, playChurn selector present=true (r43/r44 shipped 8580 B with it MISSING)
- ethBackingMark(0.32) != engine.totalEth(0.324628170871935149) at "t0 / before anything" (delta -0.004628170871935149)
- ethBackingMark(0.32) != engine.totalEth(0.324628170871935149) at "pre-crash" (delta -0.004628170871935149)
- ethBackingMark(0.32) != engine.totalEth(0.324628170871935149) at "post-crash" (delta -0.004628170871935149)
- crash dump: openCount 8 -> 6, badgesOwed(funder) 0->0, liquidatorMinted 0->2, unabsorbedEth 0 -> 0
- post-liq funder: ethShareOf=300000000000000000000000 pendingEthOf=0
- post-liq w11 staying: ethShareOf=10000000000000000000000 pendingEthOf=0
- post-liq w12 queueing: ethShareOf=10000000000000000000000 pendingEthOf=0
- ethBackingMark(0.32) != engine.totalEth(0.324628170871935149) at "after price restore" (delta -0.004628170871935149)
- w12 withdrawEth(all): pendingEthOf=0 (queued remainder), vault pendingEth=0

## Snapshots

| point | activeEthDepth | plv | freeEth | totalEth | insurance | **unabsorbedEth** | openCount | vault.assetsEth | vault.ethBackingMark | vault.pendingEth |
|---|---|---|---|---|---|---|---|---|---|---|
| t0 / before anything | 2.64769000421136024 | 0.268768170871935149 | 0.268768170871935149 | 0.324628170871935149 | 0.06069 | **0** | 8 | 0.324628170871935149 | 0.32 | 0 |
| pre-crash | 2.64769000421136024 | 0.268768170871935149 | 0.268768170871935149 | 0.324628170871935149 | 0.06069 | **0** | 8 | 0.324628170871935149 | 0.32 | 0 |
| post-crash | 2.538471947783206802 | 0.268768170871935149 | 0.268768170871935149 | 0.324628170871935149 | 0.060816355031533112 | **0** | 6 | 0.324628170871935149 | 0.32 | 0 |
| after price restore | 2.988471947783206802 | 0.268768170871935149 | 0.268768170871935149 | 0.324628170871935149 | 0.060816355031533112 | **0** | 6 | 0.324628170871935149 | 0.32 | 0 |
| after edge | 2.988471947783206802 | 0.258623540532187176 | 0.258623540532187176 | 0.314483540532187176 | 0.060816355031533112 | **0** | 6 | 0.314483540532187176 | 0.314483540532187176 | 0 |
| final | 2.988471947783206802 | 0.258623540532187176 | 0.258623540532187176 | 0.314483540532187176 | 0.060816355031533112 | **0** | 6 | 0.314483540532187176 | 0.314483540532187176 | 0 |

## Every action

| phase | action | result | tx / reason | gas |
|---|---|---|---|---|
| liq | funder buys 0.55E of token (ammo) | ok | [0xba673d1953498dd9…](https://sepolia.etherscan.io/tx/0xba673d1953498dd94d988f2379b5128f5042e119dd50fcd7fdfceb396adf97f4) | 2834776 |
| liq | funder approve router | ok | [0xfa09c889d55d5978…](https://sepolia.etherscan.io/tx/0xfa09c889d55d5978cb5801884b369cbe63af9555c7b6dd53c5b99d7fd2a695f4) | 46017 |
| liq | DUMP all ammo in one swap (in-swap sweep) | ok | [0x4a0e8660a7220ed1…](https://sepolia.etherscan.io/tx/0x4a0e8660a7220ed163de870e528d61ec34b834388f217fa2d310f65eafcfb0c6) | 2527662 |
| liq | in-swap sweep liquidated positions | ok | `` |  |
| liq | liquidator badge accrued (badgesOwed or mint) | ok | `` |  |
| liq | liquidate a healthy id expect Healthy/NotOpen | ok | `NotOpen` |  |
| liq | buy back to restore price | ok | [0xee4c1281a26fa4a6…](https://sepolia.etherscan.io/tx/0xee4c1281a26fa4a65e8c1d216e5f036b70f5bdb7aebaee8c01366b7311c9ee7a) | 2458300 |
| edge | openLong 1x at EXACTLY minCollateral | REVERT | `DustPosition` |  |
| edge | openLong 1x at minCollateral-1 expect DustPosition | ok | `DustPosition` |  |
| edge | openLong 2x over maxNotionalBps expect BadLeverage | REVERT | `Transaction creation failed.` |  |
| edge | openLong 5x expect BadLeverage | ok | `BadLeverage` |  |
| edge | openLong amount != msg.value expect BadParam | ok | `BadParam` |  |
| edge | openLong with absurd minTokenOut expect Slippage | ok | `Slippage` |  |
| edge | close a position you do not own expect NotTrader/NotOpen | ok | `NotTrader` |  |
| edge | play(0,0,..) expect NothingSupplied | ok | `NothingSupplied` |  |
| edge | play with absurd minTokenOut expect Slippage | ok | `Slippage` |  |
| edge | swap with 300k gas expect LiqGasStarved | REVERT | `undecoded selector 0x90bfb865` |  |
| edge | w12 withdrawEth ALL (queue path if free < owed) | ok | [0x8dac5d9ec0bb99fc…](https://sepolia.etherscan.io/tx/0x8dac5d9ec0bb99fc9ce922f938f6e6780d4e28d711c8720725c84c99dbc6fa7e) | 76329 |
| edge | withdrawEth(0) expect ZeroShares | ok | `ZeroShares` |  |
| edge | withdrawEth(more than owned) expect InsufficientShares | ok | `InsufficientShares` |  |
