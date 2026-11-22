#!/usr/bin/env python3
"""Run MissingSetterBound through Slither's Python API (no plugin install).

Usage:
    <venv>/bin/python run_detector.py <contract.sol>

Prints how many `missing-setter-bound` findings Slither produced.
Exit code 0 = ran cleanly (findings are reported on stdout, not via exit code).
"""
import os
import sys

sys.path.insert(
    0,
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "slither-plugin-missing-setter-bound",
    ),
)

from slither import Slither  # noqa: E402
from slither_plugin_missing_setter_bound.detector import MissingSetterBound  # noqa: E402


def main() -> None:
    target = sys.argv[1]
    slither = Slither(target)
    slither.register_detector(MissingSetterBound)
    results = slither.run_detectors()
    # run_detectors() returns one list of result dicts per detector run.
    flat = [
        r for group in results for r in (group if isinstance(group, list) else [group])
    ]
    mine = [r for r in flat if r.get("check") == MissingSetterBound.ARGUMENT]
    print(f"target: {target}")
    print(f"detector: {MissingSetterBound.ARGUMENT}")
    print(f"findings: {len(mine)}")
    for r in mine:
        print(f"  - {r.get('description', '').strip()}")


if __name__ == "__main__":
    main()
