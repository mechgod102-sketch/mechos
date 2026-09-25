# MechOS 0.3.1 Hotfix 5

Hotfix 5 fixes two hardware-test regressions found after the 0.3.1 release.

## GT 730 / legacy NVIDIA MechScope startup

The legacy-GPU session behavior is now part of the source-owned MechScope session itself rather than depending on the old Hotfix 1 one-time patch marker.

- detects the loaded NVIDIA kernel driver before configuring the session
- enables proprietary NVIDIA GBM variables only when the active driver is actually `nvidia`
- clears proprietary NVIDIA variables when the active driver is `nouveau`
- preserves the Intel UMA integration from Hotfix 36
- performs a Vulkan capability preflight before forcing Gamescope
- when Vulkan is unavailable or fails, MechScope starts through the supervised Plasma fallback instead of failing to open
- logs GPU name and loaded kernel driver for hardware diagnosis
- treats GeForce GT 730 as a mixed-generation product family rather than assuming one legacy proprietary branch

Because the corrected session is now copied directly into every cumulative bundle, a later update can no longer restore the unpatched session while leaving the old Hotfix 1 marker behind.

## Update Center health-first behavior

Update Center no longer interprets every self-repair warning as a missing helper.

It now:

1. runs the helper's local self-test first,
2. uses the helper immediately when that self-test succeeds,
3. invokes privileged self-repair only when helper health actually fails,
4. reruns status once after repair,
5. reports feed/network/signature failures separately from helper failures.

Hotfix 5 is delivered through a new A/B engine slot and does not replace the protected v38 public launchers.
