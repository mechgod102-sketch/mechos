#!/usr/bin/env python3
# MECHOS_HOTFIX17_FAILURE_STATE_FIX
"""MechOS Update Center v8.

Keeps the proven Hotfix 7 update backend while rendering the canonical
source-owned Update Center shell from /usr/local/share/mechos/ui/update_shell.py.
"""
from __future__ import annotations

import importlib.util
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PyQt6.QtCore import QProcess, QTimer, Qt
from PyQt6.QtWidgets import QApplication, QMainWindow, QMessageBox

HELPER = "/usr/local/bin/mechos-update-helper"
REBOOT = "/usr/local/bin/mechos-reboot"
FIRSTBOOT_APPLY = "/usr/local/libexec/mechos-firstboot-update-apply"
STATE = Path("/var/lib/mechos")
RELEASE = Path("/etc/mechos/release")
LOG = Path.home() / ".local/state/mechos/update-center-v8.log"
UI_FILE = Path("/usr/local/share/mechos/ui/update_shell.py")


def log(message: str) -> None:
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with LOG.open("a", encoding="utf-8") as fh:
            fh.write(message.rstrip() + "\n")
    except Exception:
        pass


def parse_values(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key and key.replace("_", "").isalnum():
            values[key] = value
    return values


def current_release() -> str:
    try:
        value = RELEASE.read_text(encoding="utf-8", errors="ignore").strip()
        return value or "unknown"
    except Exception:
        return "unknown"


def load_update_shell():
    if not UI_FILE.is_file():
        raise RuntimeError(f"Canonical Update Center GUI is missing: {UI_FILE}")
    parent = str(UI_FILE.parent)
    if parent not in sys.path:
        sys.path.insert(0, parent)
    spec = importlib.util.spec_from_file_location("mechos_update_shell_v8", UI_FILE)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load Update Center GUI: {UI_FILE}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class UpdateCenter(QMainWindow):
    # MECHOS_UPDATE_CENTER_REFERENCE_V8
    def __init__(self) -> None:
        super().__init__()
        self.proc: QProcess | None = None
        self.buffer = ""
        self.mode = ""
        self.setWindowTitle("MechOS Update Center")
        self.build_ui()
        QTimer.singleShot(250, self.load_status)
        QTimer.singleShot(400, self.load_history)

    def build_ui(self) -> None:
        shell = load_update_shell()
        actions = {
            "check": self.check_updates,
            "install": self.install_updates,
            "history": self.load_history,
            "reboot": self.reboot,
            "performance": lambda: self.spawn(["/usr/local/bin/mechos-performance-center"]),
            "creator": lambda: self.spawn(
                ["/usr/local/bin/mechos-mode-launch", "creator"]
                if Path("/usr/local/bin/mechos-mode-launch").is_file()
                else ["/usr/local/bin/mechos-creator-mode"]
            ),
        }
        ui = shell.UpdateShell(self, actions, self)
        self.setCentralWidget(ui)
        self._mechos_source_ui = ui

        # Backend-compatible aliases. The recovery backend uses the shorter
        # names; the canonical shell exposes descriptive names.
        self.channel = ui.channel
        self.status_label = ui.status_label
        self.status = ui.status_label
        self.details_label = ui.details_label
        self.version_label = ui.version_label
        self.version = ui.version_label
        self.reboot_label = ui.reboot_label
        self.reboot_button = ui.reboot_button
        self.restart_button = ui.reboot_button
        self.check_button = ui.check_button
        self.update_button = ui.update_button
        self.install_button = ui.update_button
        self.history_button = ui.history_button
        self.progress = ui.progress
        self.logview = ui.log
        self.history = ui.history
        self.mechos_count_label = ui.mechos_count_label
        self.arch_count_label = ui.arch_count_label
        self.flatpak_count_label = ui.flatpak_count_label
        self.recovery_state_label = ui.recovery_state_label

        self.setWindowFlag(Qt.WindowType.FramelessWindowHint, True)
        self.setWindowState(Qt.WindowState.WindowFullScreen)

    def spawn(self, args: list[str]) -> None:
        try:
            subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as exc:
            QMessageBox.warning(self, "MechOS Update Center", str(exc))

    def append(self, text: str) -> None:
        if not text:
            return
        self.logview.appendPlainText(text.rstrip())
        log(text)

    def set_busy(self, busy: bool) -> None:
        self.check_button.setEnabled(not busy)
        self.install_button.setEnabled(not busy)
        if busy:
            self.progress.setRange(0, 0)
            self.progress.setFormat("Working…")
        else:
            self.progress.setRange(0, 1)
            self.progress.setValue(1)
            self.progress.setFormat("Ready")

    def helper_ok(self) -> bool:
        if Path(HELPER).is_file() and os.access(HELPER, os.X_OK):
            return True
        QMessageBox.critical(
            self,
            "MechOS Update Center",
            "The MechOS update helper is missing.\n\n" f"Expected: {HELPER}",
        )
        return False

    @staticmethod
    def first_value(values: dict[str, str], *keys: str, default: str = "—") -> str:
        for key in keys:
            value = values.get(key)
            if value not in (None, ""):
                return str(value)
        return default

    def apply_status_values(self, values: dict[str, str]) -> None:
        current = values.get("CURRENT_MECHOS_VERSION", current_release())
        latest = values.get("LATEST_MECHOS_VERSION", current)
        total = self.first_value(values, "TOTAL_COUNT", "UPDATE_COUNT", default="0")
        mechos_available = values.get("MECHOS_UPDATE_AVAILABLE") == "1" or latest != current
        arch = self.first_value(values, "ARCH_COUNT", "PACMAN_COUNT", "SYSTEM_COUNT")
        flatpak = self.first_value(values, "FLATPAK_COUNT", "FLATPAKS_COUNT")
        reboot = values.get("REBOOT_REQUIRED") == "1" or (STATE / "reboot-required").exists()

        self.version_label.setText(f"CURRENT  {current}    →    LATEST  {latest}")
        self.reboot_button.setEnabled(reboot)
        self.reboot_label.setText("RESTART REQUIRED" if reboot else "RESTART NOT REQUIRED")
        self.mechos_count_label.setText("1 AVAILABLE" if mechos_available else "UP TO DATE")
        self.arch_count_label.setText(arch if arch == "—" else f"{arch} UPDATE(S)")
        self.flatpak_count_label.setText(flatpak if flatpak == "—" else f"{flatpak} UPDATE(S)")
        self.recovery_state_label.setText("SNAPSHOT READY" if shutil.which("snapper") else "STANDARD")

        try:
            count = int(total)
        except Exception:
            count = 0
        available = mechos_available or count > 0
        self.install_button.setEnabled(available and self.proc is None)
        if reboot and not available:
            self.status_label.setText("Restart required")
            self.details_label.setText("Updates are installed. Restart MechOS to finish applying them.")
        elif available:
            self.status_label.setText("Updates available")
            self.details_label.setText(f"{total} total update(s) detected across MechOS, Arch and Flatpak sources.")
        else:
            self.status_label.setText("Your system is up to date")
            self.details_label.setText("No newer MechOS release or package updates are currently reported.")

    def load_status(self) -> None:
        if not self.helper_ok():
            self.status_label.setText("Update helper missing")
            return
        try:
            out = subprocess.check_output(
                [HELPER, "status"], text=True, stderr=subprocess.STDOUT, timeout=8
            )
            self.apply_status_values(parse_values(out))
        except Exception as exc:
            self.status_label.setText("Update status unavailable")
            self.details_label.setText("The update service is installed, but its current state could not be read.")
            self.append(f"status error: {exc}")

    def load_history(self) -> None:
        candidates = [
            LOG,
            Path.home() / ".local/state/mechos/update-center-v7.log",
            Path("/var/log/mechos-update.log"),
        ]
        blocks = []
        for path in candidates:
            try:
                if path.is_file():
                    text = path.read_text(encoding="utf-8", errors="replace")
                    if text.strip():
                        blocks.append(f"== {path} ==\n" + "\n".join(text.splitlines()[-40:]))
            except Exception:
                pass
        self.history.setPlainText("\n\n".join(blocks) if blocks else "No completed update history recorded yet.")

    def start_process(self, mode: str, program: str, args: list[str]) -> None:
        if self.proc is not None:
            return
        self.mode = mode
        self.buffer = ""
        self.proc = QProcess(self)
        self.proc.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self.proc.readyReadStandardOutput.connect(self.read_process)
        self.proc.finished.connect(self.finished)
        self.set_busy(True)
        self.append(f"$ {program} {' '.join(args)}")
        self.proc.start(program, args)
        if not self.proc.waitForStarted(4000):
            error = self.proc.errorString()
            self.append(f"Unable to start: {error}")
            self.proc.deleteLater()
            self.proc = None
            self.set_busy(False)
            QMessageBox.critical(self, "MechOS Update Center", f"Could not start update action:\n{error}")

    def read_process(self) -> None:
        if self.proc is None:
            return
        text = bytes(self.proc.readAllStandardOutput()).decode("utf-8", errors="replace")
        if text:
            self.buffer += text
            self.append(text)

    def finished(self, code: int, _status) -> None:
        mode = self.mode
        output = self.buffer
        proc = self.proc
        self.proc = None
        if proc is not None:
            proc.deleteLater()
        self.set_busy(False)
        values = parse_values(output)
        if values:
            self.apply_status_values(values)

        if code != 0:
            self.status_label.setText(f"{mode.capitalize()} failed")
            if mode == "install":
                self.details_label.setText(
                    "The update did not finish. Nothing should be treated as successfully installed yet. "
                    "Review the output, correct the reported problem, then retry Install Updates."
                )
                self.install_button.setEnabled(True)
            else:
                self.details_label.setText("The update action did not complete. Review the output and retry.")
            QMessageBox.critical(
                self,
                "MechOS Update Center",
                f"{mode.capitalize()} failed with exit code {code}.\n\nLog: {LOG}",
            )
            return

        if mode == "check":
            self.status_label.setText("Update check complete")
            self.load_status()
        elif mode == "install":
            self.status_label.setText("Updates installed")
            self.load_status()
            self.load_history()

    def check_updates(self) -> None:
        if not self.helper_ok():
            return
        self.logview.clear()
        self.status_label.setText("Checking for updates…")
        self.start_process("check", HELPER, ["check"])

    def install_updates(self) -> None:
        if not self.helper_ok():
            return
        answer = QMessageBox.question(
            self,
            "Install Updates",
            "Install available MechOS, Arch, and Flatpak updates now?",
        )
        if answer != QMessageBox.StandardButton.Yes:
            return
        self.logview.clear()
        self.status_label.setText("Installing updates…")
        user = os.environ.get("USER") or ""
        firstboot = (STATE / "installed").exists() and not (STATE / "oobe-complete").exists()
        if user == "mechos-setup" and firstboot and Path(FIRSTBOOT_APPLY).is_file():
            self.start_process("install", "pkexec", [FIRSTBOOT_APPLY])
        else:
            self.start_process("install", "pkexec", [HELPER, "apply"])

    def reboot(self) -> None:
        answer = QMessageBox.question(
            self,
            "Restart MechOS",
            "Restart now to finish applying system updates?",
        )
        if answer != QMessageBox.StandardButton.Yes:
            return
        if not Path(REBOOT).is_file():
            QMessageBox.critical(self, "Restart MechOS", f"Reboot helper missing:\n{REBOOT}")
            return
        try:
            result = subprocess.run(
                [REBOOT], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15
            )
        except subprocess.TimeoutExpired:
            return
        except Exception as exc:
            QMessageBox.critical(self, "Restart MechOS", f"Restart failed: {exc}")
            return
        if result.returncode != 0:
            detail = (result.stdout or "").strip() or "The reboot helper returned an error."
            QMessageBox.critical(self, "Restart MechOS", detail + "\n\nLog: ~/.local/state/mechos/reboot.log")


def main() -> int:
    app = QApplication(sys.argv)
    win = UpdateCenter()
    win.showFullScreen()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
