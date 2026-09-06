#!/usr/bin/env python3
"""Real application-icon resolver for MechOS Creator surfaces.

The Creator visual layer historically generated monogram badges for every
button. That is useful as an offline fallback, but it also hides the actual
icons supplied by installed applications and Flatpak/AppStream metadata.

Hotfix 22 keeps MechOS-generated badges for MechOS/navigation controls while
preferring application-owned desktop/theme/AppStream icons for creator apps.
No third-party logo artwork is bundled by MechOS.
"""
from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path

from PyQt6.QtCore import QSize, Qt
from PyQt6.QtGui import QColor, QIcon, QPainter, QPen, QPixmap

# MECHOS_CREATOR_REAL_ICONS_V22

APP_HINTS = {
    "blender": {
        "desktop": ("blender.desktop", "org.blender.Blender.desktop"),
        "theme": ("blender", "org.blender.Blender"),
        "flatpak": ("org.blender.Blender",),
        "tokens": ("blender",),
    },
    "unityhub": {
        "desktop": ("unityhub.desktop", "com.unity.UnityHub.desktop", "unity-hub.desktop"),
        "theme": ("unityhub", "unity-hub", "com.unity.UnityHub"),
        "flatpak": ("com.unity.UnityHub",),
        "tokens": ("unity hub", "unityhub"),
    },
    "unreal": {
        "desktop": ("unreal-editor.desktop", "UnrealEditor.desktop", "unrealengine.desktop"),
        "theme": ("unreal-editor", "unrealengine", "UnrealEditor"),
        "flatpak": (),
        "tokens": ("unreal engine", "unreal editor", "unrealeditor"),
    },
    "vscode": {
        "desktop": ("code.desktop", "visual-studio-code.desktop", "com.visualstudio.code.desktop", "codium.desktop", "com.vscodium.codium.desktop"),
        "theme": ("visual-studio-code", "code", "com.visualstudio.code", "codium", "com.vscodium.codium"),
        "flatpak": ("com.visualstudio.code", "com.vscodium.codium"),
        "tokens": ("visual studio code", "vscode", "vscodium", "code"),
    },
    "gitkraken": {
        "desktop": ("gitkraken.desktop", "com.axosoft.GitKraken.desktop"),
        "theme": ("gitkraken", "com.axosoft.GitKraken"),
        "flatpak": ("com.axosoft.GitKraken",),
        "tokens": ("gitkraken",),
    },
    "krita": {
        "desktop": ("org.kde.krita.desktop", "krita.desktop"),
        "theme": ("krita", "org.kde.krita"),
        "flatpak": ("org.kde.krita",),
        "tokens": ("krita",),
    },
    "obs": {
        "desktop": ("com.obsproject.Studio.desktop", "obs.desktop", "obs-studio.desktop"),
        "theme": ("com.obsproject.Studio", "obs", "obs-studio"),
        "flatpak": ("com.obsproject.Studio",),
        "tokens": ("obs studio", "obs"),
    },
    "godot": {
        "desktop": ("org.godotengine.Godot.desktop", "godot.desktop", "godot4.desktop"),
        "theme": ("godot", "godot4", "org.godotengine.Godot"),
        "flatpak": ("org.godotengine.Godot",),
        "tokens": ("godot",),
    },
    "kdenlive": {
        "desktop": ("org.kde.kdenlive.desktop", "kdenlive.desktop"),
        "theme": ("kdenlive", "org.kde.kdenlive"),
        "flatpak": ("org.kde.kdenlive",),
        "tokens": ("kdenlive",),
    },
    "audacity": {
        "desktop": ("audacity.desktop", "org.audacityteam.Audacity.desktop"),
        "theme": ("audacity", "org.audacityteam.Audacity"),
        "flatpak": ("org.audacityteam.Audacity",),
        "tokens": ("audacity",),
    },
    "lmms": {
        "desktop": ("lmms.desktop", "io.lmms.LMMS.desktop"),
        "theme": ("lmms", "io.lmms.LMMS"),
        "flatpak": ("io.lmms.LMMS",),
        "tokens": ("lmms",),
    },
    "discord": {
        "desktop": ("discord.desktop", "com.discordapp.Discord.desktop"),
        "theme": ("discord", "com.discordapp.Discord"),
        "flatpak": ("com.discordapp.Discord",),
        "tokens": ("discord",),
    },
    "vrchat": {
        "desktop": ("vrchat-creator-companion.desktop", "vrchatcreatorcompanion.desktop", "vcc.desktop"),
        "theme": ("vrchat-creator-companion", "vrchatcreatorcompanion", "vcc"),
        "flatpak": (),
        "tokens": ("vrchat creator", "creator companion", "vrchat"),
    },
    "davinci": {
        "desktop": ("com.blackmagicdesign.resolve.desktop", "davinci-resolve.desktop", "resolve.desktop"),
        "theme": ("com.blackmagicdesign.resolve", "davinci-resolve", "resolve"),
        "flatpak": (),
        "tokens": ("davinci resolve", "davinci", "resolve"),
    },
}


def _desktop_roots() -> list[Path]:
    home = Path.home()
    roots = [
        home / ".local/share/applications",
        Path("/usr/local/share/applications"),
        Path("/usr/share/applications"),
        home / ".local/share/flatpak/exports/share/applications",
        Path("/var/lib/flatpak/exports/share/applications"),
    ]
    seen = set()
    result = []
    for root in roots:
        key = str(root)
        if key not in seen:
            seen.add(key)
            result.append(root)
    return result


def _read_desktop(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    try:
        for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            if key in {"Name", "Icon", "Exec", "StartupWMClass"} and key not in values:
                values[key] = value.strip()
    except Exception:
        return {}
    return values


def _icon_from_token(token: str) -> QIcon:
    token = (token or "").strip()
    if not token:
        return QIcon()
    expanded = os.path.expandvars(os.path.expanduser(token))
    path = Path(expanded)
    if path.is_absolute() and path.is_file():
        icon = QIcon(str(path))
        if not icon.isNull():
            return icon
    icon = QIcon.fromTheme(token)
    if not icon.isNull():
        return icon
    return _find_icon_file(token)


@lru_cache(maxsize=128)
def _find_icon_file(token: str) -> QIcon:
    token = Path(token).stem
    if not token:
        return QIcon()
    roots = [
        Path.home() / ".local/share/icons",
        Path("/usr/local/share/icons"),
        Path("/usr/share/icons"),
        Path("/usr/share/pixmaps"),
        Path.home() / ".local/share/flatpak/exports/share/icons",
        Path("/var/lib/flatpak/exports/share/icons"),
    ]
    extensions = (".svg", ".png", ".xpm")
    for root in roots:
        if not root.is_dir():
            continue
        if root.name == "pixmaps":
            for ext in extensions:
                candidate = root / (token + ext)
                if candidate.is_file():
                    return QIcon(str(candidate))
            continue
        # Prefer common high-resolution/icon-theme locations before a bounded
        # recursive search. This keeps Creator startup responsive.
        for size in ("scalable", "256x256", "128x128", "64x64", "48x48"):
            for category in ("apps", "applications"):
                for ext in extensions:
                    candidate = root / "hicolor" / size / category / (token + ext)
                    if candidate.is_file():
                        return QIcon(str(candidate))
        try:
            hits = []
            for ext in extensions:
                hits.extend(root.glob(f"**/{token}{ext}"))
                if hits:
                    break
            for candidate in hits[:8]:
                if candidate.is_file():
                    return QIcon(str(candidate))
        except Exception:
            pass
    return QIcon()


def _flatpak_appstream_icon(app_id: str) -> QIcon:
    home = Path.home()
    bases = [
        home / ".local/share/flatpak/appstream",
        Path("/var/lib/flatpak/appstream"),
    ]
    for base in bases:
        if not base.is_dir():
            continue
        try:
            for active in base.glob("*/**/active"):
                for size in ("128x128", "64x64"):
                    for suffix in (".png", ".svg"):
                        candidate = active / "icons" / size / (app_id + suffix)
                        if candidate.is_file():
                            return QIcon(str(candidate))
        except Exception:
            pass
    return QIcon()


def _desktop_icon(key: str) -> QIcon:
    hints = APP_HINTS.get(key, {})
    desktop_ids = tuple(hints.get("desktop", ()))
    tokens = tuple(str(x).casefold() for x in hints.get("tokens", ()))

    # Exact desktop IDs first.
    for root in _desktop_roots():
        if not root.is_dir():
            continue
        for desktop_id in desktop_ids:
            path = root / desktop_id
            if not path.is_file():
                continue
            values = _read_desktop(path)
            icon = _icon_from_token(values.get("Icon", ""))
            if not icon.isNull():
                return icon

    # Then search desktop entry metadata by app name/Exec token. Limit the
    # number of candidates so Creator Mode remains fast on systems with many
    # desktop entries.
    for root in _desktop_roots():
        if not root.is_dir():
            continue
        try:
            entries = list(root.glob("*.desktop"))[:800]
        except Exception:
            continue
        for path in entries:
            low_name = path.name.casefold()
            if not any(token.replace(" ", "") in low_name.replace("-", "").replace("_", "") for token in tokens):
                values = _read_desktop(path)
                haystack = " ".join((values.get("Name", ""), values.get("Exec", ""), values.get("StartupWMClass", ""))).casefold()
                if not any(token in haystack for token in tokens):
                    continue
            else:
                values = _read_desktop(path)
            icon = _icon_from_token(values.get("Icon", ""))
            if not icon.isNull():
                return icon
    return QIcon()


@lru_cache(maxsize=64)
def application_icon(key: str) -> QIcon:
    key = (key or "").strip().lower()
    hints = APP_HINTS.get(key)
    if not hints:
        return QIcon()

    icon = _desktop_icon(key)
    if not icon.isNull():
        return icon

    for app_id in hints.get("flatpak", ()):
        icon = _flatpak_appstream_icon(str(app_id))
        if not icon.isNull():
            return icon

    for token in hints.get("theme", ()):
        icon = _icon_from_token(str(token))
        if not icon.isNull():
            return icon
    return QIcon()


def _key_from_title(title: str, fallback: str | None = None) -> str | None:
    low = " ".join((title or "").split()).casefold()
    direct = {
        "blender": "blender",
        "unity hub": "unityhub",
        "unity 6": "unityhub",
        "unreal engine": "unreal",
        "visual studio code": "vscode",
        "vs code": "vscode",
        "gitkraken": "gitkraken",
        "krita": "krita",
        "obs studio": "obs",
        "godot": "godot",
        "kdenlive": "kdenlive",
        "audacity": "audacity",
        "lmms": "lmms",
        "discord": "discord",
        "vrchat creator": "vrchat",
        "vrchat creator companion": "vrchat",
        "davinci resolve": "davinci",
    }
    if low in direct:
        return direct[low]
    for title_key, app_key in direct.items():
        if title_key in low:
            return app_key
    return fallback if fallback in APP_HINTS else None


def _status_overlay(icon: QIcon, size: int, installed: bool | None) -> QIcon:
    if icon.isNull():
        return icon
    px_size = max(48, size * 2)
    pix = icon.pixmap(px_size, px_size)
    if pix.isNull() or installed is None:
        return icon
    canvas = QPixmap(px_size, px_size)
    canvas.fill(Qt.GlobalColor.transparent)
    painter = QPainter(canvas)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)
    painter.drawPixmap(0, 0, pix)
    dot = max(10, px_size // 5)
    margin = max(2, px_size // 24)
    painter.setBrush(QColor("#54f3b0") if installed else QColor("#61728d"))
    painter.setPen(QPen(QColor("#07101d"), max(1, px_size // 32)))
    painter.drawEllipse(px_size - dot - margin, px_size - dot - margin, dot, dot)
    painter.end()
    return QIcon(canvas)


def install(visual_module) -> None:
    """Replace v10's app-badge decorator with real-icon-first decoration."""
    if getattr(visual_module, "MECHOS_CREATOR_REAL_ICONS_V22_ACTIVE", False):
        return
    original = visual_module.decorate_button

    def decorate_button(button, key=None, size=30, installed=None):
        title_prop = button.property("mechosTitle")
        title = str(title_prop) if title_prop is not None else button.text().splitlines()[0]
        app_key = _key_from_title(title, key)
        if app_key:
            icon = application_icon(app_key)
            if not icon.isNull():
                button.setIcon(_status_overlay(icon, max(18, int(size)), installed))
                button.setIconSize(QSize(size, size))
                button.setProperty("mechosVisualV10", True)
                button.setProperty("mechosRealAppIconV22", app_key)
                return
        original(button, key, size, installed)
        button.setProperty("mechosRealAppIconV22", "fallback")

    visual_module.decorate_button = decorate_button
    visual_module.MECHOS_CREATOR_REAL_ICONS_V22_ACTIVE = True
