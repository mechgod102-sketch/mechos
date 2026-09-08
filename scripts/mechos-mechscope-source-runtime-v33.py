#!/usr/bin/env python3
# MECHOS_MECHSCOPE_SOURCE_RUNTIME_V33
"""Source-owned MechScope runtime.

This is the stable installed-system owner for MechScope.  It deliberately does
not import /usr/local/bin/mechscope.real or a generated mechscope-owner-v23.py.
The visual composition comes from src/mechscope/mechscope_shell.py, while this
module owns QApplication lifetime, live telemetry, and launch/mode callbacks.
"""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import traceback

from PyQt6.QtCore import QProcess, QTimer, Qt
from PyQt6.QtWidgets import QApplication, QMainWindow, QMessageBox

SHELL = Path(os.environ.get(
    "MECHOS_MECHSCOPE_SHELL",
    "/usr/local/share/mechos/mechscope/mechscope_shell.py",
))
MODE_FILE = Path.home() / ".config/mechos/session-mode"
STATE_DIR = Path.home() / ".local/state/mechos"
LOG = STATE_DIR / "mechscope-source-runtime-v33.log"


def log(message: str) -> None:
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        with LOG.open("a", encoding="utf-8") as fh:
            fh.write(f"[{time.strftime('%Y-%m-%dT%H:%M:%S%z')}] {message.rstrip()}\n")
    except Exception:
        pass


def load_shell():
    if not SHELL.is_file():
        raise RuntimeError(f"source-owned MechScope shell missing: {SHELL}")
    spec = importlib.util.spec_from_file_location("mechos_source_mechscope_shell_v33", SHELL)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load MechScope shell: {SHELL}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    if not hasattr(module, "MechScopeShell"):
        raise RuntimeError("MechScopeShell class missing from source-owned shell")
    return module


def detached(program: str, args: list[str] | None = None) -> bool:
    args = list(args or [])
    candidate = shutil.which(program) if "/" not in program else program
    if not candidate or not os.path.exists(candidate):
        log(f"launch target missing: {program}")
        return False
    result = QProcess.startDetached(candidate, args)
    started = result[0] if isinstance(result, tuple) else bool(result)
    log(f"detached launch program={candidate} args={args!r} started={started}")
    return bool(started)


def read_cpu_percent(state: dict[str, int]) -> int | None:
    try:
        parts = Path("/proc/stat").read_text(encoding="utf-8").splitlines()[0].split()[1:]
        values = [int(v) for v in parts]
        idle = values[3] + (values[4] if len(values) > 4 else 0)
        total = sum(values)
        old_total = state.get("total")
        old_idle = state.get("idle")
        state["total"], state["idle"] = total, idle
        if old_total is None or total <= old_total:
            return None
        delta_total = total - old_total
        delta_idle = idle - old_idle
        return max(0, min(100, int(round(100 * (delta_total - delta_idle) / delta_total))))
    except Exception:
        return None


def read_ram_percent() -> int | None:
    try:
        values: dict[str, int] = {}
        for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
            if ":" not in line:
                continue
            key, value = line.split(":", 1)
            try:
                values[key] = int(value.split()[0])
            except Exception:
                pass
        total = values.get("MemTotal", 0)
        available = values.get("MemAvailable", 0)
        if total <= 0:
            return None
        return max(0, min(100, int(round(100 * (total - available) / total))))
    except Exception:
        return None


def read_disk_percent() -> int | None:
    try:
        usage = shutil.disk_usage("/")
        if usage.total <= 0:
            return None
        return max(0, min(100, int(round(100 * usage.used / usage.total))))
    except Exception:
        return None


def gpu_summary() -> str:
    try:
        out = subprocess.check_output(["lspci"], text=True, stderr=subprocess.DEVNULL, timeout=2)
        for line in out.splitlines():
            low = line.lower()
            if "vga compatible controller" in low or "3d controller" in low or "display controller" in low:
                return line.split(": ", 1)[-1][:70]
    except Exception:
        pass
    return "GPU detected by system"


class MechScope(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MechScope 2.0")
        self.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)
        self._cpu_state: dict[str, int] = {}
        self._shell_module = load_shell()
        actions = {
            "steam": lambda: self._launch_first((("steam", []), ("/usr/bin/steam", []))),
            "store": self.open_store,
            "performance": lambda: self._launch_first((("/usr/local/bin/mechos-performance-center", []),)),
            "updates": lambda: self._launch_first((("/usr/local/bin/mechos-update-center", []),)),
            "drivers": lambda: self._launch_first((("systemsettings", ["kcm_driver_manager"]), ("systemsettings", []))),
            "systeminfo": lambda: self._launch_first((("systemsettings", ["kcm_about-distro"]), ("systemsettings", []))),
            "network": lambda: self._launch_first((("systemsettings", ["kcm_networkmanagement"]), ("systemsettings", []))),
            "gaming": lambda: None,
            "desktop": lambda: self.switch_mode("desktop"),
            "creator": lambda: self.switch_mode("creator"),
            "vr": self.launch_vr,
            "recovery": lambda: self._launch_first((("/usr/local/bin/mechos-recovery-center", []),)),
            "shutdown": self.power_menu,
        }
        self.ui = self._shell_module.MechScopeShell(self, actions, self)
        self.setCentralWidget(self.ui)
        try:
            self.ui.set_recent_games([], lambda _g: None)
        except Exception:
            pass
        self._telemetry = QTimer(self)
        self._telemetry.setInterval(1000)
        self._telemetry.timeout.connect(self.refresh_telemetry)
        self._telemetry.start()
        self.refresh_telemetry()

    def focus_button(self, button) -> None:
        button.setFocusPolicy(Qt.FocusPolicy.StrongFocus)

    def _launch_first(self, choices) -> bool:
        for program, args in choices:
            if detached(program, list(args)):
                return True
        QMessageBox.warning(self, "MechScope", "That MechOS component is not installed or could not be started.")
        return False

    def open_store(self) -> None:
        # Prefer source/system-owned store launchers. Never route Store startup
        # through the legacy mechscope.real recovery target.
        choices = (
            ("/usr/local/bin/mechos-discovery-store", []),
            ("/usr/local/bin/mechos-discover-store", []),
            ("/usr/local/bin/mechos-unified-store", []),
            ("plasma-discover", []),
        )
        self._launch_first(choices)

    def launch_vr(self) -> None:
        if not detached("steam", ["steam://run/250820"]):
            self._launch_first((("steam", []),))

    def power_menu(self) -> None:
        if detached("qdbus6", ["org.kde.LogoutPrompt", "/LogoutPrompt", "promptAll"]):
            return
        detached("qdbus", ["org.kde.LogoutPrompt", "/LogoutPrompt", "promptAll"])

    def switch_mode(self, mode: str) -> None:
        MODE_FILE.parent.mkdir(parents=True, exist_ok=True)
        MODE_FILE.write_text(mode + "\n", encoding="utf-8")
        if detached("/usr/local/bin/mechos-mode-launch", [mode]):
            log(f"mode transition requested: {mode}")
            QTimer.singleShot(250, self.close)
            return
        if mode == "creator" and detached("/usr/local/bin/mechos-creator-mode", []):
            QTimer.singleShot(250, self.close)

    def refresh_telemetry(self) -> None:
        try:
            cpu = read_cpu_percent(self._cpu_state)
            ram = read_ram_percent()
            disk = read_disk_percent()
            if hasattr(self.ui, "cpu_gauge") and cpu is not None:
                self.ui.cpu_gauge.setValue(cpu)
            if hasattr(self.ui, "ram_gauge") and ram is not None:
                self.ui.ram_gauge.setValue(ram)
            if hasattr(self.ui, "disk_gauge") and disk is not None:
                self.ui.disk_gauge.setValue(disk)
            if hasattr(self.ui, "gpu_status"):
                self.ui.gpu_status.setText("▣  " + gpu_summary())
            if hasattr(self.ui, "time_label"):
                self.ui.time_label.setText(time.strftime("%H:%M"))
            if hasattr(self.ui, "net_label"):
                online = any(p.exists() for p in Path("/sys/class/net").glob("*/operstate") if p.read_text(errors="ignore").strip() == "up")
                self.ui.net_label.setText("▥  NET online" if online else "▥  NET offline")
        except Exception:
            log("telemetry refresh failed:\n" + traceback.format_exc())


class UnifiedStore(QMainWindow):
    """Compatibility entry for callers that still request `mechscope --store`."""
    def __init__(self):
        super().__init__()
        self.setWindowTitle("MechScope Unified Store")
        QTimer.singleShot(0, self._handoff)

    def _handoff(self):
        for program in (
            "/usr/local/bin/mechos-discovery-store",
            "/usr/local/bin/mechos-discover-store",
            "/usr/local/bin/mechos-unified-store",
            "plasma-discover",
        ):
            if detached(program, []):
                self.close()
                return
        QMessageBox.warning(self, "Unified Store", "No store backend is currently installed.")
        self.close()


def main() -> int:
    try:
        app = QApplication.instance() or QApplication(sys.argv)
        app.setQuitOnLastWindowClosed(True)
        store_only = "--store" in sys.argv[1:]
        window = UnifiedStore() if store_only else MechScope()
        setattr(app, "_mechos_primary_window_v33", window)
        if not store_only:
            app.setQuitOnLastWindowClosed(False)
            window.showFullScreen()
            keep = QTimer(app)
            keep.setInterval(750)
            def ensure_visible():
                try:
                    mode = MODE_FILE.read_text(encoding="utf-8", errors="ignore").strip() if MODE_FILE.exists() else "gaming"
                    if mode == "gaming" and not window.isVisible():
                        window.showFullScreen(); window.raise_(); window.activateWindow()
                except Exception:
                    log("visibility guard failed:\n" + traceback.format_exc())
            keep.timeout.connect(ensure_visible)
            keep.start()
            setattr(app, "_mechos_visibility_timer_v33", keep)
        else:
            window.show()
        log(f"source-owned runtime started store_only={store_only}")
        rc = int(app.exec())
        log(f"source-owned runtime exited rc={rc}")
        return rc
    except Exception:
        log("source-owned runtime failed:\n" + traceback.format_exc())
        raise


if __name__ == "__main__":
    raise SystemExit(main())
