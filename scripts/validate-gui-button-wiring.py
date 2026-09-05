#!/usr/bin/env python3
"""Static GUI action-wiring gate for MechOS system surfaces.

This validator intentionally does not execute destructive/system actions. It
proves that visible Qt controls are wired to handlers, that MechScope's source
shell action keys are supplied by the runtime integration, and that the Update
Center recovery owner keeps every primary button connected.
"""
from __future__ import annotations

import ast
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(f"[GUI Button Validation] ERROR: {message}")


def read(rel: str) -> str:
    path = ROOT / rel
    if not path.is_file():
        fail(f"missing source: {rel}")
    return path.read_text(encoding="utf-8")


def parse(rel: str) -> ast.AST:
    text = read(rel)
    try:
        return ast.parse(text, filename=rel)
    except SyntaxError as exc:
        fail(f"Python syntax error in {rel}: {exc}")


def is_self_method(call: ast.Call, name: str) -> bool:
    fn = call.func
    return (
        isinstance(fn, ast.Attribute)
        and fn.attr == name
        and isinstance(fn.value, ast.Name)
        and fn.value.id == "self"
    )


# Shared button primitive: callbacks supplied by surfaces must reach Qt.
fixed = read("src/mechos_ui/fixed_canvas.py")
if "MECHOS_VM_RESPONSIVE_GEOMETRY_V3" not in fixed:
    fail("current responsive geometry V3 marker missing")
if "MECHOS_VM_RESPONSIVE_GEOMETRY_V2" not in fixed:
    fail("late Build 118 compatibility marker missing")
if "q.clicked.connect(fn)" not in fixed:
    fail("FixedCanvas.button no longer connects its callback")


# Live Installer: navigation, target selection, install mode, Repair and Install
# Now must all have an actual handler.
installer = read("src/mechos_ui/installer_shell.py")
installer_required = {
    "hotspot callback": "q.clicked.connect(fn)",
    "step navigation": "self.owner.nav_selected",
    "Repair": "self.owner.recovery",
    "Install Now": "self.owner.install",
    "Change Drive": "self.change_drive.clicked.connect(self.owner.open_partition_selector)",
    "install mode": "self.owner.set_mode",
}
for label, marker in installer_required.items():
    if marker not in installer:
        fail(f"Installer {label} button wiring missing")
for mode in ("clean", "keep", "custom"):
    if f"self.mode_button('{mode}'" not in installer:
        fail(f"Installer {mode} mode button missing")


# Creator Mode: every FixedCanvas button call must supply a callback expression.
# The active Creator Mode tab intentionally uses `lambda: None`; it is still a
# connected control and is allowed because selecting the already-active mode is
# a no-op by design.
creator_tree = parse("src/mechos_ui/creator_shell.py")
creator_buttons = 0
for node in ast.walk(creator_tree):
    if not isinstance(node, ast.Call) or not is_self_method(node, "button"):
        continue
    creator_buttons += 1
    callback = node.args[3] if len(node.args) >= 4 else None
    if callback is None:
        for kw in node.keywords:
            if kw.arg == "fn":
                callback = kw.value
                break
    if callback is None or (isinstance(callback, ast.Constant) and callback.value is None):
        fail(f"Creator Mode button at line {node.lineno} has no callback")
if creator_buttons < 15:
    fail(f"Creator Mode button scan found too few controls ({creator_buttons})")
creator = read("src/mechos_ui/creator_shell.py")
for marker in (
    'self.button("Creator Store"',
    'self.button("Performance"',
    'self.button("Refresh Updates"',
    'self.button("View Updates"',
    'self.button("Gaming Mode"',
    'self.button("Desktop Mode"',
    'self.button("MechScope"',
):
    if marker not in creator:
        fail(f"Creator Mode expected control missing: {marker}")


# MechScope source shell obtains callbacks from the runtime action map. Verify
# that every literal action key used by the source shell is supplied by the
# final native integration so a rendered button cannot silently become inert.
mech_tree = parse("src/mechscope/mechscope_shell.py")
mech_keys: set[str] = set()
for node in ast.walk(mech_tree):
    if not isinstance(node, ast.Call) or not is_self_method(node, "_button"):
        continue
    if node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str):
        mech_keys.add(node.args[0].value)
if not mech_keys:
    fail("MechScope source shell action keys were not found")
mech = read("src/mechscope/mechscope_shell.py")
if "fn = self.actions.get(key)" not in mech or "q.clicked.connect(fn)" not in mech:
    fail("MechScope source button helper does not connect action-map callbacks")
integration = read("scripts/mechos-native-ui-shell-integration.sh")
missing_keys = sorted(key for key in mech_keys if f"'{key}':" not in integration)
if missing_keys:
    fail("MechScope runtime action map is missing: " + ", ".join(missing_keys))


# Update Center recovery UI: all four visible control buttons must remain wired
# and the corresponding methods must exist.
update = read("scripts/mechos-update-center-recovery-v7.py")
update_tree = parse("scripts/mechos-update-center-recovery-v7.py")
classes = {
    node.name: node for node in update_tree.body if isinstance(node, ast.ClassDef)
}
uc = classes.get("UpdateCenter")
if uc is None:
    fail("UpdateCenter class missing")
methods = {node.name for node in uc.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))}
for method in ("check_updates", "install_updates", "reboot", "load_status", "start_process", "finished"):
    if method not in methods:
        fail(f"Update Center method missing: {method}")
for marker in (
    "self.check_button.clicked.connect(self.check_updates)",
    "self.install_button.clicked.connect(self.install_updates)",
    "self.restart_button.clicked.connect(self.reboot)",
    "self.close_button.clicked.connect(self.close)",
):
    if marker not in update:
        fail(f"Update Center button connection missing: {marker}")


# VM mode buttons/desktop shortcuts must route into the accepted launcher modes.
launcher = read("scripts/mechos-mode-launch-hotfix5.sh")
for mode in ("gaming", "mechscope", "creator", "desktop"):
    if mode not in launcher:
        fail(f"mode launcher no longer accepts {mode}")
runtime = read("scripts/mechos-vm-mode-runtime-hotfix5.sh")
if "MECHOS_VM_MECHSCOPE_PYTHON_EXEC_V2" not in runtime:
    fail("VM MechScope Python execution authority missing")

print(
    "[GUI Button Validation] PASS: Installer, Creator Mode, MechScope, "
    "Update Center and VM mode controls are statically wired to handlers; "
    f"Creator buttons scanned={creator_buttons}, MechScope action keys={len(mech_keys)}."
)
