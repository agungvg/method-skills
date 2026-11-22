#!/usr/bin/env python3
"""Reference implementation for the differential-testing example.

Spec: fee = amount * bps / 10000, rounded UP (ceiling division).
Stdlib only, no network, no side effects. Called by the Foundry FFI test
as:  python3 reference.py <amount> <bps>

Output contract: the expected fee as the HEX encoding of its 32-byte
big-endian ABI representation (64 hex chars, no 0x prefix, no newline),
so the Solidity test can `abi.decode(vm.ffi(...), (uint256))`.

Why hex, not raw bytes or decimal? Foundry's vm.ffi has two behaviours
that punish the alternatives (both verified live, forge 1.10.0):
  - raw 32-byte output: rejected — vm.ffi requires stdout to be valid
    UTF-8, and arbitrary big-endian bytes usually are not
    ("vm.ffi: invalid utf-8 sequence of 1 bytes from index 30").
  - plain decimal text: returned raw ONLY when the text is not valid
    even-length hex; a decimal string that happens to be valid hex
    (e.g. "5999") is silently hex-DECODED into different bytes
    ("5999" -> 0x5999), so vm.parseUint then fails or, worse, parses
    a wrong value. Decimal output is input-dependent — never use it.
Hex output is deterministic for every input: always 64 hex chars,
always decoded to the same 32 bytes.
"""
import sys

if len(sys.argv) != 3:
    raise SystemExit("usage: reference.py <amount> <bps>")

amount = int(sys.argv[1])
bps = int(sys.argv[2])
assert 0 <= bps <= 10_000, "bps too high"
assert amount >= 0, "amount negative"

# Ceiling division: (a * b + 9999) // 10000
fee = (amount * bps + 9_999) // 10_000
sys.stdout.write(fee.to_bytes(32, "big").hex())
