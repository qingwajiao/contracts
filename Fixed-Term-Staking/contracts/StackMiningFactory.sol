// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IBEP20.sol";
import "./interfaces/IARCStackFactory.sol";
import "./StackMining.sol";

contract StackMiningFactory is Ownable, IARCStackFactory {

    /**
     * @dev All pools
     */
    mapping(address => bool) public pools;
    
    constructor() {
        //do nothing
    }

    /**
     * @dev Add new pool to factory
     *
     * @param _stakedToken: staked token address
     * @param _rewardToken: reward token address
     * @param _rewardPerBlock: reward per block (in rewardToken)
     * @param _startBlock: start block
     * @param _bonusEndBlock: end block
     * @param _poolLimitPerUser: pool limit per user in stakedToken (if any, else 0)
     * @param _admin: admin address with ownership
     *
     * Emits an {NewPool} event indicating create new stacking pool
     */
    function newPool(
        IBEP20 _stakedToken,
        IBEP20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        uint256 _poolLimitPerUser,
        address _admin
    ) external onlyOwner {
        require(_stakedToken.totalSupply() >= 0);
        require(_rewardToken.totalSupply() >= 0);
        require(_stakedToken != _rewardToken, "Tokens must be different");

        bytes memory bytecode = type(StackMining).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_stakedToken, _rewardToken, _startBlock));
        address smartChefAddress;

        assembly {
            smartChefAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        StackMining(smartChefAddress).initialize(
            _stakedToken,
            _rewardToken,
            _rewardPerBlock,
            _startBlock,
            _bonusEndBlock,
            _poolLimitPerUser,
            _admin
        );

        addPool(smartChefAddress);

        emit NewPool(smartChefAddress);
    }

    function addPool(address _address) internal {
        require(_address != address(0), "BFLY: INVALID_ADDR");
        if (!pools[_address]) {
            pools[_address] = true;
        }

        emit AddPool(_address);
    }

    /**
     * @dev Remove pool from factory
     *
     * Emits an {RemovePool} event indicating remove contract from address list
     */
    function removePool(address _address) public onlyOwner {
        require(pools[_address], "BFLY: POOL_NOT_EXISTS");
        delete pools[_address];

        emit RemovePool(_address);
    }
}