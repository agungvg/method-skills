// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice POSITIVE case: the detector MUST fire twice here (once per setter).
/// Both setters copy a numeric parameter straight into storage with no
/// comparison bounding the parameter anywhere — no require, no if, no
/// bounding modifier.
contract FeeVault {
    uint256 public feeBps; // in basis points, 10_000 = 100%
    uint256 public rewardRate; // reward tokens per second
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        feeBps = newFeeBps; // BUG: no upper bound — a compromised owner key can set a 100%+ fee
    }

    function setRewardRate(uint256 newRate) external onlyOwner {
        rewardRate = newRate; // BUG: no upper bound — unbounded reward minting
    }
}
