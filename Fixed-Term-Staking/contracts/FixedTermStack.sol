// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


import "./interfaces/IBEP20.sol";
import "./libraries/SafeBEP20.sol";


contract FixedTermStack is Ownable, ReentrancyGuard {

    /**
     * Extends uint256 by SafeMath
     */
    // using SafeMath for uint256;

    using SafeBEP20 for IBEP20;

    uint256 public constant DENOMINATOR = 365 days;  

    uint256 public constant BASE = 1000;

    uint256 public constant DENOMINATOR_TEST = 10 minutes;

    struct UserInfo {
        uint256 lockStartTime;
        uint256 offset; 
        uint256 amount;
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

    uint256 public allAmount;

    /**
     * The reward token!
     */
    IBEP20 public para;

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

    }           

    /**
     * @dev Number of the pools
     */
    function poolLength() external view returns (uint256) {
        return poolInfos.length;
    }

    function getPoolInfo(uint256 _pid) external view returns (uint256 ,uint256, uint256, uint256 ){
        PoolInfo storage p = poolInfos[_pid];
        return (p.id, p.amount, p.duration, p.aprs[p.aprs.length - 1].apr);
    }

    /**
     * @dev Return reward multiplier over the given _from to _to block.
     */
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to - _from;
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
            reward = multiplier * pool.aprs[len-1].apr * user.amount / DENOMINATOR_TEST / BASE;
            return reward;
        }

        for (uint i = user.offset;i< len-1;i++){

            if (!flag){
                multiplier = getMultiplier(user.lockStartTime, pool.aprs[i+1].time);
                reward = multiplier * pool.aprs[i].apr * user.amount;
                flag = true;
                continue ;
            }

            uint256 tempNumber = getMultiplier(pool.aprs[i].time, pool.aprs[i+1].time);

            reward += tempNumber * pool.aprs[i].apr * user.amount;  
            multiplier += tempNumber;
                      
        }

        multiplier = getMultiplier(pool.aprs[len-1].time, block.number);
        reward += multiplier * pool.aprs[len-1].apr * user.amount;
        reward = reward / DENOMINATOR_TEST / BASE;

        return reward;

    }


    function calculateReward(uint256 _pid, address _user) public view returns (uint256 reward) {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 len = pool.aprs.length;
        uint256 multiplier;
        bool flag;
        uint256 termOfValidity = ((block.timestamp - user.lockStartTime) % pool.duration) * pool.duration ;
        
        // 如果
        if (pool.aprs[len-1].time < user.lockStartTime){
            reward = termOfValidity * pool.aprs[len-1].apr * user.amount;
            reward = reward / DENOMINATOR_TEST / BASE;
            return reward;
        }
        for (uint i = user.offset;i< len-1;i++){

            if (!flag){
                multiplier = getMultiplier(user.lockStartTime, pool.aprs[i+1].time);
                if (multiplier > termOfValidity){
                    reward = termOfValidity * pool.aprs[i].apr * user.amount;
                    reward = reward / DENOMINATOR_TEST / BASE;
                    return reward;
                    }
                reward = multiplier * pool.aprs[i].apr * user.amount;
                flag = true;
                continue ;
            }

            uint256 tempNumber = getMultiplier(pool.aprs[i].time, pool.aprs[i+1].time);

            if (tempNumber + multiplier > termOfValidity){
                reward += (termOfValidity - multiplier) * pool.aprs[i].apr * user.amount;
                reward = reward / DENOMINATOR_TEST / BASE;
                return reward;
                }    
            
            reward += tempNumber * pool.aprs[i].apr * user.amount;  
            multiplier += tempNumber;          
        }

            reward += (termOfValidity - multiplier) * pool.aprs[len-1].apr * user.amount / DENOMINATOR_TEST / BASE;
            return reward;          
        
    }

    /**
     * @dev Deposit LP tokens to LPMining for bfly allocation.
     */
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(_amount > 0,"FixedTermStack: Below minimum");

        if (user.amount > 0){
            
            if(user.lockStartTime + pool.duration < block.timestamp){
                // 质押到期，返还利息
                uint256 pending = calculateReward(_pid,msg.sender);
                if(pending > 0) {
                    IBEP20(para).safeTransfer(msg.sender, pending);
                }

            }                 
        }

                        // 追加本金 、更新质押开始时间 
            
        user.amount += _amount;
        user.lockStartTime = block.timestamp;
        user.offset = pool.aprs.length - 1;
        pool.amount += _amount;
        allAmount += _amount;


        IBEP20(para).safeTransferFrom(address(msg.sender), address(this), _amount);
        emit Deposit(msg.sender, _pid, _amount);
        
    }

    /**
     * @dev Withdraw LP tokens from MasterChef.
     */
    function withdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfos[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= 0, "FixedTermStack: SUFFICIENT_BALANCE");

        if(user.lockStartTime + pool.duration < block.timestamp){

            // 返还利息
            uint256 pending = calculateReward(_pid,msg.sender);
                if(pending > 0) {
                    IBEP20(para).safeTransfer(msg.sender, pending);
                }
            
        }

        user.amount = 0;
        user.lockStartTime = 0;
        user.offset = 0;
        pool.amount -= user.amount;
        allAmount -= user.amount;
            
        IBEP20(para).safeTransfer(msg.sender, user.amount);

        emit Withdraw(msg.sender, _pid, user.amount);
        
    }


    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount)external onlyOwner {
        require(_tokenAddress != address(para), "Cannot be staked token");

        IBEP20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);

    }

    function refundReward()external onlyOwner {
        uint256 balances = para.balanceOf(address(this));
        IBEP20(para).safeTransfer(msg.sender, balances - allAmount);
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