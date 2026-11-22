// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/FeeCalculator.sol";

/// @notice FFI reference-implementation test: the oracle lives OUTSIDE
/// Solidity, in reference.py (plain Python, stdlib only). The test feeds
/// the same randomized inputs to both and asserts equal outputs.
/// Requires `ffi = true` in foundry.toml and `forge test --ffi`.
contract DifferentialFFITest is Test {
    FeeCalculator internal impl;

    function setUp() public {
        impl = new FeeCalculator();
    }

    function test_FFI_ReferenceMatches(uint256 amount, uint256 bps) public {
        vm.assume(amount < 1e36);
        vm.assume(bps <= 10_000);
        string[] memory cmds = new string[](4);
        cmds[0] = "python3";
        cmds[1] = "reference.py";
        cmds[2] = vm.toString(amount);
        cmds[3] = vm.toString(bps);
        bytes memory out = vm.ffi(cmds);
        uint256 expected = abi.decode(out, (uint256));
        assertEq(impl.fee(amount, bps), expected, "FFI reference mismatch");
    }

    /// One fixed input, so the FFI round-trip is checkable without the fuzzer.
    function test_FFI_FixedInput() public {
        string[] memory cmds = new string[](4);
        cmds[0] = "python3";
        cmds[1] = "reference.py";
        cmds[2] = "123456789";
        cmds[3] = "250";
        bytes memory out = vm.ffi(cmds);
        uint256 expected = abi.decode(out, (uint256));
        // 123456789 * 250 = 30,864,197,250; /10000 = 3,086,419.725 -> ceil 3,086,420
        assertEq(expected, 3_086_420);
        assertEq(impl.fee(123456789, 250), expected);
    }
}
