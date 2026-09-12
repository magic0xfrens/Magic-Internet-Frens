// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MetadataMode, BrewSpec, ICauldronGovernor, LaunchLib} from "./ICauldron.sol";

/**
 * @title CauldronGovernor
 * @notice Permissionless proposal + voting registry for the eternal Cauldron.
 *
 *  Anyone can `propose()` the next brew: a name, ticker, and the NFT metadata
 *  source — either a base URI (off-chain) or an on-chain renderer contract. The
 *  MiFrens guild votes with 1 NFT = 1 vote (snapshot-free: voting weight is read
 *  live from the MiFrens ERC721 `balanceOf`, and each holder may vote once per
 *  proposal). `winner()` returns the live vote leader; the registry consumes it
 *  on relaunch and calls `markConsumed()` so it can never win twice.
 *
 *  No admin picks the winner. No pause. The only privileged call is
 *  `markConsumed`, restricted to the registry, and it only ever removes the
 *  already-summoned proposal from contention.
 */
/// @notice The registry's treasury-curated quote allowlist.
interface IRegistryQuotes {
    function allowedQuote(address quote) external view returns (bool);
}

/// @notice The three hops from this contract to the mint ladder a proposal's
///         collection will actually be priced on: registry -> hook -> curve policy.
///         Read defensively in {propose}; see {MIN_NFT_SUPPLY}.
interface IRegistryHook {
    function hook() external view returns (address);
}
interface IHookCurve {
    function curvePolicy() external view returns (address);
}
interface ICurveCalibration {
    function supply() external view returns (uint256);
}
/// @notice The live flat-ladder base a proposal's `volumePerNFT` will replace.
///         See {CURVE_BAND}.
interface IHookCurveBase {
    function volumePerNFT() external view returns (uint256);
}

contract CauldronGovernor is ICauldronGovernor, Ownable {
    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------
    /// @dev The proposed quote is not on the registry's treasury-curated
    ///      allowlist. Checked at propose AND at consumption, since the set can
    ///      change while a proposal is out for vote.
    error QuoteNotAllowed();
    error EmptyField();
    error BadRenderer();
    error UnknownProposal();
    error AlreadyVoted();
    error AlreadyConsumed();
    error NoVotingPower();
    error NotRegistry();
    error RegistryAlreadySet();
    error NoProposals();
    error SnapshotNotReady();
    error SupplyOutOfRange();
    error VotingClosed();
    error FieldTooLong();
    /// @dev A proposal's `volumePerNFT` sits outside {CURVE_BAND} of the live ladder.
    error CurveOutOfRange();

    /// @notice Hard bound on a proposal's collection size. MUST stay well below the
    ///         collections' `LIQUIDATOR_ID_BASE` (1e6), because the collection
    ///         constructor REVERTS at or above it — and a reverting constructor
    ///         inside `relaunch()` rolls back `markConsumed`, so the poisoned
    ///         proposal would win again forever and freeze the machine. (Audit C-02.)
    uint256 public constant MAX_NFT_SUPPLY = 100_000;

    /// @notice Floor on a proposal's collection size. `nftSupply == 0` still means
    ///         "leave the current size alone" (CauldronRegistry.sol:961) and is
    ///         always accepted; any non-zero value must land in
    ///         [MIN_NFT_SUPPLY, MAX_NFT_SUPPLY].
    ///
    ///  ── WHY THERE HAS TO BE A FLOOR, AND A CALIBRATION MATCH (red-team Z-09) ──
    ///  The bound above was one-sided. `nftSupply = 1` was a valid, winnable
    ///  proposal, and the mint ladder that prices the collection is NOT a function
    ///  of its size: `MintCurvePolicy` carries an IMMUTABLE `base`/`spread`/`knee`
    ///  calibrated against one `supply()`, and its `priceAt` discards the
    ///  per-generation curve `hook.setNftCurveFrom(volPerNFT)` writes at
    ///  CauldronRegistry.sol:1134. So the mint-out cost does not scale with the
    ///  collection it is pricing. Measured on the shipped 2222-fren calibration:
    ///  the first 100 rungs total $80.36 against a $20,000 target, and 10,000 rungs
    ///  total $444,083 (22x), which kills the forge for that generation outright.
    ///
    ///  Small is the dangerous direction. `CollectionLedger.floorPerNFT` is
    ///  `entitledTokens / outstanding`, so whoever holds a 100-fren collection —
    ///  minted out for ~$80 of weighted buy credit — owns 100% of the claim on a
    ///  floor funded by `floorBps` (10_000 by default) of that whole generation's
    ///  fee revenue.
    ///
    ///  Neither direction is recoverable after the fact: the policy is immutable,
    ///  so correcting it needs a timelocked `setPolicies` redeploy. Both bounds
    ///  therefore live HERE, at the proposal boundary, for the same reason the
    ///  string caps and the quote allowlist do — refusing a proposal costs one
    ///  proposal and freezes nothing, while a revert inside `relaunch()` would roll
    ///  back `markConsumed` and end the protocol.
    uint256 public constant MIN_NFT_SUPPLY = 100;

    /// @notice How far a proposal's `volumePerNFT` may sit either side of the LIVE
    ///         hook curve's base, as a divisor/multiplier. `volumePerNFT == 0` still
    ///         means "leave the current curve alone" (CauldronHook.setNftCurveFrom
    ///         returns early on 0) and is always accepted; any non-zero value must
    ///         land in [live / CURVE_BAND, live * CURVE_BAND].
    ///
    ///  ── THE TWIN OF {MIN_NFT_SUPPLY} (red-team T-2) ─────────────────────────
    ///  `nftSupply` got both bounds; `volumePerNFT` had NONE. It flows from here
    ///  straight through `CauldronRegistry.sol:1134` into
    ///  `CauldronHook.setNftCurveFrom`, which sets `volumePerNFT = _base` and
    ///  `nftPriceStep = 0` — a FLAT ladder, so the whole collection mints out for
    ///  `_base * nftSupply` of weighted buy credit. `_base = 1` is a valid,
    ///  winnable proposal: with no {MintCurvePolicy} wired, `nftPriceAt(k)` falls
    ///  through to `volumePerNFT + k * nftPriceStep` = 1 wei per fren, and the
    ///  entire collection — every dividend share and the whole claim on a floor
    ///  funded by `floorBps` of that generation's fee revenue — is minted out by
    ///  the first trader through the pool for less than the gas.
    ///
    ///  WHY A RELATIVE BAND AND NOT AN ABSOLUTE FLOOR. The credit this figure is
    ///  compared against is re-denominated: `setDeathThreshold` restates the whole
    ///  ladder into USD-at-1e18 when a `quoteOracle` is wired
    ///  (CauldronHook.sol:1796), and a generation may be quoted in a 6-decimal
    ///  asset. An absolute floor in wei would be three orders of magnitude wrong
    ///  in either of those worlds. The live curve base is by construction already
    ///  in whatever units the live `nftCredit` ledger uses, so anchoring to it is
    ///  the only denomination-safe bound available at the proposal boundary.
    ///
    ///  WHY 1000. `nftSupply` itself may legitimately move across the full
    ///  [100, 100_000] range, and a proposer holding the mint-out TARGET
    ///  (`base * supply`) constant must be able to move the base by exactly that
    ///  1000x. The band is therefore as wide as any honest proposal needs and no
    ///  wider: at the shipped 0.02 ether base it still refuses anything under
    ///  0.00002 ether per fren, and 1 wei is twelve orders of magnitude outside.
    ///
    ///  Unconstrained when the hook is not reachable or reports a zero base, for
    ///  the same reason {_calibratedSupply} degrades that way: a governor that
    ///  cannot take proposals is a dead machine, and every bound here is a
    ///  refusal of ONE proposal, never a revert inside `relaunch()`.
    uint256 public constant CURVE_BAND = 1000;

    /// @notice How long a proposal accepts votes before it may be launched. Without
    ///         a deadline, `winner()` is the live leader and a whale can flip the
    ///         result in the same block as the permissionless `relaunch()`.
    ///         (Audit M-02.)
    uint256 public constant VOTING_PERIOD = 3 days;

    /// @notice Per-field byte caps on a proposal's free-text. Enforced in
    ///         {propose}, beside the `nftSupply` and `quote` bounds and for the
    ///         same reason: these fields are UNTRUSTED input that `relaunch()`
    ///         must replay, so their size is a cost the protocol pays forever.
    ///
    ///  ── WHY A BOUND IS LOAD-BEARING, NOT COSMETIC (red-team) ────────────
    ///  These five strings were the only proposal fields left unbounded, and they
    ///  are the expensive ones. `relaunch()` reads all five back through
    ///  {winner} and RE-STORES three of them in the newborn collection
    ///  (CauldronRegistry._deployCollection -> CauldronFactory.deployBrew).
    ///
    ///  A zero-filled payload is the cheapest thing to store and the dearest to
    ///  read: writing a zero word to a fresh slot is a 100-gas no-op SSTORE,
    ///  reading it back is a full 2100-gas COLD SLOAD. Measured, the author paid
    ///  72 gas/byte ONCE and the protocol paid 83 gas/byte on EVERY rebirth —
    ///  and that asymmetry is what makes the block limit irrelevant, because one
    ///  block of authoring always buys more than one block of replay.
    ///
    ///  Measured on the Sepolia fork against a 30M block: an honest rebirth costs
    ///  5,297,638 gas; one 24,007,131-gas `propose()` carrying 320KB in `baseURI`
    ///  pushed the next rebirth to 29,288,732 and out of gas. Because the revert
    ///  rolls back the `markConsumed` inside it, {_bestUnconsumed} kept returning
    ///  the same poisoned proposal and every later rebirth died identically —
    ///  holders stranded in a dead generation with no migration path.
    ///
    ///  Bounding cannot be done at consumption instead. By the time `relaunch()`
    ///  could truncate anything the cold SLOADs are already paid, and the registry
    ///  has 62 bytes of EIP-170 margin to spend. It has to happen here, at the
    ///  boundary, where refusing costs one proposal and freezes nothing — the same
    ///  asymmetry that puts the `nftSupply` and `quote` checks here.
    ///
    ///  The caps are sized for real use: an ERC-721 name, a ticker, an IPFS or
    ///  HTTPS metadata root, and two links. Worst case all five sum to 592 bytes,
    ///  ≈49k gas to replay.
    uint256 public constant MAX_NAME_BYTES = 64;
    uint256 public constant MAX_SYMBOL_BYTES = 16;
    uint256 public constant MAX_URI_BYTES = 256;
    uint256 public constant MAX_LINK_BYTES = 128;

    // -----------------------------------------------------------------------
    // Types
    // -----------------------------------------------------------------------
    struct Proposal {
        string name;
        string symbol;
        MetadataMode mode;
        string baseURI;
        address renderer;
        string website;     // proposer's site
        string socials;     // community / X link
        /// The asset this iteration's token is PRICED IN. `address(0)` is native
        /// ETH, which is the default and every generation to date.
        ///
        /// Validated against the registry's treasury-curated allowlist at BOTH
        /// propose and consumption: the set can change between a proposal being
        /// written and it winning a vote, and the check that matters is the one
        /// at the moment liquidity actually moves.
        address quote;
        uint256 nftSupply;  // proposer-chosen NFT collection max supply
        uint256 volumePerNFT; // credit volume to forge each NFT (0 = hook default)
        address proposer;
        uint256 votes;
        uint256 snapshot;   // block at which voting power is measured
        uint256 votingEndsAt; // timestamp after which votes close and it may win
        bool consumed;
        bool exists;
    }

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    /// @notice The MiFrens checkpointed-voting NFT (electorate).
    IVotes public immutable mifrens;

    /// @notice The registry allowed to consume winners (set once).
    address public registry;

    uint256 public proposalCount;
    mapping(uint256 => Proposal) private _proposals;

    /// @notice proposalId => voter => voted.
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    // Live leader tracking (avoids O(n) scans on winner()).
    uint256 private _leaderId;
    uint256 private _leaderVotes;

    /// @dev The best mandate BEHIND the leader, maintained incrementally by
    ///      {vote} and promoted by {markConsumed}. Appended after `_leaderVotes`,
    ///      so no existing storage slot moves.
    ///
    ///  ── WHY A SECOND SLOT, AND NOT A BIGGER SCAN (red-team) ─────────────
    ///  {_recomputeLeader} is bounded to the newest {MAX_LEADER_SCAN} proposals,
    ///  which is what keeps rebirth gas O(1) in the proposal count. But the window
    ///  is POSITIONAL: it selects on proposal id, not on whether anyone voted. So
    ///  a settled mandate the guild had already voted for could be pushed out of
    ///  the window by proposals created after it, and `propose()` is permissionless
    ///  for one MiFren with no cooldown and no deposit.
    ///
    ///  Measured: with two voted mandates queued, 64 spam proposals costing
    ///  15,596,982 gas in total (one block, cents on an L2) made the second
    ///  mandate unreachable the moment a normal rebirth consumed the first —
    ///  `hasProposals()` went false, so `relaunch()` reverted `NoProposal()` and
    ///  the machine could not be reborn until the guild authored a replacement and
    ///  waited out the full {VOTING_PERIOD} again. Repeatable at every generation
    ///  boundary, indefinitely.
    ///
    ///  Enlarging the scan does not fix that — any positional window can be
    ///  flooded, and an unbounded one is the gas brick {MAX_LEADER_SCAN} exists to
    ///  prevent. The fix has to stop consumption from DEPENDING on a scan, so the
    ///  runner-up is carried forward explicitly. Spam cannot displace it: both
    ///  slots require votes, and a proposal nobody voted for can never enter
    ///  either. Displacing a mandate now costs actual voting power, which is
    ///  governance working as intended rather than a griefing vector.
    uint256 private _runnerId;
    uint256 private _runnerVotes;

    /// @notice Ownership of this governor cannot be renounced.
    ///
    ///  `Ownable` ships a live, unguarded `renounceOwnership()`, and this contract's
    ///  owner is the only party that can call {setRegistry} or {setBrewFee}. Calling
    ///  it would permanently pin both — the governor could never be re-pointed at a
    ///  new registry, and the brew fee would be frozen at whatever it happened to be
    ///  — with no recovery path and no redeploy that preserves the stockpiled
    ///  mandates. {CauldronBase} already blocks this for its inheritors; this
    ///  governor is not one of them, so it needs its own guard, the same shape fixer
    ///  D used on {MigrationVesting}. `transferOwnership` is untouched: handing the
    ///  seat to a multisig or to a burn-with-a-key address is still available, and
    ///  is the honest way to say "nobody should hold this".
    error OwnershipCannotBeRenounced();

    function renounceOwnership() public view override onlyOwner {
        revert OwnershipCannotBeRenounced();
    }

    /// @dev How many mandates the bench below can hold.
    uint256 internal constant BENCH_SLOTS = 8;

    /// @dev The mandates {_recomputeLeader} may choose from. Appended after
    ///      `_runnerVotes`, so no existing storage slot moves.
    ///
    ///  ── ONE DEEP WAS NOT DEEP ENOUGH ────────────────────────────────────
    ///  The runner-up slot above closed the easy version of this and left the
    ///  hard one open, because it is exactly ONE deep. When a third proposal
    ///  overtakes the leader, `vote` writes the DISPLACED LEADER into the runner
    ///  slot (:356-359) and the previous runner-up is forgotten — it still
    ///  exists, is still settled, is still unconsumed, and nothing remembers it.
    ///  Two consumptions drain both slots, `markConsumed` falls through to the
    ///  scan, and the scan was the positional window the runner slot was
    ///  introduced to stop depending on. Measured: A(100), B(90), C(150) filed
    ///  and voted, then 64 junk filings for 11.8M gas by one MiFren with no
    ///  cooldown — after consuming C and A, `winner()` returned 0 and
    ///  `hasProposals()` went false, so `relaunch()` reverted `NoProposal`.
    ///  B, the guild's surviving 90-vote mandate, was erased by spam.
    ///
    ///  The sibling treasury governor removed the same shape by bounding its scan
    ///  by TIME instead of position ({TreasuryGovernor.winner}), which works there
    ///  because a treasury proposal must execute inside a 3-day window. A brew
    ///  mandate has no such window on purpose — it is STOCKPILED against the next
    ///  death, which may be months away — so time is not available here and the
    ///  scan has to stop being over the proposal list at all.
    ///
    ///  Entry is by VOTES, which cost MiFrens, rather than by POSITION, which
    ///  costs gas. A proposal nobody voted for never enters; displacing an
    ///  incumbent requires out-voting the WEAKEST live mandate on the bench.
    ///  Consumed and nonexistent entries are treated as weight 0 and are reclaimed
    ///  first, so the bench self-cleans as the machine is reborn. The scan is a
    ///  fixed 8 slots whatever the proposal count, which keeps the O(1) rebirth
    ///  gas {MAX_LEADER_SCAN} was introduced for.
    uint256[BENCH_SLOTS] private _bench;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    event Proposed(uint256 indexed proposalId, address indexed proposer, string name, string symbol, MetadataMode mode);
    event Voted(uint256 indexed proposalId, address indexed voter, uint256 weight, uint256 totalVotes);
    event Consumed(uint256 indexed proposalId);
    event RegistrySet(address registry);

    constructor(address _mifrens) Ownable(msg.sender) {
        if (_mifrens == address(0)) revert EmptyField();
        mifrens = IVotes(_mifrens);
    }

    /// @notice One-time wiring of the registry that may consume winners.
    /// @dev Owner-gated: an unprotected setter would be front-runnable — an
    ///      attacker could seize `registry` and grief proposals via markConsumed.
    function setRegistry(address _registry) external onlyOwner {
        if (registry != address(0)) revert RegistryAlreadySet();
        if (_registry == address(0)) revert EmptyField();
        registry = _registry;
        emit RegistrySet(_registry);
    }

    // -----------------------------------------------------------------------
    // Propose
    // -----------------------------------------------------------------------

    /// @dev Collection size the LIVE mint-curve policy was calibrated for, or 0 if
    ///      there is no policy (or the chain to it is not wired yet). Every hop is a
    ///      raw staticcall so a registry, hook or policy that predates any of these
    ///      accessors degrades to "unconstrained" instead of making {propose}
    ///      unreachable — a governor that cannot take proposals is a dead machine.
    function _calibratedSupply() private view returns (uint256) {
        address h = _liveHook();
        if (h == address(0)) return 0;
        (bool ok, bytes memory ret) = h.staticcall(abi.encodeWithSelector(IHookCurve.curvePolicy.selector));
        if (!ok || ret.length < 32) return 0;
        address p = abi.decode(ret, (address));
        if (p == address(0)) return 0;
        (ok, ret) = p.staticcall(abi.encodeWithSelector(ICurveCalibration.supply.selector));
        if (!ok || ret.length < 32) return 0;
        return abi.decode(ret, (uint256));
    }

    /// @dev The live hook, or address(0) if the registry does not answer `hook()`.
    ///      Raw staticcall for the reason spelled out on {_calibratedSupply}.
    function _liveHook() private view returns (address) {
        address r = registry;
        if (r == address(0)) return address(0);
        (bool ok, bytes memory ret) = r.staticcall(abi.encodeWithSelector(IRegistryHook.hook.selector));
        if (!ok || ret.length < 32) return address(0);
        return abi.decode(ret, (address));
    }

    /// @dev The live flat-ladder base a proposal's `volumePerNFT` would replace, or 0
    ///      if the hook is unreachable or reports no base. See {CURVE_BAND}.
    function _liveCurveBase() private view returns (uint256) {
        address h = _liveHook();
        if (h == address(0)) return 0;
        (bool ok, bytes memory ret) = h.staticcall(abi.encodeWithSelector(IHookCurveBase.volumePerNFT.selector));
        if (!ok || ret.length < 32) return 0;
        return abi.decode(ret, (uint256));
    }

    /**
     * @notice Submit a proposal for the next brew.
     * @param name     Token + collection name.
     * @param symbol   Ticker.
     * @param mode     BaseURI or Renderer.
     * @param baseURI  Base URI (required if mode == BaseURI).
     * @param renderer On-chain renderer contract (required if mode == Renderer).
     */
    /**
     * @param name     Token + collection name (branded on-chain as
     *                 "<name> by Magic Internet Frens" — the suffix is fixed).
     * @param symbol   Ticker.
     * @param mode     BaseURI or Renderer.
     * @param baseURI  Base URI (required if mode == BaseURI).
     * @param renderer On-chain renderer (required if mode == Renderer).
     * @param website  Optional project site.
     * @param socials  Optional community / X link.
     */
    function propose(
        string calldata name,
        string calldata symbol,
        MetadataMode mode,
        string calldata baseURI,
        address renderer,
        string calldata website,
        string calldata socials,
        uint256 nftSupply,
        uint256 volumePerNFT,
        address quote
    ) external returns (uint256 id) {
        // Only the guild may propose the next brew — you must hold a MiFren
        // (auto-delegated on mint, so voting power is live without a delegate tx).
        if (mifrens.getVotes(msg.sender) == 0) revert NoVotingPower();
        if (bytes(name).length == 0 || bytes(symbol).length == 0) revert EmptyField();
        // SIZE IS A COST THE PROTOCOL REPLAYS FOREVER. Unbounded here, one
        // proposal could put `relaunch()` permanently out of gas. See the
        // {MAX_NAME_BYTES} block for the measurement and why the bound cannot live
        // at consumption instead.
        if (
            bytes(name).length > MAX_NAME_BYTES || bytes(symbol).length > MAX_SYMBOL_BYTES
                || bytes(baseURI).length > MAX_URI_BYTES
                || bytes(website).length > MAX_LINK_BYTES
                || bytes(socials).length > MAX_LINK_BYTES
        ) revert FieldTooLong();
        if (mode == MetadataMode.BaseURI) {
            if (bytes(baseURI).length == 0) revert EmptyField();
        } else {
            // Must point at a contract (code size > 0) so tokenURI can render.
            if (renderer == address(0) || renderer.code.length == 0) revert BadRenderer();
        }
        // A proposal is an UNTRUSTED input that flows straight into a constructor
        // at relaunch. Reject anything the collection could never be deployed with,
        // here at the boundary — a revert deeper in `relaunch()` would roll back
        // `markConsumed` and freeze the machine forever. (Audit C-02.)
        //  BOTH SIDES, AND BOUND TO THE LADDER THAT WILL PRICE IT (red-team Z-09).
        //  See {MIN_NFT_SUPPLY}. `0` keeps its meaning: leave the size unchanged.
        if (nftSupply != 0) {
            if (nftSupply < MIN_NFT_SUPPLY || nftSupply > MAX_NFT_SUPPLY) {
                revert SupplyOutOfRange();
            }
            //  A wired {MintCurvePolicy} is calibrated for exactly one collection
            //  size and cannot be re-calibrated, so a proposal that names a
            //  different one is asking for a collection the machine would misprice
            //  by up to 22x. Refuse it here rather than discover it from the mint
            //  ladder. Unconstrained when no policy is wired (the flat fallback
            //  `volumePerNFT + k * nftPriceStep` scales with the size by
            //  construction), which is also what keeps every existing deployment
            //  and fixture working unchanged.
            uint256 calibrated = _calibratedSupply();
            if (calibrated != 0 && nftSupply != calibrated) revert SupplyOutOfRange();
        }
        //  AND THE PRICE OF A FREN, NOT JUST HOW MANY THERE ARE (red-team T-2).
        //  `volumePerNFT` had no bound at all: 1 wei per fren minted the whole
        //  collection — its dividends and its claim on the generation's floor —
        //  out for less than the gas. See {CURVE_BAND} for why the band is
        //  relative to the live curve rather than an absolute floor in wei.
        if (volumePerNFT != 0) {
            uint256 live = _liveCurveBase();
            if (live != 0 && (volumePerNFT < live / CURVE_BAND || volumePerNFT > live * CURVE_BAND)) {
                revert CurveOutOfRange();
            }
        }
        // The quote must be one the treasury has vetted. Checked HERE so a pool
        // nobody would want can never reach a vote; re-checked at consumption
        // because the allowlist can change in between.
        //  Native ETH needs no lookup: it is allowed by construction and can
        //  never be removed, so the common case costs nothing and a registry
        //  that predates the allowlist keeps working unchanged.
        //
        //  ── WHAT THIS CHECK IS, AND IS NOT (red-team B-05) ──────────────────
        //  A vetted quote is a quote the treasury considers SAFE TO TRADE. It is
        //  NOT a promise that the next rebirth can be FUNDED in it — that depends
        //  on what the dying generation actually returns, which is unknowable when
        //  a proposal is written. `relaunch()` therefore narrows this request a
        //  second time, against real balances, in `PoolOps.seedFunding`, and
        //  degrades to a fundable quote rather than reverting.
        //
        //  Keeping the allowlist check here is still worth its bytes: it stops a
        //  proposal naming an unvetted asset from ever reaching a vote, and
        //  rejection at this boundary is free — it refuses one proposal and
        //  freezes nothing, unlike a revert inside `relaunch()`, which would roll
        //  back `markConsumed` and end the protocol. That asymmetry is the reason
        //  the `nftSupply` bound above lives here too.
        if (quote != address(0)) {
            (bool ok, bytes memory ret) = registry.staticcall(
                abi.encodeWithSelector(IRegistryQuotes.allowedQuote.selector, quote)
            );
            if (!ok || ret.length < 32 || !abi.decode(ret, (bool))) revert QuoteNotAllowed();
        }

        id = ++proposalCount;
        _proposals[id] = Proposal({
            name: name,
            symbol: symbol,
            mode: mode,
            baseURI: baseURI,
            renderer: renderer,
            website: website,
            socials: socials,
            quote: quote,
            nftSupply: nftSupply,
            volumePerNFT: volumePerNFT,
            proposer: msg.sender,
            votes: 0,
            snapshot: block.number, // voting power frozen as of this block
            votingEndsAt: block.timestamp + VOTING_PERIOD,
            consumed: false,
            exists: true
        });

        emit Proposed(id, msg.sender, name, symbol, mode);
    }

    /// @notice The public display name for a proposal: "<name> by Magic Internet Frens".
    function displayName(uint256 proposalId) external view returns (string memory) {
        Proposal storage p = _proposals[proposalId];
        if (!p.exists) revert UnknownProposal();
        return LaunchLib.displayName(p.name);
    }

    // -----------------------------------------------------------------------
    // Vote
    // -----------------------------------------------------------------------

    /**
     * @notice Vote for a proposal. Weight = caller's live MiFrens balance.
     *         One vote per address per proposal.
     */
    function vote(uint256 proposalId) external {
        Proposal storage p = _proposals[proposalId];
        if (!p.exists) revert UnknownProposal();
        if (p.consumed) revert AlreadyConsumed();
        // Votes close BEFORE a proposal becomes eligible to win, so nobody can flip
        // the outcome by front-running the permissionless relaunch. (Audit M-02.)
        // Checked ahead of `hasVoted` so a closed window always reports as such,
        // whoever asks.
        if (block.timestamp > p.votingEndsAt) revert VotingClosed();
        if (hasVoted[proposalId][msg.sender]) revert AlreadyVoted();

        // Weight is the caller's CHECKPOINTED power at the proposal's snapshot
        // block. Transferring MiFrens after the snapshot cannot mint new votes —
        // the classic "transfer to a fresh wallet and vote again" attack fails.
        if (block.number <= p.snapshot) revert SnapshotNotReady();
        uint256 weight = mifrens.getPastVotes(msg.sender, p.snapshot);
        if (weight == 0) revert NoVotingPower();

        hasVoted[proposalId][msg.sender] = true;
        p.votes += weight;

        // Update live leader (ties keep the earlier leader), carrying the
        // displaced mandate into the runner-up slot so {markConsumed} has
        // somewhere to promote from that spam cannot reach. See {_runnerId}.
        if (p.votes > _leaderVotes) {
            // Only demote a DIFFERENT proposal: the leader gaining more votes
            // must not become its own runner-up.
            if (proposalId != _leaderId) {
                _runnerId = _leaderId;
                _runnerVotes = _leaderVotes;
            }
            _leaderVotes = p.votes;
            _leaderId = proposalId;
        } else if (proposalId != _leaderId && p.votes > _runnerVotes) {
            _runnerVotes = p.votes;
            _runnerId = proposalId;
        }

        _benchRecord(proposalId, p.votes);

        emit Voted(proposalId, msg.sender, weight, p.votes);
    }

    /// @dev Keep `id` on the bench if it out-weighs the weakest thing already
    ///      there. See {_bench}. O(BENCH_SLOTS) and only on the first vote that
    ///      reaches an untracked proposal.
    function _benchRecord(uint256 id, uint256 votes) private {
        uint256 weakSlot;
        uint256 weakVotes = type(uint256).max;
        for (uint256 i; i < BENCH_SLOTS; ++i) {
            uint256 b = _bench[i];
            if (b == id) return;                       // already tracked
            uint256 v;
            if (b != 0) {
                Proposal storage q = _proposals[b];
                //  A consumed or vanished entry is dead weight, not a mandate.
                if (q.exists && !q.consumed) v = q.votes;
            }
            if (v < weakVotes) { weakVotes = v; weakSlot = i; }
        }
        if (votes > weakVotes) _bench[weakSlot] = id;
    }

    // -----------------------------------------------------------------------
    // Winner / consume
    // -----------------------------------------------------------------------

    /// @notice The current leading, unconsumed proposal.
    function winner() external view returns (uint256 proposalId, BrewSpec memory spec) {
        proposalId = _bestUnconsumed();
        if (proposalId == 0) revert NoProposals();
        Proposal storage p = _proposals[proposalId];
        spec = BrewSpec({
            name: p.name,
            symbol: p.symbol,
            mode: p.mode,
            baseURI: p.baseURI,
            renderer: p.renderer,
            website: p.website,
            socials: p.socials,
            quote: p.quote,
            nftSupply: p.nftSupply,
            volumePerNFT: p.volumePerNFT,
            proposer: p.proposer
        });
    }

    function hasProposals() external view returns (bool) {
        return _bestUnconsumed() != 0;
    }

    /// @notice Registry-only: retire a proposal once it has been summoned.
    function markConsumed(uint256 proposalId) external {
        if (msg.sender != registry) revert NotRegistry();
        Proposal storage p = _proposals[proposalId];
        if (!p.exists) revert UnknownProposal();
        if (p.consumed) revert AlreadyConsumed();
        p.consumed = true;

        // If the consumed one was the cached leader, recompute lazily.
        if (proposalId == _leaderId) {
            // PROMOTE, don't rescan. The scan is a positional window and can be
            // flooded out from under a mandate the guild already voted for; the
            // runner-up is carried explicitly and spam can never occupy it.
            // See {_runnerId} for the measurement.
            Proposal storage r = _proposals[_runnerId];
            if (_runnerId != proposalId && _runnerVotes > 0 && r.exists && !r.consumed) {
                _leaderId = _runnerId;
                _leaderVotes = _runnerVotes;
            } else {
                // Nothing queued behind it — fall back to the bounded scan, which
                // is correct whenever no runner-up was ever established.
                (_leaderId, _leaderVotes) = _recomputeLeader();
            }
            _runnerId = 0;
            _runnerVotes = 0;
        } else if (proposalId == _runnerId) {
            // The runner-up itself was consumed out of band; drop the stale slot
            // rather than leaving a consumed id promotable.
            _runnerId = 0;
            _runnerVotes = 0;
        }
        emit Consumed(proposalId);
    }

    // -----------------------------------------------------------------------
    // Views
    // -----------------------------------------------------------------------

    function getProposal(uint256 id) external view returns (Proposal memory) {
        Proposal memory p = _proposals[id];
        if (!p.exists) revert UnknownProposal();
        return p;
    }

    /// @dev Returns the cached leader if it is still valid AND its voting window has
    ///      CLOSED; otherwise recomputes over settled proposals only. A proposal
    ///      still taking votes can never be launched, which is what removes the
    ///      last-instant front-run (audit M-02).
    function _bestUnconsumed() private view returns (uint256) {
        Proposal storage cached = _proposals[_leaderId];
        if (cached.exists && !cached.consumed && _leaderVotes > 0
            && block.timestamp > cached.votingEndsAt) {
            return _leaderId;
        }
        (uint256 id, ) = _recomputeLeader();
        return id;
    }

    /// @notice Hard bound on the leader rescan (audit Z-03 — High). `relaunch()`
    ///         reaches this scan up to three times per rebirth (`hasProposals`,
    ///         `winner`, and the `markConsumed` recompute), and `propose()` is
    ///         permissionless for the holder of a SINGLE MiFren with no cooldown,
    ///         deposit or per-address cap. An unbounded scan therefore let anyone
    ///         raise the gas cost of every future rebirth without limit — measured at
    ///         ~613 gas per spam proposal per scan, i.e. ~17k proposals (a few
    ///         hundredths of an ETH on an L2) to push `relaunch()` past a 32M block
    ///         and permanently halt the eternal machine. Compounded by the fact that
    ///         `CauldronRegistry.setGovernor` is `onlyOwner` and registry ownership is
    ///         burned into the presale at deploy, so a spammed governor could never be
    ///         swapped out.
    ///
    ///         Bounding the scan makes relaunch gas O(1) in the proposal count. The
    ///         cached-leader fast path in {_bestUnconsumed} is unaffected, so an
    ///         already-established winner keeps winning however much spam follows it;
    ///         a fresh mandate simply has to be among the most recent proposals, which
    ///         it always is.
    uint256 internal constant MAX_LEADER_SCAN = 64;

    /// @dev BOUNDED scan over the most recent SETTLED (voting-closed), unconsumed
    ///      proposals. See {MAX_LEADER_SCAN}.
    function _recomputeLeader() private view returns (uint256 bestId, uint256 bestVotes) {
        //  OVER THE BENCH, NOT OVER THE PROPOSAL LIST. `uint256 first = n >
        //  MAX_LEADER_SCAN ? n - MAX_LEADER_SCAN + 1 : 1` selected on proposal id,
        //  and proposal ids are something any holder of one MiFren can mint without
        //  cooldown or deposit — so the window was floodable and a voted, settled,
        //  unconsumed mandate could be pushed out of it. See {_bench}.
        for (uint256 i; i < BENCH_SLOTS; ++i) {
            uint256 id = _bench[i];
            if (id == 0) continue;
            Proposal storage p = _proposals[id];
            if (!p.exists || p.consumed) continue;
            if (block.timestamp <= p.votingEndsAt) continue; // still open for votes
            if (p.votes > bestVotes) {
                bestVotes = p.votes;
                bestId = id;
            }
        }
    }
}
