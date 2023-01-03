# 合约测试地址
## bsc测试链：
    * PDT ：0x1309A5A2b8358245A6E9bcee9A512c7AF3cb5cbd
    * FIXEDTERMSTACK ：0x97916ab3f255957606d29295646c190c53b31E64

## Goerli测试链：
    * PDT ：0x18067430177D515d29223C91381d88F1709517e4
    * FIXEDTERMSTACK ：0x64810BDc4851cbe9eaF084779765e213ac7A4eBE

# FixedTermStack 合约主要接口

## 用户质押
* 方法名：deposit(uint256 _pid, uint256 _amount)  
* 参数：
    1. _pid：池子id 
    2. _amount：质押数量
   
  
* 返回值



----------

## 用户提现
* withdraw(uint256 _pid)
* 参数：
    1. _pid：池子id 
   
* 返回值



----------

## 查看用户奖励
* pendingReward(uint256 _pid, address _user)
* 参数：
    1. _pid：池子id 
    2. _user：用户地址
   
* 返回值
   1. reward：用户奖励 

----------

## 查看用户信息

* userInfo(uint256 _pid, address _user) 
* 参数：
    1. _pid：池子id 
    2. _user：用户地址
   
* 返回值
    1. amount：用户本金 
    2. lockStartTime：用户开始质押时的时间戳
    3. offset  这个不用管

----------

## 查看池子信息
* getPoolInfo(uint256 _pid) 
* 参数：
    1. _pid：池子id 
   
* 返回值
    1. id：池中id
    2. amount：质押在该池子的总本金 
    3. duration：期限
    4. aprs  现在年化率

----------

## 查看所有池的总本金
* allAmount() 
* 参数：
   
* 返回值
    1. allAmount：所有池的总本金

----------

## owner添加新池子
* addPool(uint256 _apr, uint256 _duration)
* 参数：
    1. _apr：年化率 （0-1000之间的整数）
    2. _duration：期限（以天为单位的整数如：90、180、360...）
   
* 返回值

----------

## owner修改池子的年化率

* setApr(uint256 _pid, uint256 _apr)
* 参数：
    1. _pid：池子id 
    2. _apr：年化率 （0-100之间的整数）
   
* 返回值

![avatar](/计算多期年化率示意图.png)
