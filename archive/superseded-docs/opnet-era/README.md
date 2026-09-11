# OP_NET / Bitcoin-era design docs — SUPERSEDED

These eight documents describe an **entirely different protocol** from the one in
this repository. They are the OP_NET (Bitcoin L1) ancestor: an Abracadabra/MIM
fork — a BTC-collateralised algorithmic stablecoin (`$MIF`) with a governance
token (`$FREN`/`sFREN`), NFT-gated lending Cauldrons, LTV/liquidation mechanics,
and a MotoSwap-based Phoenix token.

None of it matches the shipped tree, which is an autonomous, infinitely-
relaunching token protocol on **Uniswap V4** (`contracts/solidity/CAULDRON.md`).
There is no stablecoin, no borrowing, no BTC collateral, no `sFREN` staking and
no MotoSwap anywhere in the contracts.

They were moved here during the 2026-09 functional audit because they were still
being cited as *intent sources* while contradicting the code on every point —
which makes a conformance audit check against fiction.

| File | Describes | Superseded by |
|------|-----------|---------------|
| `PROTOCOL_SPEC.md` | MIF stablecoin, BTC collateral, LTV 75%, `cook()` | `CAULDRON.md`, `LAUNCH_LADDER_DESIGN.md` |
| `TOKENOMICS.md` | 1B `$FREN` supply, `sFREN` staking, TCR seigniorage | `CauldronToken.sol` (fixed supply, no owner) |
| `FLYWHEEL_ECONOMICS.md` | BTC → MIF → sFREN yield flywheel | `TREASURY_FUND_PLAN.md` |
| `DEATH_SPIRAL_ANALYSIS.md` | IRON/TITAN TCR failure modes | n/a — no algorithmic peg exists |
| `SECURITY_ANALYSIS.md` | BTC/USD oracle, MIM `cook()` exploits | `audit/` (three real audit passes) |
| `DEPLOYMENT_GUIDE.md` | OP_NET CLI, Bitcoin testnet | `contracts/solidity/deploy/`, `docs/MAINNET_LAUNCH.md` |
| `PHOENIX_SYSTEM.md` | MotoSwap rebirth, death < 0.01 BTC/24h | `CauldronRegistry.relaunch` + `CauldronHook.isDead` |
| `PHOENIX_TAX_SYSTEM.md` | 3% ERC20 **transfer** tax to a "Magic Wallet" | tiered **swap** fee in `CauldronHook` |

The last row is the sharpest example: `CauldronToken.sol` is a plain ERC20 whose
only privileged function is `burn` — it has no transfer hook and cannot tax a
transfer. The tiered NFT tax is real, but it is a *swap* fee charged by the V4
hook, not a transfer tax on the token.

Kept rather than deleted: they are the historical record of where the design came
from, and the Phoenix docs in particular are the direct conceptual ancestor of the
relaunch cycle (immortal token, 24h volume death, snapshot claims).
