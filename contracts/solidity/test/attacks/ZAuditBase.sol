// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";

import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../../cauldron/ICauldron.sol";

/**
 * @title ZAuditBase
 * @notice INDEPENDENT audit harness (2026 review). Brings up a real Cauldron on a
 *         live Uniswap-V4 fork and exposes a *generic* swap primitive covering all
 *         four (exact-in|exact-out) x (buy|sell) quadrants — the stock harness only
 *         exercises exact-input buys, which is precisely why the exact-OUTPUT sell
 *         path went unmeasured.
 *
 *  Every test in this directory no-ops unless FORK_RPC is set, matching the
 *  repository convention so CI stays green without an RPC.
 */
abstract contract ZAuditBase is Test {
    using StateLibrary for IPoolManager;

    CauldronHook internal hook;
    CauldronRegistry internal registry;
    IPoolManager internal pm;
    address internal posm;
    bool internal active;

    uint160 internal constant MIN_SQRT_LIMIT = 4295128740;
    uint160 internal constant MAX_SQRT_LIMIT = 1461446703485210103287273052203988822378723970341;

    // ---- swap request marshalling for our own unlockCallback ----
    struct ZSwap {
        bool zeroForOne;
        int256 amountSpecified; // <0 exact-in, >0 exact-out
        address recipient;
    }

    function _bootstrap(uint256 deathThreshold) internal {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        // PIN THE FORK BLOCK. On an unpinned fork the block environment is re-synced
        // to chain head behind the test, which silently swallows `vm.warp` (measured:
        // 24 consecutive `vm.warp(+150)` calls all resolved to the same timestamp).
        // Every time-dependent finding below would be untestable without this.
        vm.createSelectFork(rpc);
        uint256 pinned = vm.envOr("FORK_BLOCK", block.number - 64);
        vm.createSelectFork(rpc, pinned);

        address poolManager = vm.envAddress("POOL_MANAGER");
        posm = vm.envAddress("POSITION_MANAGER");
        pm = IPoolManager(poolManager);

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs =
            abi.encode(IPoolManager(poolManager), deathThreshold, address(0), address(this), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManager), deathThreshold, address(0), address(this), address(this)
        );
        require(address(hook) == hookAddr, "hook addr");

        registry = new CauldronRegistry(poolManager, posm, address(hook), address(0), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        // The registry's own green-candle / prime buy must be fee-exempt (both flags,
        // since exemption is gated on isOpener[sender] AND taxExempt[player]).
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));

        vm.deal(address(this), 1_000 ether);
    }

    // -----------------------------------------------------------------------
    // Pool helpers
    // -----------------------------------------------------------------------

    function _key(uint256 gen) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(registry.generationToken(gen)),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
    }

    function _liveKey() internal view returns (PoolKey memory) {
        return _key(registry.currentGeneration());
    }

    function _spotSqrt(PoolId id) internal view returns (uint160 s) {
        (s,,,) = pm.getSlot0(id);
    }

    function _tick(PoolId id) internal view returns (int24 t) {
        (, t,,) = pm.getSlot0(id);
    }

    /// @dev Generic swap through the LIVE pool, executed by THIS contract (so the
    ///      hook sees us as both `sender` and, via hookData, the tagged player).
    function _swap(PoolKey memory key, bool zeroForOne, int256 amountSpecified)
        internal
        returns (int128 amount0, int128 amount1)
    {
        bytes memory res =
            pm.unlock(abi.encode(ZSwap({zeroForOne: zeroForOne, amountSpecified: amountSpecified, recipient: address(this)}), key));
        (amount0, amount1) = abi.decode(res, (int128, int128));
    }

    /// @dev Exact-input ETH -> token. Returns tokens received.
    function _buyExactIn(uint256 ethIn) internal returns (uint256 got) {
        (, int128 a1) = _swap(_liveKey(), true, -int256(ethIn));
        got = uint256(uint128(a1));
    }

    /// @dev Exact-input token -> ETH. Returns ETH received.
    function _sellExactIn(uint256 tokenIn) internal returns (uint256 got) {
        (int128 a0,) = _swap(_liveKey(), false, -int256(tokenIn));
        got = uint256(uint128(a0));
    }

    /// @dev EXACT-OUTPUT token -> ETH ("give me exactly `ethOut` ETH"). Returns the
    ///      token amount actually spent.
    function _sellExactOut(uint256 ethOut) internal returns (uint256 spent) {
        (, int128 a1) = _swap(_liveKey(), false, int256(ethOut));
        spent = uint256(uint128(-a1));
    }

    /// @dev External wrapper for the exact-output sell. `_sellExactOut` first reads
    ///      `registry.currentGeneration()` to build the pool key, and `vm.expectRevert`
    ///      binds to the NEXT external call — which would be that view, not the swap.
    ///      Routing through a self-call makes the swap itself the expected-revert target.
    function sellExactOutExternal(uint256 ethOut) external returns (uint256) {
        require(msg.sender == address(this), "self");
        return _sellExactOut(ethOut);
    }

    /// @dev EXACT-OUTPUT ETH -> token ("give me exactly `tokenOut` token").
    function _buyExactOut(uint256 tokenOut) internal returns (uint256 spent) {
        (int128 a0,) = _swap(_liveKey(), true, int256(tokenOut));
        spent = uint256(uint128(-a0));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "not pm");
        (ZSwap memory s, PoolKey memory key) = abi.decode(data, (ZSwap, PoolKey));
        BalanceDelta d = pm.swap(
            key,
            SwapParams({
                zeroForOne: s.zeroForOne,
                amountSpecified: s.amountSpecified,
                sqrtPriceLimitX96: s.zeroForOne ? MIN_SQRT_LIMIT : MAX_SQRT_LIMIT
            }),
            abi.encode(address(this))
        );
        int128 a0 = d.amount0();
        int128 a1 = d.amount1();

        // Settle whichever leg we owe; take whichever leg we are owed.
        if (a0 < 0) pm.settle{value: uint256(uint128(-a0))}();
        if (a1 < 0) {
            pm.sync(key.currency1);
            IERC20Minimal(Currency.unwrap(key.currency1)).transfer(address(pm), uint256(uint128(-a1)));
            pm.settle();
        }
        if (a0 > 0) pm.take(key.currency0, s.recipient, uint256(uint128(a0)));
        if (a1 > 0) pm.take(key.currency1, s.recipient, uint256(uint128(a1)));
        return abi.encode(a0, a1);
    }

    /// @dev Total ETH the hook has actually banked from fees (its three tracked pots).
    function _hookBanked() internal view returns (uint256) {
        return hook.relaunchETH() + hook.legacyBuffer() + hook.proposerOwed(hook.activeProposer());
    }

    receive() external payable {}
}

/// Minimal governor stand-in so `relaunch()` can proceed in fork tests.
contract ZMockGovernor is ICauldronGovernor {
    address public prop;

    constructor(address _p) {
        prop = _p;
    }

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
            nftSupply: 1000,
            volumePerNFT: 0,
            proposer: prop
        });
        id = 1;
    }
}

/// Minimal registry-custodied ERC721 stand-in for the genesis MiFrens.
contract ZMockMiFrens {
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => bool) public everMoved;
    address public registry;

    function setRegistry(address r) external {
        registry = r;
    }

    function mint(address to, uint256 id) external {
        ownerOf[id] = to;
        balanceOf[to] += 1;
    }

    function custodyTransfer(address from, address to, uint256 id) external {
        require(msg.sender == registry, "not registry");
        require(ownerOf[id] == from, "wrong from");
        balanceOf[from] -= 1;
        balanceOf[to] += 1;
        ownerOf[id] = to;
        everMoved[id] = true;
    }
}
