// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/FeeCalculator.sol";
import "../src/FeeCalculatorBuggy.sol";

/// @notice INTENTIONALLY FAILING — this file is the demonstration of the catch.
/// It runs the identical differential fuzz against the BUGGY implementation
/// (floor division). Expect `forge test --match-contract DifferentialBuggyTest`
/// to FAIL with a counterexample. Do not "fix" this test by weakening the
/// assertion; fix the implementation under test instead (or point the test
/// at FeeCalculator and watch it go green).
contract DifferentialBuggyTest is Test {
    FeeCalculator internal impl;
    FeeCalculatorBuggy internal buggy;

    function setUp() public {
        impl = new FeeCalculator();
        buggy = new FeeCalculatorBuggy();
    }

    function test_Differential_CorrectVsBuggy(uint256 amount, uint256 bps) public view {
        vm.assume(amount < 1e36);
        vm.assume(bps <= 10_000);
        vm.assume(amount > 0 && bps > 0);
        assertEq(impl.fee(amount, bps), buggy.fee(amount, bps), "differential mismatch");
    }
}
