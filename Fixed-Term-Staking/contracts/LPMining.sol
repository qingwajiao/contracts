// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


import "./interfaces/IBEP20.sol";
import "./interfaces/IMigratorChef.sol";
import "./libraries/SafeBEP20.sol";


contract LPMining is Ownable {

    /**
     * Extends uint256 by SafeMath
     */
    using SafeMath for uint256;

    /**
     * Extends safe operation by SafeBEP20
     */
    using SafeBEP20 for IBEP20;

    /**
     * Info of each user.
     *
     *
     * We do some fancy math here. Basically, any point in time, the amount of BFLYs
     * entitled to a user but is pending to be distributed is:
     *
     *   pending reward = (user.amount * pool.accBflyPerShare) - user.rewardDebt
     *
     * Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
     *   1. The pool's `accBflyPerShare` (and `lastRewardBlock`) gets updated.
     *   2. User receives the pending reward sent to his/her address.
     *   3. User's `amount` gets updated.
     *   4. User's `rewardDebt` gets updated.
     */
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    /**
     * Info of each pool.
     */
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. BFLYs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that BFLYs distribution occurs.
        uint256 accARCPerShare; // Accumulated BFLYs per share, times 1e12. See below.
    }

    /**
     * The reward token!
     */
    IBEP20 public arc;

    /**
     * Dev address.
     */
    address public devaddr;

    /**
     * ARC tokens per block.
     */
    uint256 public arcPerBlock;

    /**
     * Bonus muliplier for early ARC makers.
     */
    uint256 public BONUS_MULTIPLIER = 1;

    /**
     * The migrator contract. It has a lot of power. Can only be set through governance (owner).
     */
    IMigratorChef public migrator;

    /**
     * Info of each pool.
     */
    PoolInfo[] public poolInfo;

    /**
     * Info of each user that stakes LP tokens.
     */
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;

    /**
     * Total allocation poitns. Must be the sum of all allocation points in all pools.
     */
    uint256 public totalAllocPoint = 0;

    /**
     * The block number when mining starts.
     */
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        IBEP20 _arc,
        address _devaddr,
        uint256 _arcPerBlock,
        uint256 _startBlock
    ) {
        arc = _arc;
        devaddr = _devaddr;
        arcPerBlock = _arcPerBlock;
        startBlock = _startBlock;

        poolInfo.push(PoolInfo({
            lpToken: arc,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accARCPerShare: 0
        }));

        totalAllocPoint = 1000;
    }

    /**
     * @dev Update multiplier
     */
    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    /**
     * @dev Number of the pools
     */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @dev Add a new lp to the pool. Can only be called by the owner.
     * XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
     */
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accARCPerShare: 0
        }));
        updateStakingPool();
    }

    /**
     * @dev Update the given pool's BFLY allocation point. Can only be called by the owner.
     */
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            updateStakingPool();
        }
    }

    /**
     * @dev Set the migrator contract. Can only be called by the owner.
     */
    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    /**
     * @dev Set migrator's address
     */
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    /**
     * @dev Migrate lp token to another lp contract. Can be called by anyone. 
     * We trust that migrator contract is good.
     */
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "BFLY: NO_MIGRATOR");
        PoolInfo storage pool = poolInfo[_pid];
        IBEP20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IBEP20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "BFLY: BAD");
        pool.lpToken = newLpToken;
    }

    /**
     * @dev Return reward multiplier over the given _from to _to block.
     */
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    /**
     * @dev View function to see pending rewards on frontend.
     */
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accARCPerShare = pool.accARCPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 reward = multiplier.mul(arcPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accARCPerShare = accARCPerShare.add(reward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accARCPerShare).div(1e12).sub(user.rewardDebt);
    }

    /**
     * @dev Update reward variables for all pools. Be careful of gas spending!
     */
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }
 
    /**
     * @dev Update reward variables of the given pool to be up-to-date.
     */
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 reward = multiplier.mul(arcPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        arc.safeTransfer(devaddr, reward.div(5));    // dev reward
        // arc.safeTransfer(address(this), reward);     // TODO: have no syrup! 
        pool.accARCPerShare = pool.accARCPerShare.add(reward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    /**
     * @dev Deposit LP tokens to LPMining for bfly allocation.
     */
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accARCPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                IBEP20(arc).safeTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accARCPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    /**
     * @dev Withdraw LP tokens from MasterChef.
     */
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "BFLY: SUFFICIENT_BALANCE");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accARCPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            arc.safeTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accARCPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    /**
     * @dev Withdraw without caring about rewards. EMERGENCY ONLY.
     */
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    /**
     * @dev Update dev address by the previous dev.
     */
    function setDev(address _devaddr) public {
        require(msg.sender == devaddr, "BFLY: NO_PERMISSION");
        devaddr = _devaddr;
    }

    /**
     * @dev Update arcPerBlock by the owner.
     */
    function setARCPerBlock(uint256 arcPerBlock_) public onlyOwner {
        arcPerBlock = arcPerBlock_;
    }
}