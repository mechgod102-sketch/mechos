#!/usr/bin/env python3
# MECHOS_MECHSCOPE_RUNTIME_V23
# MECHOS_MECHSCOPE_RUNTIME_V25
# MECHOS_MECHSCOPE_RUNTIME_V26
"""Stable MechScope entrypoint for patched generated owners.

The generated MechScope owner can be modified by cumulative hotfix layers. This
runtime deliberately imports that owner as a module and owns QApplication.exec()
itself, so a stale or missing __main__ block cannot make Gaming Mode exit 0
immediately after startup.

Hotfix 22.5 restores source-owned exact-reference helpers in memory when a
generated owner kept calls to them but lost their definitions.

Hotfix 22.6 also prevents Creator Mode from being imported into the live
MechScope interpreter. Creator owns its own QApplication; loading it through the
Hotfix 16 SourceFileLoader path can make Qt/Wayland initialize a second GUI
application in the existing process and abort. Creator requests are therefore
handed to the proven external Creator launcher while other unified-shell pages
remain in-process.
"""
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
CREATOR_LAUNCHER = Path(
    os.environ.get("MECHOS_CREATOR_LAUNCHER", str(DEFAULT_CREATOR_LAUNCHER))
)
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

    # Never try to create __pycache__ next to root-owned MechOS executables.
    sys.dont_write_bytecode = True

    spec = importlib.util.spec_from_file_location("mechos_mechscope_owner_v23", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load MechScope owner: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module

    try:
        spec.loader.exec_module(module)
    except SystemExit as exc:
        # Some historical owners contain top-level/legacy exit paths. A clean
        # exit is exactly the regression this wrapper is designed to bypass.
        code = exc.code
        if code not in (None, 0):
            raise
        log(f"ignored legacy clean SystemExit while importing owner: {code!r}")

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
    """Keep Creator Mode out of the active MechScope QApplication process."""
    mechscope_class = getattr(module, "MechScope", None)
    if mechscope_class is None:
        raise RuntimeError("MechScope class missing while installing Creator handoff")

    original = getattr(mechscope_class, "_mechos_shell_route_v16", None)
    if not callable(original):
        # Owners that predate the single-shell patch already use process-level
        # launchers and do not need this compatibility override.
        log("Creator external handoff not needed; v16 shell route is absent")
        return

    if getattr(mechscope_class, "_mechos_creator_external_handoff_v26", False):
        return

    def route_with_external_creator(self, key):
        value = str(key).strip().lower()
        aliases = {
            "mechscope": "gaming",
            "update": "updates",
            "performance-center": "performance",
            "recovery-center": "recovery",
        }
        value = aliases.get(value, value)
        if value != "creator":
            return original(self, key)

        # A stale queued Creator route must not be consumed again by the v16
        # poller after the external process is launched.
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
        # Hold a reference for the lifetime of the event loop.
        setattr(app, "_mechos_primary_window_v23", window)
        setattr(app, "_mechos_primary_window_v25", window)
        setattr(app, "_mechos_primary_window_v26", window)

        try:
            window.showFullScreen()
        except Exception:
            window.show()

        log(f"running {class_name} from owner={OWNER}")
        return int(app.exec())
    except Exception:
        log("MechScope runtime failed:\n" + traceback.format_exc())
        raise


if __name__ == "__main__":
    raise SystemExit(main())
