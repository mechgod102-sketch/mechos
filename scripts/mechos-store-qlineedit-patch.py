#!/usr/bin/env python3
"""Ensure MechOS Unified/Creator Store has its required QLineEdit import."""
from __future__ import annotations

import ast
import sys
from pathlib import Path

MARKER = "MECHOS_CREATOR_STORE_QLINEEDIT_IMPORT_V1"
IMPORT_LINE = f"from PyQt6.QtWidgets import QLineEdit  # {MARKER}"


def has_qlineedit_import(tree: ast.AST) -> bool:
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "PyQt6.QtWidgets":
            if any(alias.name in {"QLineEdit", "*"} for alias in node.names):
                return True
    return False


def patch(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    if "QLineEdit" not in text:
        compile(text, str(path), "exec")
        return False

    tree = ast.parse(text, filename=str(path))
    if has_qlineedit_import(tree):
        compile(text, str(path), "exec")
        return False

    # Future imports must stay before normal imports. Insert immediately after
    # the final __future__ import (or after a shebang/encoding header if there
    # is no future import).
    lines = text.splitlines(keepends=True)
    insert_at = 0
    for node in getattr(tree, "body", []):
        if isinstance(node, ast.ImportFrom) and node.module == "__future__":
            insert_at = max(insert_at, int(getattr(node, "end_lineno", node.lineno)))

    if insert_at == 0:
        if lines and lines[0].startswith("#!"):
            insert_at = 1
        if insert_at < len(lines) and "coding" in lines[insert_at][:80]:
            insert_at += 1

    lines.insert(insert_at, IMPORT_LINE + "\n")
    new_text = "".join(lines)
    new_tree = ast.parse(new_text, filename=str(path))
    if not has_qlineedit_import(new_tree):
        raise SystemExit(f"{path}: failed to install QLineEdit import")
    compile(new_text, str(path), "exec")
    path.write_text(new_text, encoding="utf-8")
    return True


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {Path(sys.argv[0]).name} <python-file>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    if not path.is_file():
        print(f"{path}: file not found", file=sys.stderr)
        return 2
    changed = patch(path)
    print(f"[MechOS Store] QLineEdit import {'installed' if changed else 'verified'}: {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
