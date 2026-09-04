// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MagicFrensPresale
 * @notice Simple presale contract that accepts ETH and tracks contributions
 *
 * Features:
 * - Accept ETH payments
 * - Track contributor amounts
 * - Withdrawable by owner (for liquidity setup)
 * - Claim tracking (prevent double claims)
 * - Emergency pause
 */
contract MagicFrensPresale is Ownable, ReentrancyGuard {
    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Presale price per token (0.01 ETH = 1e16 wei)
    uint256 public constant PRESALE_PRICE = 0.01 ether;

    /// @notice Maximum tokens available in presale
    uint256 public constant MAX_PRESALE_TOKENS = 1111;

    /// @notice Minimum contribution (1 token)
    uint256 public constant MIN_CONTRIBUTION = PRESALE_PRICE;

    /// @notice Maximum contribution per address (100 tokens)
    uint256 public constant MAX_CONTRIBUTION_PER_ADDRESS = 100 * PRESALE_PRICE;

    /// @notice Total ETH raised
    uint256 public totalRaised;

    /// @notice Total tokens sold
    uint256 public totalTokensSold;

    /// @notice Presale active status
    bool public presaleActive = true;

    /// @notice Emergency pause
    bool public paused = false;

    /// @notice MagicFrensPeg token address (set after deployment)
    address public magicFrensToken;

    /// @notice Treasury wallet for BTC/other payments
    address public treasury;

    /// @notice User contributions: address => amount in wei
    mapping(address => uint256) public contributions;

    /// @notice Claim status: address => claimed
    mapping(address => bool) public claimed;

    /// @notice Whitelist for early access (optional)
    mapping(address => bool) public whitelist;

    /// @notice Whitelist-only phase
    bool public whitelistOnly = false;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event Contribution(address indexed contributor, uint256 amount, uint256 tokens);
    event TokensClaimed(address indexed contributor, uint256 amount);
    event PresaleEnded(uint256 totalRaised, uint256 totalTokensSold);
    event Withdrawn(address indexed owner, uint256 amount);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event TokenAddressSet(address indexed tokenAddress);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(address _treasury) Ownable(msg.sender) {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PRESALE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Contribute to presale with ETH
     */
    function contribute() external payable nonReentrant {
        require(presaleActive, "Presale ended");
        require(!paused, "Presale paused");
        require(msg.value >= MIN_CONTRIBUTION, "Below minimum");
        require(msg.value % PRESALE_PRICE == 0, "Must be multiple of presale price");

        if (whitelistOnly) {
            require(whitelist[msg.sender], "Not whitelisted");
        }

        uint256 tokens = msg.value / PRESALE_PRICE;
        require(totalTokensSold + tokens <= MAX_PRESALE_TOKENS, "Exceeds max supply");

        uint256 newTotal = contributions[msg.sender] + msg.value;
        require(newTotal <= MAX_CONTRIBUTION_PER_ADDRESS, "Exceeds max per address");

        contributions[msg.sender] = newTotal;
        totalRaised += msg.value;
        totalTokensSold += tokens;

        emit Contribution(msg.sender, msg.value, tokens);

        // Auto-end presale if sold out
        if (totalTokensSold == MAX_PRESALE_TOKENS) {
            presaleActive = false;
            emit PresaleEnded(totalRaised, totalTokensSold);
        }
    }

    /**
     * @notice Claim MagicFrensPeg tokens after presale ends
     * @dev Requires magicFrensToken to be set
     */
    function claimTokens() external nonReentrant {
        require(!presaleActive, "Presale still active");
        require(magicFrensToken != address(0), "Token address not set");
        require(contributions[msg.sender] > 0, "No contribution");
        require(!claimed[msg.sender], "Already claimed");

        uint256 tokenAmount = (contributions[msg.sender] / PRESALE_PRICE) * 1e18; // Convert to 18 decimals
        claimed[msg.sender] = true;

        IERC20(magicFrensToken).transfer(msg.sender, tokenAmount);

        emit TokensClaimed(msg.sender, tokenAmount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice End presale early
     */
    function endPresale() external onlyOwner {
        require(presaleActive, "Already ended");
        presaleActive = false;
        emit PresaleEnded(totalRaised, totalTokensSold);
    }

    /**
     * @notice Set MagicFrensPeg token address
     */
    function setTokenAddress(address _token) external onlyOwner {
        require(_token != address(0), "Invalid address");
        require(magicFrensToken == address(0), "Already set");
        magicFrensToken = _token;
        emit TokenAddressSet(_token);
    }

    /**
     * @notice Update treasury address (for BTC/other payments)
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    /**
     * @notice Withdraw ETH to owner (for DEX liquidity setup)
     */
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");

        (bool success, ) = owner().call{value: balance}("");
        require(success, "Transfer failed");

        emit Withdrawn(owner(), balance);
    }

    /**
     * @notice Emergency pause
     */
    function togglePause() external onlyOwner {
        paused = !paused;
    }

    /**
     * @notice Add addresses to whitelist
     */
    function addToWhitelist(address[] calldata addresses) external onlyOwner {
        uint256 n = addresses.length;
        for (uint256 i = 0; i < n;) {
            whitelist[addresses[i]] = true;
            unchecked { ++i; }
        }
    }

    /**
     * @notice Toggle whitelist-only phase
     */
    function toggleWhitelistOnly() external onlyOwner {
        whitelistOnly = !whitelistOnly;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Get contribution details for an address
     */
    function getContribution(address contributor) external view returns (
        uint256 amount,
        uint256 tokens,
        bool hasClaimed
    ) {
        amount = contributions[contributor];
        tokens = amount / PRESALE_PRICE;
        hasClaimed = claimed[contributor];
    }

    /**
     * @notice Get presale stats
     */
    function getPresaleStats() external view returns (
        uint256 raised,
        uint256 sold,
        uint256 remaining,
        bool active,
        bool isPaused
    ) {
        raised = totalRaised;
        sold = totalTokensSold;
        remaining = MAX_PRESALE_TOKENS - totalTokensSold;
        active = presaleActive;
        isPaused = paused;
    }

    /**
     * @notice Receive ETH directly
     */
    receive() external payable {
        // Forward to contribute() for tracking
        revert("Use contribute() function");
    }
}
