// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";

import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../../cauldron/ICauldron.sol";

/**
 * @title FinalAuditBase
 * @notice Shared rig for the FINAL audit's attack + invariant suites.
 *
 *  Two deployment modes, because the findings split cleanly in two:
 *
 *   - {_deployOffchain} builds ONLY the contracts whose constructors make no
 *     external calls (the hook, the registry, the facet). That covers every
 *     finding whose exploit lives in the contracts' own accounting rather than
 *     in Uniswap, and it runs with no RPC — so these tests are real CI gates,
 *     not fork-gated no-ops.
 *   - the fork suites reuse the repository's established pattern (mine the hook
 *     address, drive the LIVE PoolManager); they no-op without `FORK_RPC`.
 *
 *  The hook address must carry its permission flags in its low bits, so it is
 *  always CREATE2-mined via the vendored {HookMiner} — even off-chain, because
 *  {BaseHook}'s constructor validates the address against
 *  {CauldronHook.getHookPermissions}.
 */
abstract contract FinalAuditBase is Test {
    CauldronHook internal hook;
    CauldronRegistry internal registry;

    /// @dev Storage slot of `CauldronHook.legacyOwedToReserve`, read out of the
    ///      compiled artifact's storageLayout (see the audit's Appendix). Used to
    ///      stage a state that is otherwise only reachable through a live pool.
    uint256 internal constant SLOT_LEGACY_OWED = 27;

    uint160 internal constant HOOK_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    /// @dev Deploy the hook + registry + facet with a stub PoolManager address.
    ///      Nothing in any of the three constructors calls out, so this is a real
    ///      deployment of the production bytecode — only the pool is absent.
    function _deployOffchain(address poolManagerStub) internal {
        bytes memory ctorArgs =
            abi.encode(IPoolManager(poolManagerStub), uint256(1 ether), address(0), address(this), address(this));
        (address mined, bytes32 salt) =
            HookMiner.find(address(this), HOOK_FLAGS, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManagerStub), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == mined, "hook addr");

        registry = new CauldronRegistry(poolManagerStub, poolManagerStub, address(hook), address(this), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
    }

    receive() external payable {}
}

/// @notice Minimal ERC20 used to stand in for a brew token in the off-chain rig.
contract FinalMockToken {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 a) external {
        balanceOf[to] += a;
        totalSupply += a;
    }

    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }

    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a;
        return true;
    }

    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        allowance[f][msg.sender] -= a;
        balanceOf[f] -= a;
        balanceOf[to] += a;
        return true;
    }
}

/// @notice Governor stub so `relaunch()` can reach its winner path in fork tests.
contract FinalMockGovernor is ICauldronGovernor {
    address public prop = address(0xBEEF);

    function hasProposals() external pure returns (bool) {
        return true;
    }

    function markConsumed(uint256) external {}

    function winner() external view returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Ethereal Spirit",
            symbol: "SPIRIT",
            mode: MetadataMode.BaseURI,
            baseURI: "ipfs://spirit/",
            renderer: address(0),
            website: "spirit.xyz",
            socials: "x.com/spirit",
            quote: address(0),
            nftSupply: 1000,
            volumePerNFT: 0,
            proposer: prop
        });
        id = 1;
    }
}
