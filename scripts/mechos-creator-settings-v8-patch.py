#!/usr/bin/env python3
"""Reassert the currently generated Creator Settings page exactly."""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "# MECHOS_CREATOR_SETTINGS_V8_EXACT"


def fail(msg: str) -> None:
    raise SystemExit(f"[MechOS Creator Settings v8] {msg}")


def main() -> int:
    if len(sys.argv) != 2:
        fail("usage: mechos-creator-settings-v8-patch.py <creator-owner.py>")
    path = Path(sys.argv[1])
    if not path.is_file():
        fail(f"missing Creator owner: {path}")
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        return 0

    start = text.find("    def settings(self):")
    if start < 0:
        fail("Creator.settings() not found")
    end = text.find("\n    def ", start + 8)
    if end < 0:
        fail("end of Creator.settings() not found")

    replacement = r'''    def settings(self):
        # MECHOS_CREATOR_SETTINGS_V8_EXACT
        s,v=self.scroll(); self.section(v,"CREATOR SETTINGS")
        for name,cmd in [
            ("System Settings",["systemsettings"]),
            ("Performance Center",["/usr/local/bin/mechos-performance-center"]),
            ("Update Center",["/usr/local/bin/mechos-update-center"]),
            ("Creator Folder Setup",["/usr/local/bin/mechos-creator-setup"]),
            ("Windows Creator Installer",[APP,"windows-installer"]),
        ]:
            b=QPushButton(name); b.setObjectName("action"); b.clicked.connect(lambda _,c=cmd:spawn(c)); v.addWidget(b)
        v.addStretch(); return s
'''
    patched = text[:start] + replacement.rstrip() + "\n" + text[end:]
    compile(patched, str(path), "exec")
    path.write_text(patched, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
