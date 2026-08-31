#!/usr/bin/env python3
from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

MARKER_EARLY = "# MECHOS_CURRENT_INTEGRATION_EARLY"
MARKER_LATE = "# MECHOS_CURRENT_INTEGRATION_LATE"
CALL_EARLY = f"""{MARKER_EARLY}
# Apply the cumulative MechOS runtime/installer integration.
bash /workspace/scripts/mechos-current-integration.sh early

"""
CALL_LATE = f"""{MARKER_LATE}
# Re-apply after all legacy builder blocks so current fixes win.
bash /workspace/scripts/mechos-current-integration.sh final
# Apply boot-to-MechScope performance fixes after the installed rootfs archive
# exists so FastBoot can patch both the Live image and installed-system payload.
bash /workspace/scripts/mechos-fastboot-integration.sh final

"""


def fail(message: str) -> None:
    raise SystemExit(f"[MechOS current patcher] ERROR: {message}")


def strip_legacy_patch_calls(text: str) -> str:
    # Remove only the small injected call blocks from old v0.2.1/v0.2.2 patchers.
    patterns = [
        r"\n# MECHOS_V0_2_1_REPAIR_EARLY\n.*?bash /workspace/scripts/mechos-v0\.2\.1-runtime-repair\.sh early\n\n",
        r"\n# MECHOS_V0_2_1_REPAIR_LATE\n.*?bash /workspace/scripts/mechos-v0\.2\.1-runtime-repair\.sh final\n\n",
        r"\n# MECHOS_V0_2_2_REPAIR_EARLY\n.*?bash /workspace/scripts/mechos-v0\.2\.2-runtime-repair\.sh early\n\n",
        r"\n# MECHOS_V0_2_2_REPAIR_LATE\n.*?bash /workspace/scripts/mechos-v0\.2\.2-runtime-repair\.sh final\n\n",
        r"\n# MECHOS_CURRENT_INTEGRATION_EARLY\n.*?bash /workspace/scripts/mechos-current-integration\.sh early\n\n",
        r"\n# MECHOS_CURRENT_INTEGRATION_LATE\n.*?bash /workspace/scripts/mechos-current-integration\.sh final\n(?:# Apply boot-to-MechScope performance fixes.*\n# exists so FastBoot can patch both the Live image and installed-system payload\.\n)?(?:bash /workspace/scripts/mechos-fastboot-integration\.sh final\n)?\n",
    ]
    for pattern in patterns:
        text = re.sub(pattern, "\n", text, flags=re.S)
    return text


def main() -> None:
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "scripts/build-mechos-archiso.sh")
    if not target.is_file():
        fail(f"builder not found: {target}")

    text = target.read_text(encoding="utf-8")
    if not text.startswith("#!"):
        fail("target does not look like a shell builder")

    backup = target.with_suffix(target.suffix + ".pre-current-integration.bak")
    if not backup.exists():
        shutil.copy2(target, backup)

    text = strip_legacy_patch_calls(text)

    installer_patterns = [
        r'(?m)^cat > /workspace/archlive/airootfs/usr/local/bin/mechos-install << ["\']?EOF["\']?\s*$',
        r'(?m)^cat > .*?/usr/local/bin/mechos-install << ["\']?EOF["\']?\s*$',
    ]
    match = None
    for pattern in installer_patterns:
        match = re.search(pattern, text)
        if match:
            break
    if not match:
        fail("could not locate mechos-install heredoc; refusing a blind patch")

    text = text[:match.start()] + CALL_EARLY + text[match.start():]

    mk_matches = list(re.finditer(r'(?m)^(?!\s*#).*\bmkarchiso\b.*$', text))
    if not mk_matches:
        fail("could not locate mkarchiso; refusing a blind patch")
    match = mk_matches[-1]
    text = text[:match.start()] + CALL_LATE + text[match.start():]

    target.write_text(text, encoding="utf-8")
    print(f"[MechOS current patcher] cumulative integration applied to {target}")


if __name__ == "__main__":
    main()
