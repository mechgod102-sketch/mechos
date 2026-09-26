#!/usr/bin/env python3
# MECHOS_RESTART_MAINTENANCE_V1
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

BASE = "https://raw.githubusercontent.com/mechgod102-sketch/mechos/main"
POWERCTL_URL = BASE + "/scripts/mechos-powerctl-v1.sh"
REBOOT_URL = BASE + "/scripts/mechos-reboot-frozen-v1.sh"

POWERCTL = Path("/usr/local/libexec/mechos-powerctl-v1")
REBOOT = Path("/usr/local/bin/mechos-reboot")
BACKUPS = Path("/var/lib/mechos/power-infrastructure-backups")
LOG = Path("/var/log/mechos-restart-maintenance-v1.log")

def log(msg: str) -> None:
    line = f"[{time.strftime('%Y-%m-%dT%H:%M:%S%z')}] [restart-maintenance-v1] {msg}"
    print(line, flush=True)
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with LOG.open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except Exception:
        pass

def require_root() -> None:
    if os.geteuid() == 0:
        return
    pkexec = shutil.which("pkexec")
    if not pkexec:
        raise SystemExit("Administrator permission is required and pkexec is unavailable.")
    os.execv(pkexec, [pkexec, "/usr/bin/python3", str(Path(__file__).resolve())])

def download(url: str, dst: Path) -> None:
    req = urllib.request.Request(
        url,
        headers={
            "Cache-Control": "no-cache",
            "User-Agent": "MechOS-Restart-Maintenance/1",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as src, dst.open("wb") as out:
        shutil.copyfileobj(src, out)

def validate_shell(path: Path, marker: str) -> None:
    result = subprocess.run(
        ["/usr/bin/bash", "-n", str(path)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=15,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Shell validation failed for {path.name}: {result.stdout.strip()}")
    text = path.read_text(encoding="utf-8", errors="replace")
    if marker not in text:
        raise RuntimeError(f"Expected marker {marker} missing from {path.name}")
    if "loginctl reboot" in text:
        raise RuntimeError(f"Legacy loginctl reboot path unexpectedly present in {path.name}")

def backup_existing() -> Path:
    BACKUPS.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    dst = BACKUPS / f"restart-before-maintenance-v1-{stamp}"
    dst.mkdir(parents=True, exist_ok=True)
    for src in (POWERCTL, REBOOT):
        if src.exists() or src.is_symlink():
            out = dst / src.name
            if src.is_symlink():
                out.symlink_to(os.readlink(src))
            elif src.is_file():
                shutil.copy2(src, out)
    os.chmod(dst, 0o700)
    return dst

def install(src: Path, dst: Path, mode: int = 0o755) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(dst.name + f".maintenance-new.{os.getpid()}")
    shutil.copyfile(src, tmp)
    os.chmod(tmp, mode)
    os.replace(tmp, dst)

def main() -> int:
    require_root()

    bash = subprocess.run(
        ["/usr/bin/bash", "--version"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=10,
    )
    if bash.returncode != 0:
        raise RuntimeError("/usr/bin/bash cannot execute; repair the base OS before restart maintenance.")

    log("Starting frozen restart infrastructure repair.")
    with tempfile.TemporaryDirectory(prefix="mechos-restart-maint-") as td:
        td = Path(td)
        p = td / "mechos-powerctl-v1"
        r = td / "mechos-reboot"
        download(POWERCTL_URL, p)
        download(REBOOT_URL, r)

        validate_shell(p, "MECHOS_POWERCTL_V1_FROZEN")
        validate_shell(r, "MECHOS_REBOOT_FROZEN_V1")

        backup = backup_existing()
        log(f"Backed up current restart files to {backup}")

        install(p, POWERCTL)
        install(r, REBOOT)

        selftest = subprocess.run(
            [str(POWERCTL), "selftest"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=15,
        )
        log(selftest.stdout.strip())
        if selftest.returncode != 0 or "MECHOS_POWERCTL_SELFTEST=1" not in selftest.stdout:
            raise RuntimeError("Frozen power authority self-test failed.")

        wrapper_check = subprocess.run(
            ["/usr/bin/bash", "-n", str(REBOOT)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=10,
        )
        if wrapper_check.returncode != 0:
            raise RuntimeError("Frozen restart wrapper validation failed after install.")

    print("MECHOS_RESTART_INFRASTRUCTURE_REPAIR_OK=1")
    print("MECHOS_RESTART_AUTHORITY=/usr/local/libexec/mechos-powerctl-v1")
    print("MECHOS_RELEASE_VERSION_UNCHANGED=1")
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        log(f"ERROR: {exc}")
        raise SystemExit(1)
