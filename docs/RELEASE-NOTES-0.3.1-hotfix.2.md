# MechOS 0.3.1 Hotfix 2

Hotfix 2 adds Update Center self-repair on top of the cumulative 0.3.1 Hotfix 1 release.

## Self-repair

- stores trusted local rescue copies of the signed v37 update helper
- stores a trusted Update Center launcher and backend
- stores the reboot helper
- stores the pinned MechOS update-signing public key
- verifies updater health at boot before the display manager starts
- restores missing or invalid helper/launcher/backend/reboot files
- restores lost executable permissions
- restores a missing signing public key from the pinned local copy
- refuses to silently replace a different valid signing key
- allows Update Center to invoke the same repair path with PolicyKit if its preflight fails
- runs repair before OTA transaction postflight, preventing missing updater components from causing a valid update to roll back

Hotfix 2 is cumulative and retains Hotfix 1 legacy GPU compatibility and all MechOS 0.3.1 functionality.
