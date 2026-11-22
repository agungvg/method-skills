// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice NEGATIVE case #2: the detector MUST stay silent here.
/// The bound lives in an applied modifier instead of the function body —
/// this exercises the detector's modifier-scanning path.
contract FeeVaultFixedModifier {
    uint256 public constant MAX_FEE_BPS = 1_000; // 10% cap

    uint256 public feeBps;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier validFeeBps(uint256 _feeBps) {
        require(_feeBps <= MAX_FEE_BPS, "fee too high");
        _;
    }

    function setFeeBps(uint256 newFeeBps) external onlyOwner validFeeBps(newFeeBps) {
        feeBps = newFeeBps;
    }
}
