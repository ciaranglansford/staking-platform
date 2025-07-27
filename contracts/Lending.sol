// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

error TransferFailed();
error TokenNotAllowed(address token);
error NeedsMoreThanZero();
error NotEnoughCollateral();
error NotEnoughLiquidity();
error HealthFactorTooLow();
error CannotLiquidateHealthyAccount();
error InterestAccrualFailed();

contract Lending is ReentrancyGuard, Ownable, Pausable {
    struct TokenData {
        address priceFeed;
        uint256 collateralFactor; // in bps (e.g., 8000 = 80%)
    }

    mapping(address => TokenData) private s_tokenData;
    address[] private s_allowedTokens;

    mapping(address => mapping(address => uint256)) private s_deposits;
    mapping(address => mapping(address => uint256)) private s_borrows;
    mapping(address => mapping(address => uint256)) private s_lastInterestAccrual;

    uint256 public constant LIQUIDATION_REWARD_BPS = 500; // 5%
    uint256 public constant BPS_DIVISOR = 10000;
    uint256 public constant INTEREST_RATE_BPS = 300; // e.g., 3% annualized
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event Borrow(address indexed user, address indexed token, uint256 amount);
    event Repay(address indexed user, address indexed token, uint256 amount);
    event Liquidate(address indexed account, address indexed repayToken, address indexed rewardToken, address liquidator);
    event TokenListed(address indexed token, address priceFeed, uint256 collateralFactor);

    modifier onlyAllowedToken(address token) {
        if (s_tokenData[token].priceFeed == address(0)) revert TokenNotAllowed(token);
        _;
    }

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert NeedsMoreThanZero();
        _;
    }

    constructor() Ownable(msg.sender) {}

    function deposit(address token, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyAllowedToken(token)
        moreThanZero(amount)
    {
        accrueInterest(msg.sender, token);
        s_deposits[msg.sender][token] += amount;
        emit Deposit(msg.sender, token, amount);
        if (!IERC20(token).transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
    }

    function withdraw(address token, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyAllowedToken(token)
        moreThanZero(amount)
    {
        accrueInterest(msg.sender, token);
        s_deposits[msg.sender][token] -= amount;
        if (healthFactor(msg.sender) < 1e18) revert HealthFactorTooLow();
        emit Withdraw(msg.sender, token, amount);
        if (!IERC20(token).transfer(msg.sender, amount)) revert TransferFailed();
    }

    function borrow(address token, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyAllowedToken(token)
        moreThanZero(amount)
    {
        accrueInterest(msg.sender, token);
        if (IERC20(token).balanceOf(address(this)) < amount) revert NotEnoughLiquidity();
        s_borrows[msg.sender][token] += amount;
        if (healthFactor(msg.sender) < 1e18) revert HealthFactorTooLow();
        emit Borrow(msg.sender, token, amount);
        if (!IERC20(token).transfer(msg.sender, amount)) revert TransferFailed();
    }

    function repay(address token, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyAllowedToken(token)
        moreThanZero(amount)
    {
        accrueInterest(msg.sender, token);
        s_borrows[msg.sender][token] -= amount;
        emit Repay(msg.sender, token, amount);
        if (!IERC20(token).transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
    }

    function liquidate(address account, address repayToken, address rewardToken) external nonReentrant whenNotPaused {
        if (healthFactor(account) >= 1e18) revert CannotLiquidateHealthyAccount();
        accrueInterest(account, repayToken);
        uint256 halfDebt = s_borrows[account][repayToken] / 2;
        uint256 repayValueETH = _getValueInETH(repayToken, halfDebt);
        uint256 rewardETH = (repayValueETH * LIQUIDATION_REWARD_BPS) / BPS_DIVISOR;
        uint256 totalETH = repayValueETH + rewardETH;
        uint256 rewardTokenAmount = _getValueFromETH(rewardToken, totalETH);

        s_borrows[account][repayToken] -= halfDebt;
        emit Liquidate(account, repayToken, rewardToken, msg.sender);
        if (!IERC20(repayToken).transferFrom(msg.sender, address(this), halfDebt)) revert TransferFailed();
        s_deposits[account][rewardToken] -= rewardTokenAmount;
        if (!IERC20(rewardToken).transfer(msg.sender, rewardTokenAmount)) revert TransferFailed();
    }

    function listToken(address token, address priceFeed, uint256 collateralFactorBps) external onlyOwner {
        require(collateralFactorBps <= 9000, "Over 90% not allowed");
        if (s_tokenData[token].priceFeed == address(0)) s_allowedTokens.push(token);
        s_tokenData[token] = TokenData(priceFeed, collateralFactorBps);
        emit TokenListed(token, priceFeed, collateralFactorBps);
    }

    function accrueInterest(address user, address token) public {
        uint256 last = s_lastInterestAccrual[user][token];
        uint256 current = block.timestamp;
        if (last == 0) {
            s_lastInterestAccrual[user][token] = current;
            return;
        }
        uint256 delta = current - last;
        s_lastInterestAccrual[user][token] = current;
        uint256 currentBorrow = s_borrows[user][token];
        if (currentBorrow  == 0) return;
        uint256 interest = (currentBorrow  * INTEREST_RATE_BPS * delta) / (BPS_DIVISOR * SECONDS_PER_YEAR);
        s_borrows[user][token] += interest;
    }

    function getCollateralValue(address user) public view returns (uint256 totalETH) {
        for (uint256 i = 0; i < s_allowedTokens.length; i++) {
            address token = s_allowedTokens[i];
            uint256 amount = s_deposits[user][token];
            if (amount > 0) {
                uint256 value = _getValueInETH(token, amount);
                uint256 factor = s_tokenData[token].collateralFactor;
                totalETH += (value * factor) / BPS_DIVISOR;
            }
        }
    }

    function getBorrowedValue(address user) public view returns (uint256 totalETH) {
        for (uint256 i = 0; i < s_allowedTokens.length; i++) {
            address token = s_allowedTokens[i];
            uint256 amount = s_borrows[user][token];
            if (amount > 0) totalETH += _getValueInETH(token, amount);
        }
    }

    function healthFactor(address user) public view returns (uint256) {
        uint256 borrowedValue  = getBorrowedValue(user);
        if (borrowedValue  == 0) return 1e36;
        uint256 collateral = getCollateralValue(user);
        return (collateral * 1e18) / borrowedValue;
    }

    function _getValueInETH(address token, uint256 amount) internal view returns (uint256) {
        AggregatorV3Interface feed = AggregatorV3Interface(s_tokenData[token].priceFeed);
        (, int256 price,,,) = feed.latestRoundData();
        uint8 decimals = feed.decimals();
        return (amount * uint256(price)) / (10 ** decimals);
    }

    function _getValueFromETH(address token, uint256 ethAmount) internal view returns (uint256) {
        AggregatorV3Interface feed = AggregatorV3Interface(s_tokenData[token].priceFeed);
        (, int256 price,,,) = feed.latestRoundData();
        uint8 decimals = feed.decimals();
        return (ethAmount * (10 ** decimals)) / uint256(price);
    }

    // Admin Controls
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Public Getters
    function getDeposit(address user, address token) external view returns (uint256) {
        return s_deposits[user][token];
    }

    function getBorrow(address user, address token) external view returns (uint256) {
        return s_borrows[user][token];
    }

    function getAllowedTokens() external view returns (address[] memory) {
        return s_allowedTokens;
    }
}