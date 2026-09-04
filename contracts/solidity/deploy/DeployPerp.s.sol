// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PerpEngine} from "../cauldron/PerpEngine.sol";
import {PerpVault} from "../cauldron/PerpVault.sol";

interface IHookWire {
    function setPerpEngine(address engine) external;
    function collection() external view returns (address);
}
interface ICollLiq {
    function liquidatorMinter() external view returns (address);
}
interface IPerpVaultDeposit {
    function depositEth() external payable returns (uint256);
}
interface IOwnable {
    function transferOwnership(address newOwner) external;
}

/**
 * @title DeployPerp
 * @notice POST-SUMMON deploy of the hook-native perp stack for a live Cauldron.
 *         Run this AFTER the launchpad has been deployed and gen-1 has summoned
 *         (finalize()), because the engine reads the live pool for its TWAP seed.
 *
 *  Deploys + wires:
 *    1. PerpEngine(poolManager, hook, registry, mifrens, dividend, treasury, owner)
 *    2. PerpVault(engine, registry)                — Community PLV (LP-for-perps)
 *    3. hook.setPerpEngine(engine)                 — enables afterSwap auto-liq
 *                                                    AND auto-wires the current
 *                                                    collection's badge minter
 *    4. engine.setHook(hook)                        — badge-mint target lookup
 *    5. engine.setVault(vault)                      — activates fee→LP/insurance
 *    6. (optional) seed the ETH PLV via the vault so longs work immediately
 *
 *  Env:
 *    PRIVATE_KEY        deployer/owner (required)
 *    POOL_MANAGER       V4 PoolManager (required)
 *    HOOK               the launchpad's CauldronHook (required)
 *    REGISTRY           the launchpad's CauldronRegistry (required)
 *    PRESALE            MiFrensGenesis (for the OG open-fee discount) (required)
 *    DIVIDEND           MiFrensDividend (fee sink) (required)
 *    TREASURY           treasury (default: deployer)
 *    PLV_SEED_ETH       ETH to seed the vault/PLV so longs open (default 0)
 *
 *  Run (from contracts/solidity):
 *    FOUNDRY_PROFILE=cauldron forge script deploy/DeployPerp.s.sol \
 *      --rpc-url $SEPOLIA_RPC --broadcast -vvv
 */
contract DeployPerp is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address poolManager = vm.envAddress("POOL_MANAGER");
        address hook = vm.envAddress("HOOK");
        address registry = vm.envAddress("REGISTRY");
        address presale = vm.envAddress("PRESALE");
        address dividend = vm.envAddress("DIVIDEND");
        address treasury = vm.envOr("TREASURY", deployer);
        uint256 seed = vm.envOr("PLV_SEED_ETH", uint256(0));
        // The governance timelock (from DeployLaunchpad). If set, this script hands
        // BOTH the hook and the engine to it as the final step — so from launch,
        // every param/policy/fee-router change is timelock.schedule → wait →
        // execute. Leave unset (0) only for throwaway local tests.
        address timelock = vm.envOr("TIMELOCK", address(0));

        vm.startBroadcast(pk);

        PerpEngine engine = new PerpEngine(
            IPoolManager(poolManager), hook, registry, presale, dividend, treasury, deployer
        );
        console2.log("PerpEngine     :", address(engine));

        PerpVault vault = new PerpVault(address(engine), registry);
        console2.log("PerpVault      :", address(vault));

        // Wire. The engine already knows the hook (constructor `hookAddr`), so it
        // reads hook.collection() for badge minting. setPerpEngine enables the
        // afterSwap auto-liq AND auto-wires the live collection's badge minter.
        IHookWire(hook).setPerpEngine(address(engine));
        // NOTE: the engine is NOT permanently tax-exempt — perp swaps SHOULD pay the
        // hook fee (they're high-volume revenue for the dividend/floor/reserve). The
        // registry exempts the engine ONLY for the split-second of the relaunch
        // force-close (see CauldronRegistry._perpHousekeep), so force-close swaps
        // don't nest into the legacy buyback on the dying pool.
        engine.setVault(address(vault));
        // AUDIT (M-05): `insuranceFloor` defaults to 0, which BOTH disables the
        // opens circuit-breaker (`insuranceEth < insuranceFloor` is never true) and
        // — before the risk-based guard was added — let `skimInsurance` drain the
        // entire bad-debt buffer. Arm it explicitly at deploy.
        engine.setVaultLimits(
            vm.envOr("MAX_UTIL_BPS", uint256(8_000)),
            vm.envOr("INSURANCE_FLOOR_WEI", uint256(0.05 ether))
        );

        // LIQUIDATION-MARK GUARDS, SET AT DEPLOY (audit F-12).
        //
        //  These used to be left at the contract defaults with a runbook note to
        //  "set risk params via cast BEFORE the handoff". That step did not happen:
        //  the round-31 engine still reads `twapWindow == 300` on-chain. A pending
        //  manual step behind an ownership transfer is a step that silently never
        //  runs, so the window is now an explicit deploy parameter and is correct
        //  from birth.
        //
        //  CHOOSING `TWAP_WINDOW`. This is the averaging window for the liquidation
        //  mark; execution still happens at spot. It is NOT the same thing as the
        //  engine's `OBS_INTERVAL` (15s), which is only the minimum spacing between
        //  observation-ring writes — that throttle means the EFFECTIVE lookback is
        //  between `twapWindow` and `twapWindow + 15s`.
        //
        //  Size it in BLOCKS, not seconds, because that is what an attacker has to
        //  hold a price across:
        //    * Sepolia / L1 (~12s blocks): 300s ~ 25 blocks. A 15s window would be
        //      ONE block — trivially flash-manipulable. Do not go low here.
        //    * Orbit L2 (~250ms blocks): 15s ~ 60 blocks, which is a defensible
        //      window and hugs spot far more closely (fewer born-underwater opens).
        //  Hence the default stays 300 and the fast-L2 value is opt-in per chain.
        engine.setGuards(
            uint32(vm.envOr("TWAP_WINDOW", uint256(300))),
            vm.envOr("MAX_LIQ_BPS", uint256(2_000)),
            vm.envOr("MAX_FUNDING_BPS", uint256(5_000))
        );
        console2.log("twapWindow (s) :", vm.envOr("TWAP_WINDOW", uint256(300)));

        // Optional: seed the ETH PLV through the vault (deployer gets LP shares)
        // so longs can open immediately without waiting for community deposits.
        if (seed > 0) {
            IPerpVaultDeposit(address(vault)).depositEth{value: seed}();
            console2.log("seeded PLV via vault (wei):", seed);
        }

        // FINAL HANDOFF — hand the hook AND the engine to the governance timelock.
        // All owner-gated wiring (setPerpEngine, setVault, risk params done via cast
        // after) is either done or must itself now go through the timelock. NOTE:
        // set engine risk/guards BEFORE this in a combined script, or do them via
        // the timelock after. Here we transfer last; the deploy runbook sets risk
        // params via cast BEFORE calling this handoff (see round-25 runbook).
        if (timelock != address(0)) {
            IHookWire(hook).setPerpEngine(address(engine)); // ensure wired pre-handoff
            IOwnable(hook).transferOwnership(timelock);
            IOwnable(address(engine)).transferOwnership(timelock);
            console2.log("hook + engine owner -> timelock:", timelock);
        }

        vm.stopBroadcast();

        address col = IHookWire(hook).collection();
        console2.log("--- PERP WIRED ---");
        console2.log("active collection:", col);
        console2.log("badge minter set :", col == address(0) ? address(0) : ICollLiq(col).liquidatorMinter());
        console2.log("(should equal the PerpEngine above)");
    }
}
