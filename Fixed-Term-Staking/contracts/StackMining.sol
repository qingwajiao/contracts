// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./libraries/SafeBEP20.sol";
import "./interfaces/IARCStackMining.sol";


contract StackMining is IARCStack, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    /**
     * @dev The address of the smart chef factory
     */
    address public SMART_CHEF_FACTORY;

    /**
     * @dev Whether a limit is set for users
     */
    bool public hasUserLimit;

    /**
     * @dev Whether it is initialized
     */
    bool public isInitialized;

    /**
     * @dev Accrued token per share
     */
    uint256 public accTokenPerShare;

    /**
     * @dev The block number when CAKE mining ends.
     */
    uint256 public bonusEndBlock;

    /**
     * @dev The block number when CAKE mining starts.
     */
    uint256 public startBlock;

    /**
     * @dev The block number of the last pool update
     */
    uint256 public lastRewardBlock;

    /**
     * @dev The pool limit (0 if none)
     */
    uint256 public poolLimitPerUser;

    /**
     * @dev CAKE tokens created per block.
     */
    uint256 public rewardPerBlock;

    /**
     * @dev The precision factor
     */
    uint256 public PRECISION_FACTOR;
 
    /**
     * @dev The reward token
     */
    IBEP20 public rewardToken;

    /**
     * @dev The staked token
     */
    IBEP20 public stakedToken;

    /**
     * @dev Info of each user that stakes tokens (stakedToken)
     */
    // mapping(address => UserInfo) public userInfos;

    struct UserInfo {
        uint256 amount; // How many staked tokens the user has provided
        uint256 rewardDebt; // Reward debt
        uint256 lockStartTime; // lock start time.
    }


    // Info of each pool.
    struct PoolInfo {
        uint256 duration;         // 期间
        uint256 boost;       // How many allocation points assigned to this pool. CAKEs to distribute per block.
        uint256 amount;  // Last block number that CAKEs distribution occurs.
        // uint256 accCakePerShare; // Accumulated CAKEs per share, times 1e12. See below.
    }

        // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;

    constructor() {
        SMART_CHEF_FACTORY = msg.sender;
    }

    /*
     * @notice Initialize the contract
     * @param _stakedToken: staked token address
     * @param _rewardToken: reward token address
     * @param _rewardPerBlock: reward per block (in rewardToken)
     * @param _startBlock: start block
     * @param _bonusEndBlock: end block
     * @param _poolLimitPerUser: pool limit per user in stakedToken (if any, else 0)
     * @param _admin: admin address with ownership
     */
    function initialize(
        IBEP20 _stakedToken,
        IBEP20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _poolLimitPerUser,
        address _admin
    ) external {
        require(!isInitialized, "BFLY: ALREADY_INIT");
        require(msg.sender == SMART_CHEF_FACTORY, "BFLY: NOT_FACTORY");

        // Make this contract initialized
        isInitialized = true;

        stakedToken = _stakedToken;
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;

        if (_poolLimitPerUser > 0) {
            hasUserLimit = true;
            poolLimitPerUser = _poolLimitPerUser;
        }

        uint256 decimalsRewardToken = uint256(rewardToken.decimals());
        require(decimalsRewardToken < 30, "BFLY: Must be inferior to 30");

        PRECISION_FACTOR = uint256(10**(uint256(30).sub(decimalsRewardToken)));

        // Set the lastRewardBlock as the startBlock
        lastRewardBlock = startBlock;

        // Transfer ownership to the admin address who becomes owner of the contract
        transferOwnership(_admin);
    }

    /*
     * @notice Deposit staked tokens and collect reward tokens (if any)
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function deposit(uint256 _pid,uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[_pid][msg.sender];
        PoolInfo storage pool = poolInfo[_pid];

        if (hasUserLimit) {
            require(_amount.add(user.amount) <= poolLimitPerUser, "BFLY: User amount above limit");
        }

        _updatePool();

        if (user.amount > 0) {

            if (user.lockStartTime.add(pool.duration) > block.timestamp){
                uint256 pending = user.amount.mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
                if (pending > 0) {
                    rewardToken.safeTransfer(address(msg.sender), pending);
                }
            }
            // 已经存在 则将累加用户amount 重置 lockStartTime

            user.lockStartTime = block.timestamp;
        }

        if (_amount > 0) {
            user.amount = user.amount.add(_amount);
            pool.amount = pool.amount.add(_amount);
            stakedToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        }

        user.rewardDebt = user.amount.mul(pool.boost).mul(accTokenPerShare).div(PRECISION_FACTOR);

        emit Deposit(msg.sender, _amount);
    }

    /*
     * @notice Withdraw staked tokens and collect reward tokens
     * @param _amount: amount to withdraw (in rewardToken)
     */
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "BFLY: Amount to withdraw too high");
        PoolInfo storage pool = poolInfo[_pid];

        // 没到解锁时间 只能取本金
        if (user.lockStartTime.add(pool.duration) < block.timestamp){
            emergencyWithdraw(_pid);
        }

        _updatePool();

        uint256 pending = user.amount.mul(pool.boost).mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.amount = pool.amount.sub(_amount);
            stakedToken.safeTransfer(address(msg.sender), _amount);
        }

        if (pending > 0) {
            rewardToken.safeTransfer(address(msg.sender), pending);
        }

        user.rewardDebt = user.amount.mul(pool.boost).mul(accTokenPerShare).div(PRECISION_FACTOR);

        emit Withdraw(msg.sender, _amount);
    }

    /*
     * @notice Withdraw staked tokens without caring about rewards rewards
     * @dev Needs to be for emergency.
     */
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amountToTransfer = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;

        if (amountToTransfer > 0) {
            stakedToken.safeTransfer(address(msg.sender), amountToTransfer);
        }

        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner. Needs to be for emergency.
     */
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(stakedToken), "Cannot be staked token");
        require(_tokenAddress != address(rewardToken), "Cannot be reward token");

        IBEP20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    /*
     * @notice Stop rewards
     * @dev Only callable by owner
     */
    function stopReward() external onlyOwner {
        bonusEndBlock = block.number;
    }

    /*
     * @notice Update pool limit per user
     * @dev Only callable by owner.
     * @param _hasUserLimit: whether the limit remains forced
     * @param _poolLimitPerUser: new pool limit per user
     */
    function updatePoolLimitPerUser(bool _hasUserLimit, uint256 _poolLimitPerUser) external onlyOwner {
        require(hasUserLimit, "Must be set");
        if (_hasUserLimit) {
            require(_poolLimitPerUser > poolLimitPerUser, "New limit must be higher");
            poolLimitPerUser = _poolLimitPerUser;
        } else {
            hasUserLimit = _hasUserLimit;
            poolLimitPerUser = 0;
        }
        emit NewPoolLimit(poolLimitPerUser);
    }

    /*
     * @notice Update reward per block
     * @dev Only callable by owner.
     * @param _rewardPerBlock: the reward per block
     */
    function updateRewardPerBlock(uint256 _rewardPerBlock) external onlyOwner {
        require(block.number < startBlock, "Pool has started");
        rewardPerBlock = _rewardPerBlock;
        emit NewRewardPerBlock(_rewardPerBlock);
    }

    /**
     * @notice It allows the admin to update start and end blocks
     * @dev This function is only callable by owner.
     * @param _startBlock: the new start block
     * @param _bonusEndBlock: the new end block
     */
    function updateStartAndEndBlocks(uint256 _startBlock, uint256 _bonusEndBlock) external onlyOwner {
        require(block.number < startBlock, "Pool has started");
        require(_startBlock < _bonusEndBlock, "New startBlock must be lower than new endBlock");
        require(block.number < _startBlock, "New startBlock must be higher than current block");

        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;

        // Set the lastRewardBlock as the startBlock
        lastRewardBlock = startBlock;

        emit NewStartAndEndBlocks(_startBlock, _bonusEndBlock);
    }

    /*
     * @notice View function to see pending reward on frontend.
     * @param _user: user address
     * @return Pending reward for a given user
     */
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        PoolInfo storage pool = poolInfo[_pid];
        uint256 totalShares = getTotalShares();
        if (block.number > lastRewardBlock && totalShares != 0) {
            uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
            uint256 cakeReward = multiplier.mul(rewardPerBlock);
            uint256 adjustedTokenPerShare =
                accTokenPerShare.add(cakeReward.mul(PRECISION_FACTOR).div(totalShares));
            return user.amount.mul(pool.boost).mul(adjustedTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
        } else {
            return user.amount.mul(pool.boost).mul(accTokenPerShare).div(PRECISION_FACTOR).sub(user.rewardDebt);
        }
    }

    function getTotalShares()public view returns(uint256 totalShares){

            for (uint256 pid = 0; pid < poolInfo.length; ++pid){
            totalShares = totalShares.add(poolInfo[pid].amount.mul(poolInfo[pid].boost));
        }
    }

    /*
     * @notice Update reward variables of the given pool to be up-to-date.
     */
    function _updatePool() internal {
        if (block.number <= lastRewardBlock) {
            return;
        }

        // uint256 stakedTokenSupply = stakedToken.balanceOf(address(this));
        uint256 totalShares = getTotalShares() ;
        // for (uint256 pid = 0; pid < length; ++pid) {
        
        // for (uint256 pid = 0; pid < poolInfo.length; ++pid){
        //     stakedTokenSupply = stakedTokenSupply.add(poolInfo[pid].amount.mul(poolInfo[pid].boost));
        // }

        if (totalShares == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 multiplier = _getMultiplier(lastRewardBlock, block.number);
        uint256 cakeReward = multiplier.mul(rewardPerBlock);
        accTokenPerShare = accTokenPerShare.add(cakeReward.mul(PRECISION_FACTOR).div(totalShares));
        lastRewardBlock = block.number;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /*
     * @notice Return reward multiplier over the given _from to _to block.
     * @param _from: block to start
     * @param _to: block to finish
     */
    function _getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from);
        }
    }
}