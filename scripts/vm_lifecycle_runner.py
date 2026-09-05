#!/usr/bin/env python3
"""End-to-end graphical MechOS VM lifecycle test.

This driver is intentionally destructive only to the disposable QEMU test disk.
It exercises the Live installer, first-boot OOBE, post-install mode launchers and
safe GUI surfaces. Destructive recovery actions remain covered by source wiring
validation rather than being clicked on the installed test system.
"""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

from PIL import Image, ImageChops, ImageStat
from vncdotool import api

OUT = Path(os.environ.get("VM_EVIDENCE_DIR", "vm-lifecycle"))
SERVER = os.environ.get("VNC_SERVER", "127.0.0.1::5907")
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
    # Sample rather than materializing every pixel on large displays.
    thumb = img.copy()
    thumb.thumbnail((640, 360))
    pixels = list(thumb.getdata())
    nonblack = sum(1 for r, g, b in pixels if max(r, g, b) > 12) / max(1, len(pixels))
    return mean, std, nonblack


def delta(a: Path, b: Path) -> float:
    ia = Image.open(a).convert("RGB")
    ib = Image.open(b).convert("RGB")
    if ia.size != ib.size:
        ia = ia.resize(ib.size)
    return ImageStat.Stat(ImageChops.difference(ia, ib).convert("L")).mean[0]


def require_visible(path: Path, label: str) -> None:
    mean, std, nonblack = image_metrics(path)
    log(f"{label}: mean={mean:.2f} std={std:.2f} nonblack={nonblack:.3f}")
    if mean < 7.0 or nonblack < 0.025 or std < 3.0:
        fail(f"{label} framebuffer is black or effectively blank")


def screen_size() -> tuple[int, int]:
    probe = capture("_screen-probe")
    size = Image.open(probe).size
    try:
        probe.unlink()
    except OSError:
        pass
    return size


def canvas_point(x: float, y: float) -> tuple[int, int]:
    """Map the authored 1920x1080 MechOS canvas to the current framebuffer."""
    w, h = screen_size()
    scale = min(w / 1920.0, h / 1080.0)
    ox = (w - 1920.0 * scale) / 2.0
    oy = (h - 1080.0 * scale) / 2.0
    return int(round(ox + x * scale)), int(round(oy + y * scale))


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
        fail(f"{label} did not visibly change the GUI")


def launch_surface(name: str, command: str, baseline: Path, wait: float = 7.0) -> Path:
    log(f"Launching {name}: {command}")
    krunner(command)
    time.sleep(wait)
    shot = capture(name)
    require_visible(shot, name)
    require_transition(baseline, shot, f"{name} launch", 1.2)
    return shot


try:
    # ---- Live boot -------------------------------------------------------
    log("Starting full Live -> install -> OOBE -> post-install lifecycle")
    client.keyPress("enter")  # accept default boot entry when the menu is waiting
    time.sleep(15)
    early = capture("01-live-boot-early")
    require_visible(early, "Live boot early")
    time.sleep(45)
    mid = capture("02-live-boot-mid")
    require_visible(mid, "Live boot mid")
    time.sleep(80)
    live = capture("03-live-installer")
    require_visible(live, "Live installer")
    require_transition(early, live, "Live boot progress", 1.5)

    # Verify the visible Clean Install card accepts a real click, then click
    # the actual Install Now hotspot from installer_shell.py.
    click_canvas(542, 679)
    time.sleep(2)
    clean = capture("04-live-clean-install-selected")
    require_visible(clean, "Live clean-install selection")
    click_canvas(1705, 978)
    time.sleep(3)
    # Confirm a native confirmation dialog if one is present. On a disposable
    # blank VM disk, accepting the default action is the intended test.
    client.keyPress("enter")
    time.sleep(10)
    install_start = capture("05-install-started")
    require_visible(install_start, "Install started")

    # Wait for install + automatic reboot into the installed first-boot UI.
    # We detect OOBE by exercising the authored Next button: while the Live
    # installer/boot screen is still active, this coordinate is inert.
    oobe_welcome = None
    oobe_account = None
    for attempt in range(1, 25):  # up to ~20 minutes under TCG
        time.sleep(45)
        candidate = capture(f"install-wait-{attempt:02d}")
        require_visible(candidate, f"Install wait {attempt}")
        if attempt < 5:
            continue
        click_canvas(1600, 889)
        time.sleep(2)
        after = capture(f"install-wait-{attempt:02d}-probe")
        if delta(candidate, after) >= 0.8:
            oobe_welcome = candidate
            oobe_account = after
            log(f"OOBE detected after install wait probe {attempt}")
            break
    if oobe_welcome is None or oobe_account is None:
        raise RuntimeError("installed first-boot OOBE was not detected after clean install")

    # Preserve clearly named OOBE evidence.
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

    # Finish applies the permanent account and session handoff.
    click_canvas(1600, 889)
    time.sleep(8)
    finish_apply = capture("13-oobe-finish-apply")
    require_visible(finish_apply, "OOBE finish apply")

    post = None
    for attempt in range(1, 9):
        time.sleep(20)
        shot = capture(f"postinstall-wait-{attempt:02d}")
        require_visible(shot, f"Post-install wait {attempt}")
        if delta(previous, shot) >= 3.0:
            post = shot
            break
    if post is None:
        raise RuntimeError("post-install graphical session did not replace OOBE")
    Image.open(post).save(OUT / "14-postinstall-first-session.png")
    log("Permanent post-install graphical session reached")

    # Capture the first-session/tutorial state before launching other apps.
    time.sleep(5)
    desktop = capture("15-postinstall-desktop-baseline")
    require_visible(desktop, "Post-install desktop/tutorial baseline")

    # ---- Post-install safe GUI surfaces ---------------------------------
    update = launch_surface("16-update-center", "/usr/local/bin/mechos-update-center", desktop)
    # Runtime-test the safe Check Again action. Install/rollback/reinstall are
    # intentionally not clicked on the lifecycle disk.
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
    # Creator Store is a real page on the current Creator Mode dashboard.
    click_canvas(711, 309)
    time.sleep(4)
    creator_store = capture("24-creator-store")
    require_visible(creator_store, "Creator Store")
    require_transition(creator, creator_store, "Creator Store button", 0.5)
    # Settings is the ninth authored navigation entry.
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
    # Current MechScope exact layout starts keyboard focus on Steam Library;
    # Tab once selects Unified Store, Enter opens the real UnifiedStore dialog.
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
    # This directly exercises the same helper wired to Update Center's
    # Restart MechOS action. The GUI button's signal wiring is also covered by
    # the build's validate-gui-button-wiring.py gate.
    log("Runtime-testing MechOS reboot helper")
    krunner("/usr/local/bin/mechos-reboot")
    time.sleep(12)
    rebooting = capture("30-reboot-helper-transition")
    require_transition(desktop, rebooting, "Reboot helper", 2.0)

    reboot_ready = None
    for attempt in range(1, 10):
        time.sleep(20)
        shot = capture(f"reboot-wait-{attempt:02d}")
        require_visible(shot, f"Reboot wait {attempt}")
        if delta(rebooting, shot) >= 2.0:
            reboot_ready = shot
            break
    if reboot_ready is None:
        raise RuntimeError("system did not return to a graphical session after reboot helper")
    Image.open(reboot_ready).save(OUT / "31-post-reboot-session.png")

    # Prove a real post-reboot session can still launch a system surface.
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
        "PASS: Live boot, Live installer, clean install, automatic first boot, "
        "OOBE account creation, post-install session, Update Center, Recovery "
        "Center, Quick Actions, Creator Mode/Store/Settings, MechScope, Unified "
        "Store and reboot-helper/post-reboot readiness completed."
    )
(OUT / "lifecycle-summary.txt").write_text("\n".join(SUMMARY) + "\n", encoding="utf-8")
print("\n".join(SUMMARY))
if FAILURES:
    sys.exit(1)
