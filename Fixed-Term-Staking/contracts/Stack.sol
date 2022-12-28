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

    // uint256 public constant denominator = 12 * 60 * 24 * 365;

    // uint256 public constant day = 12 * 60 * 24;
    
    // string private constant _symbol = 'SquidGrow';

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
        uint256 offset; // Reward debt. See explanation below.
        uint256 lockStartTime;
    }

    struct AprInfo {
        uint256 apr;
        uint256 time;
    }


    struct PoolInfo{
        uint256 duration;
        AprInfo[] aprs;
    }

    PoolInfo[] poolInfos;

    mapping (uint256 => mapping (address => UserInfo)) public userInfo;

    /**
     * Info of each pool.
     */
    // struct PoolInfo {
    //     uint256 duration;           // Address of LP token contract.
    //     uint256 allocPoint;       // How many allocation points assigned to this pool. BFLYs to distribute per block.
    //     uint256 lastRewardBlock;  // Last block number that BFLYs distribution occurs.
    //     uint256 accARCPerShare; // Accumulated BFLYs per share, times 1e12. See below.
    //     uint256 amount;
        
    // }

    /**
     * The reward token!
     */
    IBEP20 public para;


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

    // constructor(
    //     IBEP20 _para,
    //     uint256 _arcPerBlock,
    //     uint256 _startBlock
    // ) {
    //     para = _para;
    //     arcPerBlock = _arcPerBlock;
    //     startBlock = _startBlock;

    //     // poolInfo.push(PoolInfo({
    //     //     duration: 1 weeks,
    //     //     allocPoint: 1000,
    //     //     lastRewardBlock: startBlock,
    //     //     accARCPerShare: 0,
    //     //     amount: 0

    //     // }));

    //     totalAllocPoint = 1000;
    // }


    function aadd()public pure returns(uint256){
        return 1 minutes;
    }

    function initialized()private {


        PoolInfo storage newPool = poolInfos[0];
        newPool.duration = 90 days;
        newPool.aprs.push(AprInfo({
            apr:100,
            time:block.timestamp
            }));

    }

    /**
     * @dev Update multiplier
     */
    // function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
    //     BONUS_MULTIPLIER = multiplierNumber;
    // }

    /**
     * @dev Number of the pools
     */
    function poolLength() external view returns (uint256) {
        return poolInfos.length;
    }

    /**
     * @dev Add a new lp to the pool. Can only be called by the owner.
     * XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
     */
    function add(uint256 _apr, uint256 _duration) external  onlyOwner {

        PoolInfo storage newPool = poolInfos[poolInfos.length];
        newPool.duration = _duration;
        newPool.aprs.push(AprInfo({
            apr:_apr,
            time:block.timestamp
            }));

    }

    /**
     * @dev Update the given pool's BFLY allocation point. Can only be called by the owner.
     */
    function set(uint256 _pid, uint256 _apr) public onlyOwner {
        PoolInfo storage pool = poolInfos[_pid];
        pool.aprs.push(AprInfo({
            apr:_apr,
            time:block.timestamp
            }));
    }


    /**
     * @dev Set migrator's address
     */
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }


    /**
     * @dev Return reward multiplier over the given _from to _to block.
     */
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    /**
     * @dev View function to see pending rewards on frontend.
     */
    function pendingReward(uint256 _pid, address _user) external view returns (uint256 reward) {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 len = pool.aprs.length;
        uint256 multiplier;
        bool flag;
        if (pool.aprs[len-1].time < user.lockStartTime){
            multiplier = getMultiplier(user.lockStartTime, block.number);
            reward = multiplier.mul(pool.aprs[len-1].apr).mul(user.amount);
            return reward;
        }

        for (uint i = user.offset;i< len-1;i++){

            if (!flag){
                multiplier = getMultiplier(user.lockStartTime, pool.aprs[i+1].time);
                reward = multiplier.mul(pool.aprs[i].apr).mul(user.amount);
                flag = true;
                continue ;
            }

            uint256 tempNumber = getMultiplier(pool.aprs[i].time, pool.aprs[i+1].time);

            reward =reward.add(tempNumber.mul(pool.aprs[i].apr).mul(user.amount));  
            multiplier = multiplier.add(tempNumber);
                      
        }

        multiplier = getMultiplier(pool.aprs[len-1].time, block.number);
        reward =reward.add(multiplier.mul(pool.aprs[len-1].apr).mul(user.amount));

        return reward;

    }


    function calculateReward(uint256 _pid, address _user) public view returns (uint256 reward) {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 len = pool.aprs.length;
        uint256 multiplier;
        bool flag;
        // 如果
        if (pool.aprs[len-1].time < user.lockStartTime){
            multiplier = pool.duration;
            reward = multiplier.mul(pool.aprs[len-1].apr).mul(user.amount);
            return reward;
        }
        for (uint i = user.offset;i< len-1;i++){

            if (!flag){
                multiplier = getMultiplier(user.lockStartTime, pool.aprs[i+1].time);
                if (multiplier > pool.duration){
                    reward = pool.duration.mul(pool.aprs[i].apr).mul(user.amount);
                    return reward;
                    }
                reward = multiplier.mul(pool.aprs[i].apr).mul(user.amount);
                flag = true;
                continue ;
            }

            uint256 tempNumber = getMultiplier(pool.aprs[i].time, pool.aprs[i+1].time);

            if (tempNumber.add(multiplier) > pool.duration){
                reward = reward.add(pool.duration.sub(multiplier).mul(pool.aprs[i].apr).mul(user.amount));
                return reward;
                }    
                //      100          200           400   450 
                //             150 
            
            reward =reward.add(tempNumber.mul(pool.aprs[i].apr).mul(user.amount));  
            multiplier = multiplier.add(tempNumber);          
        }

            reward = reward.add(pool.duration.sub(multiplier).mul(pool.aprs[len-1].apr).mul(user.amount));
            return reward;          
        
    }

    /**
     * @dev Deposit LP tokens to LPMining for bfly allocation.
     */
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];


        if (user.amount > 0){
            
            if(user.lockStartTime.add(pool.duration)> block.timestamp){
                // 质押到期，返还利息
                uint256 pending = calculateReward(_pid,msg.sender);
                if(pending > 0) {
                    IBEP20(para).safeTransfer(msg.sender, pending);
                }

                // 追加本金 、更新质押开始时间 
                IBEP20(para).safeTransferFrom(address(msg.sender), address(this), _amount);
                user.amount = user.amount.add(_amount);
            
                user.lockStartTime = block.timestamp;
                user.offset = pool.aprs.length - 1;

                emit Deposit(msg.sender, _pid, _amount);
                return;

            }else{

                // 追加本金 、更新质押开始时间 
                IBEP20(para).safeTransferFrom(address(msg.sender), address(this), _amount);
                user.amount = user.amount.add(_amount);
            
                user.lockStartTime = block.timestamp;
                user.offset = pool.aprs.length - 1;

                emit Deposit(msg.sender, _pid, _amount);
                return;
            }       
        }else {
            // 第一次质押
            // 记录用户 本金和质押时间
            user.lockStartTime = block.timestamp;
            user.offset = pool.aprs.length - 1; 
            user.amount = _amount; 
            IBEP20(para).safeTransferFrom(address(msg.sender), address(this), _amount);
            emit Deposit(msg.sender, _pid, _amount);
            return ; 
        }
        
    }

    /**
     * @dev Withdraw LP tokens from MasterChef.
     */
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "BFLY: SUFFICIENT_BALANCE");

        if(user.lockStartTime.add(pool.duration)> block.timestamp){

            // 返还利息
            uint256 pending = calculateReward(_pid,msg.sender);
                if(pending > 0) {
                    IBEP20(para).safeTransfer(msg.sender, pending);
                }
            
        }
            
            IBEP20(para).safeTransfer(msg.sender, user.amount);
            // 将用户质押信息归零
            user.amount = 0; 
            return;
        
    }

    /**
     * @dev Withdraw without caring about rewards. EMERGENCY ONLY.
     */
    // function emergencyWithdraw(uint256 _pid) public {
    //     PoolInfo storage pool = poolInfo[_pid];
    //     UserInfo storage user = userInfo[_pid][msg.sender];
    //     arc.safeTransfer(address(msg.sender), user.amount);
    //     emit EmergencyWithdraw(msg.sender, _pid, user.amount);
    //     user.amount = 0;
    // }

    /**
     * @dev Update dev address by the previous dev.
     */
    // function setDev(address _devaddr) public {
    //     require(msg.sender == devaddr, "BFLY: NO_PERMISSION");
    //     devaddr = _devaddr;
    // }

    /**
     * @dev Update arcPerBlock by the owner.
     */
    function setARCPerBlock(uint256 arcPerBlock_) public onlyOwner {
        arcPerBlock = arcPerBlock_;
    }
}