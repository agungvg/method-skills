# differential-testing examples

Two runnable examples for the `differential-testing` skill
(`../SKILL.md`). Both verified live 2026-11-22 with forge 1.10.0.

## fee-diff/ — Foundry project (Workflows 1 + 2)

- `src/FeeCalculator.sol` — correct implementation (ceiling division).
- `src/FeeCalculatorBuggy.sol` — planted bug (floor division).
- `src/FeeReference.sol` — independent correct re-implementation.
- `reference.py` — Python oracle (hex output contract, see SKILL.md).
- `test/Differential.t.sol` — differential fuzz, green baseline.
- `test/DifferentialFFI.t.sol` — FFI reference test.
- `test/DifferentialBuggy.t.sol` — **intentionally failing** bug-catch demo.

```bash
export PATH="$HOME/.foundry/bin:$PATH"
cd fee-diff
forge test --match-contract DifferentialTest        # expect PASS (2 passed)
forge test --ffi --match-contract DifferentialFFITest  # expect PASS (2 passed)
forge test --match-contract DifferentialBuggyTest   # expect FAIL: 1 != 0, args=[1, 1]
```

forge-std is vendored under `lib/` (copied from a local checkout), so no
network is needed to build.

## anvil-diff/ — anvil-vs-anvil harness (Workflow 3)

```bash
export PATH="$HOME/.foundry/bin:$PATH"
cd anvil-diff
./harness.sh               # expect 18 mismatch / 2 match, exit 1
./harness.sh --both-correct # expect 20 match / 0 mismatch, exit 0
```

Runs fully offline on two local anvil instances (ports 8545/8546).
