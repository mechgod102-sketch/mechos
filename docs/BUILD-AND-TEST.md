# Building and testing MechOS 0.3.0 Alpha

## Local build

1. Use a Linux host with Docker and at least 45 GiB free; 70 GiB is recommended.
2. Run `./scripts/setup-build-host.sh`.
3. Run `./scripts/validate-project.sh`.
4. Run `./build-iso.sh`.
5. Verify `out/MechOS-Arch-Creator-x86_64.iso.sha256`.
6. Test the ISO in a virtual machine before writing it to a USB drive.

The Docker build uses `archlinux:latest`, installs ArchISO, stages the MechOS overlay and runs `mkarchiso`.

## Virtual-machine smoke test

`./scripts/test-iso-qemu.sh` starts the ISO with QEMU when QEMU is installed. Test on a virtual disk that contains no important data.

Verify:

- the live ISO reaches KDE Plasma;
- the MechOS Setup Center opens once;
- closing Setup Center leaves a usable desktop;
- Archinstall starts and does not preselect a disk;
- installation completes on a blank virtual disk;
- the installed system does not retain the live `mechos` account configuration;
- SDDM starts and the installed user is selected;
- MechScope falls back to Plasma if Steam or Gamescope is unavailable;
- Desktop, Creator and Gaming mode switching works;
- update, recovery, performance and post-install tools open;
- AMD/Intel Vulkan works, or NVIDIA setup completes without blocking first boot;
- the generated ISO matches its SHA-256 file.

Static validation catches source and configuration mistakes, but only a VM installation can validate partitioning, bootloader, display-manager and graphics behavior.

## Hotfix 20 regression pass

After installing MechOS v0.3.0 Hotfix 20, complete `docs/HOTFIX-20-REGRESSION-TEST.md` on both a VM and at least one physical-hardware system. This pass specifically covers the recovered updater, root-directory permission safety, single-window navigation, Creator Mode, physical-hardware MechScope, Unified Store, Update/Recovery/Performance Centers, restart behavior, and cold-boot persistence.

Any regression that makes `/` non-traversable, hides `/usr/bin`, removes an Update Center helper, prevents MechScope from opening, or breaks boot is a release blocker.

## Release candidate certification

A successful build and VM smoke test are not enough for a public release. For each v0.3.0 release candidate, copy or reset `docs/RELEASE-CERTIFICATION-v0.3.0.md`, record the RC/build ID and commit SHA, and complete every BLOCKER section.

The public release is **NO-GO** until the hard gate passes, including:

- successful ISO build and checksum;
- Live boot;
- clean installation;
- OOBE and `mechscope.desktop` handoff;
- installed MechScope and mode switching;
- at least one physical-hardware certification;
- real GPU/Vulkan verification;
- Steam/Proton game tests;
- Creator Mode advertised features;
- Update Center and Recovery;
- installer safety tests;
- release hygiene and known-issues review.

Do not use VirtualBox frame rate as a gaming-performance certification result. Virtual machines are for boot, install, UI, fallback and basic runtime testing; gaming performance must be verified on physical hardware.
