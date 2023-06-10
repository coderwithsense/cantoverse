// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface csrCANTO {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function withdrawClaimed() external;
}

contract wallet {
    csrCANTO private token;
    address public owner; 
    address private tokenAddress;

    constructor(address _tokenAddress) {
        owner = msg.sender;
        tokenAddress = _tokenAddress;
        token = csrCANTO(_tokenAddress);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    function getTokenBalance() public view returns (uint256){
        return token.balanceOf(address(this));
    }

    function changeOwner(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Invalid new owner address");
        owner = newOwner;
    }

    function withdraw(uint256 amount) public{
        require(msg.sender == owner, "Only owner can withdraw");
        require(token.balanceOf(address(this)) >= amount, "Not sufficient balance");
        token.transfer(owner, amount);
    }

    function withdrawClaimed() public {
        token.withdrawClaimed();
    }
}
