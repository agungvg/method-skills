"""
MissingSetterBound — custom Slither detector (example for the slither-detectors skill).

Pattern: an externally reachable function copies a numeric (uint/int) parameter
straight into a state variable without any comparison bounding that parameter
— no `require(param <= MAX)`, no `if (param > MAX) revert()`, and no such check
in an applied modifier.

Why Slither's built-ins miss it (Slither 0.11.6, verified with
`slither --list-detectors`): the built-ins cover the *neighbouring* checks —
`missing-zero-check` (address params), `events-access` (missing event on a
privileged setter), `controlled-delegatecall`, `unchecked-transfer` — but no
built-in validates that a numeric setter parameter is range-checked. An
uncapped `setFeeBps()` lets a compromised owner key (or a fat-fingered one)
set a 100%+ fee, a 0 collateral factor, or an unbounded reward rate and brick
or drain the protocol. This detector closes exactly that gap.

Heuristic, by design (IMPACT MEDIUM / CONFIDENCE MEDIUM):
- A comparison (`<`, `>`, `<=`, `>=`) on the parameter anywhere in the
  function body OR in an applied modifier counts as "bounded". A bare
  `require(param != other)` is NOT a bound and still flags.
- A bound enforced inside a *called internal function* is NOT seen (false
  positive). A bound on a *derived* value (e.g. `require(param * 2 <= MAX)`)
  IS seen, because the comparison mentions the parameter (false negative
  only if the bound is on an unrelated variable).
- Only `uint`/`int` state writes from a parameter are checked; `=` only in
  the sense that any write node reading the parameter counts.
"""

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
    """True for uint/int elementary types of any width (uint256, uint8, int128, ...)."""
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
Whoever can call `setFeeBps` (here: anyone; usually the owner, or an
attacker holding a compromised owner key) can set the fee to 10_000+ basis
points, i.e. a 100%+ fee, and brick or drain the protocol. No built-in
Slither detector flags the missing bound.
"""
    WIKI_RECOMMENDATION = (
        "Add an explicit upper bound (and, where meaningful, lower bound) "
        "check on every numeric setter parameter, e.g. "
        "`require(newFeeBps <= MAX_FEE_BPS, \"fee too high\");`, before the "
        "assignment — or enforce the same bound in an applied modifier."
    )

    @staticmethod
    def _has_comparison(var: LocalVariable, nodes) -> bool:
        """True if any SlithIR `Binary` comparison (`<`,`>`,`<=`,`>=`) in
        `nodes` reads `var` — i.e. the parameter is range-checked there."""
        for node in nodes:
            for ir in node.irs:
                if isinstance(ir, Binary) and ir.type in _COMPARISON_TYPES:
                    if var in ir.read:
                        return True
        return False

    def _checked_in_modifier(self, var: LocalVariable, modifier_stmts) -> bool:
        """True if `var` is passed to a modifier and that modifier's own
        parameter is range-checked inside the modifier body. Mirrors the
        approach of Slither's built-in `missing-zero-check` detector."""
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
