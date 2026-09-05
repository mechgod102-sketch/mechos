#!/usr/bin/env python3
"""MechOS provider install controller for Hotfix 13.

MechOS never bypasses provider authentication, ownership, DRM, or licensing.
It translates a Unified Store install request into the provider-supported client
or backend that actually owns the download.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "mechos/store"
LOG = STATE_DIR / "game-install-controller.log"
QUEUE = STATE_DIR / "install-queue.json"
HEROIC_FLATPAK = "com.heroicgameslauncher.hgl"


def log(message: str) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with LOG.open("a", encoding="utf-8") as fh:
        fh.write(f"[{time.strftime('%F %T')}] {message}\n")


def load_queue() -> list[dict]:
    try:
        data = json.loads(QUEUE.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except Exception:
        return []


def save_job(provider: str, identifier: str, state: str, backend: str, detail: str = "") -> None:
    jobs = load_queue()[-39:]
    jobs.append({
        "provider": provider,
        "identifier": identifier,
        "state": state,
        "backend": backend,
        "detail": detail,
        "updated_at": int(time.time()),
    })
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = QUEUE.with_suffix(".tmp")
    tmp.write_text(json.dumps(jobs, indent=2) + "\n", encoding="utf-8")
    tmp.replace(QUEUE)


def launch(args: list[str], provider: str, identifier: str, backend: str) -> int:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    out = LOG.open("a", encoding="utf-8")
    try:
        proc = subprocess.Popen(args, stdout=out, stderr=subprocess.STDOUT, start_new_session=True)
    except Exception as exc:
        save_job(provider, identifier, "failed", backend, str(exc))
        log(f"launch failed provider={provider} backend={backend}: {exc}")
        return 1
    save_job(provider, identifier, "handed-off", backend, f"pid={proc.pid}")
    log(f"handoff provider={provider} id={identifier!r} backend={backend} pid={proc.pid}")
    return 0


def heroic_command() -> list[str] | None:
    if shutil.which("flatpak"):
        probe = subprocess.run(
            ["flatpak", "info", HEROIC_FLATPAK],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if probe.returncode == 0:
            return ["flatpak", "run", HEROIC_FLATPAK]
    for cmd in ("heroic", "heroic-games-launcher"):
        if shutil.which(cmd):
            return [cmd]
    return None


def extract_steam_id(raw: str) -> str | None:
    raw = raw.strip()
    match = re.search(r"(?:steam://install/|store\.steampowered\.com/app/)?(\d{2,12})(?:/|\b|$)", raw)
    return match.group(1) if match else None


def extract_lutris_slug(raw: str) -> str | None:
    value = raw.strip()
    if value.startswith("lutris:"):
        value = value.split(":", 1)[1]
    elif "lutris.net/games/" in value:
        try:
            value = urlparse(value).path.rstrip("/").split("/")[-1]
        except Exception:
            return None
    value = value.strip().lower()
    return value if re.fullmatch(r"[a-z0-9][a-z0-9._+-]{1,120}", value) else None


def install_steam(identifier: str) -> int:
    appid = extract_steam_id(identifier)
    if not appid:
        print("Steam install needs an AppID or a Steam store URL containing /app/<AppID>.", file=sys.stderr)
        return 2
    if not shutil.which("steam") and not shutil.which("xdg-open"):
        print("Steam is not installed.", file=sys.stderr)
        return 3
    # The Steam client owns authentication, licensing, install location and bytes.
    return launch(["xdg-open", f"steam://install/{appid}"], "steam", appid, "steam-protocol")


def install_lutris(identifier: str) -> int:
    slug = extract_lutris_slug(identifier)
    if not slug:
        print("Lutris install needs an installer slug or lutris.net/games/<slug> URL.", file=sys.stderr)
        return 2
    if not shutil.which("lutris"):
        print("Lutris is not installed.", file=sys.stderr)
        return 3
    # Lutris documents lutris:<installer-slug> as its installer URI.
    return launch(["lutris", f"lutris:{slug}"], "lutris", slug, "lutris-installer-uri")


def install_epic(identifier: str) -> int:
    value = identifier.strip()
    if not value:
        return open_heroic("epic", value)
    if shutil.which("legendary"):
        return launch(
            ["legendary", "install", value, "--platform", "Windows", "--skip-dlcs", "-y"],
            "epic", value, "legendary",
        )
    return open_heroic("epic", value)


def install_amazon(identifier: str) -> int:
    value = identifier.strip()
    if not value:
        return open_heroic("amazon", value)
    if shutil.which("nile"):
        return launch(["nile", "install", value], "amazon", value, "nile")
    return open_heroic("amazon", value)


def open_heroic(provider: str, identifier: str) -> int:
    cmd = heroic_command()
    if cmd is None:
        print("Heroic Games Launcher is not installed.", file=sys.stderr)
        return 3
    # Heroic owns Epic/GOG/Amazon authentication and uses Legendary/GOGDL/Nile.
    # We intentionally do not scrape store web pages or bypass provider accounts.
    rc = launch(cmd, provider, identifier, "heroic")
    if rc == 0:
        save_job(provider, identifier, "provider-ui", "heroic", "Complete/confirm the install in Heroic when required.")
    return rc


def install(provider: str, identifier: str) -> int:
    p = provider.strip().lower().replace(" ", "")
    aliases = {
        "epicgames": "epic", "epic": "epic",
        "gog.com": "gog", "gog": "gog",
        "amazongames": "amazon", "amazon": "amazon",
        "heroic": "heroic", "steam": "steam", "lutris": "lutris",
    }
    p = aliases.get(p, p)
    log(f"install request provider={p} id={identifier!r}")
    if p == "steam":
        return install_steam(identifier)
    if p == "lutris":
        return install_lutris(identifier)
    if p == "epic":
        return install_epic(identifier)
    if p == "amazon":
        return install_amazon(identifier)
    if p in {"gog", "heroic"}:
        return open_heroic(p, identifier.strip())
    print(f"Unsupported provider: {provider}", file=sys.stderr)
    return 2


def status() -> int:
    jobs = load_queue()
    if not jobs:
        print("No MechOS install handoffs recorded yet.")
        return 0
    for job in jobs[-12:]:
        print(
            f"{job.get('provider','?'):8} {job.get('state','?'):12} "
            f"{job.get('backend','?'):18} {job.get('identifier','')}"
        )
    return 0


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] == "status":
        return status()
    if len(sys.argv) >= 4 and sys.argv[1] == "install":
        return install(sys.argv[2], " ".join(sys.argv[3:]))
    print("Usage: mechos-game-install {status|install <steam|epic|gog|amazon|heroic|lutris> <provider-id-or-url>}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
