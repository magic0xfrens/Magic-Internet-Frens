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

    function setUp() public {
        hookStub = new HookStub();
        factory = new CauldronFactory();
        weth = new WETHLike();
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
                royaltyReceiver: address(0xDEAD),
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

    function test_K4a_erc20_royalty_is_permanently_stranded() public {
        (address receiver, address collection) = _deployBrewReceiver();

        // The receiver really is a RoyaltyRouter wired to the hook.
        assertEq(RoyaltyRouter(payable(receiver)).hook(), address(hookStub), "receiver is the RoyaltyRouter");
        assertTrue(collection != address(0), "collection deployed");

        // POSITIVE: the ETH royalty path works end to end.
        uint256 delivered = _nativeRoyaltyReaches(receiver, 1 ether);
        assertEq(delivered, 1 ether, "native royalty reaches the legacy buffer");
        assertEq(receiver.balance, 0, "router holds no ether");

        // ATTACK / LOSS: the same royalty paid in WETH never leaves.
        (bool recoverable, uint256 stranded) = _erc20RoyaltyRecoverable(receiver, 5 ether);
        assertFalse(recoverable, "no privilege level can recover the ERC20 royalty");
        assertEq(stranded, 5 ether, "the whole ERC20 royalty is stuck on the router");
        emit log_named_uint("stranded WETH royalty (wei)", stranded);
    }
}
