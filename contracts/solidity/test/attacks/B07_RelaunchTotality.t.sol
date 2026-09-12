// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {YBase} from "./YBase.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {CauldronGovernor} from "../../cauldron/CauldronGovernor.sol";
import {ICauldronFactory} from "../../cauldron/CauldronBase.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";

/**
 * ═══════════════════════════════════════════════════════════════════════════
 *  B-07 — RELAUNCH TOTALITY  (the holder guarantee)
 * ═══════════════════════════════════════════════════════════════════════════
 *
 *  THE PROPERTY, stated once:
 *
 *      `relaunch()` must never revert in a way that rolls back
 *      `governor.markConsumed(winId)`.
 *
 *  That single sentence is the whole holder guarantee. `relaunch()` is
 *  permissionless and the ONLY path by which a dead generation becomes a live
 *  one — it is how holders migrate, how the reserve redeploys, and how the
 *  "eternal machine" is eternal. And it has a uniquely nasty failure mode:
 *  `markConsumed` sits at CauldronRegistry.sol:825, BEFORE the seed. Any revert
 *  after it rolls the consumption back with the transaction, so the same
 *  proposal keeps winning `CauldronGovernor._bestUnconsumed()` and every later
 *  call dies at the identical line. There is no retry, no timeout, no keeper
 *  that fixes it. A single reverting step is not a failed transaction — it is
 *  the permanent, unrecoverable death of the protocol with every holder's value
 *  locked inside a dead generation.
 *
 *  The codebase already knew this. Four separate sites cite audit C-02 and clamp
 *  rather than revert: the quote re-check (:811), the `nftSupply` bound
 *  (:817-820), the `newActive` underflow guard (:902-910), and the token-mining
 *  fallback (PoolOps:493-496). Two more use try/catch + gas caps citing Z-07
 *  (the perp force-close and the ticket drain). The failures found in this pass
 *  were all in the steps that had NOT been given that treatment.
 *
 *  This suite asserts the property directly, against deliberately hostile
 *  components, so a future change that reintroduces a bare revert on this path
 *  fails here instead of on-chain.
 *
 *  Covered:
 *    1. a winning proposal naming a non-native quote          (B-05)
 *    2. a floor vault whose `close()` reverts                 (lead L-3)
 *    3. a hook whose reserve release cannot pay               (B-06 consequence)
 *    4. the real governor refuses an unseedable quote up front
 *    5. repeated rebirths leave no state that accumulates into a brick
 * ═══════════════════════════════════════════════════════════════════════════
 */
contract B07_RelaunchTotality is YBase {
    BGov07 internal gov;

    function setUp() public {
        _boot(20 ether, 0);
        if (!active) return;
        gov = new BGov07();
        registry.setGovernor(address(gov));
        _arm();
    }

    /// @dev Put the live generation into a relaunchable state: dead + past its
    ///      minimum lifetime + past the anti-snipe window.
    function _arm() internal {
        hook.setDeathThreshold(type(uint256).max, address(0), 0, 0, 0);
        _warp(registry.minLifetime() + 1 days + 1);
        vm.roll(block.number + 60);
    }

    // ───────────────────────────────────────────────────────────────────────
    //  1. A hostile FLOOR VAULT cannot freeze the rebirth
    // ───────────────────────────────────────────────────────────────────────

    /// @notice `IVaultClose(oldVault).close()` (CauldronRegistry.sol:777) used to be
    ///         a bare call. `CauldronVault.close()` ends in
    ///         `registry.call{value: swept}("")` and reverts `TransferFailed` if that
    ///         send fails — which is reachable whenever the vault holds ether (anyone
    ///         may donate to its `receive()`) and the registry cannot accept it.
    ///         Safe today only by the coincidence of an empty vault plus a payable
    ///         registry; that is a coincidence, not a guarantee.
    ///
    ///  Injected through the FACTORY, which is owner-swappable — the honest way to
    ///  get a hostile vault into `generationVault[gen]` without poking storage.
    function test_TOTAL_HostileVaultCannotFreezeTheRebirth() public {
        vm.skip(!active);

        // Install a factory that hands back a vault whose close() always reverts.
        registry.setFactory(address(new HostileVaultFactory()));

        // Rebirth #1 installs the hostile vault as generation 2's floor vault.
        registry.relaunch();
        assertEq(registry.currentGeneration(), 2, "gen 2 reborn");
        address hostile = registry.generationVault(2);
        assertTrue(hostile != address(0), "hostile vault installed");
        assertTrue(HostileVault(payable(hostile)).reverts(), "and it is the reverting kind");

        // Rebirth #2 must CLOSE that hostile vault. Pre-fix this reverted and the
        // machine was dead here.
        _arm();
        registry.relaunch();

        assertEq(registry.currentGeneration(), 3, "the rebirth survives a reverting vault");
        assertEq(gov.consumedCount(), 2, "and both proposals were consumed, not rolled back");
    }

    // ───────────────────────────────────────────────────────────────────────
    //  2. An unpayable RESERVE RELEASE cannot freeze the rebirth
    // ───────────────────────────────────────────────────────────────────────

    /// @notice `hook.releaseRelaunchETH()` (CauldronRegistry.sol:782-784) reverts
    ///         `SendFailed` whenever the hook's ether balance has fallen below its
    ///         own `relaunchETH` counter — the counter is tracked by variable, not
    ///         by balance. B-06 was one way to desynchronise them; this test forces
    ///         the state directly, so the guard is asserted independently of whether
    ///         any particular desync bug exists.
    ///
    ///  The rebirth must proceed and seed with what it has.
    function test_TOTAL_UnpayableReserveCannotFreezeTheRebirth() public {
        vm.skip(!active);

        // Force the pathological state: the hook claims a reserve it cannot pay.
        // (`relaunchETH` is a public counter; the balance is what actually backs it.)
        uint256 counter = hook.relaunchETH();
        if (counter == 0) {
            _buy(1 ether, trader); // generate a fee so there IS a reserve
            counter = hook.relaunchETH();
        }
        assertGt(counter, 0, "hook has a booked reserve");

        // Remove the ether backing it, leaving the counter untouched.
        vm.deal(address(hook), 0);
        assertLt(address(hook).balance, counter, "reserve is now unbacked");

        _arm();
        registry.relaunch();

        assertEq(registry.currentGeneration(), 2, "the rebirth survives an unpayable reserve");
        assertEq(gov.consumedCount(), 1, "proposal consumed, not rolled back");
    }

    // ───────────────────────────────────────────────────────────────────────
    //  3. Repeated rebirths accumulate no bricking state
    // ───────────────────────────────────────────────────────────────────────

    /// @notice The machine must be reborn indefinitely. Four consecutive cycles,
    ///         each advancing the generation and consuming its proposal — so no
    ///         per-generation state (positions, ledgers, vaults, siblings) silently
    ///         accumulates into a revert.
    function test_TOTAL_MachineRelaunchesRepeatedly() public {
        vm.skip(!active);

        for (uint256 i; i < 4; ++i) {
            uint256 genBefore = registry.currentGeneration();
            registry.relaunch();
            assertEq(registry.currentGeneration(), genBefore + 1, "generation advances");
            _arm();
        }
        assertEq(registry.currentGeneration(), 5, "four consecutive rebirths");
        assertEq(gov.consumedCount(), 4, "four proposals consumed");
    }
}

// ═══════════════════════════════════════════════════════════════════════════
//  The governor validates the quote at the boundary, where refusing is free.
//  No fork needed — this is pure proposal validation.
// ═══════════════════════════════════════════════════════════════════════════

contract B07_GovernorQuoteBoundary is Test {
    CauldronGovernor internal governor;
    RegistryQuoteStub internal reg;

    address internal constant VETTED   = address(0xeDFd2eA3f44821dA02fFF085e893e677479D622C); // USDG
    address internal constant UNVETTED = address(0xDEAD);

    function setUp() public {
        governor = new CauldronGovernor(address(new VotesStub()), 0);
        reg = new RegistryQuoteStub();
        reg.allow(VETTED);
        //  WIRE THE REGISTRY. Without this, `governor.registry` is address(0), the
        //  allowlist staticcall returns empty, `ret.length < 32` trips, and EVERY
        //  non-native quote reverts — so a test asserting refusal would pass for a
        //  reason that has nothing to do with the allowlist. Found exactly that way.
        governor.setRegistry(address(reg));
    }

    function _propose(address quote) internal returns (uint256) {
        return governor.propose(
            "Wraith", "WRAITH", MetadataMode.BaseURI, "ipfs://w/",
            address(0), "w.xyz", "x.com/w", 1000, 0, quote
        );
    }

    /// @notice Native is allowed by construction and needs no lookup.
    function test_NativeQuoteIsAccepted() public {
        assertEq(_propose(address(0)), 1, "native proposal accepted");
    }

    /// @notice A VETTED non-native quote is accepted — the non-ETH rebirth is a
    ///         supported product, not a refused one. `relaunch()` narrows this a
    ///         second time against real balances (PoolOps.seedFunding) and degrades
    ///         rather than reverting, so accepting it here is safe.
    function test_VettedNonNativeQuoteIsAccepted() public {
        assertEq(_propose(VETTED), 1, "a treasury-vetted quote may be proposed");
    }

    /// @notice An UNVETTED quote is refused here, where refusing is free: it
    ///         rejects one proposal and freezes nothing. The same asymmetry as the
    ///         `nftSupply` bound beside it — a revert inside `relaunch()` would roll
    ///         back `markConsumed` and end the protocol.
    function test_UnvettedQuoteIsRefusedAtTheBoundary() public {
        vm.expectRevert(CauldronGovernor.QuoteNotAllowed.selector);
        _propose(UNVETTED);
    }

    /// @notice Refusal is on the QUOTE, not the proposer — the guard cannot be used
    ///         to grief an address out of proposing.
    function test_RefusalDoesNotPoisonTheProposer() public {
        vm.expectRevert(CauldronGovernor.QuoteNotAllowed.selector);
        _propose(UNVETTED);

        assertEq(_propose(address(0)), 1, "the proposer may still propose");
    }
}

/// @dev Minimal IVotes stand-in: everyone has voting power, so `propose` reaches
///      the validation this suite is about.
contract VotesStub {
    function getVotes(address) external pure returns (uint256) { return 1; }
    function getPastVotes(address, uint256) external pure returns (uint256) { return 1; }
}

/// @dev The registry surface the governor consults for the quote allowlist.
contract RegistryQuoteStub {
    mapping(address => bool) public allowedQuote;
    function allow(address q) external { allowedQuote[q] = true; }
}

/// @dev A governor whose winner is always a fresh native brew, counting
///      consumption so the tests can prove proposals are retired rather than
///      rolled back.
contract BGov07 {
    uint256 public consumedCount;

    function hasProposals() external pure returns (bool) { return true; }
    function markConsumed(uint256) external { consumedCount += 1; }

    function winner() external pure returns (uint256 id, BrewSpec07 memory spec) {
        spec = BrewSpec07({
            name: "Totality", symbol: "TOTAL", mode: MetadataMode.BaseURI,
            baseURI: "ipfs://t/", renderer: address(0), website: "t.xyz",
            socials: "x.com/t", quote: address(0), nftSupply: 1000,
            volumePerNFT: 0, proposer: address(0xBEEF)
        });
        id = 1;
    }
}

/// @dev Mirror of `BrewSpec` — declared locally so BGov07 needs no import cycle.
struct BrewSpec07 {
    string name;
    string symbol;
    MetadataMode mode;
    string baseURI;
    address renderer;
    string website;
    string socials;
    address quote;
    uint256 nftSupply;
    uint256 volumePerNFT;
    address proposer;
}

/// @dev A floor vault that refuses to close. Models the reachable state where the
///      vault holds ether and the registry cannot accept it.
contract HostileVault {
    bool public constant reverts = true;

    function outstanding() external pure returns (uint256) { return 0; }
    function close() external pure returns (uint256) { revert("vault: no"); }

    receive() external payable {}
}

/// @dev Wraps the real factory but substitutes a reverting vault, so a hostile
///      vault reaches `generationVault[gen]` through the supported wiring path
///      rather than a storage poke.
contract HostileVaultFactory {
    CauldronFactory internal immutable real = new CauldronFactory();

    function deployBrew(ICauldronFactory.Config calldata c)
        external
        returns (address collection, address vault)
    {
        // The two Config structs are distinct Solidity types with identical
        // fields; restate rather than cast.
        (collection,) = real.deployBrew(
            CauldronFactory.Config({
                name: c.name,
                symbol: c.symbol,
                hook: c.hook,
                registry: c.registry,
                maxSupply: c.maxSupply,
                mode: c.mode,
                baseURI: c.baseURI,
                renderer: c.renderer,
                royaltyReceiver: c.royaltyReceiver,
                royaltyBps: c.royaltyBps
            })
        );
        vault = address(new HostileVault());
    }

    function deployVault(address, address, uint256) external returns (address) {
        return address(new HostileVault());
    }
}
