// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {RoyaltyRouter} from "../../cauldron/RoyaltyRouter.sol";
import {CauldronFactory} from "../../cauldron/CauldronFactory.sol";
import {CauldronCollection} from "../../cauldron/CauldronCollection.sol";
import {MetadataMode} from "../../cauldron/ICauldron.sol";

contract WETHLike {
    string public name = "Wrapped Ether";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
}

/// @notice Accepts fundLegacyBuffer so the ETH path is proven live in the same test.
contract HookStub {
    uint256 public buffered;
    function fundLegacyBuffer() external payable { buffered += msg.value; }
    receive() external payable {}
}

/// @notice Stands in for MiFrensDividend: it can hold and book an arbitrary ERC20.
contract SinkStub {
    mapping(address => uint256) public adopted;
    function adopt(address asset) external returns (uint256) {
        uint256 held = WETHLike(asset).balanceOf(address(this));
        adopted[asset] = held;
        return held;
    }
}

/// @notice A marketplace splitter that pays with the 2300-gas `transfer` stipend
///         (K4d). Reverts wholesale if the receiver cannot settle within it.
contract StipendPayer {
    function paySale(address payable receiver) external payable {
        receiver.transfer(msg.value);
    }
}

/**
 * K4a — every volume collection's EIP-2981 receiver is a {RoyaltyRouter} whose only
 * inbound path is `receive()`. A marketplace that settles a secondary sale in an
 * ERC20 (Blur is WETH-only; Seaport offers are routinely WETH/USDC) pays the royalty
 * with a plain `transfer` to that address. There is no owner, no sweep, no rescue and
 * no adopt: the tokens are stranded at every privilege level, forever.
 */
contract K4a_RoyaltyErc20Strand is Test {
    HookStub internal hookStub;
    CauldronFactory internal factory;
    WETHLike internal weth;
    SinkStub internal sink;

    function setUp() public {
        hookStub = new HookStub();
        factory = new CauldronFactory();
        weth = new WETHLike();
        sink = new SinkStub();
    }

    /// @dev Deploy a brew exactly as the factory does and return its 2981 receiver.
    function _deployBrewReceiver() internal returns (address receiver, address collection) {
        (address col, ) = factory.deployBrew(
            CauldronFactory.Config({
                name: "Creature",
                symbol: "CRT",
                hook: address(hookStub),
                registry: address(this),
                maxSupply: 1000,
                mode: MetadataMode.BaseURI,
                baseURI: "ipfs://c/",
                renderer: address(0),
                royaltyReceiver: address(sink),
                royaltyBps: 500
            })
        );
        collection = col;
        (receiver, ) = CauldronCollection(col).royaltyInfo(1, 1 ether);
    }

    /// @dev Native royalty: forwarded atomically, router holds nothing. (positive)
    function _nativeRoyaltyReaches(address receiver, uint256 amount) internal returns (uint256 delivered) {
        (bool ok, ) = payable(receiver).call{value: amount}("");
        require(ok, "native royalty rejected");
        delivered = hookStub.buffered();
    }

    /// @dev ERC20 royalty: pushed by the marketplace, then probe every recovery
    ///      selector a rescue could plausibly live behind.
    function _erc20RoyaltyRecoverable(address receiver, uint256 amount)
        internal
        returns (bool recoverable, uint256 strandedBalance)
    {
        weth.mint(address(this), amount);
        weth.transfer(receiver, amount);

        bytes[] memory probes = new bytes[](7);
        probes[0] = abi.encodeWithSignature("adopt(address)", address(weth));
        probes[1] = abi.encodeWithSignature("rescueToken(address,address,uint256)", address(weth), address(this), amount);
        probes[2] = abi.encodeWithSignature("sweep(address)", address(weth));
        probes[3] = abi.encodeWithSignature("withdraw(address,uint256)", address(weth), amount);
        probes[4] = abi.encodeWithSignature("owner()");
        probes[5] = abi.encodeWithSignature("transferOwnership(address)", address(this));
        probes[6] = abi.encodeWithSignature("fundLegacyBuffer()");

        recoverable = false;
        for (uint256 i; i < probes.length; ++i) {
            (bool ok, ) = receiver.call(probes[i]);
            if (ok && weth.balanceOf(receiver) < amount) recoverable = true;
        }
        strandedBalance = weth.balanceOf(receiver);
    }

    /**
     * REGRESSION (was: the attack). The ERC20 royalty is no longer stranded — the
     * permissionless `sweep(address)` probe now succeeds and the WETH lands at the
     * router's IMMUTABLE erc20Sink (the genesis dividend), which can split it.
     * Nothing here was weakened: the same seven recovery probes are fired, the
     * same amounts are asserted, and the native positive control still runs.
     */
    function test_K4a_erc20_royalty_is_permanently_stranded() public {
        (address receiver, address collection) = _deployBrewReceiver();

        // The receiver really is a RoyaltyRouter wired to the hook.
        assertEq(RoyaltyRouter(payable(receiver)).hook(), address(hookStub), "receiver is the RoyaltyRouter");
        assertTrue(collection != address(0), "collection deployed");
        // And its ERC20 destination is fixed at construction — a stranger who calls
        // the permissionless sweep cannot point it anywhere else.
        assertEq(RoyaltyRouter(payable(receiver)).erc20Sink(), address(sink), "sink is immutable and is the dividend");

        // POSITIVE: the ETH royalty path still works end to end, unchanged.
        uint256 delivered = _nativeRoyaltyReaches(receiver, 1 ether);
        assertEq(delivered, 1 ether, "native royalty reaches the legacy buffer");
        assertEq(receiver.balance, 0, "router holds no ether");

        // WAS THE ATTACK: the same royalty paid in WETH is now recoverable, by
        // anyone, without weakening who may redirect it.
        vm.prank(address(0xB0B)); // a total stranger drives the recovery
        (bool recoverable, uint256 stranded) = _erc20RoyaltyRecoverable(receiver, 5 ether);
        assertTrue(recoverable, "the ERC20 royalty is recoverable");
        assertEq(stranded, 0, "nothing is left stuck on the router");
        assertEq(weth.balanceOf(address(sink)), 5 ether, "the whole royalty reached the dividend");
        assertEq(sink.adopted(address(weth)), 5 ether, "and the sink booked it via adopt");
        emit log_named_uint("recovered WETH royalty (wei)", weth.balanceOf(address(sink)));
    }

    /**
     * K4d — a marketplace splitter paying with the 2300-gas `transfer` stipend used
     * to revert the SALE, because the router's unmetered forward into
     * `fundLegacyBuffer` ran out of gas and the failure bubbled. Now the router
     * keeps the ether instead of blocking the trade, and `sweep(address(0))`
     * delivers it to exactly the same place the happy path does.
     */
    function test_K4d_stipend_payer_cannot_revert_the_sale() public {
        (address receiver, ) = _deployBrewReceiver();
        StipendPayer payer = new StipendPayer();
        vm.deal(address(this), 10 ether);

        uint256 bufferedBefore = hookStub.buffered();
        payer.paySale{value: 1 ether}(payable(receiver)); // MUST NOT REVERT
        emit log_named_uint("held on the router after a stipend sale (wei)", receiver.balance);

        // The stipend was too small to forward, so the ether is HELD, not lost...
        assertEq(receiver.balance, 1 ether, "stipend royalty is held, not stranded and not reverted");
        assertEq(hookStub.buffered(), bufferedBefore, "the forward was correctly skipped");

        // ...and any stranger can push it along to the legacy buffer afterwards.
        vm.prank(address(0xB0B));
        RoyaltyRouter(payable(receiver)).sweep(address(0));
        assertEq(receiver.balance, 0, "sweep emptied the router");
        assertEq(hookStub.buffered(), bufferedBefore + 1 ether, "and it reached the legacy buffer");
    }
}
