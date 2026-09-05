// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-periphery/src/libraries/LiquidityAmounts.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ReserveLib} from "./ReserveLib.sol";
import {ISeeder, SeederConfig} from "./ISeeder.sol";
import {CauldronToken} from "../CauldronToken.sol";

/// @dev Progressive-seed knobs the registry passes through to the seeder handoff.
///      Only the launch WINDOW is per-iteration configurable (user requirement);
///      the secondary tuning (floor %, poke throttle, band width) are fixed
///      constants in PoolOps to keep the registry lean under EIP-170.
struct SeedParams {
    address seeder;
    uint256 gen;
    uint64 window;
}

interface IPositionManagerOps {
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
    function nextTokenId() external view returns (uint256);
    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);
}

interface ILedgerOps {
    // Unified live+dead cap table (see CollectionLedger). `mintedNow` =
    // collection.totalMinted() so the floor tracks live gacha mints; ignored once
    // crystallized (frozen supply). `credit` accrues the floor live (buyback +
    // royalty inflow), redeemable immediately.
    function redeem(uint256 gen, uint256 mintedNow) external returns (uint256 payout);
    function buyback(uint256 gen, uint256 mintedNow, uint256 paid) external;
    function floorPerNFT(uint256 gen, uint256 mintedNow) external view returns (uint256);
    function credit(uint256 gen, uint256 tokens) external;
    function crystallize(uint256 gen, uint256 mintedAtDeath, uint256 extraEntitled) external;
    function crystallized(uint256 gen) external view returns (bool);
    function totalEntitled() external view returns (uint256);
}

interface IColMinted {
    function totalMinted() external view returns (uint256);
}
interface IVaultRedeemedOps {
    function redeemed() external view returns (uint256);
    /// @notice NFTs the vault backs = eligible minted − redeemed (excludes genesis).
    function outstanding() external view returns (uint256);
}

interface ICollectionOps {
    function custodyTransfer(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface ILegacyHookOps {
    function sweepLegacyReserve(address token, address to) external returns (uint256);
    function legacyRegistry() external view returns (address);
}

interface ICauldronBurn {
    function burn(address from, uint256 amount) external;
}
interface IAutoFlag {
    function autoMigrate(address who) external view returns (bool);
}

/// @dev The reserve position coordinates for a generation, bundled so the legacy
///      recycle/buyback helpers don't blow the stack.
struct ReserveRef {
    uint256 positionId;
    PoolKey key;
    int24 tickLower;
    int24 tickUpper;
}

interface IPermit2Ops {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

/// @dev Result of creating + seeding a two-position pool.
struct SeedResult {
    PoolId poolId;
    PoolKey key;
    uint256 activePositionId;
    uint256 reservePositionId;
    int24 reserveTickLower;
    int24 reserveTickUpper;
}

/**
 * @title PoolOps
 * @notice EXTERNAL (linked, delegatecall'd) library holding all V4
 *         PositionManager encoding for the Cauldron registry. Extracted so the
 *         registry stays under the EIP-170 24,576-byte limit while gaining the
 *         two-position (active + out-of-range reserve) launch model.
 *
 *  Because these are delegatecall'd, `address(this)` is the REGISTRY: it holds
 *  the tokens/ETH, owns the position NFTs, and is the msg.sender the
 *  PositionManager and Permit2 see. The library holds no state.
 */
library PoolOps {
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Progressive-seed fixed tuning (see SeedParams). Floor 10%, poke throttle 2%.
    // BAND WIDTH of each streamed single-sided mini-band. Narrow = deep near spot =
    // sharp anti-snipe impact (a block-0 whale eats a cliff). NOTE: the progressive
    // book is SINGLE-SIDED (token asks below spot, ETH bids above) — it has NO
    // liquidity straddling the current tick, so the perp engine (which reads spot
    // depth) correctly will NOT open leverage against a progressive generation.
    // Perps belong on ATOMIC (full-range, spot-straddling) generations — progressive
    // is the launch-only anti-snipe mechanic. A huge sell that walks past the bands
    // teleporting toward the 69× reserve is accepted BY DESIGN for spot trading.
    uint256 internal constant SEED_FLOOR_WAD = 0.1e18;
    uint256 internal constant SEED_MINSTEP_WAD = 0.02e18;
    int24 internal constant SEED_BANDWIDTH = 2000;
    // Fraction of ledger A laid ONCE at summon as a two-sided full-range BASE
    // (spot-straddling → perps get depth + the book is continuous → no teleport,
    // smooth liquidations), placed automatically and never removed until relaunch.
    // A full-range spread is thin per tick so it barely dents the single-sided
    // floor's near-spot anti-snipe. 15% is a sane default.
    uint256 internal constant SEED_BASE_WAD = 0.15e18;

    /// @notice The themed creature (token name + symbol) for a generation, cycling
    ///         every 6. Lives HERE (a linked library) rather than the registry so
    ///         its string table doesn't consume the registry's scarce EIP-170
    ///         bytecode. Gen-1 uses this ("Gnomeland/GNOME"); relaunches (gen 2+)
    ///         name from the winning BrewSpec instead, so this is really the gen-1
    ///         + fallback theme. `external pure` → deployed in the lib, delegatecall.
    function creatureFor(uint256 gen) external pure returns (string memory name, string memory symbol) {
        uint256 idx = (gen - 1) % 6;
        if (idx == 0) return ("Gnomeland", "GNOME");
        if (idx == 1) return ("Ethereal Spirit", "SPIRIT");
        if (idx == 2) return ("Shadow Wraith", "WRAITH");
        if (idx == 3) return ("Infernal Beast", "BEAST");
        if (idx == 4) return ("Astral Entity", "ASTRAL");
        return ("Storm Elemental", "STORM");
    }

    /// @dev sqrtPriceLimit floor for a zeroForOne (ETH→token) swap = MIN + 1.
    ///      The relaunch buy is a bounded exact-output, so the limit never binds.
    uint160 internal constant MIN_SQRT_LIMIT = 4295128740; // TickMath.MIN_SQRT_PRICE + 1

    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    /// @dev Approve the PositionManager to pull `amount` of `token` via Permit2.
    function _approve(address token, address pm, uint256 amount) private {
        IERC20(token).approve(PERMIT2, amount);
        IPermit2Ops(PERMIT2).approve(token, pm, uint160(amount), uint48(block.timestamp + 300));
    }

    function _sqrtPrice(uint256 tokenAmount, uint256 ethAmount) private pure returns (uint160) {
        uint256 ratio = FullMath.mulDiv(tokenAmount, 1 << 192, ethAmount);
        // Babylonian sqrt.
        uint256 x = ratio;
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) { y = z; z = (x / z + z) / 2; }
        return uint160(y);
    }

    /**
     * @notice Build the pool, initialize its price from (activeTokens:ETH), and
     *         seed BOTH the active full-range position and the out-of-range
     *         single-sided reserve. One external call keeps the registry lean.
     */
    function createAndSeed(
        IPoolManager poolManager,
        IPositionManagerOps pm,
        address hook,
        address token,
        uint256 activeTokens,
        uint256 ethAmount,
        uint256 reserveTokens,
        int24 tickSpacing,
        uint24 poolFee,
        int24 ceilingOffset,
        /// The asset this pool is PRICED IN (address(0) = native ETH).
        /// Always currency0: the token is deployed to sort above it.
        address quote
    ) external returns (SeedResult memory r) {
        r.key = PoolKey({
            currency0: Currency.wrap(quote),
            currency1: Currency.wrap(token),
            fee: poolFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hook)
        });
        r.poolId = r.key.toId();

        uint160 sqrtPriceX96 = _sqrtPrice(activeTokens, ethAmount);
        poolManager.initialize(r.key, sqrtPriceX96);
        int24 launchTick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        r.activePositionId = _seedActive(quote, pm, r.key, sqrtPriceX96, ethAmount, activeTokens, token, tickSpacing);

        if (reserveTokens > 0) {
            (r.reserveTickLower, r.reserveTickUpper) =
                ReserveLib.reserveTicks(launchTick, tickSpacing, ceilingOffset);
            r.reservePositionId =
                _seedReserve(quote, pm, r.key, r.reserveTickLower, r.reserveTickUpper, reserveTokens, token);
        }
    }

    /**
     * @notice PROGRESSIVE seed: create + init the pool, place the out-of-range
     *         RESERVE (ledger B) exactly as `createAndSeed`, but INSTEAD of one
     *         full-range active position, hand the ACTIVE tranche (ledger A) to the
     *         `seeder`, which streams it in over the launch window (see
     *         CauldronSeeder). Called via delegatecall from the registry, so
     *         `address(this)` is the registry: it holds the tokens + ETH, its token
     *         transfer + the seeder's onlyRegistry both resolve to the registry.
     *
     *  `r.activePositionId` is left 0 — there is no single active position; the
     *  seeder owns N distributed mini-positions, unwound at relaunch via withdrawAll.
     */
    /// @notice PROGRESSIVE seed handoff (see _createAndSeedProgressive doc below).
    ///         Standalone entry — the registry will call this on the progressive
    ///         path once its EIP-170 wiring lands (pending a ~450B reclaim; see
    ///         LAUNCH_LADDER_DESIGN.md). Exercised today by CauldronSeeder's fork
    ///         tests via startSeed; this is the summon-side glue.
    function createAndSeedProgressive(
        IPoolManager poolManager,
        IPositionManagerOps pm,
        address hook,
        address token,
        uint256 activeTokens,
        uint256 ethAmount,
        uint256 reserveTokens,
        int24 tickSpacing,
        uint24 poolFee,
        int24 ceilingOffset,
        SeedParams calldata sp,
        /// The asset this pool is PRICED IN (address(0) = native ETH).
        /// Always currency0: the token is deployed to sort above it.
        address quote
    ) external returns (SeedResult memory r) {
        r.key = PoolKey({
            currency0: Currency.wrap(quote),
            currency1: Currency.wrap(token),
            fee: poolFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hook)
        });
        r.poolId = r.key.toId();

        uint160 sqrtPriceX96 = _sqrtPrice(activeTokens, ethAmount);
        poolManager.initialize(r.key, sqrtPriceX96);
        int24 launchTick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        // Reserve (ledger B) — placed in full, single-sided, out of range. Untouched
        // by the seeder; backs redemption. Identical to createAndSeed.
        if (reserveTokens > 0) {
            (r.reserveTickLower, r.reserveTickUpper) =
                ReserveLib.reserveTicks(launchTick, tickSpacing, ceilingOffset);
            r.reservePositionId =
                _seedReserve(quote, pm, r.key, r.reserveTickLower, r.reserveTickUpper, reserveTokens, token);
        }

        // Ledger A → the seeder. APPROVE the active tokens (the seeder pulls them
        // itself via transferFrom inside startSeed — the single funding path; a
        // separate transfer here would double-spend), then startSeed with the active
        // ETH as value. Both are drawn from the registry (= address(this) under the
        // delegatecall), and `sp.seeder`'s onlyRegistry sees msg.sender = registry.
        IERC20(token).approve(sp.seeder, activeTokens);
        ISeeder(sp.seeder).startSeed{value: ethAmount}(SeederConfig({
            key: r.key, token: token, gen: sp.gen,
            spacing: tickSpacing, bandWidth: SEED_BANDWIDTH,
            window: sp.window, seedFloorWad: SEED_FLOOR_WAD, minStepWad: SEED_MINSTEP_WAD,
            baseWad: SEED_BASE_WAD,
            ethTotal: ethAmount, tokenTotal: activeTokens
        }));
    }

    /**
     * @notice RELAUNCH seed: instead of parking the migration reserve as a silent
     *         single-sided seed, MINT IT INTO EXISTENCE VIA A REAL FIRST-BLOCK BUY.
     *
     *  How the newborn is seeded (all in ONE relaunch tx, so nothing can front-run):
     *    1. Seed the ENTIRE supply (`activeTokens + reserveTokens`) into a
     *       full-range ACTIVE position at a DEEP-DISCOUNT launch price, funded with
     *       only `E_active = ethAmount · activeTokens / totalTokens` of the ETH.
     *    2. Spend the remaining ETH (`E_buy = ethAmount − E_active`) on an
     *       exact-output BUY of EXACTLY `reserveTokens` — a green candle in block 0.
     *    3. Route those bought tokens into the OUT-OF-RANGE reserve (below the
     *       post-buy spot), which backs 1:1 migration + genesis exactly as before.
     *
     *  The constant-product identity `E_active·total = ethAmount·activeTokens` makes
     *  the buy land the active LP at EXACTLY `(activeTokens, ethAmount)` — the same
     *  end-state the old direct-seed produced — but the reserve now arrives as a
     *  real market buy (visible volume) rather than a silent mint. Migration
     *  coverage is byte-for-byte unchanged; only the optics (and the candle) differ.
     *
     *  The caller (registry) MUST be flagged tax-exempt on the hook and must arm its
     *  `unlockCallback` before invoking this (it drives the buy leg).
     */
    function createAndSeedWithBuy(
        IPoolManager poolManager,
        IPositionManagerOps pm,
        address hook,
        address token,
        uint256 activeTokens,
        uint256 ethAmount,
        uint256 reserveTokens,
        int24 tickSpacing,
        uint24 poolFee,
        int24 ceilingOffset,
        /// The asset this pool is PRICED IN (address(0) = native ETH).
        /// Always currency0: the token is deployed to sort above it.
        address quote
    ) external returns (SeedResult memory r) {
        r.key = PoolKey({
            currency0: Currency.wrap(quote),
            currency1: Currency.wrap(token),
            fee: poolFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hook)
        });
        r.poolId = r.key.toId();

        uint256 totalTokens = activeTokens + reserveTokens;

        // E_active floored → the leftover E_buy carries a tiny buffer so the
        // exact-output buy can never revert for want of a wei to settle.
        uint256 ethActive = FullMath.mulDiv(ethAmount, activeTokens, totalTokens);

        // Deep-discount launch price = ALL tokens against only E_active ETH.
        uint160 sqrtPriceX96 = _sqrtPrice(totalTokens, ethActive);
        poolManager.initialize(r.key, sqrtPriceX96);

        // 1. Seed 100% of supply into the active full-range position.
        r.activePositionId = _seedActive(quote, pm, r.key, sqrtPriceX96, ethActive, totalTokens, token, tickSpacing);

        // 2 + 3. Buy the reserve out of the fresh pool, then re-park it out of range.
        if (reserveTokens > 0) {
            // Reserve reseed = EXACT OUTPUT (amtSpecified > 0), kept in the registry
            // (recipient = 0). The leftover ethBuy buffer covers settlement.
            bytes memory ret = poolManager.unlock(abi.encode(r.key, int256(reserveTokens), address(0)));
            uint256 bought = abi.decode(ret, (uint256));

            // Reserve band sits BELOW the POST-BUY spot (pure token1 until a ~69x
            // pump trades into it) — read the settled tick, not the launch tick.
            (, int24 finalTick,,) = poolManager.getSlot0(r.poolId);
            (r.reserveTickLower, r.reserveTickUpper) =
                ReserveLib.reserveTicks(finalTick, tickSpacing, ceilingOffset);
            r.reservePositionId =
                _seedReserve(quote, pm, r.key, r.reserveTickLower, r.reserveTickUpper, bought, token);
        }
    }

    /**
     * @notice The unlock body for the relaunch green-candle buy. Runs in the
     *         REGISTRY's context (delegatecalled from its `unlockCallback`), so
     *         `address(this)` is the registry: it settles the ETH it holds and
     *         receives the bought token. `msg.sender` is the PoolManager.
     *         Exact-output (`amountSpecified > 0`) guarantees EXACTLY `tokenOut`
     *         tokens leave the pool, so the reserve is funded to the wei.
     */
    function executeBuy(bytes calldata data) external returns (bytes memory) {
        // amountSpecified > 0 = EXACT OUTPUT (reserve reseed: exactly `tokenOut` out);
        // amountSpecified < 0 = EXACT INPUT (prime buy: spend exactly `-amt` ETH).
        // recipient == 0 → keep the bought token in the registry (reseed); otherwise
        // send it straight to `recipient` (prime buy → treasury/airdrop wallet).
        (PoolKey memory key, int256 amtSpecified, address recipient) =
            abi.decode(data, (PoolKey, int256, address));
        IPoolManager poolManager = IPoolManager(msg.sender);

        // Tag the swap with the registry (address(this)) so the hook waives every
        // fee + the anti-sniper surtax (registry must be setTaxExempt(true)).
        BalanceDelta delta = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: amtSpecified,
                sqrtPriceLimitX96: MIN_SQRT_LIMIT
            }),
            abi.encode(address(this))
        );

        uint256 ethIn = uint256(uint128(-delta.amount0())); // ETH we owe the pool
        uint256 got = uint256(uint128(delta.amount1()));    // token we're owed

        poolManager.settle{value: ethIn}();          // pay ETH from the registry
        poolManager.take(key.currency1, recipient == address(0) ? address(this) : recipient, got);
        return abi.encode(got);
    }

    /**
     * @notice PRIME BUY — a real, first-block market buy funded by owner-provided
     *         ETH (`ethIn`, held by the registry). The bought token is sent to
     *         `recipient` (the treasury/airdrop wallet) rather than kept as LP, so
     *         it is NET demand (a genuine green candle) with ZERO supply dilution.
     *         Runs in the registry's context (delegatecalled); the registry arms
     *         `_seedBuyUnlocked` around the call so the PoolManager re-entry is
     *         accepted. Exact-INPUT so it spends precisely `ethIn`.
     */
    function primeBuy(IPoolManager poolManager, PoolKey memory key, uint256 ethIn, address recipient)
        external
        returns (uint256 got)
    {
        bytes memory ret = poolManager.unlock(abi.encode(key, -int256(ethIn), recipient));
        got = abi.decode(ret, (uint256));
    }

    /**
     * @notice Deploy a CauldronToken. Delegatecalled from the registry, so
     *         `address(this)` is the registry: the deployer and the token's
     *         `registry`/mint recipient are the registry. The 3.2 KB CauldronToken
     *         creation blob lives in THIS library instead of the registry → keeps
     *         the registry under EIP-170.
     *
     *  PLAIN CREATE, NOT CREATE2 (audit A-01 — Critical). This used to be
     *  `new CauldronToken{salt: bytes32(gen)}(...)`. Every input to that address was
     *  PUBLIC before the deploying transaction existed: the salt is just the next
     *  generation number, the deployer is the registry, and (name, symbol) come from
     *  `governor.winner()` — a public view that is frozen once voting closes. So
     *  anyone could compute the next generation's token address and occupy it first.
     *  CREATE2 into an occupied address fails, `new` reverts on failure, and that
     *  revert propagates out of `relaunch()` — which also rolls back
     *  `governor.markConsumed`, so the SAME proposal wins again and the eternal
     *  machine can never be reborn. A one-transaction, permissionless, permanent
     *  brick of the entire protocol lifecycle.
     *
     *  Plain CREATE is STRUCTURALLY immune: the address derives from
     *  (registry, registry's nonce), and only the registry can advance its own
     *  nonce. To occupy that address an attacker would need a ~2^160 preimage
     *  search on keccak256. Nothing depended on the token address being predictable
     *  — the `predictTokenAddress` helper was already removed as having no callers.
     */
    /// @dev How many salts to try before giving up and launching against ETH.
    ///      Each try is one keccak over ~85 bytes (~40 gas), and the loop exits
    ///      on the FIRST hit — for a quote in the lower half of the address
    ///      space that is the first or second iteration. The bound only matters
    ///      for a pathologically high quote, where it caps the cost instead of
    ///      letting the loop spin.
    uint256 private constant SALT_TRIES = 1024;

    /**
     * @notice Deploy the iteration token at an address that sorts ABOVE `quote`.
     *
     *  WHY. Uniswap v4 orders a pool's currencies by address, and every liquidity
     *  routine below is written for "quote = currency0, token = currency1": the
     *  price is `_sqrtPrice(tokenAmount, quoteAmount)`, the reserve is sized with
     *  `getLiquidityForAmount1`, and the reserve band sits BELOW spot. Native ETH
     *  is `address(0)` so it satisfied that for free. An ERC20 quote does not —
     *  and rather than making every one of those routines correct in two mirrored
     *  orientations, the token is deployed so the ONE audited orientation always
     *  holds.
     *
     *  WHY THIS CANNOT BE FRONT-RUN. The deployer baked into a CREATE2 address is
     *  `address(this)` — and because {PoolOps} is a linked library reached by
     *  DELEGATECALL, that is the REGISTRY. Reproducing this address would require
     *  being the registry, so no third party can occupy it first. This is
     *  deliberately NOT the public deterministic deployer (0x4e59b448…): the
     *  initcode here is fully predictable from the winning proposal, so a
     *  permissionless factory would let anyone deploy the address first and make
     *  `relaunch()` revert — which rolls back `markConsumed`, re-elects the same
     *  proposal, and bricks the machine (audit C-02 class).
     *
     *  WHY IT CANNOT BE BRICKED. If no salt in `SALT_TRIES` lands above the quote,
     *  this does NOT revert — it deploys unmined and reports `address(0)`, so the
     *  caller launches the generation against ETH. A quote that is merely awkward
     *  costs the brew its chosen pair, never its existence.
     *
     * @param quote The intended quote asset. `address(0)` (native ETH) needs no
     *              mining at all: every contract address is above it.
     * @return token The deployed token.
     * @return quoteUsed `quote` when mining succeeded, else `address(0)` (ETH) —
     *              the caller MUST record this rather than what it asked for.
     */
    function deployTokenAbove(
        string memory name,
        string memory symbol,
        uint256 gen,
        uint256 totalSupply,
        address quote
    ) external returns (address token, address quoteUsed) {
        // Native ETH is address(0); any deployed contract sorts above it, so the
        // common case keeps the exact bytecode and gas it had before.
        if (quote == address(0)) {
            return (address(new CauldronToken(name, symbol, gen, address(this), totalSupply)), address(0));
        }

        bytes32 initHash = keccak256(
            abi.encodePacked(
                type(CauldronToken).creationCode,
                abi.encode(name, symbol, gen, address(this), totalSupply)
            )
        );

        for (uint256 i; i < SALT_TRIES; ++i) {
            bytes32 salt = keccak256(abi.encode(gen, i));
            address predicted = address(uint160(uint256(
                keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initHash))
            )));
            if (predicted > quote) {
                token = address(new CauldronToken{salt: salt}(name, symbol, gen, address(this), totalSupply));
                // The mined address is the one that was predicted, or the whole
                // premise is wrong — assert rather than trust the arithmetic.
                require(token == predicted && token > quote, "mine");
                return (token, quote);
            }
        }

        // Could not sort above this quote. Launch against ETH instead of
        // reverting: a failed relaunch would roll back `markConsumed` and
        // permanently brick the machine.
        return (address(new CauldronToken(name, symbol, gen, address(this), totalSupply)), address(0));
    }

    /// @dev Mint the ACTIVE full-range position (ETH + tradeable token slice).
    function _seedActive(
        address quote,
        IPositionManagerOps pm,
        PoolKey memory key,
        uint160 sqrtPriceX96,
        uint256 ethAmount,
        uint256 tokenAmount,
        address token,
        int24 tickSpacing
    ) private returns (uint256 positionId) {
        _approve(token, address(pm), tokenAmount);

        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(minTick),
            TickMath.getSqrtPriceAtTick(maxTick),
            ethAmount,
            tokenAmount
        );

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            key, minTick, maxTick, liquidity,
            uint128(ethAmount), uint128(tokenAmount), address(this), bytes("")
        );
        params[1] = abi.encode(Currency.wrap(quote), Currency.wrap(token));
        params[2] = abi.encode(Currency.wrap(quote), address(this)); // excess quote back

        positionId = pm.nextTokenId();
        //  Native pays by forwarding value; an ERC20 quote is PULLED by the
        //  PositionManager, so it must be approved instead. Sending value with an
        //  ERC20 quote would strand it in the PositionManager.
        if (quote == address(0)) {
            pm.modifyLiquidities{value: ethAmount}(abi.encode(actions, params), block.timestamp + 120);
        } else {
            _approve(quote, address(pm), ethAmount);
            pm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 120);
        }
    }

    /// @dev Mint the RESERVE single-sided TOKEN position, out of range BELOW the
    ///      launch tick (pure token1 until the token pumps into it).
    function _seedReserve(
        address quote,
        IPositionManagerOps pm,
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        uint256 tokenAmount,
        address token
    ) private returns (uint256 positionId) {
        uint128 liquidity = ReserveLib.liquidityForTokenOut(tickLower, tickUpper, tokenAmount);
        // DUST GUARD (audit A-01b). `liquidityForTokenOut` rounds DOWN, so a tiny
        // reserve tranche maps to ZERO liquidity — and MINT_POSITION with zero
        // liquidity reverts `CannotUpdateEmptyPosition` inside the PositionManager.
        // That revert propagates out of `relaunch()`, which also rolls back
        // `governor.markConsumed`, so the same proposal wins again and the machine
        // is permanently bricked. It is reachable whenever a generation dies having
        // traded almost nothing: `newActive` then absorbs nearly the whole supply
        // and `newReserve = TOTAL_SUPPLY - newActive` is dust.
        // Returning 0 leaves the generation with NO reserve position, which every
        // consumer already handles (`claimFromReserve` and `addToReserve` no-op at
        // zero liquidity, `_removeLiquidity` skips a zero id) — and it is the
        // correct outcome: a dust reserve backs nothing, so there is nothing to
        // place. The tokens simply stay with the registry.
        if (liquidity == 0) return 0;
        _approve(token, address(pm), tokenAmount);

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP)
        );
        bytes[] memory params = new bytes[](3);
        // Single-sided: max0 (ETH) = 0, max1 (token) = tokenAmount.
        params[0] = abi.encode(
            key, tickLower, tickUpper, liquidity,
            uint128(0), uint128(tokenAmount), address(this), bytes("")
        );
        params[1] = abi.encode(Currency.wrap(quote), Currency.wrap(token));
        params[2] = abi.encode(Currency.wrap(quote), address(this));

        positionId = pm.nextTokenId();
        pm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 120);
    }

    /**
     * @notice Remove 100% of a position and take both currencies to the registry,
     *         burning the NFT. Used at death for BOTH the active + reserve
     *         positions. Returns recovered (eth, tokens) via balance deltas.
     */
    function removeAll(IPositionManagerOps pm, uint256 positionId, PoolKey memory key, address token)
        external
        returns (uint256 ethRecovered, uint256 tokensRecovered)
    {
        uint128 liquidity = pm.getPositionLiquidity(positionId);
        if (liquidity == 0) return (0, 0);

        uint256 ethBefore = address(this).balance;
        uint256 tokBefore = IERC20(token).balanceOf(address(this));

        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR), uint8(Actions.BURN_POSITION)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(positionId, liquidity, uint128(0), uint128(0), bytes(""));
        params[1] = abi.encode(key.currency0, key.currency1, address(this));
        params[2] = abi.encode(positionId, uint128(0), uint128(0), bytes(""));

        pm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 120);

        ethRecovered = address(this).balance - ethBefore;
        tokensRecovered = IERC20(token).balanceOf(address(this)) - tokBefore;
    }

    /**
     * @notice Claim EXACTLY `amount` token from the out-of-range reserve position
     *         and take it straight to `recipient` — zero ETH, no price move
     *         (the range is fully below spot). Keeps the position open for the
     *         next claimer. Returns the token amount actually taken.
     */
    function claimFromReserve(
        IPositionManagerOps pm,
        uint256 positionId,
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount,
        address recipient
    ) public returns (uint256 taken) {
        uint128 liquidity = ReserveLib.liquidityForTokenOut(tickLower, tickUpper, amount);
        if (liquidity == 0) return 0;
        // Don't remove more than the position holds.
        uint128 have = pm.getPositionLiquidity(positionId);
        if (liquidity > have) liquidity = have;
        if (liquidity == 0) return 0;

        uint256 tokBefore = IERC20(Currency.unwrap(key.currency1)).balanceOf(recipient);

        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR)
        );
        bytes[] memory params = new bytes[](2);
        // amount1Min = 0 (dust rounding); reserve is out of range so ETH out = 0.
        params[0] = abi.encode(positionId, liquidity, uint128(0), uint128(0), bytes(""));
        params[1] = abi.encode(key.currency0, key.currency1, recipient);

        pm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 120);

        taken = IERC20(Currency.unwrap(key.currency1)).balanceOf(recipient) - tokBefore;
    }

    /**
     * @notice ADD `amount` token BACK into the out-of-range reserve position — the
     *         mirror of `claimFromReserve`. The registry (address(this) under
     *         delegatecall) must already hold `amount` of the token; this increases
     *         the reserve position's liquidity single-sided (the band is fully below
     *         spot → pure token1, zero ETH leg, no price move). Grows the reserve
     *         that backs redemptions + migration, so the genesis floor RATCHETS up.
     *         Returns the token amount actually consumed into the position.
     */
    function addToReserve(
        IPositionManagerOps pm,
        uint256 positionId,
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount
    ) public returns (uint256 added) {
        if (amount == 0) return 0;
        uint128 liquidity = ReserveLib.liquidityForTokenOut(tickLower, tickUpper, amount);
        if (liquidity == 0) return 0;

        address token = Currency.unwrap(key.currency1);
        _approve(token, address(pm), amount);
        uint256 tokBefore = IERC20(token).balanceOf(address(this));

        bytes memory actions = abi.encodePacked(
            uint8(Actions.INCREASE_LIQUIDITY), uint8(Actions.SETTLE_PAIR)
        );
        bytes[] memory params = new bytes[](2);
        // Single-sided top-up: max0 (ETH) = 0, max1 (token) = amount.
        params[0] = abi.encode(positionId, liquidity, uint128(0), uint128(amount), bytes(""));
        params[1] = abi.encode(key.currency0, key.currency1);

        pm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 120);

        // Consumed = the token balance the position actually pulled from us.
        added = tokBefore - IERC20(token).balanceOf(address(this));
    }

    // ── Legacy-floor orchestration (delegatecall'd → address(this) = registry) ──

    event AutoMigrated(uint256 indexed fromGen, address indexed holder, uint256 amount);

    /// @notice MIGRATE `amount` of `prevToken` from `from` 1:1 into the current token:
    ///         burn the old, release the same from the reserve. Shared by claimByBurn
    ///         (single) + autoMigrateBatch. Offloaded from the registry to save bytes.
    /// @dev DUST TOLERANCE for reserve withdrawals. `claimFromReserve` sizes the
    ///      removal in Uniswap LIQUIDITY units, which round DOWN, so an exact claim
    ///      lands a few wei short (measured: ~276 wei on a 2.8e26 claim). Anything
    ///      beyond this means the reserve is genuinely SHORT and the caller must not
    ///      silently eat the loss. (Audit H-03.)
    uint256 internal constant CLAIM_DUST = 1e12;

    /// @notice CAPACITY-AWARE migration, for the protocol's OWN inventory (the perp
    ///         engine's `syncGeneration`). Burns only what the reserve can actually
    ///         deliver, so a thin reserve yields a smaller — but still exactly 1:1 —
    ///         migration instead of either destroying value (the pre-fix behaviour:
    ///         burn 5e25, receive 9,375 wei) or migrating nothing at all.
    ///         Returns the amount migrated, which may be less than `maxAmount`.
    function migrateUpTo(
        IPositionManagerOps pm, address prevToken, address from, uint256 maxAmount, ReserveRef memory r
    ) external returns (uint256 got) {
        uint256 cap = ReserveLib.tokenOutForLiquidity(
            r.tickLower, r.tickUpper, pm.getPositionLiquidity(r.positionId)
        );
        uint256 amt = maxAmount < cap ? maxAmount : cap;
        if (amt == 0) return 0;
        got = migrateOne(pm, prevToken, from, amt, r);
    }

    function migrateOne(
        IPositionManagerOps pm, address prevToken, address from, uint256 amount, ReserveRef memory r
    ) public returns (uint256 got) {
        ICauldronBurn(prevToken).burn(from, amount);
        got = claimFromReserve(pm, r.positionId, r.key, r.tickLower, r.tickUpper, amount, from);
        // The burn above already destroyed `amount`. If the reserve cannot cover it,
        // REVERT so the burn rolls back with us — never let a holder pay in full and
        // receive less. (Audit H-03: this check was missing, and `claimFromReserve`
        // caps at the position's liquidity and returns short WITHOUT reverting.)
        if (got + CLAIM_DUST < amount) revert("reserve short");
    }

    /// @notice Keeper batch migrate — burns each opted-in holder's `prevToken` and
    ///         releases the same 1:1 from the reserve. Reads the opt-in flag via a
    ///         self-call getter (delegatecall → address(this) is the registry).
    /// @dev TRULY BEST-EFFORT (audit F-08). The NatSpec above promises the batch
    ///      "skips anyone ... whom the pool can't currently cover, so one miss never
    ///      reverts the batch", but nothing implemented that: `migrateOne` REVERTS
    ///      with "reserve short" when the reserve cannot deliver, and the revert
    ///      propagates out of the loop and kills the whole keeper call. Because
    ///      opting in is permissionless and (previously) irrevocable, one opted-in
    ///      wallet holding more than the reserve can pay is enough to make EVERY
    ///      batch containing it revert — a cheap, permanent grief against the keeper
    ///      path that the protocol advertises as hands-off. Size the reserve's
    ///      capacity once per holder and skip anyone it cannot cover in full, so a
    ///      holder is never partially migrated behind their back either.
    function autoMigrateBatch(
        IPositionManagerOps pm, address prevToken, uint256 fromGen,
        address[] calldata holders, ReserveRef memory r
    ) external {
        for (uint256 i = 0; i < holders.length; i++) {
            address h = holders[i];
            if (!IAutoFlag(address(this)).autoMigrate(h)) continue;
            uint256 bal = IERC20(prevToken).balanceOf(h);
            if (bal == 0) continue;
            // Re-read capacity each iteration: every migration drains the reserve.
            uint256 cap = ReserveLib.tokenOutForLiquidity(
                r.tickLower, r.tickUpper, pm.getPositionLiquidity(r.positionId)
            );
            if (bal > cap) continue; // reserve can't cover this holder — skip, don't revert
            emit AutoMigrated(fromGen, h, migrateOne(pm, prevToken, h, bal, r));
        }
    }

    /// @notice Route a live buyback into the legacy floors. For a normal brew the
    ///         whole amount → the collection's pending entitlement. For the iter-#2
    ///         MiFrens CONTINUATION (genCollection == mifrens), split so OG + forged
    ///         floors rise at the SAME per-fren rate (∝ fren count): the forged share
    ///         → the ledger, the OG share is RETURNED for the registry to fold into
    ///         the genesis reserve. Returns 0 (no OG share) for a normal brew.
    function doLegacyNote(
        address ledger, address mifrens, uint256 ogCount,
        uint256 gen, address genCollection, uint256 tokensBought
    ) public returns (uint256 ogShare) {
        if (mifrens != address(0) && genCollection == mifrens) {
            uint256 forged = IColMinted(mifrens).totalMinted();
            forged = forged > ogCount ? forged - ogCount : 0;
            uint256 total = ogCount + forged;
            if (total == 0) return 0;
            ogShare = (tokensBought * ogCount) / total;
            uint256 forgedShare = tokensBought - ogShare;
            // credit LIVE (redeemable immediately) — the unified ledger no longer
            // holds a separate pre-death `pending` bucket.
            if (forgedShare != 0) ILedgerOps(ledger).credit(gen, forgedShare);
        } else {
            ILedgerOps(ledger).credit(gen, tokensBought);
        }
    }

    /// @notice Move the hook's held live-buyback tokens into the collection floor —
    ///         the credit lands ONLY when the tokens are really backed, so a legacy
    ///         credit can't out-run the reserve (Invariant R). `toReserve` = the live
    ///         path (deposit into the reserve LP); false = the relaunch flush (the
    ///         dying gen's reserve is gone, so BURN the dead token and carry the value
    ///         as a pure ledger number covered by the new reserve's sizing). Returns
    ///         (credited, ogShare) — the registry folds ogShare into genesisPending.
    ///         No-op (0,0) if the ledger/hook aren't wired or nothing is pending.
    function materializeLegacy(
        IPositionManagerOps pm, address hook, address registryAddr,
        address ledger, address mifrens, uint256 genesisShares,
        uint256 gen, address genColl, address token,
        ReserveRef memory r, bool toReserve
    ) external returns (uint256 credited, uint256 ogShare) {
        if (ledger == address(0)) return (0, 0);
        if (ILegacyHookOps(hook).legacyRegistry() != registryAddr) return (0, 0);
        uint256 amt = ILegacyHookOps(hook).sweepLegacyReserve(token, registryAddr);
        if (amt == 0) return (0, 0);
        if (toReserve) {
            credited = addToReserve(pm, r.positionId, r.key, r.tickLower, r.tickUpper, amt);
            if (credited == 0) return (0, 0);
        } else {
            credited = amt;
            ICauldronBurn(token).burn(registryAddr, amt); // dead old-gen token
        }
        ogShare = doLegacyNote(ledger, mifrens, genesisShares, gen, genColl, credited);
    }

    /// @notice At a brew's death, crystallize its collection into a token
    ///         entitlement worth `swept` ETH at the new launch price
    ///         (ETH/token = totalETH/activeBase), with claimants = minted − ETH-
    ///         redeemed. No-op if ledger/collection unset or already crystallized.
    ///         Returns the entitled token amount (0 if skipped).
    function crystallizeCollection(
        address ledger, address collection, address vault,
        uint256 gen, uint256 swept, uint256 activeBase, uint256 totalETH
    ) external returns (uint256 entitled) {
        if (ledger == address(0) || collection == address(0) || totalETH == 0) return 0;
        if (ILedgerOps(ledger).crystallized(gen)) return 0;
        entitled = FullMath.mulDiv(swept, activeBase, totalETH);
        // Freeze the entitled-NFT base = the vault's OWN outstanding (already
        // excludes the genesis tranche via the vault's floorOffset), so the MiFrens
        // continuation's forged tranche is counted correctly and OGs never dilute
        // the collection floor. Any live buyback already `credit`ed entitledTokens,
        // so `entitled` here is ONLY the final swept-ETH sizing (no double count).
        // Live redemptions before death carry over via the ledger's `retired`.
        uint256 nftCount = vault == address(0) ? 0 : IVaultRedeemedOps(vault).outstanding();
        ILedgerOps(ledger).crystallize(gen, nftCount, entitled);
    }


    /// @notice RECYCLE a dead collection's NFT: debit the ledger, move the NFT to
    ///         the treasury (the registry), and pay the floor from the live reserve.
    ///         Reverts if the caller doesn't own it. Returns the token paid out.
    function recycleCollection(
        IPositionManagerOps pm,
        address ledger,
        address collection,
        uint256 gen,
        uint256 tokenId,
        address caller,
        ReserveRef memory r
    ) external returns (uint256 amount) {
        if (ICollectionOps(collection).ownerOf(tokenId) != caller) revert("not owner");
        // mintedNow sizes the LIVE floor; ignored once the collection crystallized.
        uint256 mintedNow = IColMinted(collection).totalMinted();
        uint256 payout = ILedgerOps(ledger).redeem(gen, mintedNow); // checks-effects
        ICollectionOps(collection).custodyTransfer(caller, address(this), tokenId);
        amount = claimFromReserve(pm, r.positionId, r.key, r.tickLower, r.tickUpper, payout, caller);
        // The ledger was already debited and the NFT already moved to the treasury —
        // a short reserve must roll BOTH back rather than hand over less. (Audit H-03.)
        if (amount + CLAIM_DUST < payout) revert("reserve short");
    }

    /// @notice BUY a treasury-held collection NFT for 2× its floor (paid in the
    ///         live token, pulled from `caller`), add it to the reserve, ratchet the
    ///         ledger, and hand the NFT to the buyer. Returns tokens actually added.
    function buyCollection(
        IPositionManagerOps pm,
        address ledger,
        address collection,
        address token,
        uint256 gen,
        uint256 tokenId,
        address caller,
        ReserveRef memory r
    ) external returns (uint256 added) {
        if (ICollectionOps(collection).ownerOf(tokenId) != address(this)) revert("not treasury");
        uint256 mintedNow = IColMinted(collection).totalMinted();
        uint256 paid = 2 * ILedgerOps(ledger).floorPerNFT(gen, mintedNow);
        require(paid > 0, "no floor");
        require(IERC20(token).transferFrom(caller, address(this), paid), "pay");
        added = addToReserve(pm, r.positionId, r.key, r.tickLower, r.tickUpper, paid);
        ILedgerOps(ledger).buyback(gen, mintedNow, added);
        ICollectionOps(collection).custodyTransfer(address(this), caller, tokenId);
    }
}
