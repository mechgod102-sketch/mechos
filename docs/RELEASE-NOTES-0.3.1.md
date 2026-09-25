# MechOS 0.3.1 — Phase 1 release notes

The 0.3.1 rollout starts with a cumulative Update Center release built on top of the complete 0.3.0 Hotfix 35 payload.

## Included in Phase 1

- carries forward all fixes and features from MechOS 0.3.0 Hotfix 35
- adds the official 16-image MechOS 0.3.1 desktop wallpaper collection
- installs the collection into KDE Plasma as individually selectable MechOS wallpapers
- updates the packaged MechOS default wallpaper asset to wallpaper 01
- preserves an existing user's selected Plasma wallpaper instead of forcibly replacing it
- stages the wallpaper payload under MechOS-owned OTA paths and installs it through a guarded installed-system service
- keeps the Live ISO update path disabled; this release is for installed MechOS systems through Update Center

## Rollout model

This is the first cumulative 0.3.1 roadmap slice. Remaining 0.3.1 roadmap items will be added through reviewed cumulative 0.3.1 updates after their implementation and validation gates pass.

## Update Center behavior

Installed systems on 0.3.0 Hotfix 35 or an earlier compatible cumulative build will see **MechOS v0.3.1 — Phase 1** in the Stable channel once the publication workflow succeeds. The bundle is SHA-256 verified before installation and requires a reboot so the post-update wallpaper installation service can complete before the desktop session starts.
