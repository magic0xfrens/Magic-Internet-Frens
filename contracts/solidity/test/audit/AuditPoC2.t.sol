// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";

import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronToken} from "../../CauldronToken.sol";
import {CauldronSeeder} from "../../cauldron/CauldronSeeder.sol";
import {SeederConfig} from "../../cauldron/ISeeder.sol";
import {PoolOps, IPositionManagerOps, SeedResult} from "../../cauldron/PoolOps.sol";
import {CauldronGovernor} from "../../cauldron/CauldronGovernor.sol";
import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {MiFrensDividend} from "../../cauldron/MiFrensDividend.sol";
import {MetadataMode, BrewSpec} from "../../cauldron/ICauldron.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ───────────────────────────────────────────────────────────────────────────────
// PoC 6 — PoolOps.claimFromReserve SILENTLY UNDER-DELIVERS when the reserve
//         position cannot cover the request. `claimByBurn` burns the caller's full
//         `amount` first and never checks that the same amount came back, so the
//         "migration is 1:1" invariant fails on a short reserve (loss of funds).
// ───────────────────────────────────────────────────────────────────────────────
contract PoC_ReserveUnderDelivery is Test {
    using PoolIdLibrary for PoolKey;

    IPoolManager pm;
    IPositionManagerOps posm;
    bool active;

    CauldronToken tok;
    SeedResult r;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);
        pm = IPoolManager(vm.envAddress("POOL_MANAGER"));
        posm = IPositionManagerOps(vm.envAddress("POSITION_MANAGER"));
        vm.deal(address(this), 100 ether);
    }

    function test_PoC_ClaimFromReserveCapsInsteadOfReverting() public {
        if (!active) return;

        tok = new CauldronToken("R", "R", 1, address(this), 1_000_000 ether);

        // Seed a pool exactly like the registry does, but with a DELIBERATELY small
        // reserve tranche (100 tokens). PoolOps is delegatecalled, so this contract
        // holds the tokens and owns the position NFTs — same context as the registry.
        r = PoolOps.createAndSeed(
            pm, posm, address(0), address(tok),
            900_000 ether,   // active
            1 ether,         // ETH
            100 ether,       // reserve — the whole migration/genesis backing
            200, 0, 42_400,
            address(0)      // native ETH quote, as before
        );
        assertGt(r.reservePositionId, 0, "reserve placed");

        address claimer = address(0xC1A1);
        uint256 ask = 10_000 ether; // 100x more than the reserve holds

        uint256 taken = PoolOps.claimFromReserve(
            posm, r.reservePositionId, r.key, r.reserveTickLower, r.reserveTickUpper, ask, claimer
        );

        console2.log("requested :", ask);
        console2.log("delivered :", taken);
        console2.log("shortfall :", ask - taken);

        // NO revert, and the caller receives far less than requested. In
        // `CauldronRegistry.claimByBurn` the caller's old-gen tokens were already
        // BURNED for `ask` before this call — the difference is destroyed value.
        assertLt(taken, ask, "BUG: short reserve silently under-delivers");
        assertLe(taken, 101 ether, "delivered at most what the reserve held");
    }

    receive() external payable {}
}

// ───────────────────────────────────────────────────────────────────────────────
// PoC 7 / REGRESSION — CauldronGovernor had no voting deadline, so `winner()` was
//         the LIVE leader and a whale could flip the winning brew by voting in the
//         same block that the permissionless `relaunch()` landed.  (audit M-02)
//         FIXED: a proposal accepts votes for VOTING_PERIOD and only becomes
//         eligible to win once that window has CLOSED.
// ───────────────────────────────────────────────────────────────────────────────
contract PoC_GovernorLiveWinner is Test {
    MiFrensGenesis presale;
    CauldronGovernor gov;

    address honest = address(0xA11CE);
    address whale = address(0xB0B);

    function setUp() public {
        presale = new MiFrensGenesis("MiFrens", "MIFREN", 100, 200, 0.01 ether, 100, "ipfs://");
        gov = new CauldronGovernor(address(presale));
        gov.setRegistry(address(this));

        vm.deal(honest, 10 ether);
        vm.deal(whale, 100 ether);
        vm.prank(honest);
        presale.mint{value: 0.01 ether}(1);
        vm.prank(whale);
        presale.mint{value: 0.5 ether}(50);
        vm.roll(block.number + 1);
    }

    function test_Fixed_WinnerCannotBeFrontRun() public {
        vm.prank(honest);
        uint256 idHonest = gov.propose("Good", "GOOD", MetadataMode.BaseURI, "ipfs://g/", address(0), "", "", 0, 0, address(0));
        vm.prank(whale);
        uint256 idWhale = gov.propose("Rug", "RUG", MetadataMode.BaseURI, "ipfs://r/", address(0), "", "", 0, 0, address(0));

        vm.roll(block.number + 1);
        vm.prank(honest);
        gov.vote(idHonest);

        // FIXED: while voting is OPEN, nothing is launchable at all — so there is
        // no window in which a last-instant vote can decide a live relaunch.
        assertFalse(gov.hasProposals(), "FIXED: an open proposal can never be launched");
        vm.expectRevert(CauldronGovernor.NoProposals.selector);
        gov.winner();

        // The whale casts their vote DURING the window, in the open, where the
        // guild can see and respond to it.
        vm.prank(whale);
        gov.vote(idWhale);

        // Once the window closes the result is FROZEN...
        vm.warp(vm.getBlockTimestamp() + gov.VOTING_PERIOD() + 1);
        (uint256 winId, BrewSpec memory spec) = gov.winner();
        assertEq(winId, idWhale, "the settled result stands");
        assertEq(spec.proposer, whale);

        // ...and can no longer be changed by anyone front-running the relaunch.
        vm.prank(honest);
        vm.expectRevert(CauldronGovernor.VotingClosed.selector);
        gov.vote(idHonest);
        (uint256 stillWinId,) = gov.winner();
        assertEq(stillWinId, winId, "FIXED: the winner is immutable once voting closes");
    }
}

// ───────────────────────────────────────────────────────────────────────────────
// PoC 8 / REGRESSION — a FORGED (volume-minted) fren used to keep its enchantment
//         when transferred, because MiFrensGenesis only pinged the dividend for
//         ids <= GENESIS_SUPPLY. The share kept diluting everyone while nobody
//         could claim it, and the PREVIOUS owner was later credited the NEW
//         owner's earnings.                                        (audit M-06)
//         FIXED: `_update` notifies the dividend on every transfer; the hook is
//         already a safe no-op for an un-enchanted id.
// ───────────────────────────────────────────────────────────────────────────────
contract PoC_ForgedFrenSpellLeak is Test {
    MiFrensGenesis mifrens;
    MiFrensDividend div;

    address og = address(0x0611);
    address seller = address(0x5E11);
    address buyer = address(0xB111);
    address treasury = address(0x7777);

    function setUp() public {
        mifrens = new MiFrensGenesis("MiFrens", "MIFREN", 2, 6, 0.01 ether, 100, "ipfs://");
        div = new MiFrensDividend(address(mifrens), treasury);
        mifrens.setDividend(address(div));

        vm.deal(og, 1 ether);
        vm.deal(seller, 1 ether);
        vm.prank(og);
        mifrens.mint{value: 0.02 ether}(2); // ids 1,2 (genesis tranche, sold out)

        // Iteration #2 continues the collection: the hook becomes the minter.
        mifrens.setMinter(address(this));
        mifrens.mint(seller); // id 3 — a FORGED fren
        vm.deal(address(this), 100 ether);
    }

    function test_Fixed_ForgedFrenTransferBreaksTheSpell() public {
        vm.prank(og);
        div.castSpell(1);
        vm.prank(seller);
        div.castSpell(3);
        assertEq(div.activeShares(), 2, "two enchanted frens");

        // Sell the forged fren on the open market.
        vm.prank(seller);
        mifrens.transferFrom(seller, buyer, 3);

        // FIXED A: the share is released the moment the fren moves, so it stops
        // diluting every honest holder.
        assertEq(div.activeShares(), 1, "FIXED: the sold fren left the earning set");
        assertEq(div.enchantedBy(3), address(0), "FIXED: enchantment cleared on transfer");

        // Fees arrive. ALL of them now accrue to the one genuinely-enchanted fren.
        (bool ok,) = address(div).call{value: 2 ether}("");
        assertTrue(ok);
        assertEq(div.pending(1), 2 ether, "FIXED: no phantom share dilutes the OG");

        // FIXED B: the seller earns nothing after the sale — they are settled up to
        // the exact moment of transfer and no further.
        assertEq(div.owed(seller), 0, "FIXED: seller banked only what they earned");

        // FIXED C: the buyer re-casts and earns from THAT point on, and the seller
        // can never be credited the buyer's accrual.
        vm.prank(buyer);
        div.castSpell(3);
        assertEq(div.activeShares(), 2, "buyer rejoined the earning set");
        (ok,) = address(div).call{value: 2 ether}("");
        assertTrue(ok);
        assertEq(div.pending(3), 1 ether, "FIXED: buyer earns their own share");
        assertEq(div.owed(seller), 0, "FIXED: seller is credited nothing further");
    }

    receive() external payable {}
}

// ───────────────────────────────────────────────────────────────────────────────
// PoC 9 / REGRESSION — `setRegistryOverride` defeated the one-time `setRegistry`
//         lock (whose own comment explains exactly why that lock exists), letting
//         the hook owner re-point `registry` at an address they control and pull
//         the whole `relaunchETH` reserve.                        (audit M-01)
//         FIXED: the swap is now announced on-chain, waits REGISTRY_SWAP_DELAY,
//         and FLUSHES the reserve to the OUTGOING registry before handing over.
// ───────────────────────────────────────────────────────────────────────────────
contract PoC_RegistryOverrideDrain is Test {
    IPoolManager pm;
    CauldronHook hook;
    bool active;

    address attacker = address(0xBAD);
    address constant REAL_REGISTRY = address(0x11111);

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);
        pm = IPoolManager(vm.envAddress("POOL_MANAGER"));

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG
                | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(pm)), uint256(1 ether), address(0), address(this), address(this));
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(address(pm)), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == hookAddr, "hook addr");
        hook.setRegistry(REAL_REGISTRY); // the REAL registry, "locked forever"
    }

    function test_Fixed_RegistryOverrideIsTimelocked() public {
        if (!active) return;

        // setRegistry is still one-shot ...
        vm.expectRevert(CauldronHook.RegistryAlreadySet.selector);
        hook.setRegistry(attacker);

        // ... and the override no longer takes effect immediately.
        hook.proposeRegistryOverride(attacker);
        assertEq(hook.registry(), REAL_REGISTRY, "FIXED: controller unchanged on propose");
        assertEq(hook.pendingRegistry(), attacker, "the swap is announced on-chain");

        // Executing early is refused.
        vm.expectRevert(CauldronHook.RegistryAlreadySet.selector);
        hook.executeRegistryOverride();
        assertEq(hook.registry(), REAL_REGISTRY, "FIXED: still unchanged");

        // The announcement can be cancelled outright (guardian-style abort).
        hook.cancelRegistryOverride();
        assertEq(hook.pendingRegistry(), address(0), "swap aborted");
        vm.expectRevert(CauldronHook.ZeroAddress.selector);
        hook.executeRegistryOverride();

        // A legitimate, fully-announced swap DOES flush the reserve to the OUTGOING
        // registry first, so the successor can never capture what it did not earn.
        hook.proposeRegistryOverride(attacker);
        vm.warp(vm.getBlockTimestamp() + hook.REGISTRY_SWAP_DELAY() + 1);
        hook.executeRegistryOverride();
        assertEq(hook.registry(), attacker, "swap completes only after the delay");
        assertEq(hook.relaunchETH(), 0, "FIXED: reserve flushed to the old registry");
    }

    receive() external payable {}
}

// ───────────────────────────────────────────────────────────────────────────────
// PoC 10 — CauldronSeeder MAX_RANGES: an actively-moving price makes every poke
//          open two NEW tracked ranges. Once 64 are tracked, `_track` reverts and
//          the stream halts permanently for that generation.
// ───────────────────────────────────────────────────────────────────────────────
contract PoC_SeederBandCap is Test, IUnlockCallback {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    IPoolManager pm;
    address posm;
    bool active;

    CauldronToken tok;
    CauldronSeeder seeder;
    PoolKey key;

    uint160 constant MIN_SQRT_LIMIT = 4295128740;
    uint160 constant MAX_SQRT_LIMIT = 1461446703485210103287273052203988822378723970341;
    uint256 constant ACTIVE_ETH = 40 ether;
    uint256 constant ACTIVE_TOK = 100_000_000 ether;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);
        pm = IPoolManager(vm.envAddress("POOL_MANAGER"));
        posm = vm.envAddress("POSITION_MANAGER");

        tok = new CauldronToken("S", "S", 1, address(this), 1_000_000_000 ether);
        seeder = new CauldronSeeder(address(this), posm, address(pm));
        key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(tok)),
            fee: 0, tickSpacing: 200, hooks: IHooks(address(0))
        });
        pm.initialize(key, _sqrtPriceFor(ACTIVE_TOK, ACTIVE_ETH));
        vm.deal(address(this), 5000 ether);

        tok.approve(address(seeder), ACTIVE_TOK);
        seeder.startSeed{value: ACTIVE_ETH}(SeederConfig({
            key: key, token: address(tok), gen: 1,
            spacing: 200, bandWidth: 2000,
            window: 36_000, seedFloorWad: 0.02e18, minStepWad: 0, // no throttle
            baseWad: 0.15e18,
            ethTotal: ACTIVE_ETH, tokenTotal: ACTIVE_TOK
        }));
    }

    function test_PoC_RangeSetFillsAndStreamHalts() public {
        if (!active) return;

        uint256 startTs = block.timestamp;
        bool halted;
        uint256 i;
        for (i = 0; i < 60; i++) {
            vm.warp(startTs + 300 * (i + 1));
            // move the price a full band each round (a real launch does this on its own)
            // MONOTONIC walk: every round pushes the tick further in one direction,
            // so each poke lands on a fresh (tickLower,tickUpper) pair.
            _trade(true, 30 ether);
            try seeder.poke() {
                // keep going
            } catch {
                halted = true;
                break;
            }
        }
        console2.log("pokes before halt :", i);
        console2.log("tracked ranges    :", seeder.rangeCount());
        console2.log("deployedWad       :", seeder.deployedWad());
        assertLe(seeder.rangeCount(), 64, "range set is capped");
        if (halted) {
            console2.log("BUG: poke() reverted with BandCap; the stream is stuck.");
            assertLt(seeder.deployedWad(), 1e18, "stream halted before completing");
        }
    }

    function _trade(bool buy, uint256 amt) internal {
        try this.doTrade(buy, amt) {} catch {}
    }
    function doTrade(bool buy, uint256 amt) external {
        pm.unlock(abi.encode(buy, amt));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        (bool buy, uint256 amt) = abi.decode(data, (bool, uint256));
        BalanceDelta d = pm.swap(
            key,
            SwapParams({
                zeroForOne: buy,
                amountSpecified: -int256(amt),
                sqrtPriceLimitX96: buy ? MIN_SQRT_LIMIT : MAX_SQRT_LIMIT
            }),
            ""
        );
        int128 a0 = d.amount0();
        int128 a1 = d.amount1();
        if (a0 < 0) pm.settle{value: uint256(uint128(-a0))}();
        else if (a0 > 0) pm.take(key.currency0, address(this), uint256(uint128(a0)));
        if (a1 < 0) { pm.sync(key.currency1); tok.transfer(address(pm), uint256(uint128(-a1))); pm.settle(); }
        else if (a1 > 0) pm.take(key.currency1, address(this), uint256(uint128(a1)));
        return "";
    }

    function _sqrtPriceFor(uint256 amt1, uint256 amt0) internal pure returns (uint160) {
        uint256 ratioX192 = (amt1 << 192) / amt0;
        return uint160(_sqrt(ratioX192));
    }
    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2; y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
    }
    receive() external payable {}
}
