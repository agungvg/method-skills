// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice LIMIT demo: `s = 0+1+...+(n-1) = n*(n-1)/2 <= n*n` is TRUE for
/// every n, but CHC cannot prove it without a loop invariant — expect
/// "unproved" / timeout, NOT "proved safe". Loops are SMTChecker's
/// honest weak spot.
contract LoopSum {
    function sum(uint256 n) public pure returns (uint256 s) {
        for (uint256 i = 0; i < n; i++) {
            s += i;
        }
        assert(s <= n * n);
    }
}
