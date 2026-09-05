# MechOS VM lifecycle test

The automated VM lifecycle test runs only after `Build MechOS Arch ISO` finishes successfully and produces an ISO artifact.

It uses the exact ISO and checksum from that build, a disposable 64 GB QCOW2 system disk, UEFI/OVMF firmware, QEMU, VNC input automation, and an offline libguestfs audit.

## Runtime coverage

1. Live UEFI boot and visible/non-black graphical progress.
2. Live Installer appears.
3. Clean Install card and Install Now hotspot receive real VM mouse input.
4. Clean installation proceeds on the disposable VM disk.
5. Automatic reboot/handoff reaches installed first boot.
6. OOBE Welcome -> Account -> Region -> Device -> Review -> Finish is exercised with a temporary test owner account.
7. Post-install graphical session appears.
8. Update Center launches and Check Again is clicked.
9. Recovery Center launches. Destructive repair/rollback/reinstall actions are not executed on the lifecycle disk; their callback wiring remains a source-validation requirement.
10. Quick Actions launches. Network/power toggles that could intentionally disconnect or terminate the test are not changed; their callback wiring remains source validated.
11. Creator Mode launches; Creator Store and Creator Settings are opened through their real GUI buttons.
12. MechScope launches through the VM mode router; Unified Store is opened from MechScope.
13. The installed `mechos-reboot` helper is executed and the VM must visibly reboot and return to a graphical session.
14. Update Center must still launch after that reboot.
15. Offline installed-disk audit verifies the permanent account, OOBE-complete/install markers, removal of `mechos-setup`, required launchers, and absence of MechScope/mode-launch error markers in generated state logs.

Every major phase writes screenshot/log evidence to the `MechOS-VM-lifecycle-<build>` Actions artifact. A missing, black, blank, stuck, non-transitioning, or failed required phase fails the workflow.
