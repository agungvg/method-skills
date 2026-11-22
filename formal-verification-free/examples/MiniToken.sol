// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice PASS case (stateful): transfer preserves the sum of the two
/// balances involved. CHC proves it for ALL inputs, not just tested ones.
contract MiniToken {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount);
        uint256 before = balanceOf[msg.sender] + balanceOf[to];
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        if (msg.sender != to) {
            assert(balanceOf[msg.sender] + balanceOf[to] == before);
        }
    }
}
