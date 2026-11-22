---
name: formal-verification-free
description: Free formal verification for Solidity — solc SMTChecker (ships with solc, no account, no key) to prove invariants or get concrete counterexamples, plus the verified status of the open-source Certora Prover (local build runs without a key; the cloud CLI needs a free key). Use when a check needs a mathematical proof rather than a test, or when deciding which free prover to reach for.
license: MIT
metadata:
  author: Antares
  version: "1.0"
  chain: EVM
  category: Security
tags:
  - formal-verification
  - smtchecker
  - solc
  - certora
  - cvl
  - security
---

# Free Formal Verification

Two genuinely free routes exist for proving Solidity properties. Everything
below was verified by execution on 2026-11-22 (solc 0.8.30, z3 4.14.1);
outputs quoted are real outputs from that run, not illustrations.

1. **solc SMTChecker — the default choice.** Ships inside `solc` itself.
   No account, no key, no network, runs entirely locally. It proves
   `assert` statements and built-in safety targets (overflow, division by
   zero, …) or returns a concrete counterexample. Limited, but real.
2. **Certora Prover, local build — the heavyweight choice.** The Prover
   went open source (GPL-3.0) on 2025-02-24. The code is public and the
   locally-built prover does **not** need an API key — the key is only
   required for Certora's cloud. The local build is heavy (Gradle + JDK
   19+ + z3 + cvc5 + Rust) and was **not** completed on this VM
   (see §4 for the exact blocker); use the documented build steps on a
   machine where Gradle's daemon can run.

## What you probably got wrong

- **SMTChecker is not a fuzzer and not a test.** It does not run your
  contract with sample inputs. It reasons about *all* inputs at once.
  "Proved safe" means no input can violate the property (within the
  engine's model); a counterexample is a *specific* input that breaks it.
- **"No output" can mean three different things.** (a) The property was
  proved — solc prints `proved safe`. (b) The check was never run —
  e.g. no SMT solver on `PATH` (see §1.2: solc silently warns and skips
  the analysis). (c) The property is unproved — solc says so explicitly.
  Never read silence as success; always look for the `proved safe` line
  or run with `--model-checker-show-proved-safe`.
- **SMTChecker needs an external SMT solver.** `solc` alone is not
  enough: without `z3` (or Eldarica for CHC) on `PATH`, CHC analysis is
  skipped with a warning and exit code stays 0. Install z3 first (§1.1).
- **Certora is NOT "paid only" any more — but it is not "just install
  it" either.** The source is GPL-3.0 and public
  (`github.com/Certora/CertoraProver`), and the local run path never
  calls the key check (verified in source, §4). The *cloud* path
  (`certora-cli` without a local build) still requires a personal access
  key — free, but it means registering on certora.com. Do not tell a
  user Certora needs payment; do tell them the local build is heavy.
- **`assert` vs `require` is load-bearing here.** SMTChecker verifies
  `assert` (and the built-in targets). `require` is treated as an
  assumption that prunes inputs, not as a property to prove. Put the
  property you want proved in `assert`; use `require` for preconditions.
- **A "proved safe" result is only as good as the model.** External
  calls are abstracted, loops need invariants, and anything the engine
  cannot model is reported as *unproved*, not silently passed. See §3.

## 1. solc SMTChecker

### 1.1 Install: solc + an SMT solver

SMTChecker is built into `solc` — no separate install for the checker
itself. You need (a) a `solc` binary and (b) an SMT solver on `PATH`.

```bash
# solc — solc-select (recommended), or any solc binary. Versions used here:
#   solc 0.8.30 (binary at ~/.svm/0.8.30/solc-0.8.30)
#   solc-select 1.2.0 (~/workspace/tools/method-tools-venv/bin/solc-select)
pip install solc-select
solc-select install 0.8.30
solc-select use 0.8.30
solc --version   # solc, the solidity compiler commandline interface / Version: 0.8.30+commit.73712a01.Linux.g++

# z3 — the solver solc uses by default. Free (MIT), from Microsoft Research.
# The pip wheel ships a real `z3` binary; use it if you cannot install system-wide.
python3 -m venv ~/workspace/tools/formal-verification-venv
~/workspace/tools/formal-verification-venv/bin/pip install z3-solver==4.14.1.0
export PATH=~/workspace/tools/formal-verification-venv/bin:$PATH
z3 --version     # Z3 version 4.14.1 - 64 bit
```

Notes:

- Without z3 on `PATH`, solc warns and skips the analysis — and still
  exits 0. Verified 2026-11-22 (solc 0.8.30, no solver):
  `Warning: Solver z3 was selected for SMTChecker but it is not available.`
  `Warning: CHC analysis was not possible since no Horn solver was found and enabled.`
- `cvc5` is the other supported solver (BMC can use it; CHC accepts
  Eldarica or z3). cvc5 1.2.1 static binary verified present at
  `~/workspace/tools/cvc5-1.2.1/cvc5-Linux-x86_64-static/bin/cvc5`.
  z3 alone covers every example in this skill.
- `solc` is also bundled with Foundry (`~/.foundry/bin/forge` ships its
  own compiler), but `forge build` does **not** run the model checker —
  invoke `solc` directly for this skill.

### 1.2 The engines: CHC vs BMC

| Engine | Flag | What it does | Best for |
|---|---|---|---|
| CHC | `--model-checker-engine chc` | Horn-clause solving; tries to **prove** the property for all inputs, unbounded | Proving invariants; the default engine to reach for |
| BMC | `--model-checker-engine bmc` | Bounded model checking; unrolls loops/calls up to a bound and searches for a violation | Finding bugs fast; loop-heavy code (bounded) |
| all | `--model-checker-engine all` | Runs both | When you want both a proof attempt and a bounded bug hunt |

```bash
solc --model-checker-engine chc --model-checker-timeout 10000 Contract.sol
solc --model-checker-engine bmc --model-checker-timeout 10000 Contract.sol
solc --model-checker-engine all --model-checker-timeout 10000 Contract.sol
```

- `--model-checker-timeout <ms>` is **per query** (per verification
  condition), not total. 10000 (10 s) is a sane default; raise it before
  concluding "unproved" (§3).
- `--model-checker-show-proved-safe` prints *which* check was proved,
  with file/line. `--model-checker-show-unproved` does the same for
  failures. Use them — the summary line alone hides which property.
- `--model-checker-targets <list>` selects what is checked. Default is
  all targets. Values: `assert`, `underflow`, `overflow`, `divByZero`,
  `constantCondition`, `popEmptyArray`, `outOfBounds`, `balance`,
  `verifyOverflow` (and more — see `solc --help`). Narrowing targets
  silences classes of warnings you have deliberately accepted (demo in
  §2.3).

### 1.3 What it checks

- Every `assert(...)` in the contract (the main tool: encode the
  property you want proved as an assertion).
- Built-in targets, with no assertion needed: arithmetic overflow /
  underflow, division by zero, out-of-bounds access, popping an empty
  array, unreachable/constant conditions, and (for payable code) balance
  invariants. Note: in Solidity ≥0.8, arithmetic overflow **reverts**
  by default, so the overflow target usually passes — it bites in
  `unchecked` blocks, which is exactly where the §2.2 counterexample
  comes from.

## 2. Verified examples

All examples live in `examples/` next to this file and were run with
solc 0.8.30 + z3 4.14.1 on 2026-11-22. The outputs below are verbatim
(exit code 0 in every case — **solc exits 0 even when it finds a
violation**, so read the output, never the exit code).

### 2.1 PASS — checked arithmetic, CHC proves it (`examples/SafeAdd.sol`)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract SafeAdd {
    function add(uint256 a, uint256 b) public pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}
```

```bash
solc --model-checker-engine chc --model-checker-timeout 10000 SafeAdd.sol
```

Real output:

```
Info: CHC: 1 verification condition(s) proved safe! Enable the model checker option "show proved safe" to see all of them.
```

Why it proves: Solidity 0.8 checked arithmetic reverts on overflow
*before* the `assert` is reached, so `c >= a` holds for every input
that gets that far. With `--model-checker-show-proved-safe` solc names
the check:

```
Info: CHC: Assertion violation check is safe!
 --> SafeAdd.sol:9:9:
  |
9 |         assert(c >= a);
  |         ^^^^^^^^^^^^^^
```

### 2.2 FAIL — unchecked subtraction, CHC finds a counterexample (`examples/UnsafeSub.sol`)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract UnsafeSub {
    function sub(uint256 a, uint256 b) public pure returns (uint256) {
        unchecked {
            uint256 c = a - b;
            assert(c <= a);
            return c;
        }
    }
}
```

```bash
solc --model-checker-engine chc --model-checker-timeout 10000 UnsafeSub.sol
```

Real output (counterexample + transaction trace):

```
Warning: CHC: Assertion violation happens here.
Counterexample:

a = 0
b = 115792089237316195423570985008687907853269984665640564039457584007913129639935
 = 0
c = 1

Transaction trace:
UnsafeSub.constructor()
UnsafeSub.sub(0, 115792089237316195423570985008687907853269984665640564039457584007913129639935)
  --> UnsafeSub.sol:10:13:
   |
10 |             assert(c <= a);
   |             ^^^^^^^^^^^^^^
```

Reading it: `a = 0`, `b = 2**256 - 1` underflows in `unchecked` to
`c = 1`, and `1 <= 0` is false. The trace tells you the exact call
that breaks the property — replay it as a Foundry test to confirm.

BMC finds the same bug with a smaller counterexample:

```bash
solc --model-checker-engine bmc --model-checker-timeout 10000 UnsafeSub.sol
```

```
Warning: BMC: Assertion violation happens here.
  --> UnsafeSub.sol:10:13:
   |
10 |             assert(c <= a);
   |             ^^^^^^^^^^^^^^
Note: Counterexample:
   = 0
  a = 0
  b = 1
  c = 2**256 - 1
```

### 2.3 Built-in target — division by zero needs no assert (`examples/DivZero.sol`)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract DivZero {
    function div(uint256 a, uint256 b) public pure returns (uint256) {
        return a / b;
    }
}
```

Default targets (CHC) — the `divByZero` target fires with no `assert`
in the code at all:

```
Warning: CHC: Division by zero happens here.
Counterexample:

a = 0
b = 0
 = 0

Transaction trace:
DivZero.constructor()
DivZero.div(0, 0)
 --> DivZero.sol:8:16:
  |
8 |         return a / b;
  |                ^^^^^
```

Narrowing targets to `assert` only silences it (use when a target
class is deliberately accepted, never to hide a bug you have not read):

```bash
solc --model-checker-engine chc --model-checker-targets assert --model-checker-timeout 10000 DivZero.sol
# Compiler run successful. No output generated.
```

### 2.4 PASS (stateful) / FAIL (stateful) — a token invariant (`examples/MiniToken.sol`, `examples/BuggyMint.sol`)

The useful audit pattern is a **stateful** invariant: an `assert`
about storage that must hold after every public function, not just
inside one pure function.

`MiniToken.transfer` preserves the sum of the two balances involved —
CHC proves it for all inputs:

```solidity
function transfer(address to, uint256 amount) external {
    require(balanceOf[msg.sender] >= amount);
    uint256 before = balanceOf[msg.sender] + balanceOf[to];
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    if (msg.sender != to) {
        assert(balanceOf[msg.sender] + balanceOf[to] == before);
    }
}
```

```
Info: CHC: 1 verification condition(s) proved safe! Enable the model checker option "show proved safe" to see all of them.
```

`BuggyMint.mint` credits `balanceOf` but forgets `totalSupply` — CHC
finds it on the first mint:

```solidity
function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
    // BUG: totalSupply += amount; is missing
    assert(totalSupply >= balanceOf[to]);
}
```

```
Warning: CHC: Assertion violation happens here.
Counterexample:
totalSupply = 0
to = 0x0
amount = 115792089237316195423570985008687907853269984665640564039457584007913129621478

Transaction trace:
BuggyMint.constructor()
State: totalSupply = 0
BuggyMint.mint(0x0, 115792089237316195423570985008687907853269984665640564039457584007913129621478)
  --> BuggyMint.sol:13:9:
   |
13 |         assert(totalSupply >= balanceOf[to]);
   |         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```

Note the trace includes the **pre-call state** (`totalSupply = 0`) —
that is the state the counterexample starts from, which is what makes
these traces directly replayable.

## 3. Honest limits (verified, not assumed)

- **Loops.** A true property over an unbounded loop is usually
  *unproved* without a loop invariant, even when the property is true.
  Verified (`examples/LoopSum.sol` — `s = 0+1+…+(n-1)` and
  `assert(s <= n * n)`, which holds for every `n`):

  ```
  Warning: CHC: 1 verification condition(s) could not be proved. Enable the model checker option "show unproved" to see all of them. Consider choosing a specific contract to be verified in order to reduce the solving problems. Consider increasing the timeout per query.
  ```

  "Could not be proved" is **not** "false" — it means the engine gave
  up (timeout or missing invariant). Responses, in order: raise
  `--model-checker-timeout`; verify a single contract
  (`solc … Contract.sol` already scopes per file — narrow further with
  `--model-checker-contracts Contract.sol:ContractName`); add an
  explicit loop invariant as an `assert` inside the loop; or accept
  BMC's bounded answer instead and say so.
- **External calls are abstracted.** The engine does not know what an
  unknown external contract will do; it assumes the worst (reentrancy
  included) for state it can touch. A proof that passes *despite* that
  abstraction is strong; a failure may be a modelling artefact — read
  the trace before filing.
- **Timeouts are per query, and "unproved" is the common outcome on
  real contracts.** SMTChecker is a scalpel for load-bearing invariants
  (accounting, access control, solvency), not a whole-protocol prover.
  For whole-protocol proofs, that is what Certora (§4) is for.
- **No liveness, no gas, no economics.** It proves safety properties
  ("this bad state never happens"), not "this function eventually
  succeeds" or "this is profitable".
- **Exit code 0 means nothing.** Both proved-safe and violation runs
  exit 0. Parse the output text (`proved safe` / `violation` /
  `could not be proved`).

## 4. Certora Prover — verified status (2026-11-22)

**Verdict: open-source YES; runnable locally without payment YES (by
code inspection + official docs); a full local run was NOT completed
on this VM — the blocker is this VM's Gradle daemon, not Certora.**

Evidence, each item checked 2026-11-22:

- **Open source, genuinely.** Announcement on Certora's own site,
  2025-02-24: "We are open-sourcing the Certora Prover … which is now
  free, transparent, and community-driven"
  (`certora.com/blog/certora-goes-open-source`). Repo
  `github.com/Certora/CertoraProver` (note: `CertoraProver`, no hyphen —
  `github.com/Certora/certora-prover` 404s) is public, license
  **GPL-3.0**, created 2025-02-23.
- **No key for local runs — verified in source.** In the cloned repo,
  `validate_certora_key()` (which raises unless `CERTORAKEY` is set) is
  called only from `run_remote()` (`scripts/Shared/proverCommon.py`).
  The local path (`run_local()`, same file) runs the built jar directly
  and never touches the key. `is_local()` (`scripts/Shared/certoraUtils.py`)
  selects the local path when a built `emv.jar` exists in the `CERTORA`
  directory and no `--server` flag is given. The official install docs
  (`docs.certora.com`, Step 3: "The Certora Prover requires a personal
  access key … register on the Certora website") describe the **cloud
  CLI** path (`pip install certora-cli` without a local build), not the
  local build. A free key is obtainable via registration or Certora's
  Discord, but a local build does not need one.
- **`pip install certora-cli` alone does NOT give you a local prover —
  verified from the wheel.** The `certora-cli 8.20.3` wheel from PyPI
  contains only `ASTExtraction.jar` and `Typechecker.jar` (the pieces
  that build inputs for the *cloud* prover) plus a `gambit` binary —
  no `emv.jar`. The main prover jar exists only after `./gradlew
  assemble`. Installing the CLI and running without a local build
  sends the job to the cloud and needs the key.
- **Build prerequisites (README):** JDK 19+, z3 **and** cvc5 (required),
  Python 3, solc, Rust 1.81+, LLVM tools (`llvm-symbolizer`,
  `llvm-dwarfdump`), `rustfilt`; optional Graphviz (`dot`). Build:
  `git clone --recurse-submodules https://github.com/Certora/CertoraProver.git`
  then `./gradlew assemble` with `CERTORA` set to a build-output dir on
  `PATH`. Run a bundled example with `certoraRun.py <conf>` (e.g.
  `Public/TestEVM/Counter/counter.conf`).
- **VM blocker (this machine only, 2026-11-22).** The Gradle wrapper
  cannot download its distribution here (Java's direct TLS fails
  against the egress proxy — `SSLException: Unsupported or unrecognized
  SSL message`; `curl` works). Gradle 7.2 was fetched with `curl` and
  run directly, but the Gradle daemon's localhost socket protocol
  fails on this VM in every configuration tried (JDK 17 and JDK 25,
  `--no-daemon`, clean daemon registry, `preferIPv4Stack`,
  `org.gradle.daemon=false` with matching JVM args): the client
  reports `Could not receive a message from the daemon` /
  `Unexpected type tag 109 found` (109 = `m`). The `daemon=false`
  attempt proved the point — Gradle 7.2 *always* forks a (single-use)
  daemon process, so there is no socket-free Gradle mode to fall back
  on. A minimal Java loopback test confirmed the cause: a Java
  process's localhost socket received the bytes `muse: ` instead of
  the bytes the peer sent, while the identical Python loopback test
  returned the bytes intact — so the daemon protocol is corrupted at
  the Java-socket layer on this VM, not by Certora. **Do not keep
  retrying the Gradle daemon here; run the Certora build on a machine
  with a normal loopback, or in CI.** The Certora build artefacts and
  logs from the attempt are in
  `~/workspace/tools/certora-prover-build/` (repo clone, Gradle 7.2 at
  `~/workspace/tools/gradle-7.2/`, build logs).
- **CVL in one paragraph (for when the local build works).** Rules are
  written in CVL (Certora Verification Language, Solidity-like) in a
  `.spec` file, wired to the contract in a `.conf` file, and run with
  `certoraRun <conf>` (local build on `PATH` takes priority over the
  cloud; add `--server production` to force cloud). A rule states a
  property over *all* executions (e.g. "a user can never withdraw more
  than deposited"); the Prover returns a proof or a counterexample
  trace. CVL is a separate language to learn — budget a day for the
  first real spec; the bundled `Public/TestEVM/*` examples are the
  fastest on-ramp.

## 5. Workflow: when to use which

1. **Load-bearing invariant on a small contract** (accounting,
   allowance, solvency) → SMTChecker first: 30 seconds, zero setup
   beyond z3, and a counterexample is immediately replayable.
2. **SMTChecker says "could not be proved"** → raise the timeout,
   narrow the contract/targets, add a loop invariant, or switch the
   property to BMC for a bounded answer. Record which of those you did
   — "unproved after 60 s timeout" is a finding about the method, not
   a clean bill of health.
3. **Whole-protocol property, cross-function invariants, or a rule
   that needs ghost state / summaries** → Certora local build (§4).
   If the local build is unavailable, Halmos (symbolic testing, no
   key) or Echidna/Medusa (property fuzzing) are the next rungs — they
   are weaker (bounded / sampled) but they run anywhere.
4. **Report honestly.** A first-pass report states the engine, the
   exact command, the timeout, and the outcome class for each property:
   `proved safe` / `violation (counterexample attached)` /
   `could not be proved (timeout/invariant missing)`. Never write
   "formally verified" for a BMC-only or unproved result.

## 6. Safety / scope

- Local-only by construction: `solc`, z3, cvc5 and a local Certora
  build never send code anywhere. The Certora **cloud** path sends
  your contract to Certora's servers and needs a registered key —
  that is the only network step in this skill, and it is opt-in.
- No secrets, no private keys, no account creation is needed for
  anything in §§1–3. For §4, no Certora account is needed for the
  local build; only the cloud path needs registration.
- Never present a counterexample as an exploit by itself: replay it
  (Foundry test or mainnet-fork PoC) before filing, per the usual
  proof standard.
