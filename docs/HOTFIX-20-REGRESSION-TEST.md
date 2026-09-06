# MechOS v0.3.0 Hotfix 20 Regression Test

Use this checklist after installing Hotfix 20 on both a VM and at least one physical-hardware system.

Hotfix 20 is cumulative with Hotfixes 15-19. The goal of this pass is to confirm that updater recovery, single-window navigation, Creator Mode, MechScope, store behavior, restart/recovery, and root-permission safety all survive normal use and reboot cycles.

## Test record

- Date:
- Tester:
- Machine type: VM / Physical
- GPU:
- CPU:
- Display resolution:
- Starting MechOS version:
- Ending MechOS version:
- Commit/build reference:

## Already confirmed during Hotfix 20 recovery

- [x] Creator Mode opens correctly instead of redirecting to Gaming/MechScope.
- [x] Physical-hardware MechScope opens.
- [x] Broken Hotfix 14 install can be recovered without reinstalling the OS.
- [x] Root filesystem traversal can be restored after the old transaction bug.
- [x] Update helper, reboot helper, and Update Center are restored after recovery.

## 1. Boot and release state

- [ ] Cold boot reaches the normal MechOS session without dropping to a shell or desktop unexpectedly.
- [ ] `cat /etc/mechos/release` reports `0.3.0-hotfix.20`.
- [ ] `stat -c '%a %U:%G %n' /` reports root as traversable by normal users, normally `755 root:root /`.
- [ ] `/usr/bin/bash`, `/usr/bin/pacman`, `/usr/bin/systemctl`, and `/usr/bin/sudo` are executable.
- [ ] Login/session startup completes without repeated MechScope or Creator relaunch loops.

## 2. Single-window MechOS shell

Start in MechScope/Gaming and visit each internal section.

- [ ] Gaming / MechScope dashboard stays in the main MechOS shell.
- [ ] Unified Store opens inside the same MechOS shell.
- [ ] Creator Mode switches in-place when the shell is already running.
- [ ] Performance Center opens inside the same shell.
- [ ] Update Center opens inside the same shell.
- [ ] Recovery Center opens inside the same shell.
- [ ] Back navigation returns to the previous MechOS page.
- [ ] Repeated navigation does not create extra MechOS windows.
- [ ] The Plasma desktop is not exposed during normal internal navigation.

Repeat this sequence at least three times:

`Gaming -> Store -> Creator -> Performance -> Updates -> Recovery -> Gaming`

- [ ] No page becomes blank.
- [ ] No duplicate MechOS window appears.
- [ ] No mode switch restarts MechScope unnecessarily.

## 3. Creator Mode

- [ ] Selecting Creator Mode from MechScope opens Creator Mode, not Gaming/MechScope.
- [ ] Creator Mode can be entered from the main shell without killing the shell first.
- [ ] Creator Mode launches directly when the unified shell is not already running.
- [ ] Creator UI remains usable after switching back to Gaming and returning again.
- [ ] Creator shortcuts launch their intended external tools.
- [ ] Missing external creator tools produce a useful install/error flow instead of a silent failure.

## 4. MechScope on physical hardware

- [ ] MechScope launches on normal physical hardware.
- [ ] Gamescope primary fullscreen path works when supported.
- [ ] Unsupported VRR/HDR does not stop MechScope from opening.
- [ ] If Gamescope fails, MechScope falls back to Plasma-hosted mode instead of disappearing.
- [ ] Keyboard and mouse work.
- [ ] Controller input works when a controller is connected.
- [ ] Audio output works.
- [ ] GPU/Vulkan acceleration is active on physical hardware.

If MechScope fails, collect:

```bash
cat ~/.local/state/mechos/mechscope-session-v19.log
```

## 5. Unified Store

- [ ] Game search stays inside Unified Store.
- [ ] Search Selected Store works.
- [ ] Search All Stores works.
- [ ] Search does not automatically open the default web browser.
- [ ] Steam provider actions open Steam only after selecting an install/open action.
- [ ] Epic/GOG/Amazon provider actions route through Heroic where supported.
- [ ] Missing Steam/Heroic client triggers the MechOS install/bootstrap flow.
- [ ] Installing a missing provider does not leave the user on an unrelated web page.
- [ ] Returning from an external launcher returns cleanly to the MechOS shell.

## 6. Update Center

- [ ] Check Again refreshes Current and Latest versions correctly.
- [ ] When already on Hotfix 20, MechOS OS shows up to date.
- [ ] Arch package status can be checked without `Permission denied` under `/var/lib/pacman/sync`.
- [ ] Flatpak update status can be checked.
- [ ] Failed package updates do not incorrectly report that the MechOS OS transaction failed after the core update has already staged successfully.
- [ ] Update history refreshes.
- [ ] Release notes/output remain readable at the current display resolution.
- [ ] Restart MechOS button calls the restored reboot helper successfully.

Verify helpers:

```bash
command -v mechos-update-center
command -v mechos-update-helper
command -v mechos-reboot
command -v mechos-update-rescue
```

All should resolve under `/usr/local/bin/`.

## 7. Root-permission transaction safety

Record before any future update test:

```bash
stat -c '%a %u:%g %n' /
```

After an update attempt, successful or failed:

```bash
stat -c '%a %u:%g %n' /
ls /usr/bin/bash
ls /usr/bin/pacman
```

- [ ] Root ownership/mode is unchanged after a successful update.
- [ ] Root ownership/mode is unchanged after a deliberately interrupted/failed test update in a disposable VM.
- [ ] Normal users retain traversal of `/`.
- [ ] `/usr/bin` never becomes inaccessible after an update transaction.
- [ ] A transaction safety failure is reported instead of claiming success if root traversal would be lost.

Only perform intentional failure testing in a disposable VM snapshot.

## 8. Recovery Center

- [ ] Recovery Center opens inside the main shell.
- [ ] Snapshot state is displayed correctly.
- [ ] Creating a recovery snapshot succeeds when supported.
- [ ] Rollback controls identify the correct snapshot before applying anything.
- [ ] Recovery actions require appropriate authorization.
- [ ] Opening and closing Recovery Center does not spawn duplicate MechOS windows.

## 9. Performance Center

- [ ] Performance Center opens inside the main shell.
- [ ] Hardware/system information loads.
- [ ] Performance controls do not silently fail.
- [ ] Returning to Gaming or Creator preserves the main shell.

## 10. Reboot and cold-start persistence

Perform a normal restart:

- [ ] Restart completes without a missing-helper error.
- [ ] MechOS comes back on Hotfix 20.
- [ ] Creator Mode still works after reboot.
- [ ] MechScope still works after reboot.
- [ ] Unified Store still works after reboot.
- [ ] Root permissions remain correct after reboot.

Then perform a full shutdown and power-on/cold boot:

- [ ] Cold boot completes normally.
- [ ] No stale `Restart Required` state remains after the completed reboot.
- [ ] No stale update-install failure banner remains when the OS update succeeded.
- [ ] MechScope starts correctly on physical hardware after cold boot.

## 11. VM-specific checks

- [ ] VirtualBox/VM MechScope bypasses unsupported Gamescope paths when necessary.
- [ ] Software rendering fallback works.
- [ ] Creator and Store layouts remain usable at the VM resolution.
- [ ] No buttons are clipped at common VM resolutions.
- [ ] VM clock skew only produces harmless timestamp warnings and does not fail an update.

Do not use VM frame rate as a gaming-performance result.

## 12. Physical-hardware checks

- [ ] UEFI boot works from a cold start.
- [ ] GPU initializes correctly.
- [ ] Wi-Fi works if present.
- [ ] Ethernet works if present.
- [ ] Audio input/output works.
- [ ] Bluetooth works if present.
- [ ] Controller detection works.
- [ ] Suspend/resume works if supported.
- [ ] Shutdown powers the machine off cleanly.
- [ ] Restart returns to MechOS cleanly.

## Pass / fail rule

Hotfix 20 can be treated as stable for the current v0.3.0 line only when:

- every updater/root-permission safety item passes;
- Creator Mode and physical-hardware MechScope pass;
- internal MechOS pages do not continuously spawn new windows;
- Update Center restart works;
- Recovery Center opens and reports state correctly;
- at least one VM and one physical machine complete reboot + cold-boot testing.

Any failure involving root permissions, missing `/usr/bin` access, failed boot, missing update helpers, or an unusable MechScope session is a release blocker.

## Result

- [ ] PASS
- [ ] FAIL
- [ ] PASS WITH KNOWN ISSUES

Notes:

- 
