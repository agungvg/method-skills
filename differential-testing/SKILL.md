---
name: differential-testing
effort: low
description: "Differential testing for smart contracts and numeric code: run the same inputs through two independent implementations of one spec and assert the outputs match. Use when a second implementation exists or can be written cheaply — a reference implementation in Python via Foundry FFI, a previous contract version, a fork deployment vs a local rewrite, or two chains' deployments of the same logic — and when you need to catch subtle divergences (rounding, edge cases, off-by-ones) that example tests miss. Extends the Oracle property in property-based-testing into a full method: FFI reference workflow, differential fuzzing, and fork-vs-local / anvil-vs-anvil harnesses. Not for code with no second implementation available, for nondeterministic behaviour, or as a substitute for an invariant when no oracle exists."
---

# Differential Testing

Feed the **same inputs** to **two independent implementations** of one spec
and assert the outputs are identical. The invariant is one line —
`new(x) == reference(x)` — and it is the strongest property most numeric
code supports: it needs no hand-written expected values, so the fuzzer can
range over the whole input domain instead of the cases you thought of.

This skill **extends** the Oracle property in
[property-based-testing](../property-based-testing/SKILL.md) (property
catalog: `new(x) == reference(x)`). Read that skill first for the property
vocabulary — roundtrip, idempotence, tautology vs. vacuity — then use this
one for the three concrete harnesses below. Do not duplicate its catalog
here; the method below is the part property-based-testing does not cover.

## When it applies, and when it doesn't

**Applies when:**
- A second implementation exists or is cheap to write: a reference in
  another language, the previous version of the contract, a competitor's
  contract, a fork deployment vs. a local rewrite, the same logic deployed
  on two chains.
- The function is deterministic and pure (or its state can be reset to the
  same starting point on both sides): fee math, fixed-point/rounding
  functions, pricing curves, encoding/decoding, auction/settlement math.
- The spec is written down somewhere independent of both implementations —
  a doc, a formula, a whitepaper. The spec is what decides which side is
  wrong when they disagree.

**Does not apply when:**
- There is no second implementation and writing one would just restate the
  first (that is the tautology trap from property-based-testing: two copies
  of the same bug agree with each other and prove nothing).
- Behaviour is nondeterministic or depends on external state you cannot
  equalize (block timestamps, oracle prices, balances that differ between
  the two environments). Equalize the state first, or differential testing
  reports noise, not bugs.
- Only one implementation exists and the property you actually need is an
  invariant (e.g. "total supply is conserved") — use property-based
  testing / invariant testing instead.

**The shared-bug blind spot.** Differential testing catches *divergence*,
not *wrongness*. If both implementations encode the same misunderstanding
of the spec, they agree and the bug survives. Mitigate by making the
reference as independent as possible: different language, different author,
different code shape (e.g. remainder-check instead of the `+9999` trick —
see `examples/fee-diff/src/FeeReference.sol`), and ideally derived from
the spec text rather than from the implementation under test.

## Workflow 1 — Differential fuzzing (two Solidity implementations)

The cheapest harness. Two contracts, one fuzz test, one assertion.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "forge-std/Test.sol";
import "../src/FeeCalculator.sol";   // implementation under test
import "../src/FeeReference.sol";    // independent re-implementation

contract DifferentialTest is Test {
    FeeCalculator internal impl;
    FeeReference internal ref;

    function setUp() public {
        impl = new FeeCalculator();
        ref = new FeeReference();
    }

    function test_Differential_CorrectVsReference(uint256 amount, uint256 bps) public view {
        vm.assume(amount < 1e36); // keep amount*bps clear of uint256 overflow
        vm.assume(bps <= 10_000);
        assertEq(impl.fee(amount, bps), ref.fee(amount, bps), "differential mismatch");
    }
}
```

Rules that matter:
- **Bound the inputs.** `amount * bps` must not overflow, or both sides
  revert/overflow together and the test asserts nothing. Push the bound
  into `vm.assume` (or, better, into the generator) and keep it far from
  the overflow edge: here `1e36 * 1e4 = 1e40 << 2^256`.
- **Include edge cases as fixed tests** alongside the fuzz: exact multiples
  (where floor and ceiling agree), zero, maxima. The fuzzer may take many
  runs to hit `amount * bps % 10000 == 0` on its own.
- **Keep the reference in a separate file, written from the spec**, not by
  copying the implementation and tweaking it. A copied reference shares the
  bug.

## Workflow 2 — FFI reference implementation (Python oracle)

When the reference is easiest to write in another language, run it through
Foundry FFI: the test shells out to the reference program per fuzz input
and compares.

Setup: `ffi = true` in `foundry.toml`, and run with `forge test --ffi`.
**FFI runs arbitrary local commands — enable it only in a project you fully
control, never in a repo you have not read, and never point it at a script
fetched from the network.**

Reference program (`reference.py`, stdlib only):

```python
#!/usr/bin/env python3
"""fee = amount * bps / 10000, rounded UP (ceiling division)."""
import sys
amount = int(sys.argv[1]); bps = int(sys.argv[2])
assert 0 <= bps <= 10_000
fee = (amount * bps + 9_999) // 10_000
sys.stdout.write(fee.to_bytes(32, "big").hex())
```

Test:

```solidity
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
```

### The `vm.ffi` output contract — read this before writing your own

Verified live on forge 1.10.0; all three behaviours below were hit during
verification of this skill, not guessed:

1. **Stdout must be valid UTF-8.** Raw 32-byte big-endian output is
   rejected: `vm.ffi: invalid utf-8 sequence of 1 bytes from index 30`.
2. **Stdout that looks like valid even-length hex is silently
   hex-decoded.** A decimal string that happens to be valid hex (e.g.
   `"5999"`) comes back as different bytes (`0x5999`), so a
   `vm.parseUint` on it fails — or, worse, parses a wrong value. Decimal
   output is input-dependent and must never be used.
3. **Hex output is deterministic for every input.** Emit the hex encoding
   of the ABI-encoded value (64 hex chars for a uint256, no `0x` prefix,
   no newline) and `abi.decode` it on the Solidity side. That is the only
   output contract that behaves the same for all inputs.

Also note: FFI tests are slow (one process spawn per fuzz input — 256 runs
took ~10s in verification). For large run counts, prefer Workflow 1 and
reserve FFI for the cross-language check.

## Workflow 3 — Fork-vs-local / anvil-vs-anvil harness

When the two implementations live in different deployments rather than one
test process — e.g. a mainnet-fork deployment vs. a local rewrite, or an
old version vs. a new version — deploy both, feed both the same inputs over
RPC, and diff the outputs outside the test process.

**Offline form (verified): two local anvil instances.** No fork URL, no
mainnet, no network. `examples/anvil-diff/harness.sh` starts an anvil on
:8545 and another on :8546, deploys the correct implementation to one and
the suspect one to the other, then loops over a fixed deterministic input
set (5 edge cases + 15 seeded pseudo-random pairs) calling `cast call` on
both and printing `MATCH` / `MISMATCH` per input. Exit code 0 when every
output matched, 1 otherwise. A `--both-correct` mode deploys the correct
implementation to both sides as the green baseline.

**Fork form (same shape, needs a live RPC):** replace one anvil with
`anvil --fork-url <RPC_URL> --fork-block-number <N>` and deploy (or use
the already-deployed) implementation there; the local side is a plain
anvil with the rewrite. Everything else — same inputs, same `cast call`,
diff — is identical. Pin the fork block number, or the fork side drifts
under you between runs. The fork variant was *not* run during verification
(it needs a live RPC URL); the anvil-vs-anvil form verifies the whole
harness mechanics offline, and the only delta for fork mode is how the
second chain is started.

Two live gotchas from verification, both worth knowing before you debug
them for an hour:
- `forge create` in forge 1.10 is a **dry run unless `--broadcast`** is
  passed — without it, no contract is deployed and there is no
  `Deployed to:` line to parse.
- A **wrong deployer key fails with a misleading error**: anvil rejects
  `eth_estimateGas` from an unfunded address as `Out of gas: gas required
  exceeds allowance: 0`. If you see that, check the key first — verify
  with `cast wallet address --private-key <key>` against the funded
  account anvil prints on startup (account #0 is
  `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`).

## Interpreting a mismatch

A failing differential test says "the two sides disagree". It does not say
which side is wrong. Triangulate before fixing anything:

1. **Read the spec.** The spec is the tiebreaker. In the example the spec
   says "rounded UP" — the floor-division side is wrong by definition.
2. **Check the counterexample by hand.** The fuzzer shrinks to the
   smallest failing input; compute it yourself (a calculator, the Python
   reference, a third implementation). In verification the first failing
   input was `amount=1, bps=1` → correct `1`, buggy `0` — hand-checkable
   in seconds.
3. **Suspect the harness before the code.** Wrong bounds (`vm.assume`
   too tight → vacuity), mismatched ABIs, stale artifacts, different
   starting state between the two deployments — each produces a mismatch
   with no bug behind it. The green baselines exist for exactly this: if
   the correct-vs-correct run is red, the harness is broken, not the code.
4. **Look at the shape of the divergence.** A constant off-by-one on
   non-multiples (the example: every mismatch is `A = B + 1`) points at
   rounding; divergence only above a threshold points at overflow or a
   branch; divergence on one input in a thousand points at an edge case.

## Worked example — what is in `examples/`

`examples/fee-diff/` is a complete Foundry project (forge-std vendored
under `lib/`, no network needed to build):
- `src/FeeCalculator.sol` — correct: ceiling division, per spec.
- `src/FeeCalculatorBuggy.sol` — planted bug: floor division (one-line
  difference, same signature, same reverts).
- `src/FeeReference.sol` — independent correct re-implementation
  (remainder-check shape) for Workflow 1.
- `reference.py` — Python oracle for Workflow 2 (hex output contract).
- `test/Differential.t.sol` — Workflow 1, green baseline.
- `test/DifferentialFFI.t.sol` — Workflow 2, runs with `forge test --ffi`.
- `test/DifferentialBuggy.t.sol` — **intentionally failing**: the same
  differential fuzz against the buggy implementation. It demonstrates the
  catch; do not "fix" it by weakening the assertion.
- `foundry.toml` — `ffi = true`.

`examples/anvil-diff/harness.sh` — Workflow 3, anvil-vs-anvil.

## Verification log (all run live 2026-11-22, forge 1.10.0, Python 3.12.3)

Environment: `export PATH="$HOME/.foundry/bin:$PATH"`, workdir
`examples/fee-diff/` unless noted. forge-std was copied from a local
project checkout (the `lib/forge-std` dirs in other local checkouts were
empty uninitialized submodules); no network install was used.

| Command | Result |
|---|---|
| `python3 reference.py 123456789 250` | `00000000000000000000000000000000000000000000000000000000002f1854` (= 3,086,420 — ceiling of 3,086,419.725) |
| `forge test --match-contract DifferentialTest` | **PASS** — 2 passed, 0 failed; fuzz `test_Differential_CorrectVsReference` 256 runs, edge-case test passed |
| `forge test --ffi --match-contract DifferentialFFITest` | **PASS** — 2 passed, 0 failed; fuzz `test_FFI_ReferenceMatches` 256 runs in ~9.9s |
| `forge test --match-contract DifferentialBuggyTest` | **FAIL (the catch)** — `differential mismatch: 1 != 0`, counterexample `args=[1, 1]`, `runs: 0` (first input already diverges); exit 1 |
| `forge test --ffi` (whole suite) | 4 passed, 1 failed (only the intentional buggy-catch test), exit 1 |
| `examples/anvil-diff/harness.sh` | **18 mismatch / 2 match of 20 inputs**, exit 1; every mismatch is `A = B + 1` (floor-vs-ceil signature); the 2 matches are exact multiples (`10000,1` and `1e18,500`) where floor and ceiling agree |
| `examples/anvil-diff/harness.sh --both-correct` | **20 match / 0 mismatch**, exit 0 — green baseline for the harness |

Failures encountered *while verifying* (kept here because they are the
traps a user of this method will hit):
- Raw 32-byte FFI output → `vm.ffi: invalid utf-8 sequence`; decimal FFI
  output → `"5999"` hex-decoded to `0x5999`, `vm.parseUint` failed with
  `expected at least one digit`. Both fixed by the hex output contract
  above; probe confirmed `vm.ffi("abcd") → 0xabcd`,
  `vm.ffi("hello") → 0x68656c6c6f` (raw), `vm.ffi("5999") → 0x5999`.
- `forge create` without `--broadcast` silently dry-runs; harness deploys
  failed until `--broadcast` was added.
- One mistyped hex digit in the anvil deployer key produced
  `Out of gas: gas required exceeds allowance: 0` from an unfunded
  address; fixed by copying the key from anvil's own startup output.

**Not verified:** the fork form of Workflow 3 against a live RPC URL
(needs a live RPC; the anvil-vs-anvil form verifies the same harness
mechanics offline). No other part of this skill is unverified.

## Safety

- Method only. No exfiltration, no secrets, no phone-home, no paid
  signups, no API keys. The example reference program is stdlib-only
  Python with no network access.
- `ffi = true` executes local commands: keep it in example/throwaway
  projects, review every script it can invoke, and never enable it on a
  repo you have not read.
- Anvil harnesses use throwaway local chains and anvil's well-known
  test keys — never reuse those keys or this harness shape against a
  live network.
