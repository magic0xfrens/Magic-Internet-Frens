// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {HookMiner} from "../../vendor/HookMiner.sol";
import {CauldronHook} from "../../CauldronHook.sol";
import {RoyaltyRouter} from "../../cauldron/RoyaltyRouter.sol";

contract X1ePoolManagerStub { receive() external payable {} }

/**
 * @title X1e — a royalty payment must never revert, and must never strand
 *
 *  {RoyaltyRouter} is the collection's EIP-2981 receiver and its `receive()`
 *  forwards unconditionally (cauldron/RoyaltyRouter.sol:33):
 *
 *      if (msg.value > 0) ILegacyBuffer(hook).fundLegacyBuffer{value: msg.value}();
 *
 *  When the X1/X4a denomination fix made `fundLegacyBuffer` REVERT on an
 *  ERC20-quoted generation, that turned into a permissionless liveness break:
 *  every marketplace royalty payment reverted, and a marketplace that pushes
 *  royalties atomically inside the sale would have had the WHOLE SALE revert for
 *  as long as the generation was ERC20-quoted. RoyaltyRouter has no owner, no
 *  sweep and no withdraw, so holding the ETH there instead would have stranded
 *  it at every privilege level — the same bug class, relocated.
 *
 *  The fix routes rather than refuses: the buffer still cannot take wei it would
 *  spend as ERC20 units (the Critical is untouched), and the payment lands in
 *  `relaunchETH`, which `releaseRelaunchETH` pays out.
 */
contract X1eRoyaltyRouterOnErc20Quote is Test {
    CauldronHook internal hook;
    RoyaltyRouter internal router;

    uint160 internal constant HOOK_FLAGS = uint160(
        Hooks.AFTER_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
            | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
    );

    address internal constant MARKETPLACE = address(0x4A4E);
    address internal constant QUOTE = address(0x115D6); // a 6-decimal stable quote
    address internal constant BREW = address(0xB2E4);
    uint256 internal constant ROYALTY = 0.5 ether;

    function setUp() public {
        X1ePoolManagerStub pm = new X1ePoolManagerStub();
        bytes memory ctorArgs =
            abi.encode(IPoolManager(address(pm)), uint256(1 ether), address(0), address(this), address(this));
        (address mined, bytes32 salt) =
            HookMiner.find(address(this), HOOK_FLAGS, type(CauldronHook).creationCode, ctorArgs);
        hook = new CauldronHook{salt: salt}(
            IPoolManager(address(pm)), 1 ether, address(0), address(this), address(this)
        );
        require(address(hook) == mined, "hook addr");

        // This test IS the registry, so it can set the live key and pull the
        // reserve back out the same way the real registry does.
        hook.setRegistry(address(this));
        router = new RoyaltyRouter(address(hook));
    }

    function _key(address c0, address c1) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(c0),
            currency1: Currency.wrap(c1),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });
    }

    /// @dev A marketplace paying an EIP-2981 royalty: plain ETH to the receiver.
    function _payRoyalty(uint256 amount) internal returns (bool ok) {
        vm.deal(MARKETPLACE, amount);
        vm.prank(MARKETPLACE);
        (ok, ) = address(router).call{value: amount}("");
    }

    function test_X1e_royaltyOnAnErc20QuotedGenerationIsAcceptedAndRecoverable() public {
        hook.setLiveKey(_key(QUOTE, BREW));

        bool ok = _payRoyalty(ROYALTY);

        emit log_named_uint("royalty accepted (1 = yes)", ok ? 1 : 0);
        emit log_named_uint("legacyBuffer              ", hook.legacyBuffer());
        emit log_named_uint("relaunchETH               ", hook.relaunchETH());
        emit log_named_uint("ETH stranded in the router", address(router).balance);

        // 1. THE SALE DOES NOT REVERT.
        assertTrue(ok, "a marketplace royalty payment must never revert");
        // 2. The Critical stays closed: no wei entered a buffer spent as ERC20 units.
        assertEq(hook.legacyBuffer(), 0, "no wei in a buffer denominated in the quote");
        // 3. Nothing is stranded in a contract with no owner and no sweep.
        assertEq(address(router).balance, 0, "the router still holds nothing");
        // 4. The value landed somewhere with a release path.
        assertEq(hook.relaunchETH(), ROYALTY, "credited to the relaunch reserve");
        assertEq(address(hook).balance, ROYALTY, "and the hook really holds it");

        // 5. RECOVERABLE: the registry can pull it straight back out.
        uint256 before = address(this).balance;
        uint256 released = hook.releaseRelaunchETH();
        assertEq(released, ROYALTY, "releaseRelaunchETH returns the whole royalty");
        assertEq(address(this).balance - before, ROYALTY, "and the ether really arrives");
        assertEq(hook.relaunchETH(), 0, "counter cleared");
    }

    /// @notice The ether-quoted path is unchanged: the royalty still becomes
    ///         buyback buffer, which is what backs the collection's token floor.
    function test_X1e_royaltyOnANativeQuotedGenerationStillFundsTheBuffer() public {
        hook.setLiveKey(_key(address(0), BREW));

        bool ok = _payRoyalty(ROYALTY);

        emit log_named_uint("legacyBuffer", hook.legacyBuffer());
        emit log_named_uint("relaunchETH ", hook.relaunchETH());

        assertTrue(ok, "a marketplace royalty payment must never revert");
        assertEq(hook.legacyBuffer(), ROYALTY, "native generation: it is buyback buffer, as before");
        assertEq(hook.legacyBufferAsset(), address(0), "tagged native");
        assertEq(hook.relaunchETH(), 0, "and it did NOT take the reserve route");
        assertEq(address(router).balance, 0, "the router still holds nothing");
    }

    /// @notice A rotation mid-life must not turn later royalties into a revert
    ///         either — the route flips, the payment still lands.
    function test_X1e_royaltyKeepsLandingAcrossAQuoteRotation() public {
        hook.setLiveKey(_key(address(0), BREW));
        assertTrue(_payRoyalty(ROYALTY), "native leg accepted");
        assertEq(hook.legacyBuffer(), ROYALTY, "buffered while ether-quoted");

        // The treasury rotates the generation onto a 6-decimal stable.
        hook.setLiveKey(_key(QUOTE, BREW));

        assertTrue(_payRoyalty(ROYALTY), "post-rotation royalty accepted too");

        emit log_named_uint("buffer after rotation", hook.legacyBuffer());
        emit log_named_uint("reserve after rotation", hook.relaunchETH());

        assertEq(hook.legacyBuffer(), ROYALTY, "the pre-rotation buffer is untouched, not mixed");
        assertEq(hook.relaunchETH(), ROYALTY, "the post-rotation royalty took the reserve route");
        assertEq(address(router).balance, 0, "nothing stranded in the router at any point");
    }

    receive() external payable {}
}
