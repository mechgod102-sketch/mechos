#!/usr/bin/env python3
# MECHOS_UPDATE_CENTER_MAINTENANCE_V1
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request

BASE = "https://raw.githubusercontent.com/mechgod102-sketch/mechos/main"
EXPECTED_KEY_FP = "03ae056eb65a505b8239b8b123b6437eec3afc906b517ff2a3d8e08607fe4391"

FILES = {
    "helper-launcher": "scripts/mechos-update-helper-launcher-v38.sh",
    "center-launcher": "scripts/mechos-update-center-launcher-v38.sh",
    "helper-core": "scripts/mechos-update-helper-core-v39.sh",
    "center-backend": "scripts/mechos-update-center-reference-v8.py",
    "transaction": "scripts/mechos-update-transaction-v15.sh",
    "switcher": "scripts/mechos-update-engine-switch-v38.sh",
    "self-repair": "scripts/mechos-update-self-repair-v0313.sh",
    "reboot": "scripts/mechos-reboot-frozen-v1.sh",
    "powerctl": "scripts/mechos-powerctl-v1.sh",
    "legacy-helper": "scripts/mechos-update-helper-v37.sh",
    "public-key": "updates/mechos-update-signing-public.pem",
}

ROOT = Path("/")
ENGINE = Path("/usr/local/share/mechos/update-engine")
RECOVERY = Path("/usr/local/share/mechos/update-recovery")
SLOT_NAME = "infrastructure-v1"
SLOT = ENGINE / "slots" / SLOT_NAME
CURRENT = ENGINE / "current"
BACKUP_DIR = Path("/var/lib/mechos/update-infrastructure-backups")
LOG = Path("/var/log/mechos-update-maintenance-v1.log")

MARKERS = {
    "helper-launcher": "MECHOS_UPDATE_HELPER_AB_LAUNCHER_V38",
    "center-launcher": "MECHOS_UPDATE_CENTER_AB_LAUNCHER_V38",
    "helper-core": "MECHOS_UPDATE_HELPER_CORE_V39_PACKAGE_REFRESH_STATUS",
    "center-backend": "MECHOS_HOTFIX5_HELPER_HEALTH_FIRST_V1",
    "transaction": "MECHOS_UPDATE_TRANSACTION_V15_AB_ENGINE_ISOLATION_V1",
    "switcher": "MECHOS_UPDATE_ENGINE_SWITCH_V38",
    "self-repair": "MECHOS_UPDATE_SELF_REPAIR_V0313_AB_ENGINE",
}

def log(msg: str) -> None:
    line = f"[{time.strftime('%Y-%m-%dT%H:%M:%S%z')}] [updater-maintenance-v1] {msg}"
    print(line, flush=True)
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with LOG.open("a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except Exception:
        pass

def run(args: list[str], *, check: bool = True, timeout: int = 30) -> subprocess.CompletedProcess:
    return subprocess.run(
        args,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=check,
        timeout=timeout,
    )

def require_root() -> None:
    if os.geteuid() == 0:
        return
    pkexec = shutil.which("pkexec")
    if not pkexec:
        raise SystemExit("Administrator permission is required and pkexec is unavailable.")
    os.execv(pkexec, [pkexec, "/usr/bin/python3", str(Path(__file__).resolve())])

def download(url: str, dst: Path) -> None:
    req = urllib.request.Request(url, headers={"Cache-Control": "no-cache", "User-Agent": "MechOS-Updater-Maintenance/1"})
    with urllib.request.urlopen(req, timeout=30) as src, dst.open("wb") as out:
        shutil.copyfileobj(src, out)

def validate_shell(path: Path, marker: str | None = None) -> None:
    result = run(["/usr/bin/bash", "-n", str(path)], check=False)
    if result.returncode != 0:
        raise RuntimeError(f"Shell validation failed for {path.name}: {result.stdout.strip()}")
    if marker and marker not in path.read_text(encoding="utf-8", errors="replace"):
        raise RuntimeError(f"Expected marker {marker} missing from {path.name}")

def validate_python(path: Path, marker: str | None = None) -> None:
    text = path.read_text(encoding="utf-8")
    compile(text, str(path), "exec")
    if marker and marker not in text:
        raise RuntimeError(f"Expected marker {marker} missing from {path.name}")

def key_fingerprint(path: Path) -> str:
    proc = subprocess.Popen(
        ["/usr/bin/openssl", "pkey", "-pubin", "-in", str(path), "-outform", "DER"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    out, err = proc.communicate(timeout=15)
    if proc.returncode != 0:
        raise RuntimeError(f"Invalid updater public key: {err.decode(errors='replace').strip()}")
    return hashlib.sha256(out).hexdigest()

def backup_existing() -> Path:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = BACKUP_DIR / f"updater-before-maintenance-v1-{stamp}.tar"
    paths = [
        Path("/usr/local/bin/mechos-update-helper"),
        Path("/usr/local/bin/mechos-update-center"),
        Path("/usr/local/bin/mechos-reboot"),
        Path("/usr/local/libexec/mechos-powerctl-v1"),
        Path("/usr/local/libexec/mechos-update-engine-switch-v38"),
        Path("/usr/local/libexec/mechos-update-self-repair-v0313"),
        Path("/etc/mechos/update-signing-public.pem"),
        ENGINE,
        RECOVERY,
    ]
    with tarfile.open(backup, "w") as tf:
        for p in paths:
            try:
                if p.exists() or p.is_symlink():
                    tf.add(p, arcname=str(p).lstrip("/"), recursive=True)
            except FileNotFoundError:
                pass
    os.chmod(backup, 0o600)
    return backup

def install_file(src: Path, dst: Path, mode: int) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(dst.name + f".maintenance-new.{os.getpid()}")
    shutil.copyfile(src, tmp)
    os.chmod(tmp, mode)
    os.replace(tmp, dst)

def atomic_symlink(target: Path, link: Path) -> None:
    link.parent.mkdir(parents=True, exist_ok=True)
    tmp = link.with_name(link.name + f".maintenance-new.{os.getpid()}")
    try:
        tmp.unlink()
    except FileNotFoundError:
        pass
    os.symlink(str(target), str(tmp))
    os.replace(tmp, link)

def main() -> int:
    require_root()
    log("Starting one-time frozen Update Center infrastructure repair.")

    # The frozen updater uses bash. Verify the base interpreter itself before
    # touching updater files so an OS-level execution failure is not mislabeled
    # as another Update Center problem.
    bash_check = run(["/usr/bin/bash", "--version"], check=False)
    if bash_check.returncode != 0:
        raise RuntimeError("/usr/bin/bash cannot execute; repair the base OS interpreter before updater maintenance.")

    for cmd in ("/usr/bin/python3", "/usr/bin/openssl"):
        if not Path(cmd).exists():
            raise RuntimeError(f"Required base command missing: {cmd}")

    with tempfile.TemporaryDirectory(prefix="mechos-updater-maint-") as td:
        stage = Path(td)
        fetched: dict[str, Path] = {}
        for name, rel in FILES.items():
            dst = stage / name
            log(f"Fetching {rel}")
            download(f"{BASE}/{rel}", dst)
            fetched[name] = dst

        validate_shell(fetched["helper-launcher"], MARKERS["helper-launcher"])
        validate_shell(fetched["center-launcher"], MARKERS["center-launcher"])
        validate_shell(fetched["helper-core"], MARKERS["helper-core"])
        validate_python(fetched["center-backend"], MARKERS["center-backend"])
        validate_shell(fetched["transaction"], MARKERS["transaction"])
        validate_shell(fetched["switcher"], MARKERS["switcher"])
        validate_shell(fetched["self-repair"], MARKERS["self-repair"])
        validate_shell(fetched["reboot"], "MECHOS_REBOOT_FROZEN_V1")
        validate_shell(fetched["powerctl"], "MECHOS_POWERCTL_V1_FROZEN")
        validate_shell(fetched["legacy-helper"], "MECHOS_UPDATE_HELPER_V37_SIGNED_MANIFEST_V1")

        downloaded_fp = key_fingerprint(fetched["public-key"])
        if downloaded_fp != EXPECTED_KEY_FP:
            raise RuntimeError(
                f"Downloaded signing key fingerprint mismatch: expected {EXPECTED_KEY_FP}, got {downloaded_fp}"
            )

        installed_key = Path("/etc/mechos/update-signing-public.pem")
        if installed_key.exists() and installed_key.stat().st_size:
            try:
                installed_fp = key_fingerprint(installed_key)
            except Exception as exc:
                raise RuntimeError(
                    f"Existing signing key is invalid; refusing silent replacement: {exc}"
                ) from exc
            if installed_fp != EXPECTED_KEY_FP:
                raise RuntimeError(
                    "Existing signing key does not match the pinned MechOS key; refusing silent replacement."
                )

        backup = backup_existing()
        log(f"Backed up current updater infrastructure to {backup}")

        # Stage a complete engine slot before changing current.
        slot_tmp = ENGINE / "slots" / f".{SLOT_NAME}.new.{os.getpid()}"
        if slot_tmp.exists():
            shutil.rmtree(slot_tmp)
        slot_tmp.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(fetched["helper-core"], slot_tmp / "mechos-update-helper-core")
        shutil.copyfile(fetched["center-backend"], slot_tmp / "mechos-update-center-backend.py")
        shutil.copyfile(fetched["transaction"], slot_tmp / "mechos-update-transaction")
        (slot_tmp / "version").write_text(SLOT_NAME + "\n", encoding="utf-8")
        for p in (
            slot_tmp / "mechos-update-helper-core",
            slot_tmp / "mechos-update-center-backend.py",
            slot_tmp / "mechos-update-transaction",
        ):
            os.chmod(p, 0o755)

        validate_shell(slot_tmp / "mechos-update-helper-core", MARKERS["helper-core"])
        validate_python(slot_tmp / "mechos-update-center-backend.py", MARKERS["center-backend"])
        validate_shell(slot_tmp / "mechos-update-transaction", MARKERS["transaction"])

        SLOT.parent.mkdir(parents=True, exist_ok=True)
        if SLOT.exists():
            shutil.rmtree(SLOT)
        os.replace(slot_tmp, SLOT)

        # Independent recovery copies for the stable public launchers.
        install_file(fetched["helper-launcher"], RECOVERY / "mechos-update-helper-launcher-v38", 0o755)
        install_file(fetched["center-launcher"], RECOVERY / "mechos-update-center-launcher-v38", 0o755)
        install_file(fetched["center-backend"], RECOVERY / "mechos-update-center-v8.py", 0o755)
        install_file(fetched["legacy-helper"], RECOVERY / "mechos-update-helper-v37.sh", 0o755)
        install_file(fetched["reboot"], RECOVERY / "mechos-reboot", 0o755)
        install_file(fetched["public-key"], RECOVERY / "mechos-update-signing-public.pem", 0o644)

        install_file(fetched["switcher"], Path("/usr/local/libexec/mechos-update-engine-switch-v38"), 0o755)
        install_file(fetched["self-repair"], Path("/usr/local/libexec/mechos-update-self-repair-v0313"), 0o755)
        install_file(fetched["powerctl"], Path("/usr/local/libexec/mechos-powerctl-v1"), 0o755)
        install_file(fetched["reboot"], Path("/usr/local/bin/mechos-reboot"), 0o755)
        install_file(fetched["public-key"], installed_key, 0o644)

        # Stable public entry points are deliberately tiny and frozen.
        install_file(fetched["helper-launcher"], Path("/usr/local/bin/mechos-update-helper"), 0o755)
        install_file(fetched["center-launcher"], Path("/usr/local/bin/mechos-update-center"), 0o755)

        # Preserve previous engine when valid, then atomically activate the
        # maintenance slot. This does not change /etc/mechos/release.
        switcher = "/usr/local/libexec/mechos-update-engine-switch-v38"
        activate = run([switcher, "--activate", SLOT_NAME], check=False)
        if activate.returncode != 0:
            raise RuntimeError(f"Unable to activate frozen updater slot: {activate.stdout.strip()}")
        log(activate.stdout.strip())

        repair = run(
            ["/usr/local/libexec/mechos-update-self-repair-v0313", "--repair"],
            check=False,
            timeout=60,
        )
        if repair.returncode != 0:
            raise RuntimeError(f"Post-activation self-repair failed: {repair.stdout.strip()}")
        log(repair.stdout.strip())

        power_selftest = run(["/usr/local/libexec/mechos-powerctl-v1", "selftest"], check=False)
        if power_selftest.returncode != 0 or "MECHOS_POWERCTL_SELFTEST=1" not in power_selftest.stdout:
            raise RuntimeError(f"Frozen restart authority self-test failed: {power_selftest.stdout.strip()}")
        log(power_selftest.stdout.strip())

        selftest = run(["/usr/local/bin/mechos-update-helper", "selftest"], check=False)
        if selftest.returncode != 0 or "MECHOS_UPDATE_HELPER_SELFTEST=1" not in selftest.stdout:
            raise RuntimeError(f"Frozen helper self-test failed: {selftest.stdout.strip()}")
        log(selftest.stdout.strip())

        status = run(["/usr/local/bin/mechos-update-helper", "status"], check=False, timeout=40)
        if status.returncode != 0:
            # The infrastructure itself is repaired even if the remote feed is
            # temporarily unavailable. Report that separately.
            log("Infrastructure repair succeeded, but remote status check failed:")
            log(status.stdout.strip())
        else:
            log(status.stdout.strip())

    print("MECHOS_UPDATE_INFRASTRUCTURE_REPAIR_OK=1")
    print(f"MECHOS_UPDATE_ENGINE_SLOT={SLOT_NAME}")
    print("MECHOS_RELEASE_VERSION_UNCHANGED=1")
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        log(f"ERROR: {exc}")
        raise SystemExit(1)
