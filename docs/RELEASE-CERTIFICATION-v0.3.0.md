# MechOS v0.3.0 Release Certification

Use this document for every v0.3.0 release candidate. A release is **NO-GO** if any BLOCKER item fails.

For the Hotfix 2 / Build 110 line, also complete the dedicated regression gate in section 23.

## Release candidate metadata

- RC / build ID: ____________________
- Git commit: ____________________
- ISO filename: ____________________
- SHA256: ____________________
- Test date: ____________________
- Tester: ____________________
- VM platform: ____________________
- Physical hardware: ____________________
- GPU / driver: ____________________

Status key: `PASS` / `FAIL` / `N/A` / `NOT TESTED`

---

## 1. Build and artifact gate — BLOCKER

- [ ] PASS — Brand-new `Build MechOS Arch ISO` workflow started from current `main`.
- [ ] PASS — Source validation completed successfully.
- [ ] PASS — ISO build completed without errors.
- [ ] PASS — `.iso` exists and is non-empty.
- [ ] PASS — `.iso.sha256` exists.
- [ ] PASS — `sha256sum -c` passes.
- [ ] PASS — GitHub artifact upload completes.
- [ ] PASS — Release candidate commit SHA matches the intended `main` commit.

Notes / evidence:

```text

```

## 2. Live ISO boot gate — BLOCKER

- [ ] PASS — UEFI boot succeeds.
- [ ] PASS — MechOS splash appears correctly.
- [ ] PASS — KDE Plasma live desktop appears.
- [ ] PASS — Setup / Installer opens without crashing.
- [ ] PASS — Network works in Live mode.
- [ ] PASS — Audio works in Live mode.
- [ ] PASS — Display resolution can be changed.
- [ ] PASS — No unexpected crash/fallback dialogs appear.
- [ ] PASS — Live environment does not expose installed-only Creator Mode as the normal default workflow.

## 3. Clean installation gate — BLOCKER

Test on a blank virtual disk first, then on dedicated physical test hardware.

- [ ] PASS — Installer detects the intended target disk.
- [ ] PASS — Wrong disks are not preselected or erased.
- [ ] PASS — Partitioning completes.
- [ ] PASS — Bootloader installs.
- [ ] PASS — Installation completes without manual repair.
- [ ] PASS — ISO can be removed after installation.
- [ ] PASS — Installed disk boots by itself.
- [ ] PASS — First installed boot enters the MechOS OOBE/account-creation path instead of skipping directly into a normal mode.
- [ ] PASS — Locale, timezone and keyboard settings persist.

## 4. OOBE and installed login gate — BLOCKER

- [ ] PASS — First-boot authority runs before normal MechScope/Creator mode access when OOBE is incomplete.
- [ ] PASS — Temporary `mechos-setup` session is used only for first-run setup where expected.
- [ ] PASS — OOBE starts automatically on first installed boot.
- [ ] PASS — Welcome step works.
- [ ] PASS — Account step works.
- [ ] PASS — Permanent user account is actually created.
- [ ] PASS — Created account receives `wheel` membership.
- [ ] PASS — Created administrator account has normal password-authenticated `sudo` access.
- [ ] PASS — Region / timezone step works.
- [ ] PASS — Device / profile step works.
- [ ] PASS — Review / Finish works.
- [ ] PASS — `/var/lib/mechos/oobe-complete` is created after successful completion.
- [ ] PASS — OOBE does not repeat after successful completion.
- [ ] PASS — SDDM leaves the temporary setup account after OOBE.
- [ ] PASS — SDDM selects the real `mechscope.desktop` session after OOBE.
- [ ] PASS — Installed user's session mode is initialized to `gaming`.
- [ ] PASS — Reboot after OOBE reaches the permanent user's normal MechOS session.

## 5. MechScope installed-system gate — BLOCKER

- [ ] PASS — MechScope starts automatically after install/OOBE.
- [ ] PASS — No black screen.
- [ ] PASS — No old stripped MechScope shell appears.
- [ ] PASS — Approved MechScope 2.0 GUI appears.
- [ ] PASS — UI scales correctly at 1280x720.
- [ ] PASS — UI scales correctly at 1920x1080.
- [ ] PASS — Steam Library opens.
- [ ] PASS — Unified Store opens.
- [ ] PASS — Performance Center opens.
- [ ] PASS — Update Center opens.
- [ ] PASS — Creator Mode opens.
- [ ] PASS — Recovery opens.
- [ ] PASS — Quick Actions opens.
- [ ] PASS — Power / reboot / shutdown controls work.
- [ ] PASS — Reboot returns to MechScope again.
- [ ] PASS — `~/.local/state/mechos/mechscope-session.log` contains no fatal startup loop.

## 6. Mode switching and shortcut gate — BLOCKER

Repeat each transition several times.

- [ ] PASS — MechScope → Desktop Mode.
- [ ] PASS — Desktop Mode → MechScope.
- [ ] PASS — MechScope → Creator Mode.
- [ ] PASS — Creator Mode → MechScope.
- [ ] PASS — Gaming → Desktop → Creator → Gaming.
- [ ] PASS — Mode switching still works after reboot.
- [ ] PASS — `/usr/local/bin/mechos-mode-launch` exists and accepts the intended gaming/MechScope and Creator routes.
- [ ] PASS — Start/Application menu contains **Return to MechScope**.
- [ ] PASS — Start/Application menu contains **MechOS Creator Mode**.
- [ ] PASS — Start/Application menu **Return to MechScope** entry launches the real MechScope/Gaming Mode route.
- [ ] PASS — Start/Application menu **MechOS Creator Mode** entry launches the real Creator Mode route.
- [ ] PASS — Desktop contains **Return to MechScope** shortcut for the installed user.
- [ ] PASS — Desktop contains **Creator Mode** shortcut for the installed user.
- [ ] PASS — Desktop **Return to MechScope** shortcut works.
- [ ] PASS — Desktop **Creator Mode** shortcut works.
- [ ] PASS — Shortcut repair works for an existing normal user as well as accounts created after the repair.
- [ ] PASS — Shortcut click before OOBE completion redirects/blocks correctly instead of silently launching a normal mode.
- [ ] PASS — Failed mode launch produces a visible/logged error instead of silently doing nothing.
- [ ] PASS — No duplicate MechScope / Creator Mode processes remain running.
- [ ] PASS — No runaway CPU or RAM growth after repeated switching.

## 7. Virtual machine certification — BLOCKER for VM-supported install/runtime claims

VirtualBox/VMware/QEMU are for install/UI/runtime validation, not gaming-performance certification.

- [ ] PASS — `systemd-detect-virt` identifies the VM.
- [ ] PASS — First installed VM boot runs OOBE/account creation before normal mode access.
- [ ] PASS — VM OOBE creates the permanent account successfully.
- [ ] PASS — Gamescope is bypassed in the VM path.
- [ ] PASS — Plasma supplies the compositor while MechScope launches fullscreen.
- [ ] PASS — `mechos-vm-mode-runtime` handles the VM MechScope route.
- [ ] PASS — `mechos-vm-mode-runtime` handles the VM Creator route.
- [ ] PASS — Direct app fallback works if the VM user service cannot keep the requested mode active.
- [ ] PASS — Creator Mode renders correctly.
- [ ] PASS — Installer renders correctly.
- [ ] PASS — OOBE renders correctly.
- [ ] PASS — 1280x720 layout is usable.
- [ ] PASS — Higher VM resolution is usable if available.
- [ ] PASS — Rebooted installed VM reaches MechScope.
- [ ] PASS — VM Start/Application menu **Return to MechScope** entry works.
- [ ] PASS — VM Start/Application menu **MechOS Creator Mode** entry works.
- [ ] PASS — VM desktop **Return to MechScope** shortcut works.
- [ ] PASS — VM desktop **Creator Mode** shortcut works.
- [ ] PASS — VM can switch MechScope → Creator → MechScope repeatedly without a dead shortcut or black screen.
- [ ] PASS — Update Center opens.
- [ ] PASS — Recovery opens.

## 8. Physical hardware certification — BLOCKER

Minimum: one real PC. Preferred: AMD, NVIDIA and Intel graphics coverage.

System A:
- CPU: ____________________
- GPU: ____________________
- RAM: ____________________
- Storage: ____________________
- Result: ____________________

System B:
- CPU: ____________________
- GPU: ____________________
- RAM: ____________________
- Storage: ____________________
- Result: ____________________

- [ ] PASS — Native boot works on physical hardware.
- [ ] PASS — MechScope starts on physical hardware.
- [ ] PASS — Gamescope path works or cleanly falls back.
- [ ] PASS — Desktop and Start/Application menu MechScope shortcut works.
- [ ] PASS — Desktop and Start/Application menu Creator Mode shortcut works.
- [ ] PASS — Display output is correct.
- [ ] PASS — Audio is correct.
- [ ] PASS — Network is correct.
- [ ] PASS — Suspend / resume is stable.

## 9. GPU / Vulkan / display gate — BLOCKER

- [ ] PASS — `vulkaninfo` runs.
- [ ] PASS — Vulkan reports the real GPU, not a software renderer.
- [ ] PASS — AMD path works if tested.
- [ ] PASS — NVIDIA path works if tested.
- [ ] PASS — Intel graphics path works if tested.
- [ ] PASS — Hardware acceleration is active.
- [ ] PASS — Gamescope launches on supported real hardware.
- [ ] PASS — 60 Hz works.
- [ ] PASS — High refresh rate works where supported.
- [ ] PASS — Multi-monitor behavior is acceptable.
- [ ] PASS — VRR works where supported or fails safely when unsupported.

## 10. Steam / Proton gaming gate — BLOCKER

Record game, Proton version, GPU, result and notes.

| Category | Game | Proton | Result | Notes |
|---|---|---|---|---|
| Native Linux |  |  |  |  |
| DX11 Proton |  |  |  |  |
| DX12 Proton |  |  |  |  |
| AAA / demanding |  |  |  |  |
| Multiplayer |  |  |  |  |
| Controller-first |  |  |  |  |

For each tested game:
- [ ] Launches.
- [ ] Audio works.
- [ ] Controller works if applicable.
- [ ] Frame pacing is reasonable.
- [ ] Exit returns cleanly to MechScope.
- [ ] Mode switching does not corrupt the session.

### Overwatch regression check

- [ ] PASS — Physical-hardware performance tested.
- [ ] PASS — Desktop Mode tested.
- [ ] PASS — MechScope / Gamescope tested.
- [ ] PASS — Proton Experimental tested.
- [ ] PASS — Vulkan uses the real GPU.
- [ ] PASS — No unexplained ~10 FPS regression remains on supported hardware.

## 11. Controller gate

- [ ] PASS — Xbox controller wired.
- [ ] PASS — Xbox controller Bluetooth if available.
- [ ] PASS — PlayStation controller if available.
- [ ] PASS — Steam Input works.
- [ ] PASS — MechScope can be navigated without keyboard/mouse.
- [ ] PASS — Focus indicators are visible.
- [ ] PASS — Controller reconnect works after sleep / reboot where expected.

## 12. Network and Bluetooth gate

- [ ] PASS — Ethernet.
- [ ] PASS — Wi-Fi.
- [ ] PASS — Wi-Fi reconnect after reboot.
- [ ] PASS — DNS resolution.
- [ ] PASS — Browser access.
- [ ] PASS — Steam downloads.
- [ ] PASS — Bluetooth enable / disable.
- [ ] PASS — Bluetooth controller pairing.
- [ ] PASS — Bluetooth audio pairing.
- [ ] PASS — Bluetooth reconnect after reboot.

## 13. Audio gate

- [ ] PASS — Built-in speakers / analog output if available.
- [ ] PASS — Headphones.
- [ ] PASS — HDMI / DisplayPort audio.
- [ ] PASS — USB headset if available.
- [ ] PASS — Microphone input.
- [ ] PASS — Steam game audio.
- [ ] PASS — OBS capture audio.
- [ ] PASS — Device switching works.

## 14. Creator Mode gate — BLOCKER for advertised creator features

Creator Mode must be the **live native Qt dashboard**. The old full-screen screenshot/reference-raster shell is not a passing implementation.

- [ ] PASS — Native live Creator Mode dashboard appears.
- [ ] PASS — Creator Mode is not using the old full-screen screenshot/reference-raster dashboard.
- [ ] PASS — Creator UI scales correctly at 1280x720.
- [ ] PASS — Creator UI scales correctly at 1920x1080.
- [ ] PASS — Live CPU telemetry updates from the host.
- [ ] PASS — Live RAM telemetry updates from the host.
- [ ] PASS — Disk usage reflects the real host.
- [ ] PASS — GPU and active driver detection reflect the real host/VM.
- [ ] PASS — VRAM telemetry works where supported or cleanly reports unavailable when unsupported.
- [ ] PASS — Current MechOS/update state comes from the real update source instead of baked-in text.
- [ ] PASS — Installed/not-installed creator app states reflect the actual machine.
- [ ] PASS — Local project scan finds real Unity projects.
- [ ] PASS — Local project scan finds real Unreal projects.
- [ ] PASS — Local project scan finds real Godot projects.
- [ ] PASS — Local project scan finds real Blender projects/files.
- [ ] PASS — Empty project state is correct when no projects exist.
- [ ] PASS — **New Project** shortcut performs the real project workflow or safe Project Manager fallback.
- [ ] PASS — **Open Project** opens a real directory chooser.
- [ ] PASS — **Open Project** detects Unity projects.
- [ ] PASS — **Open Project** detects Unreal projects.
- [ ] PASS — **Open Project** detects Godot projects.
- [ ] PASS — **Open Project** detects/opens Blender project files where Blender is available.
- [ ] PASS — **Project Manager** refreshes detected projects and opens the project manager.
- [ ] PASS — **Asset Browser** opens the intended Creator asset area.
- [ ] PASS — **MechClip AI** opens the intended clipping-tools area.
- [ ] PASS — **Creator Settings** opens Creator preferences.
- [ ] PASS — Performance Center action works from Creator Mode.
- [ ] PASS — Unity Hub action works.
- [ ] PASS — Blender action works.
- [ ] PASS — Unreal Engine action works.
- [ ] PASS — OBS Studio action works.
- [ ] PASS — Krita action works.
- [ ] PASS — Kdenlive action works.
- [ ] PASS — Godot action works.
- [ ] PASS — VRChat Creator tools action works if advertised in this candidate.
- [ ] PASS — Creator Store opens.
- [ ] PASS — Project profiles work.
- [ ] PASS — Installed/not-installed app states do not silently fail.
- [ ] PASS — Back to MechScope works.

## 15. Performance Center / RadarAI gate

- [ ] PASS — CPU info is reasonable.
- [ ] PASS — RAM info is reasonable.
- [ ] PASS — GPU detection is correct.
- [ ] PASS — Disk information is correct.
- [ ] PASS — Temperatures display where supported.
- [ ] PASS — Auto Optimization does not destabilize the system.
- [ ] PASS — Intended settings persist after reboot.
- [ ] PASS — RadarAI logging works.
- [ ] PASS — RadarAI user notifications do not loop or spam.
- [ ] PASS — Network/reporting failure does not freeze the UI.
- [ ] PASS — No secrets, personal data or unintended logs are submitted.

## 16. Update Center gate — BLOCKER

- [ ] PASS — Fully updated system reports correctly.
- [ ] PASS — Update check works as an unprivileged desktop user.
- [ ] PASS — User update checks do not fail because of a root-owned `/var/cache` manifest cache.
- [ ] PASS — Real MechOS update can be installed.
- [ ] PASS — Reboot after update succeeds.
- [ ] PASS — MechScope still starts after update.
- [ ] PASS — Creator Mode still starts after update.
- [ ] PASS — Desktop and Start/Application menu mode shortcuts still work after update.
- [ ] PASS — Custom MechOS files are not unexpectedly overwritten.
- [ ] PASS — Failed/interrupted update produces a recoverable state.
- [ ] PASS — Package database repair path works.

## 17. Recovery gate — BLOCKER

- [ ] PASS — Recovery Center opens.
- [ ] PASS — Boot repair path works on a controlled test case.
- [ ] PASS — Package repair path works.
- [ ] PASS — Update repair path works.
- [ ] PASS — Desktop fallback works.
- [ ] PASS — Broken MechScope can be recovered.
- [ ] PASS — User files are preserved where promised.
- [ ] PASS — Recovery never selects or wipes the wrong disk without explicit confirmation.

## 18. Suspend / resume gate

- [ ] PASS — Suspend succeeds.
- [ ] PASS — Wake succeeds.
- [ ] PASS — GPU recovers.
- [ ] PASS — Wi-Fi recovers.
- [ ] PASS — Bluetooth recovers.
- [ ] PASS — Audio recovers.
- [ ] PASS — MechScope remains usable.

## 19. Storage gate

- [ ] PASS — NVMe installation / use.
- [ ] PASS — SATA SSD if available.
- [ ] PASS — USB storage mount.
- [ ] PASS — Secondary Steam library drive.
- [ ] PASS — NTFS/Windows game drive handling if supported.
- [ ] PASS — Low disk space is handled safely.
- [ ] PASS — Nearly-full root filesystem does not corrupt update/install state.

## 20. Installer safety gate — BLOCKER

Use disposable test disks only.

- [ ] PASS — Multiple-disk system tested.
- [ ] PASS — Existing Windows disk detected without accidental erasure.
- [ ] PASS — Existing Linux disk detected without accidental erasure.
- [ ] PASS — Existing EFI partition case tested.
- [ ] PASS — Blank/unformatted disk tested.
- [ ] PASS — Cancel installation path works.
- [ ] PASS — Re-running installer after cancel works.
- [ ] PASS — Destructive action always requires explicit target/confirmation.

## 21. GUI reference and live-behavior audit

Capture screenshots from the actual built/installed OS and compare with the approved visual design. For live surfaces such as Creator Mode, also verify that displayed values and controls come from real runtime state rather than screenshot/demo data.

| Surface | Screenshot captured | Matches approved design | Live/runtime behavior verified | Notes |
|---|---|---|---|---|
| Boot splash | [ ] | [ ] | [ ] | |
| Installer | [ ] | [ ] | [ ] | |
| OOBE | [ ] | [ ] | [ ] | |
| MechScope | [ ] | [ ] | [ ] | |
| Creator Mode | [ ] | [ ] | [ ] | Must be live native UI, not screenshot raster |
| Performance Center | [ ] | [ ] | [ ] | |
| Update Center | [ ] | [ ] | [ ] | |
| Recovery | [ ] | [ ] | [ ] | |
| Quick Actions | [ ] | [ ] | [ ] | |

## 22. Release hygiene gate — BLOCKER

- [ ] PASS — No test/default passwords are published unintentionally.
- [ ] PASS — No API keys.
- [ ] PASS — No GitHub tokens.
- [ ] PASS — No secrets in shell history, logs or config.
- [ ] PASS — No build-only `/workspace/...` paths are required at runtime.
- [ ] PASS — No debug usernames or machine-specific paths.
- [ ] PASS — Temporary build files are excluded.
- [ ] PASS — Debug logging is not excessive.
- [ ] PASS — Version is correct everywhere.
- [ ] PASS — Release notes written.
- [ ] PASS — Known issues documented.
- [ ] PASS — SHA256 published with ISO.
- [ ] PASS — Installation instructions published.
- [ ] PASS — Recovery instructions published.
- [ ] PASS — Game compatibility wording does not promise unsupported anti-cheat compatibility.

## 23. Hotfix 2 / Build 110 regression gate — BLOCKER

Use this gate for the Hotfix 2 clean-build line containing the Build 104–110 fixes. If a later build supersedes Build 110, run the same checks against that release-candidate ISO.

### Account creation / first boot

- [ ] PASS — Fresh VM install reaches OOBE automatically.
- [ ] PASS — Fresh physical install reaches OOBE automatically.
- [ ] PASS — Account creation succeeds without manual terminal repair.
- [ ] PASS — Permanent account can log in after OOBE.
- [ ] PASS — Permanent account can use `sudo` with its own password.
- [ ] PASS — MechScope/Creator cannot bypass unfinished OOBE.
- [ ] PASS — OOBE completion survives reboot and does not loop.

### Desktop + Start/Application menu shortcuts

- [ ] PASS — **Return to MechScope** appears in the Start/Application menu.
- [ ] PASS — **MechOS Creator Mode** appears in the Start/Application menu.
- [ ] PASS — **Return to MechScope** appears on the desktop where the MechOS desktop layout expects it.
- [ ] PASS — **Creator Mode** appears on the desktop where the MechOS desktop layout expects it.
- [ ] PASS — All four menu/desktop launch paths call the shared mode launcher and perform the intended action.
- [ ] PASS — Existing user desktop shortcut copies are repaired by Hotfix 2 where applicable.

### VM mode shortcuts

- [ ] PASS — VM **Return to MechScope** desktop shortcut works.
- [ ] PASS — VM **Creator Mode** desktop shortcut works.
- [ ] PASS — VM Start/Application menu MechScope entry works.
- [ ] PASS — VM Start/Application menu Creator entry works.
- [ ] PASS — VM MechScope uses Plasma as compositor and does not require Gamescope.
- [ ] PASS — VM Creator Mode uses the VM-safe runtime path.
- [ ] PASS — VM direct-launch fallback works if the normal user-service route fails.

### Creator Mode live-dashboard regression

- [ ] PASS — Creator Mode is native/live and not the old screenshot shell.
- [ ] PASS — CPU/RAM/disk/GPU data is real runtime data.
- [ ] PASS — Real project scanning works.
- [ ] PASS — New Project action works or safely enters the real project workflow.
- [ ] PASS — Open Project chooser works and identifies supported project types.
- [ ] PASS — Project Manager works.
- [ ] PASS — Asset Browser works.
- [ ] PASS — MechClip AI shortcut works.
- [ ] PASS — Creator Settings works.
- [ ] PASS — Back to MechScope works.

### Update / persistence regression

- [ ] PASS — Update Center can check manifests as a normal user.
- [ ] PASS — Reboot preserves OOBE completion.
- [ ] PASS — Reboot preserves working desktop/menu shortcuts.
- [ ] PASS — Reboot preserves MechScope ↔ Creator switching.

---

# Hard GO / NO-GO gate

A public v0.3.0 release is **GO** only when all of these are PASS:

- [ ] Successful ISO build + checksum
- [ ] Live boot
- [ ] Clean installation
- [ ] OOBE/account creation
- [ ] Permanent account administrator/sudo validation
- [ ] Installed MechScope
- [ ] Desktop / Creator / Gaming mode switching
- [ ] Desktop + Start/Application menu MechScope/Creator shortcuts
- [ ] VM shortcut/mode runtime validation when VM support is claimed
- [ ] Reboot persistence
- [ ] At least one physical-hardware certification
- [ ] Vulkan / real GPU validation
- [ ] Steam / Proton game test suite
- [ ] Creator Mode live native dashboard + advertised features
- [ ] Update Center
- [ ] Recovery
- [ ] Installer safety
- [ ] Hotfix 2 / Build 110 regression gate for that release line
- [ ] Release hygiene

## Final decision

- [ ] **GO — release approved**
- [ ] **NO-GO — release blocked**

Blocking failures:

```text

```

Known non-blocking issues accepted for this release:

```text

```

Approved by: ____________________

Date: ____________________
