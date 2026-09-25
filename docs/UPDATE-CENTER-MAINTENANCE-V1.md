# Update Center Maintenance v1

This is a one-time repair path for systems whose Update Center infrastructure was damaged during the 0.3.1 hotfix series.

It is **not a MechOS hotfix** and does not change `/etc/mechos/release`.

The maintenance tool:

- uses Python/urllib instead of curl
- downloads the frozen updater infrastructure from the MechOS repository
- validates shell/Python syntax and expected source markers
- pins the MechOS update-signing public-key fingerprint
- refuses to silently replace a mismatched installed signing key
- backs up the existing updater infrastructure
- creates and validates the independent `infrastructure-v1` engine slot
- restores the small frozen public helper and Update Center launchers
- restores independent recovery copies
- atomically activates the frozen engine slot
- runs local self-repair and helper self-test
- performs a final remote status check separately

Normal MechOS hotfixes remain payload-only and are forbidden from updating this infrastructure.
