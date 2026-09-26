# MechOS Update Infrastructure Freeze

Starting after **MechOS 0.3.1-hotfix.5**, ordinary MechOS hotfixes are **payload-only**.

The Update Center is infrastructure, not application payload. A normal feature, hardware, UI, compatibility, GPU, MechScope, controller, store, power, network, or recovery hotfix must not contain or change:

- `/usr/local/bin/mechos-update-helper`
- `/usr/local/bin/mechos-update-center`
- `/usr/local/bin/mechos-reboot`
- `/usr/local/libexec/mechos-update-*`
- `/usr/local/share/mechos/update-engine/`
- `/usr/local/share/mechos/update-recovery/`
- `/etc/mechos/update-signing-public.pem`
- the Update Center self-repair systemd service

## Normal hotfix build contract

Every `0.3.1-hotfix.6+` builder must:

1. start from the desired cumulative OS payload;
2. apply only the feature/hardware fixes for that release;
3. run `scripts/mechos-strip-updater-from-stage-v1.sh "$STAGE"`;
4. build the signed archive;
5. run `scripts/validate-payload-only-hotfix-v1.sh "$BUNDLE"`.

Repo-wide CI rejects future 0.3.1 hotfix builders that do not contain both enforcement steps.

## Updating Update Center itself

Updater changes are no longer bundled with normal OS hotfixes. They require a deliberately separate updater-maintenance release/process with its own validation and hardware test gate. A normal hotfix publisher must not watch updater source files.

This freeze exists specifically to prevent a MechOS feature hotfix from breaking the mechanism needed to install the next fix.


## Restart infrastructure

Restart/shutdown authority is also frozen platform infrastructure. Normal hotfixes must not contain `/usr/local/bin/mechos-reboot` or `/usr/local/libexec/mechos-powerctl-v1`. Existing affected systems use the separate restart-maintenance repair path; normal OS payloads cannot replace it.
