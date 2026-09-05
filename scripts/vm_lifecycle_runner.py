#!/usr/bin/env python3
"""End-to-end graphical MechOS VM lifecycle test.

The driver controls the disposable QEMU VM through VNC. It deliberately waits
for the Live installer to prove that its real mode controls are present before
clicking Install Now, then verifies that the QCOW2 disk actually grows before
waiting for OOBE. This prevents a slow TCG boot from being misreported as an OS
installation failure just because fixed sleeps expired too early.
"""
from __future__ import annotations

import os
import time
from pathlib import Path

from PIL import Image, ImageChops, ImageStat
from vncdotool import api

OUT = Path(os.environ.get("VM_EVIDENCE_DIR", "vm-lifecycle"))
SERVER = os.environ.get("VNC_SERVER", "127.0.0.1::5907")
DISK = Path(os.environ.get("DISK", "")) if os.environ.get("DISK") else None
OUT.mkdir(parents=True, exist_ok=True)
SUMMARY: list[str] = []
FAILURES: list[str] = []


def log(message: str) -> None:
    print(f"[MechOS VM Lifecycle] {message}", flush=True)
    SUMMARY.append(message)


def fail(message: str) -> None:
    FAILURES.append(message)
    log("FAIL: " + message)


def connect():
    last = None
    for _ in range(60):
        try:
            return api.connect(SERVER, password=None)
        except Exception as exc:  # pragma: no cover - integration retry
            last = exc
            time.sleep(1)
    raise RuntimeError(f"VNC connection failed: {last}")


client = connect()


def capture(name: str) -> Path:
    path = OUT / f"{name}.png"
    client.captureScreen(str(path))
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError(f"empty VNC capture: {path}")
    return path


def image_metrics(path: Path) -> tuple[float, float, float]:
    img = Image.open(path).convert("RGB")
    stat = ImageStat.Stat(img)
    mean = sum(stat.mean) / 3.0
    std = sum(stat.stddev) / 3.0
    thumb = img.copy()
    thumb.thumbnail((640, 360))
    pixels = list(thumb.getdata())
    nonblack = sum(1 for r, g, b in pixels if max(r, g, b) > 12) / max(1, len(pixels))
    return mean, std, nonblack


def is_visible(path: Path) -> bool:
    mean, std, nonblack = image_metrics(path)
    return mean >= 7.0 and std >= 3.0 and nonblack >= 0.025


def report_visibility(path: Path, label: str) -> bool:
    mean, std, nonblack = image_metrics(path)
    visible = mean >= 7.0 and std >= 3.0 and nonblack >= 0.025
    log(
        f"{label}: mean={mean:.2f} std={std:.2f} "
        f"nonblack={nonblack:.3f} visible={'yes' if visible else 'no'}"
    )
    return visible


def require_visible(path: Path, label: str) -> None:
    if not report_visibility(path, label):
        raise RuntimeError(f"{label} framebuffer is black or effectively blank")


def delta(a: Path, b: Path) -> float:
    ia = Image.open(a).convert("RGB")
    ib = Image.open(b).convert("RGB")
    if ia.size != ib.size:
        ia = ia.resize(ib.size)
    return ImageStat.Stat(ImageChops.difference(ia, ib).convert("L")).mean[0]


def screen_size() -> tuple[int, int]:
    probe = capture("_screen-probe")
    size = Image.open(probe).size
    try:
        probe.unlink()
    except OSError:
        pass
    return size


def canvas_transform() -> tuple[float, float, float]:
    w, h = screen_size()
    scale = min(w / 1920.0, h / 1080.0)
    return scale, (w - 1920.0 * scale) / 2.0, (h - 1080.0 * scale) / 2.0


def canvas_point(x: float, y: float) -> tuple[int, int]:
    scale, ox, oy = canvas_transform()
    return int(round(ox + x * scale)), int(round(oy + y * scale))


def canvas_box(x1: float, y1: float, x2: float, y2: float, size: tuple[int, int]) -> tuple[int, int, int, int]:
    w, h = size
    scale = min(w / 1920.0, h / 1080.0)
    ox = (w - 1920.0 * scale) / 2.0
    oy = (h - 1080.0 * scale) / 2.0
    left = max(0, int(round(ox + x1 * scale)))
    top = max(0, int(round(oy + y1 * scale)))
    right = min(w, int(round(ox + x2 * scale)))
    bottom = min(h, int(round(oy + y2 * scale)))
    return left, top, right, bottom


def region_delta(a: Path, b: Path, box: tuple[float, float, float, float]) -> float:
    ia = Image.open(a).convert("RGB")
    ib = Image.open(b).convert("RGB")
    if ia.size != ib.size:
        ib = ib.resize(ia.size)
    crop = canvas_box(*box, ia.size)
    ca = ia.crop(crop)
    cb = ib.crop(crop)
    return ImageStat.Stat(ImageChops.difference(ca, cb).convert("L")).mean[0]


def click_canvas(x: float, y: float) -> None:
    px, py = canvas_point(x, y)
    client.mouseMove(px, py)
    client.mousePress(1)


def combo(mod: str, key: str) -> None:
    client.keyDown(mod)
    client.keyPress(key)
    client.keyUp(mod)


def replace_text(text: str) -> None:
    combo("ctrl", "a")
    client.type(text)


def krunner(command: str, settle: float = 1.2) -> None:
    combo("alt", "f2")
    time.sleep(settle)
    client.type(command)
    client.keyPress("enter")


def close_window() -> None:
    combo("alt", "f4")
    time.sleep(2)


def require_transition(before: Path, after: Path, label: str, threshold: float = 0.7) -> None:
    d = delta(before, after)
    log(f"{label}: framebuffer delta={d:.2f}")
    if d < threshold:
        raise RuntimeError(f"{label} did not visibly change the GUI")


def launch_surface(name: str, command: str, baseline: Path, wait: float = 7.0) -> Path:
    log(f"Launching {name}: {command}")
    krunner(command)
    time.sleep(wait)
    shot = capture(name)
    require_visible(shot, name)
    require_transition(baseline, shot, f"{name} launch", 1.2)
    return shot


def wait_for_live_installer() -> Path:
    """Wait until the actual installer mode buttons respond before proceeding."""
    log("Waiting for the real Live installer instead of relying on a fixed boot delay")
    options_box = (410, 600, 1160, 755)
    for attempt in range(1, 49):  # ~12 minutes worst case under TCG
        shot = capture(f"live-readiness-{attempt:02d}")
        visible = report_visibility(shot, f"Live readiness {attempt}")
        if not visible:
            # The first Enter can be lost if QEMU/OVMF is not ready yet. Sending
            # Enter during an otherwise blank boot phase is harmless and helps
            # accept the default boot entry as soon as it appears.
            client.keyPress("enter")
            time.sleep(15)
            continue

        # Prove we are on InstallerShell, not merely on some visible boot frame:
        # toggle Keep Personal Data and then Clean Install. Both buttons are
        # authored mode controls and change the checked-state styling.
        click_canvas(784, 679)
        time.sleep(1.5)
        keep = capture(f"live-readiness-{attempt:02d}-keep")
        click_canvas(542, 679)
        time.sleep(1.5)
        clean = capture(f"live-readiness-{attempt:02d}-clean")
        keep_d = region_delta(shot, keep, options_box)
        clean_d = region_delta(keep, clean, options_box)
        log(f"Installer probe {attempt}: keep_delta={keep_d:.2f} clean_delta={clean_d:.2f}")
        if is_visible(clean) and keep_d >= 0.18 and clean_d >= 0.18:
            final = OUT / "03-live-installer.png"
            Image.open(clean).save(final)
            log(f"Live installer confirmed by real mode-control response on probe {attempt}")
            return final

        # Move away from the mode cards before the next probe.
        px, py = canvas_point(1200, 120)
        client.mouseMove(px, py)
        time.sleep(12)
    raise RuntimeError("Live installer never became interactively ready within 12 minutes")


def disk_bytes() -> int:
    if DISK is None:
        return 0
    try:
        return DISK.stat().st_size
    except OSError:
        return 0


def wait_for_install_write(baseline: int) -> Path:
    """Require real QCOW2 growth so a missed Install Now click fails early."""
    target_growth = 4 * 1024 * 1024
    for attempt in range(1, 31):  # up to 5 minutes to start disk writes
        time.sleep(10)
        shot = capture(f"install-start-wait-{attempt:02d}")
        current = disk_bytes()
        growth = max(0, current - baseline)
        report_visibility(shot, f"Install-start wait {attempt}")
        log(f"Install disk growth: {growth} bytes")
        if growth >= target_growth:
            final = OUT / "05-install-started.png"
            Image.open(shot).save(final)
            log("Clean install confirmed by QCOW2 growth")
            return final
    raise RuntimeError("Install Now did not start writing to the disposable QCOW2 disk")


try:
    # ---- Live boot -------------------------------------------------------
    log("Starting full Live -> install -> OOBE -> post-install lifecycle")
    time.sleep(12)
    early = capture("01-live-boot-early")
    report_visibility(early, "Live boot early")
    client.keyPress("enter")
    time.sleep(35)
    mid = capture("02-live-boot-mid")
    report_visibility(mid, "Live boot mid")

    live = wait_for_live_installer()
    require_visible(live, "Live installer")
    require_transition(early, live, "Live boot progress", 1.5)

    # The readiness probe leaves Clean Install selected. Preserve the explicit
    # selection evidence and then click the real Install Now hotspot.
    clean = OUT / "04-live-clean-install-selected.png"
    Image.open(live).save(clean)
    require_visible(clean, "Live clean-install selection")

    before_install_bytes = disk_bytes()
    log(f"QCOW2 size before Install Now: {before_install_bytes} bytes")
    click_canvas(1705, 978)
    time.sleep(3)
    # Accept the disposable-disk confirmation dialog when one is present.
    client.keyPress("enter")
    install_start = wait_for_install_write(before_install_bytes)
    require_visible(install_start, "Install started")

    # ---- Install + automatic reboot into OOBE ---------------------------
    oobe_welcome = None
    oobe_account = None
    for attempt in range(1, 61):  # up to ~30 minutes under TCG
        time.sleep(30)
        candidate = capture(f"install-wait-{attempt:02d}")
        visible = report_visibility(candidate, f"Install wait {attempt}")
        if not visible or attempt < 6:
            continue
        # OOBE Welcome's Next button is at this authored coordinate. During
        # installer progress/reboot it is inert; on OOBE it advances to Account.
        click_canvas(1600, 889)
        time.sleep(2)
        after = capture(f"install-wait-{attempt:02d}-probe")
        probe_delta = delta(candidate, after)
        log(f"OOBE probe {attempt}: framebuffer delta={probe_delta:.2f}")
        if is_visible(after) and probe_delta >= 0.8:
            oobe_welcome = candidate
            oobe_account = after
            log(f"OOBE detected after install wait probe {attempt}")
            break
    if oobe_welcome is None or oobe_account is None:
        raise RuntimeError("installed first-boot OOBE was not detected after confirmed disk installation")

    Image.open(oobe_welcome).save(OUT / "06-oobe-welcome.png")
    Image.open(oobe_account).save(OUT / "07-oobe-account.png")
    require_transition(oobe_welcome, oobe_account, "OOBE Welcome -> Account", 0.8)

    # ---- First-boot account creation ------------------------------------
    click_canvas(585, 473)
    replace_text("mechvmtest")
    click_canvas(585, 593)
    replace_text("MechOSvm1234")
    click_canvas(1305, 593)
    replace_text("MechOSvm1234")
    account_filled = capture("08-oobe-account-filled")
    require_visible(account_filled, "OOBE account fields")

    pages = ["region", "device", "review", "finish"]
    previous = account_filled
    for number, page in enumerate(pages, start=9):
        click_canvas(1600, 889)
        time.sleep(2)
        shot = capture(f"{number:02d}-oobe-{page}")
        require_visible(shot, f"OOBE {page}")
        require_transition(previous, shot, f"OOBE -> {page}", 0.35)
        previous = shot

    click_canvas(1600, 889)
    time.sleep(8)
    finish_apply = capture("13-oobe-finish-apply")
    require_visible(finish_apply, "OOBE finish apply")

    post = None
    for attempt in range(1, 9):
        time.sleep(20)
        shot = capture(f"postinstall-wait-{attempt:02d}")
        if not report_visibility(shot, f"Post-install wait {attempt}"):
            continue
        if delta(previous, shot) >= 3.0:
            post = shot
            break
    if post is None:
        raise RuntimeError("post-install graphical session did not replace OOBE")
    Image.open(post).save(OUT / "14-postinstall-first-session.png")
    log("Permanent post-install graphical session reached")

    time.sleep(5)
    desktop = capture("15-postinstall-desktop-baseline")
    require_visible(desktop, "Post-install desktop/tutorial baseline")

    # ---- Post-install safe GUI surfaces ---------------------------------
    update = launch_surface("16-update-center", "/usr/local/bin/mechos-update-center", desktop)
    click_canvas(243, 403)
    time.sleep(6)
    update_checked = capture("17-update-center-check-again")
    require_visible(update_checked, "Update Center Check Again")
    close_window()
    desktop = capture("18-after-update-center")

    recovery = launch_surface("19-recovery-center", "/usr/local/bin/mechos-recovery-center", desktop)
    close_window()
    desktop = capture("20-after-recovery-center")

    quick = launch_surface("21-quick-actions", "/usr/local/bin/mechos-quick-actions", desktop)
    close_window()
    desktop = capture("22-after-quick-actions")

    creator = launch_surface("23-creator-mode", "/usr/local/bin/mechos-creator-mode", desktop, 9.0)
    click_canvas(711, 309)
    time.sleep(4)
    creator_store = capture("24-creator-store")
    require_visible(creator_store, "Creator Store")
    require_transition(creator, creator_store, "Creator Store button", 0.5)
    click_canvas(144, 555)
    time.sleep(4)
    creator_settings = capture("25-creator-settings")
    require_visible(creator_settings, "Creator Settings")
    require_transition(creator_store, creator_settings, "Creator Settings button", 0.5)
    close_window()
    desktop = capture("26-after-creator-mode")

    mechscope = launch_surface(
        "27-mechscope",
        "/usr/local/bin/mechos-mode-launch mechscope",
        desktop,
        10.0,
    )
    client.keyPress("tab")
    client.keyPress("enter")
    time.sleep(5)
    store = capture("28-unified-store")
    require_visible(store, "Unified Store")
    require_transition(mechscope, store, "MechScope Unified Store button", 0.5)
    client.keyPress("esc")
    time.sleep(2)
    close_window()
    desktop = capture("29-after-mechscope")

    # ---- Reboot helper / post-reboot readiness --------------------------
    log("Runtime-testing MechOS reboot helper")
    krunner("/usr/local/bin/mechos-reboot")
    time.sleep(12)
    rebooting = capture("30-reboot-helper-transition")
    require_transition(desktop, rebooting, "Reboot helper", 2.0)

    reboot_ready = None
    for attempt in range(1, 10):
        time.sleep(20)
        shot = capture(f"reboot-wait-{attempt:02d}")
        if not report_visibility(shot, f"Reboot wait {attempt}"):
            continue
        if delta(rebooting, shot) >= 2.0:
            reboot_ready = shot
            break
    if reboot_ready is None:
        raise RuntimeError("system did not return to a graphical session after reboot helper")
    Image.open(reboot_ready).save(OUT / "31-post-reboot-session.png")

    final_update = launch_surface(
        "32-post-reboot-update-center",
        "/usr/local/bin/mechos-update-center",
        reboot_ready,
        8.0,
    )
    close_window()
    final = capture("33-final-postinstall-desktop")
    require_visible(final, "Final post-install desktop")

except Exception as exc:
    fail(str(exc))
finally:
    try:
        client.disconnect()
    except Exception:
        pass

status = "PASS" if not FAILURES else "FAIL"
SUMMARY.append(f"RESULT={status}")
if not FAILURES:
    SUMMARY.append(
        "PASS: Live installer readiness, confirmed disk installation, automatic first boot, "
        "OOBE account creation, post-install session, Update Center, Recovery Center, "
        "Quick Actions, Creator Mode/Store/Settings, MechScope, Unified Store and "
        "reboot-helper/post-reboot readiness completed."
    )
(OUT / "lifecycle-summary.txt").write_text("\n".join(SUMMARY) + "\n", encoding="utf-8")
print("\n".join(SUMMARY))
if FAILURES:
    raise SystemExit(1)
