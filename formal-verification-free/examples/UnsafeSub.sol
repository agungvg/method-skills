// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice FAIL case: `unchecked` subtraction wraps on underflow, so
/// `c <= a` is FALSE when b > a (e.g. a=0, b=1 -> c = 2**256-1).
contract UnsafeSub {
    function sub(uint256 a, uint256 b) public pure returns (uint256) {
        unchecked {
            uint256 c = a - b;
            assert(c <= a);
            return c;
        }
    }
}
