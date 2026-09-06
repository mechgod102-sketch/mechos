#!/usr/bin/env python3
"""Activate the Hotfix 22 real-icon resolver in the live Creator owner."""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "MECHOS_HOTFIX22_CREATOR_REAL_ICONS_OWNER_V1"


def fail(message: str) -> None:
    raise SystemExit(f"[MechOS Creator real icons v22] {message}")


def patch(path: Path) -> None:
    if not path.is_file():
        fail(f"Creator owner missing: {path}")
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        compile(text, str(path), "exec")
        return

    anchor = "    shell = _mechos_surface_v10_module('creator_visual_shell_v10.py', 'mechos_creator_visual_shell_v10')\n"
    if anchor not in text:
        fail("Hotfix 10 Creator visual owner anchor not found")

    replacement = (
        anchor
        + "    # " + MARKER + "\n"
        + "    icons = _mechos_surface_v10_module('creator_real_icons_v22.py', 'mechos_creator_real_icons_v22')\n"
        + "    icons.install(shell)\n"
    )
    text = text.replace(anchor, replacement, 1)
    compile(text, str(path), "exec")
    if "icons.install(shell)" not in text:
        fail("real-icon activation was not inserted")
    path.write_text(text, encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        fail("usage: mechos-creator-real-icons-owner-v22-patch.py <creator-owner.py>")
    patch(Path(sys.argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
