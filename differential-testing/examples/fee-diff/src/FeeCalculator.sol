// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice CORRECT implementation.
/// Spec: "the fee is amount * bps / 10000, rounded UP to the nearest wei
/// (in the protocol's favour)". Ceiling division.
contract FeeCalculator {
    function fee(uint256 amount, uint256 bps) external pure returns (uint256) {
        require(bps <= 10_000, "bps too high");
        return (amount * bps + 9_999) / 10_000;
    }
}
