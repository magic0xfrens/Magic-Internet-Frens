/* ────────────────────────────────────────────────────────────────────────────
 * vfat.tools loader for MiFrens / Cauldron PLV (perp liquidity vault)
 *
 * This is the file that lives at `src/static/js/mifrens.js` inside a vfat-tools
 * fork. It uses vfat's STANDARD Synthetix helper (`loadSynthetixPoolInfo` +
 * `loadMultipleSynthetixPools`) — the exact pattern used by cryptex.js — so the
 * page is a fast-merge standard loader, not a bespoke page.
 *
 * It reads a StakingRewards-shaped ADAPTER (see marketing/vfat/ADAPTER_SPEC.md),
 * not the raw PerpVault, because vfat's helper expects the Synthetix ABI
 * (stakingToken / rewardsToken / rewardRate / totalSupply / balanceOf / earned /
 * periodFinish). The adapter presents the PLV's REAL, fee-derived yield through
 * that ABI, exposing rewardRate as a TRAILING realized rate (last epoch's fee
 * flow), which is the honest way to surface real-yield APR.
 *
 * ⚠️ BEFORE SUBMIT: fill the two adapter addresses below (mainnet, verified) and
 * confirm the reward/stake tokens are priceable on a DEX vfat can read.
 * ──────────────────────────────────────────────────────────────────────────── */

$(function () {
  consoleInit(main);
});

// Canonical Synthetix StakingRewards ABI (the subset vfat reads + the action
// selectors it renders buttons for). The adapter MUST match this ABI exactly.
const MIFRENS_PLV_ABI = [
  { inputs: [{ internalType: "address", name: "account", type: "address" }], name: "balanceOf", outputs: [{ internalType: "uint256", name: "", type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [{ internalType: "address", name: "account", type: "address" }], name: "earned", outputs: [{ internalType: "uint256", name: "", type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "periodFinish", outputs: [{ internalType: "uint256", name: "", type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "rewardRate", outputs: [{ internalType: "uint256", name: "", type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "rewardsToken", outputs: [{ internalType: "address", name: "", type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "stakingToken", outputs: [{ internalType: "address", name: "", type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "totalSupply", outputs: [{ internalType: "uint256", name: "", type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [{ internalType: "uint256", name: "amount", type: "uint256" }], name: "stake", outputs: [], stateMutability: "nonpayable", type: "function" },
  { inputs: [{ internalType: "uint256", name: "amount", type: "uint256" }], name: "withdraw", outputs: [], stateMutability: "nonpayable", type: "function" },
  { inputs: [], name: "getReward", outputs: [], stateMutability: "nonpayable", type: "function" },
  { inputs: [], name: "exit", outputs: [], stateMutability: "nonpayable", type: "function" },
];

async function main() {
  const App = await init_ethers();

  _print(`Initialized ${App.YOUR_ADDRESS}`);
  _print("Reading smart contracts...\n");

  // ── PLV adapter pools (fill with mainnet, verified addresses) ───────────────
  // ETH side  — stake WETH, earn WETH (perp open fee + funding + liquidations).
  // TOKEN side — stake the current iteration token (GNOME/…), earn WETH
  //              (short-side fees). Reward is real usage revenue, not emissions.
  const Pools = [
    "0x0000000000000000000000000000000000000000", // TODO: PLV_ADAPTER_ETH   (mainnet)
    "0x0000000000000000000000000000000000000000", // TODO: PLV_ADAPTER_TOKEN (mainnet)
  ].map((a) => ({
    address: a,
    abi: MIFRENS_PLV_ABI,
    stakeTokenFunction: "stakingToken",
    rewardTokenFunction: "rewardsToken",
  }));

  const tokens = {};
  const prices = {};

  // Prime the token/price maps from the first pool (vfat convention).
  await loadSynthetixPoolInfo(
    App, tokens, prices,
    Pools[0].abi, Pools[0].address,
    Pools[0].rewardTokenFunction, Pools[0].stakeTokenFunction
  );

  const p = await loadMultipleSynthetixPools(App, tokens, prices, Pools);

  _print_bold(`Total staked: $${formatMoney(p.staked_tvl)}`);
  if (p.totalUserStaked > 0) {
    _print(
      `You are staking a total of $${formatMoney(p.totalUserStaked)} ` +
        `at an APR of ${(p.totalAPR * 100).toFixed(2)}%\n`
    );
  }

  hideLoading();
}
