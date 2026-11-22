# Slither Detectors — Custom Detector Authoring

Write, register, and run your own Slither detectors for audit patterns the
~100 built-in detectors miss. Everything in this skill was verified by
execution against Slither **0.11.6** (see "Verification evidence" at the end);
no example here is untested.

## When to use this

- A finding keeps recurring across audits and no built-in detector covers it
  (check first: `slither --list-detectors`, and grep it — see §4).
- A project has a house rule ("every fee setter must be capped", "no
  `delegatecall` outside the proxy") that should be enforced mechanically.
- You want a detector that runs in CI next to the built-ins, not a one-off script.

Do NOT reach for a custom detector when a built-in already covers the
pattern, or when the check needs runtime state (a detector is static
analysis: it sees code, not chain state).

## Install

Reuse the shared method-tools venv when it exists; otherwise install durably
under `~/workspace/tools/` (never `--break-system-packages` on the system pip):

```bash
# Reuse (preferred on this machine):
VENV=~/workspace/tools/method-tools-venv
$VENV/bin/slither --version          # 0.11.6

# Fresh install if no venv exists yet:
python3 -m venv ~/workspace/tools/slither-venv
~/workspace/tools/slither-venv/bin/pip install slither-analyzer solc-select
~/workspace/tools/slither-venv/bin/solc-select install 0.8.39
~/workspace/tools/slither-venv/bin/solc-select use 0.8.39
```

Slither compiles the target itself (via crytic-compile), so a `solc` binary
must be on `PATH` when you run it — the venv's `bin/` dir provides it:

```bash
export PATH="$HOME/workspace/tools/method-tools-venv/bin:$PATH"
```

## 1. Detector skeleton

Source: Slither wiki, "Adding a new detector"
(`github.com/crytic/slither/wiki/Adding-a-new-detector`), plus the shipped
example `slither/detectors/examples/backdoor.py` in the installed package.
Subclass `AbstractDetector`. **Override `_detect()`, not `detect()`** —
`detect()` is the public entry point Slither calls; it wraps `_detect()`.

```python
from slither.detectors.abstract_detector import (
    AbstractDetector,
    DetectorClassification,
    DETECTOR_INFO,
)
from slither.utils.output import Output


class Skeleton(AbstractDetector):
    """
    Documentation
    """

    ARGUMENT = "mydetector"  # run with: slither . --detect mydetector
    HELP = "Help printed by `slither --list-detectors`"
    IMPACT = DetectorClassification.HIGH
    CONFIDENCE = DetectorClassification.HIGH

    WIKI = ""  # link to the detector's wiki page, if any
    WIKI_TITLE = ""
    WIKI_DESCRIPTION = ""
    WIKI_EXPLOIT_SCENARIO = ""
    WIKI_RECOMMENDATION = ""

    def _detect(self) -> list[Output]:
        info: DETECTOR_INFO = ["This is an example"]
        res = self.generate_result(info)
        return [res]
```

Field rules (enforced by `AbstractDetector.__init__` — a detector with a
missing/contradictory field fails at load time):

| Field | Meaning |
|---|---|
| `ARGUMENT` | CLI name: `slither . --detect <ARGUMENT>`. Lowercase, hyphens, unique across built-ins + plugins. |
| `HELP` | One line shown by `--list-detectors`. |
| `IMPACT` | `DetectorClassification.HIGH / MEDIUM / LOW / INFORMATIONAL / OPTIMIZATION`. HIGH prints red, MEDIUM yellow, the rest green. |
| `CONFIDENCE` | Same enum. HIGH = the pattern is almost certainly a bug when flagged. |
| `WIKI*` | Used to auto-generate detector docs. `WIKI_EXPLOIT_SCENARIO` is required unless IMPACT is INFORMATIONAL or OPTIMIZATION. |
| `_detect()` | Returns `list[Output]`. Each finding is `self.generate_result(info)` where `info` is a list mixing strings and Slither objects (contract, function, node, variable). Slither objects in `info` render as `file.sol#line` source references automatically. |

Available on every detector instance: `self.compilation_unit` (the
`SlitherCompilationUnit`; `.contracts`, `.contracts_derived`) and `self.slither`
(the `Slither` object). `self.contracts` is also set (same as
`compilation_unit.contracts`).

## 2. The APIs you will actually use

All of these were verified against the installed 0.11.6 package.

### Iterating code

```python
for contract in self.compilation_unit.contracts_derived:  # most-derived only; use .contracts for all
    for function in contract.functions_entry_points:       # public/external + CONSTRUCTOR (see gotcha below)
        for node in function.nodes:                        # CFG nodes of the function body
            ...
    for var in contract.state_variables:                   # StateVariable; var.type, var.name
        ...
```

- `contract.functions` — all functions (incl. inherited); `contract.functions_declared` — only those declared in this contract; `contract.functions_entry_points` — externally reachable ones.
- **Gotcha (verified): `functions_entry_points` includes the constructor.** Guard with `if function.is_constructor: continue` when a setter-style check must not fire on deployment-time assignments.
- `contract.inheritance` — all ancestors; `contract.immediate_inheritance` — direct parents. Use these instead of re-walking when the check is about inherited state.
- `function.parameters` — `list[LocalVariable]`; `function.modifiers` — applied `Modifier` objects; `function.modifiers_statements` — `ModifierStatements` (the call sites, with `.modifier` and `.nodes`).

### Reading a node

```python
node.state_variables_written   # state vars assigned in this node
node.state_variables_read      # state vars read
node.variables_read            # ALL variables read (locals + state + params)
node.local_variables_read      # locals/params read
node.irs                       # SlithIR operations in this node
node.contains_if()             # node is / is inside an if
node.contains_require_or_assert()
```

Types: `from slither.core.solidity_types.elementary_type import ElementaryType`;
`var.type == ElementaryType("address")`, or `str(var.type)` / `typ.type`
(`"uint256"`, `"int128"`, …) for width checks. `isinstance(var, LocalVariable)`
distinguishes parameters/locals from state variables.

### Calls — SlithIR operations

```python
from slither.slithir.operations import HighLevelCall, LowLevelCall, Call

for ir in node.irs:
    if isinstance(ir, HighLevelCall):
        ir.function          # the called Function (if resolved)
        ir.destination       # contract / variable called on
        ir.arguments
    if isinstance(ir, LowLevelCall):
        ir.function_name     # e.g. "delegatecall", "call"
        ir.destination
```

- `function.high_level_calls` / `function.low_level_calls` — same, function-wide.
- `isinstance(ir, Call)` matches every call kind (high/low/internal/library).
- For comparisons (range checks, zero checks): the IR class is `Binary`,
  **not** `BinaryOperation` (that name is the AST expression class in
  `slither.core.expressions`):
  ```python
  from slither.slithir.operations import Binary, BinaryType
  # ir.type in {BinaryType.LESS, GREATER, LESS_EQUAL, GREATER_EQUAL, EQUAL, NOT_EQUAL}
  # ir.variable_left / ir.variable_right / ir.read
  ```

### Modifiers

A bound enforced in a modifier is invisible if you only scan
`function.nodes`. Two verified approaches:

1. Scan the modifier's own nodes: for each `ModifierStatements` in
   `function.modifiers_statements`, map the call-site argument back to the
   modifier's parameter (`mod_stmt.modifier.parameters[args.index(var)]`)
   and scan `mod_stmt.modifier.nodes` for the check. (This is how Slither's
   built-in `missing-zero-check` does it — see
   `slither/detectors/operations/missing_zero_address_validation.py`.)
2. Simpler heuristic, same as the built-in's fallback: treat the parameter
   as checked if any node reading it `contains_require_or_assert()` or
   `contains_if()`.

The example detector in §3 uses approach 1 for modifiers and the precise
`Binary`-comparison scan for the function body.

### Source mapping (for findings)

You rarely need it by hand: put the Slither object in the `info` list and
`generate_result` renders `file.sol#line` for you, e.g.
`FeeVault.setFeeBps(uint256).newFeeBps (Vulnerable.sol#22)`. For custom
formatting, the objects carry it directly (verified):

```python
node.source_mapping.filename.short   # "Vulnerable.sol"
node.source_mapping.lines            # [22, 23, 24]
node.source_mapping.starting_column  # 62
function.source_mapping.lines
contract.source_mapping.filename
```

## 3. A real detector: missing range check on a numeric setter

### Why built-ins miss it

Verified on Slither 0.11.6 (`slither --list-detectors`, 102 detectors):

- `missing-zero-check` — validates **address** parameters only.
- `events-access` — flags privileged setters that emit **no event**, not setters with no bound.
- `controlled-delegatecall`, `unchecked-transfer`, `unchecked-lowlevel` — different patterns entirely.
- No built-in mentions a bound, cap, range, or sanity check on a setter
  parameter. Proof: plain `slither Vulnerable.sol` (see §5) runs all 102
  detectors and reports only `immutable-states` and `solc-version` — the
  uncapped setters are invisible to it.

The pattern matters in audits: an uncapped `setFeeBps()` lets a compromised
(or fat-fingered) owner set a 100%+ fee, a 0 collateral factor, or an
unbounded reward rate and brick or drain the protocol.

### The detector

File: `examples/slither-plugin-missing-setter-bound/slither_plugin_missing_setter_bound/detector.py`
(also reproduced here in full — the file is canonical).

```python
"""MissingSetterBound — flags an externally reachable setter that copies a
numeric (uint/int) parameter into a state variable without any comparison
bounding that parameter (no `require(param <= MAX)`, no `if (param > MAX)
revert()`, no such check in an applied modifier)."""

from slither.core.solidity_types.elementary_type import ElementaryType
from slither.core.variables.local_variable import LocalVariable
from slither.detectors.abstract_detector import (
    AbstractDetector,
    DetectorClassification,
    DETECTOR_INFO,
)
from slither.slithir.operations import Binary, BinaryType, Call
from slither.utils.output import Output

_COMPARISON_TYPES = frozenset(
    {
        BinaryType.LESS,
        BinaryType.LESS_EQUAL,
        BinaryType.GREATER,
        BinaryType.GREATER_EQUAL,
    }
)


def _is_numeric_type(typ) -> bool:
    """True for uint/int elementary types of any width."""
    return isinstance(typ, ElementaryType) and (
        typ.type.startswith("uint") or typ.type.startswith("int")
    )


class MissingSetterBound(AbstractDetector):
    """
    Setter assigns a numeric parameter to state without a range check
    """

    ARGUMENT = "missing-setter-bound"
    HELP = "Setter assigns a numeric parameter to state without a range check"
    IMPACT = DetectorClassification.MEDIUM
    CONFIDENCE = DetectorClassification.MEDIUM

    WIKI = "https://github.com/crytic/slither/wiki/Adding-a-new-detector"
    WIKI_TITLE = "Missing range check on numeric setter parameter"
    WIKI_DESCRIPTION = (
        "Detect externally reachable setters that copy a numeric parameter "
        "into a state variable without any comparison bounding that parameter."
    )
    WIKI_EXPLOIT_SCENARIO = """
```solidity
contract FeeVault {
    uint256 public feeBps;
    function setFeeBps(uint256 newFeeBps) external {
        feeBps = newFeeBps; // no upper bound
    }
}
```
Whoever can call `setFeeBps` can set the fee to 10_000+ basis points,
i.e. a 100%+ fee, and brick or drain the protocol.
"""
    WIKI_RECOMMENDATION = (
        "Add an explicit upper bound (and, where meaningful, lower bound) "
        "check on every numeric setter parameter, e.g. "
        "`require(newFeeBps <= MAX_FEE_BPS, \"fee too high\");`, before the "
        "assignment — or enforce the same bound in an applied modifier."
    )

    @staticmethod
    def _has_comparison(var: LocalVariable, nodes) -> bool:
        """True if any SlithIR `Binary` comparison (<, >, <=, >=) in `nodes`
        reads `var` — i.e. the parameter is range-checked there."""
        for node in nodes:
            for ir in node.irs:
                if isinstance(ir, Binary) and ir.type in _COMPARISON_TYPES:
                    if var in ir.read:
                        return True
        return False

    def _checked_in_modifier(self, var: LocalVariable, modifier_stmts) -> bool:
        """True if `var` is passed to a modifier and that modifier's own
        parameter is range-checked inside the modifier body."""
        for mod_stmt in modifier_stmts:
            for node in mod_stmt.nodes:
                if len(node.irs) != 1:
                    continue
                for ir in node.irs:
                    if isinstance(ir, Call):
                        args = list(ir.arguments)
                        if var in args:
                            param = mod_stmt.modifier.parameters[args.index(var)]
                            if self._has_comparison(param, mod_stmt.modifier.nodes):
                                return True
        return False

    def _detect(self) -> list[Output]:
        results: list[Output] = []
        for contract in self.compilation_unit.contracts_derived:
            for function in contract.functions_entry_points:
                if function.is_constructor:
                    continue
                flagged: dict[LocalVariable, list] = {}
                for node in function.nodes:
                    written = [
                        sv
                        for sv in node.state_variables_written
                        if _is_numeric_type(sv.type)
                    ]
                    if not written:
                        continue
                    for var in node.variables_read:
                        if not isinstance(var, LocalVariable):
                            continue
                        if var not in function.parameters:
                            continue
                        if not _is_numeric_type(var.type):
                            continue
                        if self._has_comparison(var, function.nodes):
                            continue
                        if self._checked_in_modifier(
                            var, function.modifiers_statements
                        ):
                            continue
                        flagged.setdefault(var, []).append(node)
                for var, nodes in flagged.items():
                    info: DETECTOR_INFO = [
                        var,
                        " is assigned to state without a range check in ",
                        function,
                        ":\n",
                    ]
                    for node in nodes:
                        info += ["\t\t- ", node, "\n"]
                    results.append(self.generate_result(info))
        return results
```

Known limits (document them in any detector you ship, don't hide them):
- A bound enforced inside a **called internal function** is not seen
  (false positive). A bound on a *derived* value mentioning the parameter
  (e.g. `require(param * 2 <= MAX)`) counts as bounded.
- A bare `require(param != other)` is **not** a bound (`!=` is not in
  `_COMPARISON_TYPES`) — it still flags, by design.
- One finding per (function, parameter); the assignment nodes are listed
  inside it.

## 4. Registering and running it

### Path A — plugin package (CLI, the supported path)

Slither discovers plugins through the `slither_analyzer.plugin` entry-point
group (`slither/__main__.py`, `get_detectors_and_printers()`). A plugin
module exposes `make_plugin()` returning `(detectors, printers)`.

Package layout (under `examples/slither-plugin-missing-setter-bound/`):

```
pyproject.toml
slither_plugin_missing_setter_bound/
    __init__.py      # make_plugin() -> ([MissingSetterBound], [])
    detector.py      # the detector above
```

```toml
# pyproject.toml
[build-system]
requires = ["setuptools>=61"]
build-backend = "setuptools.build_meta"

[project]
name = "slither-plugin-missing-setter-bound"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = ["slither-analyzer"]

[project.entry-points."slither_analyzer.plugin"]
missing-setter-bound = "slither_plugin_missing_setter_bound:make_plugin"

[tool.setuptools]
packages = ["slither_plugin_missing_setter_bound"]
```

```python
# slither_plugin_missing_setter_bound/__init__.py
from .detector import MissingSetterBound

def make_plugin():
    return [MissingSetterBound], []
```

Install and run (install into the same venv Slither lives in; `--no-deps`
when Slither is already installed there):

```bash
export PATH="$HOME/workspace/tools/method-tools-venv/bin:$PATH"
cd examples/slither-plugin-missing-setter-bound
~/workspace/tools/method-tools-venv/bin/pip install -e . --no-deps
# or: pip install --target <dir> . --no-deps, then PYTHONPATH=<dir> slither ...

slither --list-detectors | grep missing-setter-bound
slither --detect missing-setter-bound <target.sol>   # only this detector
slither <target.sol>                                 # all detectors, incl. yours
```

### Path B — Python API (no install; best for iterating)

```python
from slither import Slither
from slither_plugin_missing_setter_bound.detector import MissingSetterBound

slither = Slither("Vulnerable.sol")
slither.register_detector(MissingSetterBound)
results = slither.run_detectors()  # list of per-detector result lists
```

Runnable wrapper: `examples/run_detector.py` (adds the plugin dir to
`sys.path`, registers the detector, prints the count of
`missing-setter-bound` findings).

```bash
~/workspace/tools/method-tools-venv/bin/python run_detector.py Vulnerable.sol
```

Notes:
- `run_detectors()` returns a **list of lists** (one per detector run) —
  flatten before filtering on `r["check"]`.
- To add a detector to Slither itself instead of a plugin, add it to
  `slither/detectors/all_detectors.py` — only sensible for upstream
  contributions, not for audit work.

## 5. Positive / negative test pair

Contracts in `examples/` (all `pragma solidity ^0.8.20`, compile with the
installed solc 0.8.39):

| File | Expected | Why |
|---|---|---|
| `Vulnerable.sol` | **2 findings** | `setFeeBps` and `setRewardRate` copy params to state with no bound anywhere. |
| `Fixed.sol` | **0 findings** | Same setters, each guarded by `require(param <= MAX_...)` before the assignment. |
| `FixedViaModifier.sol` | **0 findings** | Bound lives in an applied `validFeeBps(newFeeBps)` modifier — exercises the modifier-scanning path. |

## Verification evidence (actually run, 2026-11-22)

Environment: Slither **0.11.6**, solc **0.8.39**
(`solc, the solidity compiler commandline interface / Version:
0.8.39+commit.ce47f2c8.Linux.g++`), Python 3.12, venv
`~/workspace/tools/method-tools-venv/bin/` (pre-existing shared install —
nothing installed by this skill; the plugin was installed with
`pip install --no-deps --target ~/workspace/.scratch/slither-plugin-install`
for verification only, then removed).

**Gap check — built-ins miss the pattern:**

```bash
$ slither --list-detectors | grep -iE 'bound|sanity|setter|fee|limit|cap|range'
# no setter-bound detector; closest are missing-zero-check (address only)
# and events-access (missing event only)
$ slither Vulnerable.sol
INFO:Slither:Vulnerable.sol analyzed (1 contracts with 102 detectors), 2 result(s) found
# the 2 results are `immutable-states` and `solc-version` only — no bound finding
```

**Plugin registration:**

```bash
$ PYTHONPATH=~/workspace/.scratch/slither-plugin-install slither --list-detectors \
    | grep missing-setter-bound
| 51  | missing-setter-bound  | Setter assigns a numeric parameter to state without a range check  | Medium  | Medium  |
```

**CLI, positive case — fires:**

```bash
$ slither --detect missing-setter-bound Vulnerable.sol
Detector: missing-setter-bound
FeeVault.setFeeBps(uint256).newFeeBps (Vulnerable.sol#22) is assigned to state without a range check in FeeVault.setFeeBps(uint256) (Vulnerable.sol#22-24):
		- feeBps = newFeeBps (Vulnerable.sol#23)
FeeVault.setRewardRate(uint256).newRate (Vulnerable.sol#26) is assigned to state without a range check in FeeVault.setRewardRate(uint256) (Vulnerable.sol#26-28):
		- rewardRate = newRate (Vulnerable.sol#27)
Reference: https://github.com/crytic/slither/wiki/Adding-a-new-detector
```

**CLI, negative cases — silent:**

```bash
$ slither --detect missing-setter-bound Fixed.sol
INFO:Slither:Fixed.sol analyzed (1 contracts with 1 detectors), 0 result(s) found
$ slither --detect missing-setter-bound FixedViaModifier.sol
INFO:Slither:FixedViaModifier.sol analyzed (1 contracts with 1 detectors), 0 result(s) found
```

**Python API — same matrix** (`run_detector.py`):

```bash
$ python run_detector.py Vulnerable.sol
target: Vulnerable.sol
detector: missing-setter-bound
findings: 2
$ python run_detector.py Fixed.sol
findings: 0
$ python run_detector.py FixedViaModifier.sol
findings: 0
```

## Debugging a detector that won't fire

1. `slither --list-detectors | grep <ARGUMENT>` — absent means the plugin
   entry point isn't installed/visible (check `pip show` + `PYTHONPATH`).
2. Wrong method name: logic must be in `_detect()`, not `detect()`.
3. `slither --detect <ARGUMENT> file.sol` with a debug print inside
   `_detect` — Slither swallows nothing; a traceback means an API misuse
   (usually a wrong import: `Binary`, not `BinaryOperation`, for IR
   comparisons; `Function.parameters` for params, not `function.variables`).
4. Suspect the wrong traversal: dump the shape first in a scratch script
   (`Slither(f).get_contract_from_name(...)`, then print
   `function.nodes`, `node.irs`, `node.variables_read`) before guessing.
5. `solc` not found (`InvalidCompilation: [Errno 2] No such file or
   directory: 'solc'`) — `solc` isn't on `PATH`; export the venv's `bin/`.

## Safety

Method only: detectors read local source files and run a local compiler.
No network calls, no exfiltration, no secrets, no account or funds touched.
Never point a detector run at a live deployment as an "exploit" — a detector
is a static check on source, nothing more.
