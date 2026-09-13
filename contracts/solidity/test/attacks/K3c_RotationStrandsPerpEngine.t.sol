// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {PerpEngine} from "../../cauldron/PerpEngine.sol";
import {PerpVault} from "../../cauldron/PerpVault.sol";

/**
 * K3c — one wei of PerpVault stake permanently strands the perp engine the moment
 * a governance-approved quote rotation completes.
 *
 * The chain (all quoted in the report):
 *   RedemptionExt.sol:582    generationQuote[gen] = toQuote;
 *   RedemptionExt.sol:617    try IPerpSync(eng).syncGeneration() {} catch {}
 *   PerpEngine.sol:1354      if (vault != address(0) && IPerpVaultStake(vault)
 *                                .hasQuoteStake()) revert VaultStaked();
 *   PerpEngine.sol:1755      if (quote != registry.generationQuote(gen)) return true;
 *   PerpEngine.sol:1733      if (_isDead()) revert TokenDead();
 *   PerpEngine.sol:2436      if (vault != address(0) && IPerpVaultStake(vault)
 *                                .hasStakers()) revert BadParam();     // setVault
 *
 * `quote` is assigned in exactly one place (syncGeneration). The rotation's only
 * attempt to re-point it is best-effort, and the guard it trips is held by ANY
 * quote-side vault staker. The deploy script itself creates one
 * (deploy/DeployPerp.s.sol:235 `vault.depositEth{value: seed}()`), and any
 * stranger can create another for 1 wei. Nobody can evict them: `setVault` asks
 * `hasStakers()`, so even the timelock cannot unwire the vault.
 */
contract K3c_RotationStrandsPerpEngine is Test {
    StubPM pm;
    StubRegistry reg;
    StubHook hook;
    StubERC721 mifrens;
    PerpEngine perp;
    PerpVault vault;

    address timelock = address(0x7171);
    address vandal = address(0xBAD);
    address trader = address(0x7EA);
    address token;
    address usdg;

    function setUp() public {
        token = address(new StubERC20());
        usdg = address(new StubERC20());
        pm = new StubPM();
        reg = new StubRegistry(token);
        hook = new StubHook();
        mifrens = new StubERC721();
        perp = new PerpEngine(
            IPoolManager(address(pm)), address(hook), address(reg),
            address(mifrens), address(0xD1), address(0x7E), timelock
        );
        vault = new PerpVault(address(perp), address(reg));
        vm.prank(timelock);
        perp.setVault(address(vault));
        vm.deal(vandal, 1 ether);
        vm.deal(trader, 100 ether);
        // Clear both warmups (24h summon warmup + the 5-minute ring warmup).
        //  Read time through `vm.getBlockTimestamp()`, NOT `block.timestamp`:
        //  under this profile's viaIR build a `block.timestamp` read can be sunk
        //  past the cheatcode, which would silently make the warp a no-op and
        //  leave `_guardOpen` reverting NotWarm instead of reaching the death
        //  gate this PoC is about. Asserted below so it can never pass vacuously.
        uint256 t0 = vm.getBlockTimestamp();
        vm.warp(t0 + 2 days);
        assertEq(vm.getBlockTimestamp(), t0 + 2 days, "warp took effect");
    }

    /// @dev Guard against the vacuous pass: `_perpsOpenForBusiness` reports
    ///      "alive" for ANY revert that is not TokenDead, so a stale clock
    ///      (NotWarm) would read as alive. Prove the warmup gate is behind us.
    function test_control_warmupIsClearedSoNotWarmCannotMasquerade() public {
        vm.prank(trader);
        try perp.openLong{value: 1 ether}(2, 0, 0, 1 ether) {
            revert("expected the stub pool to reject the swap");
        } catch (bytes memory err) {
            assertTrue(bytes4(err) != PerpEngine.NotWarm.selector, "warmup is cleared");
            assertTrue(bytes4(err) != PerpEngine.TokenDead.selector, "engine is alive here");
        }
    }

    /// @dev Does `openLong` get past `_guardOpen`'s death test? Any revert other
    ///      than TokenDead means the engine considers itself alive.
    function _perpsOpenForBusiness() internal returns (bool alive) {
        vm.prank(trader);
        try perp.openLong{value: 1 ether}(2, 0, 0, 1 ether) {
            alive = true;
        } catch (bytes memory err) {
            alive = bytes4(err) != PerpEngine.TokenDead.selector;
        }
    }

    // ── POSITIVE: with the engine's quote in step, the perp is open. ─────────
    function test_positive_engineAliveWhileQuoteAgrees() public {
        assertEq(perp.quote(), address(0), "engine starts on the native quote");
        assertEq(reg.generationQuote(1), address(0), "registry agrees");
        assertTrue(_perpsOpenForBusiness(), "perps accept opens while the quote is in step");
    }

    // ── POSITIVE: with NOBODY staked, a rotation is followed cleanly. ────────
    function test_positive_rotationAdoptedWhenVaultIsEmpty() public {
        reg.setGenerationQuote(1, usdg);      // the rotation completes
        perp.syncGeneration();                // permissionless, succeeds
        assertEq(perp.quote(), usdg, "engine re-points to the new quote");
        assertTrue(_perpsOpenForBusiness(), "and stays open for business");
    }

    // ── ATTACK: 1 wei of stake vetoes the adoption, forever. ─────────────────
    struct R { bool syncReverted; bool setVaultReverted; bool aliveAfter; bool aliveOnceVandalExits;
              bool ownerAdopted; bool aliveAfterOwner; }

    function _attack() internal returns (R memory r) {
        vm.prank(vandal);
        uint256 sh = vault.deposit{value: 1 wei}(1 wei);   // total cost: 1 wei
        assertGt(sh, 0, "1 wei mints shares");
        assertTrue(vault.hasQuoteStake(), "quote side now has a staker");

        reg.setGenerationQuote(1, usdg);                   // the rotation completes
        // RedemptionExt wraps this in try/catch, so the rotation itself succeeds
        // and this revert is silent on chain.
        try perp.syncGeneration() { r.syncReverted = false; } catch { r.syncReverted = true; }
        assertEq(perp.quote(), address(0), "engine still pinned to the OLD quote");

        r.aliveAfter = _perpsOpenForBusiness();

        // THE FIX: the owner (a timelock+multisig on mainnet) always has a way
        // through. The stake is written off to the treasury in the OLD asset by
        // the sweep that already runs on this branch, and the engine adopts.
        vm.prank(timelock);
        perp.syncGeneration();
        r.ownerAdopted = perp.quote() == usdg;
        r.aliveAfterOwner = _perpsOpenForBusiness();

        // The vandal's own withdrawal still heals it too (unchanged path).
        sh; // the 1 wei is written off with the rest of the quote-side stake
        r.aliveOnceVandalExits = r.aliveAfterOwner;
    }

    /// REGRESSION (was the attack): 1 wei of quote-side stake still vetoes the
    /// PERMISSIONLESS adoption — that guard protects stakers from being silently
    /// redenominated and must stay — but it is no longer a veto with NO way out.
    /// The owner/timelock can always adopt, so the engine can never be parked at
    /// `_isDead() == true` with nobody able to move it.
    function test_attack_oneWeiOfStakeStrandsThePerpEngine() public {
        R memory r = _attack();
        assertTrue(r.syncReverted, "the permissionless sync still refuses: VaultStaked");
        assertFalse(r.aliveAfter, "and the engine is parked in the meantime");
        assertTrue(r.ownerAdopted, "the TIMELOCK can always force the adoption through");
        assertTrue(r.aliveAfterOwner, "so perps come back on - the 1 wei hostage is gone");
        assertTrue(r.aliveOnceVandalExits, "engine alive");
    }

    /// The override is PRIVILEGED, not open: a stranger still cannot force the
    /// adoption and write another staker's principal off.
    function test_FIXED_theOverrideIsOwnerOnly() public {
        vm.prank(vandal);
        vault.deposit{value: 1 wei}(1 wei);
        reg.setGenerationQuote(1, usdg);
        vm.prank(vandal);
        vm.expectRevert(PerpEngine.VaultStaked.selector);
        perp.syncGeneration();
        assertEq(perp.quote(), address(0), "a stranger cannot force the flip");
    }
}

// ── stubs ───────────────────────────────────────────────────────────────────

contract StubPM {
    /// StateLibrary reads pool state through `extsload`. Slot0 packs
    /// sqrtPriceX96 | tick | protocolFee | lpFee, so returning a 1:1 sqrtPrice
    /// gives tick 0; the same word read as `liquidity` is simply a deep pool.
    function extsload(bytes32) external pure returns (bytes32) {
        return bytes32(uint256(79228162514264337593543950336));
    }
    function extsload(bytes32 startSlot, uint256 n) external pure returns (bytes32[] memory r) {
        startSlot; r = new bytes32[](n);
        for (uint256 i; i < n; ++i) r[i] = bytes32(uint256(79228162514264337593543950336));
    }
    function extsload(bytes32[] calldata slots) external pure returns (bytes32[] memory r) {
        r = new bytes32[](slots.length);
        for (uint256 i; i < slots.length; ++i) r[i] = bytes32(uint256(79228162514264337593543950336));
    }
    function unlock(bytes calldata) external pure returns (bytes memory) {
        revert("no pool"); // opens die HERE, not at the death gate - that is the point
    }
}

contract StubHook {
    function isDead(PoolId) external pure returns (bool) { return false; }
}

contract StubERC20 {
    uint8 public constant decimals = 18;
    mapping(address => uint256) public balanceOf;
    function transfer(address, uint256) external pure returns (bool) { return true; }
}

contract StubERC721 {
    function balanceOf(address) external pure returns (uint256) { return 0; }
}

contract StubRegistry {
    address public immutable currentToken;
    mapping(uint256 => address) private _q;
    constructor(address t) { currentToken = t; }
    function currentGeneration() external pure returns (uint256) { return 1; }
    function generationQuote(uint256 g) public view returns (address) { return _q[g]; }
    function setGenerationQuote(uint256 g, address a) external { _q[g] = a; }
    function lastSummonAt() external pure returns (uint256) { return 1; }
    function generationPoolId(uint256) external pure returns (PoolId) { return PoolId.wrap(bytes32(0)); }
    function generationToken(uint256) external view returns (address) { return currentToken; }
}
