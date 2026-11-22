// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice PASS case: checked arithmetic (Solidity 0.8 default) reverts on
/// overflow BEFORE the assert is reached, so `c >= a` always holds.
contract SafeAdd {
    function add(uint256 a, uint256 b) public pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}
