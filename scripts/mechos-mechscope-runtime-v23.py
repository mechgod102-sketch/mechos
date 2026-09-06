#!/usr/bin/env python3
# MECHOS_MECHSCOPE_RUNTIME_V23
# MECHOS_MECHSCOPE_RUNTIME_V25
"""Stable MechScope entrypoint for patched generated owners.

The generated MechScope owner can be modified by cumulative hotfix layers. This
runtime deliberately imports that owner as a module and owns QApplication.exec()
itself, so a stale or missing __main__ block cannot make Gaming Mode exit 0
immediately after startup.

Hotfix 22.5 also restores source-owned exact-reference helpers in memory when a
generated owner kept calls to them but lost their definitions.  The owner file
is left untouched; only missing module globals are supplied before MechScope is
constructed.
"""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import sys
import traceback

DEFAULT_OWNER = Path("/usr/local/libexec/mechscope-owner-v23.py")
DEFAULT_COMPAT = Path("/usr/local/share/mechos/ui/mechscope_reference_compat_v25.py")
OWNER = Path(os.environ.get("MECHOS_MECHSCOPE_OWNER", str(DEFAULT_OWNER)))
COMPAT = Path(os.environ.get("MECHOS_MECHSCOPE_COMPAT", str(DEFAULT_COMPAT)))
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


def main() -> int:
    try:
        module = load_owner(OWNER)
        install_owner_compat(module)
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
