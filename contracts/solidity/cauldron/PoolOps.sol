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

/// @notice The hook's two relaunch reserves. Both are registry-gated and both are
///         reached from {PoolOps.seedFunding}, which is delegatecalled BY the
///         registry — so `msg.sender` at the hook is the registry and the released
///         value lands there.
interface IHookReserves {
    function releaseRelaunchETH() external returns (uint256);
    function releaseRelaunchAsset(address asset) external returns (uint256);
}

/// @notice The dying generation's floor vault, closed from {PoolOps.seedFunding}.
interface IVaultCloseOps {
    function close() external returns (uint256 swept);
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

    /// @dev `initialize` failed AND the pool does not exist — so the failure was
    ///      a refusal (the hook's adoption gate), not the benign "already open"
    ///      case {openOrAddPair}'s catch is written for.
    error PoolInitRefused();

    /// @dev Approve the PositionManager to pull `amount` of `token` via Permit2.
    function _approve(address token, address pm, uint256 amount) private {
        IERC20(token).approve(PERMIT2, amount);
        IPermit2Ops(PERMIT2).approve(token, pm, uint160(amount), uint48(block.timestamp + 300));
    }

    /// @dev The smallest quote amount `_sqrtPrice` can REPRESENT for a given token
    ///      amount. `FullMath.mulDiv(t, 2**192, q)` builds the full 512-bit product
    ///      and reverts unless the quotient fits in 256 bits — i.e. unless
    ///      `q > t / 2**64` — and it reverts outright on `q == 0`.
    function _minQuoteFor(uint256 tokenAmount) private pure returns (uint256) {
        return (tokenAmount >> 64) + 1;
    }

    /// @dev A seed amount below which this library will not price a pool at all.
    ///      16x {_minQuoteFor} of the full supply, so it holds whatever fraction of
    ///      the supply the active tranche happens to be. See {seedFunding}.
    ///      Literal because a contract-level `constant` is not reachable as
    ///      `CauldronToken.TOTAL_SUPPLY`; it is that value (CauldronToken.sol:29,
    ///      777_000_000e18 — the only supply `CauldronRegistry:1683` ever mints)
    ///      shifted right by 60, i.e. 673,940,065 base units of the quote:
    ///      0.00000000067 ETH (never binds) or 673.94 USDG (673,940,070 exactly).
    uint256 internal constant MIN_SEED_UNITS = 777_000_000e18 >> 60;

    function _sqrtPrice(uint256 tokenAmount, uint256 ethAmount) private pure returns (uint160) {
        //  REPRESENTABILITY CLAMP, NOT A REVERT (audit Z-01 — High). `ethAmount`
        //  arrives in the QUOTE's OWN base units and nothing on this path normalises
        //  it: 42,121,254 of them is 42 gwei in ether (harmless) but 42.12 tokens in a
        //  6-decimal quote such as the USDG the live deploy allowlists
        //  (DeployLaunchpad.s.sol:625, :668). Below that, the `mulDiv` on the next line
        //  reverted with empty returndata — and on the relaunch path it does so BEHIND
        //  `CauldronRegistry:995 governor.markConsumed(winId)`, so the revert rolled the
        //  consumption back, the same proposal won `_bestUnconsumed()` again, and every
        //  later `relaunch()` died at the same line. A permanent, unrecoverable brick
        //  of the whole lifecycle, with no keeper and no owner function to clear it,
        //  because the failing input is DERIVED from protocol state.
        //  Clamping yields the extreme (maximally cheap token) launch price, which is
        //  the honest answer when the whole supply is being seeded against dust, and it
        //  changes NOTHING for any amount at or above the floor. {seedFunding} refuses
        //  to hand a sub-{MIN_SEED_UNITS} amount over in the first place; this clamp is
        //  the backstop for the callers that do not go through it ({openOrAddPair} at
        //  the rotation, and {createAndSeedProgressive}'s non-native degrade branch).
        uint256 minQ = _minQuoteFor(tokenAmount);
        if (ethAmount < minQ) ethAmount = minQ;
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

        //  ── NON-NATIVE: DEGRADE TO AN ATOMIC SEED, NEVER REVERT ────────────
        //  `CauldronSeeder.startSeed` is `payable` and asserts
        //  `msg.value == cfg.ethTotal` (:133). It pulls only the TOKEN side by
        //  `transferFrom` (:169) and has NO ERC20 path for the quote. So the
        //  `{value:}` below cannot fund a USDG-denominated generation: the
        //  registry holds no ether to send and the assert fails.
        //
        //  That revert would land inside `CauldronRegistry._seedGeneration`,
        //  called at :1000 — AFTER `governor.markConsumed(winId)` at :912. It
        //  would roll the consumption back, the same proposal would keep winning
        //  `_bestUnconsumed()`, and every later rebirth would die identically.
        //  Both preconditions are ordinary: the seeder is owner-armed and a
        //  non-native quote is a normal governance choice from the allowlist.
        //
        //  A non-native brew therefore takes the ATOMIC path — the full active
        //  tranche placed at once, exactly as {createAndSeed} does, which already
        //  handles any quote (asserted by B08_NonEthRebirth). The brew launches;
        //  it just does not stream. Same clamp-don't-revert discipline as the
        //  quote re-check, the `nftSupply` bound and the mining fallback.
        if (quote != address(0)) {
            uint160 sp0 = _sqrtPrice(activeTokens, ethAmount);
            poolManager.initialize(r.key, sp0);
            if (reserveTokens > 0) {
                (r.reserveTickLower, r.reserveTickUpper) = ReserveLib.reserveTicks(
                    TickMath.getTickAtSqrtPrice(sp0), tickSpacing, ceilingOffset
                );
                r.reservePositionId = _seedReserve(
                    quote, pm, r.key, r.reserveTickLower, r.reserveTickUpper, reserveTokens, token
                );
            }
            r.activePositionId = _seedActive(
                quote, pm, r.key, sp0, ethAmount, activeTokens, token, tickSpacing
            );
            return r;
        }

        //  ── HYBRID: GREEN CANDLE ON THE BASE, STREAM THE REST ──────────────
        //
        //  The progressive path used to place the reserve SILENTLY and hand the
        //  whole active tranche to the seeder, which meant a launch opened with no
        //  trade at all: the chart stayed empty until an outside buyer arrived, and
        //  because the seeder only streams on `poke`/`pokeInSwap`, no buyer meant no
        //  poke meant the stream never moved. Measured on round 35 — 76.5% of ledger
        //  A was still sitting in the seeder after the window had closed.
        //
        //  Folding the reserve into the BASE tranche fixes both. The base is placed
        //  and the reserve is BOUGHT out of it in the ignition transaction, so the
        //  pool has a real trade in its first block, and the seeder receives only the
        //  remainder (`baseWad: 0` — the base already exists, it must not lay another
        //  one). The launch price is unchanged: the base keeps ledger A's exact
        //  ETH:token ratio, so `baseEth/baseTok == ethAmount/activeTokens`.
        //
        //  Ledger A -> the seeder. APPROVE the streamed tokens (the seeder pulls them
        //  itself via transferFrom inside startSeed — the single funding path; a
        //  separate transfer here would double-spend), then startSeed with the
        //  streamed ETH as value. Both are drawn from the registry (= address(this)
        //  under the delegatecall), and `sp.seeder`'s onlyRegistry sees msg.sender =
        //  registry.
        uint256 baseTok = (activeTokens * SEED_BASE_WAD) / 1e18;
        uint256 baseEth = (ethAmount * SEED_BASE_WAD) / 1e18;

        _greenCandle(
            poolManager, pm, r, token, baseTok, baseEth, reserveTokens,
            tickSpacing, ceilingOffset, quote
        );

        IERC20(token).approve(sp.seeder, activeTokens - baseTok);
        ISeeder(sp.seeder).startSeed{value: ethAmount - baseEth}(SeederConfig({
            key: r.key, token: token, gen: sp.gen,
            spacing: tickSpacing, bandWidth: SEED_BANDWIDTH,
            window: sp.window, seedFloorWad: SEED_FLOOR_WAD, minStepWad: SEED_MINSTEP_WAD,
            baseWad: 0,
            ethTotal: ethAmount - baseEth, tokenTotal: activeTokens - baseTok
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

        _greenCandle(
            poolManager, pm, r, token, activeTokens, ethAmount, reserveTokens,
            tickSpacing, ceilingOffset, quote
        );
    }

    /**
     * @dev THE GREEN CANDLE, shared by the atomic and the hybrid seed paths.
     *
     *  Seeds `activeTok + reserveTok` into a full-range position at a DEEP-DISCOUNT
     *  price funded with only `E_active = ethAmt * activeTok / total`, then spends the
     *  remainder buying EXACTLY `reserveTok` back out and re-parks it out of range.
     *  The constant-product identity `E_active * total == ethAmt * activeTok` lands the
     *  active LP at exactly `(activeTok, ethAmt)` — the same end state a silent seed
     *  produces, but the reserve arrives as a real market buy.
     *
     *  IT IS SELF-FUNDING. No ETH beyond `ethAmt` is consumed: the buy spends the
     *  slice of `ethAmt` attributable to the reserve, and that ETH lands back in the
     *  LP as the buy settles. Scoping it to a SMALLER `activeTok` (the hybrid passes
     *  only the base tranche) therefore does not cost anything — it just opens the
     *  pool further below the launch price, so the candle is bigger:
     *
     *      candle multiplier = (1 + reserveTok / activeTok)^2
     *
     *  and the post-buy price is identical for every choice of `activeTok`.
     *
     *  ── THE SETTLEMENT BUFFER IS EXPLICIT, NOT INCIDENTAL ────────────────
     *  This used to be a bare `mulDiv` with the comment "E_active floored -> the
     *  leftover E_buy carries a tiny buffer so the exact-output buy can never revert
     *  for want of a wei to settle." The reasoning holds only when the division leaves
     *  a remainder. When `ethAmt * activeTok` divides EXACTLY by `total` the floor
     *  takes nothing, the buffer is zero — and the exact-output buy rounds UP, so it
     *  asks for one unit more than the caller holds and reverts inside the unlock.
     *  Measured on a round-numbered 6-decimal seed: held 20000000000, settle wanted
     *  20000000001.
     *
     *  Natively that was masked by slack — `settle{value:}` draws on the registry's
     *  whole ether balance, which usually carries dust from earlier cycles. An ERC20
     *  quote has no such slack: `seedFunding` hands over exactly what it pulled. So
     *  generalising the quote is what turned a latent rounding bug into a reachable
     *  revert on the mandatory rebirth path — i.e. another permanent freeze.
     *
     *  Subtracting a fixed floor makes the buffer unconditional. It is
     *  self-consistent: a smaller `ethActive` lowers the launch price, which makes the
     *  same exact-output buy CHEAPER while simultaneously leaving MORE to pay it with,
     *  so both sides of the inequality move the right way. 64 base units is dust in any
     *  decimals (64 wei; 0.000064 USDG) and comfortably covers v4's round-up on a
     *  single-step full-range swap.
     */
    function _greenCandle(
        IPoolManager poolManager,
        IPositionManagerOps pm,
        SeedResult memory r,
        address token,
        uint256 activeTok,
        uint256 ethAmt,
        uint256 reserveTok,
        int24 tickSpacing,
        int24 ceilingOffset,
        address quote
    ) private {
        uint256 totalTokens = activeTok + reserveTok;

        uint256 ethActive = FullMath.mulDiv(ethAmt, activeTok, totalTokens);
        if (ethActive > BUY_SETTLE_BUFFER) ethActive -= BUY_SETTLE_BUFFER;

        // Deep-discount launch price = ALL tokens against only E_active.
        uint160 sqrtPriceX96 = _sqrtPrice(totalTokens, ethActive);
        poolManager.initialize(r.key, sqrtPriceX96);

        // 1. Seed the whole tranche into the active full-range position.
        r.activePositionId =
            _seedActive(quote, pm, r.key, sqrtPriceX96, ethActive, totalTokens, token, tickSpacing);

        // 2 + 3. Buy the reserve out of the fresh pool, then re-park it out of range.
        if (reserveTok > 0) {
            // Reserve reseed = EXACT OUTPUT (amtSpecified > 0), kept in the registry
            // (recipient = 0). The leftover ethBuy buffer covers settlement.
            bytes memory ret = poolManager.unlock(abi.encode(r.key, int256(reserveTok), address(0)));
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

        uint256 ethIn = uint256(uint128(-delta.amount0())); // QUOTE we owe the pool
        uint256 got = uint256(uint128(delta.amount1()));    // token we're owed

        //  SETTLE IN WHATEVER THE QUOTE IS (red-team B-05, wall 1b).
        //
        //  This was `settle{value: ethIn}()` unconditionally. Native settlement
        //  against an ERC20-quoted pool pays nothing the pool asked for, so
        //  currency0's delta stayed open and the unlock closed with
        //  `CurrencyNotSettled()` — an unguarded revert behind `markConsumed`,
        //  i.e. a permanent freeze. The hook documents the identical limitation
        //  for its own buyback (CauldronHook `_maybeLegacyBuyback`, "ETH-LAYOUT
        //  ONLY, for now") and guards it with an early return; here it was not
        //  guarded at all because this path is mandatory.
        //
        //  ERC20 settlement in v4 is sync → transfer → settle: `sync` snapshots
        //  the manager's balance, the transfer moves the tokens in, and `settle`
        //  credits the difference. `address(this)` is the registry (this library
        //  is delegatecalled), so the tokens paid are the registry's own.
        address q = Currency.unwrap(key.currency0);
        if (q == address(0)) {
            poolManager.settle{value: ethIn}();      // pay ETH from the registry
        } else {
            poolManager.sync(key.currency0);
            //  RETURN VALUE CHECKED — this settle sits BEHIND `markConsumed`.
            //
            //  This was a bare `IERC20(q).transfer(...)`. A quote that returns
            //  false instead of reverting (USDT-shaped, and most tokenized
            //  equities) would move nothing, `settle()` would credit nothing, and
            //  the unlock would end `CurrencyNotSettled()`. That revert unwinds
            //  the whole of `relaunch()` — including `governor.markConsumed`
            //  (CauldronRegistry.sol:912, which runs BEFORE `_seedGeneration` at
            //  :1000) — so the same proposal wins `_bestUnconsumed()` again and
            //  every later rebirth dies at the identical line. Permanent, with no
            //  keeper or retry that recovers it.
            //
            //  That is the exact failure class the B-05 work removed, and this
            //  line was introduced by the fix for B-05's own bug #3. Every
            //  sibling settle in the repo already checks (see {sendAsset} below,
            //  FeeRouteLib.send, QuoteRotator._safeTransfer); this was the outlier.
            //
            //  Reverting HERE is not a regression: a quote that cannot settle
            //  cannot seed a pool either, so failing loudly at the transfer is
            //  strictly better than failing opaquely at `settle`. The real
            //  defence remains the owner-curated `allowedQuote` list.
            (bool ok, bytes memory ret) =
                q.call(abi.encodeWithSelector(IERC20.transfer.selector, address(poolManager), ethIn));
            require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "settle");
            poolManager.settle();
        }
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

    /// @dev Quote units held back from the active seed so the green-candle
    ///      exact-output buy always has enough to settle. See the long note in
    ///      {createAndSeedWithBuy}; asserted by B08_NonEthRebirth.
    uint256 private constant BUY_SETTLE_BUFFER = 64;

    /**
     * @notice Every iteration token is mined above THIS, not merely above the
     *         quote it launches with.
     *
     *  Mining above the launch quote alone would only make the token adoptable
     *  by that one asset. An ETH generation's token is then guaranteed nothing
     *  except `> 0`, so a later switch to a USDG pair would be a coin flip on
     *  the ordering — and the token cannot be redeployed, because it already
     *  holds all the liquidity.
     *
     *  Mining above a fixed watermark instead, and refusing to allowlist any
     *  quote above it (see CauldronRegistry.setAllowedQuote), makes adoptability
     *  an INVARIANT: any permitted quote sorts below any token, so ANY
     *  generation can migrate to ANY approved pair, forever.
     *
     *  0xf000… covers 93.75% of the address space, which comfortably contains
     *  every real quote asset (USDC 0xA0b8…, DAI 0x6B17…, USDT 0xdAC1…). The
     *  cost is one extra keccak per rejected candidate; measured at ~4.4k gas
     *  for the whole search, once, at deploy.
     */
    address internal constant QUOTE_WATERMARK = 0xf000000000000000000000000000000000000000;

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
        //  Mine above the WATERMARK, never merely above `quote` — including for
        //  native ETH, whose address(0) would otherwise impose no constraint at
        //  all and leave the token unable to adopt an ERC20 pair later.
        address floor = quote > QUOTE_WATERMARK ? quote : QUOTE_WATERMARK;

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
            if (predicted > floor) {
                token = address(new CauldronToken{salt: salt}(name, symbol, gen, address(this), totalSupply));
                // The mined address is the one that was predicted, or the whole
                // premise is wrong — assert rather than trust the arithmetic.
                require(token == predicted && token > floor, "mine");
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
    /**
     * @notice Open a pair for an EXISTING token against a new quote, or add to it
     *         if it already exists.
     *
     *  The return leg of a rotation. It must handle BOTH cases because the guild
     *  can rotate back: converting ETH into USDG creates the USDG pair, and
     *  converting back later must ADD to the ETH pair that is already live
     *  rather than trying to initialize it again.
     *
     *  Currency order needs no sorting logic here — the token was mined above
     *  {QUOTE_WATERMARK} and no quote above it can be allowlisted, so the quote
     *  is always currency0. That invariant is what keeps this a top-up rather
     *  than a second orientation to reason about.
     *
     * @return poolId     the pair's id, for the caller to register with the hook
     * @return positionId the freshly minted liquidity position
     */
    function openOrAddPair(
        IPoolManager poolManager,
        IPositionManagerOps pm,
        address hook,
        address token,
        address quote,
        uint256 quoteAmount,
        uint256 tokenAmount,
        int24 tickSpacing,
        uint24 poolFee
    ) external returns (PoolId poolId, uint256 positionId) {
        require(quoteAmount > 0 && tokenAmount > 0, "amt");
        require(token > quote, "order"); // the watermark invariant, asserted

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(quote),
            currency1: Currency.wrap(token),
            fee: poolFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hook)
        });
        poolId = key.toId();

        //  Price the pair off the amounts contributed. On a FIRST open that sets
        //  the opening price; on a top-up `initialize` reverts, the live price
        //  stands, and the CONTRIBUTED price must be discarded.
        //
        //  Reading the live price back is not cosmetic. Liquidity is sized from
        //  the price it is minted at, so sizing a top-up at the contributed
        //  ratio while the pool sits somewhere else makes the mint demand more
        //  of one side than was supplied — the PositionManager then reverts
        //  MaximumAmountExceeded and the whole rotation fails to land. Caught by
        //  the fork test; a stub cannot surface it.
        //  THE CATCH MEANS EXACTLY ONE THING: "the pair already exists". It must
        //  not be allowed to mean anything else. `initialize` can now also fail
        //  because the HOOK REFUSED US — `CauldronHook._afterInitialize` reverts
        //  for any sender that is not the registry, which is what makes the
        //  registry's next pool key unsquattable. Swallowing that refusal here
        //  would leave `live == 0`, keep the contributed price, and hand a
        //  non-existent pool to `_seedActive` — which fails far downstream as
        //  `PoolNotInitialized`, naming neither the real cause nor this line.
        //  A zero slot0 means the pool genuinely is not there, so re-throw.
        uint160 sqrtPriceX96 = _sqrtPrice(tokenAmount, quoteAmount);
        try poolManager.initialize(key, sqrtPriceX96) returns (int24) {
            // fresh pair: the contributed ratio IS the price
        } catch {
            (uint160 live,,,) = StateLibrary.getSlot0(poolManager, poolId);
            if (live == 0) revert PoolInitRefused();
            sqrtPriceX96 = live;
        }

        positionId = _seedActive(
            quote, pm, key, sqrtPriceX96, quoteAmount, tokenAmount, token, tickSpacing
        );
    }

    /**
     * @notice Remove a MEASURED share of a position, keeping the position alive.
     * @dev The rotation path: the guild converts part of its liquidity into a
     *      different quote, so this must never take everything. The position is
     *      NOT burned — unlike {removeAll}, which is the death path — because the
     *      original pair keeps trading throughout.
     *
     *      Both sides are measured by BALANCE DELTA rather than trusted from the
     *      caller's arithmetic, and the quote side is read from `quote` rather
     *      than assumed native: an ERC20-quoted generation recovers nothing into
     *      `address(this).balance`.
     *
     * @param bps Share of current liquidity to withdraw. Capped below 100% so a
     *            rotation can never empty the pair it is rotating out of.
     */
    function removePartial(
        IPositionManagerOps pm,
        uint256 positionId,
        PoolKey memory key,
        address token,
        address quote,
        uint16 bps
    ) external returns (uint256 quoteRecovered, uint256 tokensRecovered) {
        require(bps > 0 && bps <= MAX_ROTATION_BPS, "bps");
        uint128 liquidity = pm.getPositionLiquidity(positionId);
        if (liquidity == 0) return (0, 0);

        uint128 take = uint128((uint256(liquidity) * bps) / 10_000);
        if (take == 0) return (0, 0);

        uint256 qBefore = _balance(quote);
        uint256 tBefore = IERC20(token).balanceOf(address(this));

        // No BURN_POSITION: the position must survive so the original pair keeps
        // trading while the rotation runs.
        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR)
        );
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(positionId, take, uint128(0), uint128(0), bytes(""));
        params[1] = abi.encode(key.currency0, key.currency1, address(this));

        pm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 120);

        quoteRecovered = _balance(quote) - qBefore;
        tokensRecovered = IERC20(token).balanceOf(address(this)) - tBefore;
    }

    /// @dev Hard ceiling on a single rotation. A rotation is a reallocation, not
    ///      an exit: leaving the original pair with no depth would strand every
    ///      holder who wants to trade it while the new pair is still filling.
    uint16 internal constant MAX_ROTATION_BPS = 5000; // 50%

    /// @notice Send native or ERC20, checking the ERC20 return value. Lives here
    ///         rather than in the registry, which has no bytecode budget left.
    /**
     * @notice Decide which asset the NEWBORN generation can actually be seeded in,
     *         pull exactly the reserve that funds it, and report both.
     *
     *  ── WHY THIS EXISTS, AND WHY IT LIVES HERE ─────────────────────────────
     *  `relaunch()` used to add three native-wei figures together and hand the sum
     *  to the seeder as the quote amount, whatever quote the proposal named. That
     *  is red-team B-05: no conversion, no rescaling, and three unguarded reverts
     *  behind `markConsumed`. Choosing the quote from what the protocol ACTUALLY
     *  HOLDS is what makes a non-native rebirth real rather than aspirational.
     *
     *  It lives in this library because {CauldronRegistry} has ~100 bytes of
     *  EIP-170 headroom and this is ~600 bytes of branching. Delegatecalled, so
     *  `address(this)` is the registry: the hook sees `msg.sender == registry` on
     *  both release paths, and the released value lands in the registry.
     *
     *  ── THE PREFERENCE ORDER, AND WHY ──────────────────────────────────────
     *    1. `wantQuote` — the proposal's choice. Fundable only from value ALREADY
     *       denominated in it: the dead pool's recovery when the generation is
     *       CONTINUING in that quote, plus whatever the hook accrued in it. This
     *       is the case that makes "the guild rotates into USDG, the generation
     *       dies, and its successor is reborn in USDG" work end to end.
     *    2. NATIVE — the default, and the only denomination the floor vault and
     *       the native fee reserve can ever hold.
     *    3. `oldQuote` — last resort. A non-native generation whose native income
     *       was zero can still be reborn IN ITS OWN QUOTE rather than frozen.
     *       Without this leg, "proposal wants ETH, we hold only USDG" is a brick.
     *
     *  There is deliberately NO SWAP here. Converting the recovered value would
     *  need a route, and a route on a permissionless entrypoint is either
     *  attacker-supplied (it prices the treasury's own trade) or new governed
     *  storage. Both are a larger surface than the feature earns: the guild
     *  already changes a LIVE generation's denomination through
     *  {RedemptionExt.rotateSlice}, deliberately and reversibly, and the rebirth
     *  then inherits it via leg 1. Switching quote AT the rebirth is the one thing
     *  this does not do, and it is the right thing to leave out.
     *
     *  NOTHING HERE REVERTS. Both releases are try/catch'd — `releaseRelaunchETH`
     *  legitimately reverts `NoETHToRelease` at zero, and a reserve we cannot pull
     *  must never be the reason the machine cannot be reborn (red-team B-06/L-3).
     *
     *  Closing the dying floor vault is folded in here rather than left at the call
     *  site purely for EIP-170: the registry could not afford both this call and
     *  its own try/catch block. The sweep is returned so the caller can still size
     *  `crystallizeCollection` from it.
     *
     * @param hookAddr        the CauldronHook holding both reserves
     * @param wantQuote       the quote the winning proposal asked for (0 = native)
     * @param oldQuote        the DYING generation's quote — what `recovered` is in
     * @param recovered       quote-side value recovered from the dead LP
     * @param oldVault        the dying generation's floor vault (0 = none)
     * @return quoteUsed      the asset the newborn pool will be priced in
     * @return amount         how much of it there is, in ITS OWN units
     * @return vaultSwept     native ether recovered from the dying floor vault
     */
    function seedFunding(
        address hookAddr,
        address wantQuote,
        address oldQuote,
        uint256 recovered,
        address oldVault
    ) external returns (address quoteUsed, uint256 amount, uint256 vaultSwept) {
        //  BEST-EFFORT (red-team L-3). `close()` ends in
        //  `registry.call{value: swept}("")` and reverts `TransferFailed` if that
        //  send fails — reachable whenever the vault holds ether (anyone may donate
        //  to its `receive()`) and the registry cannot accept it. The floor sweep is
        //  an optimisation; the rebirth is the product.
        if (oldVault != address(0)) {
            try IVaultCloseOps(oldVault).close() returns (uint256 s) { vaultSwept = s; } catch {}
        }

        //  ── "CAN FUND" MUST NOT MEAN "HOLDS ONE WEI" (red-team) ─────────────
        //  Each branch below used to be taken on a bare `> 0`, and the `return`
        //  is unconditional — so the FIRST denomination holding any dust won,
        //  and the later branches were never consulted.
        //
        //  `relaunchAsset` is keyed per asset and credited from whatever asset a
        //  fee arrived in (CauldronHook._creditReserve:1150, keyed on `_feeAsset`
        //  set per swap at :1378), and every registry-opened pool is tracked and
        //  charges fees (:599). So any guild that has ever diversified into a
        //  second quote carries a balance in it from ordinary trading — and one
        //  wei of it outranked a 25 ETH position. Measured: `seedFunding` chose
        //  (USDG, 1) over 20 ETH recovered plus a 5 ETH reserve, and `relaunch()`
        //  passes that straight to `_seedGeneration` as the newborn's entire
        //  book, since `totalETH == 1` clears the `NoLiquidityToSeed` guard.
        //
        //  The value abandoned this way does not come back. `recovered` is
        //  already sitting in the registry and nothing in the normal cycle spends
        //  a loose registry balance — only `migrateToSuccessor` and the
        //  timelocked `emergencySweep` do, both break-glass.
        //
        //  RANKING ACROSS ASSETS WOULD NEED A PRICE, and putting an oracle in the
        //  one function that must never be the reason the machine cannot be
        //  reborn is a bad trade. So the rule is not "pick the biggest" but the
        //  weaker, price-free one: NEVER STRAND `recovered`. It is value already
        //  in hand that cannot change denomination without a swap, so a request
        //  in a different asset is honoured only when there is nothing to
        //  abandon. Rotating the quote at a rebirth therefore requires the
        //  treasury to have been rotated first (QuoteRotator), which is the
        //  supported order anyway.
        //
        //  This cannot brick: when `recovered > 0` exactly one of branches 2 and
        //  3 is reachable and both include `recovered`, so a state that returned
        //  a funded answer before still returns one. When `recovered == 0` every
        //  branch behaves exactly as it did.
        //
        //  ── `vaultSwept` IS WEI, AND ONLY THE NATIVE BRANCH MEASURES IN WEI
        //     (blind red-team X5c) ────────────────────────────────────────────
        //  `CauldronVault.close()` (:119) sweeps `address(this).balance` — always
        //  native. The caller feeds this third return straight into
        //  `crystallizeCollection` as the NUMERATOR over `totalETH`
        //  (Registry:1026-1028 → PoolOps:1356 `mulDiv(swept, activeBase, totalETH)`),
        //  and `totalETH` is the SECOND return, denominated in whatever quote the
        //  branch below picked. Reporting wei out of branch 1 or 3 therefore
        //  divided wei by 6-decimal USDG units: ~20 gwei donated to the dying
        //  vault (its `receive()` is open to anyone) crystallized the dead
        //  collection's entitlement at the whole newborn active tranche, and
        //  `CollectionLedger` (:143-154) has no downward adjuster.
        //
        //  Pricing wei into the new quote would need an oracle in the one
        //  function that must never be the reason the machine cannot be reborn —
        //  the trade this function already refuses to make. The honest answer is
        //  that on a non-native rebirth the swept ether does NOT enter the
        //  newborn's book at all (branches 1 and 3 seed from `recovered` + the
        //  per-asset reserve; the wei just lands in the registry), so the dead
        //  collection bought none of the new supply with it and its ETH-sized
        //  entitlement is zero. Only branch 2 folds `vaultSwept` into the amount
        //  it returns, so only branch 2 may report it: numerator and denominator
        //  then come from the same addition and cannot disagree.
        //
        //  ── "CAN FUND" ALSO MUST NOT MEAN "HOLDS LESS THAN THE PRICE MATH CAN
        //     EXPRESS" (audit Z-01 — High) ───────────────────────────────────
        //  Every branch below used to answer on a bare `> 0`, and the registry's only
        //  pre-seed solvency check is `if (totalETH == 0) revert NoLiquidityToSeed();`
        //  (CauldronRegistry:994) — a test against ZERO, in an amount denominated in
        //  whatever quote we pick here. The very next statement is
        //  `governor.markConsumed(winId)`, and everything after it is on the side of
        //  the line where, as the comment block above it says, "reverting ... is what
        //  must never happen".
        //
        //  `_greenCandle` then prices the newborn with `_sqrtPrice(TOTAL_SUPPLY,
        //  ethActive)`, which cannot represent a quote amount below
        //  `TOTAL_SUPPLY / 2**64` = 42,121,254 BASE UNITS of that quote. In ether that
        //  is 42 gwei and never binds; in a 6-decimal quote it is 42.12 tokens, and
        //  `_pullAsset` will hand over exactly that kind of amount — the hook's
        //  per-asset relaunch reserve is credited from whatever asset each swap fee
        //  arrived in, so a guild that has traded a USDG pair lightly holds tens of
        //  USDG there, and a dead position with zero liquidity makes `recovered == 0`
        //  perfectly ordinary. The result was a revert behind `markConsumed`: the
        //  consumption rolled back, the same proposal won again, and the machine could
        //  never be reborn.
        //
        //  {MIN_SEED_UNITS} carries 16x headroom over that hard floor because the
        //  binding quantity is `ethAmt * activeTok / totalTokens`, not `ethAmt`. An
        //  amount below it is treated as NOT FUNDING — we fall through to the next
        //  denomination, and if none qualifies we return zero so the registry reverts
        //  `NoLiquidityToSeed` on the SAFE side of `markConsumed`, which is
        //  recoverable by design: the proposal stays live and a later call succeeds
        //  once the machine holds enough.
        //
        // 1. The proposal's choice, if value already exists in that denomination.
        if (wantQuote != address(0) && (recovered == 0 || oldQuote == wantQuote)) {
            uint256 p = (oldQuote == wantQuote ? recovered : 0) + _pullAsset(hookAddr, wantQuote);
            if (p >= MIN_SEED_UNITS) return (wantQuote, p, 0);
        }
        // 2. Native — recovery counts toward it only if the dead pool WAS native,
        //    so this branch is skipped when it would abandon a non-native one.
        if (recovered == 0 || oldQuote == address(0)) {
            uint256 n = (oldQuote == address(0) ? recovered : 0) + vaultSwept + _pullEth(hookAddr);
            if (n >= MIN_SEED_UNITS) return (address(0), n, vaultSwept);
        }
        // 3. Last resort: the dying generation's own quote.
        if (oldQuote != address(0) && recovered > 0) {
            uint256 o = recovered + _pullAsset(hookAddr, oldQuote);
            if (o >= MIN_SEED_UNITS) return (oldQuote, o, 0);
        }
        return (address(0), 0, 0);
    }

    /// @dev Best-effort pull of the hook's per-asset relaunch reserve. This is also
    ///      the FIRST caller `releaseRelaunchAsset` has ever had (red-team L-1): the
    ///      function was registry-gated with no registry function reaching it, so a
    ///      non-native generation's fees accrued behind a door only a contract
    ///      without the key could open.
    function _pullAsset(address hookAddr, address asset) private returns (uint256 got) {
        try IHookReserves(hookAddr).releaseRelaunchAsset(asset) returns (uint256 g) { got = g; } catch {}
    }

    /// @dev Best-effort pull of the hook's NATIVE relaunch reserve. Reverts
    ///      `NoETHToRelease` at zero and `SendFailed` if the counter has outrun the
    ///      balance, so the guard replaces the caller's old `> 0` pre-check too.
    function _pullEth(address hookAddr) private returns (uint256 got) {
        try IHookReserves(hookAddr).releaseRelaunchETH() returns (uint256 g) { got = g; } catch {}
    }

    function sendAsset(address asset, address to, uint256 amount) external {
        if (amount == 0) return;
        if (asset == address(0)) {
            (bool ok, ) = to.call{value: amount}("");
            require(ok, "send");
        } else {
            (bool ok, bytes memory ret) =
                asset.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
            require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "send");
        }
    }

    function _balance(address asset) private view returns (uint256) {
        return asset == address(0) ? address(this).balance : IERC20(asset).balanceOf(address(this));
    }

    /// @dev RECOVERY IS MEASURED ON THE QUOTE SIDE, NOT ON THE ETHER BALANCE.
    ///
    ///  This used to read `address(this).balance` for the first return value. That
    ///  is only the recovered quote when the quote IS native: `TAKE_PAIR` hands
    ///  currency0 to the registry, and for an ERC20-quoted generation that arrives
    ///  as a TOKEN BALANCE and moves `address(this).balance` not at all. So a
    ///  non-native generation reported ZERO recovered quote, `relaunch()` summed
    ///  `totalETH == 0` and reverted `NoLiquidityToSeed()` — rolling back
    ///  `markConsumed` and bricking the machine permanently, the same class as
    ///  B-05's three walls and hidden behind them (they fired first).
    ///
    ///  `key.currency0` IS the quote by the watermark invariant (`deployTokenAbove`
    ///  mines the token above QUOTE_WATERMARK and no quote at or above it can be
    ///  allowlisted), so the right asset is already in scope — no signature change,
    ///  and therefore no bytecode cost at either registry call site.
    function removeAll(IPositionManagerOps pm, uint256 positionId, PoolKey memory key, address token)
        external
        returns (uint256 quoteRecovered, uint256 tokensRecovered)
    {
        uint128 liquidity = pm.getPositionLiquidity(positionId);
        if (liquidity == 0) return (0, 0);

        address quote = Currency.unwrap(key.currency0);
        uint256 ethBefore = _balance(quote);
        uint256 tokBefore = IERC20(token).balanceOf(address(this));

        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR), uint8(Actions.BURN_POSITION)
        );
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(positionId, liquidity, uint128(0), uint128(0), bytes(""));
        params[1] = abi.encode(key.currency0, key.currency1, address(this));
        params[2] = abi.encode(positionId, uint128(0), uint128(0), bytes(""));

        pm.modifyLiquidities(abi.encode(actions, params), block.timestamp + 120);

        quoteRecovered = _balance(quote) - ethBefore;
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
        //  ── THE OG TRANCHE MAY NOT DRAW THE FORGED TRANCHE'S FLOOR ──────────
        //  On the iteration-#2 continuation the generation's collection IS the
        //  MiFrens contract, OGs included — but the pot this pays from was
        //  credited with the FORGED share only (see `routeLiveBuyback` above),
        //  and the matching vault is deliberately given
        //  `floorOffset = genesisShares` for exactly that reason.
        //  {CauldronVault.redeem} enforces it with `tokenId <= floorOffset`;
        //  this path had no equivalent, so an OG could recycle against the
        //  forged pot at a floor computed over every fren. Each one that did
        //  also incremented the ledger's shared `retired`, permanently
        //  destroying a unit of forged capacity — and the only decrementer,
        //  `buyback`, reverts once the floor reaches zero, so it could not be
        //  undone. OGs keep their own exit, `redeemOgFren`.
        //
        //  The offset is ASKED OF THE COLLECTION rather than passed in, so the
        //  guard configures itself: only the MiFrens continuation answers
        //  `GENESIS_SUPPLY`, and a plain brew collection returns no data, which
        //  leaves the offset at zero and the check inert — which is correct,
        //  because a plain brew has no OG tranche to protect.
        (bool hasOg, bytes memory ogRet) =
            collection.staticcall(abi.encodeWithSignature("GENESIS_SUPPLY()"));
        if (hasOg && ogRet.length == 32) {
            uint256 ogCount = abi.decode(ogRet, (uint256));
            if (ogCount != 0 && tokenId <= ogCount) revert("og tranche");
        }
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
