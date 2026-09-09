#!/usr/bin/env python3
# MECHOS_HOTFIX35_STORE_ROUTE_PATCH
from __future__ import annotations

from pathlib import Path
import sys

MARKER = "# MECHOS_MECHSCOPE_UNIFIED_STORE_ROUTE_V35"


def patch(path: Path) -> None:
    if not path.is_file():
        raise SystemExit(f"MechScope source runtime missing: {path}")
    text = path.read_text(encoding="utf-8")
    if "MECHOS_MECHSCOPE_SOURCE_RUNTIME_V33" not in text:
        raise SystemExit("HF33 source-owned runtime marker missing")

    if MARKER not in text:
        text = text.replace(
            "# MECHOS_MECHSCOPE_SOURCE_RUNTIME_V33\n",
            "# MECHOS_MECHSCOPE_SOURCE_RUNTIME_V33\n" + MARKER + "\n",
            1,
        )

    old_open = '''        choices = (\n            ("/usr/local/bin/mechos-discovery-store", []),\n            ("/usr/local/bin/mechos-discover-store", []),\n            ("/usr/local/bin/mechos-unified-store", []),\n            ("plasma-discover", []),\n        )'''
    new_open = '''        choices = (\n            ("/usr/local/bin/mechos-unified-store", []),\n            ("/usr/local/bin/mechos-discovery-store", []),\n            ("/usr/local/bin/mechos-discover-store", []),\n            ("plasma-discover", []),\n        )'''
    if old_open in text:
        text = text.replace(old_open, new_open, 1)
    elif new_open not in text:
        raise SystemExit("could not locate dashboard store routing block")

    old_handoff = '''        for program in (\n            "/usr/local/bin/mechos-discovery-store",\n            "/usr/local/bin/mechos-discover-store",\n            "/usr/local/bin/mechos-unified-store",\n            "plasma-discover",\n        ):'''
    new_handoff = '''        for program in (\n            "/usr/local/bin/mechos-unified-store",\n            "/usr/local/bin/mechos-discovery-store",\n            "/usr/local/bin/mechos-discover-store",\n            "plasma-discover",\n        ):'''
    if old_handoff in text:
        text = text.replace(old_handoff, new_handoff, 1)
    elif new_handoff not in text:
        raise SystemExit("could not locate --store compatibility routing block")

    compile(text, str(path), "exec")

    open_start = text.index("    def open_store(self) -> None:")
    open_end = text.index("\n    def launch_vr", open_start)
    open_block = text[open_start:open_end]
    if open_block.index("/usr/local/bin/mechos-unified-store") > open_block.index("/usr/local/bin/mechos-discovery-store"):
        raise SystemExit("dashboard routing still prefers Discovery over Unified Store")

    handoff_start = text.index("    def _handoff(self):")
    handoff_end = text.index("\n\ndef main", handoff_start)
    handoff_block = text[handoff_start:handoff_end]
    if handoff_block.index("/usr/local/bin/mechos-unified-store") > handoff_block.index("/usr/local/bin/mechos-discovery-store"):
        raise SystemExit("--store routing still prefers Discovery over Unified Store")

    path.write_text(text, encoding="utf-8")


def main() -> int:
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "/usr/local/libexec/mechos-mechscope-source-runtime-v33")
    patch(target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
