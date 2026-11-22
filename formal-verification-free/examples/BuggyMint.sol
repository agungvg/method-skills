// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice FAIL case (stateful): mint() credits balanceOf but forgets
/// totalSupply, so `totalSupply >= balanceOf[to]` breaks on first mint.
contract BuggyMint {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        // BUG: totalSupply += amount; is missing
        assert(totalSupply >= balanceOf[to]);
    }
}
