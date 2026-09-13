// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title LegacyBuyLib
 * @notice The legacy-buyback swap, lifted out of {CauldronHook}.
 *
 *  This is a LINKED library — `external` functions, so Solidity deploys it
 *  separately and reaches it by `delegatecall`. It therefore runs in the hook's
 *  context: `address(this)` is the hook, the ETH paid to `settle` comes from the
 *  hook's balance, and the tokens `take` credits land on the hook. Identical
 *  behaviour to the inlined version, ~700 bytes lighter in the hook's own code.
 *
 *  Why it had to move: the hook was over the EIP-170 24,576-byte limit and could
 *  not be deployed. `forge script` does not catch that — simulation does not
 *  enforce the code-size limit — so it only surfaces against a real chain. This
 *  is the same pattern {PoolOps} already uses for the registry.
 *
 *  It deliberately holds NO state. Every storage read and write stays in the
 *  hook, which keeps the public getters the indexer and frontend read exactly
 *  where they were, and keeps this library's contract free of any layout
 *  coupling.
 */
library LegacyBuyLib {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    /// @dev The swap bought nothing — a "buyback" that acquires zero token is not
    ///      a buyback, it is a donation to the book. Reverting rolls the caller's
    ///      whole `legacyBuyStep` frame back, so the buffer is preserved.
    error NoOutput();
    /// @dev The quote token reported a failed (or false-returning) transfer.
    error QuoteTransferFailed();
    /// @dev The fill came in under the worst price the band allows — the backstop
    ///      for value skimmed off the nested swap itself rather than off the tick.
    error Slipped();

    /// @dev Widest price move this buy may itself cause, as a fraction of the
    ///      LIVE sqrt price, in bps. 9486/10000 of sqrtP is ~0.8998 of the price:
    ///      the buy may push the pool at most ~10% before it stops early.
    uint256 internal constant SLIP_SQRT_BPS = 9486;
    /// @dev Mirrors CauldronHook.MIN_SQRT_LIMIT — the widest allowable downward
    ///      bound for an exact-input buy, i.e. "no price limit".
    uint160 internal constant MIN_SQRT_LIMIT = 4295128740;

    /// @dev How far the price reference may travel per BLOCK, in ticks. Same value
    ///      the progressive seeder uses (CauldronSeeder.MAX_TICK_DEV). ~1050 ticks
    ///      is a 10% price move, so the reference tracks an honest market inside
    ///      one or two blocks while an attacker who wants it D ticks away must hold
    ///      a manipulated price for D/1000 whole blocks against every arbitrageur.
    int24 internal constant MAX_TICK_DEV = 1000;

    /// @dev Storage slot, in the DELEGATING contract, holding the price reference:
    ///      `refTick` (int24, low 24 bits) packed with `refBlock` (uint64, next 64).
    ///
    ///      It lives in a keccak-namespaced slot rather than a state variable
    ///      because {CauldronHook} — the sole caller — is 25 bytes under the
    ///      EIP-170 limit and cannot afford a slot declaration, its getter, or the
    ///      wider `buyStep` signature that passing the reference in and out would
    ///      need. A library cannot declare state, so the namespaced slot is what
    ///      keeps the hook's bytecode BYTE-IDENTICAL while still giving this buy a
    ///      price the triggering swap did not choose. The hook's own layout is
    ///      sequential from slot 0 (plus keccak(key, slot) mapping buckets), so
    ///      this cannot collide with it.
    ///
    ///      The reference is kept PER POOL (`keccak256(poolId, REF_SLOT)`): a
    ///      relaunch hands this hook an entirely new token at an unrelated tick, and
    ///      a reference carried over from the dead generation would refuse the new
    ///      one's buybacks for as many blocks as it takes to drag the difference at
    ///      1000 ticks apiece.
    bytes32 internal constant REF_SLOT = keccak256("cauldron.legacybuy.priceref.v1");

    /**
     * @dev Marks a reference that was BORN in the block currently being recorded,
     *      i.e. taken raw from whatever tick the triggering swap had just set.
     *
     *  ── WHY A BIT AND NOT JUST `seeded` (red-team S0xA, High) ────────────────
     *  The bootstrap defer used to be "the CALL that writes the sentinel returns
     *  `seeded` and refuses". That is one call, not one block, and the buyback is
     *  invoked TWICE inside a single `afterSwap` — `CauldronHook.sol:799` and
     *  `:1002`. So one transaction could: push the tick, let :799 seed the
     *  reference at that manufactured tick, and have :1002 take the
     *  `refBlock == block.number` branch, report `seeded == false`, and spend the
     *  whole buffer against a price the same transaction had just invented.
     *  Measured on the pre-fix code: an honest fill of 5,139,999 tokens for 0.547
     *  ETH became 612,853 tokens for 1.000 ETH — -88.1%, attacker +0.552 ETH,
     *  which is byte-identical to the sandwich this guard was written to stop.
     *  It recurs on every pool, so every relaunch re-armed it.
     *
     *  The sample must therefore be untradeable for the WHOLE block it was born
     *  in, not merely for the call that took it. One bit above the packed
     *  (tick | block) pair records that, and the first sync in any LATER block
     *  clears it — at which point the value has survived a block boundary and the
     *  MAX_TICK_DEV clamp governs it like any other.
     *
     *  Bit 88: ticks occupy 0-23, the block number 24-87.
     */
    uint256 internal constant VIRGIN_BIT = 1 << 88;

    /**
     * @notice Spend up to `amt` of the quote to market-buy the iteration token.
     * @dev Caller MUST have set its self-buy re-entry flag first: this swap
     *      re-enters the hook's own before/afterSwap, and without that flag the
     *      nested swap would be charged a fee and accrue volume as though a user
     *      had made it.
     *
     *      QUOTE-AT-CURRENCY0 ONLY. `zeroForOne: true` assumes the quote sits
     *      at currency0; the settle path below handles native OR ERC20. The
     *      caller gates on `quoteIsCurrency0` AND on the buffer's denomination
     *      matching `key.currency0` — see CauldronHook._maybeLegacyBuyback.
     *
     * @param encumbered How much of this contract's `currency0` balance is spoken
     *      for by OTHER counters (the relaunch reserve). `amt` is clamped to the
     *      free remainder so a buyback can never move balance the reserve's own
     *      counter still claims — which used to leave `releaseRelaunchAsset`
     *      unable to send what it believed it held.
     *
     * @return spent The quote actually consumed — settle THIS, not `amt`.
     * @return got   The token bought, owed to the caller.
     */
    function buyStep(IPoolManager poolManager, PoolKey calldata key, uint256 amt, uint256 encumbered)
        external
        returns (uint256 spent, uint256 got)
    {
        address q = Currency.unwrap(key.currency0);

        //  SPEND ONLY WHAT IS FREE. The hook's currency0 balance is shared: part
        //  of it is the buyback buffer, part is `relaunchETH`/`relaunchAsset[q]`,
        //  a holder-facing reserve. Nothing here debits those counters, so a buy
        //  larger than the free remainder would move reserve balance while the
        //  reserve still believed it held it — `releaseRelaunchAsset`'s send then
        //  fails and the remainder locks. Clamp instead: the unspent part is
        //  returned to the buffer by the caller and retried next time.
        uint256 bal = q == address(0) ? address(this).balance : IERC20(q).balanceOf(address(this));
        uint256 free = bal > encumbered ? bal - encumbered : 0;
        if (amt > free) amt = free;
        if (amt == 0) return (0, 0);

        //  A REAL PRICE BOUND, NOT `MIN_SQRT_LIMIT`. The limit used to be the
        //  absolute minimum tick price, i.e. "fill at any price at all": a book
        //  drained or skewed inside the same transaction could take the whole
        //  buffer for dust. Bound the move to a fixed fraction of the live sqrt
        //  price — if it binds, the pool consumes less than `amt` and the
        //  remainder rolls back into the buffer (already handled by the caller).
        PoolId pid = key.toId();
        (uint160 sp, int24 tick,,) = poolManager.getSlot0(pid);

        //  ...AND THE FRACTION MUST BE OF A PRICE THE CALLER DID NOT CHOOSE
        //  (red-team T-1, the twin of the seeder's Z-17). The bound above was
        //  measured from `getSlot0` — the tick the TRIGGERING swap had just
        //  produced, because `_maybeLegacyBuyback` runs in `afterSwap` inside a
        //  stranger's transaction. A bound taken off a manipulated price is a
        //  manipulated bound: push the token dear, let the protocol spend its
        //  whole buffer at your tick, then sell your inventory back through the
        //  hole the protocol's own buy just dug. Measured on a real v4
        //  PoolManager with a 10 ETH / 100M-token book and a 1 ETH buffer: the
        //  collection's floor received 612,853.96 tokens instead of
        //  5,139,999.99 (-88.1%) while the attacker netted +0.552 ETH on one
        //  block of flash-loanable capital, repeatable every time the buffer
        //  refills past `legacyThreshold`.
        //
        //  So the limit is now the TIGHTER of the self-impact bound and the same
        //  fraction of the REFERENCE price, which moves at most MAX_TICK_DEV
        //  ticks per block: `max(sp, refSqrt) * SLIP_SQRT_BPS`. When spot sits at
        //  or above the reference (including the honest case ref == spot, and the
        //  case where somebody pushed the token CHEAP, which only buys us more)
        //  the geometry is unchanged. When spot has been pushed far enough below
        //  the reference that the bound is no longer reachable, the buy is
        //  SKIPPED — the buffer keeps its value for a swap at an honest price,
        //  which is strictly better than converting it at a manufactured one.
        //
        //  REFUSING IS `return (0, 0)`, NOT A REVERT, AND THAT IS LOAD-BEARING.
        //  A revert here would roll `_syncRef`'s own write back with it, so the
        //  reference could never advance on a block where the buy was refused —
        //  a reference left stale while the buffer sat under `legacyThreshold`
        //  would then refuse FOREVER instead of catching up. (Found by execution:
        //  the first cut of this fix reverted, and every later buyback in the
        //  regression suite refused with it.) The caller already handles a short
        //  fill — `legacyBuffer += amt - spent` at CauldronHook.sol:1129 restores
        //  the whole buffer when `spent == 0` — and `legacyOwedToReserve += 0` is
        //  a no-op, so a skip is observable as `LegacyBuyback(amt, 0)` and costs
        //  the protocol nothing. No delta is opened before this point, so there
        //  is nothing to settle.
        //
        //  THE FIRST BUYBACK ON A POOL ONLY SEEDS THE REFERENCE — it does not
        //  spend. Otherwise the bootstrap sample IS the attack: whoever fires the
        //  very first buyback on a generation picks the tick the reference is born
        //  at, and gets exactly the sandwich this bound exists to stop. Measured:
        //  with a bootstrap-and-buy the sandwich still filled at -88.1% and still
        //  paid the attacker +0.552 ETH. Deferring costs one buffered buyback by
        //  one block on a brand-new pool and nothing else.
        (int24 ref, bool seeded) = _syncRef(pid, tick);
        if (seeded) return (0, 0);

        uint160 refSqrt = TickMath.getSqrtPriceAtTick(ref);
        uint256 lim = ((sp > refSqrt ? uint256(sp) : uint256(refSqrt)) * SLIP_SQRT_BPS) / 10_000;
        if (lim >= uint256(sp)) return (0, 0);
        if (lim < MIN_SQRT_LIMIT) lim = MIN_SQRT_LIMIT;

        // Exact-INPUT quote→token: spend up to `amt` for whatever token it buys.
        BalanceDelta d = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(amt),
                sqrtPriceLimitX96: uint160(lim)
            }),
            ""
        );

        // SETTLE THE REALISED DEBIT, not the intended `amt` (audit Z-17). If the
        // price limit ever binds, the pool consumes LESS than `amt`; settling the
        // constant would over-settle, leaving a positive delta that is never
        // taken — and since deltas must net to zero at unlock close, that would
        // revert the USER's parent swap.
        spent = uint256(uint128(-d.amount0()));

        //  SETTLE IN WHATEVER THE QUOTE IS, not always ether.
        //
        //  This was `settle{value: spent}()` unconditionally, which is why the
        //  hook refused to buffer a non-native fee at all: paying ether into an
        //  ERC20-quoted pool settles nothing the pool asked for, currency0's
        //  delta stays open, and the unlock closes with `CurrencyNotSettled()` —
        //  reverting the USER'S parent swap, since this runs nested inside it.
        //  Skipping the buyback was the safe workaround; generalising the
        //  settlement removes the reason for it, so the collection floor keeps
        //  accruing on a rotated generation instead of silently stopping.
        //
        //  ERC20 settlement in v4 is sync -> transfer -> settle: `sync` snapshots
        //  the manager's balance, the transfer moves the tokens in, and `settle`
        //  credits the difference. This library is delegatecalled by the hook, so
        //  `address(this)` is the hook and the tokens paid are its own.
        got = uint256(uint128(d.amount1()));
        //  A BUY THAT BOUGHT NOTHING IS NOT A BUYBACK. Reverting here rolls back
        //  the caller's `legacyBuffer = 0` too, so the buffer survives intact.
        if (got == 0) revert NoOutput();

        //  A MINIMUM OUTPUT, VALUED AT THE WORST PRICE THE BAND ALLOWS, LESS 10%
        //  FOR FEES. The price limit above bounds the MARGINAL price the pool
        //  quotes; it says nothing about value skimmed off the swap itself. Today
        //  the hook sets `_inSelfBuy` first so its own before/afterSwap charge
        //  this nested buy nothing, but the seeder's Z-17 measurement showed what
        //  happens when a tranche silently pays the anti-sniper surtax instead:
        //  up to 96% of the spend, with nothing reverting. This is the backstop
        //  for that class — a caller that forgets the flag, or a future hook fee
        //  that applies to the nested leg, now REFUSES (and preserves the buffer)
        //  rather than converting the floor's backing at a 96% discount.
        //
        //  `spent * (lim / 2^96)^2` is the token the worst allowed price buys,
        //  taken in two mulDivs so the squared Q96 never overflows.
        uint256 floorOut = FullMath.mulDiv(FullMath.mulDiv(spent, lim, 1 << 96), lim, 1 << 96);
        if (got < (floorOut * 9) / 10) revert Slipped();

        if (q == address(0)) {
            poolManager.settle{value: spent}();
        } else {
            poolManager.sync(key.currency0);
            //  CHECKED. A false-returning ERC20 used to leave currency0's delta
            //  open, and the unlock then closed with `CurrencyNotSettled()` —
            //  reverting the USER'S parent swap, which the caller's
            //  result-ignored self-call does NOT contain (it is the outer frame
            //  that dies, not this one).
            (bool okT, bytes memory r) =
                q.call(abi.encodeWithSelector(IERC20.transfer.selector, address(poolManager), spent));
            if (!okT || (r.length != 0 && !abi.decode(r, (bool)))) revert QuoteTransferFailed();
            poolManager.settle();
        }

        poolManager.take(key.currency1, address(this), got); // hold it on the hook
    }

    /**
     * @dev The price reference the buy is bounded against: a tick the caller of the
     *      host swap cannot choose.
     *
     *      Two rules, exactly the seeder's (CauldronSeeder._syncRef):
     *
     *        1. NEVER REWRITTEN TWICE IN ONE BLOCK. Inside a single transaction the
     *           reference therefore still holds a value committed in an EARLIER
     *           block, which is the whole point — a sandwich is atomic and cannot
     *           reach back.
     *        2. AT MOST `MAX_TICK_DEV` TICKS PER BLOCK. An honest market drags it
     *           along within a block or two; an attacker who wants it D ticks away
     *           must hold a manipulated price for D/1000 whole blocks, exposed to
     *           every arbitrageur for each of them.
     *
     *      It is synced on EVERY `buyStep` call, including the ones that go on to
     *      refuse, so a reference left stale while the buffer sat under
     *      `legacyThreshold` catches up 1000 ticks per block of trading and the
     *      buyback resumes by itself. No admin path, nothing to unbrick.
     *
     *      The first ever call for a pool SEEDS the reference and reports
     *      `seeded == true` (`refBlock == 0` is the sentinel; block 0 is
     *      unreachable on any live chain). The caller must not trade on that
     *      sample: the tick it captures is whatever the triggering swap set, so
     *      buying against it is the sandwich itself.
     */
    function _syncRef(PoolId pid, int24 tick) private returns (int24 ref, bool seeded) {
        bytes32 slot = keccak256(abi.encode(pid, REF_SLOT));
        uint256 packed;
        assembly ("memory-safe") { packed := sload(slot) }

        ref = int24(uint24(packed & 0xFFFFFF));
        uint64 refBlock = uint64(packed >> 24);
        uint256 virginBit;

        if (refBlock == 0) {
            ref = tick;
            seeded = true;
            virginBit = VIRGIN_BIT; // born THIS block, from an UNCLAMPED sample
        } else if (refBlock != uint64(block.number)) {
            int24 dev = tick - ref;
            if (dev > MAX_TICK_DEV) dev = MAX_TICK_DEV;
            else if (dev < -MAX_TICK_DEV) dev = -MAX_TICK_DEV;
            ref += dev;
            // virginBit stays 0: this sample has now survived a block boundary.
        } else {
            //  SAME BLOCK. Safe to trade on ONLY if the reference was not BORN
            //  here — see {VIRGIN_BIT}. An established reference reaching this
            //  branch was last written by the clamped path above, so it is bounded
            //  and spending against it is the intended behaviour.
            return (ref, (packed & VIRGIN_BIT) != 0);
        }

        packed = uint256(uint24(ref)) | (uint256(uint64(block.number)) << 24) | virginBit;
        assembly ("memory-safe") { sstore(slot, packed) }
    }
}
