// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title MasterChef
/// @notice Simplified MasterChef contract supporting multiple staking pools and time-based rewards.
contract MasterChef is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct PoolInfo {
        IERC20 stakingToken;        // Address of staking token contract
        uint256 allocPoint;         // How many allocation points assigned to this pool
        uint256 lastRewardTime;     // Last timestamp that rewards distribution occurred
        uint256 accRewardPerShare;  // Accumulated rewards per share, multiplied by ACC_PRECISION
        uint256 totalStaked;        // Total tokens staked in the pool
    }

    struct UserInfo {
        uint256 amount;     // How many staking tokens the user has provided
        uint256 rewardDebt; // Reward debt
    }

    /// @notice Precision for accRewardPerShare
    uint256 private constant ACC_PRECISION = 1e12;

    /// @notice Reward token distributed by this contract
    IERC20 public immutable rewardToken;
    /// @notice Rewards created per second
    uint256 public rewardPerSec;

    /// @notice Array of pool information
    PoolInfo[] public poolInfo;
    /// @notice Mapping of pool ID => user address => user info
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    /// @notice Total allocation points. Must be the sum of all allocation points for all pools
    uint256 public totalAllocPoint;
    /// @notice The timestamp when rewards start
    uint256 public immutable startTime;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event PoolAdded(uint256 indexed pid, address token, uint256 allocPoint);
    event PoolUpdated(uint256 indexed pid, uint256 allocPoint);

    /// @param _rewardToken The reward token address
    /// @param _rewardPerSec Reward tokens created per second
    /// @param _startTime When reward distribution starts
    constructor(IERC20 _rewardToken, uint256 _rewardPerSec, uint256 _startTime) Ownable(msg.sender){
        rewardToken = _rewardToken;
        rewardPerSec = _rewardPerSec;
        startTime = _startTime;
    }

    /// @notice Return number of pools
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /// @notice Add a new staking pool. Can only be called by the owner.
    function addPool(uint256 _allocPoint, IERC20 _stakingToken, bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint += _allocPoint;
        poolInfo.push(PoolInfo({
            stakingToken: _stakingToken,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accRewardPerShare: 0,
            totalStaked: 0
        }));
        emit PoolAdded(poolInfo.length - 1, address(_stakingToken), _allocPoint);
    }

    /// @notice Update the given pool's allocation point. Can only be called by the owner.
    function setPool(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        } else {
            updatePool(_pid);
        }
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        emit PoolUpdated(_pid, _allocPoint);
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /// @notice View function to see pending reward tokens on frontend.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        if (block.timestamp > pool.lastRewardTime && pool.totalStaked != 0) {
            uint256 timeElapsed = block.timestamp - pool.lastRewardTime;
            uint256 reward = timeElapsed * rewardPerSec * pool.allocPoint / totalAllocPoint;
            accRewardPerShare += reward * ACC_PRECISION / pool.totalStaked;
        }
        return user.amount * accRewardPerShare / ACC_PRECISION - user.rewardDebt;
    }

    /// @notice Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        if (pool.totalStaked == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 timeElapsed = block.timestamp - pool.lastRewardTime;
        uint256 reward = timeElapsed * rewardPerSec * pool.allocPoint / totalAllocPoint;
        pool.accRewardPerShare += reward * ACC_PRECISION / pool.totalStaked;
        pool.lastRewardTime = block.timestamp;
    }

    /// @notice Deposit staking tokens to MasterChef for reward allocation.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount * pool.accRewardPerShare / ACC_PRECISION - user.rewardDebt;
            if (pending > 0) {
                rewardToken.safeTransfer(msg.sender, pending);
                emit Harvest(msg.sender, _pid, pending);
            }
        }
        if (_amount > 0) {
            pool.stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
            user.amount += _amount;
            pool.totalStaked += _amount;
        }
        user.rewardDebt = user.amount * pool.accRewardPerShare / ACC_PRECISION;
        emit Deposit(msg.sender, _pid, _amount);
    }

    /// @notice Withdraw staking tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount * pool.accRewardPerShare / ACC_PRECISION - user.rewardDebt;
        if (pending > 0) {
            rewardToken.safeTransfer(msg.sender, pending);
            emit Harvest(msg.sender, _pid, pending);
        }
        if (_amount > 0) {
            user.amount -= _amount;
            pool.totalStaked -= _amount;
            pool.stakingToken.safeTransfer(msg.sender, _amount);
        }
        user.rewardDebt = user.amount * pool.accRewardPerShare / ACC_PRECISION;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    /// @notice Harvest pending rewards from a pool.
    function harvest(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 pending = user.amount * pool.accRewardPerShare / ACC_PRECISION - user.rewardDebt;
        user.rewardDebt = user.amount * pool.accRewardPerShare / ACC_PRECISION;
        if (pending > 0) {
            rewardToken.safeTransfer(msg.sender, pending);
            emit Harvest(msg.sender, _pid, pending);
        }
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        require(amount > 0, "no stake");
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalStaked -= amount;
        pool.stakingToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    /// @notice Get user info for a pool.
    function getUserInfo(uint256 _pid, address _user) external view returns (UserInfo memory) {
        return userInfo[_pid][_user];
    }

    /// @notice Get pool info for a pool id.
    function getPoolInfo(uint256 _pid) external view returns (PoolInfo memory) {
        return poolInfo[_pid];
    }

    /// @notice Update reward per second. Owner only.
    function updateRewardPerSec(uint256 _rewardPerSec, bool _withUpdate) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        rewardPerSec = _rewardPerSec;
    }
}
