// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


import "./interfaces/IBEP20.sol";
import "./libraries/SafeBEP20.sol";


contract FixedTermStack is Ownable {

    /**
     * Extends uint256 by SafeMath
     */
    using SafeMath for uint256;

    /**
     * Extends safe operation by SafeBEP20
     */
    using SafeBEP20 for IBEP20;

    uint256 public constant DENOMINATOR = 365 days;  

    uint256 public constant BASE = 100;

    uint256 public constant DENOMINATOR_TEST = 5 minutes;

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
        uint256 lockStartTime;
        uint256 offset; 
    }

    struct AprInfo {
        uint256 apr;
        uint256 time;
    }


    struct PoolInfo{
        uint256 id;
        uint256 amount;
        uint256 duration;
        AprInfo[] aprs;
    }

    PoolInfo[] poolInfos;

    mapping (uint256 => mapping (address => UserInfo)) public userInfo;


    /**
     * The reward token!
     */
    IBEP20 public para;



    /**
     * The block number when mining starts.
     */
    // uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event AddPool(uint256 indexed pid,uint256 indexed apr, uint256 indexed duration);
    event SetApr(uint256 indexed pid,uint256 indexed apr);

    constructor(
        IBEP20 _para

    ) {
        para = _para;

        initialized();
    }


    function initialized()private {

        uint _id = poolInfos.length;
        PoolInfo storage p = poolInfos.push();

        p.aprs.push(AprInfo(20, block.timestamp));
        p.duration = 5 * 1 minutes;
        p.id = _id;
        p.amount = 0;

        // poolInfos.push(PoolInfo(180 days, poolInfos[id].aprs));

        // PoolInfo storage pool1 = poolInfos[1];
        // pool1.duration = 180 days;
        // pool1.aprs.push(AprInfo({
        //     apr:20,
        //     time:block.timestamp
        //     }));  

        // PoolInfo storage pool2 = poolInfos[2];
        // pool2.duration = 360 days;
        // pool2.aprs.push(AprInfo({
        //     apr:30,
        //     time: block.timestamp
        //     })); 

    }           

    /**
     * @dev Number of the pools
     */
    function poolLength() external view returns (uint256) {
        return poolInfos.length;
    }

    function getPoolInfo(uint256 _pid) external view returns (PoolInfo memory info){
        return poolInfos[_pid];
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
            multiplier = getMultiplier(user.lockStartTime,block.timestamp);
            reward = multiplier.mul(pool.aprs[len-1].apr).mul(user.amount);
            reward = reward.div(DENOMINATOR_TEST).div(100);
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
        reward = reward.div(DENOMINATOR_TEST).div(100);

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
            reward = reward.div(DENOMINATOR_TEST).div(100);
            return reward;
        }
        for (uint i = user.offset;i< len-1;i++){

            if (!flag){
                multiplier = getMultiplier(user.lockStartTime, pool.aprs[i+1].time);
                if (multiplier > pool.duration){
                    reward = pool.duration.mul(pool.aprs[i].apr).mul(user.amount);
                    reward = reward.div(DENOMINATOR_TEST).div(100);
                    return reward;
                    }
                reward = multiplier.mul(pool.aprs[i].apr).mul(user.amount);
                flag = true;
                continue ;
            }

            uint256 tempNumber = getMultiplier(pool.aprs[i].time, pool.aprs[i+1].time);

            if (tempNumber.add(multiplier) > pool.duration){
                reward = reward.add(pool.duration.sub(multiplier).mul(pool.aprs[i].apr).mul(user.amount));
                reward = reward.div(DENOMINATOR_TEST).div(100);
                return reward;
                }    
                //      100          200           400   450 
                //             150 
            
            reward =reward.add(tempNumber.mul(pool.aprs[i].apr).mul(user.amount));  
            multiplier = multiplier.add(tempNumber);          
        }

            reward = reward.add(pool.duration.sub(multiplier).mul(pool.aprs[len-1].apr).mul(user.amount));
            reward = reward.div(DENOMINATOR_TEST).div(100);
            return reward;          
        
    }

    /**
     * @dev Deposit LP tokens to LPMining for bfly allocation.
     */
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(_amount > 0,"FixedTermStack: Below minimum");

        if (user.amount > 0){
            
            if(user.lockStartTime.add(pool.duration)> block.timestamp){
                // 质押到期，返还利息
                uint256 pending = calculateReward(_pid,msg.sender);
                if(pending > 0) {
                    IBEP20(para).safeTransfer(msg.sender, pending);
                }

            }                 
        }

                        // 追加本金 、更新质押开始时间 
            
        user.amount = user.amount.add(_amount);
        user.lockStartTime = block.timestamp;
        user.offset = pool.aprs.length - 1;
        pool.amount = pool.amount.add(_amount);

        IBEP20(para).safeTransferFrom(address(msg.sender), address(this), _amount);
        emit Deposit(msg.sender, _pid, _amount);
        
    }

    /**
     * @dev Withdraw LP tokens from MasterChef.
     */
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "FixedTermStack: SUFFICIENT_BALANCE");

        if(user.lockStartTime.add(pool.duration)> block.timestamp){

            // 返还利息
            uint256 pending = calculateReward(_pid,msg.sender);
                if(pending > 0) {
                    IBEP20(para).safeTransfer(msg.sender, pending);
                }
            
        }

        user.amount = user.amount.sub(_amount);
        user.lockStartTime = block.timestamp;
        user.offset = pool.aprs.length - 1;
        pool.amount = pool.amount.sub(_amount);
            
        IBEP20(para).safeTransfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _pid, _amount);
        
    }


    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(para), "Cannot be staked token");

        IBEP20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);

    }


    function addPool(uint256 _apr, uint256 _duration) external  onlyOwner {

        uint _id = poolInfos.length;
        PoolInfo storage p = poolInfos.push();

        p.aprs.push(AprInfo(_apr, block.timestamp));
        p.duration = _duration * 1 minutes;
        p.id = _id;
        p.amount = 0;

        emit AddPool(_id,_apr,_duration);

    }

    /**
     * @dev Update the given pool's BFLY allocation point. Can only be called by the owner.
     */
    function setApr(uint256 _pid, uint256 _apr) public onlyOwner {
        PoolInfo storage pool = poolInfos[_pid];
        pool.aprs.push(AprInfo({
            apr:_apr,
            time:block.timestamp
            }));

        emit SetApr(_pid,_apr);
    }


}