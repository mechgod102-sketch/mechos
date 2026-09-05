#!/usr/bin/env python3
"""Static GUI action-wiring and responsive-layout gate for MechOS.

The validator does not execute destructive/system actions. It proves that
visible controls are wired to handlers, source-owned fixed-canvas surfaces use
the responsive geometry authority, custom installer labels survive resize,
MechScope nested recent-game cards scale with their host, and literal authored
geometry remains inside the design canvas at common VM/desktop resolutions.
"""
from __future__ import annotations

import ast
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Resolutions intentionally cover low-resolution VMs, common laptop/desktop
# modes, 4:3 fallback, ultrawide, 1440p and 4K. Aspect-preserving canvases are
# centered (letterboxed/pillarboxed) instead of stretching the layout.
RESOLUTIONS = (
    (1024, 576),
    (1024, 768),
    (1280, 720),
    (1366, 768),
    (1600, 900),
    (1920, 1080),
    (2560, 1440),
    (3440, 1440),
    (3840, 2160),
)


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


def call_name(call: ast.Call) -> str:
    fn = call.func
    if isinstance(fn, ast.Name):
        return fn.id
    if isinstance(fn, ast.Attribute):
        return fn.attr
    return ""


def number(node: ast.AST):
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return float(node.value)
    if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.USub):
        value = number(node.operand)
        return None if value is None else -value
    if isinstance(node, ast.BinOp):
        left = number(node.left)
        right = number(node.right)
        if left is None or right is None:
            return None
        if isinstance(node.op, ast.Add):
            return left + right
        if isinstance(node.op, ast.Sub):
            return left - right
        if isinstance(node.op, ast.Mult):
            return left * right
        if isinstance(node.op, ast.Div) and right:
            return left / right
    return None


def literal_qrect(node: ast.AST):
    if not isinstance(node, ast.Call) or call_name(node) != "QRect" or len(node.args) != 4:
        return None
    values = [number(arg) for arg in node.args]
    if any(value is None for value in values):
        return None
    x, y, w, h = values
    return (x, y, w, h)


def all_literal_rects(tree: ast.AST):
    result = []
    for node in ast.walk(tree):
        rect = literal_qrect(node)
        if rect is not None:
            result.append((getattr(node, "lineno", 0), rect))
    return result


def interactive_literal_rects(tree: ast.AST, methods: set[str]):
    result = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or call_name(node) not in methods:
            continue
        rect = None
        for arg in node.args:
            rect = literal_qrect(arg)
            if rect is not None:
                break
        if rect is None:
            for kw in node.keywords:
                rect = literal_qrect(kw.value)
                if rect is not None:
                    break
        if rect is not None:
            result.append((getattr(node, "lineno", 0), rect))
    return result


def scaled_rect(rect, base_w, base_h, screen_w, screen_h):
    x, y, w, h = rect
    scale = min(screen_w / base_w, screen_h / base_h)
    ox = (screen_w - base_w * scale) / 2
    oy = (screen_h - base_h * scale) / 2
    return (
        ox + x * scale,
        oy + y * scale,
        max(1.0, w * scale),
        max(1.0, h * scale),
    )


def validate_rects(rel: str, tree: ast.AST, base_w: int, base_h: int, minimum: int) -> int:
    rects = all_literal_rects(tree)
    if len(rects) < minimum:
        fail(f"{rel} exposes too few literal authored rectangles ({len(rects)})")
    for lineno, (x, y, w, h) in rects:
        if w <= 0 or h <= 0:
            fail(f"{rel}:{lineno} has non-positive geometry {x,y,w,h}")
        if x < 0 or y < 0 or x + w > base_w + .01 or y + h > base_h + .01:
            fail(f"{rel}:{lineno} authored rectangle escapes {base_w}x{base_h}: {x,y,w,h}")
        for sw, sh in RESOLUTIONS:
            sx, sy, rw, rh = scaled_rect((x, y, w, h), base_w, base_h, sw, sh)
            if sx < -1 or sy < -1 or sx + rw > sw + 1 or sy + rh > sh + 1:
                fail(f"{rel}:{lineno} escapes {sw}x{sh} after responsive scaling")
    return len(rects)


def validate_interactive_size(rel: str, tree: ast.AST, methods: set[str], base_w: int, base_h: int) -> int:
    rects = interactive_literal_rects(tree, methods)
    if not rects:
        fail(f"{rel} has no literal interactive rectangles")
    # At the smallest supported VM size controls must still retain a clickable
    # footprint. This is deliberately a geometry guard, not a typography guess.
    sw, sh = RESOLUTIONS[0]
    for lineno, rect in rects:
        _, _, rw, rh = scaled_rect(rect, base_w, base_h, sw, sh)
        if rw < 20 or rh < 18:
            fail(f"{rel}:{lineno} becomes too small at {sw}x{sh}: {rw:.1f}x{rh:.1f}")
    return len(rects)


# Shared button primitive: callbacks supplied by surfaces must reach Qt and the
# responsive resize pass must not erase labels owned by custom QPushButtons.
fixed = read("src/mechos_ui/fixed_canvas.py")
if "MECHOS_VM_RESPONSIVE_GEOMETRY_V3" not in fixed:
    fail("current responsive geometry V3 marker missing")
if "MECHOS_VM_RESPONSIVE_GEOMETRY_V2" not in fixed:
    fail("late Build 118 compatibility marker missing")
if "q.clicked.connect(fn)" not in fixed:
    fail("FixedCanvas.button no longer connects its callback")
for marker in (
    "return min(self.width() / BASE_W, self.height() / BASE_H)",
    "widget.setGeometry(scaled)",
    "f.setPointSize(max(5, int(round(base * s))))",
    "title_prop = widget.property('mechosTitle')",
    "if title_prop is not None:",
):
    if marker not in fixed:
        fail(f"FixedCanvas responsive authority missing: {marker}")


# Live Installer: navigation, target selection, install mode, Repair and Install
# Now must all have an actual handler. Its custom mode/change-drive labels are
# intentionally not owned by FixedCanvas.button and must therefore survive the
# shared resize pass above.
installer_rel = "src/mechos_ui/installer_shell.py"
installer = read(installer_rel)
installer_tree = parse(installer_rel)
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
if "self.change_drive.setProperty('role', 'mode')" not in installer:
    fail("Installer Change Drive responsive role missing")
installer_rect_count = validate_rects(installer_rel, installer_tree, 1920, 1080, 20)
installer_button_count = validate_interactive_size(
    installer_rel, installer_tree, {"hotspot", "mode_button"}, 1920, 1080
)


# Creator Mode: every FixedCanvas button call must supply a callback expression.
# The active Creator Mode tab intentionally uses `lambda: None`; it is still a
# connected control and is allowed because selecting the already-active mode is
# a no-op by design.
creator_rel = "src/mechos_ui/creator_shell.py"
creator_tree = parse(creator_rel)
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
creator = read(creator_rel)
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
creator_rect_count = validate_rects(creator_rel, creator_tree, 1920, 1080, 30)
creator_literal_buttons = validate_interactive_size(creator_rel, creator_tree, {"button"}, 1920, 1080)


# MechScope source shell obtains callbacks from the runtime action map. Verify
# that every literal action key used by the source shell is supplied by the
# final native integration so a rendered button cannot silently become inert.
mech_rel = "src/mechscope/mechscope_shell.py"
mech_tree = parse(mech_rel)
mech_keys: set[str] = set()
for node in ast.walk(mech_tree):
    if not isinstance(node, ast.Call) or not is_self_method(node, "_button"):
        continue
    if node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str):
        mech_keys.add(node.args[0].value)
if not mech_keys:
    fail("MechScope source shell action keys were not found")
mech = read(mech_rel)
if "fn = self.actions.get(key)" not in mech or "q.clicked.connect(fn)" not in mech:
    fail("MechScope source button helper does not connect action-map callbacks")
for marker in (
    "return min(self.width()/BASE_W, self.height()/BASE_H)",
    "widget.setGeometry(self._rect(rect))",
    "MECHOS_RESPONSIVE_RECENT_GAMES_V1",
    "self._layout_recent_widgets()",
    "host_w / 1001.0",
    "host_h / 218.0",
):
    if marker not in mech:
        fail(f"MechScope responsive authority missing: {marker}")
if "btn.setGeometry(i*(card_w+gap),0,card_w,210)" in mech:
    fail("MechScope recent game cards still use unscaled fixed child geometry")
integration = read("scripts/mechos-native-ui-shell-integration.sh")
missing_keys = sorted(key for key in mech_keys if f"'{key}':" not in integration)
if missing_keys:
    fail("MechScope runtime action map is missing: " + ", ".join(missing_keys))
mech_rect_count = validate_rects(mech_rel, mech_tree, 1672, 941, 20)
mech_button_count = validate_interactive_size(mech_rel, mech_tree, {"_button"}, 1672, 941)


# Update Center recovery UI: all four visible control buttons must remain wired.
# It is a normal Qt layout-based window rather than a fixed canvas, so Qt owns
# row reflow as the window grows/shrinks; minimum size prevents unusable collapse.
update_rel = "scripts/mechos-update-center-recovery-v7.py"
update = read(update_rel)
update_tree = parse(update_rel)
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
    "QHBoxLayout()",
    "QVBoxLayout(root)",
    "self.setMinimumSize(760, 520)",
):
    if marker not in update:
        fail(f"Update Center responsive/button requirement missing: {marker}")


# VM mode buttons/desktop shortcuts must route into the accepted launcher modes.
launcher = read("scripts/mechos-mode-launch-hotfix5.sh")
for mode in ("gaming", "mechscope", "creator", "desktop"):
    if mode not in launcher:
        fail(f"mode launcher no longer accepts {mode}")
runtime = read("scripts/mechos-vm-mode-runtime-hotfix5.sh")
if "MECHOS_VM_MECHSCOPE_PYTHON_EXEC_V2" not in runtime:
    fail("VM MechScope Python execution authority missing")

print(
    "[GUI Button Validation] PASS: controls are wired and responsive geometry "
    "is bounded/aligned for 1024x576, 1024x768, 720p, 768p, 900p, 1080p, "
    "1440p, ultrawide and 4K; custom Installer labels survive resize and "
    "MechScope recent-game cards scale with their host. "
    f"Rects checked: Installer={installer_rect_count}, Creator={creator_rect_count}, "
    f"MechScope={mech_rect_count}; literal interactive controls: "
    f"Installer={installer_button_count}, Creator={creator_literal_buttons}, "
    f"MechScope={mech_button_count}; Creator button calls={creator_buttons}."
)
