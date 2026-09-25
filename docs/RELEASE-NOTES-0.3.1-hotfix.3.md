# MechOS 0.3.1 Hotfix 3

Hotfix 3 changes the updater architecture so ordinary hotfixes cannot break the Update Center that is installing them.

## A/B Update Engine

- public `mechos-update-helper` and `mechos-update-center` become small stable launchers
- updater implementation files live in versioned engine slots
- a new slot is fully validated before activation
- activation uses an atomic `current` symlink switch
- the old active slot is retained as `previous`
- self-repair can fall back from a damaged `current` slot to `previous`
- transaction rollback also restores the previous engine link
- cumulative bundles may still contain bootstrap launchers for old systems, but transaction v15 does not overwrite a healthy v38 launcher

## Hotfix isolation policy

Ordinary feature hotfixes should update MechOS components, not the active updater. Updating the updater itself now requires adding a new engine slot. If a release contains no slot matching that release version, the active updater engine does not change.

This is cumulative on Hotfix 2 and retains legacy GPU integration, signed manifests, downgrade protection, and Update Center self-repair.
