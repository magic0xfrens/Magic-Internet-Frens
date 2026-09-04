// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import { TickMath } from "./Utils/TickMath.sol";
import { FullMath, LiquidityAmounts } from "./Utils/LiquidityAmounts.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
pragma abicoder v2;
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function approve(address spender, uint value) external returns (bool);
}
interface IMinimalNonfungiblePositionManager {
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
        function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
          
        struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    /// @notice Collects up to a maximum amount of fees owed to a specific position to the recipient
    /// @param params tokenId The ID of the NFT for which tokens are being collected,
    /// recipient The account that should receive the tokens,
    /// amount0Max The maximum amount of token0 to collect,
    /// amount1Max The maximum amount of token1 to collect
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}
interface IFren {
    function balanceOf(address) external view returns (uint256);

    function enableTrading() external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);
}
interface IGameContract {
    function applyHeal(address player) external;
    function applyProtect(address player) external;
}

contract Cauldron is ReentrancyGuard  {
    IMinimalNonfungiblePositionManager public positionManager;

    struct StakedPosition {
    uint256 tokenId;
    uint128 liquidity;
    uint256 stakedAt;
    uint256 lastRewardTime;
}   
struct PositionGetter {
    uint128 liquidity;
    address token0;
    address token1;
    int24 tickLower;
    int24 tickUpper;
}
    IUniswapV3Pool public pool;  
    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    mapping(uint256 => address) public positionOwner;
    mapping(address => StakedPosition) public stakedPositions;
    address public  MIMANA_ADDRESS;
    address public constant WETH_ADDRESS = 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6;
      
      uint256[] public stakedTokenIds;
       address public owner;
int24 MinTick = TickMath.MIN_TICK; // Replace with actual min tick for the pool
int24 MaxTick = TickMath.MAX_TICK; // Replace with actual max tick for the pool
uint256 public totalStakedLiquidity;
uint256 public dailyRewardAmount= 1*10**18; // Daily reward amount in miMana tokens
uint256 public constant HEAL_POTION_COST = 100;
uint256 public constant PROTECT_POTION_COST = 200;
IGameContract public gameContract;


event PositionDeposited(uint256 indexed tokenId, address indexed from, address indexed to);

    constructor(address miMana) {
        owner = msg.sender;
        MIMANA_ADDRESS= miMana;
        positionManager = IMinimalNonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);// Base UniV3 Position Manager
    }
 modifier onlyOwner() {
        require(msg.sender == owner , "Caller is not the authorized");
        _;
    }
    function setGameContract(address GameContract) public onlyOwner{
        gameContract = IGameContract(GameContract);
        
    }
    function setPool(address _pool) public onlyOwner{
         pool = IUniswapV3Pool(_pool);
        
    }
   
      
function getPositionValue(uint256 tokenId)
    public
    view
    returns (
        uint128 liquidity,
        address token0,
        address token1,
        int24 tickLower,
        int24 tickUpper
    )
{
    (
        , // nonce
        , // operator
        address _token0, // token0
        address _token1, // token1
        , // fee
        int24 _tickLower, // tickLower
        int24 _tickUpper, // tickUpper
        uint128 _liquidity, // liquidity
        , // feeGrowthInside0LastX128
        , // feeGrowthInside1LastX128
        , // tokensOwed0
          // tokensOwed1
    ) = positionManager.positions(tokenId);

    return (_liquidity, _token0, _token1, _tickLower, _tickUpper);
}
function setDailyRewardAmount(uint256 _amount) external onlyOwner {
    dailyRewardAmount = _amount;
}

    function stakePosition(uint256 tokenId) public nonReentrant {
    (uint128 liquidity,address token0,address token1 , int24 tickLower,int24 tickUpper) = getPositionValue(tokenId);
     require(stakedPositions[msg.sender].tokenId == 0, "You Already have a staked position Fren");
   require(
            (token0 == MIMANA_ADDRESS && token1 == WETH_ADDRESS) || 
            (token0 == WETH_ADDRESS && token1 == MIMANA_ADDRESS), 
            "Position does not involve the correct token pair"
        );
        require(liquidity > 0, "Invalid liquidity");
         require(tickLower == MinTick && tickUpper == MaxTick, "Position does not span full range");

   
    

    // Transfer the NFT to this contract for staking
    // Ensure the NFT contract supports safeTransferFrom and the sender is the NFT owner
    positionManager.safeTransferFrom(msg.sender, address(this), tokenId,"");

    positionOwner[tokenId] = msg.sender;
    stakedPositions[msg.sender] = StakedPosition(tokenId,liquidity, block.timestamp,block.timestamp);
    stakedTokenIds.push(tokenId); // Add the token ID to the array
    totalStakedLiquidity += liquidity;

    // Additional logic for reward calculation start
}


   function withdrawPosition(uint256 tokenId) external nonReentrant {
    StakedPosition memory stakedPosition = stakedPositions[msg.sender];

    require(stakedPosition.tokenId == tokenId, "Not staked token");
    require(positionOwner[tokenId] == msg.sender, "Not position owner");

    // Transfer the NFT back to the user
    positionManager.safeTransferFrom(address(this), msg.sender, tokenId, "");

    totalStakedLiquidity -= stakedPosition.liquidity;
    // Clear the staked position data
     // Remove the tokenId from the stakedTokenIds array
    for (uint i = 0; i < stakedTokenIds.length; i++) {
        if (stakedTokenIds[i] == tokenId) {
            stakedTokenIds[i] = stakedTokenIds[stakedTokenIds.length - 1];
            stakedTokenIds.pop();
            break;
        }
    }
    delete positionOwner[tokenId];
    delete stakedPositions[msg.sender];
}
function pendingRewards(address user) public view returns (uint256) {
    StakedPosition memory position = stakedPositions[user];
    if (position.tokenId == 0 || totalStakedLiquidity == 0) {
        return 0;
    }

    uint256 timeElapsed = block.timestamp - position.lastRewardTime;
    uint256 userShare = (position.liquidity * 1e18) / totalStakedLiquidity; // Calculate user's share (using 1e18 for precision)
    uint256 rewards = (dailyRewardAmount * timeElapsed * userShare) / (1 days * 1e18);

    return rewards;
}
function claimRewards() public nonReentrant {
    StakedPosition storage position = stakedPositions[msg.sender];
    require(position.tokenId != 0, "No staked position");
    
    uint256 rewards = pendingRewards(msg.sender);
    require(rewards > 0, "No rewards available");

    position.lastRewardTime = block.timestamp; // Update the last reward time

    // Transfer miMana tokens to the user
    // Ensure that the contract has enough miMana tokens and is authorized to distribute them
    // miManaToken.transfer(msg.sender, rewards);
    require(IFren(MIMANA_ADDRESS).balanceOf(address(this)) > rewards, "No more $miMana to give");
        
        IFren(MIMANA_ADDRESS).transfer(msg.sender, rewards);
    // Emit an event if necessary
    // emit RewardsClaimed(msg.sender, rewards);
}
function drinkHealPotion() public nonReentrant {
    consumePotion(HEAL_POTION_COST);
     gameContract.applyHeal(msg.sender);

}

function drinkProtectPotion() public nonReentrant {
    consumePotion(PROTECT_POTION_COST);
     gameContract.applyProtect(msg.sender);
}

function consumePotion(uint256 potionCost) private {
    StakedPosition storage position = stakedPositions[msg.sender];
    require(position.tokenId != 0, "No staked position");

    uint256 rewards = pendingRewards(msg.sender);
    require(rewards >= potionCost, "Insufficient rewards to drink potion");

    position.lastRewardTime = block.timestamp; // Update the last reward time

    uint256 remainingRewards = rewards - potionCost;
    // Transfer remaining rewards to the user
    // miManaToken.transfer(msg.sender, remainingRewards);
 require(IFren(MIMANA_ADDRESS).balanceOf(address(this)) > remainingRewards, "No more $miMana to give");
        
        IFren(MIMANA_ADDRESS).transfer(msg.sender, remainingRewards);
    // Emit an event for drinking the potion
   
}
   function onERC721Received(address, address from, uint256 tokenId, bytes memory) public virtual  returns (bytes4) {
     emit PositionDeposited(tokenId, from, address(this));
        return this.onERC721Received.selector;
    }

    function collectAllFees() external returns (uint256 totalAmount0, uint256 totalAmount1) {
    uint256 amount0;
    uint256 amount1;

    for (uint i = 0; i < stakedTokenIds.length; i++) {
        IMinimalNonfungiblePositionManager.CollectParams memory params =
            IMinimalNonfungiblePositionManager.CollectParams({
                tokenId: stakedTokenIds[i],
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = positionManager.collect(params);
        totalAmount0 += amount0;
        totalAmount1 += amount1;
    }
}
function frensFundus() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(success);
    }

    function somethingAboutTokens(address token) external onlyOwner {
        uint256 balance = IFren(token).balanceOf(address(this));
        IFren(token).transfer(msg.sender, balance);
    }
    function swapExactInputSingle() external payable returns (uint amountOut) {
    require(msg.value > 0, "Must send ETH");

    // Wrap ETH to WETH
    IWETH(WETH_ADDRESS).deposit{value: msg.value}();
    assert(IWETH(WETH_ADDRESS).transfer(address(this), msg.value));

    // Approve the router to spend WETH
    IWETH(WETH_ADDRESS).approve(address(swapRouter), msg.value);

    // Set up swap parameters
    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
        tokenIn: WETH_ADDRESS,
        tokenOut: MIMANA_ADDRESS,
        fee: 3000, // Assuming a 0.3% pool fee
        recipient: msg.sender,
        deadline: block.timestamp,
        amountIn: msg.value,
        amountOutMinimum: 0,
        sqrtPriceLimitX96: 0
    });

    // Perform the swap
    amountOut = swapRouter.exactInputSingle(params);
}

}