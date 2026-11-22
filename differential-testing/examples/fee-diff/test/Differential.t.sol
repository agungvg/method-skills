// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/FeeCalculator.sol";
import "../src/FeeReference.sol";

/// @notice Differential fuzz: the SAME randomized inputs go to two
/// independent implementations of the same spec, and the invariant is
/// simply "outputs must match". Both implementations here are correct,
/// so this test PASSES — the green baseline that proves the harness
/// itself is not broken before you point it at a suspect implementation.
contract DifferentialTest is Test {
    FeeCalculator internal impl;
    FeeReference internal ref;

    function setUp() public {
        impl = new FeeCalculator();
        ref = new FeeReference();
    }

    function test_Differential_CorrectVsReference(uint256 amount, uint256 bps) public view {
        // Keep amount * bps far from uint256 overflow: 1e36 * 1e4 = 1e40 << 2^256.
        vm.assume(amount < 1e36);
        vm.assume(bps <= 10_000);
        assertEq(impl.fee(amount, bps), ref.fee(amount, bps), "differential mismatch");
    }

    /// Concrete edge cases the fuzzer may take a while to hit on its own.
    function test_Differential_EdgeCases() public view {
        assertEq(impl.fee(1, 1), ref.fee(1, 1)); // 1*1/10000 rounds up to 1
        assertEq(impl.fee(10_000, 1), ref.fee(10_000, 1)); // exact multiple
        assertEq(impl.fee(9_999, 9_999), ref.fee(9_999, 9_999));
        assertEq(impl.fee(0, 5_000), ref.fee(0, 5_000)); // zero amount
        assertEq(impl.fee(1e18, 500), ref.fee(1e18, 500)); // 1 ether, 5%
        assertEq(impl.fee(1e18, 10_000), ref.fee(1e18, 10_000)); // 100% bps
    }
}
