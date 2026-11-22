"""Slither plugin entry point: exposes MissingSetterBound to the CLI."""

from .detector import MissingSetterBound

__all__ = ["MissingSetterBound", "make_plugin"]


def make_plugin():
    """Slither calls this via the `slither_analyzer.plugin` entry point.

    Returns (detectors, printers). This plugin ships detectors only.
    """
    return [MissingSetterBound], []
