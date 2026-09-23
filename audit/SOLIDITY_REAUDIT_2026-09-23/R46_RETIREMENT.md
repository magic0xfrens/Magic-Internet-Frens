# Retiring r46 liquidity on Sepolia (2026-09-23, owner-authorized)

The owner asked to remove the old deployment's liquidity before the r47 redeploy.
Executed through r46's own governance path with the deployer key (timelock
proposer/executor). Every timelock action was dry-run as an eth_call from the
timelock first. RPC: https://sepolia.gateway.tenderly.co (chain 11155111).

| Step | Transaction | Result |
|---|---|---|
| timelock.schedule(registry.armEmergency) | 0x63478045ef446a36dff186cc4f0853a6396a70b1ca1b8af584d2815b7184b25f | ok |
| first execute attempt | — | not sent: gas estimation reported the op not ready (chain clock) |
| timelock.schedule(registry.emergencyWithdrawLP(1)) | 0x9f22d8a0bae21988d54f2d355a55013bba3a7ec23a05b095087365fd23bab021 | ok |
| timelock.execute(armEmergency) | 0x76f66208dab0df88ef78554b67c584cc8588911c8adbb1f3a3f0eca390ae1a4a | emergencyReadyAt 1790193384 (300 s) |
| timelock.execute(emergencyWithdrawLP(1)) | 0x591708e27bb053c083d3ee71be0a4a801f884b75c192c2e8e262997d1e40077e | positions 39762/39763 -> 0 liquidity; 2.222 ETH + 777M gen-1 tokens to timelock |
| timelock.scheduleBatch(setVaultLimits(8000,0), skimInsurance(0.06 ETH, deployer), forward 2.222 ETH) | 0xf33661b3fb324683f8eb923073ad43088b4704e00417e27b75557b1689e5700c | ok |
| timelock.executeBatch | 0xefe99b7a11faf9f12d497c6f8014cbd639e85ac0ea29927c09935646409b4110 | deployer 7.0922 -> 9.3741 ETH (+2.2819 net of gas) |

State after: r46 registry `0xc56f1eb7bf758ef879ccfc5a9f0bea899ba34393` has no LP;
engine insurance 0 with floor 0 (utilization cap unchanged at 8000 bps); timelock
holds 0 ETH and the dead gen-1 tokens (worthless, left in place). r46 had no open
perp positions, no rotated legs and no seeder campaign. OG redemption and trading
on r46 are therefore over; the site must move to r47.

Not touched: the r46 presale/Genesis contract, dividend, governors, factory and
their state; the engine's ownership (still the r46 timelock).
