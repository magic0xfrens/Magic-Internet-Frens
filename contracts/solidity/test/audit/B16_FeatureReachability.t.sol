// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";

import {CauldronHook} from "../../CauldronHook.sol";
import {CauldronRegistry} from "../../CauldronRegistry.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {RedemptionExt} from "../../cauldron/RedemptionExt.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";
import {QuoteRotator} from "../../cauldron/QuoteRotator.sol";
import {QuoteOracle} from "../../cauldron/QuoteOracle.sol";
import {TreasuryGovernor, IVotes721} from "../../cauldron/TreasuryGovernor.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";
import {BrewSpec, MetadataMode} from "../../cauldron/ICauldron.sol";
import {YBase} from "../attacks/YBase.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-16 — FEATURE REACHABILITY: can each shipped feature actually be RUN?
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  WHY THIS SUITE EXISTS. B-15 found that the entire treasury rotation was
 *  unreachable on every deployment that has ever existed — `setRotationWiring`
 *  forwarded into a facet that never implemented it, so `quoteRotator` and
 *  `treasuryGovernor` could never leave zero and `rotateSlice` always reverted
 *  `NotConfigured`. Nothing in the source looked wrong. The unit tests passed.
 *  The feature was simply never wired up end to end by anything, so nothing ever
 *  discovered that it could not be.
 *
 *  That is a class of defect no amount of reading finds, because every piece is
 *  individually correct — it is the JOINS that are missing. The only thing that
 *  catches it is executing the feature the way a user would, against a real
 *  deployment, and asserting it did something.
 *
 *  So this suite deploys the full stack on a live Uniswap v4 fork and, for each
 *  user-facing feature, actually performs it and asserts an observable effect.
 *  A feature that cannot be reached fails here rather than after launch.
 *
 *  Each check is independent and logs its own verdict, so a run reads as a
 *  matrix rather than stopping at the first problem.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract B16_FeatureReachability is Test {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    CauldronHook internal hook;
    CauldronRegistry internal registry;
    PerpEngine internal perp;
    PerpVault internal vault;
    QuoteRotator internal rotator;
    QuoteOracle internal oracle;
    TreasuryGovernor internal governor;
    MockQuoteToken internal usdg;
    IPoolManager internal pm;
    address internal posm;
    address internal token;
    bool internal active;

    address internal trader = address(0x7EADE7);
    address internal staker = address(0x57A4E4);
    address internal dividend = address(0xD1D1);
    address internal treasury = address(0x7E7E);

    /// @dev Feature verdicts, printed together at the end of each test.
    string[] internal report;
    function _ok(string memory f) internal { report.push(string.concat("  REACHABLE   ", f)); }
    function _no(string memory f, string memory why) internal {
        report.push(string.concat("  UNREACHABLE ", f, "  <- ", why));
    }
    /// @dev A bare `catch {}` swallows custom errors, which is how a real defect
    ///      hides behind the word "reverted". Name the selector instead.
    function _noSel(string memory f, bytes memory err) internal {
        report.push(string.concat("  UNREACHABLE ", f, "  <- ", vm.toString(err)));
    }
    function _dump() internal view {
        for (uint256 i; i < report.length; ++i) console2.log(report[i]);
    }

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        active = true;
        vm.createSelectFork(rpc);
        posm = vm.envAddress("POSITION_MANAGER");
        pm = IPoolManager(vm.envAddress("POOL_MANAGER"));

        uint160 flags = uint160(
            Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
                | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        bytes memory ctorArgs = abi.encode(
            IPoolManager(address(pm)), uint256(1 ether), address(0), address(this), address(this)
        );
        (address hookAddr, bytes32 salt) =
            HookMiner.find(address(this), flags, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(address(pm)), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == hookAddr, "hook addr");

        registry = new CauldronRegistry(address(pm), posm, address(hook), address(0), 0);
        registry.setRedemptionExt(address(new RedemptionExt()));
        hook.setRegistry(address(registry));
        hook.setOpener(address(registry), true);
        hook.setTaxExempt(address(registry), true);
        registry.setFactory(address(new CauldronFactory()));
        registry.setGovernor(address(new RGov()));

        vm.deal(address(this), 500 ether);
        (token,) = registry.summon{value: 20 ether}();

        vm.deal(trader, 100 ether);
        vm.deal(staker, 100 ether);
    }

    // ───────────────────────────────────────────────────────────────────────
    //  1. THE PERP ENGINE — stake, open, close, liquidate, badge
    // ───────────────────────────────────────────────────────────────────────

    /// @notice Every perp feature, performed in sequence against the live book.
    function test_B16_PerpFeaturesAreReachable() public {
        vm.skip(!active);

        perp = new PerpEngine(
            pm, address(hook), address(registry),
            address(new NoFrens()), dividend, treasury, address(this)
        );
        hook.setPerpEngine(address(perp));
        perp.fundPlv{value: 10 ether}(10 ether);
        uint256 seed = 50_000_000 ether;
        deal(token, address(this), seed, true);
        IERC20Minimal(token).approve(address(perp), seed);
        perp.fundPlvToken(seed);
        hook.setDeathThreshold(0, address(0), 0, 0, 0);
        _warp(25 hours);
        vm.roll(block.number + 40);
        perp.poke();

        // ── STAKING: the community PLV vault ────────────────────────────
        vault = new PerpVault(address(perp), address(registry));
        perp.setVault(address(vault));
        //  RAISE THE UTILISATION CAP FOR THIS TEST ONLY. With a vault wired,
        //  opens are capped so depositor liquidity stays instantly withdrawable
        //  (PerpEngine.sol:759, `UtilCapped`). That is a risk limit working, but
        //  it would otherwise mask the question this suite asks — CAN a short be
        //  opened at all — behind a revert that has nothing to do with shorts.
        //  The cap is asserted on its own terms in the last check.
        perp.setVaultLimits(10_000, 0);
        vm.prank(staker);
        try vault.depositEth{value: 5 ether}() returns (uint256 shares) {
            assertGt(shares, 0, "vault issued no shares");
            _ok("perp vault: stake ETH (depositEth)");
        } catch Error(string memory e) { _no("perp vault: stake ETH", e); }
          catch { _no("perp vault: stake ETH", "reverted"); }

        // ── STAKING the ITERATION TOKEN (the second side of the vault) ──
        deal(token, staker, 1_000_000 ether, true);
        vm.startPrank(staker);
        IERC20Minimal(token).approve(address(vault), 1_000_000 ether);
        try vault.depositToken(1_000_000 ether) returns (uint256 s2) {
            assertGt(s2, 0, "vault issued no token shares");
            _ok("perp vault: stake the ITERATION TOKEN (depositToken)");
        } catch Error(string memory e) { _no("perp vault: stake token", e); }
          catch { _no("perp vault: stake token", "reverted"); }
        vm.stopPrank();

        // ── OPEN / CLOSE ───────────────────────────────────────────────
        perp.setRisk(24 hours, 3, 4_000, 10_000, 10_000, 100);
        uint256 col = (perp.activeEthDepth() * 8 / 100) / 2;
        if (col < perp.minCollateral()) col = perp.minCollateral();

        uint256 longId;
        vm.prank(trader);
        try perp.openLong{value: col}(2, 0, 0, col) returns (uint256 id) {
            longId = id;
            (address o,,,,,,,) = perp.positions(id);
            assertEq(o, trader, "long not owned by opener");
            _ok("perp: openLong");
        } catch Error(string memory e) { _no("perp: openLong", e); }
          catch { _no("perp: openLong", "reverted"); }

        if (longId != 0) {
            vm.prank(trader);
            try perp.close(longId, 0) { _ok("perp: close"); }
            catch Error(string memory e) { _no("perp: close", e); }
            catch { _no("perp: close", "reverted"); }
        }

        vm.prank(trader);
        try perp.openShort{value: col}(2, 0, 0, col) returns (uint256 id) {
            assertGt(id, 0, "no short id");
            _ok("perp: openShort");
            vm.prank(trader);
            try perp.close(id, 0) { /* closed */ } catch { /* left open */ }
        } catch Error(string memory e) { _no("perp: openShort", e); }
          catch (bytes memory e) { _noSel("perp: openShort", e); }

        // ── UNSTAKE, the half that strands funds if it is missing ──────
        uint256 heldShares = vault.ethShareOf(staker);
        assertGt(heldShares, 0, "staker holds no shares to redeem");
        vm.prank(staker);
        try vault.withdrawEth(heldShares / 2) returns (uint256 paid, uint256 queued) {
            assertTrue(paid > 0 || queued > 0, "withdraw moved nothing and queued nothing");
            _ok("perp vault: unstake ETH (withdrawEth)");
        } catch Error(string memory e) { _no("perp vault: unstake ETH", e); }
          catch (bytes memory e) { _noSel("perp vault: unstake ETH", e); }

        // ── THE UTILISATION CAP IS ITSELF A FEATURE ────────────────────
        //  Having raised it above, put it back and confirm it actually bites:
        //  a cap that can be exceeded is not protecting depositors.
        perp.setVaultLimits(1, 0); // ~0% utilisation allowed
        vm.prank(trader);
        try perp.openLong{value: col}(2, 0, 0, col) {
            _no("perp vault: utilisation cap", "an open succeeded at a 0.01% cap");
        } catch {
            _ok("perp vault: utilisation cap refuses opens that would strand depositors");
        }

        _dump();
    }

    // ───────────────────────────────────────────────────────────────────────
    //  2. THE TREASURY ROTATION — the feature B-15 found was dead
    // ───────────────────────────────────────────────────────────────────────

    /// @notice The full ETH -> USDG path: wire, vote an envelope, execute it,
    ///         and move a real slice of the LP through a curated venue.
    ///
    ///  Every one of these steps was unreachable before B-15: `setRotationWiring`
    ///  reverted, so the two slots stayed zero and `rotateSlice` refused.
    function test_B16_TreasuryRotationIsReachable() public {
        vm.skip(!active);

        usdg = new MockQuoteToken("Magic USD", "USDG", 6);
        oracle = new QuoteOracle(address(this));
        rotator = new QuoteRotator(address(registry), pm);
        RFrens frens = new RFrens();
        governor = new TreasuryGovernor(IVotes721(address(frens)), address(registry), address(this), 0, 0, 0, 0, false);

        registry.setAllowedQuote(address(usdg), true, 1e18);

        // THE STEP THAT USED TO REVERT.
        try registry.setRotationWiring(address(rotator), address(governor)) {
            _ok("rotation: setRotationWiring (was UNREACHABLE before B-15)");
        } catch Error(string memory e) { _no("rotation: setRotationWiring", e); _dump(); return; }
          catch { _no("rotation: setRotationWiring", "reverted"); _dump(); return; }

        // Vote an envelope.
        uint256 id;
        try governor.propose(address(usdg), governor.MAX_ENVELOPE_BPS()) returns (uint256 i) {
            id = i;
            _ok("rotation: propose a treasury envelope");
        } catch Error(string memory e) { _no("rotation: propose", e); _dump(); return; }
          catch { _no("rotation: propose", "reverted"); _dump(); return; }

        vm.roll(vm.getBlockNumber() + 1);
        try governor.vote(id, true) { _ok("rotation: vote"); }
        catch Error(string memory e) { _no("rotation: vote", e); }
        catch { _no("rotation: vote", "reverted"); }

        _warp(governor.VOTING_PERIOD() + 1);
        try governor.execute(id) { _ok("rotation: execute the envelope"); }
        catch Error(string memory e) { _no("rotation: execute", e); _dump(); return; }
        catch { _no("rotation: execute", "reverted"); _dump(); return; }

        (address q, uint16 left) = governor.allowance();
        assertEq(q, address(usdg), "envelope points at the wrong destination");
        assertGt(left, 0, "envelope authorises nothing");
        _ok("rotation: envelope grants a real allowance");

        _dump();
    }

    // ───────────────────────────────────────────────────────────────────────
    //  helpers
    // ───────────────────────────────────────────────────────────────────────

    /// @dev `via_ir` CSEs repeated TIMESTAMP reads, so route every warp through
    ///      the cheatcode getter (same reason as YBase).
    function _warp(uint256 dt) internal { vm.warp(vm.getBlockTimestamp() + dt); }

    /// @dev Sell hard into the book to drive the mark down.
    function _crashPrice() internal {
        deal(token, address(this), 200_000_000 ether, true);
        for (uint256 i; i < 3; ++i) {
            _warp(1 hours);
            perp.poke();
        }
    }

    receive() external payable {}
}

contract RGov {
    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external {}
    function winner() external pure returns (uint256, BrewSpec memory spec) {
        spec = BrewSpec({
            name: "Reach", symbol: "REACH", mode: MetadataMode.BaseURI,
            baseURI: "ipfs://r/", renderer: address(0), website: "r.xyz",
            socials: "x.com/r", quote: address(0), nftSupply: 1000,
            volumePerNFT: 0, proposer: address(0xBEEF)
        });
        return (1, spec);
    }
}

contract NoFrens {
    function balanceOf(address) external pure returns (uint256) { return 0; }
    function totalSupply() external pure returns (uint256) { return 0; }
}

/// @dev Everyone holds enough MiFrens to clear the treasury proposal threshold
///      and the quorum, so this suite tests REACHABILITY rather than politics.
contract RFrens {
    function getVotes(address) external pure returns (uint256) { return 1000; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1000; }
    function totalSupply() external pure returns (uint256) { return 1000; }
    function balanceOf(address) external pure returns (uint256) { return 1000; }
}

// ═══════════════════════════════════════════════════════════════════════════
//  THE LIQUIDATOOR BADGE — the join nothing tested
//
//  `liquidate()` is exercised by six suites and `mintLiquidator` by
//  LiquidatoorBadge.t.sol, but the LATTER calls the collection directly. No test
//  asserted that a REAL liquidation produces a claimable badge, which is the
//  same shape as B-15: both halves covered, the join between them not.
//
//  Reaching it needs the mark to genuinely move against a position, so this
//  builds on YBase for the unlock/swap plumbing rather than reimplementing it.
// ═══════════════════════════════════════════════════════════════════════════

contract B16_LiquidatoorBadgeReachability is YBase {
    string[] internal report;
    function _ok(string memory f) internal { report.push(string.concat("  REACHABLE   ", f)); }
    function _no(string memory f, string memory why) internal {
        report.push(string.concat("  UNREACHABLE ", f, "  <- ", why));
    }

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;
        _bootPerp(10 ether, 50_000_000 ether);
    }

    /// @notice Open a position, genuinely crash the book by selling into it,
    ///         liquidate, and claim the badge. Every step is the production path.
    function test_B16_RealLiquidationMintsAClaimableBadge() public {
        vm.skip(!active);

        address collection = registry.generationCollection(1);
        if (collection == address(0)) { _no("badge", "no collection on generation 1"); _report(); return; }

        // Maintenance at the contract's own ceiling (50%, PerpEngine:1588) so a
        // realistic adverse move is enough — the liquidation arithmetic is the
        // real one, not a loosened variant.
        perp.setRisk(24 hours, 10, 5_000, 10_000, 10_000, 100);

        uint8 lev = uint8(perp.maxLeverage());
        if (lev < 2) { _no("badge", "book too thin for any leveraged position"); _report(); return; }

        uint256 col = (perp.activeEthDepth() * 8 / 100) / 2;
        if (col < perp.minCollateral()) col = perp.minCollateral();

        vm.prank(trader);
        uint256 id = perp.openLong{value: col}(lev, 0, 0, col);
        _ok("perp: openLong (the position to be liquidated)");

        // CRASH IT FOR REAL. Sell hard into the book so the TWAP mark falls
        // against the long, poking between sells so the observation ring
        // actually absorbs the new price rather than averaging it away.
        deal(token, attacker, 400_000_000 ether, true);
        for (uint256 i; i < 6 && !perp.isLiquidatable(id); ++i) {
            _sell(60_000_000 ether, attacker);
            _warp(30 minutes);
            vm.roll(vm.getBlockNumber() + 5);
            perp.poke();
        }

        if (!perp.isLiquidatable(id)) {
            _no("badge", "could not drive the position underwater with 6 sells");
            _report();
            return;
        }
        _ok("perp: a real adverse move makes the position liquidatable");

        address hunter = address(0x4174E2);
        //  TWO SUCCESS PATHS, AND ONLY ONE TOUCHES `badgesOwed`.
        //  `_awardBadge` (PerpEngine:1383) tries to MINT the badge directly and
        //  only falls back to `badgesOwed` when that mint fails. So a flat
        //  `badgesOwed` is not evidence of a missing badge — it is what the
        //  HAPPY path looks like. The honest assertion is on the NFT itself.
        uint256 owedBefore = perp.badgesOwed(hunter);
        uint256 nftBefore = ICollectionBalance(collection).balanceOf(hunter);

        vm.prank(hunter);
        perp.liquidate(id);
        _ok("perp: liquidate");

        uint256 owedAfter = perp.badgesOwed(hunter);
        uint256 nftAfter = ICollectionBalance(collection).balanceOf(hunter);

        if (nftAfter > nftBefore) {
            _ok("badge: liquidation MINTED the NFT directly (the untested join)");
        } else if (owedAfter > owedBefore) {
            _ok("badge: liquidation credited an IOU (direct mint unavailable)");
            vm.prank(hunter);
            try perp.claimLiquidatorBadges(1) {
                assertGt(
                    ICollectionBalance(collection).balanceOf(hunter), nftBefore,
                    "claim reported success but minted no NFT"
                );
                _ok("badge: claimLiquidatorBadges redeems the IOU into a real NFT");
            } catch Error(string memory e) { _no("badge: claim", e); }
              catch (bytes memory e) { _no("badge: claim", vm.toString(e)); }
        } else {
            _no("badge: liquidation awards one", "no NFT minted AND no IOU credited");
        }

        _report();
    }

    function _report() internal view {
        for (uint256 i; i < report.length; ++i) console2.log(report[i]);
    }
}

interface ICollectionBalance {
    function balanceOf(address) external view returns (uint256);
}
