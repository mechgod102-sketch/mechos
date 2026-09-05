#!/usr/bin/env python3
"""MechOS Update Center recovery owner for Hotfix 7.

This is deliberately self-contained so an in-place patch of an older Update
Center cannot make the updater itself unlaunchable.  The UI delegates update
logic to the long-lived mechos-update-helper backend.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from PyQt6.QtCore import QProcess, QTimer, Qt
from PyQt6.QtGui import QFont
from PyQt6.QtWidgets import (
    QApplication,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

HELPER = "/usr/local/bin/mechos-update-helper"
REBOOT = "/usr/local/bin/mechos-reboot"
FIRSTBOOT_APPLY = "/usr/local/libexec/mechos-firstboot-update-apply"
STATE = Path("/var/lib/mechos")
RELEASE = Path("/etc/mechos/release")
LOG = Path.home() / ".local/state/mechos/update-center-v7.log"


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


class UpdateCenter(QMainWindow):
    # MECHOS_UPDATE_CENTER_RECOVERY_V7
    def __init__(self) -> None:
        super().__init__()
        self.proc: QProcess | None = None
        self.buffer = ""
        self.mode = ""
        self.setWindowTitle("MechOS Update Center")
        self.resize(1040, 720)
        self.setMinimumSize(760, 520)
        self._build()
        QTimer.singleShot(250, self.load_status)

    def _build(self) -> None:
        root = QWidget(self)
        self.setCentralWidget(root)
        outer = QVBoxLayout(root)
        outer.setContentsMargins(24, 22, 24, 22)
        outer.setSpacing(14)

        title = QLabel("MECHOS UPDATE CENTER")
        title.setFont(QFont("Sans Serif", 22, QFont.Weight.Bold))
        outer.addWidget(title)

        self.version = QLabel(f"CURRENT  {current_release()}    •    LATEST  checking…")
        self.version.setFont(QFont("Sans Serif", 12, QFont.Weight.DemiBold))
        outer.addWidget(self.version)

        self.status = QLabel("Checking update service…")
        self.status.setWordWrap(True)
        outer.addWidget(self.status)

        buttons = QHBoxLayout()
        self.check_button = QPushButton("Check Again")
        self.install_button = QPushButton("Install Updates")
        self.restart_button = QPushButton("Restart MechOS")
        self.close_button = QPushButton("Close")
        self.check_button.clicked.connect(self.check_updates)
        self.install_button.clicked.connect(self.install_updates)
        self.restart_button.clicked.connect(self.reboot)
        self.close_button.clicked.connect(self.close)
        buttons.addWidget(self.check_button)
        buttons.addWidget(self.install_button)
        buttons.addWidget(self.restart_button)
        buttons.addStretch(1)
        buttons.addWidget(self.close_button)
        outer.addLayout(buttons)

        self.logview = QPlainTextEdit()
        self.logview.setReadOnly(True)
        self.logview.setPlaceholderText("Update details and diagnostics appear here.")
        outer.addWidget(self.logview, 1)

    def append(self, text: str) -> None:
        if not text:
            return
        self.logview.appendPlainText(text.rstrip())
        log(text)

    def set_busy(self, busy: bool) -> None:
        self.check_button.setEnabled(not busy)
        self.install_button.setEnabled(not busy)

    def helper_ok(self) -> bool:
        if Path(HELPER).is_file() and os.access(HELPER, os.X_OK):
            return True
        QMessageBox.critical(
            self,
            "MechOS Update Center",
            "The MechOS update helper is missing. Hotfix recovery cannot continue.\n\n"
            f"Expected: {HELPER}",
        )
        return False

    def load_status(self) -> None:
        if not self.helper_ok():
            self.status.setText("Update helper missing")
            return
        try:
            out = subprocess.check_output(
                [HELPER, "status"],
                text=True,
                stderr=subprocess.STDOUT,
                timeout=8,
            )
        except Exception as exc:
            self.status.setText("Update service is installed, but status could not be read.")
            self.append(f"status error: {exc}")
            return
        values = parse_values(out)
        current = values.get("CURRENT_MECHOS_VERSION", current_release())
        latest = values.get("LATEST_MECHOS_VERSION", current)
        self.version.setText(f"CURRENT  {current}    •    LATEST  {latest}")
        reboot = values.get("REBOOT_REQUIRED") == "1"
        self.restart_button.setEnabled(reboot)
        self.status.setText("Restart required" if reboot else "Ready to check for updates")

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
        current = values.get("CURRENT_MECHOS_VERSION", current_release())
        latest = values.get("LATEST_MECHOS_VERSION", current)
        if current or latest:
            self.version.setText(f"CURRENT  {current}    •    LATEST  {latest}")

        if code != 0:
            self.status.setText(f"{mode.capitalize()} failed")
            QMessageBox.critical(
                self,
                "MechOS Update Center",
                f"{mode.capitalize()} failed with exit code {code}.\n\n"
                f"Log: {LOG}",
            )
            return

        if mode == "check":
            total = values.get("TOTAL_COUNT", "0")
            mechos_available = values.get("MECHOS_UPDATE_AVAILABLE") == "1"
            if mechos_available:
                self.status.setText(f"MechOS {latest} is available • {total} total update(s)")
            else:
                self.status.setText(f"System check complete • {total} total update(s)")
        elif mode == "install":
            self.status.setText("Updates installed")
            reboot_required = values.get("REBOOT_REQUIRED") == "1" or (STATE / "reboot-required").exists()
            self.restart_button.setEnabled(reboot_required)
            self.load_status()

    def check_updates(self) -> None:
        if not self.helper_ok():
            return
        self.logview.clear()
        self.status.setText("Checking for updates…")
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
        self.status.setText("Installing updates…")
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
                [REBOOT],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=15,
            )
        except subprocess.TimeoutExpired:
            # The machine may already be transitioning to reboot.
            return
        except Exception as exc:
            QMessageBox.critical(self, "Restart MechOS", f"Restart failed: {exc}")
            return
        if result.returncode != 0:
            detail = (result.stdout or "").strip() or "The reboot helper returned an error."
            QMessageBox.critical(
                self,
                "Restart MechOS",
                detail + "\n\nLog: ~/.local/state/mechos/reboot.log",
            )


def main() -> int:
    app = QApplication(sys.argv)
    win = UpdateCenter()
    win.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
