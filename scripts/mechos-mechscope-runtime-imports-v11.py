#!/usr/bin/env python3
"""Ensure generated MechScope storefront code has its runtime Qt imports.

py_compile only proves syntax. Hotfix 9/10 add GUI methods late in the build and
older installed MechScope owners can have a narrower import list. This guard
adds the harmless runtime imports required by the current Unified Store before
MechScope is launched, then compiles the result.
"""
from __future__ import annotations

import ast
import sys
from pathlib import Path

MARKER = "MECHOS_MECHSCOPE_RUNTIME_IMPORTS_V11"
BLOCK = f"""# {MARKER}
from pathlib import Path
import shutil
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QPixmap
from PyQt6.QtWidgets import (
    QDialog, QFrame, QGridLayout, QHBoxLayout, QLabel, QLineEdit,
    QMainWindow, QMessageBox, QPushButton, QStackedWidget, QVBoxLayout,
    QWidget,
)
"""


def insertion_line(tree: ast.AST, lines: list[str]) -> int:
    pos = 0
    for node in getattr(tree, "body", []):
        if isinstance(node, ast.ImportFrom) and node.module == "__future__":
            pos = max(pos, int(getattr(node, "end_lineno", node.lineno)))
    if pos == 0:
        if lines and lines[0].startswith("#!"):
            pos = 1
        if pos < len(lines) and "coding" in lines[pos][:80]:
            pos += 1
    return pos


def patch(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    compile(text, str(path), "exec")
    if MARKER in text:
        return False

    # Only Python MechScope owners are patched. A native executable should
    # never be rewritten as text by an update hotfix.
    first = text.splitlines()[0] if text.splitlines() else ""
    looks_python = "python" in first or "class MechScope(" in text or "class UnifiedStore(" in text
    if not looks_python:
        raise SystemExit(f"{path}: target does not look like Python MechScope source")

    tree = ast.parse(text, filename=str(path))
    lines = text.splitlines(keepends=True)
    pos = insertion_line(tree, lines)
    lines.insert(pos, BLOCK + "\n")
    patched = "".join(lines)
    compile(patched, str(path), "exec")
    path.write_text(patched, encoding="utf-8")
    return True


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <mechscope.py>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"{path}: file not found", file=sys.stderr)
        return 2
    changed = patch(path)
    print(f"[MechOS Hotfix 11] runtime Qt imports {'installed' if changed else 'verified'}: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
