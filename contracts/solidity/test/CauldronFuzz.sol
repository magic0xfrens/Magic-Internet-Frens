// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {FrenBase} from "./fren-review/FrenBase.sol";
import {YNoFrens} from "./attacks/YBase.sol";
import {PerpEngine} from "../cauldron/PerpEngine.sol";

interface IPositionLiquidity {
    function getPositionLiquidity(uint256 tokenId) external view returns (uint128);
}

/// Buys during the harness's constructor. The PoolManager calls back whoever
/// unlocked it, and a contract under construction has no code to answer, so the
/// setup buys go through this helper instead.
contract FuzzSetupBuyer is IUnlockCallback {
    IPoolManager internal immutable pm;

    constructor(IPoolManager _pm) { pm = _pm; }

    function buy(PoolKey calldata key, address to) external payable {
        pm.unlock(abi.encode(key, to, msg.value));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(pm), "pm");
        (PoolKey memory key, address to, uint256 ethIn) = abi.decode(data, (PoolKey, address, uint256));
        BalanceDelta d = pm.swap(key, SwapParams({zeroForOne: true, amountSpecified: -int256(ethIn), sqrtPriceLimitX96: 4295128740}), "");
        pm.settle{value: uint256(uint128(-d.amount0()))}();
        pm.take(key.currency1, to, uint256(uint128(d.amount1())));
        return "";
    }
}

/// @title Fren Review fuzz harness — IMD fuzz campaigns
///
/// IMD's `fuzz` template runs this contract's `prop_` functions with
/// `forge test --fuzz-runs <runs>` through a generated wrapper
/// (`test/ImdFuzzCampaign.t.sol`, `harness = new CauldronFuzz()`), so:
/// - the constructor boots the whole protocol once, on a local v4 PoolManager
///   with no fork and no RPC, and every run starts again from that state;
/// - a `prop_` reverts ONLY when a property breaks (the revert string names it);
///   an action the protocol legitimately refuses is caught and skipped;
/// - every `prop_` takes arguments, so the fuzzer has something to vary.
///
/// The properties are the whole-system guarantees of
/// test/invariants/CauldronSystemInvariants.t.sol, turned into bounded action
/// sequences that run offline.
contract CauldronFuzz is FrenBase {
    using StateLibrary for *;
    using PoolIdLibrary for PoolKey;

    uint256 internal constant Q96 = 0x1000000000000000000000000;
    uint256 internal constant ACTIONS = 10;
    uint256 internal constant CLAIM_DUST = 1e12;
    address[3] internal actors;

    constructor() {
        _boot(25 ether, 50); // 50 genesis frens: the reserve has claims to back
        actors = [trader, attacker, victim];

        // Perps on the live generation, funded by REAL buys: `deal` would move
        // totalSupply and falsify the supply property.
        perp = new PerpEngine(
            pm, address(hook), address(registry), address(new YNoFrens()), address(0xD1D1), address(0x7E7E), address(this)
        );
        hook.setPerpEngine(address(perp));
        perp.fundPlv{value: 5 ether}(5 ether);
        FuzzSetupBuyer buyer = new FuzzSetupBuyer(pm);
        buyer.buy{value: 2 ether}(_key(), address(this));
        uint256 bag = IERC20(token).balanceOf(address(this));
        IERC20(token).approve(address(perp), bag);
        perp.fundPlvToken(bag);
        for (uint256 i; i < 3; i++) buyer.buy{value: 1 ether}(_key(), actors[i]);
        hook.setDeathThreshold(0, address(0), 0, 0, 0); // keep the brew alive so opens are reachable
        _warp(25 hours);                                  // past the open warmup
        vm.roll(block.number + 40);                       // past the anti-snipe surtax window
        perp.poke();
    }

    // ── properties ─────────────────────────────────────────────────────────

    /// P1: a round trip never profits. Buy with `ethIn`, sell every token back in
    /// `chunks` slices in the same block: the trader cannot end with more ETH.
    function prop_roundTripNeverProfits(uint256 ethIn, uint8 chunks) external {
        ethIn = bound(ethIn, 0.0001 ether, 20 ether);
        uint256 n = bound(chunks, 1, 4);
        uint256 before = address(this).balance;
        uint256 got;
        try this.doBuy(ethIn, address(this)) returns (uint256 g) { got = g; } catch { return; }
        uint256 sold;
        for (uint256 i; i < n; i++) {
            uint256 slice = i + 1 == n ? got - sold : got / n;
            if (slice == 0) continue;
            try this.doSell(slice, address(this)) { sold += slice; } catch {}
        }
        require(address(this).balance <= before, "P1: a buy-then-sell round trip returned more ETH than it cost");
        _checkAccounting();
    }

    /// P2: trading keeps the books. Ten seeded actions (buys, sells, exact-output
    /// buys, time) by three wallets; after each: fixed supply, the hook's ETH
    /// obligations are held, and the reserve covers the genesis claims.
    function prop_tradingKeepsAccounting(uint256 seed, uint96 size) external {
        for (uint256 i; i < ACTIONS; i++) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            address who = actors[r % 3];
            uint256 amt = bound(uint256(keccak256(abi.encode(size, i))), 0.0001 ether, 15 ether);
            uint256 op = (r >> 8) % 4;
            if (op == 0) {
                try this.doBuy(amt, who) {} catch {}
            } else if (op == 1) {
                uint256 bal = IERC20(token).balanceOf(who);
                if (bal > 0) try this.doSell(bound(r >> 16, 1, bal), who) {} catch {}
            } else if (op == 2) {
                uint256 want = bound(r >> 16, 1e18, 5_000_000e18);
                uint256 before = IERC20(token).balanceOf(who);
                try this.doBuyExactOut(want, who) {
                    require(IERC20(token).balanceOf(who) - before == want, "P2: an exact-output buy delivered a different amount");
                } catch {}
            } else {
                _warp(bound(r >> 16, 1, 2 days));
                vm.roll(block.number + bound(r >> 32, 1, 400));
            }
            _checkAccounting();
        }
    }

    /// P3: perps stay solvent. Ten seeded actions (opens of either side at 1–3x,
    /// price swings, time, liquidations, closes); after each the engine holds
    /// every wei and token it books.
    function prop_perpsStaySolvent(uint256 seed, uint96 size) external {
        uint256[] memory ids = new uint256[](ACTIONS);
        uint256 open;
        for (uint256 i; i < ACTIONS; i++) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            uint256 amt = bound(uint256(keccak256(abi.encode(size, i))), 0.005 ether, 1 ether);
            uint8 lev = uint8(bound(r >> 8, 1, 3));
            uint256 op = (r >> 16) % 6;
            if (op == 0 || op == 1) {
                try this.doOpen(op == 0, lev, amt) returns (uint256 id) { ids[open++] = id; } catch {}
            } else if (op == 2) {
                try this.doBuy(amt * 20, attacker) {} catch {}
            } else if (op == 3) {
                uint256 bal = IERC20(token).balanceOf(attacker);
                if (bal > 0) try this.doSell(bound(r >> 24, 1, bal), attacker) {} catch {}
            } else if (op == 4) {
                _warp(bound(r >> 24, 60, 3 days));
                vm.roll(block.number + 50);
                try perp.poke() {} catch {}
            } else if (open > 0) {
                uint256 id = ids[(r >> 24) % open];
                if ((r >> 32) % 2 == 0) try perp.liquidate(id) {} catch {}
                else try this.doClose(id) {} catch {}
            }
            _checkPerp();
            _checkAccounting();
        }
    }

    // ── the checks ─────────────────────────────────────────────────────────

    function _checkAccounting() internal view {
        require(IERC20(token).totalSupply() == registry.TOTAL_SUPPLY(), "I-1: the live token's supply moved");
        uint256 owedEth = hook.relaunchETH() + (hook.legacyBufferAsset() == address(0) ? hook.legacyBuffer() : 0);
        require(address(hook).balance >= owedEth, "I-6: the hook owes more ETH than it holds");

        uint256 g = registry.currentGeneration();
        uint256 rid = registry.generationReservePositionId(g);
        if (rid != 0) {
            int24 lo = registry.reserveTickLower(g);
            int24 hi = registry.reserveTickUpper(g);
            (, int24 tick,,) = pm.getSlot0(_key().toId());
            if (tick > hi) { // the band is fully below spot: pure token
                uint128 L = IPositionLiquidity(posm).getPositionLiquidity(rid);
                uint256 held = FullMath.mulDiv(
                    uint256(L), uint256(TickMath.getSqrtPriceAtTick(hi)) - uint256(TickMath.getSqrtPriceAtTick(lo)), Q96
                );
                //  Liquidity units round down, so the position can sit a few wei under
                //  its claims; the protocol tolerates PoolOps.CLAIM_DUST (1e12) per claim.
                require(held + CLAIM_DUST >= registry.genesisReserveOutstanding(), "I-3: the reserve holds less than the genesis claims");
            }
        }
    }

    function _checkPerp() internal view {
        require(
            address(perp).balance >= perp.plv() + perp.insuranceEth() + perp.tokYieldEth(),
            "I-5: the perp engine books more ETH than it holds"
        );
        require(IERC20(token).balanceOf(address(perp)) >= perp.plvToken(), "I-5: the perp engine books more tokens than it holds");
    }

    // ── self-call wrappers, so a refused action can be caught ────────────────

    modifier onlySelf() { require(msg.sender == address(this), "self"); _; }

    function doBuy(uint256 ethIn, address to) external onlySelf returns (uint256) { return _buy(ethIn, to); }
    function doSell(uint256 tokenIn, address payer) external onlySelf returns (uint256) { return _sell(tokenIn, payer); }
    function doBuyExactOut(uint256 tokenOut, address to) external onlySelf returns (uint256) { return _buyExactOut(tokenOut, to); }

    function doOpen(bool isLong, uint8 lev, uint256 collateral) external onlySelf returns (uint256 id) {
        vm.prank(trader);
        id = isLong
            ? perp.openLong{value: collateral}(lev, 0, 0, collateral)
            : perp.openShort{value: collateral}(lev, 0, 0, collateral);
    }

    function doClose(uint256 id) external onlySelf {
        vm.prank(trader);
        perp.close(id, 0);
    }
}
