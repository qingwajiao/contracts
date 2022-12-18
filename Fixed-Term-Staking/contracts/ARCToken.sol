// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./BEP20.sol";

contract ARCToken is BEP20 {

    /**
     * Extends uint256 by SafeMath
     */
    using SafeMath for uint256;


    constructor(string memory name_, string memory symbol_, uint256 totalSupply_) BEP20(name_, symbol_) {
        _mint(msg.sender, totalSupply_ * 10**18);
    }

    /**
     * @dev Burn `_amount` token from `_from`. 
     * 
     * NOTE:
     * Must only be called by the owner (MasterChef).
     */
    function burn(address _from ,uint256 _amount) public onlyOwner {
        _burn(_from, _amount);
    }
}