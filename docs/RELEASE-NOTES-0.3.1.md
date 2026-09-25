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

## Release integrity gate

The existing Update Center verifies the cumulative bundle SHA-256 and applies it transactionally with rollback protection. The 0.3.1 roadmap also calls for signed manifests. A real update signing public key/private-key workflow has not yet been provisioned in the repository, so the full Stable release must not be certified as satisfying that signing requirement until the signing key is configured. A private key must never be committed to the repository.

## Update Center

Once the release integrity gate and validation workflow pass, the publisher builds `MechOS-0.3.1-update.tar.zst`, verifies its checksum, and moves the Stable channel from `0.3.0-hotfix.35` to `0.3.1`.
