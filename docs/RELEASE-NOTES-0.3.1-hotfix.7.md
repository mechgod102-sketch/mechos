# MechOS 0.3.1 Hotfix 7

Hotfix 7 hardens Creator Mode against a Qt/PyQt event-loop abort observed as `SIGABRT` from `python3 /usr/local/bin/mechos-creator-mode.real`.

## Failure pattern

The Creator dashboard had repeating QTimers for metrics, installed-app scans, project scans and update status, plus a startup `QTimer.singleShot`. Those Qt signals called Python callbacks directly. If an unexpected Python exception escaped a callback, Qt/PyQt could terminate the GUI process from the event loop instead of leaving Creator Mode running.

The update-status path was especially exposed because it also created and replaced a `QProcess` connected directly to Python slots.

## Fix

- every background timer enters a guarded callback boundary
- exceptions are written to `~/.local/state/mechos/creator-mode-v27.log`
- the startup update check is a page-owned single-shot QTimer
- QProcess output, finish and error callbacks are guarded
- failed/non-running update QProcess objects are cleared and scheduled for deletion
- completed update QProcess objects are cleared safely
- Creator Mode's user service uses bounded `Restart=on-failure` so one transient Qt abort does not leave the mode dead
- intentional clean mode transitions are not restarted

This remains a payload-only hotfix. Update Center and frozen restart/power infrastructure are not part of the archive.
