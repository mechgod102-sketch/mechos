#!/usr/bin/env python3
# MECHOS_MECHSCOPE_RUNTIME_V23
# MECHOS_MECHSCOPE_RUNTIME_V25
# MECHOS_MECHSCOPE_RUNTIME_V26
# MECHOS_MECHSCOPE_LIFETIME_V29
"""Stable MechScope entrypoint for patched generated owners."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import sys
import traceback

DEFAULT_OWNER = Path("/usr/local/libexec/mechscope-owner-v23.py")
DEFAULT_COMPAT = Path("/usr/local/share/mechos/ui/mechscope_reference_compat_v25.py")
DEFAULT_CREATOR_LAUNCHER = Path("/usr/local/libexec/mechos-creator-launch-v19")
OWNER = Path(os.environ.get("MECHOS_MECHSCOPE_OWNER", str(DEFAULT_OWNER)))
COMPAT = Path(os.environ.get("MECHOS_MECHSCOPE_COMPAT", str(DEFAULT_COMPAT)))
CREATOR_LAUNCHER = Path(os.environ.get("MECHOS_CREATOR_LAUNCHER", str(DEFAULT_CREATOR_LAUNCHER)))
MODE_FILE = Path.home() / ".config/mechos/session-mode"
LOG = Path(os.environ.get(
    "MECHOS_MECHSCOPE_RUNTIME_LOG",
    str(Path.home() / ".local/state/mechos/mechscope-runtime-v23.log"),
))


def log(message: str) -> None:
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with LOG.open("a", encoding="utf-8") as fh:
            fh.write(message.rstrip() + "\n")
    except Exception:
        pass


def load_owner(path: Path):
    if not path.is_file():
        raise RuntimeError(f"MechScope owner missing: {path}")
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("mechos_mechscope_owner_v23", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load MechScope owner: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    try:
        spec.loader.exec_module(module)
    except SystemExit as exc:
        if exc.code not in (None, 0):
            raise
        log(f"ignored legacy clean SystemExit while importing owner: {exc.code!r}")
    return module


def load_compat(path: Path):
    if not path.is_file():
        raise RuntimeError(f"MechScope compatibility module missing: {path}")
    spec = importlib.util.spec_from_file_location("mechos_mechscope_reference_compat_v25", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load MechScope compatibility module: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def install_owner_compat(module) -> None:
    required = ("MechReferenceGauge", "mechos_gpu_load_percent")
    missing = [name for name in required if not hasattr(module, name)]
    if not missing:
        return
    compat = load_compat(COMPAT)
    installed = []
    for name in missing:
        value = getattr(compat, name, None)
        if value is None:
            raise RuntimeError(f"MechScope compatibility module does not provide {name}")
        setattr(module, name, value)
        installed.append(name)
    log("installed MechScope reference compatibility: " + ", ".join(installed))


def install_creator_external_handoff(module) -> None:
    mechscope_class = getattr(module, "MechScope", None)
    if mechscope_class is None:
        raise RuntimeError("MechScope class missing while installing Creator handoff")
    original = getattr(mechscope_class, "_mechos_shell_route_v16", None)
    if not callable(original):
        log("Creator external handoff not needed; v16 shell route is absent")
        return
    if getattr(mechscope_class, "_mechos_creator_external_handoff_v26", False):
        return

    def route_with_external_creator(self, key):
        value = str(key).strip().lower()
        aliases = {
            "mechscope": "gaming", "update": "updates",
            "performance-center": "performance", "recovery-center": "recovery",
        }
        value = aliases.get(value, value)
        if value != "creator":
            return original(self, key)
        route_file = getattr(self, "_mechos_shell_route_file_v16", None)
        if route_file is not None:
            try:
                route_file.unlink(missing_ok=True)
            except Exception:
                pass
        if not CREATOR_LAUNCHER.is_file() or not os.access(CREATOR_LAUNCHER, os.X_OK):
            raise RuntimeError(f"MechOS Creator launcher missing: {CREATOR_LAUNCHER}")
        from PyQt6.QtCore import QProcess
        result = QProcess.startDetached(str(CREATOR_LAUNCHER), ["creator"])
        started = result[0] if isinstance(result, tuple) else bool(result)
        if not started:
            raise RuntimeError("MechOS Creator external handoff failed to start")
        log(f"Creator Mode handed off externally via {CREATOR_LAUNCHER}")
        return True

    mechscope_class._mechos_shell_route_v16 = route_with_external_creator
    mechscope_class._mechos_creator_external_handoff_v26 = True
    log("installed Creator external Qt handoff for v16 unified-shell routes")


def gaming_mode_active() -> bool:
    try:
        if MODE_FILE.is_file():
            return MODE_FILE.read_text(encoding="utf-8", errors="ignore").strip() == "gaming"
    except Exception:
        pass
    return True


def install_lifetime_guard(app, window) -> None:
    """Keep the gaming shell resident until a real mode switch occurs.

    Mixed-version owners can briefly hide/close their top-level window while
    restoring a page. Qt's default behavior quits when the last window closes,
    which looks like MechScope starts and then stops. VM and hardware session
    wrappers mark supervised Gaming Mode explicitly, so only those sessions
    disable implicit quit. Creator/Desktop transitions change session-mode and
    are never fought by the guard.
    """
    supervised = (
        os.environ.get("MECHOS_VM_MODE") == "1"
        or os.environ.get("MECHOS_SESSION_SUPERVISED") == "1"
    )
    if not supervised:
        return

    from PyQt6.QtCore import QTimer

    app.setQuitOnLastWindowClosed(False)
    state = {"hidden": False}

    def keepalive() -> None:
        if not gaming_mode_active():
            return
        try:
            visible = bool(window.isVisible())
        except RuntimeError:
            log("lifetime guard: primary MechScope QObject was destroyed")
            return
        if visible:
            state["hidden"] = False
            return
        if not state["hidden"]:
            log("lifetime guard: MechScope became hidden while Gaming Mode remained active; restoring window")
            state["hidden"] = True
        try:
            window.showFullScreen()
            window.raise_()
            window.activateWindow()
        except Exception:
            log("lifetime guard restore failed:\n" + traceback.format_exc())

    timer = QTimer(app)
    timer.setInterval(750)
    timer.timeout.connect(keepalive)
    timer.start()
    setattr(app, "_mechos_lifetime_timer_v29", timer)
    app.aboutToQuit.connect(lambda: log(
        "QApplication aboutToQuit; mode=" +
        (MODE_FILE.read_text(encoding="utf-8", errors="ignore").strip() if MODE_FILE.is_file() else "unknown")
    ))
    log("installed MechScope lifetime guard for supervised Gaming Mode")


def main() -> int:
    try:
        module = load_owner(OWNER)
        install_owner_compat(module)
        install_creator_external_handoff(module)
        from PyQt6.QtWidgets import QApplication

        app = QApplication.instance()
        if app is None:
            app = QApplication(sys.argv)

        store_only = "--store" in sys.argv[1:]
        class_name = "UnifiedStore" if store_only else "MechScope"
        window_class = getattr(module, class_name, None)
        if window_class is None:
            raise RuntimeError(f"{class_name} class missing from MechScope owner")

        window = window_class()
        setattr(app, "_mechos_primary_window_v23", window)
        setattr(app, "_mechos_primary_window_v25", window)
        setattr(app, "_mechos_primary_window_v26", window)
        setattr(app, "_mechos_primary_window_v29", window)

        try:
            window.showFullScreen()
        except Exception:
            window.show()

        if not store_only:
            install_lifetime_guard(app, window)

        log(f"running {class_name} from owner={OWNER}")
        rc = int(app.exec())
        log(f"QApplication exited rc={rc} mode={'gaming' if gaming_mode_active() else 'non-gaming'}")
        return rc
    except Exception:
        log("MechScope runtime failed:\n" + traceback.format_exc())
        raise


if __name__ == "__main__":
    raise SystemExit(main())
