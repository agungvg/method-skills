// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice INDEPENDENT second implementation of the same spec, written in a
/// different code shape (explicit remainder check instead of the +9999 trick).
/// This is the in-Solidity oracle for the differential test: it shares no
/// code with FeeCalculator, so a bug in one implementation's arithmetic
/// cannot silently hide in the other.
contract FeeReference {
    function fee(uint256 amount, uint256 bps) external pure returns (uint256) {
        require(bps <= 10_000, "bps too high");
        uint256 prod = amount * bps;
        uint256 q = prod / 10_000;
        if (prod % 10_000 != 0) {
            q += 1;
        }
        return q;
    }
}
