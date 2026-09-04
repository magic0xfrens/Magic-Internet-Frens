// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FullMath} from "v4-core/src/libraries/FullMath.sol";

interface IPerpEngineVault {
    function fundFromVault() external payable;
    function withdrawPlvTo(uint256 amount, address to) external;
    function fundTokenFromVault(uint256 amount) external;
    function withdrawPlvTokenTo(uint256 amount, address to) external;
    function totalEth() external view returns (uint256);
    function freeEth() external view returns (uint256);
    function totalTokenAssets() external view returns (uint256);
    function freeToken() external view returns (uint256);
    // side-attributed token-side ETH reward pot
    function tokYieldCumulative() external view returns (uint256);
    function withdrawTokYieldTo(uint256 amount, address to) external;
}

interface IVaultRegistry {
    function currentToken() external view returns (address);
}

/**
 * @title PerpVault — Community PLV (LP-for-perps)
 * @notice Anyone can supply the liquidity that backs the perp engine's leverage
 *         and earn REAL yield from it — no team ETH required. Two independent
 *         sides:
 *
 *    • ETH side  — stakers deposit ETH that backs LONGS. Yield = a redirected
 *      slice of the perp OPEN FEE + FUNDING + LIQUIDATION PENALTIES, which the
 *      engine leaves in the PLV so the pot (and thus each share) grows over time.
 *      ETH stakers bear the (insurance-buffered) bad-debt tail risk.
 *
 *    • TOKEN side — stakers deposit the current iteration token that backs
 *      SHORTS (the inventory shorts borrow and must return). Because a short's
 *      buy-back always returns the inventory IN FULL, token principal is
 *      STRUCTURALLY PROTECTED — the ETH shortfall of a bad short is borne by the
 *      ETH side + insurance, never the token side.
 *
 *  ── HOW YIELD SHOWS UP ──────────────────────────────────────────────────────
 *  There is no separate "harvest": fees accrue INSIDE the engine's PLV, so
 *  `engine.totalEth()` / `engine.totalTokenAssets()` grow and the share price
 *  (assets-per-share) rises. Withdrawing later returns more than you put in.
 *
 *  ── WITHDRAWALS UNDER UTILIZATION ───────────────────────────────────────────
 *  Only the UN-LENT portion is instantly withdrawable (the engine caps lending
 *  at `maxUtilBps`, so a buffer is always free). If your withdrawal exceeds the
 *  free buffer, the remainder is QUEUED as a fixed claim and becomes claimable
 *  (`claimPending`) as open positions close and liquidity returns. Queued claims
 *  stop earning yield and stop bearing bad-debt risk the moment they're queued.
 *
 *  Share math uses a virtual offset (à la ERC-4626) so the first deposit and
 *  donation/inflation attacks are handled safely.
 */
contract PerpVault is ReentrancyGuard {
    /// @dev Virtual-shares offset (à la ERC-4626 decimals offset). Shares are
    ///      minted at 1e6× assets, so a first-depositor / donation-inflation
    ///      attack would have to donate ~1e6× a victim's deposit to round their
    ///      shares down — economically infeasible. (Audit V-02)
    uint256 private constant OFFSET = 1e6;

    IPerpEngineVault public immutable engine;
    IVaultRegistry public immutable registry;

    // ── ETH side ──
    uint256 public ethShares;                       // total ETH-side shares
    mapping(address => uint256) public ethShareOf;
    uint256 public pendingEth;                      // ETH owed to queued exits
    mapping(address => uint256) public pendingEthOf;

    // ── TOKEN side ──
    uint256 public tokShares;                       // total token-side shares
    mapping(address => uint256) public tokShareOf;
    uint256 public pendingTok;                      // token owed to queued exits
    mapping(address => uint256) public pendingTokOf;

    // ── TOKEN-side ETH reward accrual (short-attributed fees, paid in ETH) ──
    /// @dev MasterChef-style accumulator: token stakers earn ETH — the engine's
    ///      short-side LP yield — pro-rata to their token shares, WITHOUT their
    ///      token principal ever converting. Claimed as ETH via {claimTokYield}.
    uint256 private constant ACC = 1e18;
    uint256 public accEthPerTokShare;                 // 1e18-scaled ETH per token-share
    uint256 public lastTokYieldCum;                   // last engine.tokYieldCumulative() folded in
    mapping(address => uint256) public tokRewardDebt; // 1e18-scaled baseline per user
    mapping(address => uint256) public tokRewardOwed; // settled, claimable ETH per user

    event DepositEth(address indexed user, uint256 assets, uint256 shares);
    event WithdrawEth(address indexed user, uint256 shares, uint256 paid, uint256 queued);
    event ClaimEth(address indexed user, uint256 paid);
    event DepositTok(address indexed user, uint256 assets, uint256 shares);
    event WithdrawTok(address indexed user, uint256 shares, uint256 paid, uint256 queued);
    event ClaimTok(address indexed user, uint256 paid);
    event ClaimTokYield(address indexed user, uint256 paid);
    /// @notice Short-side yield that accrued while NO token shares existed. It has no
    ///         rightful claimant and is deliberately NOT back-paid to the next
    ///         depositor; it stays in the engine's segregated pot. (Audit H-05.)
    event UnattributedYield(uint256 amount);

    error ZeroAmount();
    error ZeroShares();
    error InsufficientShares();
    error TransferFailed();

    constructor(address _engine, address _registry) {
        engine = IPerpEngineVault(_engine);
        registry = IVaultRegistry(_registry);
    }

    // ── asset bases (what backs LIVE shares, net of queued exits) ────────────
    /// @notice ETH backing live shares = engine's ETH PLV minus queued exits.
    function assetsEth() public view returns (uint256) {
        uint256 t = engine.totalEth();
        return t > pendingEth ? t - pendingEth : 0;
    }
    /// @notice Token backing live shares = engine's token inventory minus queued.
    function assetsTok() public view returns (uint256) {
        uint256 t = engine.totalTokenAssets();
        return t > pendingTok ? t - pendingTok : 0;
    }

    // ── ETH side: deposit / withdraw / claim ─────────────────────────────────

    /// @notice Stake ETH to back longs and earn perp fees. Mints shares at the
    ///         live assets-per-share (with a virtual offset for safety).
    function depositEth() external payable nonReentrant returns (uint256 shares) {
        if (msg.value == 0) revert ZeroAmount();
        // Price BEFORE the engine receives the funds (assetsEth is pre-deposit).
        shares = FullMath.mulDiv(msg.value, ethShares + OFFSET, assetsEth() + 1);
        if (shares == 0) revert ZeroShares();
        ethShares += shares;
        ethShareOf[msg.sender] += shares;
        engine.fundFromVault{value: msg.value}();
        emit DepositEth(msg.sender, msg.value, shares);
    }

    /// @notice Redeem ETH shares. Pays instantly up to the engine's FREE ETH; any
    ///         remainder is queued (claim later via {claimPendingEth}).
    function withdrawEth(uint256 shares) external nonReentrant returns (uint256 paid, uint256 queued) {
        uint256 bal = ethShareOf[msg.sender];
        if (shares == 0) revert ZeroShares();
        if (shares > bal) revert InsufficientShares();

        uint256 owed = FullMath.mulDiv(shares, assetsEth() + 1, ethShares + OFFSET);
        uint256 free = engine.freeEth();
        paid = owed <= free ? owed : free;
        queued = owed - paid;
        // EFFECTS first (CEI): burn shares + earmark any queued claim, THEN the
        // single external ETH send. Queued ETH leaves the share base — it stops
        // earning yield AND stops bearing bad-debt risk — and waits for liquidity
        // to free up as positions close.
        ethShareOf[msg.sender] = bal - shares;
        ethShares -= shares;
        if (queued > 0) {
            pendingEth += queued;
            pendingEthOf[msg.sender] += queued;
        }
        if (paid > 0) engine.withdrawPlvTo(paid, msg.sender); // INTERACTION last
        emit WithdrawEth(msg.sender, shares, paid, queued);
    }

    /// @notice Claim a previously-queued ETH exit as liquidity frees up.
    function claimPendingEth() external nonReentrant returns (uint256 paid) {
        uint256 owed = pendingEthOf[msg.sender];
        if (owed == 0) revert ZeroAmount();
        uint256 free = engine.freeEth();
        paid = owed <= free ? owed : free;
        if (paid == 0) revert ZeroAmount();
        pendingEthOf[msg.sender] = owed - paid;
        pendingEth -= paid;
        engine.withdrawPlvTo(paid, msg.sender);
        emit ClaimEth(msg.sender, paid);
    }

    // ── TOKEN side: deposit / withdraw / claim ───────────────────────────────

    // ── token-side ETH reward accumulator (short-attributed yield) ──
    /// @dev Fold newly-accrued engine token-side yield into the per-share index.
    ///
    ///      ZERO-SHARE HANDLING (audit H-05). Yield that accrued while NOBODY was
    ///      staked has no rightful claimant. The watermark is therefore advanced
    ///      even at zero shares, so it can never be back-paid to whoever happens to
    ///      deposit first. Previously the watermark was left behind, which let a
    ///      watcher deposit one share after a zero-stake window and claim the ENTIRE
    ///      accrued pot regardless of size — ordering, not capital, decided the
    ///      payout. The orphaned ETH stays in the engine's segregated
    ///      `tokYieldEth` pot; governance can redirect it (treasury or insurance).
    function _syncTokYield() internal {
        uint256 cum = engine.tokYieldCumulative();
        if (cum == lastTokYieldCum) return;
        uint256 delta = cum - lastTokYieldCum;
        lastTokYieldCum = cum;                     // ALWAYS advance
        if (tokShares == 0) { emit UnattributedYield(delta); return; }
        accEthPerTokShare += FullMath.mulDiv(delta, ACC, tokShares);
    }
    /// @dev Bank a user's earned-so-far ETH into their owed balance (call before
    ///      any change to their token-share count).
    function _settleTok(address user) internal {
        uint256 sh = tokShareOf[user];
        if (sh > 0) {
            uint256 acc = FullMath.mulDiv(sh, accEthPerTokShare, ACC);
            if (acc > tokRewardDebt[user]) tokRewardOwed[user] += acc - tokRewardDebt[user];
        }
    }
    /// @dev Reset a user's reward baseline to their current share count.
    function _resetTokDebt(address user) internal {
        tokRewardDebt[user] = FullMath.mulDiv(tokShareOf[user], accEthPerTokShare, ACC);
    }

    /// @notice Stake the current iteration token to back shorts. Requires an
    ///         approval to this vault. Token principal is structurally protected
    ///         (short buy-backs always return the inventory in full); on top of
    ///         that, you earn ETH from short-side fees (claim via {claimTokYield}).
    function depositToken(uint256 amount) external nonReentrant returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();
        address tok = registry.currentToken();
        _syncTokYield(); _settleTok(msg.sender);      // bank rewards at old share count
        shares = FullMath.mulDiv(amount, tokShares + OFFSET, assetsTok() + 1);
        if (shares == 0) revert ZeroShares();
        tokShares += shares;
        tokShareOf[msg.sender] += shares;
        _resetTokDebt(msg.sender);                    // rebase baseline to new count
        // Pull from the user, then let the engine pull from us.
        _pull(tok, msg.sender, amount);
        _approve(tok, address(engine), amount);
        engine.fundTokenFromVault(amount);
        emit DepositTok(msg.sender, amount, shares);
    }

    /// @notice Claim your accrued short-side ETH reward (paid in ETH; your token
    ///         principal stays staked and protected).
    function claimTokYield() external nonReentrant returns (uint256 paid) {
        _syncTokYield(); _settleTok(msg.sender); _resetTokDebt(msg.sender);
        paid = tokRewardOwed[msg.sender];
        if (paid == 0) revert ZeroAmount();
        tokRewardOwed[msg.sender] = 0;
        engine.withdrawTokYieldTo(paid, msg.sender);  // from the segregated pot
        emit ClaimTokYield(msg.sender, paid);
    }

    /// @notice Redeem token shares. Pays instantly up to the engine's FREE token
    ///         inventory; any remainder is queued ({claimPendingToken}).
    function withdrawToken(uint256 shares) external nonReentrant returns (uint256 paid, uint256 queued) {
        uint256 bal = tokShareOf[msg.sender];
        if (shares == 0) revert ZeroShares();
        if (shares > bal) revert InsufficientShares();

        _syncTokYield(); _settleTok(msg.sender);      // bank ETH rewards at old count
        uint256 owed = FullMath.mulDiv(shares, assetsTok() + 1, tokShares + OFFSET);
        uint256 free = engine.freeToken();
        paid = owed <= free ? owed : free;
        queued = owed - paid;
        // EFFECTS before the external transfer (CEI).
        tokShareOf[msg.sender] = bal - shares;
        tokShares -= shares;
        _resetTokDebt(msg.sender);                    // rebase baseline to new count
        if (queued > 0) {
            pendingTok += queued;
            pendingTokOf[msg.sender] += queued;
        }
        if (paid > 0) engine.withdrawPlvTokenTo(paid, msg.sender);
        emit WithdrawTok(msg.sender, shares, paid, queued);
    }

    /// @notice Claim a previously-queued token exit as inventory frees up.
    function claimPendingToken() external nonReentrant returns (uint256 paid) {
        uint256 owed = pendingTokOf[msg.sender];
        if (owed == 0) revert ZeroAmount();
        uint256 free = engine.freeToken();
        paid = owed <= free ? owed : free;
        if (paid == 0) revert ZeroAmount();
        pendingTokOf[msg.sender] = owed - paid;
        pendingTok -= paid;
        engine.withdrawPlvTokenTo(paid, msg.sender);
        emit ClaimTok(msg.sender, paid);
    }

    // ── frontend views ───────────────────────────────────────────────────────

    /// @notice ETH currently redeemable for `user`'s shares (at the live price),
    ///         and how much of it is instantly withdrawable right now.
    function ethPosition(address user) external view returns (uint256 redeemable, uint256 instant, uint256 pending) {
        uint256 s = ethShareOf[user];
        redeemable = FullMath.mulDiv(s, assetsEth() + 1, ethShares + OFFSET);
        uint256 free = engine.freeEth();
        instant = redeemable <= free ? redeemable : free;
        pending = pendingEthOf[user];
    }
    /// @notice Token currently redeemable for `user`'s shares + instant portion.
    function tokenPosition(address user) external view returns (uint256 redeemable, uint256 instant, uint256 pending) {
        uint256 s = tokShareOf[user];
        redeemable = FullMath.mulDiv(s, assetsTok() + 1, tokShares + OFFSET);
        uint256 free = engine.freeToken();
        instant = redeemable <= free ? redeemable : free;
        pending = pendingTokOf[user];
    }
    /// @notice A token staker's accrued short-side ETH reward, claimable now
    ///         (includes yield not yet folded into the accumulator).
    function pendingTokYield(address user) external view returns (uint256) {
        uint256 acc = accEthPerTokShare;
        uint256 cum = engine.tokYieldCumulative();
        // Mirrors _syncTokYield exactly: at zero shares the delta is unattributed and
        // is NOT credited to anyone, so the view must not promise it either (H-05).
        if (cum > lastTokYieldCum && tokShares > 0) acc += FullMath.mulDiv(cum - lastTokYieldCum, ACC, tokShares);
        uint256 sh = tokShareOf[user];
        uint256 earned;
        if (sh > 0) { uint256 a = FullMath.mulDiv(sh, acc, ACC); if (a > tokRewardDebt[user]) earned = a - tokRewardDebt[user]; }
        return tokRewardOwed[user] + earned;
    }

    // ── internal ERC20 helpers ────────────────────────────────────────────────
    function _pull(address token, address from, uint256 amount) private {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, address(this), amount)
        );
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }
    function _approve(address token, address spender, uint256 amount) private {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, amount)
        );
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }
}
