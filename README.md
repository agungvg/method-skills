# method-skills

Bug-bounty verification-method skills, authored from scratch and verified by
execution. Each skill's commands and examples were actually run on a synthetic
vulnerable contract — nothing here is copied from docs alone.

| Skill | Method | Verified |
|---|---|---|
| `differential-testing` | Oracle property, Foundry FFI reference impl, fork-vs-local harness, differential fuzzing | forge tests catch the planted bug; anvil harness 18/20 mismatch vs buggy, 20/20 vs correct |
| `ityfuzz` | ItyFuzz snapshot-based hybrid fuzzer | planted reentrancy found in 257 executions with `-d reentrancy` |
| `wake-fuzzing` | Wake 5 invariant fuzzing (manually-guided flows + Python model) | planted reentrancy caught in 0.41 s, seed-reproducible |
| `slither-detectors` | Custom Slither detector authoring | `missing-setter-bound` detector: 2 findings on vulnerable, 0 on fixed |
| `formal-verification-free` | solc SMTChecker + open-source Certora Prover status | CHC proves SafeAdd, finds BuggyMint violation with counterexample |

## Notes

- `formal-verification-free` also documents the verified status of the
  Certora Prover: open-source (GPL-3.0) since 2025-02-24, local build runs
  without an API key. The full local build was not completed on the author's
  VM (Gradle daemon loopback issue) — see the skill for details.
- No paid signups, no API keys, no exfiltration in any skill.
- License: MIT unless a skill's own frontmatter says otherwise.
