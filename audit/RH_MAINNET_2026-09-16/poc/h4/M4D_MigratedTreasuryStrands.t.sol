// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {YBase} from "./YBase.sol";
import {console2} from "forge-std/console2.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

contract D4Quote {
    string public name = "D4USD";
    string public symbol = "D4USD";
    uint8 public decimals = 6;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    event Transfer(address indexed f, address indexed t, uint256 v);
    event Approval(address indexed o, address indexed s, uint256 v);
    function mint(address to, uint256 a) external { balanceOf[to] += a; totalSupply += a; emit Transfer(address(0), to, a); }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; emit Transfer(msg.sender, to, a); return true;
    }
    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a; emit Approval(msg.sender, s, a); return true;
    }
    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= a;
        balanceOf[f] -= a; balanceOf[to] += a; emit Transfer(f, to, a); return true;
    }
}

contract D4Gov {
    address public q;
    uint16 public remaining = 10_000;
    bool public spent;
    function setEnvelope(address _q, uint16 _r) external { q = _q; remaining = _r; }
    function setSpent(bool s) external { spent = s; }
    function allowance() external view returns (address, uint16) { return (q, remaining); }
    function consume(uint16, bool) external {}
    function migrationMandateSpent() external view returns (bool) { return spent; }
}

/// @dev Stand-in venue: takes the ETH leg and hands back the destination quote at
///      a fixed 3000 USD/ETH. Mechanically identical to a real curated venue for
///      the purpose of this test — the value moves, the rotation completes.
contract D4Rotator {
    D4Quote public usd;
    uint256 public lastOut;
    constructor(D4Quote u) { usd = u; }
    function swapOnce(PoolKey calldata, address, address, uint256 amountIn, uint256)
        external returns (uint256 out)
    {
        out = (amountIn * 3000) / 1e12;   // wei(18) -> USD(6) at $3000/ETH
        usd.mint(address(this), out);
        lastOut = out;
    }
    function withdraw(address, address to, uint256 amount) external { usd.transfer(to, amount); }
    receive() external payable {}
}

/**
 * @notice WHAT BREAKS AFTER A GUILD-APPROVED QUOTE MIGRATION COMPLETES.
 *
 *  Runs the real `RedemptionExt.rotateSliceFrom` path end to end: liquidity
 *  leaves the ETH primary, the destination pair is opened through the hook's
 *  adoption gate, the leg is recorded, and `generationQuote[gen]` flips
 *  (RedemptionExt.sol:581-582). Then it relaunches and asks where the migrated
 *  treasury went.
 */
contract M4D_MigratedTreasuryStrands is YBase {
    struct Res {
        bool booted;
        bool sliceOk;
        bytes sliceErr;
        address quoteAfter;
        uint256 legUsd;          // USD the leg holds after the rotation
        uint256 relaunchOk;
        uint256 legProceedsUsd;  // USD booked to legProceeds at teardown
        uint256 regUsdBal;
        uint256 gen;
        uint256 swept;
    }

    Res internal R;
    D4Gov internal gov;
    D4Rotator internal rot;
    D4Quote internal usd;

    function setUp() public {
        _boot(25 ether, 0);
        R.booted = active;
    }

    function _key0() internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(registry.currentToken()),
            fee: registry.POOL_FEE(),
            tickSpacing: registry.TICK_SPACING(),
            hooks: IHooks(address(hook))
        });
    }

    function _run() internal {
        if (!R.booted) return;

        usd = new D4Quote();
        gov = new D4Gov();
        rot = new D4Rotator(usd);
        registry.setAllowedQuote(address(usd), true, 1e18);
        registry.setRotationWiring(address(rot), address(gov));

        // The guild voted a FULL-POSITION migration into `usd`.
        gov.setEnvelope(address(usd), 10_000);
        gov.setSpent(true); // this slice completes the mandate

        (R.sliceOk, R.sliceErr) = address(registry).call(
            abi.encodeWithSignature(
                "rotateSliceFrom(uint8,uint16,uint256,(address,address,uint24,int24,address))",
                uint8(0), uint16(2500), uint256(0), _key0()
            )
        );
        if (!R.sliceOk) { console2.log("slice failed"); console2.logBytes(R.sliceErr); return; }

        R.quoteAfter = registry.generationQuote(1);
        R.legUsd = usd.balanceOf(address(registry));
        console2.log("generationQuote[1] after migration", R.quoteAfter);
        console2.log("registry usd LOOSE right after the slice", R.legUsd);
        console2.log("leg pool usd", usd.balanceOf(address(pm)));
        console2.log("rotator converted (USD 6dp)", rot.lastOut());

        // Now the whole lifecycle moves on: the generation dies and is reborn.
        _warp(26 hours);
        assertGt(vm.getBlockTimestamp(), 0, "warp landed");
        (bool ok,) = address(registry).call(abi.encodeWithSignature("relaunch()"));
        R.relaunchOk = ok ? 1 : 0;
        R.gen = registry.currentGeneration();

        (bool okv, bytes memory rv) = address(registry).call(
            abi.encodeWithSignature("legProceedsOf(address)", address(usd))
        );
        if (okv && rv.length >= 32) R.legProceedsUsd = abi.decode(rv, (uint256));
        R.regUsdBal = usd.balanceOf(address(registry));
        (bool oks, bytes memory rs) = address(registry).call(
            abi.encodeWithSignature("sweepLegProceeds(address,address)", address(usd), address(0xDEAD))
        );
        R.swept = (oks && rs.length >= 32) ? abi.decode(rs, (uint256)) : type(uint256).max;
        console2.log("sweepLegProceeds returned (max = call reverted)", R.swept);
        console2.log("0xDEAD usd after sweep", usd.balanceOf(address(0xDEAD)));

        console2.log("relaunch ok", R.relaunchOk);
        console2.log("gen now", R.gen);
        console2.log("legProceeds[usd]", R.legProceedsUsd);
        console2.log("registry usd balance", R.regUsdBal);
        console2.log("gen2 quote", registry.generationQuote(2));
    }

    function test_migrated_treasury_after_rebirth() public {
        _run();
        assertTrue(R.booted, "fork harness must be live");
        assertTrue(R.sliceOk, "the rotation slice must land");
        assertEq(R.quoteAfter, address(usd), "migration must redenominate the generation");
        assertEq(R.relaunchOk, 1, "relaunch must still succeed after a completed migration");
        assertEq(R.gen, 2, "gen must advance");
        // The whole migrated treasury is booked to legProceeds, NOT seeded into
        // the newborn, and the newborn launches back in ETH.
        // Where did the migrated treasury end up?
        assertGt(R.regUsdBal, 0, "the registry holds the migrated destination asset");
        assertTrue(R.swept != type(uint256).max, "sweepLegProceeds must be callable");
        assertEq(registry.generationQuote(2), address(0), "newborn re-launches in ETH");
    }
}
