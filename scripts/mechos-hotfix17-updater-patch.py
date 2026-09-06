#!/usr/bin/env python3
# MECHOS_HOTFIX17_UPDATER_PATCH
from pathlib import Path
import sys


def patch_helper(path: Path) -> None:
    text = path.read_text(encoding='utf-8')
    marker = '# MECHOS_HOTFIX17_HELPER_WARNING_FIX'
    if marker not in text:
        old = '  if ! tar --zstd -xpf "$bundle" -C "$stage"; then rm -rf "$work"; return 16; fi\n'
        new = marker + '\n  if ! tar --warning=no-timestamp --zstd -xpf "$bundle" -C "$stage"; then rm -rf "$work"; return 16; fi\n'
        if old not in text:
            raise SystemExit('update helper extraction anchor missing')
        text = text.replace(old, new, 1)
    path.write_text(text, encoding='utf-8')


def patch_center(path: Path) -> None:
    text = path.read_text(encoding='utf-8')
    marker = '# MECHOS_HOTFIX17_FAILURE_STATE_FIX'
    if marker in text:
        compile(text, str(path), 'exec')
        return

    # A stale reboot-required flag must not make a newer available release look
    # as though it already installed successfully.
    old_status = '''        if reboot:\n            self.status_label.setText("Restart required")\n            self.details_label.setText("Updates are installed. Restart MechOS to finish applying them.")\n        elif available:\n'''
    new_status = '''        if reboot and not available:\n            self.status_label.setText("Restart required")\n            self.details_label.setText("Updates are installed. Restart MechOS to finish applying them.")\n        elif available:\n'''
    if old_status not in text:
        raise SystemExit('Update Center status-state anchor missing')
    text = text.replace(old_status, new_status, 1)

    old_failure = '''        if code != 0:\n            self.status_label.setText(f"{mode.capitalize()} failed")\n            QMessageBox.critical(\n                self,\n                "MechOS Update Center",\n                f"{mode.capitalize()} failed with exit code {code}.\\n\\nLog: {LOG}",\n            )\n            return\n'''
    new_failure = '''        # MECHOS_HOTFIX17_FAILURE_STATE_FIX\n        if code != 0:\n            self.status_label.setText(f"{mode.capitalize()} failed")\n            if mode == "install":\n                self.details_label.setText(\n                    "The update did not finish. Nothing should be treated as successfully installed yet. "\n                    "Review the output, correct the reported problem, then retry Install Updates."\n                )\n                self.install_button.setEnabled(True)\n            else:\n                self.details_label.setText("The update action did not complete. Review the output and retry.")\n            QMessageBox.critical(\n                self,\n                "MechOS Update Center",\n                f"{mode.capitalize()} failed with exit code {code}.\\n\\nLog: {LOG}",\n            )\n            return\n'''
    if old_failure not in text:
        raise SystemExit('Update Center failure-state anchor missing')
    text = text.replace(old_failure, new_failure, 1)
    compile(text, str(path), 'exec')
    path.write_text(text, encoding='utf-8')


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit('usage: mechos-hotfix17-updater-patch.py {helper|center} PATH')
    kind, raw = sys.argv[1], sys.argv[2]
    path = Path(raw)
    if not path.is_file():
        raise SystemExit(f'missing target: {path}')
    if kind == 'helper':
        patch_helper(path)
    elif kind == 'center':
        patch_center(path)
    else:
        raise SystemExit(f'unknown patch kind: {kind}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
