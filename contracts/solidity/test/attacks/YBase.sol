// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {ICauldronGovernor, BrewSpec, MetadataMode} from "../../cauldron/ICauldron.sol";

/**
 * @title YBase — FINAL red-team harness (pass 3)
 * @notice Brings up a live Cauldron on a Uniswap-v4 fork and adds the two
 *         primitives the earlier harnesses lacked, which is exactly why the
 *         remaining leads could never be reproduced:
 *
 *           1. RAW `modifyLiquidity` (mint/burn a concentrated band). Every
 *              perp risk cap in the protocol is derived from
 *              `poolManager.getLiquidity(id)` — the in-range liquidity — which is
 *              a quantity ANY actor can move. Without an LP primitive the Z-10
 *              lead is untestable.
 *           2. Arbitrarily large directional swaps that can push the pool tick
 *              THROUGH the 69x reserve ceiling, so the reserve band stops being
 *              out-of-range. That is the seam behind the new Y-01 finding.
 *
 *  Every test no-ops unless FORK_RPC is set (repo convention).
 */
abstract contract YBase is Test, IUnlockCallback {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    CauldronHook internal hook;
    CauldronRegistry internal registry;
    PerpEngine internal perp;
    IPoolManager internal pm;
    address internal posm;
    address internal token;
    bool internal active;

    YMockMiFrens internal frens;

    address internal trader = address(0x7EADE7);
    address internal attacker = address(0xA77ACC);
    address internal victim = address(0x717C71);

    uint160 internal constant MIN_LIMIT = 4295128740;
    uint160 internal constant MAX_LIMIT = 1461446703485210103287273052203988822378723970342 - 1;

    // op codes for unlockCallback
    uint8 internal constant OP_SWAP = 0;
    uint8 internal constant OP_LIQ = 1;

    struct YSwap {
        bool zeroForOne;
        int256 amountSpecified;
        address payer; // who supplies the token leg on a sell
        address recipient;
    }

    struct YLiq {
        int24 tickLower;
        int24 tickUpper;
        int256 liquidityDelta;
    }

    // -----------------------------------------------------------------------
    // Bring-up
    // -----------------------------------------------------------------------

    /// @param seedEth       ETH paired into the genesis pool
    /// @param genesisFrens  0 = no genesis bonus; >0 = mint that many mock OG frens
    ///                      and reserve 20% of supply as the redemption floor
    function _boot(uint256 seedEth, uint256 genesisFrens) internal {
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
        registry.setGovernor(address(new YGov()));

        if (genesisFrens > 0) {
            frens = new YMockMiFrens();
            frens.setRegistry(address(registry));
            for (uint256 i = 1; i <= genesisFrens; i++) frens.mint(victim, i);
            // 20% of supply reserved as the OG redemption floor.
            registry.setGenesisBonus(address(frens), 2000, genesisFrens);
        }

        vm.deal(address(this), 100_000 ether);
        (token,) = registry.summon{value: seedEth}();

        vm.deal(trader, 1_000 ether);
        vm.deal(attacker, 100_000 ether);
        vm.deal(victim, 1_000 ether);
    }

    /// @dev Stand up the perp engine on the live generation and fund both sides.
    function _bootPerp(uint256 plvEth, uint256 plvToken) internal {
        perp = new PerpEngine(
            pm, address(hook), address(registry),
            address(new YNoFrens()), address(0xD1D1), address(0x7E7E), address(this)
        );
        hook.setPerpEngine(address(perp));
        perp.fundPlv{value: plvEth}();
        deal(token, address(this), plvToken, true);
        IERC20Minimal(token).approve(address(perp), plvToken);
        perp.fundPlvToken(plvToken);

        hook.setDeathThreshold(0);            // keep the brew alive for opens
        _warp(25 hours);                      // past the open warmup
        vm.roll(block.number + 40);           // past the anti-snipe surtax window
        perp.poke();
    }

    // -----------------------------------------------------------------------
    // Clock helpers
    //
    //  H-1 (prior audit): `via_ir` CSEs repeated TIMESTAMP reads, so
    //  `vm.warp(block.timestamp + x)` inside a loop resolves to the SAME target
    //  every iteration. Route every warp through a storage-backed helper.
    // -----------------------------------------------------------------------
    function _warp(uint256 dt) internal {
        vm.warp(vm.getBlockTimestamp() + dt);
    }

    // -----------------------------------------------------------------------
    // Pool helpers
    // -----------------------------------------------------------------------

    function _key() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(registry.currentToken()),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
    }

    function _keyOf(uint256 gen) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(registry.generationToken(gen)),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
    }

    function _tick() internal view returns (int24 t) {
        (, t,,) = pm.getSlot0(_key().toId());
    }

    function _sqrtP() internal view returns (uint160 s) {
        (s,,,) = pm.getSlot0(_key().toId());
    }

    function _inRangeLiquidity() internal view returns (uint128) {
        return pm.getLiquidity(_key().toId());
    }

    /// @dev Exact-input ETH -> token, paid by this contract, delivered to `to`.
    function _buy(uint256 ethIn, address to) internal returns (uint256 got) {
        bytes memory r = pm.unlock(
            abi.encode(OP_SWAP, abi.encode(YSwap(true, -int256(ethIn), address(this), to)), _key())
        );
        (, int128 a1) = abi.decode(r, (int128, int128));
        got = uint256(uint128(a1));
    }

    /// @dev Exact-input token -> ETH. `payer` must have approved the PoolManager
    ///      (we prank the transfer, so an approval is not actually needed).
    function _sell(uint256 tokenIn, address payer) internal returns (uint256 got) {
        bytes memory r = pm.unlock(
            abi.encode(OP_SWAP, abi.encode(YSwap(false, -int256(tokenIn), payer, address(this))), _key())
        );
        (int128 a0,) = abi.decode(r, (int128, int128));
        got = uint256(uint128(a0));
    }

    /// @dev Mint (positive) or burn (negative) raw liquidity on the live pool.
    ///      This is the primitive the perp risk caps are unwittingly derived from.
    function _modifyLiquidity(int24 lower, int24 upper, int256 delta) internal returns (int128 a0, int128 a1) {
        bytes memory r = pm.unlock(
            abi.encode(OP_LIQ, abi.encode(YLiq(lower, upper, delta)), _key())
        );
        (a0, a1) = abi.decode(r, (int128, int128));
    }

    /// @dev Align a tick to the pool's spacing (toward -inf).
    function _align(int24 t) internal view returns (int24) {
        int24 s = registry.TICK_SPACING();
        int24 r = t / s;
        if (t < 0 && (t % s != 0)) r -= 1;
        return r * s;
    }

    function unlockCallback(bytes calldata raw) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        (uint8 op, bytes memory payload, PoolKey memory key) = abi.decode(raw, (uint8, bytes, PoolKey));

        if (op == OP_SWAP) {
            YSwap memory s = abi.decode(payload, (YSwap));
            BalanceDelta d = pm.swap(
                key,
                SwapParams({
                    zeroForOne: s.zeroForOne,
                    amountSpecified: s.amountSpecified,
                    sqrtPriceLimitX96: s.zeroForOne ? MIN_LIMIT : MAX_LIMIT
                }),
                ""
            );
            _settleDelta(key, d.amount0(), d.amount1(), s.payer, s.recipient);
            return abi.encode(d.amount0(), d.amount1());
        } else {
            YLiq memory l = abi.decode(payload, (YLiq));
            (BalanceDelta d,) = pm.modifyLiquidity(
                key,
                ModifyLiquidityParams({
                    tickLower: l.tickLower,
                    tickUpper: l.tickUpper,
                    liquidityDelta: l.liquidityDelta,
                    salt: bytes32(0)
                }),
                ""
            );
            _settleDelta(key, d.amount0(), d.amount1(), address(this), address(this));
            return abi.encode(d.amount0(), d.amount1());
        }
    }

    function _settleDelta(PoolKey memory key, int128 a0, int128 a1, address payer, address recipient) private {
        if (a0 < 0) pm.settle{value: uint256(uint128(-a0))}();
        if (a1 < 0) {
            pm.sync(key.currency1);
            if (payer == address(this)) {
                IERC20Minimal(Currency.unwrap(key.currency1)).transfer(address(pm), uint256(uint128(-a1)));
            } else {
                vm.prank(payer);
                IERC20Minimal(Currency.unwrap(key.currency1)).transfer(address(pm), uint256(uint128(-a1)));
            }
            pm.settle();
        }
        if (a0 > 0) pm.take(key.currency0, recipient, uint256(uint128(a0)));
        if (a1 > 0) pm.take(key.currency1, recipient, uint256(uint128(a1)));
    }

    receive() external payable {}
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

contract YNoFrens {
    function balanceOf(address) external pure returns (uint256) { return 0; }
}

contract YGov is ICauldronGovernor {
    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external {}
    function winner() external pure returns (uint256 id, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Shadow Wraith", symbol: "WRAITH", mode: MetadataMode.BaseURI,
            baseURI: "ipfs://wraith/", renderer: address(0), website: "w.xyz",
            socials: "x.com/w", nftSupply: 1000, volumePerNFT: 0, proposer: address(0xBEEF)
        });
        id = 1;
    }
}

/// @dev Registry-custodied ERC721 stand-in for the genesis MiFrens.
contract YMockMiFrens {
    mapping(uint256 => address) public ownerOf;
    mapping(address => uint256) public balanceOf;
    mapping(uint256 => bool) public everMoved;
    address public registry;
    uint256 public totalMinted;
    address public minter;
    address public vault;
    uint256 public maxSupply = 2400;

    function setRegistry(address r) external { registry = r; }
    // Surface used by `CauldronRegistry._continueMiFrens` on the gen-2 rebirth.
    function setMinter(address m) external { minter = m; }
    function setVault(address v) external { vault = v; }
    function mint(address to) external returns (uint256 id) {
        id = ++totalMinted;
        ownerOf[id] = to;
        balanceOf[to] += 1;
    }

    function mint(address to, uint256 id) external {
        ownerOf[id] = to;
        balanceOf[to] += 1;
        totalMinted += 1;
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

/// @dev A gas-metered relaunch caller: runs `registry.relaunch()` with a HARD gas
///      cap so the 63/64 rule applies exactly as it would to a real L2 block-gas
///      limit, and reports whether the rebirth completed.
contract YRelaunchRunner {
    function tryRelaunch(address reg, uint256 gasCap) external returns (bool ok) {
        (ok,) = reg.call{gas: gasCap}(abi.encodeWithSignature("relaunch()"));
    }
}
