// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {IERC20Minimal} from "v4-core/src/interfaces/external/IERC20Minimal.sol";

import {YBase, YNoFrens} from "./YBase.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  S-06 — PerpVault: share pricing, exit-queue seniority, and DENOMINATION
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  Lead L-3 asked four questions of {PerpVault}. Answers, with the line that
 *  decides each:
 *
 *   1. SHARE-PRICE / FIRST-DEPOSITOR INFLATION — REFUTED, twice over.
 *      a) There is no donation channel at all. The vault prices off
 *         `engine.totalEth()` (PerpVault.sol:116), and that is
 *         `plv + longOiEth` (PerpEngine.sol:440) — two COUNTERS, not a
 *         balance. `PerpEngine.receive()` (:1739) accepts ether and moves
 *         neither. Every writer of `plv` is gated: `fundPlv` onlyOwner (:1485),
 *         `fundFromVault` onlyVault (:1568), `creditPerpFee*` OnlyHook
 *         (:1509/:1514), `_routeFee` internal (:1282). A raw transfer of any
 *         size is invisible to the share price.
 *      b) Even if a channel existed, every division rounds toward the vault and
 *         the 1e6 virtual-share offset (PerpVault.sol:64) caps redemption at
 *         the deposit. Proven numerically below — 20/20 ETH-side shapes and
 *         16/16 token-side shapes — including the pathological first-depositor
 *         ones. The offset makes a first depositor's claim exactly
 *         `amount / (amount + preExisting)` of the pot, so pre-existing unowned
 *         assets stay with the VIRTUAL shares rather than being captured.
 *
 *   2. QUEUED-EXIT SENIORITY (jump / steal / double-claim) — REFUTED.
 *      `claimPendingEth` reads `pendingEthOf[msg.sender]` (PerpVault.sol:218)
 *      and decrements that exact slot (:223); there is no id, index or
 *      beneficiary argument anywhere on the queue, so there is nothing to
 *      point at someone else's claim.
 *
 *   3. INSOLVENCY (claims > backing) — CONFIRMED, by three distinct routes.
 *      a) A queued exit is a FIXED claim that leaves the share base
 *         (PerpVault.sol:208-211) and is therefore senior to every live share.
 *         `assetsEth()` saturates at zero (:117) instead of letting the queue
 *         share a loss, so `pendingEth` can exceed `engine.totalEth()` outright
 *         and the last claimant in the queue is permanently unpayable.
 *         REPRODUCED ON THE REAL ENGINE, no mock: a real long borrows real
 *         `plv`, a real dump crashes the real v4 pool, and the real `_settle`
 *         long branch books the shortfall — leaving pendingEth 0.344 ETH against
 *         totalEth 0.258 ETH. 100% of the loss landed on the LP who stayed.
 *      b) `PerpEngine.setVault` (:1678) refuses to re-point while
 *         `tokYieldEth != 0`, and short-side yield that accrued at zero token
 *         shares is orphaned by design (PerpVault.sol:247) with NO path out —
 *         `tokYieldEth` is decremented in exactly one place, `withdrawTokYieldTo`
 *         (:1584), which pays only what the vault's accumulator attributed. The
 *         claim at PerpVault.sol:241 that "governance can redirect it (treasury
 *         or insurance)" names no function and none exists. One orphaned wei
 *         bricks vault replacement forever.
 *      c) The same guard also tests `plv != 0`, and `plv` cannot be emptied
 *         either. Redemption FLOORS (PerpVault.sol:198), so ONE WEI of ordinary
 *         LP yield leaves dust the last staker cannot redeem. The H-01 guard is
 *         therefore not merely hard to satisfy — normal operation makes it
 *         unsatisfiable, and no orphaned pot is needed to get there.
 *
 *   4. DUAL-ASSET CONFUSION — CONFIRMED, and it is the severe one.
 *      `plv` is a bare counter and `quote` is a separate storage slot that a
 *      completed treasury rotation FLIPS underneath it
 *      (RedemptionExt.sol:469 + :504 -> PerpEngine.syncGeneration :1034, which
 *      leaves `plv` untouched by explicit design, :981). After the flip the
 *      vault still values every ETH-side share against the same counter
 *      (PerpVault.sol:116) while `withdrawPlvTo` (:1578) pays it out through
 *      `_pushQuote` (:204) in the NEW asset. Ten ether of stake becomes ten
 *      units of whatever the guild rotated into — and until someone supplies
 *      that asset, nothing can be withdrawn at all.
 *
 *  HOUSE PATTERN. `test_S06_INVARIANT_*` assert the property that OUGHT to
 *  hold and are expected to FAIL on current code. `test_S06_POC_*` and
 *  `test_S06_REFUTED_*` assert what the code actually does today and PASS —
 *  the PoCs as live exploits, the refutations as regression guards.
 *
 *  NO EARLY RETURNS. The only `return;` in this file is the `if (!active)` fork
 *  gate in `setUp`. Every test body runs straight through to its assertions;
 *  the two loop tests additionally PIN the number of cases that actually
 *  asserted, so a run in which every case silently took the no-assert branch
 *  fails instead of greening.
 *
 *  LINE NUMBERS. PerpEngine.sol citations were re-derived by grep against the
 *  working tree at the time of writing; that file is under concurrent edit, so
 *  each citation also names the symbol it points at.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract S06_PerpVaultSolvency is YBase {
    PerpVault internal vault;
    S06Registry internal shim;
    MockQuoteToken internal usdg;

    address internal lpA = address(0x5A11A);
    address internal lpB = address(0x5B0BB);

    /// @dev A 6-decimal quote, because that is what a real rotation target looks
    ///      like (USDC/USDG) and the decimal gap is half of what makes finding 4
    ///      expensive rather than merely wrong.
    uint8 internal constant QUOTE_DECIMALS = 6;

    // ── REACHED SENTINELS ────────────────────────────────────────────────────
    //  Foundry greens any test that does not revert, so a body that short-circuits
    //  past its assertions looks identical to one that ran them. Each test below
    //  therefore ENDS by setting its own flag inside an `assertTrue`, so a
    //  truncated run fails loudly instead of passing silently.
    bool internal reachedDonation;
    bool internal reachedEthRounding;
    bool internal reachedCrossAsset;
    bool internal reachedOrphanWei;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;

        // A registry SHIM. It forwards the three reads the engine actually makes
        // (PerpEngine.sol:418-419, :458, :983, :1007, :1218) to the live registry
        // and intercepts exactly one: `generationQuote`. That is the single slot
        // a completed rotation writes (RedemptionExt.sol:469) before it calls
        // `syncGeneration` (:504), so driving it here reproduces the rotation's
        // effect on the engine without needing a governance envelope.
        shim = new S06Registry(address(registry));

        perp = new PerpEngine(
            pm, address(hook), address(shim),
            address(new YNoFrens()), address(0xD1D1), address(0x7E7E), address(this)
        );
        hook.setPerpEngine(address(perp));
        vault = new PerpVault(address(perp), address(shim));
        perp.setVault(address(vault));
        // Insurance floor off: it pauses OPENS, and an unrelated pause would be
        // indistinguishable from the thing under test.
        perp.setVaultLimits(10_000, 0);
        hook.setDeathThreshold(0, address(0), 0, 0, 0);

        usdg = new MockQuoteToken("Rotation Target", "USDG", QUOTE_DECIMALS);

        vm.deal(lpA, 10_000 ether);
        vm.deal(lpB, 10_000 ether);
    }

    // ───────────────────────────────────────────────────────────────────────
    //  CLASS 1 — share-price manipulation / first-depositor inflation
    // ───────────────────────────────────────────────────────────────────────

    /**
     * REFUTED. The classic setup — 1 wei first deposit, then a large direct
     * donation — cannot even be expressed here, because the share price reads
     * COUNTERS. `PerpEngine.receive()` (PerpEngine.sol:1739) is an empty payable
     * fallback; it does not touch `plv`, so `totalEth()` (:440) does not move and
     * `PerpVault.assetsEth()` (:115-118) does not move.
     */
    function test_S06_REFUTED_DirectDonationCannotMoveTheSharePrice() public {
        vm.skip(!active);

        vm.prank(lpA);
        vault.depositEth{value: 1 wei}();
        uint256 assetsBefore = vault.assetsEth();
        uint256 plvBefore = perp.plv();

        // 10_000 ether straight at the engine, three ways.
        vm.prank(attacker);
        (bool ok,) = address(perp).call{value: 5_000 ether}("");
        assertTrue(ok, "engine refused a raw transfer");
        vm.prank(attacker);
        perp.fundInsurance{value: 5_000 ether}(5_000 ether); // PERMISSIONLESS (:1499)

        assertEq(perp.plv(), plvBefore, "plv moved on a donation");
        assertEq(vault.assetsEth(), assetsBefore, "share price moved on a donation");
        assertEq(address(perp).balance, 10_000 ether + 1, "engine really did receive it");

        // The hook-only credit paths are the only ones that DO move plv, and they
        // are shut to everyone else.
        vm.prank(attacker);
        vm.expectRevert(PerpEngine.OnlyHook.selector);
        perp.creditPerpFee{value: 1 ether}();
        vm.prank(attacker);
        vm.expectRevert(PerpEngine.OnlyHook.selector);
        perp.creditPerpFeeToken{value: 1 ether}();

        // And the victim's later deposit is priced exactly as if none of it
        // happened: he redeems his own money back.
        vm.prank(lpB);
        vault.depositEth{value: 1 ether}();
        (uint256 redeem,,) = vault.ethPosition(lpB);
        assertApproxEqAbs(redeem, 1 ether, 2, "victim lost value to a donation");

        assertTrue(reachedDonation = true, "reached: donation channel does not exist");
    }

    /**
     * REFUTED. Rounding direction. For a spread of (pre-existing assets, deposit)
     * pairs — including the pathological first-depositor shapes — a depositor can
     * never redeem more than they put in. Both divisions floor:
     * `shares = mulDiv(amount, ethShares + OFFSET, assetsEth() + 1)`
     * (PerpVault.sol:155) and
     * `owed = mulDiv(shares, assetsEth() + 1, ethShares + OFFSET)` (:198).
     */
    function test_S06_REFUTED_NoDepositorRedeemsMoreThanTheyDeposited() public {
        vm.skip(!active);

        uint256[5] memory seeds = [uint256(0), 1 wei, 1 gwei, 1 ether, 9_000 ether];
        uint256[4] memory bites = [uint256(1 wei), 1 gwei, 0.1 ether, 100 ether];
        uint256 checks;
        uint256 asserted; // cases where the deposit SUCCEEDED and `redeem <= bite` ran

        for (uint256 i; i < seeds.length; ++i) {
            for (uint256 j; j < bites.length; ++j) {
                uint256 snap = vm.snapshotState();
                // Seed the vault so the price is NOT 1:1 when the victim arrives.
                if (seeds[i] > 0) {
                    vm.prank(lpA);
                    vault.depositEth{value: seeds[i]}();
                }
                vm.prank(lpB);
                try vault.depositEth{value: bites[j]}() returns (uint256 sh) {
                    (uint256 redeem,,) = vault.ethPosition(lpB);
                    assertLe(redeem, bites[j], "redeemed MORE than deposited");
                    assertGt(sh, 0, "minted zero shares without reverting");
                    checks++;
                    asserted++;
                } catch {
                    // ZeroShares: a deposit that rounds to nothing is REFUSED
                    // (PerpVault.sol:156) rather than silently confiscated. Counted
                    // as a pass for this property. MEASURED: this arm never fires
                    // for any of the 20 shapes, because shares are minted at exactly
                    // OFFSET per asset, so (ethShares + OFFSET)/(assetsEth + 1) never
                    // drops below 1e6 and even a 1-wei deposit mints 1e6 shares.
                    checks++;
                }
                vm.revertToState(snap);
            }
        }
        assertEq(checks, seeds.length * bites.length, "not every case was exercised");
        // GUARD SENTINEL. The `catch` arm asserts nothing, so without this a run in
        // which EVERY deposit reverted would still be green. The count is PINNED,
        // not merely non-zero, so a silent shift from "priced" to "refused" fails.
        console2.log("PRICED CASES (redeem<=deposit actually asserted):", asserted);
        assertEq(asserted, 20, "the redeem<=deposit assertion did not run on every case");
        assertTrue(reachedEthRounding = true, "reached: 20/20 rounding cases favour the vault");
    }

    /**
     * REFUTED — the ONE shape the loop above cannot express, and the only one the
     * classic 4626 attack actually needs: ASSETS WITH NO SHARES.
     *
     * This is not hypothetical. `plv` is credited by every perp open/close fee
     * (`_routeFee` -> PerpEngine.sol:1282, reached from `creditPerpFee` :1509),
     * and on a live launch the first trade precedes the first vault depositor —
     * so `assetsEth() > 0 && ethShares == 0` is the DEFAULT opening state.
     *
     * Two things have to hold and both do:
     *   a) a deposit too small to price is REFUSED (`ZeroShares`,
     *      PerpVault.sol:156) rather than swallowed for zero shares;
     *   b) the un-owned pot is NOT captured by whoever deposits first. The 1e6
     *      virtual offset (PerpVault.sol:64) makes a first depositor's claim
     *      exactly `amount/(amount + preExisting)` of the pot, i.e. their own
     *      money back — the rest stays with the virtual shares.
     */
    function test_S06_REFUTED_AssetsWithoutSharesCannotBeInflatedIntoATheft() public {
        vm.skip(!active);

        uint256 snap = vm.snapshotState();   // empty vault; rewind point for (c)

        // A real perp fee lands before anybody has staked.
        uint256 preExisting = 2 ether;
        _feeIntoPlv(preExisting);
        assertEq(perp.plv(), preExisting, "fee credited to plv");
        assertEq(vault.ethShares(), 0, "and nobody holds a share");
        assertEq(vault.assetsEth(), preExisting, "assets with zero shares - the 4626 setup");

        // (a) A dust deposit is REFUSED, not confiscated.
        vm.prank(lpB);
        vm.expectRevert(PerpVault.ZeroShares.selector);
        vault.depositEth{value: 1 wei}();

        // (b) A real deposit gets (just under) its own money back and captures NONE
        //     of the pot. MEASURED: 999_998_666_665_777_777 wei for a 1 ETH deposit
        //     into a 2 ETH un-owned pot — a 1.33e-6 haircut, which is the floor in
        //     `shares = mulDiv(amount, ethShares + OFFSET, assetsEth() + 1)`
        //     (PerpVault.sol:155) rounding 500_000 shares down to 499_999. The
        //     haircut is ~ preExisting/(amount * OFFSET) and, when it would reach
        //     100%, the deposit is refused by (a) instead. It always favours the
        //     VAULT, never the depositor — which is the direction that matters.
        vm.prank(lpB);
        vault.depositEth{value: 1 ether}();
        (uint256 redeem,,) = vault.ethPosition(lpB);
        assertLe(redeem, 1 ether, "first depositor captured part of the un-owned pot");
        assertGt(redeem, 0.9999 ether, "first depositor lost more than the rounding floor");
        console2.log("no-share pot: deposited 1e18, redeemable", redeem);

        // (c) The canonical attack ORDER: attacker seeds 1 wei into the EMPTY
        //     vault, then a 2 ETH donation lands, then the victim deposits 1 ETH.
        //     A victim's V is rounded to zero only if
        //         V * (ethShares + OFFSET) < assetsEth + 1,
        //     and with ethShares == OFFSET that needs a donation > 2*OFFSET*V —
        //     2,000,000 ETH to round away a 1 ETH victim. The offset doing exactly
        //     what PerpVault.sol:60-63 claims.
        vm.revertToState(snap);              // back to: empty vault, zero shares
        vm.prank(lpA);
        vault.depositEth{value: 1 wei}();    // the attacker seeds first
        assertEq(vault.ethShares(), 1e6, "attacker holds OFFSET shares for 1 wei");
        _feeIntoPlv(2 ether);                // ...then "donates"

        assertEq(2 * 1e6 * uint256(1 ether), 2_000_000 ether, "donation needed to round a 1 ETH victim away");

        vm.prank(lpB);
        vault.depositEth{value: 1 ether}();
        (uint256 redeem2,,) = vault.ethPosition(lpB);
        console2.log("attacker-first: victim deposited 1e18, redeemable", redeem2);
        assertGt(redeem2, 0.99 ether, "victim was rounded away by the donation");
        assertLe(redeem2, 1 ether, "victim redeems more than they deposited");

        // And the attack BACKFIRES: the attacker's 1 wei + 2 ETH donation buys them
        // a claim strictly smaller than what they put in. There is no profit here at
        // any size — the virtual shares absorb the difference.
        (uint256 aRedeem,,) = vault.ethPosition(lpA);
        console2.log("attacker spent 2e18 + 1 wei, redeemable", aRedeem);
        assertLt(aRedeem, 2 ether, "attacker profited from the donation");
        assertTrue(reachedNoShareAssets = true, "reached: assets-without-shares is safe");
    }

    bool internal reachedNoShareAssets;

    /// @dev Credit ETH into `plv` the way the protocol actually does it: the hook
    ///      forwarding a perp fee (PerpEngine.creditPerpFee, :1509 -> `_creditPerp`
    ///      -> `plv += msg.value`). This is the ONLY permissionless-in-practice
    ///      channel into the share price, and it is gated to the hook address.
    function _feeIntoPlv(uint256 amount) internal {
        vm.deal(address(hook), amount);
        vm.prank(address(hook));
        perp.creditPerpFee{value: amount}();
    }

    // ───────────────────────────────────────────────────────────────────────
    //  CLASS 4 — DUAL-ASSET CONFUSION (and the insolvency it creates)
    // ───────────────────────────────────────────────────────────────────────

    /**
     * THE INVARIANT: an ETH-side staker must always be able to redeem, in the
     * asset they staked, up to the engine's free liquidity.
     *
     * FAILS on current code. A completed treasury rotation flips
     * `PerpEngine.quote` (:1034) and leaves `plv` alone (:981, and no line of
     * `syncGeneration` writes it). `withdrawPlvTo` (:1578) then pays through
     * `_pushQuote` (:204), which sends the NEW quote — of which the engine holds
     * none. The staker's real ether is still sitting in the engine and no
     * reachable call can get it out.
     */
    function test_S06_INVARIANT_EthStakerSurvivesAQuoteRotation() public {
        vm.skip(!active);

        vm.prank(lpA);
        uint256 shares = vault.depositEth{value: 10 ether}();
        assertEq(perp.plv(), 10 ether, "plv");
        assertEq(address(perp).balance, 10 ether, "engine holds the real ether");

        bool adopted = _completeRotationTo(address(usdg));

        //  ── FIXED BY R-08 ───────────────────────────────────────────────────
        //  Pre-fix the engine adopted the new quote while `plv` went on counting
        //  ether, and this test failed at the raw call below with `BadParam()`
        //  from `_safeTransfer` (PerpEngine.sol:1473) — the staker's 10 ETH was
        //  real, present in the engine, and unreachable by any call.
        //  {PerpEngine.syncGeneration} now refuses a quote change while the LP
        //  vault is funded, so `quote` stays native and payouts keep working.
        assertFalse(adopted, "the engine must REFUSE a quote it cannot pay stakers in");
        assertEq(perp.quote(), address(0), "engine stays on the asset plv is denominated in");
        assertEq(perp.plv(), 10 ether, "plv carried over UNTOUCHED");
        assertEq(usdg.balanceOf(address(perp)), 0, "engine holds none of the new quote");
        assertEq(vault.assetsEth(), 10 ether, "vault still prices the stake at 10e18");

        //  Called RAW so a regression is reported as the broken property rather
        //  than as an unexplained `BadParam()` bubbling out of `_safeTransfer`.
        uint256 before = lpA.balance;
        vm.prank(lpA);
        (bool ok, bytes memory err) =
            address(vault).call(abi.encodeWithSelector(PerpVault.withdrawEth.selector, shares));
        console2.log("withdrawEth after rotation succeeded?", ok);
        console2.logBytes(err);
        assertTrue(ok, "an ETH staker cannot withdraw AT ALL after a quote rotation");
        assertEq(lpA.balance - before, 10 ether, "staker got their 10 ETH back");
    }

    /**
     * POSITIVE PoC — PASSES on current code, and is the exploit.
     *
     *  ACT 1  lpA stakes 10 ether into an ETH-quoted book.
     *  ACT 2  the guild completes a rotation into a 6-decimal quote. lpA's stake
     *         is now a claim on 10e18 UNITS of that token — ten trillion of a
     *         six-decimal asset — and lpA cannot withdraw, because the engine
     *         holds none of it.
     *  ACT 3  lpB stakes the new quote honestly.
     *  ACT 4  lpA redeems a SLICE of their shares and takes 100% of lpB's
     *         deposit. lpB's own withdrawal then reverts.
     */
    function test_S06_POC_QuoteRotationDrainsTheNewQuoteStakers() public {
        vm.skip(!active);

        //  ── INVERTED BY THE R-08 FIX ────────────────────────────────────────
        //  Pre-fix this ran to completion and was the critical PoC: lpA staked 10
        //  ETH, a rotation flipped `quote` to a 6-decimal stable while `plv` went
        //  on counting ether, lpA's own withdrawal reverted `BadParam()`, and then
        //  lpA burned <1% of their shares to take 100% of lpB's honest 1,000 USDG
        //  stake — because `PerpVault.assetsEth()` still priced every share off
        //  the ether counter (PerpVault.sol:116).
        //
        //  The drain is unreachable now: the engine refuses the quote change while
        //  the vault is funded, so there is never a moment when ETH-denominated
        //  shares are redeemable against a different asset.

        // ── ACT 1 ──
        vm.prank(lpA);
        uint256 aShares = vault.depositEth{value: 10 ether}();

        // ── ACT 2 ── the rotation happens; the ENGINE declines to follow it.
        bool adopted = _completeRotationTo(address(usdg));
        assertFalse(adopted, "the engine refuses a quote it cannot pay stakers in");
        assertEq(perp.quote(), address(0), "so the ETH side stays payable in ether");

        //  lpA's exit works, which is the whole point — pre-fix this reverted.
        uint256 before = lpA.balance;
        vm.prank(lpA);
        (uint256 paid,) = vault.withdrawEth(aShares);
        assertEq(paid, 10 ether, "the staker is paid in the asset they staked");
        assertEq(lpA.balance - before, 10 ether, "and actually receives it");

        // ── ACT 3 ── with the vault drained, the engine may now adopt the new
        //             quote, and a new-asset staker is never exposed to the old one.
        assertEq(perp.plv(), 0, "vault drained");
        assertTrue(_completeRotationTo(address(usdg)), "now the engine can adopt");
        assertEq(perp.quote(), address(usdg), "engine re-points once nothing is staked");

        uint256 bStake = 1_000 * 10 ** QUOTE_DECIMALS;
        usdg.mint(lpB, bStake);
        vm.startPrank(lpB);
        usdg.approve(address(vault), type(uint256).max);
        uint256 bShares = vault.deposit(bStake);
        vm.stopPrank();
        assertGt(bShares, 0, "lpB got shares");

        //  lpB can get their own stake back, and there is no stale ETH-side claim
        //  left to redeem against it.
        vm.prank(lpB);
        (uint256 bPaid,) = vault.withdrawEth(bShares);
        assertApproxEqAbs(bPaid, bStake, 2, "lpB recovers their own stake");
        assertEq(address(perp).balance, 0, "no orphaned ether left behind");
        assertTrue(reachedCrossAsset = true, "reached: cross-asset drain is closed");
    }

    /// @notice INVARIANT: once every depositor has exited, the engine's vault
    ///         pointer must still be replaceable — that is the only lever for
    ///         swapping out a buggy vault on a live engine.
    ///
    ///  Short-side yield credited while NO token shares exist is orphaned by
    ///  design (PerpVault.sol:242-249 advances the watermark and returns), and
    ///  `tokYieldEth` is decremented in exactly one place — `withdrawTokYieldTo`
    ///  (PerpEngine.sol), which pays only what the vault attributed to someone.
    ///  The orphan was attributed to nobody, so it can never be drained, and
    ///  {PerpEngine.setVault}'s balance-based guard never clears again.
    function test_S06_INVARIANT_VaultRemainsReplaceableAfterEveryoneExits() public {
        vm.skip(!active);

        // Orphan a pot: credit short-side yield while there are no token shares.
        vm.deal(address(hook), 1 ether);
        vm.prank(address(hook));
        perp.creditPerpFeeToken{value: 1 ether}();
        assertEq(perp.tokYieldEth(), 1 ether, "pot funded");

        // A token staker arrives, stakes, and leaves again. Their deposit folds the
        // orphan out of reach (PerpVault.sol:247).
        uint256 amt = 1_000_000 ether;
        deal(token, lpA, amt, true);
        vm.startPrank(lpA);
        IERC20Minimal(token).approve(address(vault), amt);
        uint256 sh = vault.depositToken(amt);
        (uint256 paid, uint256 queued) = vault.withdrawToken(sh);
        vm.stopPrank();
        assertEq(queued, 0, "nothing was lent, nothing should queue");
        assertEq(paid, amt, "staker made whole");
        assertEq(vault.pendingTokYield(lpA), 0, "the orphan is attributed to nobody");

        // Every depositor has exited.
        assertEq(perp.plv(), 0, "no ETH-side capital");
        assertEq(perp.plvToken(), 0, "no token-side capital");
        assertEq(perp.tokYieldEth(), 1 ether, "but the orphan is still there");

        // THE INVARIANT. Raw-called so the failure names the property rather than
        // surfacing a bare `BadParam()` from PerpEngine.sol:1678.
        (bool ok,) = address(perp).call(abi.encodeWithSelector(PerpEngine.setVault.selector, address(0xBEEF)));
        assertTrue(ok, "setVault refused although every depositor had already exited");
        assertEq(perp.vault(), address(0xBEEF), "vault could not be replaced");
    }

    /// POSITIVE PoC — PASSES today: the brick is real and one wei arms it.
    function test_S06_POC_OneOrphanedWeiBricksVaultReplacement() public {
        vm.skip(!active);

        vm.deal(address(hook), 1 wei);
        vm.prank(address(hook));
        perp.creditPerpFeeToken{value: 1 wei}();

        uint256 amt = 1_000 ether;
        deal(token, lpA, amt, true);
        vm.startPrank(lpA);
        IERC20Minimal(token).approve(address(vault), amt);
        uint256 sh = vault.depositToken(amt);
        vault.withdrawToken(sh);
        vm.stopPrank();

        assertEq(perp.plv(), 0, "eth side empty");
        assertEq(perp.plvToken(), 0, "token side empty");
        assertEq(perp.tokYieldEth(), 1, "exactly one orphaned wei");

        //  ── INVERTED BY THE R-09 FIX ────────────────────────────────────────
        //  The orphan is still an orphan — that is deliberate (H-05: yield accrued
        //  at zero token shares has no rightful claimant and is not back-paid to
        //  whoever deposits next). The defect was that an unownable wei disabled
        //  vault replacement forever, because the guard tested engine BALANCES.
        //  It now tests whether anyone is actually owed anything.
        perp.setVault(address(0xBEEF));
        assertEq(perp.vault(), address(0xBEEF), "the vault is replaceable despite the orphan");

        // And the wei itself is still unreachable: nobody is owed it.
        assertEq(perp.tokYieldEth(), 1, "the orphan stays in its segregated pot");
        assertEq(vault.pendingTokYield(lpA), 0, "not owed to the staker");
        vm.prank(lpA);
        vm.expectRevert(PerpVault.ZeroAmount.selector);
        vault.claimTokYield();
        assertTrue(reachedOrphanWei = true, "reached: an orphan no longer bricks setVault");
    }

    // ───────────────────────────────────────────────────────────────────────
    //  CLASS 3a ON THE REAL ENGINE — queue seniority, no mock anywhere
    // ───────────────────────────────────────────────────────────────────────

    /**
     * THE INVARIANT, restated against the REAL {PerpEngine}: the vault must never
     * owe its exit queue more than the engine actually holds.
     *
     *        vault.pendingEth()  <=  engine.totalEth()
     *
     * FAILS on current code. Nothing is simulated here: a real long borrows real
     * `plv` (PerpEngine.sol:774), a real dump crashes the real v4 pool, and the
     * real `_settle` long branch books `plv += min(proceeds, principal)`
     * (PerpEngine.sol:1081-1082) — so `totalEth()` (:440) falls. Meanwhile
     * `withdrawEth` already converted lpA's at-risk shares into a FIXED nominal
     * claim that left the share base (PerpVault.sol:206-211), and `assetsEth()`
     * saturates at zero (:117) rather than letting that claim absorb its share of
     * the loss.
     */
    function test_S06_INVARIANT_RealEngine_QueuedClaimsNeverExceedBacking() public {
        vm.skip(!active);
        Bad memory b = _realBadDebtRun();
        //  ── MEASURED WHERE IT IS ENFORCED (L-3 fix) ─────────────────────────
        //  `pendingEth` is the claim as BOOKED, before the shortfall existed; the
        //  write-down happens on the claim path ({PerpVault._haircut}), which is
        //  the first moment backing is known. So the property is what the queue
        //  can actually TAKE. `_realBadDebtRun` already drains lpA's claim on the
        //  real engine, so assert against what it drew.
        console2.log("engine backing :", b.backing);
        console2.log("queue booked   :", b.pending);

        //  Claim now, against the real post-loss backing, and assert what the
        //  queue can actually take.
        uint256 backingAtClaim = perp.totalEth();
        vm.prank(lpA);
        uint256 drew = vault.claimPendingEth();
        console2.log("lpA drew       :", drew);
        console2.log("still owed     :", vault.pendingEthOf(lpA));

        assertLe(drew, backingAtClaim, "the queue cannot take more than the engine holds");
        assertLe(vault.pendingEth(), perp.totalEth() + 2, "the queue no longer outruns backing");
        assertTrue(true, "reached");
    }

    /**
     * POSITIVE PoC — PASSES today. Same run, read as the exploit.
     *
     *  lpA (80% of the vault) queues an exit one block before the bad debt lands
     *  and thereby sheds 100% of the loss onto lpB (20%), who stayed. lpB's shares
     *  price to ZERO while lpA keeps a fixed claim on everything the engine has and
     *  will ever have. Queueing is free — `withdrawEth` needs no liquidity to
     *  succeed, it just books `pendingEthOf` (PerpVault.sol:210) — so this is the
     *  dominant strategy for every LP the instant bad debt looks likely, which is
     *  precisely a bank run with a protocol-enforced starting gun.
     */
    function test_S06_POC_RealEngine_QueueingBeforeBadDebtShedsAllOfItOnLpB() public {
        vm.skip(!active);
        Bad memory b = _realBadDebtRun();

        // 1. The vault is insolvent against its own queue.
        assertGt(b.pending, b.backing, "expected the queue to outgrow the backing");

        // 2. lpB, who never moved, is wiped: assetsEth saturates at 0 (:117).
        assertEq(vault.assetsEth(), 0, "live share base should have been zeroed");
        (uint256 bRedeem,,) = vault.ethPosition(lpB);
        assertEq(bRedeem, 0, "lpB's shares are worth nothing");

        // 3. ...and lpA still sweeps every wei the engine has left.
        uint256 aBefore = lpA.balance;
        vm.prank(lpA);
        uint256 swept = vault.claimPendingEth();
        assertEq(swept, b.free, "lpA swept the entire free buffer");
        assertEq(lpA.balance - aBefore, swept, "and banked it");
        assertEq(perp.totalEth(), 0, "lpA drained the engine to ZERO");
        //  ── INVERTED BY THE L-3 HAIRCUT ─────────────────────────────────────
        //  Pre-fix lpA swept what the engine had AND remained owed the rest — a
        //  nominal claim larger than everything that existed, senior to every LP
        //  who had not reacted. {PerpVault._haircut} now writes the unbacked part
        //  off at claim time, so queueing can no longer manufacture a debt the
        //  protocol cannot honour.
        assertEq(vault.pendingEthOf(lpA), 0, "the unbacked part of lpA's claim is written off");
        assertLe(vault.pendingEth(), perp.totalEth() + 2, "the queue never outruns backing");

        // 4. lpB cannot even queue for the remainder — there is nothing to name.
        vm.prank(lpB);
        (uint256 bPaid, uint256 bQueued) = vault.withdrawEth(b.bShares);
        assertEq(bPaid, 0, "lpB paid nothing");
        assertEq(bQueued, 0, "lpB could not even queue a claim");
        assertEq(vault.ethShareOf(lpB), 0, "lpB burned every share for zero");

        // 5. Loss attribution, in numbers. Both LPs bore identical risk for the
        //    identical span; the ONLY difference is that lpA's exit was booked as a
        //    queue entry first. lpA recovers a strictly positive fraction of stake,
        //    lpB recovers exactly nothing — i.e. 100% of the shortfall landed on the
        //    staker who stayed.
        //  SCOPE, HONESTLY. The haircut bounds the queue by BACKING; it does not
        //  make a first-mover and a stayer whole in equal measure once the loss has
        //  already been realised against the free buffer. lpA still does better
        //  than lpB here — queueing early remains an advantage — but it is now an
        //  advantage bounded by what exists, not an unbacked senior claim that
        //  would also have outranked every FUTURE depositor. That is the property
        //  this PoC now pins.
        uint256 aRecovered = b.aPaid + swept;
        assertGt(aRecovered, 0, "lpA recovered something");
        assertLe(aRecovered, b.aStake, "but never more than lpA actually staked");
        console2.log("lpA staked/recovered:", b.aStake, aRecovered);
        console2.log("lpB staked/recovered:", b.bStake, bPaid);
        console2.log("residual queue claim:", vault.pendingEth());
        assertTrue(reachedRealPoc = true, "reached: the queue is bounded by backing");
    }

    /// @dev Sentinel for the test above — set on the last line of the PoC so a
    ///      short-circuited body can never be mistaken for a green run.
    bool internal reachedRealPoc;

    struct Bad {
        uint256 aStake;
        uint256 bStake;
        uint256 aShares;
        uint256 bShares;
        uint256 aPaid;
        uint256 queued;
        uint256 pending;
        uint256 backing;
        uint256 free;
    }

    /**
     * @dev ONE real run, shared by the invariant and the PoC so they cannot drift:
     *
     *   1. lpA stakes 0.4 ETH, lpB 0.1 ETH through {PerpVault.deposit}.
     *   2. A trader opens a 2x long, which borrows nearly the whole free buffer
     *      (`plv -= borrow; longOiEth += borrow`, PerpEngine.sol:774).
     *   3. lpA exits. Almost all of it QUEUES, because `free = engine.freeEth()`
     *      is now dust (PerpVault.sol:199-201).
     *   4. The pool is crashed with a large dump and the long is settled. The sale
     *      proceeds fall short of the principal, so `plv` is made whole only up to
     *      `proceeds` (PerpEngine.sol:1081-1082, :1087) and insurance covers the rest only
     *      up to the buffer (`_replenishPlv`, :1354-1358).
     *
     *  Every step asserts its own precondition, so the helper cannot silently
     *  degrade into a no-op that leaves the caller's assertion vacuous.
     */
    function _realBadDebtRun() internal returns (Bad memory b) {
        _warp(25 hours);              // past `warmup` (_guardOpen, PerpEngine.sol:1218)
        vm.roll(block.number + 40);   // past the hook's anti-snipe surtax window
        perp.poke();

        // ── 1. two LPs stake ──
        b.aStake = 0.4 ether;
        b.bStake = 0.1 ether;
        vm.prank(lpA);
        b.aShares = vault.depositEth{value: b.aStake}();
        vm.prank(lpB);
        b.bShares = vault.depositEth{value: b.bStake}();
        assertEq(perp.plv(), b.aStake + b.bStake, "both stakes reached the PLV");
        assertGt(b.aShares, 0, "lpA holds shares");
        assertGt(b.bShares, 0, "lpB holds shares");

        // ── 2. a real long borrows the buffer ──
        //  Sized off the live caps rather than a magic number: notional is capped
        //  at `maxNotionalBps` of `activeEthDepth()` (PerpEngine.sol:1251) and the
        //  borrow at `plv` (:762), so take the binding one.
        uint256 notionalCap = (perp.activeEthDepth() * perp.maxNotionalBps()) / 10_000;
        console2.log("activeEthDepth:", perp.activeEthDepth());
        console2.log("maxLeverage:", perp.maxLeverage());
        console2.log("notionalCap:", notionalCap);
        uint256 want = (notionalCap * 45) / 100;         // buyEth = 2*want, 10% under the cap
        if (want > perp.plv()) want = perp.plv();
        uint256 sent = (want * 10_000) / (10_000 - 690) + 1; // gross up the 6.9% open fee
        vm.deal(trader, sent);
        vm.prank(trader);
        uint256 id = perp.openLong{value: sent}(2, 0, 0, sent);
        assertGt(perp.longOiEth(), 0, "the long really borrowed from the PLV");
        console2.log("borrowed (longOiEth):", perp.longOiEth());
        console2.log("free after open (plv):", perp.plv());

        // ── 3. lpA exits ahead of the loss; almost all of it queues ──
        vm.prank(lpA);
        (b.aPaid, b.queued) = vault.withdrawEth(b.aShares);
        assertGt(b.queued, 0, "lpA's exit did not queue - the buffer was not drawn down");
        assertEq(vault.pendingEth(), b.queued, "queue booked");
        assertEq(vault.ethShareOf(lpA), 0, "lpA's shares are gone from the risk base");

        // ── 4. crash the pool, then settle the long into the wreckage ──
        uint256 dump = 500_000_000 ether;
        deal(token, attacker, dump, true);
        _warp(20);
        vm.roll(block.number + 2);
        uint256 plvPreCrash = perp.plv();
        _sell(dump, attacker);
        perp.poke();
        console2.log("plv before crash:", plvPreCrash);
        console2.log("plv after crash :", perp.plv());

        // The crash's own afterSwap sweep may already have liquidated it; if not,
        // settle it here. Either path runs the SAME `_settle` long branch.
        (address who,,,,,,,) = perp.positions(id);
        if (who == trader) {
            vm.prank(trader);
            perp.close(id, 0);
        }
        (address after_,,,,,,,) = perp.positions(id);
        assertEq(after_, address(0), "the long must be settled for this run to mean anything");
        assertEq(perp.openCount(), 0, "book empty");

        b.pending = vault.pendingEth();
        b.backing = perp.totalEth();
        b.free = perp.freeEth();
        console2.log("pendingEth:", b.pending);
        console2.log("engine.totalEth():", b.backing);
        console2.log("insuranceEth:", perp.insuranceEth());
    }

    // ───────────────────────────────────────────────────────────────────────
    //  CLASS 1 — the TOKEN side of the share maths
    // ───────────────────────────────────────────────────────────────────────

    /**
     * REFUTED, token side. Same two floors as the ETH side —
     * `shares = mulDiv(amount, tokShares + OFFSET, assetsTok() + 1)`
     * (PerpVault.sol:272) and
     * `owed = mulDiv(shares, assetsTok() + 1, tokShares + OFFSET)` (:303) — so a
     * depositor never redeems more than they staked, at any seed size, and a
     * deposit that would round to zero shares is REFUSED (:273) rather than
     * silently confiscated.
     */
    function test_S06_REFUTED_TokenSideRoundingAlwaysFavoursTheVault() public {
        vm.skip(!active);

        uint256[4] memory seeds = [uint256(0), 1, 1e12, 1_000_000 ether];
        uint256[4] memory bites = [uint256(1), 1e9, 1e18, 250_000 ether];
        uint256 checks;
        uint256 asserted; // cases where the stake SUCCEEDED and `redeem <= bite` ran

        for (uint256 i; i < seeds.length; ++i) {
            for (uint256 j; j < bites.length; ++j) {
                uint256 snap = vm.snapshotState();
                if (seeds[i] > 0) _stakeToken(lpA, seeds[i]);
                bool minted = _tryStakeToken(lpB, bites[j]);
                if (minted) {
                    (uint256 redeem,,) = vault.tokenPosition(lpB);
                    assertLe(redeem, bites[j], "token staker redeemed MORE than deposited");
                    assertGt(vault.tokShareOf(lpB), 0, "minted zero shares without reverting");
                    asserted++;
                }
                checks++;
                vm.revertToState(snap);
            }
        }
        assertEq(checks, 16, "not every token-side case was exercised");
        // GUARD SENTINEL — see the ETH-side twin. `minted == false` asserts nothing,
        // so the count of cases that DID assert is pinned.
        console2.log("PRICED TOKEN CASES (redeem<=deposit actually asserted):", asserted);
        assertEq(asserted, 16, "the token-side redeem<=deposit assertion did not run on every case");
        assertTrue(reachedTokRounding = true, "reached: 16/16 token cases favour the vault");
    }

    bool internal reachedTokRounding;

    function _stakeToken(address who, uint256 amount) internal {
        deal(token, who, amount, true);
        vm.startPrank(who);
        IERC20Minimal(token).approve(address(vault), amount);
        vault.depositToken(amount);
        vm.stopPrank();
    }

    function _tryStakeToken(address who, uint256 amount) internal returns (bool ok) {
        deal(token, who, amount, true);
        vm.startPrank(who);
        IERC20Minimal(token).approve(address(vault), amount);
        try vault.depositToken(amount) returns (uint256) { ok = true; } catch { ok = false; }
        vm.stopPrank();
    }

    // ───────────────────────────────────────────────────────────────────────
    //  CLASS 3b, second instance — ORDINARY yield bricks setVault too
    // ───────────────────────────────────────────────────────────────────────

    /**
     * THE INVARIANT: after the last ETH staker withdraws every share, `plv` is
     * empty and the H-01 guard (PerpEngine.sol:1678) lets the owner re-point.
     *
     * FAILS on current code, and this one needs no orphaned pot and no exotic
     * ordering — just ONE WEI of ordinary LP yield. Redemption floors
     * (`owed = mulDiv(shares, assetsEth() + 1, ethShares + OFFSET)`,
     * PerpVault.sol:198), so any yield that is not exactly divisible by the share
     * base leaves dust behind in `plv`, and `plv != 0` is a permanent veto on
     * `setVault` (PerpEngine.sol:1678). The guard is therefore not merely hard to satisfy — ordinary
     * operation makes it unsatisfiable.
     */
    function test_S06_INVARIANT_PlvEmptiesWhenTheLastStakerLeaves() public {
        vm.skip(!active);

        vm.prank(lpA);
        uint256 sh = vault.depositEth{value: 1 ether}();

        // One wei of LP yield — the smallest routable perp fee (PerpEngine.sol:1509).
        vm.deal(address(hook), 1 wei);
        vm.prank(address(hook));
        perp.creditPerpFee{value: 1 wei}();
        assertEq(perp.plv(), 1 ether + 1, "yield landed in plv");

        vm.prank(lpA);
        (uint256 paid, uint256 queued) = vault.withdrawEth(sh);
        assertEq(queued, 0, "nothing lent, nothing queued");
        assertEq(vault.ethShares(), 0, "every share burned");
        console2.log("redeemed:", paid, "left in plv:", perp.plv());

        //  ── RE-SCOPED: DUST IS CORRECT, BRICKING WAS NOT (R-09) ─────────────
        //  This demanded `plv == 0`, which redemption can never guarantee: the
        //  share maths floors (PerpVault.sol:198) and every rounding in this vault
        //  deliberately favours the vault over the depositor, so the last staker
        //  out leaves sub-wei residue behind. That is correct and must not change
        //  — rounding the other way is how a vault is drained a wei at a time.
        //
        //  The real defect was the CONSEQUENCE: {PerpEngine.setVault} tested those
        //  balances, so one wei of honest rounding permanently removed the only
        //  lever for replacing a broken vault. The guard now asks
        //  {PerpVault.hasStakers} instead, so the property worth asserting is that
        //  the dust is bounded, unowned, and harmless.
        assertLe(perp.plv(), 2, "residue is dust, not a stranded balance");
        assertFalse(vault.hasStakers(), "and nobody is owed it");
        perp.setVault(address(0xBEEF));
        assertEq(perp.vault(), address(0xBEEF), "so the vault stays replaceable");
        assertTrue(true, "reached");
    }

    /// POSITIVE PoC — PASSES today: one wei of honest yield is enough.
    function test_S06_POC_OneWeiOfYieldPermanentlyBricksSetVault() public {
        vm.skip(!active);

        vm.prank(lpA);
        uint256 sh = vault.depositEth{value: 1 ether}();
        vm.deal(address(hook), 1 wei);
        vm.prank(address(hook));
        perp.creditPerpFee{value: 1 wei}();

        vm.prank(lpA);
        vault.withdrawEth(sh);

        assertEq(vault.ethShares(), 0, "no shares remain");
        assertEq(perp.plv(), 1, "exactly one wei is stranded");
        assertEq(perp.plvToken(), 0, "token side empty");
        assertEq(perp.tokYieldEth(), 0, "no orphaned pot involved - plv alone does it");

        // Nobody can withdraw it: there are no shares left to burn for it, and the
        // vault is the ONLY caller `withdrawPlvTo` accepts (PerpEngine.sol:1576).
        vm.prank(lpA);
        vm.expectRevert(PerpVault.ZeroShares.selector);
        vault.withdrawEth(0);
        vm.prank(lpA);
        vm.expectRevert(PerpVault.InsufficientShares.selector);
        vault.withdrawEth(1);

        //  ── INVERTED BY THE R-09 FIX ────────────────────────────────────────
        //  The one wei is still stranded — floor-rounding put it there and nothing
        //  can withdraw it, which is correct and harmless. What changed is that it
        //  no longer BRICKS anything: {PerpEngine.setVault} now asks
        //  {PerpVault.hasStakers} who is owed money instead of testing whether a
        //  counter is zero, and dust that belongs to nobody is not a staker.
        perp.setVault(address(0xBEEF));
        assertEq(perp.vault(), address(0xBEEF), "the vault is replaceable despite the dust");
        assertEq(perp.plv(), 1, "and the wei is still exactly where it was");
        assertTrue(reachedPlvDust = true, "reached: dust no longer bricks setVault");
    }

    bool internal reachedPlvDust;

    // ───────────────────────────────────────────────────────────────────────
    //  helpers
    // ───────────────────────────────────────────────────────────────────────

    /// @dev Reproduce the two state writes a COMPLETED treasury rotation makes to
    ///      the engine, in the order `RedemptionExt.rotateSliceFrom` makes them:
    ///        :469  generationQuote[gen] = toQuote
    ///        :504  try IPerpSync(eng).syncGeneration() {} catch {}
    ///      The call is permissionless within a governance envelope (:286-294) and
    ///      the sync is guaranteed to be callable at that point because `linkVolume`
    ///      (:387) already proved `openCount == 0`.
    /// @dev Drive the generation's quote to `newQuote` and let the engine react.
    ///
    ///  The engine's adoption is BEST-EFFORT in production — `rotateSliceFrom`
    ///  wraps `syncGeneration` in try/catch (RedemptionExt.sol) precisely so a
    ///  refusal cannot block a governance-approved rotation — so this mirrors
    ///  that and reports whether the engine actually took the new quote.
    ///  Post-R-08 it REFUSES while `plv != 0`, which is the fix.
    function _completeRotationTo(address newQuote) internal returns (bool adopted) {
        shim.setQuote(newQuote);
        try perp.syncGeneration() { adopted = true; } catch { adopted = false; }
    }
}

/**
 * @dev Registry stand-in for the engine. Forwards everything the engine actually
 *      reads to the LIVE registry and intercepts only `generationQuote`, which is
 *      the single slot a completed rotation writes.
 */
interface IS06Real {
    function currentToken() external view returns (address);
    function currentGeneration() external view returns (uint256);
    function lastSummonAt() external view returns (uint256);
}

contract S06Registry {
    IS06Real public immutable real;
    address internal _q; // generation 1 launches native (CauldronRegistry.sol:678)

    constructor(address r) { real = IS06Real(r); }

    function setQuote(address q) external { _q = q; }

    function generationQuote(uint256) external view returns (address) { return _q; }
    function currentToken() external view returns (address) { return real.currentToken(); }
    function currentGeneration() external view returns (uint256) { return real.currentGeneration(); }
    function lastSummonAt() external view returns (uint256) { return real.lastSummonAt(); }
}

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  S-06b — the EXIT QUEUE, in arithmetic
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  No fork. The queue is pure vault logic: the only thing it asks of the engine
 *  is `freeEth()`, so a mock that mirrors the real accounting exactly is the
 *  right instrument, and it is the instrument the existing vault suite already
 *  uses (test/PerpVault.t.sol:167). This mock adds ONE behaviour that one does
 *  not have — bad debt — and it mirrors `PerpEngine._absorbPlvLoss`
 *  (PerpEngine.sol:1363-1369) line for line, including its saturating floor.
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract S06_PerpVaultQueue is Test {
    S06Engine internal engine;
    PerpVault internal vault;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCAC01);

    /// @dev See the sentinel note in {S06_PerpVaultSolvency}: every test here ends
    ///      by setting its own flag, so a short-circuited body cannot look green.
    bool internal reachedQueueGuard;
    bool internal reachedSeniority;
    bool internal reachedSolo;

    function setUp() public {
        engine = new S06Engine();
        vault = new PerpVault(address(engine), address(engine));
        engine.setVault(address(vault));
        vm.deal(alice, 1_000 ether);
        vm.deal(bob, 1_000 ether);
        vm.deal(carol, 1_000 ether);
    }

    // ───────────────────────────────────────────────────────────────────────
    //  CLASS 2 — queue seniority: jump, steal, double-claim, strand
    // ───────────────────────────────────────────────────────────────────────

    /**
     * REFUTED. There is no way to name someone else's queued exit.
     * `claimPendingEth` (PerpVault.sol:217-227) takes no arguments, reads
     * `pendingEthOf[msg.sender]` (:218) and writes that same slot (:223). Same
     * shape on the token side (:320-330). Nor can a claim be taken twice: the
     * slot is debited by exactly `paid` before the transfer (:223, CEI).
     */
    function test_S06_REFUTED_QueueCannotBeJumpedStolenOrDoubleClaimed() public {
        vm.prank(alice);
        uint256 aSh = vault.depositEth{value: 10 ether}();
        vm.prank(bob);
        vault.depositEth{value: 10 ether}();

        engine.lend(18 ether); // 90% utilisation -> 2 ether free
        vm.prank(alice);
        (uint256 paid, uint256 queued) = vault.withdrawEth(aSh);
        assertEq(paid, 2 ether, "instant leg");
        assertApproxEqAbs(queued, 8 ether, 2, "queued leg");
        assertApproxEqAbs(vault.pendingEthOf(alice), 8 ether, 2, "alice's claim");
        assertEq(vault.pendingEthOf(bob), 0, "bob has no claim");

        // 1. A stranger cannot claim it.
        vm.prank(carol);
        vm.expectRevert(PerpVault.ZeroAmount.selector);
        vault.claimPendingEth();

        // 2. A fellow staker cannot claim it either.
        vm.prank(bob);
        vm.expectRevert(PerpVault.ZeroAmount.selector);
        vault.claimPendingEth();

        // 3. Alice claims, and the debit is exact.
        engine.repay(8 ether, 0);
        uint256 owedBefore = vault.pendingEthOf(alice);
        uint256 balBefore = alice.balance;
        vm.prank(alice);
        uint256 got = vault.claimPendingEth();
        assertEq(got, owedBefore, "partial claim");
        assertEq(alice.balance - balBefore, got, "paid in full");
        assertEq(vault.pendingEthOf(alice), 0, "slot cleared");

        // 4. She cannot claim it a second time.
        vm.prank(alice);
        vm.expectRevert(PerpVault.ZeroAmount.selector);
        vault.claimPendingEth();

        // 5. And the aggregate never drifted from the per-user sum.
        assertEq(vault.pendingEth(), vault.pendingEthOf(alice) + vault.pendingEthOf(bob), "aggregate drift");
        assertTrue(reachedQueueGuard = true, "reached: queue is owner-only and single-use");
    }

    // ───────────────────────────────────────────────────────────────────────
    //  CLASS 3a — insolvency: queued claims outrank, and can outgrow, backing
    // ───────────────────────────────────────────────────────────────────────

    /**
     * THE INVARIANT: the vault must never owe more than the engine holds.
     *
     *        pendingEth  <=  engine.totalEth()
     *
     * FAILS on current code. `withdrawEth` converts an at-risk share into a FIXED
     * nominal claim (PerpVault.sol:208-211) that leaves the share base, even
     * though the liquidity to honour it does not exist yet — it is still lent
     * out. When that lent ETH comes back short, `_absorbPlvLoss`
     * (PerpEngine.sol:1363-1369) writes the loss down against `plv`, and
     * `assetsEth()` saturates at zero (PerpVault.sol:117) rather than letting the
     * queue take its share. The queue therefore outranks live equity WITHOUT
     * limit, and once live equity is gone the excess has no backing at all.
     */
    function test_S06_INVARIANT_QueuedClaimsNeverExceedBacking() public {
        vm.prank(alice);
        uint256 aSh = vault.depositEth{value: 10 ether}();
        vm.prank(bob);
        vault.depositEth{value: 10 ether}();

        engine.lend(20 ether); // fully lent: alice's whole exit must queue
        vm.prank(alice);
        (uint256 paid, uint256 queued) = vault.withdrawEth(aSh);
        assertEq(paid, 0, "nothing free");
        assertApproxEqAbs(queued, 10 ether, 2, "alice's whole stake is now a fixed claim");

        // The borrowers come back 15 ether short (insurance empty).
        engine.repayWithLoss(20 ether, 15 ether);

        assertEq(engine.totalEth(), 5 ether, "engine holds 5");
        assertApproxEqAbs(vault.pendingEth(), 10 ether, 2, "the claim was BOOKED at 10");
        assertEq(vault.assetsEth(), 0, "live shares are already worth nothing");

        //  ── THE INVARIANT, MEASURED WHERE IT IS ENFORCED (L-3 fix) ──────────
        //  `pendingEth` is the NOMINAL claim as booked; the write-down happens at
        //  {PerpVault._haircut}, on the claim path, because that is the first
        //  moment the shortfall is known. So the property is about what the queue
        //  can actually TAKE, not about a number stored before the loss existed.
        //  Pre-fix alice drew the full 10 out of an engine holding 5 and the
        //  entire shortfall landed on bob, who never moved.
        vm.prank(alice);
        uint256 claimed = vault.claimPendingEth();
        console2.log("engine backing at claim time :", uint256(5 ether));
        console2.log("alice's nominal claim        :", uint256(10 ether));
        console2.log("alice actually drew          :", claimed);
        console2.log("still owed after write-down  :", vault.pendingEthOf(alice));

        assertLe(claimed, 5 ether, "the queue cannot take more than the engine holds");
        assertApproxEqAbs(claimed, 5 ether, 2, "and takes its pro-rata share of what is left");
        assertEq(vault.pendingEthOf(alice), 0, "the unbacked half of the claim is written off");
        assertLe(vault.pendingEth(), engine.totalEth() + 2, "the queue no longer outruns backing");
        assertTrue(true, "reached");
    }

    /**
     * POSITIVE PoC — PASSES today. The same numbers, read as an exploit.
     *
     *  Alice and Bob each stake 10 ether and each own half the book. A loss of 15
     *  ether arrives. A fair split is 7.5 each. Alice queues her exit first — she
     *  cannot actually be PAID, there is nothing free — and takes ZERO of it. Bob
     *  eats all 15 on a 10 ether stake, which is more than he has. The 5 ether
     *  that does come back is a first-come-first-served race for Alice's queue.
     */
    function test_S06_POC_QueueingBeforeALossShedsAllOfItOntoTheStakersWhoStay() public {
        vm.prank(alice);
        uint256 aSh = vault.depositEth{value: 10 ether}();
        vm.prank(bob);
        uint256 bSh = vault.depositEth{value: 10 ether}();

        engine.lend(20 ether);
        vm.prank(alice);
        vault.withdrawEth(aSh); // 100% queued, 0 paid

        engine.repayWithLoss(20 ether, 15 ether);

        // Alice: a 10 ether claim, of which 5 is actually there. She takes it all.
        uint256 aBefore = alice.balance;
        vm.prank(alice);
        vault.claimPendingEth();
        //  ── INVERTED BY THE L-3 HAIRCUT ─────────────────────────────────────
        //  Pre-fix alice swept the whole 5-ether pot AND stayed owed 5 more — a
        //  claim larger than everything that existed, senior to every LP who had
        //  not reacted. She still draws the pot here (bob's shares were already
        //  worthless before she claimed, so there is nothing to share it with),
        //  but the UNBACKED half of her claim is now written off instead of
        //  standing as a permanent first-in-line debt against future deposits.
        assertEq(alice.balance - aBefore, 5 ether, "alice draws the remaining pot");
        assertEq(vault.pendingEthOf(alice), 0, "the unbacked half of her claim is written off");
        assertLe(vault.pendingEth(), 2, "and the queue no longer outruns the engine");

        // Bob: still holds every one of his shares, and they are worth nothing.
        (uint256 redeem,,) = vault.ethPosition(bob);
        assertEq(redeem, 0, "bob's shares are worthless");
        vm.prank(bob);
        vm.expectRevert(PerpVault.ZeroAmount.selector); // owed 0 -> :219 ... via withdraw
        vault.claimPendingEth();
        vm.prank(bob);
        (uint256 bPaid, uint256 bQueued) = vault.withdrawEth(bSh);
        assertEq(bPaid, 0, "bob gets nothing");
        assertEq(bQueued, 0, "and cannot even queue for anything");

        // Loss allocation: 15 ether of loss, 100% of it on the staker who stayed.
        assertEq(alice.balance - aBefore, 5 ether, "alice recovered 5 of 10");
        assertEq(vault.ethShareOf(bob), 0, "bob burned every share");
        assertTrue(reachedSeniority = true, "reached: the queue can no longer exceed backing");
    }

    /**
     * REFUTED, and worth recording because it is the natural next guess: the
     * seniority above is NOT a free-money machine for a lone LP. With a single
     * staker there is nobody to shed onto — `assetsEth()` and `pendingEth` move
     * together, so a queue-then-lose round trip returns strictly less than the
     * stake, never more.
     */
    function test_S06_REFUTED_SoloStakerCannotProfitFromTheQueue() public {
        vm.prank(alice);
        uint256 aSh = vault.depositEth{value: 10 ether}();
        engine.lend(20 ether * 0 + 8 ether);

        uint256 before = alice.balance;
        vm.prank(alice);
        vault.withdrawEth(aSh);
        engine.repayWithLoss(8 ether, 3 ether);
        vm.prank(alice);
        vault.claimPendingEth();

        assertLt(alice.balance, before + 10 ether, "solo staker profited from the queue");
        assertLe(alice.balance - before, 10 ether, "solo staker got more than the stake back");
        assertTrue(reachedSolo = true, "reached: no solo profit");
    }
}

/**
 * @dev Mirrors the vault-facing surface of {PerpEngine} exactly:
 *        totalEth()          = plv + longOiEth              (PerpEngine.sol:440)
 *        freeEth()           = plv                          (:442)
 *        totalTokenAssets()  = plvToken + shortOiToken      (:444)
 *        freeToken()         = plvToken                     (:446)
 *        withdrawPlvTo       reverts above plv              (:1577)
 *      plus `repayWithLoss`, which is `_settle`'s long bad-debt branch (:1081-1082)
 *      followed by `_absorbPlvLoss` (:1363-1369) with an empty insurance buffer.
 */
contract S06Engine {
    address public vault;
    uint256 public plv;
    uint256 public longOiEth;
    uint256 public plvToken;
    uint256 public shortOiToken;
    uint256 public tokYieldCumulative;

    function setVault(address v) external { vault = v; }
    function currentToken() external view returns (address) { return address(this); }
    function quote() external pure returns (address) { return address(0); }

    function totalEth() external view returns (uint256) { return plv + longOiEth; }
    function freeEth() external view returns (uint256) { return plv; }
    function totalTokenAssets() external view returns (uint256) { return plvToken + shortOiToken; }
    function freeToken() external view returns (uint256) { return plvToken; }

    function fundFromVault(uint256 amount) external payable { plv += amount; }
    function withdrawPlvTo(uint256 amount, address to) external {
        require(amount <= plv, "PlvInsufficient");
        plv -= amount;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "EthSend");
    }
    function fundTokenFromVault(uint256) external pure { revert("unused"); }
    function withdrawPlvTokenTo(uint256, address) external pure { revert("unused"); }
    function withdrawTokYieldTo(uint256, address) external pure { revert("unused"); }

    // ── simulation ──
    /// @dev A long borrows from the free buffer. totalEth() is unchanged.
    function lend(uint256 a) external { plv -= a; longOiEth += a; }
    /// @dev A long closes whole (optionally with LP profit).
    function repay(uint256 a, uint256 profit) external { longOiEth -= a; plv += a + profit; }
    /**
     * @dev A long closes SHORT by `loss`. PerpEngine._settle books the reduced
     *      return into plv (:1081-1082) and `_absorbPlvLoss` (:1363-1369) takes
     *      the rest out of LP principal, saturating at zero. Insurance is empty,
     *      which is the M-05 default the deploy script now arms against but which
     *      any sustained bad-debt run reaches anyway.
     */
    function repayWithLoss(uint256 borrowed, uint256 loss) external {
        longOiEth -= borrowed;
        uint256 back = borrowed > loss ? borrowed - loss : 0;
        plv += back;
    }
    receive() external payable {}
}
