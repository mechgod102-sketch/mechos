# MechOS 0.3.1 release candidate

MechOS 0.3.1 is a cumulative Update Center release based on the complete 0.3.0 Hotfix 35 payload. The release branch now carries an installable v1 component for every 0.3.1 roadmap section instead of publishing only the wallpaper slice.

## Included

- MechScope boot path keeps the source-owned supervised Gamescope/Plasma fallback and branded loading asset
- MechOS Downloads & Updates hub with Update Center and Steam Downloads handoff
- cumulative OTA transaction, checksum verification, rollback protection and release commit machinery from the hardened 0.3.0 hotfix chain
- Companion Bridge v1 with authenticated fixed-action API, local-only default and TLS requirement before LAN pairing
- dedicated MechOS Network Setup status page with NetworkManager handoff
- MechBrowser launcher using the maintained Firefox backend and gaming-oriented quick links
- GPU compatibility diagnostics for detected GPU, Vulkan and installed driver packages
- per-game Efficiency, Balanced and Performance wrapper with GameMode support and automatic platform-profile restoration
- game crash history for MechOS-managed launches, including exit code, profile and elapsed time
- Creator Store catalog and handoff to Creator Mode, Bottles and Lutris
- Windows-game compatibility database with S.T.A.L.K.E.R. G.A.M.M.A. and Star Citizen intentionally marked Needs Setup/Testing until real hardware validation is complete
- USB4/Thunderbolt, HOTAS/joystick and controller diagnostics with system controller/Bluetooth settings handoff
- official 16-image MechOS 0.3.1 wallpaper collection packaged for KDE Plasma

## Compatibility labels

0.3.1 does not turn untested hardware or games into fake “Verified” entries. GPU, USB4, HOTAS, controller, Windows-creator-app, GAMMA and Star Citizen support remains conservatively labeled where physical-device or end-to-end game testing is still required.

## Release integrity

The Stable update channel now uses a provisioned public/private signing workflow. The private signing key remains stored outside the repository, the committed public key verifies signed manifests, and Update Center applies the cumulative bundle transactionally with SHA-256 verification and rollback protection.

Post-release hotfixes add downgrade protection and Update Center self-repair. Hotfix 2 keeps trusted local rescue copies of critical updater components and the pinned signing public key, restores missing updater files before transaction postflight, and refuses silent replacement of a mismatched signing key.

## Update Center

The base 0.3.1 publisher is retained for deliberate manual recovery only. Stable normally advances through signed `0.3.1-hotfix.x` releases so the base publisher cannot automatically overwrite a newer hotfix.
