# MechOS 0.3.1 Hotfix 4

Hotfix 4 improves package refresh reliability and makes Update Center report partial success correctly.

## Update result separation

A signed MechOS OTA and the optional Arch/Flatpak refresh are now reported as separate operations.

After an install, the engine emits explicit machine-readable results for:

- MechOS core update
- Arch/pacman refresh
- Flatpak refresh
- whether pacman permissions were automatically repaired
- whether any post-update warnings remain

If MechOS installs successfully but pacman fails, Update Center now says that the MechOS update succeeded and the package refresh needs attention. It no longer tells the user to reinstall the hotfix.

## Pacman permission recovery

For the specific pacman 7 failure where a temporary path under `/var/lib/pacman/sync/download-*` cannot create a database `.part` file because of permission denial, the engine:

1. removes only stale `download-*` directories under the pacman sync database directory,
2. restores the pacman database and sync directories to root ownership and mode 0755,
3. retries `pacman -Syu --noconfirm` once.

Other pacman failures, such as mirror/network/package errors, are not altered or hidden.

## A/B isolation

Hotfix 4 is delivered as a new `0.3.1-hotfix.4` Update Engine slot. The protected v38 public Update Center/helper launchers are not replaced.
