// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Built-in target demo: division by zero is checked even with
/// NO assert in the code (target `divByZero` is on by default).
contract DivZero {
    function div(uint256 a, uint256 b) public pure returns (uint256) {
        return a / b;
    }
}
