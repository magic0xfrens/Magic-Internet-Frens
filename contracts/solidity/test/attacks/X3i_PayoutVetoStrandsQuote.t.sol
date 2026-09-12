// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {MockQuoteToken} from "../../cauldron/MockQuoteToken.sol";

contract X3iPM {
    // slot0 = (tick 0 << 160) | sqrtPriceX96 = 2**96 — a live 1:1 pool.
    bytes32 constant S0 = bytes32(uint256(79228162514264337593543950336));
    function extsload(bytes32) external pure returns (bytes32) { return S0; }
    function extsload(bytes32, uint256 n) external pure returns (bytes32[] memory r) { r = new bytes32[](n); }
    function extsload(bytes32[] calldata s) external pure returns (bytes32[] memory r) { r = new bytes32[](s.length); }
}

contract X3iRegistry {
    address public currentToken;
    uint256 public currentGeneration = 1;
    uint256 public lastSummonAt;
    mapping(uint256 => address) public generationQuote;
    constructor(address tok) { currentToken = tok; lastSummonAt = block.timestamp; }
    function rotateQuote(address q) external { generationQuote[currentGeneration] = q; }
}

/// A fee sink that cannot accept the quote — the shape the audit names for the
/// real MiFrensDividend and treasury sinks, and for any contract recipient whose
/// `receive()` reverts or costs more than the 30k settlement budget.
contract X3iRefuser {
    receive() external payable { revert("no thanks"); }
}

/// Thin exposure of the REAL `_routeFee`, so the stuck entry is created by
/// production code (`_routeFee` -> `_payOut` -> the credit at PerpEngine.sol:1461)
/// rather than planted with vm.store. Nothing is overridden.
contract X3iEngine is PerpEngine {
    constructor(IPoolManager pm, address hook, address reg, address mf, address div, address tre, address own)
        PerpEngine(pm, hook, reg, mf, div, tre, own) {}
    function routeFee(uint256 amount, bool longSide) external { _routeFee(amount, longSide); }
}

/**
 * X3i — the rotation guard added in e964d54 requires `payoutOwedTotal == 0`, but
 * `payoutOwedTotal` is cleared ONLY by `claimPayout()`, which is msg.sender-keyed
 * with no override. One wei owed to a recipient that refuses its push therefore
 * pins the counter non-zero forever and permanently VETOES quote adoption.
 *
 * The rotation itself still completes — RedemptionExt.sol:562 wraps the sync in
 * `try {} catch {}` — so the engine is left stranded on the OLD quote for the rest
 * of the generation: exactly the F-10/F-11 state the guard exists to prevent,
 * reached through a different door. It needs no attacker.
 */
contract X3iPayoutVetoStrandsQuote is Test {
    X3iEngine perp;
    X3iRegistry reg;
    X3iRefuser refuser;
    MockQuoteToken newQuote;
    address constant KEEPER = address(0xCEE9E4);

    function setUp() public {
        X3iPM pm = new X3iPM();
        MockQuoteToken tok = new MockQuoteToken("Gen1", "G1", 18);
        reg = new X3iRegistry(address(tok));
        reg.rotateQuote(address(0));                 // gen-1 launched NATIVE
        refuser = new X3iRefuser();
        perp = new X3iEngine(
            IPoolManager(address(pm)), address(this), address(reg),
            address(0xBEEF), address(refuser), address(0), address(this)
        );
        newQuote = new MockQuoteToken("USDG", "USDG", 18);
        // 100% of the routed fee goes to the dividend sink, so one wei of fee
        // becomes one wei owed to a recipient that cannot take it.
        perp.setFees(0, 0, 0, 10_000, 0);
    }

    function isDead(PoolId) external pure returns (bool) { return false; }

    // ── helpers ──────────────────────────────────────────────────────────────
    /// Route ONE WEI of trading fee to the refusing sink, through real code.
    function _stickOneWei() internal {
        vm.deal(address(perp), 1 wei);               // raw backing, no counter
        perp.routeFee(1, true);
    }
    function _rotateAndSync() internal returns (bool ok) {
        reg.rotateQuote(address(newQuote));
        vm.prank(KEEPER);
        try perp.syncGeneration() { ok = true; } catch { ok = false; }
    }
    function _refuserClaims() internal returns (bool ok) {
        vm.prank(address(refuser));
        try perp.claimPayout() returns (uint256) { ok = true; } catch { ok = false; }
    }

    /// A STRANGER retiring the entry. While the engine's quote disagrees with its
    /// generation's, this entry is the only thing standing between the engine and
    /// recovery, and S01's liveness invariant promises nothing privileged is needed
    /// to put that right — for any recipient that CAN be paid.
    function _strangerRetires() internal returns (bool ok) {
        vm.prank(address(0xC0FFEE));
        try perp.retirePayout(address(refuser)) { ok = true; } catch { ok = false; }
    }

    /// The timelock retiring it. This contract is the engine's owner.
    function _ownerRetires() internal returns (bool ok) {
        try perp.retirePayout(address(refuser)) { ok = true; } catch { ok = false; }
    }

    function test_OneWeiToARefusingSinkCannotVetoQuoteAdoption() public {
        _stickOneWei();
        uint256 owed = perp.payoutOwed(address(refuser));

        bool syncedWithStuckWei = _rotateAndSync();
        address quoteAfter = perp.quote();
        bool selfClaimWorks = _refuserClaims();

        assertEq(owed, 1, "one wei is owed to a sink that cannot accept it");
        assertEq(perp.plv(), 0, "every OTHER quote counter is clean");
        assertEq(perp.tokYieldEth(), 0, "...tokYieldEth clean");
        assertEq(perp.insuranceEth(), 0, "...insuranceEth clean");
        assertFalse(selfClaimWorks, "claimPayout - the ONLY clearer - reverts for this recipient");
        assertFalse(syncedWithStuckWei, "one wei DOES still gate adoption - the counter is load-bearing");
        assertEq(quoteAfter, address(0), "engine not yet on the new quote");

        // ── THE FIX: the gate is ESCAPABLE without the recipient's cooperation ──
        //  Before {retirePayout} existed, `payoutOwedTotal` was a one-way ratchet —
        //  cleared ONLY by the msg.sender-keyed {claimPayout} — so this state was
        //  permanent, and RedemptionExt's `try {} catch {}` around the sync meant the
        //  rotation completed anyway and left the engine stranded on the old quote
        //  for the rest of the generation. That is the F-10/F-11 shape the guard
        //  exists to prevent, reached through a different door.
        //  ── AND THE WRITE-OFF IS THE OWNER'S, NOT A STRANGER'S (F-02) ───────
        //  `retirePayout` discarded the push result, so while the engine was diverged
        //  ANY address could name ANY recipient and destroy its escrow — including a
        //  recipient that was only TRANSIENTLY unable to receive, whose claim
        //  {claimPayout} would have kept. A stranger may now only retire an entry
        //  whose value actually moved. THIS refuser reverts at full gas too, so it is
        //  a genuine write-off and the timelock takes it; liveness is unharmed
        //  because every payable recipient is still clearable by anyone
        //  (X9c_RetirePayoutBurnsEscrow asserts both halves).
        bool strangerRetired = _strangerRetires();
        uint256 owedAfterStranger = perp.payoutOwed(address(refuser));
        bool ownerRetired = _ownerRetires();
        bool syncedAfterRetire = _rotateAndSync();
        bool retireAgain = _ownerRetires();

        assertFalse(strangerRetired, "a stranger may NOT write off a claim the push could not deliver");
        assertEq(owedAfterStranger, 1, "the refuser keeps its wei until someone privileged writes it off");
        assertTrue(ownerRetired, "the owner (timelock) can, so the veto is always escapable");
        assertEq(perp.payoutOwed(address(refuser)), 0, "the stranded entry is gone");
        assertEq(perp.payoutOwedTotal(), 0, "and so is the veto");
        assertTrue(syncedAfterRetire, "the rotation now ADOPTS");
        assertEq(perp.quote(), address(newQuote), "engine follows its generation");
        assertFalse(retireAgain, "nothing left to retire - and once recovered it is owner-only again");
    }
}
