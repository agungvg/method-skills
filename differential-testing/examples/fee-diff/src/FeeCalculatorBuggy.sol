// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice BUGGY implementation — the planted bug for the differential demo.
/// It uses FLOOR division instead of the ceiling division the spec requires,
/// so it under-charges by 1 wei whenever amount * bps is not an exact
/// multiple of 10_000. Same signature, same revert behaviour, one-line
/// difference — exactly the kind of subtle rounding bug differential
/// testing exists to catch.
contract FeeCalculatorBuggy {
    function fee(uint256 amount, uint256 bps) external pure returns (uint256) {
        require(bps <= 10_000, "bps too high");
        return (amount * bps) / 10_000;
    }
}
