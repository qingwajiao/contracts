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
        uint256 number; // Reward debt. See explanation below.
        uint256 lockStartTime;
    }

    struct ArpInfo {
        uint256 arp;
        uint256 time;
    }


    struct PoolInfo{
        uint256 duration;
        ArpInfo[] arps;
    }

    PoolInfo[] poolInfo;

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
    // PoolInfo[] public poolInfo;

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

        // poolInfo.push(PoolInfo({
        //     duration: 1 weeks,
        //     allocPoint: 1000,
        //     lastRewardBlock: startBlock,
        //     accARCPerShare: 0,
        //     amount: 0

        // }));

        totalAllocPoint = 1000;
    }

    function initialized()private {


        PoolInfo storage newPool = poolInfo[0];
        newPool.duration = 12 weeks;
        newPool.arps.push(ArpInfo({
            arp:100,
            time:block.timestamp
            }));
        // ArpInfo[] memory temp = new ArpInfo[](1);
        // temp[0] =  ArpInfo({
        //     arp:100,
        //     time:block.timestamp
        // });
        // PoolInfo memory p1 = PoolInfo({
        //     duration: 1 weeks,
        //     arps:temp
        // });

        // poolInfo.push(p1);
       

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
    function add(uint256 _arp, uint256 _duration) external  onlyOwner {

        PoolInfo storage newPool = poolInfo[poolInfo.length];
        newPool.duration = _duration;
        newPool.arps.push(ArpInfo({
            arp:_arp,
            time:block.timestamp
            }));

        // ArpInfo[] memory temp = new ArpInfo[](1);
        // temp[0] =  ArpInfo({
        //     arp:_arp,
        //     time:block.timestamp
        //     });
        // PoolInfo memory newPool = PoolInfo({
        //     duration: _duration,
        //     arps:temp
        //     });

        // poolInfo.push(newPool);
    }

    /**
     * @dev Update the given pool's BFLY allocation point. Can only be called by the owner.
     */
    function set(uint256 _pid, uint256 _arp) public onlyOwner {
        PoolInfo storage pool = poolInfo[_pid];
        pool.arps.push(ArpInfo({
            arp:_arp,
            time:block.timestamp
            }));
    }

    /**
     * @dev Set the migrator contract. Can only be called by the owner.
     */
    // function updateStakingPool() internal {
    //     uint256 length = poolInfo.length;
    //     uint256 points = 0;
    //     for (uint256 pid = 1; pid < length; ++pid) {
    //         points = points.add(poolInfo[pid].allocPoint);
    //     }
    //     if (points != 0) {
    //         points = points.div(3);
    //         totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
    //         poolInfo[0].allocPoint = points;
    //     }
    // }

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
    // function migrate(uint256 _pid) public {
    //     require(address(migrator) != address(0), "BFLY: NO_MIGRATOR");
    //     PoolInfo storage pool = poolInfo[_pid];
    //     IBEP20 lpToken = pool.lpToken;
    //     uint256 bal = lpToken.balanceOf(address(this));
    //     lpToken.safeApprove(address(migrator), bal);
    //     IBEP20 newLpToken = migrator.migrate(lpToken);
    //     require(bal == newLpToken.balanceOf(address(this)), "BFLY: BAD");
    //     pool.lpToken = newLpToken;
    // }

    /**
     * @dev Return reward multiplier over the given _from to _to block.
     */
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    /**
     * @dev View function to see pending rewards on frontend.
     */
    function pendingReward(uint256 _pid, address _user) external view returns (uint256 reward) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 len = pool.arps.length;
        uint256 multiplier;
        if (pool.arps[len-1].time < user.lockStartTime){
            multiplier = getMultiplier(user.lockStartTime, block.number);
            reward = multiplier.mul(pool.arps[0].arp).mul(user.amount);
            return reward;
        }

        for (uint i = len-1;i>0;i--){
            multiplier = getMultiplier(pool.arps[i].time, block.number);
            reward =reward.add(multiplier.mul(pool.arps[i].arp).mul(user.amount));   
            
            if (pool.arps[i-1].time < user.lockStartTime) {
                multiplier = getMultiplier(pool.arps[i].time, pool.arps[i-1].time);
                reward =reward.add(multiplier.mul(pool.arps[i-1].arp).mul(user.amount));
                continue ;
            }

        
            multiplier = getMultiplier(user.lockStartTime, pool.arps[i-1].time);
            reward = reward.add(multiplier.mul(pool.arps[i-1].arp).mul(user.amount));

            return reward;
        }
        //. 10-15.  20-12.     30-11.    40-10.    50（现在）
        //                            25
        //.                5*12 + 10*11 + 10*10

    }

    /**
     * @dev Update reward variables for all pools. Be careful of gas spending!
     */
    // function massUpdatePools() public {
    //     uint256 length = poolInfo.length;
    //     for (uint256 pid = 0; pid < length; ++pid) {
    //         updatePool(pid);
    //     }
    // }

    // function updatePool(uint256 _pid) public {
    //     PoolInfo2 storage pool = poolInfo2[_pid];

    //     pool.arps.arp
    // }
 
    /**
     * @dev Update reward variables of the given pool to be up-to-date.
     */
    // function updatePool(uint256 _pid) public {
    //     PoolInfo storage pool = poolInfo[_pid];
    //     if (block.number <= pool.lastRewardBlock) {
    //         return;
    //     }
    //     uint256 lpSupply = pool.amount;
    //     if (lpSupply == 0) {
    //         pool.lastRewardBlock = block.number;
    //         return;
    //     }
    //     uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
    //     uint256 reward = multiplier.mul(arcPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
    //     // arc.safeTransfer(devaddr, reward.div(5));    // dev reward
    //     // arc.safeTransfer(address(this), reward);     // TODO: have no syrup! 
    //     pool.accARCPerShare = pool.accARCPerShare.add(reward.mul(1e12).div(lpSupply));
    //     pool.lastRewardBlock = block.number;
    // }

    function calculateReward(uint256 _pid, address _user) public view returns (uint256 reward) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 len = pool.arps.length;
        uint256 multiplier;
        bool flag;
        // 如果
        if (pool.arps[len-1].time < user.lockStartTime){
            multiplier = pool.duration;
            reward = multiplier.mul(pool.arps[len-1].arp).mul(user.amount);
            return reward;
        }

        for (uint i = user.number;i< len-1;i++){

            // multiplier = getMultiplier(pool.arps[i].time, user.lockStartTime);
            // if (multiplier > pool.duration){
            //     reward = pool.duration.mul(pool.arps[i].arp).mul(user.amount);
            //     return reward;
            // }

            if (!flag){
                multiplier = getMultiplier(pool.arps[i].time, user.lockStartTime);
                if (multiplier > pool.duration){
                    reward = pool.duration.mul(pool.arps[i].arp).mul(user.amount);
                    return reward;
                    }
                reward = multiplier.mul(pool.arps[i].arp).mul(user.amount);
                flag = true;
                continue ;
            }

            uint256 tempNumber = multiplier.add(getMultiplier(pool.arps[i].time, pool.arps[i+1].time));

            if (tempNumber > pool.duration){
                reward = reward.add(pool.duration.sub(tempNumber).mul(pool.arps[i].arp).mul(user.amount));
                return reward;
                }
            
            multiplier = tempNumber;
            // reward = multiplier.mul(pool.arps[i].arp).mul(user.amount);
            reward =reward.add(multiplier.mul(pool.arps[i].arp).mul(user.amount));   
            
        }

    }

    /**
     * @dev Deposit LP tokens to LPMining for bfly allocation.
     */
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];


        if (user.amount > 0){
            
            if(user.lockStartTime.add(pool.duration)> block.timestamp){
                // 质押到期，返还利息
                uint256 pending = calculateReward(_pid,msg.sender);
                if(pending > 0) {
                    IBEP20(arc).safeTransfer(msg.sender, pending);
                }

                // 追加本金 、更新质押开始时间 
                IBEP20(arc).safeTransferFrom(address(msg.sender), address(this), _amount);
                user.amount = user.amount.add(_amount);
            
                user.lockStartTime = block.timestamp;
                user.number = pool.arps.length - 1;

                emit Deposit(msg.sender, _pid, _amount);
                return;

            }else{

                // 追加本金 、更新质押开始时间 
                IBEP20(arc).safeTransferFrom(address(msg.sender), address(this), _amount);
                user.amount = user.amount.add(_amount);
            
                user.lockStartTime = block.timestamp;
                user.number = pool.arps.length - 1;

                emit Deposit(msg.sender, _pid, _amount);
                return;
            }       
        }else {
            // 第一次质押
            // 记录用户 本金和质押时间
            user.lockStartTime = block.timestamp;
            user.number = pool.arps.length - 1; 
            user.amount = _amount; 
            IBEP20(arc).safeTransferFrom(address(msg.sender), address(this), _amount);
            emit Deposit(msg.sender, _pid, _amount);
            return ; 
        }
        
    }

    /**
     * @dev Withdraw LP tokens from MasterChef.
     */
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "BFLY: SUFFICIENT_BALANCE");

        if(user.lockStartTime.add(pool.duration)> block.timestamp){

            // 返还利息
            uint256 pending = calculateReward(_pid,msg.sender);
                if(pending > 0) {
                    IBEP20(arc).safeTransfer(msg.sender, pending);
                }
            
        }
            
            IBEP20(arc).safeTransfer(msg.sender, user.amount);
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