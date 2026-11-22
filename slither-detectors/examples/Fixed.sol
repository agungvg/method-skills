// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice NEGATIVE case: the detector MUST stay silent here.
/// Same setters as Vulnerable.sol, but each parameter is range-checked with
/// a require() before the assignment.
contract FeeVaultFixed {
    uint256 public constant MAX_FEE_BPS = 1_000; // 10% cap
    uint256 public constant MAX_REWARD_RATE = 1 ether;

    uint256 public feeBps;
    uint256 public rewardRate;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= MAX_FEE_BPS, "fee too high");
        feeBps = newFeeBps;
    }

    function setRewardRate(uint256 newRate) external onlyOwner {
        require(newRate <= MAX_REWARD_RATE, "rate too high");
        rewardRate = newRate;
    }
}
