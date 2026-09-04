// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";

import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronToken} from "../../CauldronToken.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../../cauldron/ICauldron.sol";

/**
 * ATTACK A-01 — CREATE2 TOKEN-ADDRESS SQUAT (permanent protocol brick)
 *
 *  TARGET INVARIANT: "Lifecycle — the eternal machine can always be summoned and
 *  relaunched."
 *
 *  THE ATTACK. Every generation's ERC-20 is deployed with a FULLY DETERMINISTIC
 *  CREATE2 address:
 *
 *      CauldronRegistry._deployToken -> PoolOps.deployToken (DELEGATECALL, so
 *        address(this) == the registry):
 *          token = address(new CauldronToken{salt: bytes32(gen)}(
 *                      name, symbol, gen, address(this), totalSupply));
 *
 *  Every input is public *before* the transaction that would deploy it:
 *      salt      = the generation number       (registry.currentGeneration() + 1)
 *      deployer  = the registry                (constant)
 *      name      = LaunchLib.displayName(spec.name)  ("<name> by Magic Internet Frens")
 *      symbol    = spec.symbol
 *      supply    = CauldronBase.TOTAL_SUPPLY   (constant)
 *  and (name, symbol) come from `governor.winner()` — a PUBLIC VIEW whose result
 *  is *frozen* once the leading proposal's `votingEndsAt` has passed
 *  (CauldronGovernor._bestUnconsumed).
 *
 *  So anyone can compute the next generation's token address and deploy ANY
 *  contract there first. CREATE2 into an occupied address fails, Solidity's
 *  `new ... {salt}` reverts on failure, and the revert propagates out of
 *  `relaunch()` — which means `governor.markConsumed(winId)` NEVER executes, the
 *  same proposal keeps winning, and the machine can never be reborn.
 *
 *  SEVERITY: CRITICAL (permanent, cheap, permissionless denial of the entire
 *  protocol lifecycle: no relaunch => no migration reserve for the next gen, LP
 *  stuck in a dead pool, perp engine stranded on a dead token).
 *
 *  ── STATUS: FIXED ───────────────────────────────────────────────────────────
 *  {PoolOps.deployToken} now uses PLAIN CREATE. The address derives from
 *  (registry, registry nonce), and only the registry can advance its own nonce, so
 *  there is no address for an attacker to occupy — this is structural immunity,
 *  not a probabilistic hardening. Nothing depended on the token address being
 *  predictable. The tests below are the REGRESSIONS.
 */
contract A01_Create2SquatTest is Test {
    CauldronHook hook;
    CauldronRegistry registry;
    IPoolManager pm;
    address posm;
    bool active;

    uint256 constant TOTAL_SUPPLY = 777_000_000e18;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
        posm = vm.envAddress("POSITION_MANAGER");
        pm = IPoolManager(poolManager);

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs =
            abi.encode(IPoolManager(poolManager), uint256(1 ether), address(0), address(this), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManager), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == hookAddr, "hook addr");

        registry = new CauldronRegistry(poolManager, posm, address(hook), address(0), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));

        vm.deal(address(this), 100 ether);
    }

    // ---------------------------------------------------------------------
    // Address prediction (this is the whole attack primitive)
    // ---------------------------------------------------------------------

    function _predictToken(address deployer, uint256 gen, string memory name, string memory symbol)
        internal
        pure
        returns (address)
    {
        bytes memory initCode = abi.encodePacked(
            type(CauldronToken).creationCode,
            abi.encode(name, symbol, gen, deployer, TOTAL_SUPPLY)
        );
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), deployer, bytes32(gen), keccak256(initCode))
                    )
                )
            )
        );
    }

    // ---------------------------------------------------------------------
    // 1. THE PRIMITIVE IS GONE: the summoned token no longer lands on the
    //    address an outsider can compute from the public CREATE2 inputs.
    // ---------------------------------------------------------------------
    function test_Fixed_A01_TokenAddressIsNotPredictable() public {
        if (!active) return;

        address predicted =
            _predictToken(address(registry), 1, "Gnomeland by Magic Internet Frens", "GNOME");

        (address token,) = registry.summon{value: 1 ether}();

        assertTrue(token != predicted, "FIXED: CREATE2 prediction no longer matches");
        console2.log("attacker's CREATE2 prediction:", predicted);
        console2.log("actual gen-1 token           :", token);
    }

    // ---------------------------------------------------------------------
    // 2. INVARIANT: an attacker occupying the CREATE2-predicted address must
    //    NOT be able to stop genesis. (Was the finding; now holds.)
    // ---------------------------------------------------------------------
    function test_Invariant_A01_SummonSurvivesTokenAddressSquat() public {
        if (!active) return;

        // The attacker computes the OLD CREATE2 target and occupies it.
        address predicted =
            _predictToken(address(registry), 1, "Gnomeland by Magic Internet Frens", "GNOME");
        _squat(predicted);

        // FIXED: genesis proceeds regardless — the squatted address is simply not
        // where the token goes any more.
        (address token,) = registry.summon{value: 1 ether}();
        assertEq(registry.currentGeneration(), 1, "genesis completed despite the squat");
        assertTrue(token != predicted, "token dodged the squatted address");
        assertEq(CauldronToken(token).totalSupply(), TOTAL_SUPPLY, "and is fully minted");
    }

    // ---------------------------------------------------------------------
    // 3. THE REAL KILL SHOT: squat the NEXT generation and `relaunch()` is
    //    permanently bricked — and because the revert rolls back
    //    `governor.markConsumed`, the same proposal wins forever.
    //    (This test FAILING is the finding.)
    // ---------------------------------------------------------------------
    function test_Invariant_A01_RelaunchSurvivesTokenAddressSquat() public {
        if (!active) return;

        SquatGov gov = new SquatGov();
        registry.setGovernor(address(gov));
        registry.summon{value: 1 ether}();

        // Age the pool into "dead" so relaunch is unlocked (permissionless).
        vm.warp(vm.getBlockTimestamp() + 1 days + 1); // wall-clock death window (audit Z-05)
        assertTrue(hook.isDead(registry.generationPoolId(1)), "pool dead");

        // ATTACKER: read the public winner, compute gen-2's OLD CREATE2 address,
        // and occupy it. This used to brick the rebirth permanently.
        (, BrewSpec memory spec) = gov.winner();
        address predicted = _predictToken(
            address(registry), 2, string.concat(spec.name, " by Magic Internet Frens"), spec.symbol
        );
        _squat(predicted);
        console2.log("squatted (old CREATE2) gen-2 address:", predicted);

        // FIXED: the eternal machine is reborn regardless.
        (address token2,) = registry.relaunch();
        assertEq(registry.currentGeneration(), 2, "machine reborn despite the squat");
        assertTrue(token2 != predicted, "gen-2 token dodged the squatted address");
        assertEq(gov.consumedCount(), 1, "the winning proposal was actually retired");
        console2.log("actual gen-2 token                  :", token2);
    }

    // ---------------------------------------------------------------------
    // helpers
    // ---------------------------------------------------------------------

    /// @dev Occupy `who` with (any) runtime code. On-chain the attacker would use a
    ///      one-line CREATE2 factory; `vm.etch` is the same end state for the EVM's
    ///      CREATE2 collision rule (target must have empty code AND zero nonce).
    function _squat(address who) internal {
        vm.etch(who, hex"60006000fd"); // 5 bytes of anything
        assertGt(who.code.length, 0, "squatter in place");
    }
}

/// @dev Minimal governor whose winner is stable + publicly readable (exactly the
///      shape the real {CauldronGovernor} exposes once voting has closed).
contract SquatGov is ICauldronGovernor {
    uint256 public consumedCount;

    function hasProposals() external pure returns (bool) { return true; }

    function markConsumed(uint256) external { consumedCount += 1; }

    function winner() external pure returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Ethereal Spirit",
            symbol: "SPIRIT",
            mode: MetadataMode.BaseURI,
            baseURI: "ipfs://spirit/",
            renderer: address(0),
            website: "spirit.xyz",
            socials: "x.com/spirit",
            nftSupply: 1000,
            volumePerNFT: 0,
            proposer: address(0xBEEF)
        });
        id = 1;
    }
}
