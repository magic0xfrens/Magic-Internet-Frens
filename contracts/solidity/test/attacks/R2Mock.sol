// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @dev Minimal stand-ins for the two interfaces PerpVault declares
///      (contracts/solidity/cauldron/PerpVault.sol:8-28). Nothing here is
///      production code; it exists so the vault's OWN arithmetic can be driven
///      into states the live engine reaches (bad debt, zero free liquidity)
///      without a fork.
contract MockEngine {
    uint256 public plv;          // free ETH   (engine.freeEth)
    uint256 public lentEth;      // ETH lent to longs (counts in totalEth)
    uint256 public plvToken;     // free token (engine.freeToken)
    uint256 public lentToken;    // token lent to shorts
    uint256 public tokYieldEth;
    uint256 public tokYieldCumulative;
    address public vault;

    receive() external payable {}

    address public token;
    function setVault(address v) external { vault = v; }
    function setToken(address t) external { token = t; }
    function _tf(address to, uint256 a) private {
        (bool ok, bytes memory d) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, a));
        require(ok && (d.length == 0 || abi.decode(d,(bool))), "tf");
    }

    // --- IPerpEngineVault -------------------------------------------------
    function quote() external pure returns (address) { return address(0); }
    function totalEth() public view returns (uint256) { return plv + lentEth; }
    function freeEth() external view returns (uint256) { return plv; }
    function totalTokenAssets() public view returns (uint256) { return plvToken + lentToken; }
    function freeToken() external view returns (uint256) { return plvToken; }

    function fundFromVault(uint256 amount) external payable { plv += amount; }
    function withdrawPlvTo(uint256 amount, address to) external {
        require(msg.sender == vault, "onlyVault");
        plv -= amount;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "send");
    }
    function fundTokenFromVault(uint256 amount) external {
        plvToken += amount;
        (bool ok, bytes memory d) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount));
        require(ok && (d.length == 0 || abi.decode(d,(bool))), "tff");
    }
    function withdrawPlvTokenTo(uint256 amount, address to) external {
        require(msg.sender == vault, "onlyVault");
        plvToken -= amount;
        _tf(to, amount);
    }
    function withdrawTokYieldTo(uint256 amount, address) external { tokYieldEth -= amount; }

    // --- levers the real engine pulls internally --------------------------
    /// engine `_utilGate` lends PLV out to open positions: plv -> longOiEth.
    function lend(uint256 amount) external { plv -= amount; lentEth += amount; }
    function lendToken(uint256 amount) external { plvToken -= amount; lentToken += amount; }
    /// positions close and the principal returns to the free pot
    function repay(uint256 amount) external { lentEth -= amount; plv += amount; }
    /// `_absorbPlvLoss` (PerpEngine.sol:2243) after insurance is exhausted.
    function absorbPlvLoss(uint256 loss) external { plv = plv > loss ? plv - loss : 0; }
    function absorbLentLoss(uint256 loss) external { lentEth = lentEth > loss ? lentEth - loss : 0; }
    /// `_writeOffTok(..., false)` (PerpEngine.sol:2223): shortOiToken -= amount.
    function writeOffTok(uint256 amount) external { lentToken = lentToken > amount ? lentToken - amount : 0; }
}

contract MockRegistry {
    address public currentToken;
    function set(address t) external { currentToken = t; }
}

contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    function mint(address to, uint256 a) external { balanceOf[to] += a; }
    function approve(address s, uint256 a) external returns (bool) { allowance[msg.sender][s] = a; return true; }
    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a; balanceOf[to] += a; return true;
    }
    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= a;
        balanceOf[f] -= a; balanceOf[t] += a; return true;
    }
}
