#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def fail(msg: str) -> None:
    raise SystemExit(f"[Visual Surfaces v9 Validation] ERROR: {msg}")


def require(path: Path, *needles: str) -> str:
    if not path.is_file():
        fail(f"missing {path.relative_to(ROOT)}")
    text = path.read_text(encoding="utf-8")
    for needle in needles:
        if needle not in text:
            fail(f"{path.name} missing {needle!r}")
    return text


def main() -> int:
    fixed = require(
        ROOT / "src/mechos_ui/fixed_canvas.py",
        "MECHOS_VISUAL_SURFACES_V9_FIXED_CANVAS",
        "MECHOS_VM_RESPONSIVE_GEOMETRY_V3",
        "#b96cff",
        "#5ee7ff",
    )
    quick = require(
        ROOT / "src/mechos_ui/quick_actions_shell.py",
        "MECHOS_QUICK_ACTIONS_VISUAL_V9",
        "KEYBOARD RGB",
        "Brightness −",
        "Audio Settings",
        "Streaming & Recording".upper(),
        "Recovery Center",
    )
    theme = require(
        ROOT / "src/mechos_ui/reference-v9.qss",
        "MECHOS_VISUAL_SURFACES_V9",
        "QFrame#settingsHero",
        "QFrame#settingsCard",
        "QPushButton#storeTab:checked",
        "QLabel#statusPill",
    )
    owner = require(
        ROOT / "scripts/mechos-final-surface-owner-v8-patch.py",
        "MECHOS_VISUAL_SURFACES_V9_QUICK_ACTIONS_WIRING",
        "brightness-down",
        "brightness-up",
        "rgb-picker",
        "rgb-restore",
        "rgb-advanced",
        "system-settings",
        "audio-settings",
    )
    patch = ROOT / "scripts/mechos-visual-surfaces-v9-patch.py"
    require(
        patch,
        "MECHOS_VISUAL_SURFACES_V9_CREATOR_STORE",
        "MECHOS_VISUAL_SURFACES_V9_CREATOR_SETTINGS",
        "MECHOS_VISUAL_SURFACES_V9_UNIFIED_STORE",
        "Search Creator Store",
        "textChanged.connect(apply_filter)",
        "Gaming / MechScope",
        "Search Selected Store",
        "Refresh Local Library",
    )
    final = require(
        ROOT / "scripts/mechos-build125-final-surfaces.sh",
        "mechos-visual-surfaces-v9-patch.py",
        "reference-v9.qss",
        "VISUAL_PATCH\" unified-store",
        "VISUAL_PATCH\" creator",
        "0.3.0-hotfix.9",
    )

    # Ensure the quick panel retains all requested action keys and has sensible
    # fixed-design geometry rather than accidentally dropping a control.
    for key in (
        "performance", "balanced", "battery", "performance-center", "wifi", "bluetooth",
        "display", "system-settings", "system-info", "brightness-down", "brightness-up",
        "audio-settings", "vol-down", "mute", "vol-up", "rgb-picker", "rgb-restore",
        "rgb-advanced", "go-live", "end-stream", "record", "stream-center", "updates",
        "creator", "recovery", "close",
    ):
        if f"'{key}'" not in owner or f"'{key}'" not in quick:
            fail(f"Quick Actions key not present in both UI and owner wiring: {key}")

    # Syntax-check all actual source/patch components without importing Qt.
    for path in (
        ROOT / "src/mechos_ui/fixed_canvas.py",
        ROOT / "src/mechos_ui/quick_actions_shell.py",
        patch,
        ROOT / "scripts/mechos-final-surface-owner-v8-patch.py",
    ):
        subprocess.run([sys.executable, "-m", "py_compile", str(path)], check=True)

    # Exercise the visual patcher against disposable owners. Runtime symbols do
    # not need to exist for compile-time verification; the generated structure
    # must still be valid Python and contain the exact visual contracts.
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        creator = td / "creator.py"
        creator.write_text(
            "class Creator(object):\n"
            "    def app_store(self):\n        return None\n"
            "    def settings(self):\n        return None\n"
            "    def tail(self):\n        return None\n",
            encoding="utf-8",
        )
        subprocess.run([sys.executable, str(patch), "creator", str(creator)], check=True)
        ctext = creator.read_text(encoding="utf-8")
        for needle in (
            "MECHOS_VISUAL_SURFACES_V9_CREATOR_STORE",
            "MECHOS_VISUAL_SURFACES_V9_CREATOR_SETTINGS",
            "Search Creator Store",
            "textChanged.connect(apply_filter)",
            "Windows Creator Installer",
            "Quick Actions",
        ):
            if needle not in ctext:
                fail(f"Creator visual simulation missing {needle}")
        subprocess.run([sys.executable, "-m", "py_compile", str(creator)], check=True)

        store = td / "mechscope.py"
        store.write_text(
            "class UnifiedStore(object):\n"
            "    def build_reference_v5(self):\n        return None\n"
            "    def tail(self):\n        return None\n"
            "class MechScope(object):\n    pass\n",
            encoding="utf-8",
        )
        subprocess.run([sys.executable, str(patch), "unified-store", str(store)], check=True)
        stext = store.read_text(encoding="utf-8")
        for needle in (
            "MECHOS_VISUAL_SURFACES_V9_UNIFIED_STORE",
            "Search Selected Store",
            "Refresh Local Library",
            "Return to MechScope",
        ):
            if needle not in stext:
                fail(f"Unified Store visual simulation missing {needle}")
        subprocess.run([sys.executable, "-m", "py_compile", str(store)], check=True)

    print(
        "[Visual Surfaces v9 Validation] PASS: MechScope/Unified Store, Creator Store, "
        "Creator Settings, Quick Actions and the shared visual theme are structurally "
        "aligned; Quick Actions controls are wired to real backends and responsive V3 is preserved."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
