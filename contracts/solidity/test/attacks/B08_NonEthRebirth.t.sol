// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {CauldronHook} from "../../CauldronHook.sol";
import {PoolOps, IPositionManagerOps, SeedResult} from "../../cauldron/PoolOps.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-08 — THE NON-ETH REBIRTH, IMPLEMENTED AND PROVEN
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  B-05 established that a non-native rebirth could not work and bricked the
 *  protocol trying. Four separate walls, each an unguarded revert behind
 *  `markConsumed`. This suite proves each one is now genuinely gone — not
 *  refused, not degraded, but WORKING — and that the decision logic which picks
 *  the seed quote can never revert or pick something it cannot fund.
 *
 *  THE FOUR WALLS, AND WHERE EACH IS PROVEN HERE:
 *
 *    1. No conversion / no rescaling — the seed amount was native wei whatever
 *       the quote. FIXED by `PoolOps.seedFunding`, which picks the quote from
 *       what the protocol ACTUALLY HOLDS and pulls exactly the matching reserve.
 *       Proven by the four `SeedFunding` unit tests below.
 *
 *    2. `PoolOps.removeAll` measured recovery as `address(this).balance`, which
 *       does not move when currency0 arrives as an ERC20 — so a non-native
 *       generation reported ZERO recovered and tripped `NoLiquidityToSeed()`.
 *       This wall was MASKED by the other three and only surfaced while building
 *       the fix. Proven by `test_Wall2_RemoveAllRecoversTheQuoteSide`.
 *
 *    3. The green-candle buy settled native ether into an ERC20-currency0 pool →
 *       `CurrencyNotSettled()`. Proven by
 *       `test_Wall3_UsdgSeedAndGreenCandleSettles`, which runs the REAL
 *       `createAndSeedWithBuy` against a 6-decimal quote on a live fork.
 *
 *    4. `setLiveKey` refused a non-native key. Proven in B05.
 *
 *  DECIMALS ARE THE POINT OF USING USDG HERE. The live manifest's USDG is 6
 *  decimals, so a seed figure carried over from a native generation would be
 *  wrong by 1e12 — the failure that produced
 *  `ERC20InsufficientBalance(registry, 0, 19999999999999987150)`. Seeding in an
 *  asset's OWN units is what makes that class of error unrepresentable.
 * ═══════════════════════════════════════════════════════════════════════════
 */

/// @dev 6-decimal quote — the shape of USDG in indexer/deployments/round.json.
contract Usdg6 is IERC20 {
    string public constant name = "Magic USD";
    string public constant symbol = "USDG";
    uint8 public constant decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 a) external { balanceOf[to] += a; totalSupply += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a; return true;
    }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= a;
        balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Wall 1 — the funding decision. Pure logic, no fork needed.
// ═══════════════════════════════════════════════════════════════════════════

contract B08_SeedFunding is Test {
    HookReserveStub internal hook;
    Usdg6 internal usdg;

    address internal constant NATIVE = address(0);

    function setUp() public {
        hook = new HookReserveStub();
        usdg = new Usdg6();
        vm.deal(address(hook), 100 ether);
    }

    /// @notice LEG 1 — the proposal's quote is honoured when value already exists
    ///         in it. This is the case that makes the whole feature real: the guild
    ///         rotates a live generation into USDG, it dies holding USDG, and its
    ///         successor is reborn in USDG with no conversion anywhere.
    function test_Leg1_ProposalQuoteHonouredWhenFundable() public {
        (address q, uint256 amt,) = PoolOps.seedFunding(
            address(hook),
            address(usdg),   // want USDG
            address(usdg),   // the dying generation was ALSO USDG
            5_000e6,         // recovered, in USDG's OWN 6-decimal units
            address(0)
        );
        assertEq(q, address(usdg), "seeded in the requested quote");
        assertEq(amt, 5_000e6, "in its own units - no 1e12 rescale anywhere");
    }

    /// @notice LEG 1 also picks up the hook's per-asset reserve — which is the FIRST
    ///         caller `releaseRelaunchAsset` has ever had (red-team L-1). Before
    ///         this, a non-native generation's fees accrued behind a registry-gated
    ///         door that no registry function opened.
    function test_Leg1_PullsTheHookPerAssetReserve() public {
        usdg.mint(address(hook), 250e6);
        hook.setAssetReserve(address(usdg), 250e6);

        (address q, uint256 amt,) = PoolOps.seedFunding(
            address(hook), address(usdg), address(usdg), 1_000e6, address(0)
        );
        assertEq(q, address(usdg), "USDG");
        assertEq(amt, 1_250e6, "recovery + the previously-unreachable asset reserve");
        assertEq(hook.assetReserve(address(usdg)), 0, "reserve was actually pulled");
    }

    /// @notice LEG 2 — a quote we cannot fund DEGRADES to native rather than
    ///         reverting. The dying generation was native, so its recovery is
    ///         native; asking for USDG with no USDG anywhere must not brick.
    function test_Leg2_UnfundableQuoteDegradesToNative() public {
        (address q, uint256 amt,) = PoolOps.seedFunding(
            address(hook),
            address(usdg),   // want USDG
            NATIVE,          // but the dying generation was ETH
            8 ether,         // so the recovery is ETH
            address(0)
        );
        assertEq(q, NATIVE, "degrades to native");
        assertEq(amt, 8 ether, "seeded with what we actually hold");
        assertEq(hook.assetReserve(address(usdg)), 0, "and nothing was pulled for USDG");
    }

    /// @notice LEG 3 — the case that would otherwise be a brick. The dying
    ///         generation is USDG, the proposal asks for native, and there is no
    ///         native income at all. Falling back to "native" would seed ZERO and
    ///         revert; instead the machine is reborn in its own quote.
    function test_Leg3_NoNativeIncomeStillRebirthsInTheOldQuote() public {
        vm.deal(address(hook), 0);          // no native reserve
        hook.setEthReserve(0);

        (address q, uint256 amt,) = PoolOps.seedFunding(
            address(hook),
            NATIVE,          // proposal wants ETH
            address(usdg),   // dying generation is USDG
            3_000e6,         // and all we hold is USDG
            address(0)
        );
        assertEq(q, address(usdg), "reborn in the old quote rather than frozen");
        assertEq(amt, 3_000e6, "with the recovered USDG");
    }

    /// @notice The native path still works exactly as before — the common case must
    ///         not have been disturbed by any of this.
    function test_NativePathUnchanged() public {
        hook.setEthReserve(2 ether);

        (address q, uint256 amt,) = PoolOps.seedFunding(
            address(hook), NATIVE, NATIVE, 5 ether, address(0)
        );
        assertEq(q, NATIVE, "native");
        assertEq(amt, 7 ether, "recovery + the hook's native reserve");
    }

    /// @notice TOTALITY: a hook that reverts on BOTH reserve pulls must not take the
    ///         rebirth down with it. `seedFunding` runs after `markConsumed` in some
    ///         orderings and is on the mandatory path in all of them, so it must
    ///         never revert for any reason.
    function test_TOTAL_HostileHookCannotRevertTheDecision() public {
        hook.setHostile(true);

        (address q, uint256 amt,) = PoolOps.seedFunding(
            address(hook), address(usdg), NATIVE, 4 ether, address(0)
        );
        assertEq(q, NATIVE, "still decides");
        assertEq(amt, 4 ether, "still funds, from the recovery alone");
    }

    /// @notice TOTALITY: a floor vault whose `close()` reverts is caught here too
    ///         (the try/catch moved into this helper for EIP-170 headroom).
    function test_TOTAL_HostileVaultCannotRevertTheDecision() public {
        (address q, uint256 amt, uint256 swept) = PoolOps.seedFunding(
            address(hook), NATIVE, NATIVE, 6 ether, address(new RevertingVault())
        );
        assertEq(q, NATIVE, "still decides");
        assertEq(amt, 6 ether, "recovery survives the failed sweep");
        assertEq(swept, 0, "and the sweep reports zero rather than reverting");
    }

    /// @notice Nothing to seed with reports ZERO rather than reverting. The caller
    ///         turns that into `NoLiquidityToSeed` on the SAFE side of
    ///         `markConsumed`, where a revert is recoverable.
    function test_NothingToSeedReturnsZero() public {
        vm.deal(address(hook), 0);
        hook.setEthReserve(0);

        (, uint256 amt,) = PoolOps.seedFunding(address(hook), NATIVE, NATIVE, 0, address(0));
        assertEq(amt, 0, "reports zero, does not revert");
    }

    /// @dev PoolOps is delegatecalled, so the hook's native release pays THIS
    ///      contract. Without a payable receiver the send fails, the try/catch
    ///      swallows it, and the reserve silently reads as zero — which is how
    ///      `test_NativePathUnchanged` first failed.
    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════
//  Walls 2 + 3 — the real seed path, against a 6-decimal quote, on a fork.
// ═══════════════════════════════════════════════════════════════════════════

contract B08_NonEthSeedFork is Test {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    bool internal active;
    IPoolManager internal pm;
    address internal posm;
    CauldronHook internal hook;
    Usdg6 internal usdg;

    /// @dev The hook reads this at adoption. This contract IS the registry here,
    ///      which is also what makes the delegatecalled PoolOps run in our context.
    function allowedQuote(address q) external view returns (bool) {
        return q == address(usdg) || q == address(0);
    }

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);

        address poolManager = vm.envAddress("POOL_MANAGER");
        posm = vm.envAddress("POSITION_MANAGER");
        pm = IPoolManager(poolManager);

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG
                | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.AFTER_SWAP_FLAG
                | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs = abi.encode(
            IPoolManager(poolManager), uint256(1 ether), address(0), address(this), address(this)
        );
        (, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(poolManager), 1 ether, address(0), address(this), address(this)
        );
        hook.setRegistry(address(this));
        hook.setOpener(address(this), true);
        hook.setTaxExempt(address(this), true);

        usdg = new Usdg6();
        vm.deal(address(this), 100 ether);
    }

    /// @notice WALL 3 — the whole non-native seed, end to end, through the REAL
    ///         `createAndSeedWithBuy`: initialize a USDG-quoted pool, mint the
    ///         active position, run the green-candle exact-output buy (which now
    ///         settles USDG rather than ether), and park the reserve out of range.
    ///
    ///  Pre-fix this reverted `CurrencyNotSettled()` inside the unlock, because
    ///  `executeBuy` paid `settle{value:}` against an ERC20 currency0.
    function test_Wall3_UsdgSeedAndGreenCandleSettles() public {
        vm.skip(!active);

        (address token,) =
            PoolOps.deployTokenAbove("Gnome", "GNOME", 2, 777_000_000e18, address(usdg));

        // Fund the "registry" in the quote's OWN units: 50,000 USDG at 6 decimals.
        // Note the figure — 50_000e6, not 50_000e18. Seeding in native units is
        // exactly what made the old path off by 1e12.
        uint256 seedUsdg = 50_000e6;
        usdg.mint(address(this), seedUsdg);

        _armUnlock();
        SeedResult memory r = PoolOps.createAndSeedWithBuy(
            pm, IPositionManagerOps(posm), address(hook),
            token,
            60_000_000e18,   // active tokens
            seedUsdg,        // quote amount, in USDG units
            40_000_000e18,   // reserve tokens (bought by the green candle)
            200, 0, 6000,
            address(usdg)    // THE QUOTE
        );
        _disarmUnlock();

        assertTrue(r.activePositionId != 0, "active position minted against USDG");
        assertTrue(r.reservePositionId != 0, "reserve parked out of range");

        (uint160 sp,,,) = pm.getSlot0(r.poolId);
        assertGt(sp, 0, "the USDG-quoted pool is initialised and live");
        assertEq(
            Currency.unwrap(r.key.currency0), address(usdg), "quote sits at currency0"
        );
        assertEq(Currency.unwrap(r.key.currency1), token, "token sits at currency1");
    }

    /// @notice WALL 2 — recovery is measured on the QUOTE side. Seed a USDG pool,
    ///         tear the active position down, and assert the returned figure is the
    ///         USDG actually received.
    ///
    ///  Pre-fix this returned 0, because `removeAll` measured
    ///  `address(this).balance` and an ERC20 quote never touches it — so
    ///  `relaunch()` summed zero and reverted `NoLiquidityToSeed()`, rolling back
    ///  `markConsumed`. A fourth wall, hidden behind the other three.
    function test_Wall2_RemoveAllRecoversTheQuoteSide() public {
        vm.skip(!active);

        (address token,) =
            PoolOps.deployTokenAbove("Wraith", "WRAITH", 3, 777_000_000e18, address(usdg));

        uint256 seedUsdg = 20_000e6;
        usdg.mint(address(this), seedUsdg);

        _armUnlock();
        SeedResult memory r = PoolOps.createAndSeedWithBuy(
            pm, IPositionManagerOps(posm), address(hook),
            token, 30_000_000e18, seedUsdg, 10_000_000e18, 200, 0, 6000, address(usdg)
        );
        _disarmUnlock();

        uint256 usdgBefore = usdg.balanceOf(address(this));
        uint256 ethBefore = address(this).balance;

        (uint256 quoteRecovered, uint256 tokensRecovered) =
            PoolOps.removeAll(IPositionManagerOps(posm), r.activePositionId, r.key, token);

        assertGt(quoteRecovered, 0, "the QUOTE side must be reported, not zero");
        assertEq(
            usdg.balanceOf(address(this)) - usdgBefore,
            quoteRecovered,
            "and it must equal the USDG actually received"
        );
        assertEq(address(this).balance, ethBefore, "no ether moved - it never does here");
        assertGt(tokensRecovered, 0, "token side still reported");
    }

    // ── unlock plumbing: PoolOps drives the green candle through our callback ──
    bool private _unlocked;

    function _armUnlock() private { _unlocked = true; }
    function _disarmUnlock() private { _unlocked = false; }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "not pm");
        require(_unlocked, "not armed");
        return PoolOps.executeBuy(data);
    }

    receive() external payable {}
}

// ═══════════════════════════════════════════════════════════════════════════
//  Stubs
// ═══════════════════════════════════════════════════════════════════════════

/// @dev Stands in for the hook's two registry-gated relaunch reserves.
contract HookReserveStub {
    mapping(address => uint256) public assetReserve;
    uint256 public ethReserve;
    bool public hostile;

    error NoETHToRelease();

    function setAssetReserve(address a, uint256 v) external { assetReserve[a] = v; }
    function setEthReserve(uint256 v) external { ethReserve = v; }
    function setHostile(bool v) external { hostile = v; }

    function relaunchETH() external view returns (uint256) { return ethReserve; }

    function releaseRelaunchETH() external returns (uint256 amount) {
        if (hostile) revert("hostile");
        amount = ethReserve;
        if (amount == 0) revert NoETHToRelease(); // mirrors the real hook
        ethReserve = 0;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "send");
    }

    function releaseRelaunchAsset(address asset) external returns (uint256 amount) {
        if (hostile) revert("hostile");
        amount = assetReserve[asset];
        if (amount == 0) revert NoETHToRelease();
        assetReserve[asset] = 0;
        IERC20(asset).transfer(msg.sender, amount);
    }

    receive() external payable {}
}

/// @dev A floor vault that refuses to close.
contract RevertingVault {
    function close() external pure returns (uint256) { revert("vault: no"); }
}
