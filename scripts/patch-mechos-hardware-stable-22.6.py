#!/usr/bin/env python3
# MECHOS_HARDWARE_STABLE_PATCHER_V22_6
from __future__ import annotations

import re
import sys
from pathlib import Path

MARKER = "# MECHOS_HARDWARE_STABLE_22_6_INTEGRATION"
SEED_CALL = "bash /workspace/scripts/mechos-hardware-stable-seed-v22.sh final"
ACCOUNT_CALL = "bash /workspace/scripts/mechos-postinstall-account-hotfix.sh final"


def patch(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        if SEED_CALL not in text:
            raise SystemExit("hardware stable marker exists without seed integration call")
        if ACCOUNT_CALL not in text:
            raise SystemExit("hardware stable marker exists without postinstall account hotfix call")
        return

    matches = list(re.finditer(r"(?m)^[ \t]*(?:sudo[ \t]+)?mkarchiso\b[^\n]*$", text))
    if not matches:
        raise SystemExit("mkarchiso invocation not found")

    match = matches[-1]
    block = (
        f"{MARKER}\n"
        "# Seed the verified current stable cumulative payload only after the\n"
        "# normal final install-payload synchronization. Then apply the account\n"
        "# creation repair as the absolute-final firstboot/OOBE authority so no\n"
        "# older integration layer can relock or bypass the setup account.\n"
        f"{SEED_CALL}\n"
        f"{ACCOUNT_CALL}\n\n"
    )
    text = text[: match.start()] + block + text[match.start() :]
    path.write_text(text, encoding="utf-8")

    check = path.read_text(encoding="utf-8")
    if check.count(MARKER) != 1:
        raise SystemExit("hardware stable integration marker was not inserted exactly once")
    if check.count(SEED_CALL) != 1:
        raise SystemExit("hardware stable seed was not inserted exactly once")
    if check.count(ACCOUNT_CALL) != 1:
        raise SystemExit("postinstall account hotfix was not inserted exactly once")
    if check.index(SEED_CALL) > check.index(ACCOUNT_CALL):
        raise SystemExit("postinstall account hotfix must run after the hardware payload seed")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-mechos-hardware-stable-22.6.py BUILD_SCRIPT")
    path = Path(sys.argv[1])
    if not path.is_file():
        raise SystemExit(f"build script not found: {path}")
    patch(path)


if __name__ == "__main__":
    main()
