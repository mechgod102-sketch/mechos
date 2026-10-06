#!/usr/bin/env python3
# MECHOS_CREATOR_QT_CALLBACK_GUARD_V27
"""Live Creator Mode shell.

Creator Mode is rendered from native Qt widgets and live system/project data.
The reference artwork is a design guide only; no system values, projects,
news, update state, or controls are baked into a screenshot.
"""
from __future__ import annotations

import os
import platform
import shutil
import subprocess
import sys
import time
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fixed_canvas import BASE_H, BASE_W, FixedCanvas
from PyQt6.QtCore import QProcess, QRect, QTimer, Qt
from PyQt6.QtGui import QColor, QLinearGradient, QPainter, QPen
from PyQt6.QtWidgets import QLabel, QStackedWidget, QWidget


RELEASE_FILE = Path("/etc/mechos/release")
UPDATE_HELPER = Path("/usr/local/bin/mechos-update-helper")
CREATOR_RUNTIME_LOG = Path.home() / ".local/state/mechos/creator-mode-v27.log"


def _creator_log(message: str) -> None:
    try:
        CREATOR_RUNTIME_LOG.parent.mkdir(parents=True, exist_ok=True)
        with CREATOR_RUNTIME_LOG.open("a", encoding="utf-8") as fh:
            fh.write(f"[{time.strftime('%Y-%m-%dT%H:%M:%S%z')}] {message.rstrip()}\n")
    except Exception:
        pass


def _output(args, timeout=2):
    try:
        return subprocess.check_output(
            args, text=True, stderr=subprocess.DEVNULL, timeout=timeout
        ).strip()
    except Exception:
        return ""


def _shell(command, timeout=2):
    try:
        return subprocess.check_output(
            ["bash", "-lc", command],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
        ).strip()
    except Exception:
        return ""


def _release():
    try:
        value = RELEASE_FILE.read_text(encoding="utf-8", errors="ignore").strip()
        return value or "unknown"
    except Exception:
        return "unknown"


def _uptime_text():
    try:
        seconds = int(float(Path("/proc/uptime").read_text().split()[0]))
    except Exception:
        return "unknown"
    days, seconds = divmod(seconds, 86400)
    hours, seconds = divmod(seconds, 3600)
    minutes = seconds // 60
    if days:
        return f"{days}d {hours}h {minutes}m"
    if hours:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


def _cpu_model():
    value = _shell("lscpu | sed -n 's/^Model name:[[:space:]]*//p' | head -n1")
    return value or platform.processor() or "Unknown CPU"


def _gpu_info():
    block = _shell(
        "lspci -nnk | awk "
        "'/VGA compatible controller|3D controller|Display controller/ {show=1; print; next} "
        "show && /Kernel driver in use:/ {print; exit}'"
    )
    lines = [x.strip() for x in block.splitlines() if x.strip()]
    gpu = "Unknown GPU"
    driver = "Unknown"
    if lines:
        first = lines[0]
        gpu = first.split(": ", 1)[1] if ": " in first else first
    for line in lines[1:]:
        if "Kernel driver in use:" in line:
            driver = line.split("Kernel driver in use:", 1)[1].strip() or "Unknown"
            break
    return gpu, driver


def _mem_percent():
    try:
        values = {}
        for line in Path("/proc/meminfo").read_text().splitlines():
            key, raw = line.split(":", 1)
            values[key] = int(raw.strip().split()[0])
        total = values["MemTotal"]
        available = values.get("MemAvailable", 0)
        return round((1 - available / total) * 100) if total else None
    except Exception:
        return None


def _disk_percent():
    try:
        usage = shutil.disk_usage("/")
        return round(usage.used / usage.total * 100) if usage.total else None
    except Exception:
        return None


def _vram_percent():
    out = _output(
        ["nvidia-smi", "--query-gpu=memory.used,memory.total", "--format=csv,noheader,nounits"],
        timeout=1,
    )
    if out:
        try:
            used, total = [float(x.strip()) for x in out.splitlines()[0].split(",")[:2]]
            return round(used / total * 100) if total else None
        except Exception:
            pass

    for card in sorted(Path("/sys/class/drm").glob("card*/device")):
        used = card / "mem_info_vram_used"
        total = card / "mem_info_vram_total"
        if used.is_file() and total.is_file():
            try:
                u = int(used.read_text().strip())
                t = int(total.read_text().strip())
                if t > 0:
                    return round(u / t * 100)
            except Exception:
                pass
    return None


def _cpu_sample():
    try:
        fields = [int(x) for x in Path("/proc/stat").read_text().splitlines()[0].split()[1:]]
        idle = fields[3] + (fields[4] if len(fields) > 4 else 0)
        return sum(fields), idle
    except Exception:
        return None


def _flatpak_installed(app_id):
    if not shutil.which("flatpak"):
        return False
    for scope in ("--user", "--system"):
        try:
            if subprocess.run(
                ["flatpak", "info", scope, app_id],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=1,
            ).returncode == 0:
                return True
        except Exception:
            pass
    return False


def _app_installed(appid):
    commands = {
        "blender": ("blender",),
        "unityhub": ("unityhub",),
        "unreal": ("UnrealEditor", "unreal-editor"),
        "vscode": ("code", "codium"),
        "gitkraken": ("gitkraken",),
        "krita": ("krita",),
        "obs": ("obs",),
        "godot": ("godot", "godot4"),
        "kdenlive": ("kdenlive",),
        "audacity": ("audacity",),
    }
    flatpaks = {
        "unityhub": "com.unity.UnityHub",
        "vscode": "com.visualstudio.code",
        "gitkraken": "com.axosoft.GitKraken",
        "obs": "com.obsproject.Studio",
        "krita": "org.kde.krita",
        "kdenlive": "org.kde.kdenlive",
    }
    if any(shutil.which(cmd) for cmd in commands.get(appid, ())):
        return True
    fid = flatpaks.get(appid)
    if fid and _flatpak_installed(fid):
        return True
    if appid == "unreal":
        candidates = (
            Path.home() / "UnrealEngine/Engine/Binaries/Linux/UnrealEditor",
            Path("/opt/unreal-engine/Engine/Binaries/Linux/UnrealEditor"),
            Path("/opt/UnrealEngine/Engine/Binaries/Linux/UnrealEditor"),
        )
        return any(p.exists() for p in candidates)
    return False


def scan_local_projects(limit=4):
    """Return only projects that actually exist on this computer."""
    roots = [
        Path.home() / "Projects",
        Path.home() / "Documents",
        Path.home() / "Desktop",
        Path.home() / "Unreal Projects",
        Path.home() / "Unity",
        Path.home() / "VRChat",
    ]
    found = {}
    for root in roots:
        if not root.is_dir():
            continue
        root_depth = len(root.parts)
        try:
            for current, dirs, files in os.walk(root):
                p = Path(current)
                depth = len(p.parts) - root_depth
                if depth > 3:
                    dirs[:] = []
                    continue
                dirs[:] = [
                    d
                    for d in dirs
                    if not d.startswith(".")
                    and d not in {"Library", "Temp", "Logs", "obj", "Binaries", "Intermediate"}
                ]
                if "ProjectVersion.txt" in files and p.name == "ProjectSettings":
                    project = p.parent
                    try:
                        found[str(project.resolve())] = (project.stat().st_mtime, project, "Unity")
                    except OSError:
                        pass
                    dirs[:] = []
                    continue
                if "project.godot" in files:
                    try:
                        found[str(p.resolve())] = (p.stat().st_mtime, p, "Godot")
                    except OSError:
                        pass
                    dirs[:] = []
                    continue
                if any(name.endswith(".uproject") for name in files):
                    try:
                        found[str(p.resolve())] = (p.stat().st_mtime, p, "Unreal")
                    except OSError:
                        pass
                    dirs[:] = []
        except Exception:
            continue

    for root in (Path.home() / "Projects", Path.home() / "Documents"):
        if not root.is_dir():
            continue
        try:
            for f in root.rglob("*.blend"):
                if len(f.relative_to(root).parts) > 4:
                    continue
                found[str(f.resolve())] = (f.stat().st_mtime, f, "Blender")
        except Exception:
            pass

    return sorted(found.values(), key=lambda x: x[0], reverse=True)[:limit]


def _launch_project(entry, owner):
    _, path, kind = entry
    mod = sys.modules.get(owner.__class__.__module__)
    fn = getattr(mod, "launch_project", None) if mod else None
    if callable(fn) and kind != "Blender":
        try:
            fn(path, kind)
            return
        except Exception:
            pass
    try:
        if kind == "Blender" and shutil.which("blender"):
            subprocess.Popen(["blender", str(path)])
        else:
            owner.select(1)
    except Exception:
        try:
            owner.select(1)
        except Exception:
            pass


class LiveCreatorHome(FixedCanvas):
    """Native, functional Creator Mode dashboard."""

    def __init__(self, owner, parent=None):
        super().__init__(parent)
        self.owner = owner
        self._prev_cpu = None
        self._projects = []
        self._app_buttons = {}
        self._build()

        self.metric_timer = QTimer(self)
        self.metric_timer.timeout.connect(self._timer_refresh_metrics)
        self.metric_timer.start(2000)

        self.app_timer = QTimer(self)
        self.app_timer.timeout.connect(self._timer_refresh_apps)
        self.app_timer.start(15000)

        self.project_timer = QTimer(self)
        self.project_timer.timeout.connect(self._timer_refresh_projects)
        self.project_timer.start(15000)

        self.update_timer = QTimer(self)
        self.update_timer.timeout.connect(self._timer_refresh_updates)
        self.update_timer.start(300000)

        self.refresh_system_info()
        self._run_guarded("startup-metrics", self.refresh_metrics)
        self._run_guarded("startup-apps", self.refresh_apps)
        self._run_guarded("startup-projects", self.refresh_projects)

        # Parent the startup timer to the page instead of using the static
        # singleShot overload. This guarantees its lifetime follows the
        # Creator page and gives the callback the same exception guard as all
        # repeating background tasks.
        self.startup_update_timer = QTimer(self)
        self.startup_update_timer.setSingleShot(True)
        self.startup_update_timer.timeout.connect(self._timer_refresh_updates)
        self.startup_update_timer.start(600)

    def _run_guarded(self, label, fn, *args):
        try:
            return fn(*args)
        except Exception:
            _creator_log(
                f"background callback failed label={label}\n"
                + traceback.format_exc()
            )
            try:
                if label.startswith("update"):
                    self.update_status.setText("UPDATE STATUS UNAVAILABLE")
                    self.update_notes.setText(
                        "Creator Mode caught an update-status error without closing the UI. "
                        f"See {CREATOR_RUNTIME_LOG}."
                    )
            except Exception:
                pass
            return None

    def _timer_refresh_metrics(self):
        self._run_guarded("metrics", self.refresh_metrics)

    def _timer_refresh_apps(self):
        self._run_guarded("apps", self.refresh_apps)

    def _timer_refresh_projects(self):
        self._run_guarded("projects", self.refresh_projects)

    def _timer_refresh_updates(self):
        self._run_guarded("update-refresh", self.refresh_updates)

    def _safe_read_update_output(self):
        self._run_guarded("update-output", self._read_update_output)

    def _safe_update_finished(self, code, status):
        self._run_guarded("update-finished", self._update_finished, code, status)

    def _safe_update_error(self, error):
        self._run_guarded("update-process-error", self._update_process_error, error)

    def _build(self):
        self.label("◈  MECHOS", QRect(28, 18, 260, 50), 21, True)
        self.label(
            "CREATOR MODE",
            QRect(700, 14, 520, 58),
            27,
            True,
            "accent",
            Qt.AlignmentFlag.AlignCenter,
        )
        self.cpu_top = self.label("CPU  --", QRect(1360, 20, 120, 40), 11, True, "muted")
        self.ram_top = self.label("RAM  --", QRect(1480, 20, 120, 40), 11, True, "muted")
        self.vram_top = self.label("VRAM  --", QRect(1600, 20, 130, 40), 11, True, "muted")
        self.disk_top = self.label("DISK  --", QRect(1730, 20, 140, 40), 11, True, "muted")

        nav = [
            ("Dashboard", 0),
            ("Projects", 1),
            ("Engines", 2),
            ("Tools", 3),
            ("Assets", 5),
            ("MechClip AI", 6),
            ("Learn", 7),
            ("Community", 8),
            ("Settings", 9),
        ]
        for i, (title, index) in enumerate(nav):
            self.button(
                title,
                "",
                QRect(28, 92 + i * 55, 232, 45),
                lambda _=False, n=index: self.owner.select(n),
                i == 0,
                False,
                12,
            )

        self.label("SYSTEM STATUS", QRect(42, 620, 205, 30), 12, True, "section")
        self.os_label = self.label("OS  --", QRect(42, 654, 205, 34), 10, True)
        self.kernel_label = self.label("KERNEL  --", QRect(42, 688, 205, 34), 10, False, "muted")
        self.uptime_label = self.label("UPTIME  --", QRect(42, 722, 205, 34), 10, False, "muted")
        self.gpu_label = self.label("GPU  --", QRect(42, 756, 205, 64), 9, False, "muted")
        self.driver_label = self.label("DRIVER  --", QRect(42, 816, 205, 42), 9, False, "muted")
        self.button("System Monitor", "Open live monitor", QRect(42, 868, 205, 62), self.open_monitor, True, False, 11)
        self.user_label = self.label(
            f"{os.environ.get('USER') or Path.home().name}\nCreator",
            QRect(42, 958, 205, 62),
            11,
            True,
        )

        self.label("WELCOME TO", QRect(320, 108, 240, 30), 12, True, "section")
        self.label("CREATOR MODE", QRect(320, 140, 560, 74), 34, True)
        self.label(
            "Build. Create. Innovate. Live system data, real projects and working creator tools.",
            QRect(320, 215, 770, 58),
            14,
            False,
            "muted",
        )
        self.button("New Project", "Open project manager", QRect(320, 278, 250, 62), lambda: self.owner.select(1), True)
        self.button("Creator Store", "Install creator tools", QRect(586, 278, 250, 62), lambda: self.owner.select(4))
        self.button("Performance", "Open Performance Center", QRect(852, 278, 280, 62), self.open_performance)

        self.label("CREATOR SHORTCUTS", QRect(1592, 100, 270, 30), 12, True, "section")
        shortcuts = [
            ("New Project", "Project manager", lambda: self.owner.select(1)),
            ("Open Project", "Browse real projects", lambda: self.owner.select(1)),
            ("Project Manager", "Manage projects", lambda: self.owner.select(1)),
            ("Asset Browser", "Creator assets", lambda: self.owner.select(5)),
            ("MechClip AI", "Open clipping tools", lambda: self.owner.select(6)),
            ("Creator Settings", "Preferences", lambda: self.owner.select(9)),
        ]
        for i, (title, sub, fn) in enumerate(shortcuts):
            self.button(title, sub, QRect(1592, 140 + i * 68, 278, 58), fn, i == 0, False, 11)

        self.label("QUICK LAUNCH", QRect(320, 376, 300, 28), 12, True, "section")
        apps = [
            ("Blender", "blender"),
            ("Unity Hub", "unityhub"),
            ("Unreal Engine", "unreal"),
            ("VS Code", "vscode"),
            ("GitKraken", "gitkraken"),
            ("Krita", "krita"),
            ("OBS Studio", "obs"),
        ]
        for i, (title, appid) in enumerate(apps):
            x = 320 + i * 174
            b = self.button(
                title,
                "Checking…",
                QRect(x, 414, 158, 94),
                lambda _=False, a=appid: self.owner.quick(a),
                False,
                False,
                11,
            )
            self._app_buttons[appid] = (b, title)

        self.label("CREATOR TOOLS", QRect(320, 536, 300, 28), 12, True, "section")
        tool_groups = [
            ("3D CREATION", [("Blender", "blender"), ("Krita", "krita"), ("All 3D Tools", "page-tools")]),
            ("GAME ENGINES", [("Unity Hub", "unityhub"), ("Unreal Engine", "unreal"), ("Godot", "godot")]),
            ("WORLDS & AVATARS", [("VRChat Creator", "page-store"), ("Assets", "page-assets"), ("Optimization", "performance")]),
            ("AUDIO & VIDEO", [("OBS Studio", "obs"), ("Kdenlive", "kdenlive"), ("Audacity", "audacity")]),
        ]
        for col, (heading, items) in enumerate(tool_groups):
            x = 320 + col * 304
            self.label(heading, QRect(x + 16, 576, 270, 28), 11, True, "accent")
            for row, (title, action) in enumerate(items):
                self.button(
                    title,
                    "",
                    QRect(x + 16, 610 + row * 48, 270, 40),
                    lambda _=False, a=action: self.tool_action(a),
                    False,
                    False,
                    10,
                )

        self.label("RECENT PROJECTS", QRect(320, 790, 300, 28), 12, True, "section")
        self.project_buttons = []
        for i in range(4):
            b = self.button(
                "Scanning…",
                "",
                QRect(320, 828 + i * 48, 610, 40),
                lambda _=False, n=i: self.open_project_index(n),
                False,
                False,
                10,
            )
            self.project_buttons.append(b)

        self.label("SYSTEM RESOURCES", QRect(964, 790, 300, 28), 12, True, "section")
        self.cpu_metric = self.label("CPU\n--", QRect(964, 832, 138, 86), 16, True, "accent", Qt.AlignmentFlag.AlignCenter)
        self.ram_metric = self.label("RAM\n--", QRect(1112, 832, 138, 86), 16, True, "accent", Qt.AlignmentFlag.AlignCenter)
        self.vram_metric = self.label("VRAM\n--", QRect(1260, 832, 138, 86), 16, True, "accent", Qt.AlignmentFlag.AlignCenter)
        self.disk_metric = self.label("DISK\n--", QRect(1408, 832, 138, 86), 16, True, "accent", Qt.AlignmentFlag.AlignCenter)
        self.cpu_model_label = self.label("CPU: --", QRect(964, 930, 582, 40), 10, False, "muted")
        self.button("Open Performance Center", "Live tuning & diagnostics", QRect(964, 974, 582, 54), self.open_performance, True, False, 11)

        self.label("NEWS & UPDATES", QRect(1592, 582, 270, 30), 12, True, "section")
        self.update_status = self.label("Checking MechOS update status…", QRect(1602, 626, 258, 54), 12, True)
        self.update_versions = self.label("Current --\nLatest --", QRect(1602, 686, 258, 56), 10, False, "accent")
        self.update_notes = self.label(
            "Release notes will appear here from the real update manifest.",
            QRect(1602, 750, 258, 132),
            10,
            False,
            "muted",
        )
        self.update_counts = self.label("Arch --  •  Flatpak --", QRect(1602, 886, 258, 34), 10, True, "muted")
        self.button("Refresh Updates", "Check now", QRect(1602, 930, 124, 54), self.refresh_updates, False, False, 10)
        self.button("View Updates", "Update Center", QRect(1736, 930, 124, 54), self.open_updates, True, False, 10)

        self.button("Gaming Mode", "", QRect(320, 1035, 260, 38), lambda: self.mode("gaming"), False, False, 10)
        self.button("Creator Mode", "", QRect(594, 1035, 260, 38), lambda: None, True, False, 10)
        self.button("Desktop Mode", "", QRect(868, 1035, 260, 38), lambda: self.mode("desktop"), False, False, 10)
        self.button("MechScope", "", QRect(1142, 1035, 260, 38), lambda: self.mode("gaming"), False, False, 10)

    def tool_action(self, action):
        if action == "page-tools":
            self.owner.select(3)
        elif action == "page-store":
            self.owner.select(4)
        elif action == "page-assets":
            self.owner.select(5)
        elif action == "performance":
            self.open_performance()
        else:
            self.owner.quick(action)

    def mode(self, name):
        path = Path("/usr/local/bin/mechos-mode-launch")
        if path.exists():
            try:
                subprocess.Popen([str(path), name])
                return
            except Exception:
                pass
        if name == "gaming":
            try:
                self.owner.mechscope()
            except Exception:
                pass

    def open_monitor(self):
        for cmd in (
            ["plasma-systemmonitor"],
            ["konsole", "-e", "btop"],
            ["konsole", "-e", "htop"],
        ):
            if shutil.which(cmd[0]):
                try:
                    subprocess.Popen(cmd)
                    return
                except Exception:
                    pass

    def open_performance(self):
        self._spawn("/usr/local/bin/mechos-performance-center")

    def open_updates(self):
        self._spawn("/usr/local/bin/mechos-update-center")

    def _spawn(self, path):
        try:
            subprocess.Popen([path])
        except Exception:
            pass

    def refresh_system_info(self):
        gpu, driver = _gpu_info()
        self.os_label.setText(f"OS  MechOS {_release()}")
        self.kernel_label.setText(f"KERNEL  {platform.release()}")
        self.uptime_label.setText(f"UPTIME  {_uptime_text()}")
        self.gpu_label.setText("GPU\n" + gpu)
        self.driver_label.setText("DRIVER  " + driver)
        self.cpu_model_label.setText("CPU: " + _cpu_model())

    def refresh_metrics(self):
        sample = _cpu_sample()
        cpu = None
        if sample and self._prev_cpu:
            total_delta = sample[0] - self._prev_cpu[0]
            idle_delta = sample[1] - self._prev_cpu[1]
            if total_delta > 0:
                cpu = round((1 - idle_delta / total_delta) * 100)
        if sample:
            self._prev_cpu = sample

        ram = _mem_percent()
        vram = _vram_percent()
        disk = _disk_percent()

        def fmt(value):
            return f"{value}%" if value is not None else "N/A"

        self.cpu_top.setText("CPU  " + fmt(cpu))
        self.ram_top.setText("RAM  " + fmt(ram))
        self.vram_top.setText("VRAM  " + fmt(vram))
        self.disk_top.setText("DISK  " + fmt(disk))
        self.cpu_metric.setText("CPU\n" + fmt(cpu))
        self.ram_metric.setText("RAM\n" + fmt(ram))
        self.vram_metric.setText("VRAM\n" + fmt(vram))
        self.disk_metric.setText("DISK\n" + fmt(disk))
        self.uptime_label.setText(f"UPTIME  {_uptime_text()}")

    def refresh_apps(self):
        for appid, (button, title) in self._app_buttons.items():
            installed = _app_installed(appid)
            button.setText(f"{title}\n{'Installed' if installed else 'Not installed'}")

    def refresh_projects(self):
        self._projects = scan_local_projects(4)
        for i, button in enumerate(self.project_buttons):
            if i < len(self._projects):
                _, path, kind = self._projects[i]
                label = path.name if kind != "Blender" else path.stem
                button.setText(f"{label}   •   {kind}\n{path}")
                button.setEnabled(True)
            else:
                if i == 0 and not self._projects:
                    button.setText("No creator projects found on this PC\nOpen Project Manager to create or locate one")
                else:
                    button.setText("—")
                button.setEnabled(i == 0 and not self._projects)

    def open_project_index(self, index):
        if index < len(self._projects):
            _launch_project(self._projects[index], self.owner)
        else:
            self.owner.select(1)

    def refresh_updates(self):
        if not UPDATE_HELPER.exists():
            self.update_status.setText("Update service unavailable")
            self.update_notes.setText("mechos-update-helper is not installed on this system.")
            return

        proc = getattr(self, "_update_proc", None)
        if proc is not None and proc.state() != QProcess.ProcessState.NotRunning:
            return

        self.update_status.setText("Checking for updates…")
        self.update_notes.setText("Reading the real MechOS update channel.")
        self._update_buffer = ""
        self._update_proc = QProcess(self)
        self._update_proc.setProgram(str(UPDATE_HELPER))
        self._update_proc.setArguments(["check"])
        self._update_proc.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        self._update_proc.readyReadStandardOutput.connect(self._safe_read_update_output)
        self._update_proc.finished.connect(self._safe_update_finished)
        self._update_proc.errorOccurred.connect(self._safe_update_error)
        self._update_proc.start()

    def _read_update_output(self):
        proc = getattr(self, "_update_proc", None)
        if proc is None:
            return
        data = bytes(proc.readAllStandardOutput()).decode(errors="replace")
        self._update_buffer += data

    def _update_process_error(self, error):
        proc = getattr(self, "_update_proc", None)
        detail = proc.errorString() if proc is not None else str(error)
        _creator_log(f"update QProcess error={error!r} detail={detail}")
        try:
            self.update_status.setText("UPDATE CHECK FAILED")
            self.update_notes.setText(
                "Creator Mode could not start the update status check. "
                f"See {CREATOR_RUNTIME_LOG}."
            )
        except Exception:
            pass

    def _update_finished(self, code, _status):
        proc = getattr(self, "_update_proc", None)
        if proc is not None:
            data = bytes(proc.readAllStandardOutput()).decode(errors="replace")
            if data:
                self._update_buffer += data
            self._update_proc = None
            proc.deleteLater()

        values = {}
        for line in self._update_buffer.splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip()

        current = values.get("CURRENT_MECHOS_VERSION", _release())
        latest = values.get("LATEST_MECHOS_VERSION", current)
        available = values.get("MECHOS_UPDATE_AVAILABLE") == "1"
        arch = values.get("PACMAN_COUNT", "0")
        flatpak = values.get("FLATPAK_COUNT", "0")
        notes = values.get("MECHOS_RELEASE_NOTES", "").strip()

        if code == 0:
            self.update_status.setText("UPDATE AVAILABLE" if available else "SYSTEM CURRENT")
            self.update_versions.setText(f"Current  {current}\nLatest   {latest}")
            self.update_counts.setText(f"Arch {arch}  •  Flatpak {flatpak}")
            self.update_notes.setText(notes or "No release notes were supplied by the current update manifest.")
        else:
            self.update_status.setText("UPDATE CHECK FAILED")
            self.update_versions.setText(f"Current  {current}")
            tail = self._update_buffer.strip().splitlines()[-3:]
            self.update_notes.setText("\n".join(tail) or "Unable to query the update service.")
            self.update_counts.setText("Arch --  •  Flatpak --")

    def paint_background(self, painter: QPainter):
        painter.fillRect(self.scale_rect(QRect(0, 0, BASE_W, BASE_H)), QColor("#030711"))

        self.panel(painter, QRect(14, 78, 260, 958), "#050914", "#27244a", 18, 1)
        self.panel(painter, QRect(294, 88, 1280, 270), "#070d1b", "#62428f", 22, 2)
        self.panel(painter, QRect(294, 364, 1280, 156), "#060b15", "#263b5b", 18, 1)
        self.panel(painter, QRect(294, 524, 1280, 244), "#060b15", "#263b5b", 18, 1)
        self.panel(painter, QRect(294, 778, 654, 252), "#060b15", "#263b5b", 18, 1)
        self.panel(painter, QRect(952, 778, 622, 252), "#060b15", "#263b5b", 18, 1)
        self.panel(painter, QRect(1582, 88, 306, 468), "#060b15", "#263b5b", 18, 1)
        self.panel(painter, QRect(1582, 566, 306, 464), "#060b15", "#263b5b", 18, 1)

        for col in range(4):
            self.panel(
                painter,
                QRect(310 + col * 304, 568, 292, 186),
                "#08101c",
                "#3a315f" if col == 0 else "#263b5b",
                14,
                1,
            )

        for x in (964, 1112, 1260, 1408):
            self.panel(painter, QRect(x, 832, 138, 86), "#08101c", "#314b70", 14, 1)

        hero = self.scale_rect(QRect(294, 88, 1280, 270))
        grad = QLinearGradient(hero.left(), hero.top(), hero.right(), hero.bottom())
        grad.setColorAt(0.0, QColor("#07111e"))
        grad.setColorAt(0.55, QColor("#180c32"))
        grad.setColorAt(1.0, QColor("#07223a"))
        painter.setBrush(grad)
        painter.setPen(QPen(QColor("#6d4ca5"), max(1, int(self.scale_factor()))))
        painter.drawRoundedRect(hero, int(22 * self.scale_factor()), int(22 * self.scale_factor()))


class CreatorShell(FixedCanvas):
    """Fullscreen Creator Mode shell with a live native home page."""

    def __init__(self, owner, parent=None):
        super().__init__(parent)
        self.owner = owner
        self.build()

    def build(self):
        self.owner.nav = []
        self.owner.stack = self.reg(QStackedWidget(), QRect(0, 0, BASE_W, BASE_H))
        self.home = LiveCreatorHome(self.owner)
        self.owner.stack.addWidget(self.home)

        factories = [
            self.owner.projects,
            lambda: self.owner.catalog(
                "GAME ENGINES", ["unityhub", "unreal", "godot", "vscode", "gitkraken"]
            ),
            lambda: self.owner.catalog(
                "CREATOR TOOLS",
                ["blender", "krita", "obs", "kdenlive", "audacity", "lmms", "vscode", "gitkraken"],
            ),
            self.owner.app_store,
            self.owner.assets,
            self.owner.mechclip,
            self.owner.learn,
            self.owner.community,
            self.owner.settings,
        ]
        for fn in factories:
            try:
                self.owner.stack.addWidget(fn())
            except Exception as exc:
                self.owner.stack.addWidget(self._error(str(exc)))

        self.owner.cpu = self._hidden_label()
        self.owner.ram = self._hidden_label()
        self.owner.vram = self._hidden_label()
        self.owner.disk = self._hidden_label()
        self.owner.status = self._hidden_label()
        self.owner.select(0)

    def _hidden_label(self):
        q = QLabel(self)
        q.hide()
        return q

    def _error(self, text):
        w = QWidget()
        q = QLabel("Creator page could not load:\n" + text, w)
        q.setGeometry(40, 40, 1000, 120)
        q.setWordWrap(True)
        return w

    def paint_background(self, painter):
        painter.fillRect(self.scale_rect(QRect(0, 0, BASE_W, BASE_H)), QColor("#030711"))
